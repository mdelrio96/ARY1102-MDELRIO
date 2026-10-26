# Changelog

Generado automáticamente con [git-cliff](https://git-cliff.org) a partir de los commits
([Conventional Commits](https://www.conventionalcommits.org/es/)); formato basado en
[Keep a Changelog](https://keepachangelog.com/es/1.1.0/). No editar a mano.

## [Unreleased]

### Añadido

- `2026-09-19` **ev1:** Infraestructura FreshBox con Terraform ([22d7392](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/22d73927b989068efa083bdaaba16c3a9658a75d))
- `2026-09-19` **ev1:** Aplicacion FreshBox adaptada al ALB unico ([c21bb00](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/c21bb00f0f6f047291002b821b77e34e5c3798a6))
- `2026-09-19` **ev1:** Script para cargar credenciales del Learner Lab en GitHub ([3168b66](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/3168b6644c59ac22bd49d4bdaa23031dbb521f9a))
- `2026-10-24` **ev2:** Aplicacion FreshBox para EKS (Nginx enruta por metodo HTTP, Node 22 sin root) ([8941ff7](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/8941ff7036e87f904a59e58142bd4a0e983aade9))
- `2026-10-24` **ev2:** Manifiestos de Kubernetes (Deployments, Services, HPA, PDB, Ingress y migracion de datos de EP1) ([c9c4ca8](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/c9c4ca8d5d10eab2f15e566904ff5329bc94a27d))
- `2026-10-24` **ev2:** Infraestructura con Terraform (red, SG por capa, ECR, EKS opcional y RDS Multi-AZ) ([8b5e4bc](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/8b5e4bc680354986e1e2b7d295f8777d6451bb52))
- `2026-10-24` **ev2:** Scripts de despliegue en EKS, prueba CRUD, carga para el HPA y retiro del ALB ([aa2ae43](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/aa2ae4392f14e0aae1858aabaa5db351480d6d2d))
- `2026-10-24` **ev2:** Node group con 2 nodos y prefix delegation para que el HPA escale dentro de ellos ([15bb21d](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/15bb21de35d5edfad2b0fed65ea25c8cbccaedde))
- `2026-10-24` **ev2:** Aplicar-k8s muestra pods, CPU y memoria asignables por nodo ([d271b80](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/d271b80c7d2e12b081468064595158a8778843bf))
- `2026-10-25` **ev2:** Maquina de carga con k6 y Cluster Autoscaler para la demo de escalado ([3e9af83](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/3e9af833f48a9c0dcb65494e73904f7192bd4129))

### Corregido

- `2026-09-19` **ev1:** Rolling manual de EC2 App en vez de instance refresh ([19cfca1](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/19cfca1b968de42e1988b72a8a06655cc672e6c9))
- `2026-10-24` **ev2:** ALB del Ingress sin etiquetas propias (Auto Mode rechazaba CreateRule) y recreacion del Ingress sin DNS ([e174bcf](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/e174bcf6d967f812fb558f3a2982ed7c526b9346))

### CI/CD

- `2026-09-19` **ev1:** Receta reutilizable de Terraform (apply, destroy, plan) ([ab7fc8e](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/ab7fc8e5664da01c434e042d9f8491d6f5513065))
- `2026-09-19` **ev1:** Plantilla build + push a ECR + instance refresh ([8b345a6](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/8b345a6469f50c5b0a1e691820c8098c8d3ec87b))
- `2026-09-19` **ev1:** Despliegue completo infra + app desde Run workflow ([49814c5](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/49814c53d3eb993e6572c7bd83d5db2fc09ccb96))
- `2026-09-19` **ev1:** Validacion de Terraform y Dockerfiles en push y PR ([a985551](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/a98555152e875bc77d726438da99cfb6c543bdf4))
- `2026-09-19` Changelog automatico por evaluacion con git-cliff ([4ad477d](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/4ad477dadd0982af490623874d20c228a65840f7))
- `2026-09-19` Fecha de cada cambio en el changelog ([550aa56](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/550aa56be028f0fecb44bdb37036443bee283a38))
- `2026-09-21` **ev1:** Backend de estado en S3 + DynamoDB como etapa previa a la infraestructura ([5035ea4](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/5035ea44bada8f3b9ba2a3c7b158d69f5f83a954))
- `2026-10-24` **ev2:** Workflows de infraestructura, despliegue en EKS y validacion ([a2d93a0](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/a2d93a0e33537ec63b0cd0336dd8ef33211f4059))
- `2026-10-24` **ev1:** Un solo workflow para EP1 con la accion a elegir (desplegar, actualizar-app, infraestructura, plan, eliminar, validar) ([a8e7d67](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/a8e7d677a7fb74732f074e62ed418fee33095105))
- `2026-10-24` **ev2:** Un solo workflow para EP2 con la accion a elegir (desplegar, actualizar-app, infraestructura, plan, eliminar, validar) ([e63d90b](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/e63d90bdff560d38d67328eb95e5e824fb7a6f9c))
- `2026-10-24` Nombres fijos en los jobs y titulo de cada run con la accion elegida ([33360f1](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/33360f156707c7f0f91786e1cd502a2f780c7c57))

### Documentación

- `2026-09-16` Carga de archivo README general de repositorio ([105c245](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/105c2459ade21d3ab5fd332137cc1be33d2cf2cf))
- `2026-09-19` **ev1:** Diagrama TO-BE D1 de FreshBox ([0023e65](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/0023e658bed74b5edcecc49ebfc126037600d7c0))
- `2026-09-19` **ev1:** Guia de despliegue de EV1 ([e3c4474](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/e3c4474ddd0263431d0f315617e5a47002de777a))
- `2026-09-19` Enlaza cada evaluacion desde el README principal ([cfd1b4a](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/cfd1b4a2a2cece49aec049970d74746d3b47efbf))
- `2026-09-19` **ev1:** Muestra el diagrama TO-BE en el README ([4fda194](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/4fda194175be4fc534342d85ba8d44eba68a61aa))
- `2026-09-21` **ev1:** Secretos del lab renovados a mano; se retira el script de secretos ([24291ea](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/24291eacaa032d05016ea5e90444fa1add36ea6d))
- `2026-09-22` Explica el .gitattributes (finales de linea LF para scripts y plantillas) ([5e5e21e](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/5e5e21e8af30ab811b8fc936ad909e2ee461c675))
- `2026-09-22` **ev1:** Guia de ejecucion local desde un clon (otra cuenta, override de backend, validacion y destroy) ([4fe1187](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/4fe118795f42e06acec271bec1cc164c65b4e88b))
- `2026-10-24` **ev2:** Diagrama TO-BE D1 de FreshBox con EKS y RDS Multi-AZ ([3f77339](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/3f7733945263882f5e1b0bcea94b994af3e9990d))
- `2026-10-24` **ev2:** Guia de despliegue de EV2 y enlace desde el README principal ([0cdf9d8](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/0cdf9d8f00a47063f9f8cee1c144159690f22b3d))
- `2026-10-24` Un workflow por evaluacion en el README principal ([95f66b3](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/95f66b3b78a855b460d73166ee507b58a7810f69))
- `2026-10-24` **ev2:** Diagrama D1 con el node group como minimo y maximo, sin deseado ([8aae6fe](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/8aae6fe109f3fc5ff93ff8fd372911cb1d16c89a))
- `2026-10-26` **ev2:** Regenera el PNG del diagrama D1 con el node group de minimo 2 y maximo 4 ([689b909](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/689b909f17e59cf36a2933068cff534dac85c838))

### Mantenimiento

- `2026-09-19` Ignora estado y temporales de Terraform ([ee41dc7](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/ee41dc785df52eb5dc0c7499bda735b5ee4f1055))
- `2026-09-19` Fuerza fin de linea LF para scripts y plantillas ([63a22c7](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/63a22c74e3826c1103d9a5c906ac36ca3200e189))

