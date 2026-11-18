# ---------- API Gateway REST: fachada unica de la app (pauta EP3 2.2, 2.3 y 2.5, paso 7) ----------
# freshbox-api, stage prod, con las 8 rutas de la guia del docente:
#   /api/products          GET, POST     -> ALB de EKS (HTTP_PROXY)
#   /api/products/{id}     PUT, DELETE   -> ALB de EKS (HTTP_PROXY)
#   /api/cart              GET, POST     -> Lambda Cart (AWS_PROXY)
#   /api/cart/{productId}  DELETE        -> Lambda Cart (AWS_PROXY)
#   /api/orders            POST          -> Lambda Create-Order (AWS_PROXY)
# mas OPTIONS (CORS) en cada recurso, porque el frontend se sirve desde otro
# origen (S3 Static Website).
#
# El ALB lo crea el Ingress de EKS al aplicar los manifiestos, no Terraform, asi
# que su DNS no se conoce en el apply. Las integraciones lo leen de la variable
# de stage albHost: el workflow la actualiza despues de crear el Ingress
# (aws apigateway update-stage) y Terraform no la vuelve a tocar.
# La integracion con el ALB va por HTTP 80 sobre Internet: el lab no tiene
# certificado ACM y el diseno no incluye VPC Link (mejora propuesta en el informe).

resource "aws_api_gateway_rest_api" "main" {
  name        = "${local.name}-api"
  description = "FreshBox EP3: productos por el ALB de EKS, carrito y ordenes por Lambda"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = { Name = "${local.name}-api", Layer = "api" }
}

# ---------- Recursos (rutas) ----------

resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "products" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "products"
}

resource "aws_api_gateway_resource" "product_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.products.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "cart" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "cart"
}

resource "aws_api_gateway_resource" "cart_product" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.cart.id
  path_part   = "{productId}"
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "orders"
}

locals {
  # Cada recurso con su ruta completa (para la URL del ALB) y los metodos que
  # anuncia en CORS.
  api_recursos = {
    products     = { id = aws_api_gateway_resource.products.id, path = "/api/products", metodos = "GET,POST,OPTIONS" }
    product_id   = { id = aws_api_gateway_resource.product_id.id, path = "/api/products/{id}", metodos = "PUT,DELETE,OPTIONS" }
    cart         = { id = aws_api_gateway_resource.cart.id, path = "/api/cart", metodos = "GET,POST,OPTIONS" }
    cart_product = { id = aws_api_gateway_resource.cart_product.id, path = "/api/cart/{productId}", metodos = "DELETE,OPTIONS" }
    orders       = { id = aws_api_gateway_resource.orders.id, path = "/api/orders", metodos = "POST,OPTIONS" }
  }

  # Las 8 rutas. destino = "alb" o la clave de la funcion en local.lambdas.
  api_rutas = {
    "GET /api/products"            = { recurso = "products", metodo = "GET", destino = "alb" }
    "POST /api/products"           = { recurso = "products", metodo = "POST", destino = "alb" }
    "PUT /api/products/{id}"       = { recurso = "product_id", metodo = "PUT", destino = "alb" }
    "DELETE /api/products/{id}"    = { recurso = "product_id", metodo = "DELETE", destino = "alb" }
    "GET /api/cart"                = { recurso = "cart", metodo = "GET", destino = "procesar-carrito" }
    "POST /api/cart"               = { recurso = "cart", metodo = "POST", destino = "procesar-carrito" }
    "DELETE /api/cart/{productId}" = { recurso = "cart_product", metodo = "DELETE", destino = "procesar-carrito" }
    "POST /api/orders"             = { recurso = "orders", metodo = "POST", destino = "crear-orden" }
  }

  # Funciones que invoca API Gateway (para sus permisos).
  api_lambdas = toset([for r in values(local.api_rutas) : r.destino if r.destino != "alb"])

  lambda_invoke_arns = { for k, f in aws_lambda_function.app : k => f.invoke_arn }
}

