#!/bin/bash
# ============================================
# Despliega FreshBox EP3 en EKS con las salidas de Terraform (EV3/infra/freshbox-ep3):
#   1. kubeconfig del cluster y chequeo de que las 4 imagenes del tag existen en ECR
#   2. completa los manifiestos de EV3/k8s en EV3/.render/ (fuera de Git, permisos 600)
#   3. namespace, ConfigMap y Secret (clave de RDS desde Terraform, nunca en argumentos)
#   4. Job migrar-datos-ep3: esquema (productos y ordenes) y datos iniciales
#   5. Deployments, Services, HPA y PDB; espera el rollout
#   6. IngressClass + Ingress (ALB de EKS Auto Mode con reglas por metodo HTTP)
#   7. espera el DNS del ALB y lo guarda en la variable de stage albHost de API Gateway
#
#   IMAGE_TAG=<tag publicado en ECR> ./EV3/script/aplicar-k8s.sh
# IMAGE_TAG por defecto es el commit actual (el mismo que usa ecr-push.sh).
# Requiere aws, kubectl y terraform con el backend ya inicializado
# (terraform -chdir=EV3/infra/freshbox-ep3 init).
# ============================================
set -euo pipefail

EV3_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$EV3_DIR/infra/freshbox-ep3"
K8S_DIR="$EV3_DIR/k8s"
OUT="$EV3_DIR/.render"
NS=freshbox
APPS=(get-products create-product update-product delete-product)
IMAGE_TAG="${IMAGE_TAG:-$(git -C "$EV3_DIR" rev-parse --short HEAD)}"

for c in aws kubectl terraform; do
  command -v "$c" > /dev/null || { echo "Falta $c en el PATH"; exit 1; }
done

tf() { terraform -chdir="$TF_DIR" output -raw "$1"; }
if [ "$(tf eks_enabled)" != "true" ]; then
  echo "La infraestructura se creo sin cluster EKS (create_eks = false)."
  echo "Agregalo con: terraform -chdir=EV3/infra/freshbox-ep3 apply -var create_eks=true"
  exit 1
fi
REGION="$(tf aws_region)"
CLUSTER="$(tf cluster_name)"
REGISTRY="$(tf ecr_registry)"
RDS_ENDPOINT="$(tf rds_endpoint)"
SG_ALB="$(tf sg_alb_id)"
DB_USER="$(tf db_user)"
API_ID="$(tf api_id)"

echo "=== Cluster $CLUSTER ($REGION) | imagenes $REGISTRY/freshbox-*:$IMAGE_TAG ==="
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" --alias "$CLUSTER" > /dev/null

for app in "${APPS[@]}"; do
  aws ecr describe-images --repository-name "freshbox-$app" --image-ids imageTag="$IMAGE_TAG" \
    --region "$REGION" > /dev/null 2>&1 \
    || { echo "No existe freshbox-$app:$IMAGE_TAG en ECR: publica ese tag (EV3/app/scripts/ecr-push.sh)."; exit 1; }
done

# --- 1. Manifiestos con valores reales ---
umask 077
rm -rf "$OUT"
mkdir -p "$OUT"
while IFS= read -r f; do
  sed -e "s|<ECR_REGISTRY>|$REGISTRY|g" \
      -e "s|<IMAGE_TAG>|$IMAGE_TAG|g" \
      -e "s|<RDS_ENDPOINT>|$RDS_ENDPOINT|g" \
      -e "s|<SG_ALB_ID>|$SG_ALB|g" "$K8S_DIR/$f" > "$OUT/${f//\//-}"
done < <(cd "$K8S_DIR" && find . -name '*.yaml' | sed 's|^\./||' | sort)

# --- 2. Namespace, ConfigMap y Secret ---
# Si cambian hay que reiniciar los pods: leen esos valores solo al arrancar.
REINICIAR=0
kubectl apply -f "$OUT/00-namespace.yaml"
kubectl apply -f "$OUT/01-configmap.yaml" | tee "$OUT/apply.log"
{ printf 'DB_USER=%s\n' "$DB_USER"; printf 'DB_PASS=%s\n' "$(tf db_password)"; } > "$OUT/db.env"
kubectl create secret generic freshbox-secret -n "$NS" --from-env-file="$OUT/db.env" \
  --dry-run=client -o yaml | kubectl apply -f - | tee -a "$OUT/apply.log"
rm -f "$OUT/db.env"
grep -q " configured" "$OUT/apply.log" && REINICIAR=1

# --- 3. Job de esquema y datos iniciales ---
kubectl create configmap freshbox-init-sql -n "$NS" \
  --from-file=init.sql="$EV3_DIR/app/init.sql" \
  --from-file=datos-iniciales.sql="$EV3_DIR/app/datos-iniciales.sql" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl delete job migrar-datos-ep3 -n "$NS" --ignore-not-found
kubectl apply -f "$OUT/03-migrar-datos-job.yaml"
if ! kubectl wait --for=condition=complete job/migrar-datos-ep3 -n "$NS" --timeout=300s; then
  kubectl logs job/migrar-datos-ep3 -n "$NS" --tail=50 || true
  echo "La migracion no termino: revisa SG-RDS, el endpoint y la clave."
  exit 1
fi
kubectl logs job/migrar-datos-ep3 -n "$NS"

# --- 4. Deployments, Services, HPA y PodDisruptionBudgets ---
kubectl apply -f "$OUT/servicios.yaml" -f "$OUT/pdb.yaml"
if [ "$REINICIAR" = 1 ]; then
  echo "ConfigMap o Secret cambiaron: reinicio de los Deployments"
  kubectl rollout restart deployment -n "$NS"
fi
for app in "${APPS[@]}"; do
  kubectl rollout status "deployment/$app" -n "$NS" --timeout=300s
done

# --- 5. ALB (Ingress de EKS Auto Mode) ---
# Un Ingress sin DNS quedo a medio crear: se borra para que el controlador lo arme de nuevo.
if kubectl get ingress freshbox-ingress -n "$NS" > /dev/null 2>&1 \
   && [ -z "$(kubectl get ingress freshbox-ingress -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')" ]; then
  echo "El Ingress existe sin DNS del ALB: se borra y se vuelve a crear"
  kubectl delete ingress freshbox-ingress -n "$NS" --wait=true --timeout=300s
fi
kubectl apply -f "$OUT/ingressclass.yaml" -f "$OUT/ingress.yaml"

# --- 6. DNS del ALB (los targets tardan 1-3 minutos mas en quedar sanos) ---
ALB=""
for i in $(seq 1 40); do
  ALB="$(kubectl get ingress freshbox-ingress -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2> /dev/null || true)"
  [ -n "$ALB" ] && break
  echo "[$i] esperando el DNS del ALB..."
  sleep 15
done
if [ -z "$ALB" ]; then
  kubectl describe ingress freshbox-ingress -n "$NS" | tail -20
  echo "El Ingress no recibio DNS en 10 minutos (revisa los eventos de arriba)."
  exit 1
fi

# --- 7. albHost en API Gateway: el stage apunta al ALB sin redesplegar la API ---
aws apigateway update-stage --rest-api-id "$API_ID" --stage-name prod --region "$REGION" \
  --patch-operations "op=replace,path=/variables/albHost,value=$ALB" > /dev/null
echo "API Gateway (stage prod): albHost = $ALB"

kubectl get nodes -o wide
kubectl get pods,services,ingress,hpa,pdb -n "$NS" -o wide
echo "=== ALB http://$ALB | API Gateway -> ALB listo ==="
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "alb_url=http://$ALB" >> "$GITHUB_OUTPUT"
fi
