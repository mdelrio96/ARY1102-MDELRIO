# ============================================
# FreshBox SpA - Outputs (EP2)
# script/aplicar-k8s.sh los lee para completar los manifiestos de EV2/k8s.
# ============================================

output "aws_region" {
  value = var.aws_region
}

output "eks_enabled" {
  description = "true si este apply creo el cluster EKS (create_eks)."
  value       = var.create_eks
}

output "cluster_name" {
  description = "Nombre del cluster EKS (null si create_eks = false)."
  value       = var.create_eks ? aws_eks_cluster.main[0].name : null
}

output "kubeconfig_command" {
  description = "Configura kubectl contra el cluster."
  value       = var.create_eks ? "aws eks update-kubeconfig --name ${aws_eks_cluster.main[0].name} --region ${var.aws_region}" : null
}

output "node_group_name" {
  value = var.create_eks ? aws_eks_node_group.main[0].node_group_name : null
}

output "ecr_registry" {
  description = "Registro ECR de la cuenta."
  value       = local.registry
}

output "ecr_repository_urls" {
  description = "URLs de los 5 repositorios ECR."
  value       = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}

output "rds_endpoint" {
  description = "Host de RDS (sin puerto); no cambia tras un failover Multi-AZ."
  value       = aws_db_instance.main.address
}

output "rds_identifier" {
  value = aws_db_instance.main.identifier
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "db_user" {
  value = aws_db_instance.main.username
}

output "db_password" {
  description = "Clave de RDS; terraform output -raw db_password."
  value       = random_password.db.result
  sensitive   = true
}

output "sg_alb_id" {
  description = "SG-ALB, para la anotacion security-groups del Ingress."
  value       = aws_security_group.alb.id
}

output "sg_eks_id" {
  value = aws_security_group.eks.id
}

output "sg_rds_id" {
  value = aws_security_group.rds.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_ids" {
  value = {
    public = aws_subnet.public[*].id
    app    = aws_subnet.app[*].id
    data   = aws_subnet.data[*].id
  }
}
