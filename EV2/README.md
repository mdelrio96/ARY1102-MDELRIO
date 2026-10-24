# EV2 — EP2 ARY1102 · FreshBox SpA en Amazon EKS + RDS Multi-AZ

Modernización de la arquitectura de EV1. Los cinco contenedores que corrían con Docker en las EC2 del Auto Scaling Group pasan a Amazon EKS: un Managed Node Group de 2 a 4 nodos `t4g.small`, cinco Deployments con dos réplicas cada uno y un HPA por Deployment. La base MySQL que corría en una EC2 pasa a Amazon RDS MySQL `db.t4g.small` Multi-AZ, cifrada y con snapshots automáticos. La red de tres capas es la misma de EV1 (VPC `10.0.0.0/22`, seis subredes `/25` en dos AZ).

Todo se levanta con Terraform y se despliega desde GitHub Actions **sin push** (Actions → Run workflow), o desde el PC con los mismos scripts.

## Diagrama TO-BE

[![Diagrama TO-BE FreshBox EKS](diagramas/D1_FreshBox_EKS_TOBE.png)](diagramas/D1_FreshBox_EKS_TOBE.png)

Editable en [`diagramas/D1_FreshBox_EKS_TOBE.drawio`](diagramas/D1_FreshBox_EKS_TOBE.drawio). Qué muestra cada parte y en qué se aparta de la tabla de la pauta: [`diagramas/README.md`](diagramas/README.md).

## Estructura

```
.github/workflows/                     (raíz del repo)
├── ep2-deploy.yaml                    EP2 · Desplegar FreshBox en EKS (infra + app)   ← Run workflow
├── ep2-provision-freshbox.yaml        EP2 · Infraestructura: apply | destroy | plan, con o sin clúster EKS (opción crear_eks)
├── ep2-deploy-app.yaml                EP2 · Build arm64 → ECR → manifiestos en EKS → prueba CRUD (reutilizable + Run workflow)
└── ep2-validate.yaml                  CI: terraform validate, docker build, kubeconform y shellcheck
EV2/
├── infra/freshbox-ep2/                Terraform: main, network, security, ecr, eks, rds, variables, outputs
├── app/                               frontend Nginx + 4 microservicios Node + init.sql + docker-compose.yml
│   └── scripts/ecr-push.sh            build linux/arm64 y push de las 5 imágenes
├── k8s/                               manifiestos con marcadores (<ECR_REGISTRY>, <IMAGE_TAG>, <RDS_ENDPOINT>, <SG_ALB_ID>)
│   ├── 00-namespace · 01-configmap · 02-secret.example · 03-migrar-datos-job
│   ├── <servicio>/                    deployment, service y hpa de cada uno de los 5 servicios
│   ├── pdb.yaml                       PodDisruptionBudget por servicio
│   └── ingressclass.yaml · ingress.yaml
├── script/
│   ├── bootstrap-tfstate.sh           bucket S3 + tabla DynamoDB del estado (los mismos de EV1)
│   ├── aplicar-k8s.sh                 completa los manifiestos con las salidas de Terraform y los aplica
│   ├── probar-crud.sh                 GET, POST, PUT y DELETE por el ALB
│   ├── carga-hpa.sh                   carga sobre get-products para ver escalar el HPA
│   └── bajar-k8s.sh                   retira el ALB del Ingress antes de terraform destroy
└── diagramas/                         D1 TO-BE (draw.io, PNG, SVG y generador)
```

## Qué cambia respecto de EV1

| Aspecto | EV1 (EC2 + Docker) | EV2 (EKS + RDS) |
|---|---|---|
| Cómputo | ASG de EC2; el user data descarga las imágenes y levanta los 5 contenedores | Managed Node Group; Kubernetes reparte los pods y los reinicia si fallan |
| Actualización | rolling manual terminando EC2 de a una (el lab bloquea instance refresh) | rolling update de cada Deployment, sin cortar el servicio |
| Escalado | el ASG agrega instancias completas por CPU promedio | HPA por servicio (2 a 5 réplicas) dentro de un Node Group de 2 a 4 nodos |
| Entrada | ALB de Terraform hacia las EC2 :80 | ALB creado por el Ingress (EKS Auto Mode) hacia las IP de los pods frontend |
| Base de datos | MySQL en una EC2 con AWS Backup diario; contingencia restaurando en 1b | RDS Multi-AZ: standby sincrónico, failover automático con el mismo endpoint, snapshots de 7 días |
| Red Data | ruta al NAT (la EC2 descargaba su imagen) | sin salida a Internet |
| Credenciales | `alumno123` en `variables.tf` | clave aleatoria generada por Terraform, llevada a un Secret sin pasar por Git |
| Imágenes | Node 18 como root | Node 22 con usuario sin privilegios, tag por commit |

