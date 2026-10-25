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

# El Node Group parte con el minimo: el HPA agrega replicas dentro de estos dos
# nodos (prefix delegation y los requests de 64Mi lo permiten). Llegar a 3 o 4
# nodos es un cambio manual (sin Cluster Autoscaler en el lab).
variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

# Sin prefix delegation un t4g.small admite 11 pods (3 ENI x 3 IP + 2) y en dos
# nodos no caben los 10 pods de la app junto a los de sistema. Con prefijos EKS
# sube maxPods a 110 y el limite pasa a ser la CPU: unos 2 vCPU por nodo dan
# para ~12 pods de la app (100m cada uno) mas ~7 de sistema. La reserva de
# memoria del kubelet se calcula para 24 pods, con margen sobre esa cifra.
variable "node_pods_reserva" {
  description = "Pods por nodo para los que se reserva memoria del kubelet (255Mi + 11Mi por pod)."
  type        = number
  default     = 24

  validation {
    condition     = var.node_pods_reserva >= 11 && var.node_pods_reserva <= 110
    error_message = "node_pods_reserva debe estar entre 11 y 110 (maxPods que EKS admite en instancias de menos de 30 vCPU)."
  }
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
