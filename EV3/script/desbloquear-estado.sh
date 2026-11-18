#!/bin/bash
# ============================================
# Destraba el estado de Terraform de EP3 despues de cancelar un apply a medias.
# Un run cancelado mata a Terraform sin dejarlo cerrar, y eso deja dos cosas:
#   1. el candado del estado (archivo .tflock en S3 y fila en DynamoDB): el
#      siguiente apply falla con "Error acquiring the state lock" (412)
#   2. recursos que AWS alcanzo a crear pero que Terraform no anoto en el estado
#      (los que terminaban de crearse en los ultimos segundos o seguian en curso:
#      NAT Gateway, RDS, EKS, colas SQS, subredes publicas): el siguiente apply
#      intentaria crearlos de nuevo y fallaria con "already exists"
#
# Este script libera el candado y registra esos recursos con terraform import,
# esperando antes a que terminen de crearse. Cada recurso se revisa por separado:
# si ya esta en el estado se salta, y si no existe en AWS lo crea el siguiente
# apply. No crea ni borra nada en AWS.
#
# Solo debe correr cuando NO hay un apply en marcha: el candado de un apply vivo
# es legitimo. En el workflow lo garantiza el grupo de concurrencia.
#
#   ./EV3/script/desbloquear-estado.sh    # con terraform init ya hecho
# Requiere aws, terraform y jq.
# ============================================
set -euo pipefail

EV3_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$EV3_DIR/infra/freshbox-ep3"
NAME=freshbox
CFG="$TF_DIR/.terraform/terraform.tfstate"

for c in aws terraform jq; do
  command -v "$c" > /dev/null || { echo "Falta $c en el PATH"; exit 1; }
done
[ -f "$CFG" ] || { echo "Falta terraform init en $TF_DIR"; exit 1; }
cd "$TF_DIR"

# create_eks debe valer lo mismo que en el apply cancelado, para que
# aws_eks_cluster.main[0] exista en la configuracion al importarlo.
export TF_VAR_create_eks="${TF_VAR_create_eks:-true}"
export TF_INPUT=0

BUCKET="$(jq -r '.backend.config.bucket // empty' "$CFG")"
KEY="$(jq -r '.backend.config.key // empty' "$CFG")"
TABLE="$(jq -r '.backend.config.dynamodb_table // empty' "$CFG")"
REGION="$(jq -r '.backend.config.region // empty' "$CFG")"
[ -n "$BUCKET" ] && [ -n "$KEY" ] || { echo "No se pudo leer el backend de $CFG"; exit 1; }
export AWS_DEFAULT_REGION="${REGION:-${AWS_REGION:-us-east-1}}"

TMP="$(mktemp)"
ESTADO="$(mktemp)"
trap 'rm -f "$TMP" "$ESTADO"' EXIT
KEY_JSON="{\"LockID\":{\"S\":\"$BUCKET/$KEY\"}}"
RESUMEN=""

nota() { # nota <linea>: la muestra y la suma al resumen del run
  echo "$1"
  RESUMEN="$RESUMEN$1"$'\n'
}

s3_lock_existe() { aws s3api head-object --bucket "$BUCKET" --key "$KEY.tflock" > /dev/null 2>&1; }

dynamo_lock_info() { # JSON de la fila de bloqueo, o nada si no hay
  [ -n "$TABLE" ] || return 0
  local info
  info="$(aws dynamodb get-item --table-name "$TABLE" --key "$KEY_JSON" \
    --query 'Item.Info.S' --output text 2> /dev/null || true)"
  [ "$info" = None ] || printf '%s' "$info"
}

# --- 1. Candado ---
echo "=== 1. Candado del estado: s3://$BUCKET/$KEY ==="
LOCK_ID=""
if s3_lock_existe; then
  aws s3api get-object --bucket "$BUCKET" --key "$KEY.tflock" "$TMP" > /dev/null
  LOCK_ID="$(jq -r '.ID // empty' "$TMP" 2> /dev/null || true)"
fi
INFO="$(dynamo_lock_info)"
if [ -z "$LOCK_ID" ] && [ -n "$INFO" ]; then
  LOCK_ID="$(printf '%s' "$INFO" | jq -r '.ID // empty' 2> /dev/null || true)"
fi

if [ -n "$LOCK_ID" ]; then
  echo "Candado encontrado: $LOCK_ID"
  terraform force-unlock -force "$LOCK_ID" || echo "force-unlock fallo: se borran los restos a mano"
  nota "- Candado $LOCK_ID liberado"
else
  nota "- No habia candado en el estado"
fi
# Restos que force-unlock no haya quitado (un candado sin ID legible, por ejemplo).
if s3_lock_existe; then
  aws s3api delete-object --bucket "$BUCKET" --key "$KEY.tflock" > /dev/null
  nota "- Se borro el .tflock que seguia en S3"
