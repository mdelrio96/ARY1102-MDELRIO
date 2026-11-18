#!/bin/bash
# ============================================
# Vacia y borra el bucket del frontend (lo contrario de publicar-frontend.sh).
# terraform destroy no lo toca porque no es un recurso de Terraform; se corre
# junto con la eliminacion para dejar la cuenta limpia. Si no existe, no falla.
#
# El nombre (freshbox-frontend-<ID de cuenta>) es el mismo que entrega el
# output frontend_bucket; se arma aqui para no depender del estado de Terraform.
#
#   ./EV3/script/bajar-frontend.sh    # desde cualquier directorio
# ============================================
set -euo pipefail

command -v aws > /dev/null || { echo "Falta aws en el PATH"; exit 1; }

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="freshbox-frontend-$ACCOUNT"

if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" > /dev/null 2>&1; then
  aws s3 rm "s3://$BUCKET" --recursive --region "$REGION"
  aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION"
  echo "Bucket $BUCKET: vaciado y borrado."
else
  echo "Bucket $BUCKET: no existe, nada que borrar."
fi
