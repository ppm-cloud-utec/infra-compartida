# Modelo de Eventos (EDA)

Un solo topic SNS de dominio: **`ppm-eventos`**. Cada evento lleva atributos de
mensaje para que las colas filtren, y un cuerpo JSON con esta forma:

```json
{
  "evento_id": "uuid-v4",
  "tipo": "gasto.registrado",
  "version": 1,
  "tenant_id": "t-acme",
  "ocurrido_en": "2026-11-05T14:22:01Z",
  "origen": "ms-presupuestos",
  "datos": { }
}
```

Atributos de mensaje SNS (para las *filter policies*): `tipo`, `tenant_id`,
`origen`.

## Catálogo de eventos

| Evento | Lo publica | Lo consume | Efecto en el consumidor |
|---|---|---|---|
| `proyecto.creado` | ms-portafolios | ms-presupuestos, ms-analitico | crea el presupuesto en 0; registra el proyecto en el data lake |
| `proyecto.priorizado` | ms-portafolios | ms-analitico | recalcula el ranking del portafolio |
| `tarea.creada` | ms-tareas | ms-portafolios, ms-analitico | incrementa el total de tareas del proyecto |
| `tarea.completada` | ms-tareas | ms-portafolios, ms-analitico | **recalcula el % de avance del proyecto** |
| `recurso.asignado` | ms-recursos | ms-presupuestos, ms-analitico | proyecta el costo de horas-hombre |
| `recurso.sobreasignado` | ms-recursos | ms-alertas (SQS) | notifica al PM: la persona pasó del 100% de capacidad |
| `gasto.registrado` | ms-presupuestos | ms-analitico | actualiza la ejecución presupuestal |
| `presupuesto.excedido` | ms-presupuestos | ms-alertas (SQS), ms-portafolios | notifica y marca el proyecto en riesgo |

## Colas SQS

| Cola | Filtro (`tipo`) | Lambda worker | DLQ |
|---|---|---|---|
| `cola-portafolios` | `tarea.*`, `presupuesto.excedido` | `ms-portafolios/worker` | sí |
| `cola-presupuestos` | `proyecto.creado`, `recurso.asignado` | `ms-presupuestos/worker` | sí |
| `cola-analitico` | **todos** | `ms-analitico/ingesta` → S3 | sí |
| `cola-alertas` | `*.excedido`, `*.sobreasignado` | `ms-analitico/notificador` → SNS `ppm-alertas` | sí |

Todas con `maxReceiveCount: 3` y `batchSize: 10`.

## Reglas para todos

1. **Idempotencia obligatoria.** SQS garantiza *at-least-once*: el mismo evento
   puede llegar dos veces. Guarda los `evento_id` ya procesados (tabla
   `eventos_procesados`) y descarta repetidos. Si no lo haces, el % de avance y
   la ejecución presupuestal van a quedar inflados en la demo.
2. **Nunca confíes en el `tenant_id` del body de una request HTTP.** Solo en el
   del JWT. En eventos sí se usa el del cuerpo, porque el productor es de
   confianza.
3. **Nunca publiques antes de confirmar la escritura.** Primero commit en la BD,
   después `sns.publish`.
4. **Versiona el evento.** Si cambias el `datos`, sube `version` y avisa al grupo.

## Lo que hay que mostrar en la demo

El flujo visible de punta a punta: en el tenant Acme completar una tarea en el
frontend → el % de avance del proyecto se actualiza sin que el frontend llame a
`ms-portafolios` → y registrar un gasto que cruce el 90% del presupuesto →
llega la alerta. Eso es la prueba de que el sistema es event-driven y no un
monolito repartido.