fi
if [ -n "$(dynamo_lock_info)" ]; then
  aws dynamodb delete-item --table-name "$TABLE" --key "$KEY_JSON"
  nota "- Se borro la fila de bloqueo que seguia en DynamoDB"
fi

# --- 2. Recursos creados en AWS que el estado no conoce ---
echo
echo "=== 2. Recursos que Terraform alcanzo a crear sin anotarlos ==="
terraform state list > "$ESTADO" 2> /dev/null || true
echo "El estado tiene $(wc -l < "$ESTADO") recursos"

aws_valor() { # aws_valor <comando aws ... --output text>: el valor, o vacio si no existe
  local v
  v="$("$@" 2> /dev/null || true)"
  [ "$v" = None ] || printf '%s' "$v"
}

esperar() { # esperar <descripcion> <aws ... wait ...>
  local que="$1"
  shift
  echo "  ... esperando que termine de crearse: $que"
  "$@" || { nota "- $que no llego a estar disponible: revisalo en la consola de AWS"; return 1; }
}

importar() { # importar <direccion de Terraform> <id en AWS>
  local direccion="$1" id="$2"
  if grep -qxF -- "$direccion" "$ESTADO"; then
    echo "  = $direccion ya esta en el estado"
    return 0
  fi
  if [ -z "$id" ]; then
    echo "  - $direccion no existe en AWS: lo crea el siguiente apply"
    return 0
  fi
  if terraform import -input=false "$direccion" "$id" > "$TMP" 2>&1; then
    nota "- Importado $direccion ($id)"
  else
    tail -n 8 "$TMP"
    nota "- No se pudo importar $direccion ($id): revisa el log del paso"
  fi
}

# Subredes publicas y su asociacion a la tabla de rutas (1a y 1b = indices 0 y 1).
i=0
for az in 1a 1b; do
  SUBNET="$(aws_valor aws ec2 describe-subnets --filters "Name=tag:Name,Values=$NAME-subnet-public-$az" \
    --query 'Subnets[0].SubnetId' --output text)"
  importar "aws_subnet.public[$i]" "$SUBNET"
  if [ -n "$SUBNET" ]; then
    RTB="$(aws_valor aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$SUBNET" \
      --query 'RouteTables[0].RouteTableId' --output text)"
    if [ -n "$RTB" ]; then
      importar "aws_route_table_association.public[$i]" "$SUBNET/$RTB"
    fi
  fi
  i=$((i + 1))
done

# Colas SQS: el id de importacion es la URL de la cola.
for par in "ordenes_dlq:ordenes-$NAME-dlq" "ordenes:ordenes-$NAME"; do
  URL="$(aws_valor aws sqs get-queue-url --queue-name "${par#*:}" --query QueueUrl --output text)"
  importar "aws_sqs_queue.${par%%:*}" "$URL"
done

# NAT Gateway, RDS y EKS tardan minutos: se espera a que terminen antes de
# importarlos, para que el siguiente apply no los encuentre "en creacion".
NAT="$(aws_valor aws ec2 describe-nat-gateways \
  --filter "Name=tag:Name,Values=$NAME-natgw" "Name=state,Values=pending,available" \
  --query 'NatGateways[0].NatGatewayId' --output text)"
if [ -n "$NAT" ] && ! grep -qxF -- aws_nat_gateway.nat "$ESTADO"; then
  esperar "NAT Gateway $NAT" aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT" || NAT=""
fi
importar aws_nat_gateway.nat "$NAT"

DB="$(aws_valor aws rds describe-db-instances --db-instance-identifier "$NAME-db" \
  --query 'DBInstances[0].DBInstanceIdentifier' --output text)"
if [ -n "$DB" ] && ! grep -qxF -- aws_db_instance.main "$ESTADO"; then
  esperar "RDS $DB (Multi-AZ, hasta 20 min)" aws rds wait db-instance-available --db-instance-identifier "$DB" || DB=""
fi
importar aws_db_instance.main "$DB"

CLUSTER="$(aws_valor aws eks describe-cluster --name "$NAME-cluster" --query cluster.name --output text)"
if [ -n "$CLUSTER" ] && ! grep -qxF -- 'aws_eks_cluster.main[0]' "$ESTADO"; then
  esperar "cluster EKS $CLUSTER (hasta 15 min)" aws eks wait cluster-active --name "$CLUSTER" || CLUSTER=""
fi
importar 'aws_eks_cluster.main[0]' "$CLUSTER"

echo
echo "=== Listo. Siguiente: accion plan del workflow y luego desplegar ==="
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### Estado de Terraform"; echo; printf '%s' "$RESUMEN"; } >> "$GITHUB_STEP_SUMMARY"
fi
