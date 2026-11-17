# Alta de organizaciones con Step Functions

## El problema que resuelve

Hasta la version anterior los tenants estaban escritos en el codigo de los
tres microservicios que usan RDS:

```python
SCHEMAS = {"t-acme": "t_acme", "t-globex": "t_globex", "t-initech": "t_initech"}
```

La multi-tenancy funcionaba, pero quedaba **fijada en tiempo de despliegue**:
dar de alta una organizacion obligaba a editar tres repositorios, redesplegar
y ademas correr `bases.sh` a mano. Eso no es un SaaS multi-tenant, es una
aplicacion con tres clientes cableados.

## Por que una maquina de estados y no una Lambda

Crear una organizacion son seis pasos que tienen que ocurrir **en orden**,
cualquiera puede fallar, y si falla el cuarto hay que deshacer los tres
anteriores o queda una organizacion a medias: visible en el selector del
login pero sin tablas donde guardar nada.

Resolver eso dentro de una sola Lambda significa escribir a mano los
reintentos, el paralelismo y el rollback, con un limite de 15 minutos y sin
ninguna traza de en que paso se rompio. En una maquina de estados las cuatro
cosas son declarativas y cada ejecucion queda registrada paso a paso en la
consola.

## El flujo

```
                        Validar
                           |
                  Registrar identidad          (ms-identidad)
                           |
              +------------+------------+
              |            |            |      en paralelo: no dependen
        Schema          Schema        Schema   entre si
     portafolios      recursos     presupuestos
              |            |            |
              +------------+------------+
                           |
                   Habilitar tenant              (escribe /ppm/tenants)
                           |
                         Listo

   cualquier fallo --> Compensar (5 ramas, best-effort) --> Fallo
```

| Paso | Lo ejecuta | Que hace |
|---|---|---|
| Validar | `ppm-validar-tenant` | formato del id, nombre obligatorio, que no exista ya |
| Registrar identidad | `ms-identidad` | item del tenant + primer usuario admin |
| Schema x3 | cada microservicio RDS | `CREATE SCHEMA` + su propio `esquema.sql` |
| Habilitar tenant | `ppm-publicar-tenants` | agrega el id a `/ppm/tenants` |
| Compensar | los 5 servicios | borra schemas, admin, registro y lo saca de la lista |

## Las tres decisiones que hay que poder defender

**1. Cada microservicio aprovisiona su propia base.** La maquina no abre
PostgreSQL ni escribe en DynamoDB: invoca la Lambda de cada servicio. Si la
orquestacion tocara las bases ajenas, el requisito de que cada microservicio
sea dueno de su BD se romperia justo en la operacion mas delicada. Ademas
cada DDL vive en el repo de su dueno y no hay copias que se desincronicen.

**2. La lista se publica al final.** Mientras las tres bases no esten listas,
el tenant no debe recibir trafico. Publicar antes abriria una ventana en la
que el login funciona y cualquier consulta revienta. Es el ultimo paso a
proposito.

**3. La contrasena del admin nunca entra ni sale de la maquina.** El input y
el output de cada paso quedan en el historial de ejecucion, que es legible
desde la consola. Asi que se genera dentro de la Lambda, se guarda cifrada en
Parameter Store y hacia afuera solo viaja la **ruta** del parametro.

## Limitaciones conocidas

- **La propagacion tarda hasta 60 segundos.** Las Lambdas de negocio cachean
  `/ppm/tenants` ese tiempo para no pegarle a SSM en cada request. Un tenant
  recien creado puede dar `Tenant no autorizado` durante ese minuto. Se
  podria invalidar al instante publicando un evento en el topic SNS; se
  prefirio la cache por simplicidad y porque el alta no es una operacion
  frecuente.
- **El tenant nace vacio.** La maquina crea la estructura, no datos de
  ejemplo. Sembrar 30,000 registros son minutos de trabajo y no corresponde a
  un alta real.
- **Reusa `LabRole`.** En AWS Academy no se pueden crear roles IAM, asi que
  la maquina y las Lambdas comparten el mismo rol amplio. En una cuenta
  propia cada paso llevaria un rol con permisos minimos: la maquina solo
  `lambda:InvokeFunction` sobre esas seis funciones, y cada Lambda solo su
  propia base.
- **No hay baja de tenants.** `Compensar` existe para el rollback de un alta
  fallida, no como operacion de negocio. Dar de baja una organizacion real
  exigiria exportar sus datos antes de borrarlos.

## Como se usa

```bash
cd infra-compartida
./scripts/crear-tenant.sh t-umbrella "Umbrella Corp" farmaceutica
```

La contrasena del admin se lee despues con:

```bash
aws ssm get-parameter --with-decryption \
  --name /ppm/tenants/t-umbrella/admin-password \
  --query Parameter.Value --output text
```

Para la demo conviene lanzarlo desde la **consola de Step Functions**: el
grafo se pinta en vivo y se ve el paralelismo de los tres schemas. Y para
mostrar la compensacion, basta mandar un `tenant_id` con formato valido pero
un `nombre` vacio desde un paso posterior, o apagar momentaneamente una de
las bases.
