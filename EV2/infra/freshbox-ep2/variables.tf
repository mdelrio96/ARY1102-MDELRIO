# ============================================
# FreshBox SpA - Variables (EP2)
# Los valores por defecto son los de la pauta: VPC /22, Node Group t4g.small
# de 2 a 4 nodos, RDS MySQL db.t4g.small Multi-AZ.
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

# ---- Red (mismos CIDR que EV1) ----

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

# ---- EKS ----

variable "create_eks" {
  description = "Crea el cluster EKS (plano de control, node group y add-ons) junto con la base. false = solo red, SG, ECR y RDS."
  type        = bool
  default     = true
}

variable "cluster_version" {
  description = "Version de Kubernetes del cluster (la que valido el docente en el lab)."
  type        = string
  default     = "1.34"
}

variable "eks_public_access_cidrs" {
  description = "CIDR que pueden llegar a la API publica de EKS (ademas exige IAM). 0.0.0.0/0 permite usar kubectl desde GitHub Actions."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_type" {
  description = "Tipo de instancia del Node Group (pauta: t4g.small, Graviton arm64)."
  type        = string
  default     = "t4g.small"
}

variable "node_ami_type" {
  description = "AMI optimizada de EKS que corresponde al tipo de instancia (arm64 para t4g)."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_min_size" {
  type    = number
  default = 2
}

# Un t4g.small admite 11 pods (3 ENI x 3 IP + 2). Con los 10 pods de la app,
# CoreDNS, Metrics Server y los agentes de Container Insights, dos nodos quedan
# sin espacio para que el HPA agregue replicas; con tres sobra para la demo.
variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_disk_size" {
  description = "GB del volumen raiz (gp3 cifrado) de cada nodo."
  type        = number
  default     = 20
}

variable "enable_container_insights" {
  description = "Instala el add-on amazon-cloudwatch-observability (Container Insights)."
  type        = bool
  default     = true
}

# ---- Base de datos ----

variable "db_instance_class" {
  type    = string
  default = "db.t4g.small"
}

variable "db_engine_version" {
  description = "Version mayor de MySQL; RDS elige la menor vigente y la actualiza en la ventana de mantencion."
  type        = string
  default     = "8.0"
}

variable "db_name" {
  type    = string
  default = "freshbox"
}

variable "db_user" {
  type    = string
  default = "alumno"
}

variable "db_backup_retention_days" {
  description = "Dias que RDS conserva los snapshots automaticos (y el log para restaurar a un punto en el tiempo)."
  type        = number
  default     = 7
}
