# Changelog

Generado automáticamente con [git-cliff](https://git-cliff.org) a partir de los commits
([Conventional Commits](https://www.conventionalcommits.org/es/)); formato basado en
[Keep a Changelog](https://keepachangelog.com/es/1.1.0/). No editar a mano.

## [Unreleased]

### Añadido

- `2026-10-24` **ev2:** Aplicacion FreshBox para EKS (Nginx enruta por metodo HTTP, Node 22 sin root) ([8941ff7](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/8941ff7036e87f904a59e58142bd4a0e983aade9))
- `2026-10-24` **ev2:** Manifiestos de Kubernetes (Deployments, Services, HPA, PDB, Ingress y migracion de datos de EP1) ([c9c4ca8](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/c9c4ca8d5d10eab2f15e566904ff5329bc94a27d))
- `2026-10-24` **ev2:** Infraestructura con Terraform (red, SG por capa, ECR, EKS opcional y RDS Multi-AZ) ([8b5e4bc](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/8b5e4bc680354986e1e2b7d295f8777d6451bb52))
- `2026-10-24` **ev2:** Scripts de despliegue en EKS, prueba CRUD, carga para el HPA y retiro del ALB ([aa2ae43](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/aa2ae4392f14e0aae1858aabaa5db351480d6d2d))

### Corregido

- `2026-10-24` **ev2:** ALB del Ingress sin etiquetas propias (Auto Mode rechazaba CreateRule) y recreacion del Ingress sin DNS ([e174bcf](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/e174bcf6d967f812fb558f3a2982ed7c526b9346))

### CI/CD

- `2026-10-24` **ev2:** Workflows de infraestructura, despliegue en EKS y validacion ([a2d93a0](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/a2d93a0e33537ec63b0cd0336dd8ef33211f4059))

### Documentación

- `2026-10-24` **ev2:** Diagrama TO-BE D1 de FreshBox con EKS y RDS Multi-AZ ([3f77339](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/3f7733945263882f5e1b0bcea94b994af3e9990d))
- `2026-10-24` **ev2:** Guia de despliegue de EV2 y enlace desde el README principal ([0cdf9d8](https://github.com/mdelrio96/ARY1102-MDELRIO/commit/0cdf9d8f00a47063f9f8cee1c144159690f22b3d))

