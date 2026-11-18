# ============================================
# FreshBox SpA - Outputs (EP3, paso 1: base)
# Datos que necesitan los pasos siguientes (manifiestos de EKS, Lambdas y
# API Gateway).
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
  description = "URLs de los 4 repositorios ECR del backend."
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

output "dynamodb_table_name" {
  description = "Tabla del carrito (variable TABLE_NAME de las Lambdas)."
  value       = aws_dynamodb_table.carrito.name
}

output "dynamodb_table_arn" {
  description = "ARN de la tabla, para la politica IAM minima de las Lambdas."
  value       = aws_dynamodb_table.carrito.arn
}

output "sqs_queue_url" {
  description = "URL de la cola de ordenes (variable QUEUE_URL de Create-Order)."
  value       = aws_sqs_queue.ordenes.url
}

output "sqs_queue_arn" {
  description = "ARN de la cola de ordenes (trigger de Process-Order)."
  value       = aws_sqs_queue.ordenes.arn
}

output "sqs_dlq_arn" {
  value = aws_sqs_queue.ordenes_dlq.arn
}

output "lambda_function_names" {
  description = "Nombres de las 3 funciones Lambda."
  value       = { for k, f in aws_lambda_function.app : k => f.function_name }
}

output "lambda_invoke_arns" {
  description = "ARN de invocacion de cada Lambda, para las integraciones de API Gateway."
  value       = { for k, f in aws_lambda_function.app : k => f.invoke_arn }
}

output "sg_lambda_id" {
  value = aws_security_group.lambda.id
}

output "api_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "api_url" {
  description = "URL base de API Gateway (stage prod); el frontend la usa como API_URL."
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "api_stage" {
  value = aws_api_gateway_stage.prod.stage_name
}

output "frontend_bucket" {
  description = "Bucket del frontend; lo crea EV3/script/publicar-frontend.sh (no Terraform)."
  value       = "${local.name}-frontend-${data.aws_caller_identity.current.account_id}"
}

output "vpce_dynamodb_id" {
  value = aws_vpc_endpoint.dynamodb.id
}
