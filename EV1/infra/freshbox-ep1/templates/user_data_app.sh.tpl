#!/bin/bash
# ============================================
# FreshBox SpA - User Data EC2 App (Launch Template freshbox-lt-app)
# Generado por Terraform; equivale a EV1/app/scripts/deploy-containers.sh ejecutado al arrancar cada instancia.
# Instala Docker, hace login en ECR y levanta los 5 contenedores.
# Solo el frontend (Nginx :80) es alcanzable desde la red; los 4 backends
# escuchan en 127.0.0.1:300x (para depurar con curl desde la instancia) y el
# frontend los enruta por la red Docker interna (/api/products).
# ============================================

exec > /var/log/user-data.log 2>&1
set -x

dnf update -y
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

REGION="${region}"
ACCOUNT_ID="${account_id}"
REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
TAG="${image_tag}"
DB_HOST="${db_host}"
P="${project_name}"
SERVICES="frontend get-products create-product update-product delete-product"

# Login a ECR con las credenciales del LabInstanceProfile (IMDSv2).
ecr_login() {
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
}

pull_all() {
  for S in $SERVICES; do
    docker pull "$REGISTRY/$P-$S:$TAG" || return 1
  done
}

# Las imagenes las publica la pipeline (GitHub Actions) despues del
# terraform apply: se reintenta el pull hasta ~20 min para no depender del orden.
for i in $(seq 1 40); do
  if ecr_login && pull_all; then
    break
  fi
  echo "Imagenes aun no disponibles en ECR (intento $i/40); reintento en 30 s"
  sleep 30
done

docker network create "$P-net" 2>/dev/null || true
for S in $SERVICES; do
  docker rm -f "$P-$S" 2>/dev/null || true
done

DB_ENV="-e DB_HOST=$DB_HOST -e DB_USER=${db_user} -e DB_PASS=${db_pass} -e DB_NAME=${db_name} -e DB_PORT=3306"

# Backends primero (Nginx resuelve sus nombres al arrancar). El alias de red
# coincide con los upstreams de nginx.conf (get-products, create-product, ...).
PORT=3001
for S in get-products create-product update-product delete-product; do
  docker run -d --name "$P-$S" --network "$P-net" --network-alias "$S" \
    --restart unless-stopped -p 127.0.0.1:$PORT:$PORT \
    $DB_ENV -e PORT=$PORT \
    "$REGISTRY/$P-$S:$TAG"
  PORT=$((PORT + 1))
done

docker run -d --name "$P-frontend" --network "$P-net" --restart unless-stopped \
  -p 80:80 "$REGISTRY/$P-frontend:$TAG"

echo "=== Contenedores desplegados en $(hostname) ==="
docker ps