# ---------- Metodos e integraciones de las 8 rutas ----------

resource "aws_api_gateway_method" "ruta" {
  for_each = local.api_rutas

  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = local.api_recursos[each.value.recurso].id
  http_method   = each.value.metodo
  authorization = "NONE"

  # {id} se declara para copiarlo en la URL del ALB; las Lambdas reciben sus
  # parametros de ruta solas (integracion proxy).
  request_parameters = { for k, v in { "method.request.path.id" = true } : k => v if each.value.recurso == "product_id" }
}

resource "aws_api_gateway_integration" "ruta" {
  for_each = local.api_rutas

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_method.ruta[each.key].resource_id
  http_method = aws_api_gateway_method.ruta[each.key].http_method

  # ALB: HTTP_PROXY con el mismo metodo y la misma ruta (el Ingress reparte por
  # metodo a cada microservicio). Lambda: AWS_PROXY, que siempre invoca con POST
  # y entrega metodo, ruta, query y cuerpo dentro del evento.
  type                    = each.value.destino == "alb" ? "HTTP_PROXY" : "AWS_PROXY"
  integration_http_method = each.value.destino == "alb" ? each.value.metodo : "POST"
  uri = (each.value.destino == "alb"
    ? "http://$${stageVariables.albHost}${local.api_recursos[each.value.recurso].path}"
  : lookup(local.lambda_invoke_arns, each.value.destino, ""))

  request_parameters = { for k, v in { "integration.request.path.id" = "method.request.path.id" } : k => v if each.value.recurso == "product_id" }
}

resource "aws_lambda_permission" "apigw" {
  for_each = local.api_lambdas

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ---------- CORS ----------
# Preflight OPTIONS resuelto en API Gateway (MOCK, sin backend). Las respuestas
# normales ya traen Access-Control-Allow-Origin: las Lambdas lo agregan en su
# funcion resp() y los microservicios usan el middleware cors().

resource "aws_api_gateway_method" "options" {
  for_each = local.api_recursos

  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = each.value.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  for_each = local.api_recursos

  rest_api_id       = aws_api_gateway_rest_api.main.id
  resource_id       = aws_api_gateway_method.options[each.key].resource_id
  http_method       = aws_api_gateway_method.options[each.key].http_method
  type              = "MOCK"
  request_templates = { "application/json" = jsonencode({ statusCode = 200 }) }
}

resource "aws_api_gateway_method_response" "options" {
  for_each = local.api_recursos

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_method.options[each.key].resource_id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  for_each = local.api_recursos

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_method.options[each.key].resource_id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'${each.value.metodos}'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.options]
}

# Errores que genera API Gateway (4XX/5XX propios, p. ej. timeout del ALB) con el
# encabezado CORS, para que el navegador muestre el error en vez de bloquearlo.
resource "aws_api_gateway_gateway_response" "cors" {
  for_each = toset(["DEFAULT_4XX", "DEFAULT_5XX"])

  rest_api_id   = aws_api_gateway_rest_api.main.id
  response_type = each.value

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type'"
  }
}

# ---------- Despliegue y stage prod ----------

# Una foto de la configuracion: se rehace cuando cambia una ruta, una
# integracion o la respuesta CORS (si no, prod seguiria con la version anterior).
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      local.api_rutas,
      [for k, i in aws_api_gateway_integration.ruta : i.uri],
      values(aws_api_gateway_method.ruta)[*].id,
      values(aws_api_gateway_integration.options)[*].id,
      values(aws_api_gateway_integration_response.options)[*].id,
      values(aws_api_gateway_gateway_response.cors)[*].id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.ruta,
    aws_api_gateway_integration_response.options,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = "prod"

  variables = {
    albHost = var.alb_dns_name
  }

  tags = { Name = "${local.name}-api-prod", Layer = "api" }

  # albHost lo actualiza el workflow cuando el Ingress ya creo el ALB.
  lifecycle {
    ignore_changes = [variables]
  }
}
