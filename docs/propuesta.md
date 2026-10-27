# Propuesta funcional — "Portafolio", un SaaS de PPM

## El problema que resuelve

Una empresa mediana tiene 20 proyectos corriendo al mismo tiempo, S/ 2 millones
de presupuesto anual y 40 personas. Cada gerente de proyecto sabe cómo va **su**
proyecto. Nadie sabe cómo va **el conjunto**:

- ¿En qué estamos gastando realmente la plata, y cuánto queda?
- ¿Quién está sobrecargado y quién está libre?
- ¿Qué proyecto se va a caer este mes?
- Si solo puedo financiar 5 de 12 proyectos el próximo trimestre, ¿cuáles?

Esas cuatro preguntas son el producto. Todo lo que construimos existe para
responderlas en una pantalla.

## La diferencia con un gestor de tareas

Esto **no** es Trello ni Jira, y es importante tenerlo claro porque es el error
en el que cae cualquiera que escuche "proyectos y tareas".

| | Gestor de tareas | PPM (lo nuestro) |
|---|---|---|
| Quién lo usa | el equipo que ejecuta | la dirección que decide |
| Pregunta que responde | ¿qué hago hoy? | ¿en qué invertimos y a costa de qué? |
| Unidad de trabajo | la tarea | el **portafolio** |
| Lo central | el tablero | el presupuesto, la capacidad y la prioridad |

La capa que nos hace PPM es el **portafolio**: el nivel que está *encima* de los
proyectos, donde se compara, se prioriza y se reparte plata y gente. Las tareas
están ahí solo porque son la fuente del % de avance real.

## Los usuarios (4 roles por tenant)

| Rol | Qué hace |
|---|---|
| **Admin** | crea usuarios de su organización |
| **Director de portafolio (PMO)** | crea portafolios, prioriza proyectos, aprueba presupuestos, vive en el dashboard |
| **Gerente de proyecto (PM)** | planifica tareas, pide recursos, registra gastos de su proyecto |
| **Miembro de equipo** | marca sus tareas como completadas |

## Qué se puede hacer (el alcance)

### Admisión de demanda (intake)
Cualquiera en la organización propone un proyecto a través de un formulario:
qué es, qué problema resuelve, costo estimado, beneficio esperado. Entra como
`propuesto` a una bandeja, y el PMO lo **aprueba o rechaza**. Nada se convierte
en proyecto sin pasar por ahí.

Es lo que Smartsheet llama *"flujos de trabajo de admisión y aprobación
centralizados"*. Vale la pena construirlo porque es barato (un formulario y dos
botones) y es lo que distingue un PPM de una lista de proyectos: aquí hay una
**puerta de entrada con decisión**.

### Portafolios y proyectos
Agrupar proyectos en portafolios por objetivo estratégico. Cada proyecto tiene
estado (`propuesto`, `aprobado`, `en curso`, `en pausa`, `cerrado`), fechas,
responsable, **prioridad** y un **semáforo de salud** (verde / ámbar / rojo) que
el sistema calcula solo, no se pone a mano.

### Priorización contra capacidad real
Cada proyecto propuesto recibe un **score de prioridad** calculado a partir de
valor estratégico, urgencia, costo y riesgo. El PMO ve el ranking ordenado y
decide qué entra al trimestre.

Pero el ranking solo no sirve: al marcar los proyectos que quiere aprobar, el
sistema le dice **cuánto presupuesto y cuánta capacidad del equipo consumen en
total**, y si se pasa de lo disponible. Planview lo vende exactamente así:
priorizar *"contra criterios de inversión, no por intuición"* y modelar las
decisiones *"contra la capacidad real antes de comprometerse"*.

Es la función por la que una empresa paga por un PPM en vez de usar un Excel, y
es nuestro diferenciador frente a un gestor de tareas.

### Tareas e hitos
El PM descompone el proyecto en tareas con responsable, fechas y dependencias.
Cuando el equipo completa tareas, **el % de avance del proyecto se recalcula
solo**. Nadie reporta avance a mano — ahí está el valor y ahí está el evento.

### Recursos y capacidad
Personas con rol, costo por hora y capacidad semanal. Se asignan a proyectos con
un % de dedicación. Si Ana queda al 150% entre dos proyectos, el sistema
**detecta la sobreasignación y avisa** en vez de esperar a que ella se queme.

### Presupuestos
Monto aprobado por proyecto, gastos registrados, y la **ejecución** (gastado vs
aprobado) calculada en vivo. Al cruzar el 90% el proyecto se marca en riesgo
automáticamente y le llega la alerta al PMO.

### Dashboard ejecutivo
Las cuatro preguntas del inicio, en una pantalla: semáforo de todos los
proyectos, presupuesto total aprobado vs ejecutado, mapa de carga del equipo,
y el ranking de prioridad del próximo trimestre.

## Los 3 tenants (y por qué son distintos)

No son "empresa 1, 2, 3". Cada una usa el mismo producto para algo distinto, que
es justamente el argumento de por qué un SaaS multi-tenant tiene sentido:

| Tenant | Organización | Sus portafolios son… | Sus proyectos son… |
|---|---|---|---|
| `t-acme` | Acme Ingeniería | líneas de obra | obras civiles con alto presupuesto y pocos recursos |
| `t-globex` | Globex Consulting | carteras de cliente | consultorías cortas, muchos recursos compartidos |
| `t-initech` | Initech Software | líneas de producto | desarrollos largos con tareas muy divididas |

Los datos ficticios deben reflejar eso: Acme con proyectos de S/ 500,000 y 12
tareas; Initech con proyectos de S/ 30,000 y 400 tareas. Si los tres tenants
tienen datos idénticos, el multi-tenancy se ve falso en la demo.

