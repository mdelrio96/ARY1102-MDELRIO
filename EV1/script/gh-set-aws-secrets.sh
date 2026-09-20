#!/bin/bash
# ============================================
# Copia las credenciales temporales del AWS Academy Learner Lab a los secretos
# de GitHub que usan las pipelines (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
# AWS_SESSION_TOKEN). Ejecutar cada vez que se inicia el lab: las credenciales
# caducan al terminar la sesion.
#
# Pasos previos (una sola vez): gh auth login.
# En el Learner Lab: "AWS Details" -> "AWS CLI: Show" -> pegar el bloque en
# ~/.aws/credentials (perfil [default]) y luego:
#
#   ./EV1/script/gh-set-aws-secrets.sh             # desde la raiz del repo (usa el remoto origin)
#   ./EV1/script/gh-set-aws-secrets.sh miperfil    # otro perfil de ~/.aws/credentials
# ============================================
set -euo pipefail

PROFILE="${1:-default}"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

for tool in aws gh; do
  command -v "$tool" > /dev/null || { echo "Falta $tool en el PATH"; exit 1; }
done

for key in aws_access_key_id aws_secret_access_key aws_session_token; do
  value="$(aws configure get "$key" --profile "$PROFILE" || true)"
  if [ -z "$value" ]; then
    echo "El perfil '$PROFILE' no tiene $key (el Learner Lab siempre entrega los tres valores)"
    exit 1
  fi
  gh secret set "${key^^}" --repo "$REPO" --body "$value"
done

echo "Secretos AWS_* actualizados en $REPO."
echo "Caducan al cerrar la sesion del Learner Lab; volver a ejecutar este script al reiniciarlo."
