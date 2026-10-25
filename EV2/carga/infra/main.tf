# ============================================
# FreshBox EP2 - Maquina de carga (demo de escalado, fuera de la evaluacion)
# EC2 en la VPC por defecto del lab, fuera de la red de FreshBox: ataca el ALB
# publico como un cliente real y corre el Cluster Autoscaler del node group.
#
# El autoscaler vive aqui y no en el cluster porque el lab no deja crear roles:
# LabEksNodeRole no tiene permisos de autoscaling y LabRole (que si los tiene)
# no confia en Pod Identity. Esta EC2 asume LabRole por LabInstanceProfile y
# entra al cluster con un access entry de ese rol.
#
# Estado propio (otra clave del mismo bucket): se crea y se borra sin tocar
# EKS ni RDS. No lee el cluster con un data source para que el destroy funcione
# aunque el cluster ya no exista.
# ============================================

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket         = "freshbox-tfstate-870431978422" # el mismo de EV2/infra/freshbox-ep2
    key            = "freshbox/ep2-carga/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "freshbox-tfstate-lock"
    use_lockfile   = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "FreshBox"
      Env       = "EP2-carga"
      ManagedBy = "terraform"
    }
  }
}

data "aws_iam_role" "lab" {
  name = "LabRole"
}

data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_az" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "availability-zone"
    values = [var.availability_zone]
  }
}

data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-*-arm64"]
  }
}

# Rangos del servicio EC2 Instance Connect: permite entrar desde la consola
# (respaldo de Session Manager) sin abrir el puerto 22 a Internet.
data "aws_ec2_managed_prefix_list" "instance_connect" {
  name = "com.amazonaws.${var.aws_region}.ec2-instance-connect"
}

# ---------- Acceso de LabRole al cluster (kubectl y Cluster Autoscaler) ----------

resource "aws_eks_access_entry" "carga" {
  cluster_name  = var.cluster_name
  principal_arn = data.aws_iam_role.lab.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "carga" {
  cluster_name  = var.cluster_name
  principal_arn = aws_eks_access_entry.carga.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ---------- Maquina de carga ----------

resource "aws_security_group" "carga" {
  name        = "freshbox-carga-sg"
  description = "Maquina de carga: SSH solo desde EC2 Instance Connect; salida libre"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "SSH desde EC2 Instance Connect (consola)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.instance_connect.id]
  }

  egress {
    description = "Salida a Internet (ALB, API de EKS, descargas)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "freshbox-carga-sg" }
}

resource "aws_instance" "carga" {
  ami                         = data.aws_ami.al2023_arm64.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default_az.ids[0]
  vpc_security_group_ids      = [aws_security_group.carga.id]
  iam_instance_profile        = data.aws_iam_instance_profile.lab.name
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 16
    encrypted   = true
    tags        = { Name = "freshbox-carga-ebs" }
  }

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  # Comprimido: los tres scripts van dentro y el user data sin comprimir se
  # acerca al limite de 16 KB.
  user_data_base64 = base64gzip(templatefile("${path.module}/user_data.sh.tpl", {
    region       = var.aws_region
    cluster_name = var.cluster_name
    k6_version   = var.k6_version
    carga_js     = base64encode(file("${path.module}/../scripts/carga.js"))
    demo_sh      = base64encode(file("${path.module}/../scripts/freshbox-demo.sh"))
    vigilar_sh   = base64encode(file("${path.module}/../scripts/freshbox-vigilar.sh"))
  }))
  user_data_replace_on_change = true

  tags = { Name = "freshbox-carga" }

  # Al arrancar ya usa kubectl y el autoscaler: el access entry debe existir.
  depends_on = [aws_eks_access_policy_association.carga]

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.default_az.ids) > 0
      error_message = "La VPC por defecto no tiene subred en la zona indicada (variable availability_zone)."
    }
  }
}
