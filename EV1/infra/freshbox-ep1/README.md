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

El estado vive en S3 (`freshbox-tfstate-870431978422`, bloqueo nativo `use_lockfile`), declarado en el bloque `backend` de `main.tf`, así que `terraform init` es idéntico en el PC y en la pipeline. El bucket se crea **una sola vez** y no se destruye nunca (vacío no cuesta); no es parte de la infraestructura que se levanta y baja en cada evaluación.

> Por qué no lo crea Terraform: la SCP de AWS Academy deniega `s3:GetBucketObjectLockConfiguration`, que el recurso `aws_s3_bucket` consulta siempre al leer (probado con proveedor 5.100 y 6.65). Cualquier bucket gestionado o importado por Terraform falla en este lab.

Creación única (ya hecha el 19-sep-2026; repetir solo si la cuenta del lab cambia, ajustando el nombre en `main.tf`):

```bash
aws s3api create-bucket --bucket freshbox-tfstate-870431978422 --region us-east-1
aws s3api put-bucket-versioning --bucket freshbox-tfstate-870431978422 --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket freshbox-tfstate-870431978422 --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

## Uso local (mismos comandos que la pipeline)

```bash
cd EV1/infra/freshbox-ep1
terraform init            # o: terraform init -backend=false  (estado local, solo pruebas)
terraform plan
terraform apply
```

Para bajar todo al terminar la evaluación (el vault de Backup debe quedar vacío antes):

```bash
for ARN in $(aws backup list-recovery-points-by-backup-vault --backup-vault-name freshbox-backup-vault --query 'RecoveryPoints[].RecoveryPointArn' --output text); do aws backup delete-recovery-point --backup-vault-name freshbox-backup-vault --recovery-point-arn "$ARN"; done
terraform destroy
```

Fallback si el lab rechaza `t4g`: `terraform apply -var instance_type=t3.small -var mysql_instance_type=t3.small -var instance_arch=x86_64` e imágenes `linux/amd64`.

Después del `apply` hay que publicar las imágenes (`EV1/app/scripts/ecr-push.sh`, o el workflow *EP1 · Desplegar*) y, si las EC2 App ya se rindieron esperando, forzar un *instance refresh*:

```bash
aws autoscaling start-instance-refresh --auto-scaling-group-name freshbox-asg-app
```

Validar con `terraform output alb_url` → `/` (frontend) y `/api/products` (JSON).

## Notas del Learner Lab

- Solo `us-east-1`; sin creación de roles IAM (`LabRole` / `LabInstanceProfile`).
- Acceso a instancias por Session Manager (sin key pair).
- Antes de `terraform destroy` hay que borrar los *recovery points* del vault de Backup (arriba); el workflow `destroy.yml` lo hace solo.
- Las credenciales del lab duran una sesión (~4 h): si la pipeline falla con `ExpiredToken`, actualizar los secretos (`EV1/script/gh-set-aws-secrets.sh`).
