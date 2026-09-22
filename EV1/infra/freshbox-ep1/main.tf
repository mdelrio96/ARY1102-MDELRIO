# ============================================
# FreshBox SpA - Infraestructura EP1 (ARY1102 Arquitectura Cloud)
# Arquitectura TO-BE de 3 capas en un AWS Academy Learner Lab.
# Los valores de diseno son los del caso (VPC /22, SG por capa, ASG 2-4, t4g.small).
#
# Todo en main.tf (red, SG, ECR, MySQL, LT + ASG, ALB, Backup); variables.tf
# y outputs.tf aparte por convencion.
# ============================================

terraform {
  required_version = ">= 1.10.0" # use_lockfile del backend S3

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Estado remoto en S3 con bloqueo en DynamoDB (formato pedido en el curso) y,
  # ademas, el lockfile nativo de S3. Terraform avisa en cada init que
  # dynamodb_table esta obsoleto: es esperable. Ni el bucket ni la tabla pueden
  # ser recursos de Terraform (el backend los necesita antes del init y la SCP
  # del Learner Lab impide leer buckets: GetBucketObjectLockConfiguration). Los
  # crea EV1/script/bootstrap-tfstate.sh antes de cada init (pipeline y local),
  # asi que un reset del lab no requiere pasos a mano. Mismo "terraform init" en
  # el PC y en GitHub Actions. Para probar sin S3: terraform init -backend=false
  backend "s3" {
    bucket         = "freshbox-tfstate-870431978422" # freshbox-tfstate-<ID de cuenta del lab>
    key            = "freshbox/ep1/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "freshbox-tfstate-lock" # clave de particion LockID (S)
    use_lockfile   = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "FreshBox"
      Env       = "EP1"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# AWS Academy no permite crear roles IAM: se reutilizan el Instance Profile y
# el Role que el Learner Lab deja provisionados.
data "aws_iam_instance_profile" "lab" {
  name = var.lab_instance_profile_name
}

data "aws_iam_role" "lab" {
  name = var.lab_role_name
}

# Amazon Linux 2023 de la arquitectura elegida (arm64 = Graviton / t4g).
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-*-${var.instance_arch}"]
  }

  filter {
    name   = "architecture"
    values = [var.instance_arch]
  }
}

locals {
  name     = var.project_name
  registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"

  services = [
    "frontend",
    "get-products",
    "create-product",
    "update-product",
    "delete-product",
  ]
}

# ---------- Red: VPC 10.0.0.0/22 + 6 subredes /25 (2 publicas, 2 App, 2 Data) ----------
# Queda libre 10.0.3.0/24 para la etapa 2 (carrito y ordenes).

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

locals {
  az_suffix = ["1a", "1b"]
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name  = "${local.name}-subnet-public-${local.az_suffix[count.index]}"
    Layer = "web"
  }
}

resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name  = "${local.name}-subnet-app-${local.az_suffix[count.index]}"
    Layer = "app"
  }
}

resource "aws_subnet" "data" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.data_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name  = "${local.name}-subnet-data-${local.az_suffix[count.index]}"
    Layer = "data"
  }
}

# Un solo NAT Gateway (en public-1a) por costo; da salida a Internet a las
# subredes privadas de ambas AZ. Un segundo NAT en 1b queda como mejora.
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${local.name}-eip-natgw" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${local.name}-natgw" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.name}-rt-public" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${local.name}-rt-private" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data" {
  count          = 2
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------- Security Groups encadenados (matriz exacta del caso) ----------
#   SG-ALB : 80, 443 desde 0.0.0.0/0
#   SG-APP : 80, 443 solo desde SG-ALB
#   SG-DATA: 3306 solo desde SG-APP

resource "aws_security_group" "alb" {
  name        = "${local.name}-sg-alb"
  description = "HTTP/HTTPS desde Internet hacia el ALB"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = [80, 443]
    content {
      description = "Internet a ALB ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg-alb", Layer = "web" }
}

