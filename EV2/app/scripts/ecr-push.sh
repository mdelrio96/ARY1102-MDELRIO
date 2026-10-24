#!/bin/bash
# ============================================
# FreshBox SpA - Build y push de las 5 imagenes a ECR (EP2)
# Construye linux/arm64 (nodos t4g.small Graviton) y publica cada imagen con dos
# tags: IMAGE_TAG (por defecto, el commit actual) y latest. Los manifiestos usan
# IMAGE_TAG con imagePullPolicy IfNotPresent, asi que cada version debe tener
# un tag propio. Los repositorios los crea Terraform (EV2/infra/freshbox-ep2).
#
#   ./EV2/app/scripts/ecr-push.sh                 # desde cualquier directorio
#   IMAGE_TAG=v2 ./EV2/app/scripts/ecr-push.sh
# Requiere Docker con Buildx (Docker Desktop lo incluye) y credenciales del lab.
# ============================================
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
PLATFORM="${PLATFORM:-linux/arm64}"
IMAGE_TAG="${IMAGE_TAG:-$(git -C "$APP_DIR" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M)}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
echo "=== Cuenta: $ACCOUNT_ID | Region: $REGION | Plataforma: $PLATFORM | Tag: $IMAGE_TAG ==="

declare -A CONTEXTS=(
  [frontend]=microservicioFrontend
  [get-products]=microserviciosBackend/get-products
  [create-product]=microserviciosBackend/create-product
  [update-product]=microserviciosBackend/update-product
  [delete-product]=microserviciosBackend/delete-product
)

for SERVICE in "${!CONTEXTS[@]}"; do
  aws ecr describe-repositories --repository-names "freshbox-$SERVICE" --region "$REGION" > /dev/null 2>&1 \
    || { echo "No existe el repositorio freshbox-$SERVICE: aplica primero Terraform (EV2/infra/freshbox-ep2)."; exit 1; }
done

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for SERVICE in "${!CONTEXTS[@]}"; do
  echo "=== freshbox-$SERVICE ==="
  docker buildx build --platform "$PLATFORM" --provenance=false --push \
    -t "$REGISTRY/freshbox-$SERVICE:$IMAGE_TAG" \
    -t "$REGISTRY/freshbox-$SERVICE:latest" \
    "$APP_DIR/${CONTEXTS[$SERVICE]}"
done

docker logout "$REGISTRY" > /dev/null
echo "=== Push completado. Para desplegar: IMAGE_TAG=$IMAGE_TAG ./EV2/script/aplicar-k8s.sh ==="

# 2026 - Disenador asignatura: Ignacio A. Pastenet M. (adaptado para EP2)
