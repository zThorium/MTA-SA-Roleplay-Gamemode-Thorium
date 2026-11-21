# Trabajos (`rp_jobs`)

Seis trabajos civiles pensados para que no sea "repetir lo mismo para ganar dinero": cada
turno mezcla conducir o caminar por el mapa con **minijuegos en CEF** y eventos al azar,
el jugador sube de nivel en cada trabajo y lo que produce se vende en **mercados con
precios que cambian**.

## Cómo se juega

1. Se consigue el trabajo en la **agencia de trabajos** (`rp_agency`, otro recurso) o,
   mientras `JOBS_CONFIG.HIRE_AT_HQ = true`, en la propia sede con E. Cambiar de trabajo
   tiene una espera de `CHANGE_COOLDOWN_MIN` minutos. `/dejartrabajo` para renunciar.
2. En la **sede** (marcador del color del trabajo; la propia se ve desde todo el mapa)
   se abre con E el panel: nivel, experiencia, ganado, mejor turno y **Empezar turno**.
3. Durante el turno, un panel a la izquierda dice qué hacer y cuánto llevas. El punto
   siguiente sale con marcador y blip; los de "Pulsa E" se activan al estar encima.
4. El turno termina en la sede, con `/terminarturno`, al morir, al cambiar de trabajo o
   si dejas el vehículo de trabajo solo más de 4 minutos a más de 400 m.

`/trabajo` te recuerda tu trabajo y marca la sede con GPS.

## Los trabajos

| Trabajo | Bucle | Minijuegos | Paga |
|---|---|---|---|
| 🗑️ **Recolector de basura** | Ruta de 5 paradas al azar en Los Santos con el camión. En cada una cargas 2-4 bolsas (se llevan en la mano hasta la parte de atrás del camión). Al volver a la planta, bono y nueva ruta. | **Compactador** (vista del interior del camión, estilo Chinatown Wars): arrastrar bolsas al compactador, reciclables al contenedor, no tocar jeringas y llevarte al bolsillo lo que brilla bajo las bolsas (anillos, relojes, vinilos, fajos de billetes...). | $60-120 por parada + $150 por ruta. Hallazgos al inventario (o dinero). |
| 🌾 **Granjero** | Temporada con un cultivo al azar: arar con el tractor, sembrar a mano, 1-2 cuidados al azar, cosechar con la cosechadora y llevar al silo. | **Siembra** (timing), **Plaga** (aplastar bichos), **Riego** (manguera sin encharcar), **Malas hierbas** (arrancar sin tocar el cultivo). | $250-500 por cosecha según la calidad media. |
| 🪓 **Leñador** | 4 árboles marcados en Shady Creeks, cargar los troncos en el camión (se ven en la caja) y llevarlos al aserradero. | **Talar**: elegir hacia dónde cae (evitando camino, cabaña, cables...) y hachazos en la zona verde. **Aserradero**: seguir la línea de corte. | $45-90 por tronco según caída y corte. |
| 🦌 **Cazador** | Zona de caza con quad. Rastro de 4-6 huellas que se enfría si tardas; al final, el animal. | **Huellas** (elegir la fresca; fallar alarga el rastro), **Mira** (balanceo, respiración con Shift, viento y caída), **Despiece** (trazar la línea). | Carne, pieles y cornamentas al inventario; se venden en la peletería. Jabalí y oso cargan si fallas. |
| 🎣 **Pescador** | Muelle a pie o barco (nivel 2). Cada punto se agota tras unas capturas. | **Pesca**: lanzamiento con fuerza justa, picada (no picar a los amagos) y recoger manteniendo el pez en la zona verde sin romper el sedal. | Sardina, lubina, atún, pez espada (nivel 3), bota vieja, botella con mensaje, perla. Se venden en la lonja o la compraventa. |
| ⛏️ **Minero** | 5 vetas por tanda en la cantera Hunter; luego salen otras. | **Veta** (grietas que brillan; golpes en roca sana cansan), **Dinamita** (nivel 2: retirarte en el momento justo), **Derrumbe** (teclas a tiempo o daño). | Carbón, hierro, cobre, plata (nv 2), oro (nv 3) y gemas. Se venden en la fundición o la compraventa. |

**Niveles**: XP por cada tarea (`LEVEL_XP = 0, 120, 320, 650, 1100`). Cada nivel paga un
8% más y desbloquea cosas (barco, jabalí y oso, plata y oro, dinamita, más hallazgos en
la basura). La XP se guarda por trabajo: si vuelves a un trabajo antiguo conservas tu nivel.

**Mercados** (`MARKETS` en `shared/s_config.lua`): Lonja del puerto, Carnicería y
peletería, Fundición de la cantera y Compraventa El Trapero. Cualquiera puede vender
(se puede rolear la reventa). El precio de cada producto se mueve cada 15 min entre el
60% y el 135% del base, baja un 1,2% por unidad vendida y vuelve poco a poco a su valor.

