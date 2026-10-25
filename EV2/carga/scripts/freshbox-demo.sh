#!/bin/bash
# ============================================
# Demo de escalado de FreshBox, desde la maquina de carga (como root: sudo -i).
#   1. Sube el maximo del HPA de frontend y get-products (por defecto a 15). Con
#      el maximo del repositorio (5) todas las replicas caben en 2 nodos y el
#      Cluster Autoscaler nunca agregaria un tercero.
#   2. Lanza k6 contra el ALB: 2 min de subida, meseta y 1 min de bajada.
#   3. Al terminar, o con Ctrl+C, devuelve el maximo original.
# Despues los pods vuelven al minimo en ~2 min y los nodos extra se retiran
# unos 4-5 min mas tarde (lo decide el Cluster Autoscaler).
#
#   freshbox-demo [usuarios_virtuales] [minutos_de_meseta]   # por defecto 100 y 6
#   MAX_DEMO=20 freshbox-demo                                # otro maximo de replicas
# En otra sesion: freshbox-vigilar
# ============================================
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/etc/freshbox-carga/kubeconfig}"

VUS="${1:-100}"
MESETA="${2:-6}"
MAX_DEMO="${MAX_DEMO:-15}"
NS=freshbox
HPAS=(frontend-hpa get-products-hpa)

if [ ! -f /etc/freshbox-carga/lista ]; then
  echo "La maquina aun se esta preparando: revisa /var/log/freshbox-carga.log"
  exit 1
fi

ALB="$(kubectl get ingress freshbox-ingress -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
if [ -z "$ALB" ]; then
  echo "El Ingress freshbox-ingress no tiene DNS del ALB: despliega EP2 primero."
  exit 1
fi

declare -A ORIGINAL
restaurar() {
  for h in "${HPAS[@]}"; do
    [ -n "${ORIGINAL[$h]:-}" ] || continue
    kubectl patch hpa "$h" -n "$NS" --type merge -p "{\"spec\":{\"maxReplicas\":${ORIGINAL[$h]}}}" > /dev/null
    echo "HPA $h: maxReplicas de vuelta en ${ORIGINAL[$h]}"
  done
}
trap restaurar EXIT
trap 'exit 130' INT TERM HUP # cerrar la sesion tambien devuelve el maximo

for h in "${HPAS[@]}"; do
  ORIGINAL[$h]="$(kubectl get hpa "$h" -n "$NS" -o jsonpath='{.spec.maxReplicas}')"
  kubectl patch hpa "$h" -n "$NS" --type merge -p "{\"spec\":{\"maxReplicas\":$MAX_DEMO}}" > /dev/null
  echo "HPA $h: maxReplicas ${ORIGINAL[$h]} -> $MAX_DEMO (solo durante la demo)"
done

echo "=== k6: $VUS usuarios virtuales contra http://$ALB, meseta de $MESETA min ==="
k6 run -e BASE_URL="http://$ALB" -e VUS="$VUS" -e MESETA="${MESETA}m" /opt/freshbox-carga/carga.js || true

kubectl get hpa -n "$NS"
kubectl get nodes
echo "=== Fin de la carga: sigue la bajada de pods y nodos en freshbox-vigilar ==="
