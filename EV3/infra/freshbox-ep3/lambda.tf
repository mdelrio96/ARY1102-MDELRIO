# ---------- AWS Lambda: Cart, Create-Order y Process-Order (pauta EP3 2.2 y 2.5, paso 6) ----------
# Codigo en EV3/app/lambda: copia sin cambios del recurso AVA
# (desarrolloappEP3/lambda), con los nombres de la guia del docente.
#
# El runtime nodejs22.x ya trae el AWS SDK v3, asi que Cart y Create-Order se
# suben solo con su index.js. Process-Order necesita ademas mysql2: el pipeline
# (o quien aplique en local) corre "npm install --omit=dev" en
# EV3/app/lambda/procesar-orden antes del plan; si falta, el plan se detiene.
#
# Rol: AWS Academy no deja crear roles IAM, asi que las tres funciones asumen
# LabRole. La politica minima de cada una (pauta 1.3) se documenta en el informe.

data "aws_iam_role" "lab" {
  name = "LabRole"
}

locals {
  lambda_src = "${path.module}/../../app/lambda"

  # Clave = carpeta del codigo y sufijo del nombre de la funcion.
  lambdas = {
    "procesar-carrito" = {
      descripcion = "Lambda Cart: agrega, consulta y quita productos del carrito en DynamoDB"
      timeout     = 10
      en_vpc      = false
    }
    "crear-orden" = {
      descripcion = "Lambda Create-Order: calcula el total del carrito y publica la orden en SQS"
      timeout     = 10
      en_vpc      = false
    }
    "procesar-orden" = {
      descripcion = "Lambda Process-Order: consume SQS, registra la orden en RDS y vacia el carrito"
      timeout     = 30 # el visibility timeout de la cola (180 s) es 6 veces este valor
      en_vpc      = true
    }
  }

  # Variables de entorno que lee el codigo. Van aparte de local.lambdas porque
  # DB_PASS es sensible y un for_each no puede recorrer valores sensibles.
  lambda_env = {
    "procesar-carrito" = {
      TABLE_NAME = aws_dynamodb_table.carrito.name
    }
    "crear-orden" = {
      TABLE_NAME = aws_dynamodb_table.carrito.name
      QUEUE_URL  = aws_sqs_queue.ordenes.url
    }
    "procesar-orden" = {
      TABLE_NAME = aws_dynamodb_table.carrito.name
      DB_HOST    = aws_db_instance.main.address
      DB_PORT    = tostring(aws_db_instance.main.port)
      DB_NAME    = aws_db_instance.main.db_name
      DB_USER    = aws_db_instance.main.username
      DB_PASS    = random_password.db.result
    }
  }
}

data "archive_file" "lambda" {
  for_each = local.lambdas

  type        = "zip"
  source_dir  = "${local.lambda_src}/${each.key}"
  output_path = "${path.module}/.build/${each.key}.zip" # ignorado en git
}

# Grupos de logs creados por Terraform (y no por Lambda en la primera ejecucion)
# para fijar la retencion y que terraform destroy los borre.
resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.lambdas

  name              = "/aws/lambda/${local.name}-${each.key}"
  retention_in_days = 7

  tags = { Name = "${local.name}-${each.key}", Layer = "serverless" }
}

resource "aws_lambda_function" "app" {
  for_each = local.lambdas

  function_name = "${local.name}-${each.key}"
  description   = each.value.descripcion
  role          = data.aws_iam_role.lab.arn
  runtime       = "nodejs22.x"
  handler       = "index.handler"
  architectures = ["arm64"] # Graviton, como los nodos t4g: menor precio por GB-segundo
  memory_size   = 128
  timeout       = each.value.timeout

  filename         = data.archive_file.lambda[each.key].output_path
  source_code_hash = data.archive_file.lambda[each.key].output_base64sha256

  environment {
    variables = local.lambda_env[each.key]
  }

  # Solo Process-Order entra a la VPC (necesita RDS): una ENI en cada subred App.
  # Cart y Create-Order quedan fuera y llegan a DynamoDB y SQS por la red de AWS.
  dynamic "vpc_config" {
    for_each = each.value.en_vpc ? [1] : []
    content {
      subnet_ids         = aws_subnet.app[*].id
      security_group_ids = [aws_security_group.lambda.id]
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  lifecycle {
    precondition {
      condition     = each.key != "procesar-orden" || fileexists("${local.lambda_src}/procesar-orden/node_modules/mysql2/package.json")
      error_message = "Falta mysql2 en EV3/app/lambda/procesar-orden: ejecuta npm install --omit=dev en esa carpeta antes del plan."
    }
  }

  tags = { Name = "${local.name}-${each.key}", Layer = "serverless" }
}

# Trigger SQS -> Process-Order: el servicio Lambda lee la cola por lotes y borra
# los mensajes que la funcion procesa sin error. Un error devuelve el lote a la
# cola; al tercer intento fallido el mensaje pasa a la DLQ (sqs.tf).
resource "aws_lambda_event_source_mapping" "ordenes" {
  event_source_arn = aws_sqs_queue.ordenes.arn
  function_name    = aws_lambda_function.app["procesar-orden"].arn
  batch_size       = 10
  enabled          = true

  # El Learner Lab permite 10 ejecuciones simultaneas de Lambda en la cuenta: el
  # consumidor de la cola usa como maximo 2 y deja el resto a Cart y
  # Create-Order, que responden al usuario en linea.
  scaling_config {
    maximum_concurrency = 2
  }
}
