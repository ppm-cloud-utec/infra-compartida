# Colección de Postman

`PPM-CS2032.postman_collection.json` — 26 peticiones a los 6 microservicios.

## Importar

Postman → **Import** → arrastra el archivo `.json`.

## Usar

1. Corre **`1. Login Acme`**. El token se guarda solo en la variable `{{token}}`
   y lo usan todas las demás peticiones. No hay que copiarlo a mano.
2. Para cambiar de organización, corre **`1. Login Globex`**. Las mismas
   peticiones devolverán datos completamente distintos.

El `tenant_id` viaja **dentro del token**, nunca en la URL ni en el body. Por
eso basta con volver a hacer login para cambiar de tenant.

## Orden sugerido para la exposición

| Carpeta | Qué demuestra |
|---|---|
| **0. Demostrar que están PROTEGIDOS** | el 401 sin token — palabra textual del enunciado |
| **1. Login** | el JWT con el `tenant_id` adentro |
| **2. AISLAMIENTO entre tenants** | el token de Globex pidiendo un usuario de Acme → **404** |
| **4. EL EDA** | completar una tarea y ver el avance cambiar solo |
| **3, 5, 6, 7** | el resto de los microservicios |

## La carpeta 4 es la importante

Son cuatro pasos en orden:

1. **a)** mira el `avance_pct` del proyecto
2. **b)** copia un `tarea_id` de las pendientes
3. **c)** pégalo en la URL de la petición y complétala — **esto llama solo a
   `ms-tareas`**
4. **d)** espera unos 3 segundos y vuelve a pedir el proyecto: **el avance
   cambió**

Nadie llamó a `ms-portafolios`. Lo recalculó su worker al recibir
`tarea.completada` por SQS. Eso es lo que hay que mostrar.

## Si algo da 401 de golpe

El token dura 12 horas. Vuelve a correr el login.

## Si todo da error de red

El RDS se detiene cuando se cierra el Learner Lab. Arráncalo y espera a que
quede `available`. Afecta a `ms-portafolios`, `ms-recursos` y
`ms-presupuestos`; los otros tres siguen funcionando.
