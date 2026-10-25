# Diagramas EP2 · FreshBox SpA (EKS + RDS Multi-AZ)

| Archivo | Descripción |
|---|---|
| `D1_FreshBox_EKS_TOBE.drawio` | Diagrama TO-BE de tres capas con Amazon EKS y RDS MySQL Multi-AZ (editable en https://app.diagrams.net/) |
| `D1_FreshBox_EKS_TOBE.png` / `.svg` | Exportación para el informe y la presentación |
| `gen_d1_eks_tobe.py` | Generador del `.drawio`; la composición es la del D1 de EV1 |

## Qué muestra el D1 (pauta EP2, punto 2.1)

| Exigencia | Dónde aparece |
|---|---|
| 3 capas: pública, privada App, privada Data | rótulos a la izquierda, con la route table de cada capa; seis subredes `/25` en dos AZ dentro de la VPC `10.0.0.0/22` (mismos CIDR que EV1) |
| ALB Ingress + Ingress Controller | ALB centrado en la capa pública; el Ingress Controller de EKS Auto Mode, en la columna de servicios administrados, lo crea a partir del Ingress `freshbox-ingress` |
| Amazon EKS y Node Group | clúster `freshbox-cluster` (1.34) en las subredes App; Managed Node Group `freshbox-ng` de 2 a 4 nodos `t4g.small` arm64 (2 deseados, prefix delegation en el VPC CNI) con EBS cifrado |
| 5 pods | frontend + 4 microservicios con su puerto, una réplica de cada uno por zona (10 pods en total) |
| HPA | un HPA por Deployment, de 2 a 5 réplicas con CPU objetivo de 70 % |
| RDS MySQL Multi-AZ | primaria `db.t4g.small` en DATA 1a y standby sincrónico en DATA 1b, cifrada con KMS, snapshots automáticos con 7 días de retención |
| ECR | 5 repositorios `freshbox-*` con imágenes `linux/arm64` |
| Security Groups | matriz de la pauta 2.4: SG-ALB (80/443 desde 0.0.0.0/0) → SG-EKS (80/443 desde SG-ALB) → SG-RDS (3306 desde SG-EKS) |
| Flujo ALB → EKS Pods → RDS | flechas con puerto y flujo numerado al pie |
| Container Insights | columna de servicios administrados (add-on `amazon-cloudwatch-observability`) |

## Diferencias con la tabla de la pauta y con EV1

- **ECR, plano de control de EKS, Container Insights y KMS** quedan fuera de la VPC. La pauta los agrupa en la capa App, pero son servicios regionales: los nodos llegan a ellos por HTTPS 443 a través del NAT.
- **NAT Gateway** en la subred pública 1a. La pauta lo lista en la capa App porque da salida a esa capa, pero un NAT necesita ruta al IGW. Es uno solo por costo y no da redundancia de salida entre zonas (igual que en EV1).
- **Ingress Controller**: el ALB lo crea EKS Auto Mode. El AWS Load Balancer Controller necesita un rol IAM propio (IRSA) y el Learner Lab no permite crear roles. Es el mismo mecanismo que validó el docente en la actividad 2.3.
- **Capa DATA sin salida a Internet**: en EV1 las subredes DATA usaban la route table privada con ruta al NAT, porque la EC2 MySQL descargaba su imagen. RDS no lo necesita, así que su route table queda solo con la ruta local.
- **Contingencia de la base**: en EV1 la segunda instancia MySQL solo existía como restauración desde AWS Backup. Ahora RDS mantiene un standby sincrónico y conmuta solo, sin cambiar el endpoint.

## Por validar en el Learner Lab

El diagrama es el diseño objetivo. Estos puntos se confirman al desplegar y, si cambian, se ajusta el generador:

- Capacidad de los nodos `t4g.small`: sin ajustes el VPC CNI admite 11 pods por nodo y en dos nodos no caben los 10 pods de la app con los de sistema. Con prefix delegation (EKS sube `maxPods` a 110) y requests de 64Mi, el Node Group parte con 2 nodos y el HPA escala dentro de ellos, limitado por la CPU (ver `EV2/README.md`). Confirmar que cada nodo muestre 110 pods asignables.
- Que Auto Mode acepte el SG-ALB creado por Terraform (anotación `alb.ingress.kubernetes.io/security-groups`).
- Que `LabEksNodeRole` tenga los permisos que necesita el add-on de Container Insights.
- Escalado real del Node Group: el mínimo y el máximo son límites. Para que el grupo agregue nodos por sí solo hace falta un autoscaler (Cluster Autoscaler), que también depende de permisos IAM.

## Regenerar

```bash
python gen_d1_eks_tobe.py D1_FreshBox_EKS_TOBE.drawio
```

Para exportar, abrir el `.drawio` en https://app.diagrams.net/ → Archivo → Exportar como → PNG (zoom 200 %, borde 20).
