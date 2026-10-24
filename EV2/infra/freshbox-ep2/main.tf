# ============================================
# FreshBox SpA - Infraestructura EP2 (ARY1102 Arquitectura Cloud)
# Modernizacion de EP1: contenedores en Amazon EKS y base de datos en RDS MySQL
# Multi-AZ, sobre la misma red de tres capas de EV1 (VPC /22, 6 subredes /25).
#
#   main.tf      backend, proveedores, roles del lab, nombres
#   network.tf   VPC, subredes, IGW, NAT, route tables
#   security.tf  SG-ALB -> SG-EKS -> SG-RDS (matriz de la pauta 2.4)
#   ecr.tf       5 repositorios de imagenes
#   eks.tf       cluster (Auto Mode solo para el ALB), node group t4g.small, add-ons;
#                opcional con create_eks
#   rds.tf       RDS MySQL db.t4g.small Multi-AZ cifrada con snapshots automaticos
# ============================================

terraform {
  required_version = ">= 1.10.0" # use_lockfile del backend S3

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # compute_config / storage_config de EKS Auto Mode
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Mismo bucket y tabla de bloqueo que EV1, con otra clave: los dos estados
  # conviven sin pisarse. Los crea EV2/script/bootstrap-tfstate.sh antes del
  # init (la SCP del Learner Lab impide gestionarlos con Terraform; ver EV1).
  # Para probar sin S3: terraform init -backend=false
  backend "s3" {
    bucket         = "freshbox-tfstate-870431978422" # freshbox-tfstate-<ID de cuenta del lab>
    key            = "freshbox/ep2/terraform.tfstate"
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
      Env       = "EP2"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# AWS Academy no permite crear roles IAM. El lab ya trae uno para el plano de
# control de EKS y otro para los nodos; sus nombres llevan un prefijo y un
# sufijo aleatorios por cuenta, asi que se buscan por la parte fija.
data "aws_iam_roles" "eks_cluster" {
  name_regex = "LabEksClusterRole"
}

data "aws_iam_roles" "eks_nodes" {
  name_regex = "LabEksNodeRole"
}

locals {
  name         = var.project_name
  cluster_name = "${var.project_name}-cluster"
  registry     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  az_suffix    = ["1a", "1b"]
  eks_count    = var.create_eks ? 1 : 0

  eks_cluster_role_arn = one(data.aws_iam_roles.eks_cluster.arns)
  eks_node_role_arn    = one(data.aws_iam_roles.eks_nodes.arns)

  services = [
    "frontend",
    "get-products",
    "create-product",
    "update-product",
    "delete-product",
  ]
}
