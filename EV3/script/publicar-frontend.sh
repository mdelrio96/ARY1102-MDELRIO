#!/bin/bash
# ============================================
# Frontend de FreshBox en Amazon S3 Static Website (pauta EP3 2.2 y 2.5, paso 8).
# Crea el bucket si no existe, activa el hosting estatico, deja solo lectura
# publica de los objetos y sube EV3/app/frontend con la URL de API Gateway en
# js/app.js. Idempotente: se repite para actualizar el sitio.
#
# Por que un script y no Terraform: la SCP del Learner Lab deniega
# s3:GetBucketObjectLockConfiguration, que el recurso aws_s3_bucket consulta al
# leer cualquier bucket (ver EV1/infra/freshbox-ep1/README.md).
#
# Lee api_url, frontend_bucket y aws_region del estado de Terraform, asi que
# necesita terraform init hecho en EV3/infra/freshbox-ep3.
#
#   ./EV3/script/publicar-frontend.sh    # desde cualquier directorio
# ============================================
set -euo pipefail

EV3="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$EV3/infra/freshbox-ep3"
SRC="$EV3/app/frontend"

for c in aws terraform; do
  command -v "$c" > /dev/null || { echo "Falta $c en el PATH"; exit 1; }
done

tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }
REGION="$(tf_out aws_region)"
API_URL="$(tf_out api_url)"
BUCKET="$(tf_out frontend_bucket)"

# --- Bucket ---
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" > /dev/null 2>&1; then
  echo "Bucket $BUCKET: ya existe."
else
  echo "Bucket $BUCKET: creando en $REGION..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" > /dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" > /dev/null
  fi
  aws s3api wait bucket-exists --bucket "$BUCKET" --region "$REGION"
fi

aws s3api put-bucket-tagging --bucket "$BUCKET" --region "$REGION" \
  --tagging 'TagSet=[{Key=Project,Value=FreshBox},{Key=Env,Value=EP3},{Key=Layer,Value=web},{Key=ManagedBy,Value=script}]'

# Solo la politica del bucket puede dar acceso publico; las ACL siguen bloqueadas.
aws s3api put-public-access-block --bucket "$BUCKET" --region "$REGION" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false

aws s3api put-bucket-website --bucket "$BUCKET" --region "$REGION" \
  --website-configuration '{"IndexDocument":{"Suffix":"index.html"},"ErrorDocument":{"Key":"index.html"}}'

# Lectura publica de los objetos (s3:GetObject) y nada mas.
POLICY="$(printf '{"Version":"2012-10-17","Statement":[{"Sid":"LecturaPublicaSitio","Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::%s/*"}]}' "$BUCKET")"
aws s3api put-bucket-policy --bucket "$BUCKET" --region "$REGION" --policy "$POLICY"

# --- Archivos: copia temporal con la URL real de API Gateway ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -R "$SRC/." "$TMP/"
sed -i "s|^const API_URL = \".*\";|const API_URL = \"$API_URL\";|" "$TMP/js/app.js"
if ! grep -qF "const API_URL = \"$API_URL\";" "$TMP/js/app.js"; then
  echo "No se pudo escribir API_URL en js/app.js"
  exit 1
fi

# no-cache: el navegador vuelve a pedir el sitio despues de cada publicacion.
aws s3 sync "$TMP" "s3://$BUCKET" --region "$REGION" --delete --cache-control "no-cache"

URL="http://$BUCKET.s3-website-$REGION.amazonaws.com"
echo "Frontend publicado: $URL (API: $API_URL)"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "frontend_url=$URL" >> "$GITHUB_OUTPUT"
fi
