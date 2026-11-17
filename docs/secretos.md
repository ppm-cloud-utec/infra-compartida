# Secretos: Secrets Manager y Parameter Store

## El problema que tenia el diseno anterior

Los secretos se resolvian en el DESPLIEGUE:

```yaml
environment:
  JWT_SECRET: ${ssm:/ppm/jwt-secret}
```

Serverless lee ese valor al desplegar y lo escribe como **variable de entorno
de la Lambda**. El secreto termina guardado en la configuracion de la funcion
y en la plantilla de CloudFormation. Cualquiera que pueda abrir la consola de
Lambda lo lee en texto plano, aunque en Parameter Store estuviera cifrado.

Con `JWT_SECRET` eso no es un detalle: quien lo lee puede **firmar un token
valido para cualquier tenant**, y el authorizer lo aceptaria. Todo el
aislamiento multi-tenant del sistema descansa en esa cadena.

Estaba asi en 6 sitios: el JWT en el authorizer y en ms-identidad, y las
credenciales de base de datos de los tres microservicios de RDS.

## Como quedo

La Lambda ya no recibe el secreto, recibe **su nombre**:

```yaml
environment:
  JWT_SECRET_NOMBRE: ppm/jwt-secret
```

`src/secretos.py` lo resuelve contra Secrets Manager la primera vez que hace
falta y lo cachea 15 minutos en memoria. Como Lambda reutiliza el contenedor
entre invocaciones, es una lectura por contenedor, no una por peticion.

Ahora la configuracion de cualquier funcion se puede enseñar en pantalla sin
filtrar nada. Eso es comprobable en la demo: abre la consola de Lambda, mira
las variables de entorno y solo hay rutas.

| Secreto | Contenido |
|---|---|
| `ppm/jwt-secret` | clave HS256 que firma y valida los tokens |
| `ppm/portafolios/db` | `{"username":…,"password":…}` |
| `ppm/recursos/db` | idem |
| `ppm/presupuestos/db` | idem |
| `ppm/rds/master` | usuario maestro, para los scripts de administracion |

## Por que no todo se movio

**Parameter Store sigue en uso, a proposito.** La separacion es:

- **Secrets Manager**: lo que, filtrado, compromete el sistema.
- **Parameter Store**: configuracion que no es secreta, como `/ppm/tenants`,
  la lista de organizaciones habilitadas.

Meter configuracion en Secrets Manager cuesta dinero por secreto y sugiere
que es confidencial cuando no lo es.

**Las credenciales maestras del RDS siguen tambien en SSM** para
CloudFormation:

```yaml
MasterUsername: ${ssm:/ppm/rds/master-user}
MasterUserPassword: ${ssm:/ppm/rds/master-password}
```

CloudFormation solo las usa al CREAR la instancia y ese valor nunca llega a
una Lambda. Cambiarlas por una referencia dinamica a Secrets Manager
arriesgaria una modificacion del RDS a cambio de nada. Estan duplicadas en
`ppm/rds/master` para los scripts de administracion, que si leen de Secrets
Manager.

## Limitaciones conocidas

- **Una lectura por arranque en frio.** Añade unos 50 ms al primer request de
  cada contenedor. A cambio el secreto no queda grabado en ningun sitio.
- **Sin rotacion automatica.** Secrets Manager la soporta con una Lambda de
  rotacion; aqui no se implemento porque rotar la clave del JWT invalidaria
  todos los tokens vigentes y rotar la de base de datos exige coordinar el
  cambio con PostgreSQL. Con la cache de 15 minutos, una rotacion se
  propagaria sola en ese plazo.
- **Reusa `LabRole`,** que puede leer cualquier secreto de la cuenta. Con
  roles propios, cada microservicio solo podria leer el suyo.

## Migrar o re-sincronizar

```bash
cd infra-compartida
./scripts/migrar-secretos.sh     # idempotente: copia SSM -> Secrets Manager
```

Copia, no regenera: cambiar los valores obligaria a recrear las bases y
dejaria sin validez todos los tokens emitidos.
