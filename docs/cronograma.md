# Cronograma — hoy 23-oct, entrega 22-nov

## Hitos del curso

| Fecha | Qué |
|---|---|
| **Sáb 14-nov** | Exposición virtual con el ACL · avance ≥30% · **3 puntos** |
| **Dom 22-nov 23:59** | Informe (Word/PDF) + PPT en Canvas · links a repos + diseño de BD |
| **Semana 16** | Exposición presencial + demo con 2 tenants · **obligatoria** |

> Si alguien no se presenta a la exposición presencial, su nota máxima es 10.

## Plan por semanas

### Semana 1 — 23 al 29 de octubre · *cimientos*
- Osmar: crear la org y los 7 repos, `infra-compartida` desplegada (RDS, SNS,
  S3, authorizer) y `ms-identidad` emitiendo JWT con `tenant_id`.
- Todos: `serverless.yml` mínimo desplegado con un endpoint `/health` protegido
  y el modelo de datos (`docs/modelo.md`) escrito.
- **Bloqueante:** nadie puede avanzar en serio hasta que el authorizer exista.
  Es lo primero.

### Semana 2 — 30 de octubre al 5 de noviembre · *CRUD y datos*
- Cada MS: endpoints CRUD completos y el `seed/` cargando los 30,000 registros.
- Frontend: login funcionando contra `ms-identidad` + shell del dashboard.

### Semana 3 — 6 al 12 de noviembre · *eventos*
- Publicación a SNS y workers de SQS con idempotencia.
- Frontend: consumiendo los 5 MS.
- **Mié 12-nov: ensayo interno completo.** Lo que no funcione aquí, no entra.

### Jue 13 y vie 14 de noviembre · *exposición ACL*
- Diagrama de arquitectura terminado.
- Guion de 10 minutos: multi-tenancy, un endpoint protegido, un evento
  fluyendo, el conteo de registros.

### Semana 4 — 15 al 21 de noviembre · *cierre*
- Analítico, Athena y dashboard de KPIs.
- Informe + PPT + capturas de todos.
- Ensayo de la demo con 2 tenants.

### Dom 22-nov · subir a Canvas antes de las 23:59.

## Riesgos que ya conocemos

| Riesgo | Mitigación |
|---|---|
| Las credenciales de AWS Academy expiran cada ~4 horas | Todo con `sls deploy`; nada configurado a mano en la consola |
| El RDS es compartido por 3 MS | Database y usuario separados por MS; nadie hace DROP |
| El seed de 30k se vuelve lento | Carga por lotes (`batch_write` / `COPY`), no fila por fila |
| Eventos duplicados inflan los números en la demo | Tabla `eventos_procesados` desde el día 1, no al final |
| Frontend queda para el final y vale 6 puntos | Mocks de los 5 MS desde la semana 1 para no quedar bloqueado |
