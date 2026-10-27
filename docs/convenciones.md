# Convenciones técnicas — todos los repos

**Runtime único: Python 3.12.** Región `us-east-1`. Stage `dev`.

## Estructura de repo (igual en los 6)

```
ms-<nombre>/
├── serverless.yml
├── requirements.txt
├── INTEGRANTE.md
├── README.md            # endpoints + cómo probarlos
├── src/
│   ├── handlers/        # una función por endpoint
│   │   ├── crear.py
│   │   ├── listar.py
│   │   └── worker.py    # consumidor SQS (si aplica)
│   ├── db.py            # conexión + SET search_path  (o cliente DynamoDB)
│   ├── eventos.py       # publicar() a SNS
│   └── respuesta.py     # ok() / error() con los headers CORS
├── seed/
│   └── generar.py       # 30,000 registros en 3 tenants
└── docs/
    ├── modelo.md        # ER (SQL) o estructura JSON (NoSQL)
    └── capturas/
```

## Dependencias comunes

```
PyJWT==2.9.0              # solo ms-identidad y el authorizer
psycopg[binary]==3.2.3    # solo los 3 MS con RDS
boto3                     # ya viene en el runtime, NO lo pongas en requirements
```

Nada más. Sin ORM, sin FastAPI, sin Flask. Un handler es una función que recibe
`event` y devuelve un dict. Mangum/FastAPI dentro de Lambda solo agrega peso de
arranque y no lo necesitamos para 5 endpoints.

Plugin obligatorio: `serverless-python-requirements` con
`dockerizePip: non-linux` (para que `psycopg` compile para Amazon Linux).

## Contrato de respuesta HTTP

Todos devuelven la misma forma, para que el frontend no tenga 6 casos distintos:

```python
# éxito
{"ok": True,  "datos": <objeto o lista>, "meta": {"total": 120, "cursor": "..."}}
# error
{"ok": False, "error": {"codigo": "NO_ENCONTRADO", "mensaje": "..."}}
```

Códigos HTTP: 200 ok, 201 creado, 400 validación, 401 sin token,
403 tenant equivocado, 404 no encontrado, 500 error interno.

## Cómo se lee el tenant_id (NUNCA de otro lado)

El Lambda Authorizer compartido ya validó el JWT y dejó esto listo:

```python
def tenant_de(event):
    return event["requestContext"]["authorizer"]["tenant_id"]
```

- **Jamás** `event["body"]["tenant_id"]` ni `?tenant_id=`. Si lo haces,
  cualquier usuario puede leer los datos de otro tenant y el ACL lo va a probar.
- En RDS: `SET search_path TO t_<tenant>` al abrir la conexión, y de ahí en
  adelante los queries van sin prefijo.
- En DynamoDB: la partition key siempre empieza con `TENANT#<tenant_id>`.

## Variables de entorno (mismos nombres en los 6)

| Variable | De dónde sale |
|---|---|
| `JWT_SECRET` | SSM Parameter Store `/ppm/jwt-secret`, creado por infra-compartida |
| `SNS_TOPIC_ARN` | Output de CloudFormation de infra-compartida |
| `BUCKET_DATALAKE` / `BUCKET_ADJUNTOS` | idem |
| `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | SSM, uno por microservicio |

Nunca una credencial escrita en el `serverless.yml`. Se importan así:

```yaml
environment:
  JWT_SECRET: ${ssm:/ppm/jwt-secret}
  SNS_TOPIC_ARN: ${cf:infra-compartida-dev.SnsEventosArn}
```

## Nomenclatura

- Repos: `ms-identidad`, `ms-portafolios`, `ms-tareas`, `ms-recursos`,
  `ms-presupuestos`, `ms-analitico`, `web-ppm`, `infra-compartida`
- Stacks: `ppm-<servicio>-<stage>`
- Tablas DynamoDB: `ppm-<servicio>-<entidad>-<stage>`
- Schemas RDS: `t_acme`, `t_globex`, `t_initech`
- Rutas: plural y en español — `/proyectos`, `/proyectos/{id}/tareas`
- Código, tablas y columnas: **español**, snake_case. Sin mezclar idiomas.

## Decisión: Lambdas fuera de la VPC

El RDS queda `PubliclyAccessible` con Security Group restringido al 5432, y las
Lambdas **no** se meten en la VPC.

**Por qué:** una Lambda dentro de una VPC pierde salida a internet y a SNS/S3/
DynamoDB salvo que haya NAT Gateway o VPC Endpoints, y en AWS Academy el NAT
está limitado. Como los 3 MS con RDS también publican a SNS, estarían en el peor
caso posible. Además se evitan los cold starts por creación de ENI.

**Qué decir en el informe:** que en producción el RDS iría en subnet privada con
las Lambdas en VPC y VPC Endpoints para SNS/S3, y que se optó por acceso público
restringido por las limitaciones del laboratorio. La competencia evaluada pide
explícitamente "comprender las limitaciones" de las herramientas: reconocer el
trade-off suma, esconderlo resta.

## Git

- Rama `main` protegida no, pero **nadie hace push a main de otro repo**.
- Commits en español, imperativo: `agrega endpoint de listado de proyectos`.
- Sin Co-Authored-By.
