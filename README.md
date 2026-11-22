# infra-compartida

Recursos compartidos de la plataforma Portafolio (proyecto final de Cloud Computing CS2032, Grupo 4). Se despliega antes que los microservicios, que importan sus salidas.

Crea:

- API Gateway `ppm-api-dev` y el Lambda Authorizer que valida el JWT
- RDS PostgreSQL compartido (una base por microservicio, un schema por organizacion)
- Topics SNS `ppm-eventos` y `ppm-alertas`
- Buckets S3 del data lake y de adjuntos
- Tabla DynamoDB de idempotencia
- Maquina de estados `ppm-aprovisionar-tenant` (Step Functions) para dar de alta organizaciones
- Tabla Glue y workgroup de Athena sobre el data lake
- Alarmas de CloudWatch sobre las DLQ y el tablero `ppm-plataforma-dev`

## Despliegue

```bash
npm install
./scripts/parametros.sh       # solo la primera vez
./scripts/migrar-secretos.sh  # copia los secretos a Secrets Manager
npx serverless deploy
./scripts/bases.sh            # crea las bases y los schemas iniciales
```

Despues se despliegan los seis microservicios.

## Crear una organizacion

```bash
./scripts/crear-tenant.sh t-umbrella "Umbrella Corp" farmaceutica
```

## Verificar el sistema

```bash
./verificar-sistema.sh
```

Prueba login, rechazo sin token, aislamiento entre organizaciones, el flujo de eventos, el data lake, las colas y los disparadores. Si el Learner Lab se apago, los disparadores quedan desactivados y el script indica como reactivarlos.

La coleccion de Postman esta en `postman/`.
