#!/bin/bash
# ============================================
# Prueba de punta a punta de FreshBox EP3, siempre por API Gateway (la entrada
# unica de la app), igual que la usaria el sitio de S3:
#   1. CRUD de productos: GET, POST, PUT, DELETE, y la lista tras cada cambio
#   2. carrito: POST, GET (con el total) y su limpieza al final
#   3. orden: POST /api/orders -> SQS -> Process-Order -> tabla ordenes en RDS
# Crea un producto temporal y lo borra; la orden queda registrada en RDS.
#
#   ./EV3/script/probar-flujo.sh             # toma la URL de API Gateway de Terraform
#   ./EV3/script/probar-flujo.sh https://...  # o una URL explicita
# ============================================
set -euo pipefail

EV3_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$EV3_DIR/infra/freshbox-ep3"
NS=freshbox

for c in aws kubectl terraform curl; do
  command -v "$c" > /dev/null || { echo "Falta $c en el PATH"; exit 1; }
done

BASE="${1:-$(terraform -chdir="$TF_DIR" output -raw api_url)}"
BASE="${BASE%/}"
API="$BASE/api/products"
USUARIO="verif-$(date +%s)"

paso() { printf '\n--- %s\n' "$1"; }

# La API tarda unos minutos en responder: el ALB necesita targets sanos.
echo "=== Esperando que API Gateway responda por el ALB ($BASE) ==="
for i in $(seq 1 40); do
  curl -fsS --max-time 10 "$API" > /dev/null 2>&1 && break
  [ "$i" = 40 ] && { echo "API Gateway no respondio en 10 minutos"; exit 1; }
  echo "[$i] aun no responde..."
  sleep 15
done

# --- 1. CRUD de productos ---
paso "GET /api/products (get-products)"
LISTA="$(curl -fsS "$API")"
printf '%s...\n' "${LISTA:0:300}"
ID_BASE="$(printf '%s' "$LISTA" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | head -1)"
[ -n "$ID_BASE" ] || { echo "La lista no trae productos: revisa datos-iniciales.sql"; exit 1; }

paso "POST /api/products (create-product)"
CREADO="$(curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"nombre":"Prueba CRUD EP3","descripcion":"Registro temporal de la prueba","precio":1990,"stock":5,"categoria":"Prueba"}' "$API")"
echo "$CREADO"
ID="$(printf '%s' "$CREADO" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')"
[ -n "$ID" ] || { echo "No se obtuvo el id del producto creado"; exit 1; }

paso "PUT /api/products/$ID (update-product)"
curl -fsS -X PUT -H 'Content-Type: application/json' \
  -d '{"nombre":"Prueba CRUD EP3 (editado)","descripcion":"Registro temporal modificado","precio":2490,"stock":3,"categoria":"Prueba"}' "$API/$ID"
echo

# API Gateway expone las 8 rutas de la pauta y GET por id no es una de ellas:
# la lectura se verifica con la lista completa.
paso "GET /api/products (la lista trae el producto $ID editado)"
LISTA="$(curl -fsS "$API")"
[[ "$LISTA" == *"\"id\":$ID,\"nombre\":\"Prueba CRUD EP3 (editado)\""* ]] \
  || { echo "El producto $ID editado no aparece en la lista"; exit 1; }
echo "El producto $ID aparece con el nombre editado"

paso "DELETE /api/products/$ID (delete-product)"
curl -fsS -X DELETE "$API/$ID"
echo

paso "GET /api/products (la lista ya no trae el producto $ID)"
LISTA="$(curl -fsS "$API")"
if [[ "$LISTA" == *"\"id\":$ID,"* ]]; then
  echo "El producto $ID sigue existiendo"
  exit 1
fi
echo "El producto $ID ya no aparece"

# --- 2. Carrito (Lambda Cart + DynamoDB por VPC Endpoint) ---
paso "POST /api/cart (Lambda Cart)"
curl -fsS -X POST -H 'Content-Type: application/json' \
  -d "{\"userId\":\"$USUARIO\",\"productId\":\"$ID_BASE\",\"nombre\":\"Producto de prueba\",\"precio\":1000,\"cantidad\":2}" "$BASE/api/cart"
echo

paso "GET /api/cart?userId=$USUARIO (Lambda Cart)"
CARRITO="$(curl -fsS "$BASE/api/cart?userId=$USUARIO")"
echo "$CARRITO"
printf '%s' "$CARRITO" | grep -q '"cantidadItems":1' || { echo "El carrito no tiene el producto agregado"; exit 1; }

# --- 3. Orden (Create-Order -> SQS -> Process-Order -> RDS) ---
paso "POST /api/orders (Lambda Create-Order)"
ORDEN="$(curl -fsS -X POST -H 'Content-Type: application/json' -d "{\"userId\":\"$USUARIO\"}" "$BASE/api/orders")"
echo "$ORDEN"

# Process-Order corre en segundo plano desde la cola: se consulta RDS con un Job temporal.
paso "Verificando en RDS que la orden quedo procesada (Job verificar-orden)"
kubectl delete job verificar-orden -n "$NS" --ignore-not-found > /dev/null
JOB="$(mktemp)"
trap 'rm -f "$JOB"' EXIT
cat > "$JOB" <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: verificar-orden
  namespace: freshbox
  labels:
    app: verificar-orden
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: mysql-client
          image: mysql:8.0
          env:
            - name: DB_HOST
              valueFrom:
                configMapKeyRef: { name: freshbox-config, key: DB_HOST }
            - name: DB_NAME
              valueFrom:
                configMapKeyRef: { name: freshbox-config, key: DB_NAME }
            - name: DB_USER
              valueFrom:
                secretKeyRef: { name: freshbox-secret, key: DB_USER }
            - name: MYSQL_PWD
              valueFrom:
                secretKeyRef: { name: freshbox-secret, key: DB_PASS }
            - name: USUARIO
              value: "__USUARIO__"
          command:
            - sh
            - -c
            - |
              for i in $(seq 1 24); do
                N=$(mysql -h "$DB_HOST" -u "$DB_USER" -N -e "SELECT COUNT(*) FROM ordenes WHERE user_id='$USUARIO' AND estado='procesado'" "$DB_NAME")
                if [ "${N:-0}" -ge 1 ]; then
                  echo "Orden procesada en RDS para $USUARIO (intento $i)"
                  mysql -h "$DB_HOST" -u "$DB_USER" -e "SELECT id, user_id, total, estado, processed_at FROM ordenes WHERE user_id='$USUARIO'" "$DB_NAME"
                  exit 0
                fi
                sleep 5
              done
              echo "La orden de $USUARIO no aparecio en RDS en 2 minutos"
              exit 1
EOF
sed -i "s|__USUARIO__|$USUARIO|" "$JOB"
kubectl apply -f "$JOB" > /dev/null
if kubectl wait --for=condition=complete job/verificar-orden -n "$NS" --timeout=240s > /dev/null 2>&1; then
  kubectl logs job/verificar-orden -n "$NS"
else
  kubectl logs job/verificar-orden -n "$NS" --tail=40 || true
  echo "La orden no quedo registrada en RDS: revisa la DLQ y los logs de Process-Order en CloudWatch."
  exit 1
fi

# --- Limpieza del carrito (la orden ya lo vacio; esto cubre el caso de error) ---
curl -fsS -X DELETE "$BASE/api/cart/$ID_BASE?userId=$USUARIO" > /dev/null 2>&1 || true

printf '\n=== Flujo EP3 OK por %s ===\n' "$BASE"
