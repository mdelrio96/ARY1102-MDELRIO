variable "aws_region" {
  description = "Region del Learner Lab (solo habilita us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Cluster EKS de EV2/infra/freshbox-ep2 (local.cluster_name)."
  type        = string
  default     = "freshbox-cluster"
}

variable "availability_zone" {
  description = "Zona de la subred por defecto donde va la maquina (t4g existe en us-east-1a)."
  type        = string
  default     = "us-east-1a"
}

variable "instance_type" {
  description = "Tipo de la maquina de carga (Graviton: la AMI y los binarios son arm64)."
  type        = string
  default     = "t4g.small"

  validation {
    condition     = can(regex("^t4g\\.(small|medium|large)$", var.instance_type))
    error_message = "Usa t4g.small, t4g.medium o t4g.large (arm64 y dentro de los tipos que admite el lab)."
  }
}

variable "k6_version" {
  description = "Version de k6 que se descarga de GitHub (grafana/k6)."
  type        = string
  default     = "v1.0.0"
}
