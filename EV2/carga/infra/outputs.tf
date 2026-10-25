output "instance_id" {
  description = "ID de la maquina de carga."
  value       = aws_instance.carga.id
}

output "public_ip" {
  description = "IP publica de la maquina de carga."
  value       = aws_instance.carga.public_ip
}

output "conectar_url" {
  description = "Consola EC2 > Connect (Session Manager o EC2 Instance Connect), con la sesion del lab abierta."
  value       = "https://${var.aws_region}.console.aws.amazon.com/ec2/home?region=${var.aws_region}#ConnectToInstance:instanceId=${aws_instance.carga.id}"
}
