#!/bin/bash
# ============================================
# Genera carga sobre get-products para ver escalar al HPA (demostracion).
# Lanza un pod busybox con N bucles que piden /api/products dentro del cluster
# durante DURACION segundos y muestra el HPA cada 15 s. Al terminar borra el pod;
# el HPA vuelve al minimo despues de 2 minutos sin carga.
#
#   ./EV2/script/carga-hpa.sh [segundos] [bucles]     # por defecto 180 y 20
# En otra terminal: kubectl get hpa -n freshbox -w   /   kubectl top pods -n freshbox
# ============================================
set -euo pipefail

DURACION="${1:-180}"
BUCLES="${2:-20}"
NS=freshbox
DESTINO="http://get-products.$NS.svc.cluster.local:3001/api/products"

kubectl delete pod carga-hpa -n "$NS" --ignore-not-found --wait=true > /dev/null
kubectl run carga-hpa -n "$NS" --image=busybox:1.36 --restart=Never --labels=app=carga-hpa -- \
  /bin/sh -c "for i in \$(seq 1 $BUCLES); do (while true; do wget -q -O /dev/null $DESTINO; done) & done; sleep $DURACION"
kubectl wait --for=condition=Ready pod/carga-hpa -n "$NS" --timeout=120s

echo "=== Carga: $BUCLES bucles contra get-products durante $DURACION s ==="
FIN=$((SECONDS + DURACION))
while [ "$SECONDS" -lt "$FIN" ]; do
  kubectl get hpa get-products-hpa -n "$NS" --no-headers
  sleep 15
done

kubectl delete pod carga-hpa -n "$NS" --ignore-not-found > /dev/null
kubectl get pods -n "$NS" -l app=get-products -o wide
kubectl get hpa -n "$NS"
echo "=== Fin de la carga ==="
