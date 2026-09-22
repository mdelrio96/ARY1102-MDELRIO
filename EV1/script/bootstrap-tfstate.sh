#!/bin/bash
# ============================================
# Crea el bucket S3 del estado de Terraform y la tabla DynamoDB de bloqueo si
# no existen. Idempotente: lo que ya esta, no se toca. El workflow de
# infraestructura lo ejecuta antes de cada "terraform init"; en local se corre
# igual, con las credenciales del lab.
#
# Ninguno de los dos puede ser un recurso de Terraform: el backend los necesita
# antes del init y, ademas, la SCP del Learner Lab deniega
# s3:GetBucketObjectLockConfiguration, que el proveedor consulta al leer buckets.
# Un reset del lab los borra junto con todo lo demas; este script los vuelve a
# crear y el siguiente apply parte con un estado vacio.
#
# Nombres y region se leen del bloque backend de main.tf (unica fuente). El
# sufijo del bucket es el ID de la cuenta del lab: si la cuenta cambio, el
# script se detiene y pide actualizar main.tf.
#
#   ./EV1/script/bootstrap-tfstate.sh    # desde cualquier directorio
# ============================================
set -euo pipefail

MAIN_TF="$(cd "$(dirname "$0")/../infra/freshbox-ep1" && pwd)/main.tf"

command -v aws > /dev/null || { echo "Falta aws en el PATH"; exit 1; }

backend_value() { # backend_value bucket -> valor de esa clave dentro de backend "s3" { ... }
  sed -n "/backend \"s3\" {/,/^[[:space:]]*}/ s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$MAIN_TF"
}
BUCKET="$(backend_value bucket)"
TABLE="$(backend_value dynamodb_table)"
REGION="$(backend_value region)"
if [ -z "$BUCKET" ] || [ -z "$TABLE" ] || [ -z "$REGION" ]; then
  echo "No se encontro bucket/dynamodb_table/region en el bloque backend de $MAIN_TF"
  exit 1
fi

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
if [ "${BUCKET##*-}" != "$ACCOUNT" ]; then
  echo "La cuenta del lab es $ACCOUNT pero main.tf apunta a $BUCKET."
  echo "Cambia el bucket del backend a ${BUCKET%-*}-$ACCOUNT y vuelve a ejecutar."
  exit 1
fi

# --- Bucket S3 del estado: versionado y sin acceso publico ---
if out="$(aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>&1)"; then
  echo "Bucket $BUCKET: ya existe."
elif grep -q "(404)" <<< "$out"; then
  echo "Bucket $BUCKET: no existe (lab reseteado o cuenta nueva); creando en $REGION..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" > /dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" > /dev/null
  fi
  aws s3api wait bucket-exists --bucket "$BUCKET" --region "$REGION"
  aws s3api put-bucket-versioning --bucket "$BUCKET" --region "$REGION" \
    --versioning-configuration Status=Enabled
  aws s3api put-public-access-block --bucket "$BUCKET" --region "$REGION" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  echo "Bucket $BUCKET: creado (versionado, acceso publico bloqueado)."
else
  echo "$out"
  echo "No se pudo consultar $BUCKET (403 = nombre en uso por otra cuenta o sin permisos)."
  exit 1
fi

# --- Tabla DynamoDB de bloqueo: clave de particion LockID (S), bajo demanda ---
if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" > /dev/null 2>&1; then
  echo "Tabla $TABLE: ya existe."
else
  echo "Tabla $TABLE: no existe; creando en $REGION..."
  aws dynamodb create-table --table-name "$TABLE" --region "$REGION" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST > /dev/null
  aws dynamodb wait table-exists --table-name "$TABLE" --region "$REGION"
  echo "Tabla $TABLE: creada."
fi

echo "Backend de Terraform listo: s3://$BUCKET + tabla $TABLE."