## Decisiones por las limitaciones del Learner Lab

- **Roles IAM.** El lab no deja crear roles. El clúster usa `LabEksClusterRole` y los nodos `LabEksNodeRole`, que Terraform busca por nombre (llevan prefijo y sufijo aleatorios).
- **Ingress Controller.** El AWS Load Balancer Controller necesita su propio rol (IRSA). Se usa el controlador de ALB de **EKS Auto Mode**, el mismo que validó el docente en la actividad 2.3. Auto Mode queda habilitado solo para el balanceo (`node_pools = []`); los nodos son los del Managed Node Group.
- **Tres nodos deseados (mínimo 2, máximo 4).** Un `t4g.small` admite 11 pods (3 ENI × 3 IP + 2). Los 10 pods de la app, CoreDNS, Metrics Server y los agentes de Container Insights no caben en dos nodos con espacio para que el HPA agregue réplicas. Con tres nodos quedan unos 6 lugares libres.
- **Escalado de nodos.** El mínimo y el máximo del Node Group son límites. Para que agregue nodos por sí solo hace falta un Cluster Autoscaler, que necesita permisos IAM que el lab no da. En la demostración se escala a mano (abajo) y el HPA es el escalado automático.
- **API de EKS pública con autenticación IAM** (`0.0.0.0/0`), para que la pipeline de GitHub pueda usar `kubectl`. Se puede limitar con `eks_public_access_cidrs`.
- **HTTP sin TLS.** El SG-ALB permite 443 como pide la pauta, pero el lab no tiene dominio ni certificado ACM para un listener HTTPS.
- **El ALB no lleva etiquetas propias** (`Project`, `Env`...). Auto Mode crea el ALB, el listener y sus reglas con `LabEksClusterRole`, y su política (`AmazonEKSLoadBalancingPolicy`) solo acepta claves `eks:eks-cluster-name` e `ingress.eks.amazonaws.com/*` en esas creaciones. Con la anotación `alb.ingress.kubernetes.io/tags` el controlador recibe `AccessDenied` en `CreateRule`.
- **Un NAT Gateway**, igual que en EV1. Solo lo usa el tráfico que sale de los nodos; los usuarios entran por el IGW al ALB.

## Cada sesión del Learner Lab (GitHub Actions)

