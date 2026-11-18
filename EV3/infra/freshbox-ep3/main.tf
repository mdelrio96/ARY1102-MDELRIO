# ============================================
# FreshBox SpA - Infraestructura EP3 (ARY1102 Arquitectura Cloud)
# Paso 1 de la arquitectura hibrida (EKS + Serverless): la base de EV2.
# La pauta EP3 (punto 2.2) permite reutilizar la red ya creada; aqui se recrea
# la misma red de tres capas (VPC /22, 6 subredes /25) con EKS y RDS MySQL
# Multi-AZ, que siguen atendiendo el CRUD de productos.
#
#   main.tf      backend, proveedores, roles del lab, nombres
#   network.tf   VPC, subredes, IGW, NAT, route tables
#   security.tf  SG-ALB -> SG-EKS -> SG-RDS (pauta 2.4)
#   ecr.tf       4 repositorios de imagenes backend (pauta 2.5, pasos 1 y 2)
#   eks.tf       cluster (Auto Mode solo para el ALB), node group t4g.small, add-ons;
#                opcional con create_eks
#   rds.tf       RDS MySQL db.t4g.small Multi-AZ cifrada con snapshots automaticos
#   dynamodb.tf  tabla carrito-freshbox con TTL de 24 h (pauta 2.5, paso 4)
#   sqs.tf       cola ordenes-freshbox y su DLQ con maxReceiveCount 3 (paso 5)
#   lambda.tf    Lambdas Cart, Create-Order y Process-Order con LabRole y el
#                trigger SQS (paso 6); SG-LAMBDA esta en security.tf
#   apigateway.tf  API REST freshbox-api, stage prod, 8 rutas + CORS (paso 7)
#   vpc_endpoint.tf  VPC Endpoint Gateway de DynamoDB en la capa App (paso 9)
#
# El bucket del frontend (paso 8, S3 Static Website) no es de Terraform: lo
# crean EV3/script/publicar-frontend.sh y bajar-frontend.sh, porque la SCP del
# Learner Lab impide leer buckets con el proveedor (ver EV1).
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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7" # empaqueta el codigo de las Lambdas en .zip
    }
  }

  # Mismo bucket y tabla de bloqueo que EV1 y EV2, con otra clave: los estados
  # conviven sin pisarse. Los crea EV2/script/bootstrap-tfstate.sh antes del
  # init (la SCP del Learner Lab impide gestionarlos con Terraform; ver EV1).
  # Para probar sin S3: terraform init -backend=false
  backend "s3" {
    bucket         = "freshbox-tfstate-870431978422" # freshbox-tfstate-<ID de cuenta del lab>
    key            = "freshbox/ep3/terraform.tfstate"
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
      Env       = "EP3"
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

  # Pauta EP3 2.5: 4 imagenes backend. El frontend sale de EKS y pasa a S3
  # Static Website (paso 8), asi que ya no lleva repositorio ECR.
  services = [
    "get-products",
    "create-product",
    "update-product",
    "delete-product",
  ]
}
