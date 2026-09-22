# Changelog

Generado automáticamente con [git-cliff](https://git-cliff.org) a partir de los commits
([Conventional Commits](https://www.conventionalcommits.org/es/)); formato basado en
[Keep a Changelog](https://keepachangelog.com/es/1.1.0/). No editar a mano.

## [Unreleased]

### Añadido

- `2026-09-19` **ev1:** Infraestructura FreshBox con Terraform ([22d7392](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/22d73927b989068efa083bdaaba16c3a9658a75d))
- `2026-09-19` **ev1:** Aplicacion FreshBox adaptada al ALB unico ([c21bb00](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/c21bb00f0f6f047291002b821b77e34e5c3798a6))
- `2026-09-19` **ev1:** Script para cargar credenciales del Learner Lab en GitHub ([3168b66](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/3168b6644c59ac22bd49d4bdaa23031dbb521f9a))

### Corregido

- `2026-09-19` **ev1:** Rolling manual de EC2 App en vez de instance refresh ([19cfca1](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/19cfca1b968de42e1988b72a8a06655cc672e6c9))

### CI/CD

- `2026-09-19` **ev1:** Receta reutilizable de Terraform (apply, destroy, plan) ([ab7fc8e](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/ab7fc8e5664da01c434e042d9f8491d6f5513065))
- `2026-09-19` **ev1:** Plantilla build + push a ECR + instance refresh ([8b345a6](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/8b345a6469f50c5b0a1e691820c8098c8d3ec87b))
- `2026-09-19` **ev1:** Despliegue completo infra + app desde Run workflow ([49814c5](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/49814c53d3eb993e6572c7bd83d5db2fc09ccb96))
- `2026-09-19` **ev1:** Validacion de Terraform y Dockerfiles en push y PR ([a985551](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/a98555152e875bc77d726438da99cfb6c543bdf4))
- `2026-09-21` **ev1:** Backend de estado en S3 + DynamoDB como etapa previa a la infraestructura ([5035ea4](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/5035ea44bada8f3b9ba2a3c7b158d69f5f83a954))

### Documentación

- `2026-09-19` **ev1:** Diagrama TO-BE D1 de FreshBox ([0023e65](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/0023e658bed74b5edcecc49ebfc126037600d7c0))
- `2026-09-19` **ev1:** Guia de despliegue de EV1 ([e3c4474](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/e3c4474ddd0263431d0f315617e5a47002de777a))
- `2026-09-19` **ev1:** Muestra el diagrama TO-BE en el README ([4fda194](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/4fda194175be4fc534342d85ba8d44eba68a61aa))
- `2026-09-21` **ev1:** Secretos del lab renovados a mano; se retira el script de secretos ([24291ea](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/24291eacaa032d05016ea5e90444fa1add36ea6d))
- `2026-09-22` Explica el .gitattributes (finales de linea LF para scripts y plantillas) ([5e5e21e](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/5e5e21e8af30ab811b8fc936ad909e2ee461c675))
- `2026-09-22` **ev1:** Guia de ejecucion local desde un clon (otra cuenta, override de backend, validacion y destroy) ([4fe1187](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/4fe118795f42e06acec271bec1cc164c65b4e88b))

