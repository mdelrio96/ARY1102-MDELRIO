# ---------- ECR: 5 repositorios (frontend + 4 microservicios) ----------
# Mismos nombres que en EV1 (freshbox-<servicio>): EP2 reemplaza a EP1, asi que
# los dos stacks no se levantan a la vez. Las imagenes linux/arm64 las publica
# el workflow ep2-freshbox.yaml (desplegar o actualizar-app) o EV2/app/scripts/ecr-push.sh.

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
