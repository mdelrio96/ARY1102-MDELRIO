#!/bin/bash
# Prepara la maquina de carga: scripts de la demo, kubectl, k6 y el Cluster
# Autoscaler como servicio systemd. Log en /var/log/freshbox-carga.log; al
# terminar crea /etc/freshbox-carga/lista (freshbox-demo la exige).
set -euxo pipefail
exec > >(tee -a /var/log/freshbox-carga.log) 2>&1
export HOME=/root

REGION="${region}"
CLUSTER="${cluster_name}"
K6_VERSION="${k6_version}"
ETC=/etc/freshbox-carga
mkdir -p "$ETC" /opt/freshbox-carga

# --- Scripts de la demo (EV2/carga/scripts) ---
echo "${carga_js}" | base64 -d > /opt/freshbox-carga/carga.js
echo "${demo_sh}" | base64 -d > /usr/local/bin/freshbox-demo
echo "${vigilar_sh}" | base64 -d > /usr/local/bin/freshbox-vigilar
chmod 755 /usr/local/bin/freshbox-demo /usr/local/bin/freshbox-vigilar

dnf install -y docker jq
systemctl enable --now docker

# --- kubeconfig: autentica con LabRole (perfil de instancia), legible por todos los usuarios ---
aws eks wait cluster-active --name "$CLUSTER" --region "$REGION"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" --kubeconfig "$ETC/kubeconfig"
chmod 644 "$ETC/kubeconfig"
echo "export KUBECONFIG=$ETC/kubeconfig" > /etc/profile.d/freshbox-carga.sh

# --- kubectl y Cluster Autoscaler con la misma version menor que el cluster ---
K8S="$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.version --output text)"
KUBECTL="$(curl -fsSL "https://dl.k8s.io/release/stable-$K8S.txt")"
curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$KUBECTL/bin/linux/arm64/kubectl"
chmod 755 /usr/local/bin/kubectl

curl -fsSL "https://github.com/grafana/k6/releases/download/$K6_VERSION/k6-$K6_VERSION-linux-arm64.tar.gz" | tar xz -C /tmp
install -m 755 "/tmp/k6-$K6_VERSION-linux-arm64/k6" /usr/local/bin/k6

# El proyecto solo publica imagenes: el binario se copia desde la imagen oficial
# (ultimo parche de la version menor; si no se puede listar, el .0).
CA_TAG="$(curl -fsSL https://registry.k8s.io/v2/autoscaling/cluster-autoscaler/tags/list \
  | jq -r '.tags[]' | grep -E "^v$K8S\.[0-9]+$" | sort -V | tail -1 || true)"
[ -n "$CA_TAG" ] || CA_TAG="v$K8S.0"
CA_IMG="registry.k8s.io/autoscaling/cluster-autoscaler:$CA_TAG"
docker pull "$CA_IMG"
CA_BIN="$(docker image inspect "$CA_IMG" | jq -r '.[0].Config | ((.Entrypoint // []) + (.Cmd // []))[0]')"
docker create --name ca-extraer "$CA_IMG"
docker cp "ca-extraer:$CA_BIN" /usr/local/bin/cluster-autoscaler
docker rm ca-extraer

# Descubre el ASG del node group por los tags que EKS le pone
# (k8s.io/cluster-autoscaler/enabled y k8s.io/cluster-autoscaler/<cluster>) y
# respeta su minimo y maximo (2 y 4). Retira un nodo tras 2 min sin uso
# (por defecto son 10) para que la bajada se vea en la demo.
cat > /etc/systemd/system/cluster-autoscaler.service <<EOF
[Unit]
Description=Cluster Autoscaler del node group de $CLUSTER ($CA_TAG)
Wants=network-online.target
After=network-online.target

[Service]
Environment=AWS_REGION=$REGION
ExecStart=/usr/local/bin/cluster-autoscaler \
  --cloud-provider=aws \
  --kubeconfig=$ETC/kubeconfig \
  --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/$CLUSTER \
  --balance-similar-node-groups \
  --expander=least-waste \
  --skip-nodes-with-system-pods=false \
  --skip-nodes-with-local-storage=false \
  --scale-down-unneeded-time=2m \
  --scale-down-delay-after-add=2m \
  --v=2
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now cluster-autoscaler

touch "$ETC/lista"
echo "Maquina de carga lista ($CA_TAG). Como root (sudo -i): freshbox-vigilar y freshbox-demo"
