# EV1 — EP1 ARY1102 · FreshBox SpA

Arquitectura TO-BE de tres capas en AWS (Academy Learner Lab) para el catálogo online de FreshBox: VPC `10.0.0.0/22` con seis subredes `/25` en dos AZ, ALB, Auto Scaling Group (2–4 EC2 `t4g.small` con Docker: frontend Nginx + 4 microservicios), EC2 MySQL con AWS Backup y Security Groups por capa. Infraestructura con Terraform, desplegada desde GitHub Actions **sin push** (Actions → Run workflow).

## Diagrama TO-BE

[![Diagrama TO-BE FreshBox](diagramas/D1_FreshBox_TOBE.png)](diagramas/D1_FreshBox_TOBE.png)

Editable en [`diagramas/D1_FreshBox_TOBE.drawio`](diagramas/D1_FreshBox_TOBE.drawio) (draw.io) y publicado también en [Eraser.io](https://app.eraser.io/workspace/gSCDj5OUcicVftci9FlG?diagram=QsxnEutyEokrQdSwhicx&layout=canvas).

```
.gitattributes                     finales de línea LF en todo el repo: los .sh y .tpl corren en Linux (ver README raíz)
.github/workflows/                 (raíz del repo; GitHub solo los lee ahí)
├── ep1-deploy.yaml                EP1 · Desplegar FreshBox (infra + app)   ← Run workflow
├── ep1-provision-freshbox.yaml    EP1 · Infraestructura: backend de estado → apply | destroy | plan (reutilizable + Run workflow)
├── ep1-bootstrap-tfstate.yaml     EP1 · Backend de estado: bucket S3 + tabla DynamoDB si no existen (reutilizable + Run workflow)
├── ep1-deploy-app-ecr.yaml        plantilla: build arm64 → ECR → rolling de EC2 App → smoke test
└── ep1-validate.yaml              CI: terraform validate + docker build sin publicar
EV1/
├── infra/freshbox-ep1/            Terraform (main.tf, variables.tf, outputs.tf, templates/, files/)
├── app/                           frontend Nginx + 4 microservicios Node + init.sql + compose
├── script/bootstrap-tfstate.sh    crea el bucket S3 del estado y la tabla DynamoDB de bloqueo si no existen (tras un reset del lab)
└── diagramas/                     D1 TO-BE (draw.io + PNG; enlace a Eraser en su README)
```

## Flujo de despliegue

```
Run workflow "EP1 · Desplegar" ──► backend de estado (S3 + DynamoDB) ──► infra (terraform apply) ──► app (5× build arm64 → ECR) ──► rolling de EC2 App + curl al ALB
```

Las plantillas se invocan con `uses: ./.github/workflows/...` (mismo repo). `ep1-provision-freshbox.yaml` también tiene su propio *Run workflow* para levantar, bajar (`destroy`) o revisar (`plan`) solo la infraestructura; en cualquiera de los tres casos su primer job es `ep1-bootstrap-tfstate.yaml`, que deja listos el bucket de estado y la tabla de bloqueo antes de `terraform init`. Ese workflow también se puede lanzar solo (*EP1 · Backend de estado*) para preparar el backend antes de levantar nada.

## Cada sesión del Learner Lab

Las credenciales del lab duran una sesión (~4 h) y no admiten OIDC (no se pueden crear roles IAM); por eso van como secretos del repo (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) y se renuevan en cada sesión:

1. Iniciar el lab → **AWS Details → AWS CLI: Show**: ahí están los tres valores.
2. GitHub → **Settings → Secrets and variables → Actions** → actualizar los tres secretos con esos valores.
3. Actions → **EP1 · Desplegar FreshBox (infra + app)** → Run workflow: backend de estado → infra → app en un solo run. El resumen final muestra la URL del ALB.
4. Al terminar: Actions → **EP1 · Infraestructura** → `destroy`. Todo desaparece y no consume créditos; solo quedan el bucket de estado (`freshbox-tfstate-870431978422`) y la tabla de bloqueo (`freshbox-tfstate-lock`), vacíos y sin costo. Si un *reset* del lab los borra, el job *backend de estado* los vuelve a crear antes del siguiente `init` (`script/bootstrap-tfstate.sh`; ver `infra/freshbox-ep1/README.md`).

Si un job falla con `ExpiredToken`, repetir el paso 2 y relanzar. En el PC, el mismo bloque va en `~/.aws/credentials`.

## Ejecución local desde un clon (sin GitHub Actions)

Para levantar y probar la infraestructura en otra cuenta de Learner Lab, sin tocar los workflows. Son los mismos comandos que ejecuta la pipeline.

Requisitos: Git, Terraform ≥ 1.10 (la pipeline usa 1.15.8), AWS CLI v2, Docker con Buildx (Docker Desktop lo incluye; en Linux hace falta además `qemu-user-static` para construir imágenes arm64) y bash (en Windows, Git Bash). Un Learner Lab iniciado, con el bloque de **AWS Details → AWS CLI: Show** pegado en `~/.aws/credentials`.

1. Clonar y entrar al repositorio:

   ```bash
   git clone https://github.com/mdelrio96/ARY1102-MDELRIO.git && cd ARY1102-MDELRIO
   ```

2. Backend de estado. El nombre del bucket termina en el ID de la cuenta, así que en otra cuenta el script se detiene y dice qué nombre poner en `EV1/infra/freshbox-ep1/main.tf` (línea `bucket = ...`); al ejecutarlo de nuevo crea el bucket y la tabla de bloqueo:

   ```bash
   ./EV1/script/bootstrap-tfstate.sh
   ```

   Alternativa para una prueba rápida, sin S3 ni DynamoDB: un archivo *override* que reemplaza el bloque `backend` sin editar `main.tf`; el estado queda en `terraform.tfstate` dentro de la carpeta (`.gitignore` ignora ambos archivos):

   ```bash
   printf 'terraform {\n  backend "local" {}\n}\n' > EV1/infra/freshbox-ep1/local_override.tf
   ```

3. Infraestructura (unos 4 minutos):

   ```bash
   terraform -chdir=EV1/infra/freshbox-ep1 init
   terraform -chdir=EV1/infra/freshbox-ep1 apply
   ```

   Si el lab rechaza `t4g`: `apply -var instance_type=t3.small -var mysql_instance_type=t3.small -var instance_arch=x86_64` y, en el paso 4, `PLATFORM=linux/amd64`.

4. Imágenes a ECR (los repositorios los creó Terraform; el script toma cuenta y región de las credenciales):

   ```bash
   cd EV1/app && ./scripts/ecr-push.sh && cd ../..
   ```

   En un primer despliegue no hay nada más que hacer: las EC2 App reintentan el `docker pull` hasta 20 minutos y arrancan solas cuando las imágenes están. Solo si ya corrían una versión anterior hay que terminarlas de a una (`aws ec2 terminate-instances --instance-ids <id>`; el ASG las reemplaza, porque el lab bloquea *instance refresh*).

5. Validar:

   ```bash
   terraform -chdir=EV1/infra/freshbox-ep1 output alb_url
   ```

   Abrir esa URL: carga el catálogo y `/api/products` devuelve JSON (el Target Group tarda unos minutos en marcar `healthy` los dos targets). Por Session Manager: en una EC2 App, `sudo docker ps` lista los cinco contenedores; en la EC2 MySQL, `sudo docker exec freshbox-db mysql -ualumno -palumno123 freshbox -e "SELECT id, nombre FROM productos;"`.

6. Destruir (antes hay que vaciar el vault de AWS Backup; el workflow lo hace solo):

   ```bash
   for ARN in $(aws backup list-recovery-points-by-backup-vault --backup-vault-name freshbox-backup-vault --query 'RecoveryPoints[].RecoveryPointArn' --output text); do aws backup delete-recovery-point --backup-vault-name freshbox-backup-vault --recovery-point-arn "$ARN"; done
   terraform -chdir=EV1/infra/freshbox-ep1 destroy
   ```

   Quedan solo el bucket de estado y la tabla de bloqueo, vacíos (con el override local, nada).
