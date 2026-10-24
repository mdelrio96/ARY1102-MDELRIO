# ---------- Security Groups encadenados (matriz de la pauta EP2, punto 2.4) ----------
#   SG-ALB : 80, 443 desde 0.0.0.0/0
#   SG-EKS : 80, 443 solo desde SG-ALB      (pods y nodos; el ALB envia a la IP del pod)
#   SG-RDS : 3306 solo desde SG-EKS
# SG-ALB lo usa el ALB del Ingress (anotacion security-groups). SG-EKS va en el
# launch template de los nodos junto al SG del cluster, que sigue cubriendo el
# trafico nodo <-> nodo y plano de control <-> nodo. Los pods comparten la ENI
# de su nodo, asi que salen hacia RDS con SG-EKS como origen.

resource "aws_security_group" "alb" {
  name        = "${local.name}-sg-alb"
  description = "HTTP/HTTPS desde Internet hacia el ALB del Ingress"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = [80, 443]
    content {
      description = "Internet a ALB ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg-alb", Layer = "web" }
}

# Sin la etiqueta kubernetes.io/cluster/<cluster>: el controlador del ALB espera
# encontrar exactamente un SG etiquetado en la ENI del pod (el del cluster).
resource "aws_security_group" "eks" {
  name        = "${local.name}-sg-eks"
  description = "Nodos y pods EKS: solo el ALB llega a 80/443"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = [80, 443]
    content {
      description     = "SG-ALB a pods ${ingress.value}"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.alb.id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg-eks", Layer = "app" }
}

# Sin reglas de salida: RDS responde por la misma conexion y la replicacion
# Multi-AZ la gestiona AWS fuera de este grupo.
resource "aws_security_group" "rds" {
  name        = "${local.name}-sg-rds"
  description = "Solo los pods de EKS llegan a MySQL 3306"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SG-EKS a MySQL 3306"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.eks.id]
  }

  tags = { Name = "${local.name}-sg-rds", Layer = "data" }
}
