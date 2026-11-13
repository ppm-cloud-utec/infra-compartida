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
| `spawn python3.12 ENOENT` | `dockerizePip: non-linux` **no** usa Docker estando en Linux, y busca un `python3.12` local | ya está resuelto: los 7 repos usan `dockerizePip: true` |
| `Cannot find version X for postgres` | AWS retira versiones de motor con el tiempo | consultar las vigentes (abajo) y ajustar `EngineVersion` |
| `must be able to SET ROLE "<usuario>"` | en RDS el usuario maestro **no** es superusuario | ya está resuelto: `bases.sh` hace `GRANT <usuario> TO <admin>` antes de crear los schemas |
| `Warning: Invalid configuration at provider.runtime` | el esquema de Serverless v3.40 no conoce `python3.12` | **es solo un aviso**, el deploy funciona y AWS acepta el runtime |

### Consultar las versiones de PostgreSQL vigentes

```bash
aws rds describe-orderable-db-instance-options --engine postgres \
  --db-instance-class db.t3.micro \
  --query 'OrderableDBInstanceOptions[].EngineVersion' --output text \
  | tr '\t' '\n' | sort -uV | tail -10
```

Las versiones de motor **se consultan, no se asumen**: AWS las va retirando.

## Para borrar todo al final del ciclo

En orden inverso, porque infra exporta Outputs que los demás importan:

```bash
for r in ms-analitico ms-presupuestos ms-recursos ms-tareas ms-portafolios ms-identidad; do
  (cd ../$r && npx serverless remove)
done
cd ../infra-compartida && npx serverless remove
```

## Al reencender el Learner Lab: revisar los disparadores

Apagar el lab aplica la politica `voc-cancel-cred`, que deniega los permisos de
`LabRole`. Las Lambdas corren con ese rol, asi que dejan de poder leer
DynamoDB, RDS y S3 — pero ademas **AWS deshabilita los event source mappings**
(los disparadores SQS y de DynamoDB Streams) y **no los vuelve a activar solo**
cuando el lab arranca.

Es la falla mas enganosa del proyecto, porque todo lo demas se ve sano:

- los 6 microservicios responden 200,
- las colas se ven **vacias**, pero porque nadie encola, no porque se haya
  procesado todo,
- las DLQ estan vacias por la misma razon,
- y el unico sintoma es que completar una tarea no mueve el avance.

Diagnostico y arreglo:

```bash
# ver cuales estan caidos
aws lambda list-event-source-mappings \
  --query 'EventSourceMappings[].[FunctionArn,State,UUID]' --output text

# reactivar cada uno (tarda 1-2 min en quedar Enabled)
aws lambda update-event-source-mapping --uuid <UUID> --enabled
```

Son 5: `ms-tareas-dev-publicarTareas`, `ms-portafolios-dev-worker`,
`ms-presupuestos-dev-worker`, `ms-analitico-dev-ingesta` y
`ms-analitico-dev-notificador`.

`verificar-sistema.sh` ya lo comprueba en su seccion 8 y escupe el comando
exacto. **Correrlo es obligatorio antes de cualquier demo.**

**Tras reactivarlos, la primera corrida del script suele fallar en la seccion 5
(el EDA).** No es un error: los consumidores tardan alrededor de un minuto en
empezar a leer de verdad aunque la consola ya los muestre `Enabled`. Vuelve a
correr el script y pasa. Por eso conviene hacer esto con 15 minutos de margen y
no justo antes de exponer.

### Y la region

El bloque que AWS Academy da para `~/.aws/credentials` **no trae la region**.
Si falta, el CLI falla con `NoRegion`. Queda fijada aparte en `~/.aws/config`:

```ini
[default]
region = us-east-1
output = json
```

Ese archivo no caduca, asi que solo se crea una vez.
