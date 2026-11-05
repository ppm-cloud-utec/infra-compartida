# Runbook de despliegue

Orden obligatorio. `infra-compartida` va primero porque los otros seis
importan sus Outputs; si no está arriba, sus deploys fallan al resolver
`${cf:infra-compartida-dev.*}`.

```
infra-compartida  →  ms-identidad  →  los otros 5 (en paralelo)  →  web-ppm
```

---

## 0. Requisitos (una sola vez)

**AWS CLI v2** — instalado en `~/.local/bin`. Si `aws` no se encuentra, agrega
esto a tu `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Credenciales del Learner Lab.** Entra al lab, *AWS Details → AWS CLI*, y pega
el bloque en `~/.aws/credentials`. **Caducan cada ~4 horas**: si un deploy falla
con `ExpiredToken`, vuelve a copiarlas.

```bash
aws sts get-caller-identity    # debe responder con tu cuenta
```

**Docker corriendo** — lo necesita `serverless-python-requirements` para
compilar `psycopg` contra Amazon Linux. Sin Docker, los tres microservicios con
RDS despliegan un paquete que revienta en ejecución con
`ImportError: libpq.so.5`.

```bash
docker info > /dev/null && echo "docker ok"
```

> **Serverless v3 a propósito.** La v4 exige una cuenta de serverless.com y un
> `SERVERLESS_ACCESS_KEY` en cada deploy. La v3 solo necesita credenciales de
> AWS, que es lo único que da el Learner Lab.

---

## 1. infra-compartida (bloqueante)

```bash
cd infra-compartida
npm install
./scripts/parametros.sh        # secretos a SSM — solo la primera vez
npx serverless deploy
./scripts/bases.sh             # databases y schemas por tenant
npx serverless info --verbose  # anota los Outputs
```

`parametros.sh` genera y guarda en SSM: el `JWT_SECRET`, el usuario y clave
maestros del RDS, y un usuario distinto por cada microservicio con RDS.

`bases.sh` crea `ppm_portafolios`, `ppm_recursos` y `ppm_presupuestos`, y dentro
de cada una los schemas `t_acme`, `t_globex`, `t_initech`, más el usuario del
microservicio sin acceso a las demás databases. **Necesita `psql`**; si no lo
tienes: `sudo apt install postgresql-client`.

El RDS tarda **5 a 10 minutos** en quedar disponible. Es normal.

### Qué anotar de los Outputs

| Output | Lo necesita |
|---|---|
| `RdsEndpoint` | los seeds de los 3 microservicios con RDS |
| `BucketDatalake` | el seed de ms-analitico |
| `SnsEventosArn`, `AutorizadorArn` | los importan solos, no hay que copiarlos |

---

## 2. ms-identidad

```bash
cd ../ms-identidad
npm install
npx serverless deploy
export TABLA=ms-identidad-identidad-dev
python3 seed/generar.py          # 30,006 registros
python3 seed/generar.py --contar
./verificar.sh <url-del-api>     # 401 sin token + aislamiento entre tenants
```

Sin esto nadie puede probar sus endpoints protegidos: es el único que emite
tokens.

---

## 3. Los otros cinco (pueden ir en paralelo)

### Con DynamoDB — ms-tareas

```bash
npm install && npx serverless deploy
export TABLA=ms-tareas-tareas-dev
python3 seed/generar.py && python3 seed/generar.py --contar
```

### Con RDS — ms-portafolios, ms-recursos, ms-presupuestos

```bash
npm install && npx serverless deploy

export DB_HOST=$(aws cloudformation describe-stacks --stack-name infra-compartida-dev \
  --query "Stacks[0].Outputs[?OutputKey=='RdsEndpoint'].OutputValue" --output text)
export DB_NAME=ppm_<servicio>          # portafolios | recursos | presupuestos
export DB_USER=ppm_<servicio>
export DB_PASSWORD=$(aws ssm get-parameter --name /ppm/<servicio>/db-password \
  --with-decryption --query Parameter.Value --output text)

pip install 'psycopg[binary]'
python3 seed/generar.py --esquema      # crea las tablas en los 3 schemas
python3 seed/generar.py                # 30,000 registros
python3 seed/generar.py --contar
```

### Con S3 — ms-analitico

```bash
npm install && npx serverless deploy
export BUCKET_DATALAKE=$(aws cloudformation describe-stacks --stack-name infra-compartida-dev \
  --query "Stacks[0].Outputs[?OutputKey=='BucketDatalake'].OutputValue" --output text)
export TABLA_AGREGADOS=ms-analitico-agregados-dev
python3 seed/generar.py && python3 seed/generar.py --contar
```

Después, en la consola de Athena, correr `athena/tabla.sql` (reemplazando
`<BUCKET>`) y luego `MSCK REPAIR TABLE ppm_analitico.eventos`.

---

## 4. Verificar el sistema completo

```bash
cd infra-compartida
./verificar-sistema.sh
```

Descubre las URLs de los 6 microservicios por CloudFormation, hace login en dos
tenants y comprueba el aislamiento, los 401 y el flujo de eventos de punta a
punta. **Es lo que se corre en vivo en la exposición.**

---

## 5. web-ppm en Amplify

```bash
cd ../web-ppm
# Las 6 URLs salen de: npx serverless info --verbose en cada repo
cp .env.local.example .env.local && nano .env.local
npm install && npm run build      # comprobar que compila antes de subir
```

Consola de Amplify → *Host a web app* → GitHub → `web-ppm` → rama `main`.
En *App settings → Environment variables*, las 6 `NEXT_PUBLIC_API_*`.

---

## Problemas conocidos

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `ExpiredToken` | las credenciales del Learner Lab caducan cada ~4 h | volver a copiarlas |
| `ImportError: libpq.so.5` | se empaquetó sin Docker | levantar Docker y volver a desplegar |
| `User is not authorized to perform iam:CreateRole` | AWS Academy no deja crear roles | ya está resuelto: los 7 stacks usan `LabRole` |
| `Cannot resolve variable at ... cf:infra-compartida-dev` | infra no está desplegada | desplegar infra primero |
| 403 en la segunda ruta con el mismo token | política del authorizer cacheada por método | ya está resuelto: usa recurso comodín |
| `psql: command not found` en `bases.sh` | falta el cliente de Postgres | `sudo apt install postgresql-client` |
| El RDS no responde | tarda 5-10 min en quedar disponible | esperar |

## Para borrar todo al final del ciclo

En orden inverso, porque infra exporta Outputs que los demás importan:

```bash
for r in ms-analitico ms-presupuestos ms-recursos ms-tareas ms-portafolios ms-identidad; do
  (cd ../$r && npx serverless remove)
done
cd ../infra-compartida && npx serverless remove
```