## El recorrido de la demo (10 minutos, 2 tenants)

1. **Login como PMO de Acme.** El dashboard muestra solo los datos de Acme.
2. **Revisar la bandeja de admisión:** hay 3 propuestas pendientes. El PMO ve
   el ranking por score, marca dos y el sistema avisa que juntas se pasan del
   presupuesto disponible. Aprueba una.
   → se dispara `proyecto.creado` y el presupuesto nace solo en 0.
3. **Asignar a dos personas.** Una ya estaba al 70% en otra obra → salta la
   **alerta de sobreasignación**. (evento `recurso.sobreasignado`)
4. **Completar una tarea** como miembro del equipo → volver al dashboard y ver
   que **el % de avance subió sin que nadie lo escribiera**.
   (evento `tarea.completada`, es el momento clave de la demo)
5. **Registrar un gasto** que cruza el 90% del presupuesto → el proyecto pasa a
   **rojo** y llega la alerta. (evento `presupuesto.excedido`)
6. **Cerrar sesión y entrar como Globex.** Mismos endpoints, mismas pantallas,
   **datos completamente distintos** y cero rastro de Acme. Ahí se demuestra el
   aislamiento.
7. **Correr `verificar.sh`:** token de Globex pidiendo un proyecto de Acme → 403.

## Cómo se reparte en los 6 microservicios

| Funcionalidad del producto | Microservicio |
|---|---|
| Organizaciones, usuarios, roles, login | `ms-identidad` |
| Portafolios, proyectos, estados, prioridad, salud | `ms-portafolios` |
| Tareas, hitos, dependencias, avance | `ms-tareas` |
| Personas, capacidad, asignaciones, sobreasignación | `ms-recursos` |
| Presupuesto aprobado, gastos, ejecución | `ms-presupuestos` |
| Dashboard ejecutivo, KPIs históricos | `ms-analitico` |

El corte no es arbitrario: **cada microservicio es dueño de una sola pregunta
del negocio**. Por eso ninguno necesita llamar a otro por HTTP — cuando algo
cambia en su dominio, publica el evento y los demás reaccionan.

---

## Vistas del frontend (las 5 que tienen los tres referentes)

Los tres productos coinciden en el mismo conjunto de vistas sobre los mismos
datos. Esto es el checklist de `web-ppm`, que vale 6 de los 20 puntos:

| Vista | Qué muestra | Lo alimenta |
|---|---|---|
| **Tabla / Grid** | listado filtrable de proyectos con estado, prioridad, avance, presupuesto | ms-portafolios |
| **Kanban** | proyectos (o tareas) en columnas por estado, arrastrables | ms-portafolios / ms-tareas |
| **Gantt / Timeline** | proyectos y tareas en el tiempo, con hitos y dependencias | ms-tareas |
| **Carga del equipo (Workload)** | cada persona y su % de ocupación por semana, en rojo si pasa del 100% | ms-recursos |
| **Dashboard** | semáforo del portafolio, presupuesto aprobado vs ejecutado, ranking de prioridad | ms-analitico |

Más la **bandeja de admisión** y el **formulario de propuesta**.

> Si el tiempo aprieta, la que se puede recortar es el Gantt (es la más caro de
> construir). Las otras cuatro no: tabla, kanban, carga y dashboard son lo que
> hace que el producto se vea como un PPM y no como un CRUD.

## De dónde sale cada idea (las 3 referencias del enunciado)

Conviene tener esta tabla en el informe: demuestra que el alcance no se inventó,
sino que se tomó de los productos líderes del rubro.

| Lo nuestro | monday.com | Smartsheet | Planview |
|---|---|---|---|
| Portafolios sobre proyectos | *portfolio management* | visibilidad de proyecto y portafolio | portafolios, alineamiento estratégico |
| Admisión y aprobación | formularios | flujos de admisión y aprobación | *demand intake* |
| Priorización por score | — | — | priorización dinámica por criterios de inversión |
| Priorizar contra capacidad | — | planificación de capacidad | *scenario planning* contra capacidad real |
| Carga y capacidad del equipo | *workload*, asignación de recursos | equilibrio de carga de trabajo | reasignación dinámica de recursos |
| Presupuesto vs ejecutado | *budget remaining* en dashboards | — | trazabilidad inversión → resultado |
| Tareas, hitos, dependencias | gantt, dependencias | hitos y dependencias | — |
| Semáforo y alertas | automatizaciones | automatización de flujos | detección temprana de riesgo |
| Dashboard ejecutivo | dashboards | paneles de portafolio | indicadores de salud del portafolio |

**Lo que deliberadamente NO hacemos** (está en los tres, pero no en 4 semanas, y
nada de esto está en la rúbrica): integraciones con Jira/Salesforce, IA y
agentes, automatizaciones configurables por el usuario, documentos
colaborativos, no-code, y gestión de pruebas.

## Lo que este producto NO es

Aclaración porque el nombre "proyectos y recursos" se presta a confusión:

- **No es una red social ni un LinkedIn.** No hay perfiles públicos, contactos,
  feed, ni postulaciones. Los "recursos" son los empleados de *esa misma*
  organización, vistos como capacidad de trabajo asignable: cuántas horas
  semanales tienen y a qué proyectos están dedicados.
- **No es un marketplace.** Los tenants no se ven entre sí ni intercambian
  nada. Cada organización está completamente aislada.
- **No es un gestor de tareas.** Las tareas son insumo del % de avance, no el
  centro del producto.
- **No es un ERP ni contabilidad.** El presupuesto se controla a nivel de
  proyecto (aprobado vs gastado), no hay asientos ni facturación.
