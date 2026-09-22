# Evaluaciones

Repositorio con las evaluaciones desarrolladas a lo largo del semestre.

## 📁 Estructura

Cada evaluación se organiza en su propia carpeta, siguiendo la nomenclatura `/EV1`, `/EV2`, `/EV3`:

| Carpeta | Evaluación | Contenido |
|---|---|---|
| [EV1](https://github.com/mdelrio96/ARY1102-MDELRIO/tree/main/EV1) | EP1 · FreshBox SpA — arquitectura TO-BE de tres capas en AWS | Terraform (`infra/`), aplicación (`app/`), diagrama TO-BE, guía de despliegue y [changelog](https://github.com/mdelrio96/ARY1102-MDELRIO/blob/main/EV1/CHANGELOG.md) |
| EV2 | *(pendiente)* | |
| EV3 | *(pendiente)* | |

Dentro de cada carpeta se incluyen los archivos correspondientes al desarrollo, documentación y/o entregables de esa evaluación. Los workflows de GitHub Actions viven en `.github/workflows/` con el prefijo de la evaluación (`ep1-*`).

## 🛠️ Cómo navegar el repositorio

1. Ingresa a la carpeta de la evaluación que te interese.
2. Revisa el archivo README interno (si existe) para más detalles específicos.
3. Los documentos de entrega suelen estar en formato `.docx`, `.pdf` o `.md`, según corresponda.

## 📌 Notas

- Este repositorio se irá actualizando conforme se desarrollen nuevas evaluaciones.
- Los commits siguen Conventional Commits (`feat`, `fix`, `docs`, `ci`, `chore`) con el ámbito de la evaluación (`feat(ev1): ...`). A partir de ellos, el workflow `changelog.yaml` genera automáticamente `CHANGELOG.md` (global) y `EV<n>/CHANGELOG.md` (por evaluación) en cada push a `main`; no se editan a mano.
- `.gitattributes` fija finales de línea LF en todo el repositorio (`* text=auto eol=lf`, y explícito para `*.sh` y `*.tpl`) y marca como binarios `png`, `pdf` y `zip`. Los scripts y las plantillas de *user data* corren en Linux (runners de GitHub, EC2) y se editan en Windows: con CRLF fallarían con `$'\r': command not found`. No depende del `core.autocrlf` de cada máquina, así que conviene no borrarlo.

## 👤 Autor

Este repositorio es mantenido de forma individual como parte del trabajo académico del semestre.

---
