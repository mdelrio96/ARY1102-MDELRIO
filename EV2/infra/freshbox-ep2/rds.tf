# ---------- Capa Data: Amazon RDS MySQL Multi-AZ (PaaS) ----------
# Reemplaza la EC2 MySQL + AWS Backup de EV1: AWS administra parches, respaldos
# y failover. Primaria en una subred Data y standby sincronico en la otra AZ;
# ante una falla RDS promueve el standby y el endpoint no cambia.

# La clave se genera aqui y no se versiona: queda en el estado de Terraform
# (bucket S3 privado) y script/aplicar-k8s.sh la lleva al Secret de Kubernetes.
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "main" {
  name        = "${local.name}-db-subnets"
  description = "Subredes privadas Data en dos AZ"
  subnet_ids  = aws_subnet.data[*].id
  tags        = { Name = "${local.name}-db-subnets", Layer = "data" }
}

resource "aws_db_instance" "main" {
  identifier     = "${local.name}-db"
  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_user
  password = random_password.db.result
  port     = 3306

  # Almacenamiento gp3 cifrado (clave administrada aws/rds); crece solo hasta 50 GB.
  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Snapshots automaticos diarios (03:00 en Chile) con retencion configurable.
  backup_retention_period = var.db_backup_retention_days
  backup_window           = "06:00-06:30"
  maintenance_window      = "sun:07:00-sun:07:30"
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Laboratorio: se destruye al terminar cada sesion, sin snapshot final.
  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true

  tags = { Name = "${local.name}-db", Layer = "data" }
}
