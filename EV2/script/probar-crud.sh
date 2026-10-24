#!/bin/bash
# ============================================
# Prueba el CRUD completo por el ALB: frontend, GET de la lista, POST, PUT,
# GET por id, DELETE y GET final (404). Crea un registro temporal y lo borra,
# asi que la base queda como estaba.
#
#   ./EV2/script/probar-crud.sh http://<DNS del ALB>
#   ./EV2/script/probar-crud.sh          # sin argumento lo toma del Ingress
# ============================================
set -euo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  URL="http://$(kubectl get ingress freshbox-ingress -n freshbox -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
fi
URL="${URL%/}"
API="$URL/api/products"

echo "=== Esperando que el ALB tenga targets sanos ($URL) ==="
for i in $(seq 1 40); do
  curl -fsS --max-time 10 "$API" > /dev/null 2>&1 && break
  [ "$i" = 40 ] && { echo "El ALB no respondio en 10 minutos"; exit 1; }
  echo "[$i] aun no responde..."
  sleep 15
done

paso() { printf '\n--- %s\n' "$1"; }

paso "GET / (frontend Nginx)"
curl -fsS -o /dev/null -w 'HTTP %{http_code}\n' "$URL/"

paso "GET /api/products (get-products)"
LISTA="$(curl -fsS "$API")"
printf '%s...\n' "${LISTA:0:500}"

paso "POST /api/products (create-product)"
CREADO="$(curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"nombre":"Prueba CRUD EP2","descripcion":"Registro temporal de la prueba","precio":1990,"stock":5,"categoria":"Prueba"}' "$API")"
echo "$CREADO"
ID="$(printf '%s' "$CREADO" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')"
[ -n "$ID" ] || { echo "No se obtuvo el id del producto creado"; exit 1; }

paso "PUT /api/products/$ID (update-product)"
curl -fsS -X PUT -H 'Content-Type: application/json' \
  -d '{"nombre":"Prueba CRUD EP2 (editado)","descripcion":"Registro temporal modificado","precio":2490,"stock":3,"categoria":"Prueba"}' "$API/$ID"
echo

paso "GET /api/products/$ID (get-products)"
curl -fsS "$API/$ID"
echo

paso "DELETE /api/products/$ID (delete-product)"
curl -fsS -X DELETE "$API/$ID"
echo

paso "GET /api/products/$ID (debe responder 404)"
CODE="$(curl -s -o /dev/null -w '%{http_code}' "$API/$ID")"
echo "HTTP $CODE"
[ "$CODE" = 404 ] || { echo "El producto $ID sigue existiendo"; exit 1; }

printf '\n=== CRUD OK por %s ===\n' "$URL"
