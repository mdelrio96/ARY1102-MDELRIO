#!/bin/bash
# ============================================
# Muestra cada 5 s lo que se mira durante la demo de escalado: HPA (replicas y
# CPU), nodos, CPU por nodo y pods por nodo. Los pods en <none> estan Pending:
# son los que obligan al Cluster Autoscaler a agregar un nodo. Salir con Ctrl+C.
#
#   freshbox-vigilar
# Decisiones del autoscaler: journalctl -u cluster-autoscaler -f | grep -iE 'scale-up|scale_up|removing|unneeded'
# ============================================
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/etc/freshbox-carga/kubeconfig}"

exec watch -n 5 -t '
date "+%H:%M:%S"
echo "--- HPA ---"
kubectl get hpa -n freshbox
echo; echo "--- Nodos ---"
kubectl get nodes -L node.kubernetes.io/instance-type,topology.kubernetes.io/zone
echo; echo "--- CPU por nodo ---"
kubectl top nodes 2> /dev/null || echo "(metrics-server aun sin datos)"
echo; echo "--- Pods por nodo (<none> = Pending) ---"
kubectl get pods -n freshbox --no-headers -o custom-columns=NODO:.spec.nodeName | sort | uniq -c
'
