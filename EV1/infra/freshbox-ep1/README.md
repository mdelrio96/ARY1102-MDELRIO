# FreshBox SpA — Terraform (EP1, AWS Academy Learner Lab)

Despliega la arquitectura TO-BE de tres capas del caso FreshBox (diagrama en `EV1/diagramas/`). Se ejecuta desde los workflows del repo (`.github/workflows/ep1-*.yaml`, Actions → Run workflow) o a mano con los mismos comandos.

## Archivos

```
EV1/infra/freshbox-ep1/
├── main.tf          toda la infraestructura: red, SG, ECR, MySQL, LT + ASG, ALB, Backup
├── variables.tf     valores de la pauta (CIDR, t4g.small, ASG 2–4, IP MySQL, credenciales)
├── outputs.tf       alb_url, asg_name, ecr_repository_urls, mysql_private_ip…
├── files/init.sql   copia de ../../app/init.sql
└── templates/user_data_app.sh.tpl · user_data_mysql.sh.tpl
```

## Qué crea (nombres)

| Recurso | Nombre |
|---|---|
| VPC / IGW / NAT | `freshbox-vpc`, `freshbox-igw`, `freshbox-natgw` (public-1a) |
| Subredes | `freshbox-subnet-{public,app,data}-{1a,1b}` |
| Route tables | `freshbox-rt-public` (→ IGW), `freshbox-rt-private` (→ NAT) |
| Security Groups | `freshbox-sg-alb`, `freshbox-sg-app`, `freshbox-sg-data` |
| ECR | `freshbox-frontend`, `freshbox-get-products`, `freshbox-create-product`, `freshbox-update-product`, `freshbox-delete-product` |
| Capa App | `freshbox-lt-app` (t4g.small arm64, EBS cifrado) → `freshbox-asg-app` (min 2 / max 4) |
| ALB | `freshbox-alb` → listener HTTP:80 → `freshbox-tg-web` (health check `/`) |
| Capa Data | `freshbox-ec2-mysql` (10.0.2.10) |
| Backup | `freshbox-backup-vault`, `freshbox-backup-plan` |

## Estado remoto

El estado vive en S3 (`freshbox-tfstate-870431978422`) con bloqueo en la tabla DynamoDB `freshbox-tfstate-lock` (clave de partición `LockID`, capacidad bajo demanda) y, además, el *lockfile* nativo de S3 (`use_lockfile`). Todo está declarado en el bloque `backend` de `main.tf`, así que `terraform init` es idéntico en el PC y en la pipeline. Terraform avisa en cada `init` que `dynamodb_table` está obsoleto en favor de `use_lockfile`; es esperable y no afecta al despliegue. Ni el bucket ni la tabla forman parte de la infraestructura que se levanta y baja en cada evaluación: `destroy` no los toca y vacíos no cuestan.

> Por qué no los crea Terraform: el backend los necesita antes del `init` y, además, la SCP de AWS Academy deniega `s3:GetBucketObjectLockConfiguration`, que el recurso `aws_s3_bucket` consulta siempre al leer (probado con proveedor 5.100 y 6.65). Cualquier bucket gestionado o importado por Terraform falla en este lab.

Los crea `EV1/script/bootstrap-tfstate.sh`, primera etapa de todo despliegue (workflow *EP1 · Backend de estado*, que *EP1 · Infraestructura* invoca como job previo a `terraform init` y que también se puede lanzar solo desde Actions): lee los nombres y la región del bloque `backend`, comprueba que el sufijo del bucket coincide con la cuenta del lab y crea lo que falte (bucket con versionado y acceso público bloqueado; tabla con clave `LockID`); lo que ya existe no se toca. Un *reset* del Learner Lab los borra junto con el resto de la cuenta; el siguiente `apply` los recrea y parte con un estado vacío, coherente con la cuenta vacía. Si la cuenta del lab cambia, el script se detiene y pide actualizar el nombre del bucket en `main.tf` (`freshbox-tfstate-<ID de cuenta>`).

```bash
./EV1/script/bootstrap-tfstate.sh     # desde la raíz del repo; equivale a s3api create-bucket + put-bucket-versioning + put-public-access-block y dynamodb create-table
```

## Uso local (mismos comandos que la pipeline)

La guía completa desde un clon (requisitos, backend en otra cuenta, imágenes, validación y destroy) está en `EV1/README.md`. Lo específico de Terraform:

```bash
./EV1/script/bootstrap-tfstate.sh   # crea bucket y tabla si no existen; en otra cuenta indica el nombre de bucket que va en main.tf
cd EV1/infra/freshbox-ep1
terraform init            # si el bloque backend cambió desde el último init: terraform init -reconfigure
terraform plan
terraform apply
```

`terraform init -backend=false` sirve solo para `validate` (así lo usa `ep1-validate.yaml`): sin backend inicializado, `plan` y `apply` no corren. Para probar con estado local sin tocar `main.tf`: `printf 'terraform {\n  backend "local" {}\n}\n' > local_override.tf` antes del `init` (el bloque debe ir en varias líneas; en una sola, HCL lo rechaza).

Para bajar todo al terminar la evaluación (el vault de Backup debe quedar vacío antes):

```bash
for ARN in $(aws backup list-recovery-points-by-backup-vault --backup-vault-name freshbox-backup-vault --query 'RecoveryPoints[].RecoveryPointArn' --output text); do aws backup delete-recovery-point --backup-vault-name freshbox-backup-vault --recovery-point-arn "$ARN"; done
terraform destroy
```

Fallback si el lab rechaza `t4g`: `terraform apply -var instance_type=t3.small -var mysql_instance_type=t3.small -var instance_arch=x86_64` e imágenes `linux/amd64`.

Después del `apply` hay que publicar las imágenes (`EV1/app/scripts/ecr-push.sh`, o el workflow *EP1 · Desplegar*) y, si las EC2 App ya corrían una versión anterior, reemplazarlas de a una (la SCP del lab deniega `StartInstanceRefresh`; el ASG relanza cada instancia terminada):

```bash
aws ec2 terminate-instances --instance-ids <id-ec2-app>   # esperar a que el reemplazo quede healthy en el TG antes de la siguiente
```

Validar con `terraform output alb_url` → `/` (frontend) y `/api/products` (JSON).

## Notas del Learner Lab

- Solo `us-east-1`; sin creación de roles IAM (`LabRole` / `LabInstanceProfile`).
- Acceso a instancias por Session Manager (sin key pair).
- Antes de `terraform destroy` hay que borrar los *recovery points* del vault de Backup (arriba); el workflow *EP1 · Infraestructura* con `destroy` lo hace solo.
- Las credenciales del lab duran una sesión (~4 h): si la pipeline falla con `ExpiredToken`, renovar los tres secretos con las credenciales nuevas del lab y relanzar.
