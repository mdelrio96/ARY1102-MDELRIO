# ---------- DynamoDB: carrito temporal con TTL (pauta EP3 2.2 y 2.5, paso 4) ----------
# Lo usan las tres Lambdas (Cart escribe, consulta y borra; Create-Order consulta;
# Process-Order consulta y vacia el carrito al registrar la orden). El nombre, la
# clave y el atributo de expiracion salen del codigo de las Lambdas
# (EA3/desarrolloappEP3/lambda): TABLE_NAME = carrito-freshbox, clave userId +
# productId (ambos String) y expiresAt en segundos epoch (ahora + 24 h).
#
# Modo on-demand: el carrito no tiene trafico predecible y no hay capacidad que
# aprovisionar ni pagar en reposo (pay-per-use, como el resto de la capa serverless).
# El cifrado en reposo viene activo por defecto (clave propiedad de AWS).

resource "aws_dynamodb_table" "carrito" {
  name         = "carrito-${local.name}"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "userId"
  range_key = "productId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "productId"
    type = "S"
  }

  # DynamoDB borra solo los items cuyo expiresAt ya paso (en general en las
  # horas siguientes al vencimiento): el carrito abandonado expira a las 24 h.
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  deletion_protection_enabled = false # laboratorio: se destruye al terminar la sesion

  tags = { Name = "carrito-${local.name}", Layer = "serverless" }
}
