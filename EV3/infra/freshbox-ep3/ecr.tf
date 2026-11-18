# ---------- ECR: 4 repositorios (microservicios backend del CRUD) ----------
# Mismos nombres que en EV1 y EV2 (freshbox-<servicio>): EP3 reemplaza a EP2,
# asi que los dos stacks no se levantan a la vez. El repositorio del frontend
# ya no se crea porque el sitio pasa a S3 Static Website (pauta EP3 2.5, paso 8).
# Las imagenes linux/arm64 se publican despues (pauta 2.5, pasos 1 y 2).

resource "aws_ecr_repository" "app" {
  for_each = toset(local.services)

  name                 = "${local.name}-${each.value}"
  image_tag_mutability = "MUTABLE" # latest se mueve; cada version tiene ademas su tag propio
  force_delete         = true      # permite terraform destroy aunque queden imagenes

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${local.name}-${each.value}", Layer = "app" }
}

# Conservar solo las ultimas 10 imagenes por repositorio (costo de almacenamiento).
resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantener las ultimas 10 imagenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
