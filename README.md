# infra-compartida

Infraestructura compartida del SaaS PPM. **Se despliega primero**: los 6
microservicios importan sus Outputs con `${cf:infra-compartida-dev.<Output>}`.

- **Responsable:** @Osomar1705
- **Runtime:** Python 3.12 · Serverless Framework v4 · us-east-1

## Qué crea

| Recurso | Nombre | Para qué |
|---|---|---|
| SNS topic | `ppm-eventos-dev` | el bus de eventos de dominio (EDA) |
| SNS topic | `ppm-alertas-dev` | alertas al PMO (presupuesto excedido, sobreasignación) |
| DynamoDB | `ppm-eventos-procesados-dev` | idempotencia de los workers SQS, con TTL de 30 días |
| S3 | `ppm-datalake-<cuenta>-dev` | eventos en JSON particionados, fuente de Athena |
| S3 | `ppm-adjuntos-<cuenta>-dev` | adjuntos de proyectos, key prefijada por tenant |
| RDS PostgreSQL | `ppm-rds-dev` | el único RDS, con una database por microservicio |
| Lambda | `ppm-autorizador-dev` | authorizer compartido que valida el JWT |

## Despliegue

**Guía completa paso a paso: [DESPLIEGUE.md](DESPLIEGUE.md)** — incluye el
orden de los 7 stacks, los seeds, los problemas conocidos y cómo borrar todo
al final del ciclo.

Resumen:

### 0. Requisitos

- AWS CLI v2 y credenciales del Learner Lab (caducan cada ~4 h)
- **Docker corriendo**: lo necesita `serverless-python-requirements` para
  compilar `psycopg` contra Amazon Linux
- `psql` para `bases.sh` (`sudo apt install postgresql-client`)

### 1. Parámetros en SSM (una sola vez, antes del primer deploy)

Los secretos no van en el `serverless.yml`. Se cargan con:

```bash
./scripts/parametros.sh
```

### 2. Desplegar

```bash
npm install            # instala Serverless v3 y el plugin de Python
npx serverless deploy
```

> **Serverless v3 a propósito.** La v4 exige una cuenta de serverless.com y un
> `SERVERLESS_ACCESS_KEY` en cada deploy; la v3 solo necesita credenciales de
> AWS, que es lo único que da el Learner Lab.

### 3. Crear las databases y los schemas por tenant

```bash
./scripts/bases.sh
```

Crea `ppm_portafolios`, `ppm_recursos` y `ppm_presupuestos`, y dentro de cada
una los schemas `t_acme`, `t_globex`, `t_initech` más el usuario del
microservicio con permiso solo sobre su database.

### 4. Verificar

```bash
npx serverless info --verbose   # los Outputs que consumen los demás repos
./verificar-sistema.sh          # prueba los 6 microservicios de punta a punta
```

`verificar-sistema.sh` descubre las URLs por CloudFormation, entra con dos
tenants y comprueba los tres pilares: que ningún tenant vea datos del otro, que
los 6 devuelvan 401 sin token, y que **completar una tarea cambie el avance del
proyecto sin que nadie llame a ms-portafolios**. Revisa además las 4 colas y sus
DLQ. Es lo que se corre en vivo en la exposición.

## Decisiones que afectan a todo el equipo

**Lambdas fuera de la VPC, RDS con acceso público restringido al 5432.** Una
Lambda dentro de una VPC pierde salida a SNS, S3 y DynamoDB salvo con NAT
Gateway o VPC Endpoints, y en AWS Academy el NAT está limitado. Como los 3
microservicios con RDS también publican a SNS, estarían en el peor caso. En
producción el RDS iría en subnet privada con VPC Endpoints; aquí se optó por
acceso público por las limitaciones del laboratorio.

**LabRole en vez de roles propios.** AWS Academy no permite crear roles IAM.
Los permisos mínimos que cada microservicio necesitaría están comentados en su
`serverless.yml` para documentar la intención.

## Documentación del proyecto

| Documento | Qué contiene |
|---|---|
| [propuesta.md](docs/propuesta.md) | el producto: qué resuelve, roles, alcance, las 3 referencias |
| [arquitectura.md](docs/arquitectura.md) | multi-tenancy, serverless, EDA, diagrama, los 6 microservicios |
| [eventos.md](docs/eventos.md) | catálogo de eventos, colas SQS, reglas de idempotencia |
| [convenciones.md](docs/convenciones.md) | Python 3.12, estructura de repo, contrato HTTP, nomenclatura |
| [reparto.md](docs/reparto.md) | quién hace qué y qué entrega cada uno |
| [cronograma.md](docs/cronograma.md) | plan semanal, hito del ACL, riesgos |