## Seguridad

- El cliente solo avisa "llegué" o "terminé el minijuego"; el servidor comprueba que el
  punto es el actual, la distancia (con margen), si vas a pie o en el vehículo del trabajo,
  y que el minijuego tiene el token correcto y no terminó antes de un tiempo mínimo.
- Los resultados de los minijuegos se acotan en el servidor (`min`/`max`) y el pago por
  tarea tiene tope (`MAX_TASK_PAY`). Lo que se puede encontrar en la basura lo sortea el
  servidor antes de abrir el compactador: el cliente solo elige cuáles de esos se queda.
- Vender: distancia al mostrador, que tengas el objeto, `takeItem` antes de pagar.
- Los vehículos de trabajo solo los conduce su trabajador (`rp:jobVehicle` en el vehículo).

## API para otros recursos

Exports de **servidor**:

| Export | Devuelve |
|---|---|
| `getJobList()` | Array de `{ id, name, icon, description, pay, howTo, requirements, locationName, location = {x, y, z, interior, dimension}, color = {r, g, b}, cinematic }` |
| `getJobInfo(jobId)` | Lo mismo para un trabajo, o `false` |
| `getPlayerJob(player)` | Id del trabajo (`"garbage"`, `"farmer"`, `"lumber"`, `"hunter"`, `"fisher"`, `"miner"`) o `nil` |
| `setPlayerJob(player, jobId [, force])` | `true` o `false, motivo`. `force` salta la espera entre cambios |
| `quitPlayerJob(player)` | `true` o `false, motivo` |
| `isPlayerOnShift(player)` | `true` si está de turno |
| `getPlayerJobLevel(player [, jobId])` | Nivel (1-5) |
| `getPlayerJobStats(player [, jobId])` | `{ xp, level, tasks, earned, bestShift }` o `false` |
| `showJobLocation(player, jobId)` | Pone un blip y una flecha en la sede; se quitan al llegar |
| `getMarketPrice(marketId, itemId)` | Precio actual o `false` |

Exports de **cliente**: `playJobCinematic(jobId)` (recorre los planos de `cinematic` con
bandas negras y subtítulos; Espacio la salta; al acabar dispara en `localPlayer` el evento
de cliente `rp:jobs:onCinematicEnd` con el `jobId`), `stopJobCinematic()`, `isJobCinematicPlaying()`.

Cada plano de `cinematic` es `{ cam = {x, y, z}, look = {x, y, z}, ms, text }`.

Element data: `rp:job` (id del trabajo o `false`, sincronizado), `rp:jobShift` (id si está de turno).
Eventos de servidor: `rp:jobs:onJobChanged` (source = jugador; `nuevoId` o `false`, `anteriorId`) y
`rp:jobs:onShiftEnd` (source = jugador; `jobId`, `ganado`, `tareas`).

### Contrato con la agencia (`rp_agency`)

La agencia llama a `getJobList()` para mostrar los trabajos, reproduce `cinematic` en
"Más información", asigna con `setPlayerJob` y usa `showJobLocation` para "cómo llegar".
Cuando la agencia esté en el servidor, pon `JOBS_CONFIG.HIRE_AT_HQ = false` para que el
puesto solo se pida allí.

## Añadir un trabajo nuevo

1. Entrada en `JOBS` (y sus ajustes) en `shared/s_config.lua`.
2. `server/jobs/s_<id>.lua` con `Jobs.register("<id>", { start, onReach, onGame, stop?, tick?, options?, perks })`:
   - `Jobs.waypoint(player, { kind, x, y, z, r, mode = "drive"|"foot"|"any", act = "enter"|"press", text, label })`
   - `Jobs.game(player, "nombre", params, msMinimo)` y el resultado llega a `onGame(player, s, nombre, resultado)`
   - `Jobs.pay`, `Jobs.xp`, `Jobs.give`, `Jobs.hud`, `Jobs.props`, `Jobs.propFx`, `Jobs.hold`, `Jobs.anim`, `Jobs.spawnVehicle`
3. Si tiene minijuego nuevo, `html/games/<archivo>.js` con `JG.register("nombre", { title, help, start(stage, params, api) })`
   y una demo en `window.JG_DEMOS` (se prueba abriendo `html/index.html?demo=nombre` en un navegador).
4. Los objetos nuevos, en `rp_inventory/shared/s_items.lua`; si se venden, en un `MARKETS`.
5. Archivos nuevos en `meta.xml`.

## Pendiente o por ajustar en juego

- Las coordenadas Z son aproximadas; marcadores y objetos se ajustan al suelo cuando la
  zona carga. Conviene revisar sedes, puntos de pesca y árboles con un admin en juego.
- Árboles, rocas y bolsas los ve solo el trabajador (son objetos de cliente).
- Los vehículos de trabajo no tienen combustible propio ni llaves (no están en la tabla `vehicles`).