resource "aws_security_group" "app" {
  name        = "${local.name}-sg-app"
  description = "Solo el ALB llega a las EC2 App (Nginx frontend)"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = [80, 443]
    content {
      description     = "SG-ALB a App ${ingress.value}"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.alb.id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg-app", Layer = "app" }
}

resource "aws_security_group" "data" {
  name        = "${local.name}-sg-data"
  description = "Solo la capa App llega a MySQL (3306)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SG-APP a MySQL 3306"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg-data", Layer = "data" }
}

# ---------- ECR: 5 repositorios (frontend + 4 microservicios) ----------
# Las imagenes (arm64) las construye y publica la pipeline de GitHub Actions
# (.github/workflows/_docker-ecr.yml) o scripts/ecr-push.sh desde el PC.

resource "aws_ecr_repository" "app" {
  for_each = toset(local.services)

  name         = "${local.name}-${each.value}"
  force_delete = true # permite terraform destroy aunque queden imagenes

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${local.name}-${each.value}" }
}

# Conservar solo las ultimas 5 imagenes por repositorio (costo de almacenamiento).
resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantener las ultimas 5 imagenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ---------- Capa Data: EC2 MySQL 8.0 en data-1a con IP privada fija ----------
# La IP fija (10.0.2.10) permite que el user data del ASG no dependa del
# orden de creacion. Datos en /opt/freshbox/mysql-data sobre el EBS raiz cifrado.

resource "aws_instance" "mysql" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.mysql_instance_type
  subnet_id              = aws_subnet.data[0].id
  private_ip             = var.mysql_private_ip
  vpc_security_group_ids = [aws_security_group.data.id]
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 12
    encrypted   = true
    tags        = { Name = "${local.name}-ebs-mysql" }
  }

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  user_data = templatefile("${path.module}/templates/user_data_mysql.sh.tpl", {
    project_name  = local.name
    init_sql      = file("${path.module}/files/init.sql")
    root_password = var.db_root_password
    db_user       = var.db_user
    db_pass       = var.db_pass
    db_name       = var.db_name
  })

  tags = { Name = "${local.name}-ec2-mysql", Layer = "data" }
}

# ---------- Capa App: Launch Template + Auto Scaling Group (2-4) Multi-AZ ----------

resource "aws_launch_template" "app" {
  name                   = "${local.name}-lt-app"
  image_id               = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.app.id]
  update_default_version = true

  iam_instance_profile {
    name = data.aws_iam_instance_profile.lab.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 8
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  monitoring {
    enabled = true # metricas cada 1 min para el target tracking
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data_app.sh.tpl", {
    region       = var.aws_region
    account_id   = data.aws_caller_identity.current.account_id
    project_name = local.name
    image_tag    = var.image_tag
    db_host      = aws_instance.mysql.private_ip
    db_user      = var.db_user
    db_pass      = var.db_pass
    db_name      = var.db_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-ec2-app", Layer = "app" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${local.name}-ebs-app", Layer = "app" }
  }

  tags = { Name = "${local.name}-lt-app" }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name}-asg-app"
  min_size                  = var.asg_min_size
  desired_capacity          = var.asg_desired_capacity
  max_size                  = var.asg_max_size
  vpc_zone_identifier       = aws_subnet.app[*].id
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 900 # el user data reintenta el pull de ECR hasta ~20 min

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Reemplazo gradual cuando cambia el Launch Template; la pipeline tambien lo
  # (StartInstanceRefresh esta denegado por la SCP del Learner Lab: la pipeline
  # hace un rolling manual terminando las EC2 de a una tras publicar imagenes).
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-ec2-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Layer"
    value               = "app"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity] # lo gobierna la politica de escalado
  }
}

# Escalado por CPU promedio del grupo (target tracking).
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${local.name}-asg-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.asg_cpu_target
  }
}

# ---------- Capa publica: ALB internet-facing, 1 listener :80 -> TG :80 ----------
# Todo el trafico entra por el frontend (Nginx), que enruta /api/products a los
# 4 microservicios por la red Docker interna; asi la capa App solo abre 80/443.

resource "aws_lb" "main" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags               = { Name = "${local.name}-alb", Layer = "web" }
}

resource "aws_lb_target_group" "web" {
  name                 = "${local.name}-tg-web"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${local.name}-tg-web" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ---------- AWS Backup: snapshot diario de la EC2 MySQL (05:00 UTC, 7 dias) ----------
# Contingencia: restaurar el recovery point como nueva EC2 en data-1b.

resource "aws_backup_vault" "main" {
  name = "${local.name}-backup-vault"
  tags = { Name = "${local.name}-backup-vault" }
}

resource "aws_backup_plan" "main" {
  name = "${local.name}-backup-plan"

  rule {
    rule_name         = "${local.name}-daily-mysql"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 5 * * ? *)"

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }

  tags = { Name = "${local.name}-backup-plan" }
}

resource "aws_backup_selection" "mysql" {
  name         = "${local.name}-mysql-selection"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = data.aws_iam_role.lab.arn
  resources    = [aws_instance.mysql.arn]
}
