#!/bin/bash
# ============================================
# Retira lo que Kubernetes creo fuera de Terraform, antes de terraform destroy:
# el ALB del Ingress (con sus target groups) y los pods del namespace freshbox.
# Si el ALB quedara vivo, sus interfaces impedirian borrar las subredes y la VPC.
# No falla si el cluster ya no existe.
#
#   ./EV2/script/bajar-k8s.sh
# ============================================
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${CLUSTER:-freshbox-cluster}"
NS=freshbox

if ! VPC="$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
              --query 'cluster.resourcesVpcConfig.vpcId' --output text 2> /dev/null)"; then
  echo "No existe el cluster $CLUSTER: nada que retirar en Kubernetes."
  exit 0
fi
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" --alias "$CLUSTER" > /dev/null

# El controlador borra el ALB y despues quita el finalizer del Ingress: --wait espera eso.
if kubectl get namespace "$NS" > /dev/null 2>&1; then
  kubectl delete ingress --all -n "$NS" --wait=true --timeout=300s || true
  kubectl delete namespace "$NS" --wait=true --timeout=300s || true
fi
kubectl delete ingressclass freshbox-alb --ignore-not-found || true
kubectl delete ingressclassparams freshbox-alb --ignore-not-found 2> /dev/null || true

# Comprobacion independiente del nombre: ningun balanceador en la VPC del cluster.
for i in $(seq 1 20); do
  LBS="$(aws elbv2 describe-load-balancers --region "$REGION" \
           --query "LoadBalancers[?VpcId=='$VPC'].LoadBalancerName" --output text)"
  if [ -z "$LBS" ] || [ "$LBS" = "None" ]; then
    echo "Sin balanceadores en $VPC: se puede ejecutar terraform destroy."
    exit 0
  fi
  echo "[$i] aun existen: $LBS"
  sleep 15
done
echo "Siguen existiendo balanceadores en $VPC ($LBS): borralos antes de terraform destroy."
exit 1