1. Iniciar el lab → **AWS Details → AWS CLI: Show** y actualizar los secretos `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y `AWS_SESSION_TOKEN` del repositorio (igual que en EV1).
2. Actions → **EP2 · Desplegar FreshBox en EKS (infra + app)** → Run workflow. Tarda unos 35 a 40 minutos: EKS y RDS Multi-AZ se crean en paralelo, luego los nodos, las imágenes y los manifiestos. El resumen del run muestra la URL del ALB y la prueba CRUD.
3. Al terminar: Actions → **EP2 · Infraestructura** → `destroy`. Primero retira el ALB del Ingress, después destruye con Terraform y borra los logs de Container Insights.

**Infraestructura en dos etapas (opcional).** *EP2 · Infraestructura* → `apply` tiene la casilla **crear_eks**, marcada por defecto. Desmarcada, crea solo la base: red, Security Groups, ECR y RDS Multi-AZ. Un segundo `apply` con la casilla marcada agrega el clúster EKS con su Node Group y add-ons. Desmarcarla en una sesión posterior quita el clúster (antes retira el ALB del Ingress) y conserva la base y los datos de RDS, lo que ahorra créditos mientras no se trabaja con Kubernetes. *EP2 · Desplegar* siempre crea el clúster, porque la app lo necesita.

Si solo cambió la app: **EP2 · Build + Push ECR + despliegue en EKS** → Run workflow. Si un job falla con `ExpiredToken`, se renuevan los secretos y se relanza.

## Ejecución local desde un clon

Requisitos: Terraform ≥ 1.10, AWS CLI v2, kubectl, Docker con Buildx y bash (en Windows, Git Bash), con el bloque de **AWS CLI: Show** del lab en `~/.aws/credentials`.

```bash
./EV2/script/bootstrap-tfstate.sh                     # bucket y tabla del estado (si cambió la cuenta, indica qué poner en main.tf)
terraform -chdir=EV2/infra/freshbox-ep2 init
terraform -chdir=EV2/infra/freshbox-ep2 apply         # ~25 min (con -var create_eks=false, solo la base sin clúster)
./EV2/app/scripts/ecr-push.sh                         # 5 imágenes linux/arm64, tag = commit actual
./EV2/script/aplicar-k8s.sh                           # ConfigMap, Secret, migración, Deployments, Ingress, HPA
./EV2/script/probar-crud.sh                           # GET, POST, PUT, DELETE por el ALB
```

Para bajar todo:

```bash
./EV2/script/bajar-k8s.sh
terraform -chdir=EV2/infra/freshbox-ep2 destroy
```

Prueba local de la app, sin AWS: `cd EV2/app && docker compose up -d --build` → http://localhost:8080.

## Verificación para la demostración

| Pauta | Comando o lugar en la consola |
|---|---|
| Clúster y nodos en 2 AZ | `kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type` |
| 5 Deployments, 10 pods | `kubectl get deploy,pods -n freshbox -o wide` |
| Services ClusterIP e Ingress con DNS del ALB | `kubectl get svc,ingress -n freshbox` |
| Imágenes en ECR | `aws ecr describe-images --repository-name freshbox-get-products --query 'imageDetails[].imageTags'` |
| RDS Multi-AZ en detalle | `aws rds describe-db-instances --db-instance-identifier freshbox-db --query 'DBInstances[0].{Clase:DBInstanceClass,MultiAZ:MultiAZ,Primaria:AvailabilityZone,Standby:SecondaryAvailabilityZone,Cifrada:StorageEncrypted,Retencion:BackupRetentionPeriod,Publica:PubliclyAccessible}'` |
| Migración de datos | `kubectl logs job/migrar-datos-ep1 -n freshbox` |
| CRUD por el ALB | `./EV2/script/probar-crud.sh` o el navegador en la URL del ALB |
| HPA escalando | `./EV2/script/carga-hpa.sh` y, en otra terminal, `kubectl get hpa -n freshbox -w` |
| Métricas | `kubectl top nodes` · `kubectl top pods -n freshbox` · CloudWatch → Container Insights |
| Escalar el Node Group | `aws eks update-nodegroup-config --cluster-name freshbox-cluster --nodegroup-name freshbox-ng --scaling-config minSize=2,maxSize=4,desiredSize=4` |

## Estado en el Learner Lab

Primer despliegue completo (2026-10-24, *EP2 · Desplegar*):

- Terraform creó la red, RDS Multi-AZ y el clúster con los add-ons administrados (vpc-cni, kube-proxy, CoreDNS, Metrics Server, Container Insights): 3 nodos `t4g.small` arm64 `Ready` con Kubernetes 1.34.
- El Job `migrar-datos-ep1` terminó, los 10 pods quedaron `Running` repartidos en los 3 nodos y los 5 HPA leen la CPU de los pods.
- El ALB `freshbox-eks-alb` se creó (Auto Mode respetó el nombre), pero el controlador no pudo crear la regla del listener: `AccessDenied` en `elasticloadbalancing:CreateRule`, por las etiquetas propias del Ingress (ver decisiones). Se quitaron, y `aplicar-k8s.sh` ahora borra y recrea un Ingress que quedó sin DNS.

Por confirmar en el siguiente despliegue:

- **CRUD por el ALB** y que el ALB quede con `freshbox-sg-alb` (EC2 → Load Balancers → `freshbox-eks-alb` → Security).
- **Container Insights.** El agente usa el rol del nodo. Revisar si `LabEksNodeRole` tiene `CloudWatchAgentServerPolicy`:
  `aws iam list-attached-role-policies --role-name "$(aws iam list-roles --query "Roles[?contains(RoleName,'LabEksNodeRole')].RoleName" --output text)"`.
  Si no la tiene y el lab no deja adjuntarla, los pods del add-on corren pero no publican métricas; la infografía de la pauta permite documentar la restricción y mostrar `kubectl top` y las métricas del ALB y de RDS.
