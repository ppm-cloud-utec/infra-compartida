# Reparto del equipo — Grupo 4

Organización GitHub propuesta: **`ppm-cloud`** (repos públicos, los 6 con push
en todos). Cada repo lleva su `INTEGRANTE.md`, igual que en el proyecto parcial.

| Integrante | Repo(s) | BD | Qué entrega |
|---|---|---|---|
| **Osomar1705** | `infra-compartida` + `ms-identidad` + `ms-analitico` | DynamoDB · S3/Athena | RDS, SNS, S3, Lambda Authorizer, login/JWT multi-tenant, data lake y KPIs |
| **Brisseth-raton** | `ms-portafolios` | RDS `ppm_portafolios` | Portafolios, proyectos, prioridades, % de avance (worker SQS) |
| **fabianbot1331** | `ms-tareas` | DynamoDB | Tareas, hitos, dependencias, publicación de `tarea.*` |
| **sebastianperez72** | `ms-recursos` | RDS `ppm_recursos` | Personas, roles, capacidad, asignaciones, detección de sobreasignación |
| **carloscondor1610** | `ms-presupuestos` + **Arquitectura de Solución** | RDS `ppm_presupuestos` | Presupuesto, gastos, ejecución, alerta de exceso · **y todo el entregable de arquitectura (2 pts)** |
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

## Responsabilidades del entregable final

| Pieza | Quién | Vale |
|---|---|---|
| **Arquitectura de Solución** y todo lo relacionado | **carloscondor1610** | **2 pts** |
| Armado del informe Word/PDF | Brisseth-raton | parte de los 8+6 |
| PPT del resumen | alxgr-08 + fabianbot1331 | — |
| Guion y ensayo de la demo con 2 tenants | sebastianperez72 | 1 pt (expo) |
| Despliegue en AWS y coordinación | Osomar1705 | habilita todo |

Cada uno entrega sus capturas y su sección de modelo de datos; el armado es
solo juntar.

### Qué incluye "Arquitectura de Solución" (Carlos)

Es un entregable de 2 puntos por sí solo, y no es solo dibujar un diagrama:

1. **El diagrama de arquitectura** con los 6 microservicios, sus bases de
   datos, API Gateway, el Lambda Authorizer, el topic SNS, las 4 colas SQS con
   sus DLQ, los 2 buckets S3, el RDS y Amplify. La base está en
   [arquitectura.md](arquitectura.md), sección 3, en Mermaid: se puede exportar
   o redibujar en draw.io / Lucidchart para el informe.
2. **Explicar los tres pilares** que exige el enunciado y cómo los cumple el
   diseño: multi-tenancy (el `tenant_id` dentro del JWT, partición en DynamoDB,
   `search_path` en RDS), serverless y EDA.
3. **El modelo de eventos:** los 8 eventos, qué microservicio publica cada uno,
   qué cola lo consume y con qué filtro. Está en [eventos.md](eventos.md).
4. **Justificar las decisiones y sus limitaciones** — esto es lo que mide la
   competencia del curso ("comprende sus limitaciones"):
   - por qué un único RDS con un schema por tenant
   - por qué las Lambdas van fuera de la VPC y el RDS queda con acceso público
     restringido (NAT Gateway limitado en AWS Academy), y qué se haría en
     producción
   - por qué se reusa `LabRole` en vez de roles IAM propios
   - por qué el dashboard lee de agregados en DynamoDB y no de Athena
   - por qué los microservicios no se llaman entre sí por HTTP
5. **La sección de arquitectura del informe** y las láminas de arquitectura
   del PPT.

Todo el material fuente ya está escrito en `infra-compartida/docs/`: Carlos
tiene que entenderlo, redibujarlo para el informe y poder defenderlo ante el
ACL, que pregunta individualmente.
