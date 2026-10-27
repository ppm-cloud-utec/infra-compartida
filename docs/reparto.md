# Reparto del equipo — Grupo 4

Organización GitHub propuesta: **`ppm-cloud`** (repos públicos, los 6 con push
en todos). Cada repo lleva su `INTEGRANTE.md`, igual que en el proyecto parcial.

| Integrante | Repo(s) | BD | Qué entrega |
|---|---|---|---|
| **Osomar1705** | `infra-compartida` + `ms-identidad` + `ms-analitico` | DynamoDB · S3/Athena | RDS, SNS, S3, Lambda Authorizer, login/JWT multi-tenant, data lake y KPIs |
| **Brisseth-raton** | `ms-portafolios` | RDS `ppm_portafolios` | Portafolios, proyectos, prioridades, % de avance (worker SQS) |
| **fabianbot1331** | `ms-tareas` | DynamoDB | Tareas, hitos, dependencias, publicación de `tarea.*` |
| **sebastianperez72** | `ms-recursos` | RDS `ppm_recursos` | Personas, roles, capacidad, asignaciones, detección de sobreasignación |
| **carloscondor1610** | `ms-presupuestos` | RDS `ppm_presupuestos` | Presupuesto por proyecto, gastos, ejecución, alerta de exceso |
| **alxgr-08** | `web-ppm` | — | Next.js en Amplify: login, selector de tenant, dashboard, CRUD de los 5 MS |

> El reparto de Osmar es desigual a propósito: `infra-compartida` es
> **prerequisito de todos** y tiene que estar lista primero; `ms-identidad` y
> `ms-analitico` son los dos extremos de la plomería (JWT y SNS/SQS/S3), así que
> conviene que los lleve la misma persona que hizo la infra.

## Entregable de cada responsable de microservicio

1. `serverless.yml` que despliega solo con `sls deploy` (sin pasos manuales).
2. Mínimo 5 endpoints REST protegidos (CRUD + un listado con filtros).
3. **ER (SQL)** o **estructura JSON documentada (NoSQL)** en `docs/modelo.md`.
4. Script `seed/` que carga **30,000 registros en 3 tenants**.
5. Publicación de sus eventos a SNS y, si le toca, worker de SQS idempotente.
6. Capturas: despliegue, endpoint protegido (401 sin token), datos de 2 tenants
   distintos con el mismo endpoint, y conteo de registros.
7. `README.md` con los endpoints y cómo probarlos.

## Entregable del frontend (vale 6 de 20, es el más pesado)

Login, cambio de tenant, listado/creación de portafolios y proyectos, tablero de
tareas, vista de recursos con su carga, vista de presupuesto con la ejecución y
el dashboard de KPIs. Desplegado en Amplify con la URL pública en el informe.

## Responsabilidades compartidas del informe final

| Pieza | Quién |
|---|---|
| Diagrama de arquitectura (2 pts) | Osmar |
| Armado del informe Word/PDF | Brisseth + Carlos |
| PPT del resumen | alxgr-08 + Fabián |
| Guion de la demo con 2 tenants | Sebastián |

Cada uno entrega sus capturas y su sección de BD; el armado es solo juntar.
