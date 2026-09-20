#!/bin/bash
# ============================================
# FreshBox SpA - User Data EC2 MySQL (generado por Terraform)
# Levanta el contenedor mysql:8.0 (mismo que docker-compose.yml) con init.sql.
# Los datos quedan en /opt/freshbox/mysql-data, sobre el EBS raiz cifrado,
# por lo que sobreviven a reinicios del contenedor y a stop/start del lab.
# ============================================

exec > /var/log/user-data.log 2>&1
set -x

dnf update -y
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

mkdir -p /opt/${project_name}/mysql-data
cat > /opt/${project_name}/init.sql << 'EOSQL'
${init_sql}
EOSQL

docker rm -f ${project_name}-db 2>/dev/null || true

docker run -d \
  --name ${project_name}-db \
  --restart unless-stopped \
  -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD='${root_password}' \
  -e MYSQL_USER='${db_user}' \
  -e MYSQL_PASSWORD='${db_pass}' \
  -e MYSQL_DATABASE='${db_name}' \
  -v /opt/${project_name}/init.sql:/docker-entrypoint-initdb.d/init.sql:ro \
  -v /opt/${project_name}/mysql-data:/var/lib/mysql \
  mysql:8.0

echo "=== MySQL (${project_name}-db) desplegado en $(hostname) ==="
