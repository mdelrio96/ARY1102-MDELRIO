# ---------- VPC Endpoint Gateway para DynamoDB (pauta EP3 2.2, 2.4 y 2.5, paso 9) ----------
# Agrega a la route table de la capa App una ruta hacia la lista de prefijos de
# DynamoDB: Lambda Process-Order llega a la tabla del carrito por la red de AWS,
# sin pasar por el NAT ni por Internet. Los endpoints Gateway no tienen costo.
# La capa Data no lo necesita (RDS no usa DynamoDB).
#
# La politica limita el endpoint a la tabla del carrito y a las operaciones que
# hace el codigo de las Lambdas.

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app.id]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "SoloTablaCarrito"
      Effect    = "Allow"
      Principal = "*"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:Query",
        "dynamodb:DeleteItem",
        "dynamodb:BatchWriteItem",
      ]
      Resource = [aws_dynamodb_table.carrito.arn]
    }]
  })

  tags = { Name = "${local.name}-vpce-dynamodb", Layer = "app" }
}
