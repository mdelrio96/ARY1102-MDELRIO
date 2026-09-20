# ============================================
# FreshBox SpA - Variables (EP1)
# Los valores por defecto son los del caso FreshBox (VPC /22, SG por capa, ASG 2-4, t4g.small).
# ============================================

variable "aws_region" {
  description = "Region del Learner Lab (solo habilita us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo de nombres y etiquetas."
  type        = string
  default     = "freshbox"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

# ---- Red ----

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/22"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/25", "10.0.0.128/25"]
}

variable "app_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/25", "10.0.1.128/25"]
}

variable "data_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.2.0/25", "10.0.2.128/25"]
}

variable "mysql_private_ip" {
  description = "IP privada fija de la EC2 MySQL (debe pertenecer a data_subnet_cidrs[0])."
  type        = string
  default     = "10.0.2.10"
}

# ---- Computo ----

variable "instance_type" {
  description = "Tipo de instancia de la capa App. Fallback si el lab rechaza t4g: t3.small + instance_arch=x86_64 + imagenes linux/amd64."
  type        = string
  default     = "t4g.small"
}

variable "mysql_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "instance_arch" {
  description = "Arquitectura de la AMI (arm64 para t4g/Graviton, x86_64 para t3)."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.instance_arch)
    error_message = "instance_arch debe ser arm64 o x86_64."
  }
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_cpu_target" {
  description = "CPU promedio objetivo (%) de la politica target tracking."
  type        = number
  default     = 60
}

variable "image_tag" {
  description = "Tag de las imagenes ECR que descargan las EC2 App."
  type        = string
  default     = "latest"
}

# ---- Learner Lab ----

variable "lab_instance_profile_name" {
  description = "Instance Profile que AWS Academy ya crea (IAM > Instance profiles)."
  type        = string
  default     = "LabInstanceProfile"
}

variable "lab_role_name" {
  description = "Role que AWS Academy ya crea (lo usa AWS Backup)."
  type        = string
  default     = "LabRole"
}

# ---- Base de datos ----

variable "db_name" {
  type    = string
  default = "freshbox"
}

variable "db_user" {
  type    = string
  default = "alumno"
}

variable "db_pass" {
  type      = string
  default   = "alumno123"
  sensitive = true
}

variable "db_root_password" {
  type      = string
  default   = "root123"
  sensitive = true
}

variable "backup_retention_days" {
  type    = number
  default = 7
}
