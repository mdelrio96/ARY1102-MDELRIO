# ============================================
# FreshBox SpA - Outputs (EP1)
# ============================================

output "alb_dns_name" {
  description = "DNS publico del ALB."
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "URL del frontend (y de /api/products) por el ALB."
  value       = "http://${aws_lb.main.dns_name}"
}

output "asg_name" {
  description = "Nombre del Auto Scaling Group."
  value       = aws_autoscaling_group.app.name
}

output "launch_template_id" {
  value = aws_launch_template.app.id
}

output "ecr_registry" {
  description = "Registro ECR de la cuenta."
  value       = local.registry
}

output "ecr_repository_urls" {
  description = "URLs de los 5 repositorios ECR."
  value       = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}

output "mysql_private_ip" {
  value = aws_instance.mysql.private_ip
}

output "mysql_instance_id" {
  description = "ID de la EC2 MySQL (Session Manager)."
  value       = aws_instance.mysql.id
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
