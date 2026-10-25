# Máquina de carga (demo de escalado)

Herramienta para mostrar el escalado de FreshBox con tráfico real. No forma parte de la entrega de EP2: no cambia los manifiestos, el clúster ni el workflow evaluado.

Es una EC2 `t4g.small` en la VPC por defecto del lab, fuera de la red de FreshBox. Hace dos trabajos:

```
Máquina de carga (EC2 con LabRole)
 ├─ k6: pide /api/products y / por el ALB      → el HPA agrega pods
 └─ Cluster Autoscaler: ve pods en Pending     → el node group pasa de 2 a 3 o 4 nodos
```

## Por qué el Cluster Autoscaler corre aquí y no en el clúster

El autoscaler necesita permisos de Auto Scaling y el lab no deja crear roles. Se revisó con `aws iam simulate-principal-policy`:

| Rol | Permisos de autoscaling | Lo puede usar un pod |
| --- | --- | --- |
| `LabEksNodeRole` (nodos) | no (`implicitDeny`) | sí, por IMDS |
| `LabRole` | sí (`allowed`) | no: confía en EC2 pero no en `pods.eks.amazonaws.com` |

Esta EC2 asume `LabRole` con `LabInstanceProfile` y entra al clúster con un access entry de ese rol (`AmazonEKSClusterAdminPolicy`).

## Uso

Requisito: EP2 desplegado (workflow **EP2 · FreshBox (EKS + RDS)**, acción `desplegar`).

1. Actions → **EP2 · Máquina de carga** → acción `crear` (unos 2 minutos). La máquina termina de prepararse sola unos 4 minutos después.
2. Abre el enlace del resumen del run (consola EC2 → Connect) con la sesión del lab abierta. Entra por **Session Manager**; si no conecta, usa **EC2 Instance Connect**.
3. Ejecuta `sudo -i`.
4. Abre una segunda sesión igual. En la primera, `freshbox-vigilar`; en la segunda, `freshbox-demo`.
5. Al terminar, el mismo workflow con la acción `eliminar`.

`freshbox-demo` acepta usuarios virtuales y minutos de meseta (`freshbox-demo 150 8`; por defecto 100 y 6). Mientras dura la carga sube `maxReplicas` de `frontend-hpa` y `get-products-hpa` de 5 a 15 (`MAX_DEMO=20 freshbox-demo` para otro valor) y al salir lo devuelve. Con 5 réplicas máximo todos los pods caben en 2 nodos y el autoscaler no tendría motivo para agregar uno.

## Qué se ve (tiempos aproximados)

| Minuto | Qué pasa |
| --- | --- |
| 0-2 | sube la carga; el HPA aumenta las réplicas de `frontend` y `get-products` |
| 2-4 | los pods que no caben quedan en `<none>` (Pending) y el autoscaler pide un nodo más |
| 4-6 | el nodo nuevo queda `Ready` (2-3 min) y los pods pendientes arrancan en él |
| fin + 2 | el HPA vuelve al mínimo de réplicas |
| fin + 5 a 8 | el autoscaler retira los nodos sobrantes hasta volver a 2 |

Decisiones del autoscaler: `journalctl -u cluster-autoscaler -f`. Preparación de la máquina: `/var/log/freshbox-carga.log`.

## Archivos

| Archivo | Qué hace |
| --- | --- |
| `infra/main.tf` | EC2, SG (solo SSH desde EC2 Instance Connect), access entry de `LabRole`; estado en `freshbox/ep2-carga/terraform.tfstate` |
| `infra/user_data.sh.tpl` | instala kubectl y k6 (misma versión menor que el clúster) y el Cluster Autoscaler como servicio systemd |
| `scripts/carga.js` | escenario de k6: rampa, meseta y bajada |
| `scripts/freshbox-demo.sh` | sube el máximo del HPA, lanza k6 y lo restaura |
| `scripts/freshbox-vigilar.sh` | HPA, nodos, CPU y pods por nodo cada 5 s |

Si se elimina y se vuelve a desplegar el clúster de EP2, la máquina queda apuntando al clúster anterior: elimínala y créala de nuevo.
