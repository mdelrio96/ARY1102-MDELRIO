# ---------- Security Groups encadenados (matriz de la pauta EP3, punto 2.4) ----------
#   SG-ALB : 80, 443 desde 0.0.0.0/0
#   SG-EKS : 80, 443 solo desde SG-ALB      (pods y nodos; el ALB envia a la IP del pod)
#   SG-RDS    : 3306 solo desde SG-EKS y SG-LAMBDA
#   SG-LAMBDA : sin entrada; sale solo a RDS 3306 y a DynamoDB 443
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
  description = "Solo EKS y Lambda Process-Order llegan a MySQL 3306"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SG-EKS a MySQL 3306"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.eks.id]
  }

  ingress {
    description     = "SG-LAMBDA a MySQL 3306"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  tags = { Name = "${local.name}-sg-rds", Layer = "data" }
}

# Lambda Process-Order corre dentro de la VPC (subredes App) para llegar a RDS.
# Sin reglas de entrada: nadie abre conexiones hacia la funcion (el trigger de
# SQS lo opera el servicio Lambda fuera de la VPC). Las salidas van como reglas
# separadas porque SG-RDS ya referencia a este grupo (en linea seria un ciclo).
# Terraform quita la regla de salida "todo permitido" que AWS crea por defecto.
resource "aws_security_group" "lambda" {
  name        = "${local.name}-sg-lambda"
  description = "Lambda Process-Order: sin entrada, sale a RDS y DynamoDB"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-sg-lambda", Layer = "app" }
}

resource "aws_vpc_security_group_egress_rule" "lambda_rds" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "SG-LAMBDA a MySQL 3306"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.rds.id
}

# DynamoDB por HTTPS (vaciar el carrito). La lista de prefijos administrada por
# AWS cubre las IP del servicio: sirve hoy por el NAT y despues por el VPC
# Endpoint Gateway (pauta 2.5, paso 9) sin cambiar la regla.
data "aws_ec2_managed_prefix_list" "dynamodb" {
  name = "com.amazonaws.${var.aws_region}.dynamodb"
}

resource "aws_vpc_security_group_egress_rule" "lambda_dynamodb" {
  security_group_id = aws_security_group.lambda.id
  description       = "SG-LAMBDA a DynamoDB 443"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.dynamodb.id
}
