# ---------- SQS: cola de ordenes + DLQ (pauta EP3 2.2 y 2.5, paso 5) ----------
# Desacopla Lambda Create-Order (publica) de Lambda Process-Order (consume y
# registra en RDS). Segun la guia del docente: cola ordenes-freshbox con una DLQ
# y maxReceiveCount = 3, es decir, un mensaje que falla 3 veces pasa a la DLQ.
#
# El trigger SQS -> Lambda Process-Order se crea junto con la funcion Lambda.

# Cola de mensajes fallidos: se crea primero porque la cola principal la referencia.
resource "aws_sqs_queue" "ordenes_dlq" {
  name                      = "ordenes-${local.name}-dlq"
  message_retention_seconds = 1209600 # 14 dias (maximo): tiempo para revisar las ordenes fallidas
  sqs_managed_sse_enabled   = true

  tags = { Name = "ordenes-${local.name}-dlq", Layer = "serverless" }
}

resource "aws_sqs_queue" "ordenes" {
  name = "ordenes-${local.name}"

  # Debe superar el timeout de Process-Order: AWS recomienda al menos 6 veces el
  # de la funcion (30 s en el paso de las Lambdas = 180 s); si no, un mensaje
  # que sigue en proceso vuelve a la cola y se registra dos veces en RDS.
  visibility_timeout_seconds = 180
  sqs_managed_sse_enabled    = true # cifrado en reposo administrado por SQS, sin costo

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ordenes_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "ordenes-${local.name}", Layer = "serverless" }
}

# Solo la cola de ordenes puede enviar mensajes a la DLQ.
resource "aws_sqs_queue_redrive_allow_policy" "ordenes_dlq" {
  queue_url = aws_sqs_queue.ordenes_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.ordenes.arn]
  })
}
