# Eventos dinámicos: propuesta y lluvia de ideas

Estado: **propuesta (fase 1, sin código)**. Nada de esto está implementado. El objetivo es que la ciudad
se sienta viva y variable: que dos noches seguidas en Los Santos no sean iguales, y que los NPC reaccionen,
recuerden y den pie a rol entre jugadores.

> Nota: se pidió apoyarse en `docs/IA_NPCS.md`, pero ese archivo no existe en el repo. Las fases de IA de
> este documento salen de leer `rp_citizens/c_citizens.lua` y su cabecera.

## 1. Qué hay hoy (y qué condiciona el diseño)

| Pieza | Cómo funciona hoy | Qué implica para los eventos |
|---|---|---|
| `rp_citizens` | Peatones y autos **100% en el cliente**; cada jugador ve su propia población (máx. 14 peds / 16 autos, menos de noche). Máquinas de estados: peatón `WALK, IDLE, FLEE, FIGHT, DEAD`; auto `DRIVE, BLOCKED, HONK, AVOID, FLEE, RED, FOLLOW, YIELD, ABANDONED`. Perfiles por zona (`ghetto`, `rich`, `industrial`, `default`), bandas por barrio, patrullas en el tráfico, red vial `getRoadGraph()`. | Los NPC ambientales **no existen en el servidor ni se comparten** entre jugadores. Un "accidente" solo lo ven todos si lo crea el servidor. Hay que separar eventos *locales* (decorado) de eventos *compartidos* (con consecuencias). |
| `rp_emergency` | `/911` con menú policía/bomberos/ambulancia. Solo **ambulancia implementada** (`enabled = true`), con paramédicos IA que circulan por la red vial y reaniman o trasladan. Hook `rp:emergency:onCall` ya previsto para policía y bomberos. Un cliente "controlador" mueve la unidad y el servidor valida. | Es el patrón a copiar para unidades de evento: elementos del servidor + un cliente controlador + tiempos límite y reintentos. Bomberos y policía están por implementar. |
| `rp_wanted` | `reportCrime(jugador, crimen, víctima, dontCare, witnessed)`, estrellas, patrullas, helicóptero, SWAT, cárcel. Policía de servicio no acumula búsqueda. | Los eventos delictivos pueden alimentar `reportCrime` y los avisos a la policía jugadora. |
| `rp_robbery` | Robo a 24/7 con interior propio (dimensión `21000 + id`), miedo, negociación, rehenes. | Base para "atraco con testigos" y para rumores posteriores. |
| `rp_jobs` | 6 trabajos con turnos, mercados dinámicos (`getMarketPrice`), hooks `rp:jobs:onShiftEnd`. | Los eventos pueden mover precios y dar tareas extra a quien está de turno. |
| `rp_needs`, `rp_injury`, `rp_payday`, `rp_factions`, `rp_phone`, `rp_shops`, `rp_properties`, `rp_vehicles`, `rp_hud`, `rp_notify` | Necesidades, abatido, sueldo, facciones, teléfono, tiendas con NPC, casas, autos con combustible, HUD, avisos. | Cada uno ofrece un punto de enganche (sección 5). |
| Hora y clima | **No hay recurso servidor que los gobierne.** `rp_hud` solo lee `getTime()` en el cliente. | Es el primer hueco: sin reloj y clima compartidos no hay eventos de horario ni de clima coherentes. |

Convenciones que se respetan (de `CLAUDE.md` y `docs/CONVENCIONES.md`): una sola conexión MySQL, consultas
asíncronas y parametrizadas, esquema solo hacia adelante al final de `schema.lua`, el servidor valida todo,
eventos `rp:<sistema>:<accion>`, configuración en `shared/s_config.lua`, sin timers por jugador sin limpiar.

## 2. Arquitectura propuesta

### 2.1 Dos niveles de evento

1. **Ambiental (cliente, barato, sin consecuencias).** Lo decide y lo dibuja el cliente de cada jugador
   dentro de `rp_citizens` (o un módulo hermano `rp_citizens` → `c_scenes.lua`). Ejemplos: dos peatones
   discuten en una esquina, un vendedor ambulante, gente mirando un escaparate, un coche con la capota
   abierta y música. Se crean cerca, se destruyen al alejarse, nunca persisten, no dan estrellas ni 911.
   Son el 90% de la sensación de "vida".
2. **Compartido (servidor, con consecuencias).** Lo crea el **director de eventos** en el servidor. Todos
   los jugadores cercanos ven lo mismo, se puede llamar al 911, deja pistas, puede persistir. Usa elementos
   del servidor (peds/vehículos) y, si hace falta IA de movimiento, un cliente **controlador** como en
   `rp_emergency`.

Regla de oro: *si no tiene consecuencias de rol, que sea ambiental; si las tiene, que sea compartido.*
Un evento compartido puede **degradar** a ambiental cuando nadie lo mira (ver 2.6).

### 2.2 Recurso nuevo: `rp_events` (director de eventos)

```
rp_events/
  meta.xml
  shared/s_config.lua     pesos, cooldowns globales, límites, tipos de zona
  shared/s_catalog.lua    definiciones de eventos propias del recurso (las de otros se registran por API)
  server/s_director.lua   el "cerebro": cada tick decide si lanzar algo y qué
  server/s_registry.lua   API: registerEvent / unregisterEvent / listEvents
  server/s_world.lua      reloj y clima compartidos (ver 2.3)
  server/s_state.lua      eventos activos, historial, persistencia ligera en BD
  server/s_admin.lua      /evento, /eventos, /eventoslista (y entrada en rp_adminpanel)
  client/c_events.lua     recibe eventos, dibuja efectos locales, reporta "cerca/lejos"
  client/c_scenes.lua     escenas ambientales locales (nivel 1)
```

Se arranca después de `rp_citizens`, `rp_wanted` y `rp_emergency` en `mtaserver.conf`. Los demás recursos
**no dependen** de `rp_events` para funcionar: se enganchan con la API opcional (sección 2.5) usando `pcall`
sobre el export, igual que `rp_robbery` usa `rp_wanted`.

### 2.3 Reloj y clima compartidos (`s_world.lua`, base de todo)

- Reloj del mundo en el servidor: `setMinuteDuration(...)` configurable (p. ej. 1 minuto de juego = 15 s
  reales, 24 h de juego = 6 h reales) y `setTime` al arrancar. `rp_hud` ya lee `getTime()`, no cambia.
- Clima por **máquina de estados** con transiciones ponderadas (soleado → nublado → lluvia → tormenta →
  niebla...), duración aleatoria y cambio gradual (`setWeatherBlended`). Se expone el estado a los
  clientes por `setElementData(root, "rp:world", {hora, clima, severidad})`.
- Estaciones o "días especiales" por calendario real o de juego (festivo, fin de semana), que cambian
  pesos del director.
- Export: `getWorldState()` -> `{ hour, minute, weather, isNight, isRaining, dayType }`. Los eventos
  consultan esto para sus requisitos.

### 2.4 Definición de un evento

Cada evento es una tabla declarativa más tres callbacks:

```lua
{
  id        = "traffic_accident",
  category  = "traffic",          -- para limitar cuántos de la misma categoría a la vez
  weight    = 10,                 -- peso base en el sorteo
  cooldown  = 600,                -- s antes de poder repetirse (global)
  cooldownPerZone = 1200,         -- s antes de repetirse en el mismo barrio
  duration  = { 240, 600 },       -- s de vida; el director lo limpia si se pasa
  scope     = "shared",           -- "ambient" (cliente) | "shared" (servidor)
  severity  = 2,                  -- 1 leve, 2 medio, 3 grande (cuenta para el presupuesto de drama)
  requires  = {                   -- filtros duros
    zones      = { "ghetto", "default" },   -- perfiles de rp_citizens o nombres de barrio
    hours      = { 6, 23 },                 -- rango de hora de juego (admite cruce de medianoche)
    weather    = nil,                       -- nil = cualquiera
    minPlayers = 1, maxPlayers = nil,       -- jugadores conectados con personaje
    minPlayersNearby = 1,                   -- jugadores a < 120 m del punto elegido
    notWith    = { "blackout" },            -- incompatibles
    needsRoad  = true,                      -- requiere nodo de la red vial cercano
  },
  modifiers = {                   -- multiplican el peso si se cumplen
    { when = { weather = "rain" }, mult = 2.5 },
    { when = { hours = { 22, 5 } }, mult = 1.8 },
    { when = { zones = { "ghetto" } }, mult = 1.5 },
  },
  pickLocation = function(ctx) ... end,   -- devuelve x,y,z (+ extra) o nil
  start        = function(ev) ... end,    -- crea elementos, avisa a clientes
  tick         = function(ev, dt) ... end, -- opcional, cada 1-2 s
  finish       = function(ev, reason) ... end, -- siempre limpia; reason = "timeout"|"resolved"|"cancel"|"abort"
}
```

**El sorteo.** Cada `TICK` (p. ej. 20 s) el director:
1. Calcula el **presupuesto de drama**: un número que sube con el tiempo y con los jugadores activos, y baja
   al lanzar eventos (cuesta su `severity`). Evita ráfagas y mantiene el ritmo. Un servidor con 3 jugadores
   no debería ver un incendio, un atraco y una manifestación a la vez.
2. Filtra por `requires` y por cooldowns (global, por categoría, por zona).
3. Calcula el peso efectivo = `weight × modifiers × factor_de_variedad`, donde el **factor de variedad**
   reduce el peso de lo que salió hace poco (memoria de los últimos N eventos), para que no se repita.
4. Elige por ruleta ponderada, escoge un jugador "ancla" (con preferencia a quien lleva rato sin ver nada)
   y llama a `pickLocation` cerca de él (fuera de vista, como ya hacen los spawns de `rp_citizens`).
5. Reintenta con otro evento hasta 3 veces si no hay ubicación válida; si no, espera al siguiente tick.

**Intensidad configurable** (`/eventosintensidad 0-3`): 0 apagado, 1 tranquilo, 2 normal, 3 movido. Afecta
la tasa de recarga del presupuesto de drama. Un interruptor global `/eventos on|off` para el staff.

**Eventos en cadena.** Un evento puede dejar "semillas" para el director: un robo puede encadenar una
persecución; un accidente grave, un atasco y un desvío; una tormenta, apagones y árboles caídos. Se
implementa como `ev:spawn("otro_evento", params)` desde `tick` o `finish`, sujeto al presupuesto.

### 2.5 API para que otros recursos registren eventos

Exports del servidor (declarados en `meta.xml`; las funciones **no** se pasan entre recursos, así que la
lógica del evento vive en el recurso que lo registra y `rp_events` lo llama por evento de servidor):

```lua
exports.rp_events:registerEvent(def)        -- def = tabla declarativa sin funciones (ver nota)
exports.rp_events:unregisterEvent(id)
exports.rp_events:triggerEvent(id, params)  -- fuerza un evento (admin, misiones, otros sistemas)
exports.rp_events:endEvent(eventId, reason)
exports.rp_events:getActiveEvents([cat])    -- lista de {eventId, id, x, y, z, startedAt, data}
exports.rp_events:getWorldState()
exports.rp_events:addTag(eventId, "witness", player)  -- ver sección 4
```

Nota técnica: como MTA no permite pasar funciones entre recursos, el registro lleva solo datos
(`requires`, `weight`...) y el recurso dueño atiende dos eventos de servidor que dispara el director:
`rp:events:<id>:start` y `rp:events:<id>:finish` (con `eventId` y `data`). El director espera la confirmación
`rp_events:started(eventId, ok)` y limpia por timeout si el recurso dueño no responde. Los eventos propios
de `rp_events` pueden usar callbacks directos porque viven en el mismo recurso.

Eventos de servidor que emite el director, para quien quiera escuchar sin registrar nada:
`rp:events:onStart`, `rp:events:onEnd`, `rp:events:onWorldChanged` (cambio de hora/clima).

### 2.6 Sincronización cliente/servidor

- **Una sola fuente de verdad: el servidor.** El servidor guarda `activeEvents[eventId] = { id, x, y, z,
  dim, int, startedAt, endsAt, data }`. No manda nada a quien está lejos.
- **Streaming por proximidad.** El cliente avisa su zona/celda (rejilla de 150 m) al servidor cada pocos
  segundos; el servidor envía `rp:events:show` solo de los eventos a < 250 m y `rp:events:hide` al alejarse.
  Los elementos del servidor (ped/vehículo) ya hacen su propio streaming; el evento solo manda *metadatos*
  (efectos, sonidos, marcadores, texto).
- **Cliente controlador** (como `rp_emergency`) cuando hace falta IA de movimiento (ambulancia, bomberos,
  grupo de manifestantes que camina): el servidor elige al jugador más cercano, le entrega el control y lo
  revalida; si se va, se reasigna. Los controladores solo mueven; las **decisiones** (muerte, daño, estrellas)
  las valida el servidor.
- **Degradar a ambiental.** Si no hay ningún jugador cerca, el evento compartido no necesita simularse:
  se pausa (o se resuelve "fuera de cámara" con un resultado abstracto, p. ej. "el incendio se apagó solo")
  y se limpia. Ahorra CPU y evita elementos huérfanos.
- **Dimensión/interior.** Los eventos exteriores ignoran jugadores en interiores propios (tiendas con
  dimensión `21000 + id`, casas). Eventos de interior (robo, pelea en un bar) viven en la dimensión del lugar.
- **Reconexión.** Un jugador que entra a mitad de evento recibe el estado actual al spawnear
  (`rp:onCharacterSpawn`), no la historia completa.

### 2.7 Rendimiento

- Presupuesto duro: **máx. 3 eventos compartidos activos** (configurable) y máx. N elementos de servidor
  creados por eventos en total (p. ej. 40). Si se alcanza, el director no sortea.
- El tick del director es de 10-20 s, no por frame. Los `tick` de evento a 1-2 s y solo si hay jugadores cerca.
- Toda limpieza pasa por `finish(reason)` con **tabla de elementos propios por evento**; en
  `onResourceStop` se destruye todo. Nunca timers sueltos sin referencia.
- Las escenas ambientales **respetan el cupo de `rp_citizens`**: una escena cuenta como sus peatones dentro
  de `MAX_PEDS`; no se suma encima. Con `/poblacion` apagada, las escenas también.
- Persistencia mínima: solo lo que debe sobrevivir a un reinicio (ver 6.4); el resto se pierde y está bien.
- Registro para depurar: `outputServerLog` de cada inicio/fin con motivo y duración, y `/eventoslista`.

## 3. Catálogo de ideas

Leyenda: **Alcance** A = ambiental (cliente), C = compartido (servidor). **Esfuerzo** 🟢 bajo · 🟡 medio · 🔴 alto.
**Riesgo** = probabilidad de bugs, abuso o carga. Las integraciones nombran los recursos existentes.

### 3.1 Tráfico y calle

| Evento | Alc. | Descripción y reglas | Integra con | Esf. | Riesgo |
|---|---|---|---|---|---|
| Accidente de tráfico leve | C | Dos autos chocados con luces de emergencia; conductores discuten o intercambian datos. Aviso al 911 → patrulla/ambulancia si hay heridos. Requiere `needsRoad`. Más probable con lluvia y de noche. | `rp_citizens` (red vial), `rp_emergency`, `rp_wanted` | 🟡 | Bajo |
| Accidente grave con heridos | C | Auto volcado, humo, peatones en el suelo (abatidos NPC). Ambulancia y, cuando existan, bomberos. Genera atasco (el tráfico ambiental esquiva/espera). | `rp_emergency`, `rp_injury` | 🔴 | Medio |
| Avería en la calzada | A | Auto parado con capó abierto y balizas; algunos autos esquivan, otros tocan bocina. | `rp_citizens` (AVOID/HONK) | 🟢 | Bajo |
| Atasco | A | Baja la velocidad objetivo en un tramo; sube bocinas. Relacionado con obras o accidentes. | `rp_citizens` | 🟡 | Bajo |
| Obras viales y desvíos | C | Conos y vallas que **cortan un tramo** de la red vial (se marcan los links como bloqueados para NPC y se avisa por la radio/HUD); los autos NPC toman otra ruta. Trabajadores con casco. | `rp_citizens` (`path_links`), `rp_radio` | 🔴 | Medio (rutas rotas) |
| Control policial de carretera | C | Retén con 2 patrullas y conos que revisa documentos (licencia de `rp_driving`, llave de `rp_vehicles`); a un jugador sin licencia le pueden multar. Policía jugadora puede reemplazarlo. | `rp_wanted`, `rp_driving`, `rp_vehicles` (multas) | 🟡 | Medio |
| Persecución policial NPC | C | Un auto huye de 2 patrullas por la ciudad; si el jugador lo ve, puede ayudar (llamar al 911, bloquear) o estorbar. | `rp_wanted`, `rp_citizens` | 🔴 | Medio |
| Conductor ebrio | A | Auto que zigzaguea entre carriles; patrulla NPC lo para y lo detienen. | `rp_citizens` | 🟡 | Bajo |
| Cortejo de bodas / funeral | A | Fila de 3-4 autos decorados con bocinazos; el tráfico cede. Fines de semana. | `rp_citizens` | 🟡 | Bajo |

### 3.2 Calle y gente

| Evento | Alc. | Descripción y reglas | Integra con | Esf. | Riesgo |
|---|---|---|---|---|---|
| Pelea callejera | C | Dos NPC (o bandas rivales por barrio) se golpean; la gente se aparta (FLEE) y mira. Puede escalar a navajazo si nadie interviene. Testigos llaman al 911. | `rp_citizens` (FIGHT), `rp_wanted` | 🟡 | Medio |
| Discusión (escena) | A | Dos peatones gesticulan; a veces un tercero separa. No escala. | `rp_citizens` | 🟢 | Bajo |
| Músico o artista callejero | A | Con sonido local 3D y una gorra para propinas (rol: dar $ → `rp_inventory`/dinero). | `rp_inventory` | 🟢 | Bajo |
| Vendedor ambulante | C | Puesto temporal (comida, flores) con ítems del catálogo y precio dinámico; rol de compra rápida. Horario de mañana/tarde. | `rp_shops`, `rp_needs`, `rp_inventory` | 🟡 | Bajo |
| Mercadillo / feria | C | Zona con varios puestos fines de semana; sube población de la zona y venden ítems raros. | `rp_shops`, `rp_jobs` (mercado) | 🟡 | Bajo |
| Concierto o show en la calle | C | Escenario con sonido, luces y multitud NPC; ruido que atrae a la policía por "molestias". Recurso para eventos de facción o de staff. | `rp_radio`, `rp_factions` | 🔴 | Medio |
| Manifestación | C | Grupo de 8-12 NPC que camina por una ruta con pancartas; corta un carril, la policía acompaña; puede volverse tensa si hay bandas. Enlace con 911. | `rp_citizens`, `rp_wanted` | 🔴 | Medio |
| Evento deportivo / partido | A | Más gente en barras, grupos con camisetas, tráfico a la salida. | `rp_citizens` (POP) | 🟡 | Bajo |
| Festival (Día de... / aniversario) | C | Calendario especial con luces, tiendas con descuento y mini-eventos. Lo activa el staff o el calendario. | `rp_shops`, `rp_payday` | 🟡 | Bajo |
| Carteristas | C | Un NPC roba la cartera de un jugador distraído (resta dinero en mano de forma acotada y deja un aviso); si el jugador reacciona a tiempo, lo atrapa. | `rp_inventory` | 🟡 | **Alto** (percepción de abuso) |
| Persona perdida / mascota perdida | C | Un NPC pide ayuda; llevarla a casa da recompensa (rol, sin combate). | `rp_notify`, dinero | 🟢 | Bajo |

### 3.3 Delitos con testigos

| Evento | Alc. | Descripción y reglas | Integra con | Esf. | Riesgo |
|---|---|---|---|---|---|
| Atraco a tienda (NPC) | C | Un NPC armado entra a un 24/7 mientras hay jugadores cerca; el cajero lanza la alarma; si no interviene nadie, la policía llega. Reutiliza `rp_robbery` con atracador NPC. | `rp_robbery`, `rp_wanted`, `rp_emergency` | 🔴 | Medio |
| Robo de auto | C | Un NPC fuerza un auto aparcado (de NPC, nunca de un jugador). Un testigo grita y llama al 911. | `rp_citizens`, `rp_wanted` | 🟡 | Medio |
| Tiroteo entre bandas | C | Solo en zonas ghetto de noche; dos grupos disparan; la población huye; patrullas con sirenas, ambulancia. | `rp_citizens` (GANGS), `rp_wanted`, `rp_emergency` | 🔴 | **Alto** (carga y fricción con jugadores) |
| Testigos y denuncias | C | Cualquier delito (de jugador o NPC) tiene testigos NPC cerca; guardan "quién y qué" y pueden denunciarlo (ver sección 4). | `rp_wanted` (`witnessed`) | 🟡 | Medio |
| Vandalismo / grafiti | A | NPC rayando una pared; si lo ven jugadores policías, puede ser un delito menor. | decorado | 🟢 | Bajo |

### 3.4 Emergencias y servicios

| Evento | Alc. | Descripción y reglas | Integra con | Esf. | Riesgo |
|---|---|---|---|---|---|
| Incendio de edificio o auto | C | Fuego con humo y daño progresivo; propaga a objetos cercanos si no se apaga. Bomberos IA (cuando existan) o jugadores bomberos con manguera. Por rayo en tormenta, cortocircuito o accidente. | `rp_emergency` (`fire` aún sin implementar), `rp_factions` | 🔴 | **Alto** (fuego en MTA es costoso y puede dañar el rendimiento) |
| Ambulancia en tránsito | A | Ambulancias y patrullas con sirena cruzan la ciudad sin destino real; el tráfico cede (ya existe `sirenBehind` en citizens). | `rp_citizens`, `rp_emergency` | 🟢 | Bajo |
| Fuga de gas / explosión pequeña | C | Cordón de seguridad, evacuación NPC, desvío. | obras viales, bomberos | 🔴 | Alto |
| Rescate (gato en un árbol, persona en azotea) | C | Mini-misión de rol para bomberos/paramédicos jugadores; sin violencia. | `rp_factions` | 🟡 | Bajo |
| Emergencia médica NPC | C | Un peatón se desploma; testigos llaman al 911; la ambulancia viene; si un jugador médico llega antes, puede estabilizar. | `rp_emergency`, `rp_injury` | 🟡 | Bajo |

### 3.5 Clima, horario y mundo

| Evento | Alc. | Descripción y reglas | Integra con | Esf. | Riesgo |
|---|---|---|---|---|---|
| Lluvia y tormenta | C | Calles vacías, paraguas, más accidentes, menos peatones, autos más lentos, mercado de trabajos afectado (agricultores), charcos y relámpagos. | `s_world.lua`, `rp_citizens`, `rp_jobs` | 🟡 | Bajo |
| Niebla / ola de calor | C | Visibilidad reducida; más necesidad de sed (`rp_needs`: multiplicador de `thirst`); menos gente en la calle al mediodía. | `rp_needs` | 🟢 | Bajo |
| Apagón | C | Barrio sin luz: semáforos apagados (los autos NPC tratan los cruces como ceda el paso), tiendas cerradas, más delincuencia, iluminación local apagada. Recuperación por rol (facción eléctrica). | `rp_citizens` (semáforos `lightFor`), `rp_shops` | 🔴 | Medio |
| Comercios que abren/cierran | C | Horarios de tienda por tipo: bancos 9-17, 24/7 siempre, bares hasta tarde; cerrado en feriados. NPC cajero se va, persiana cerrada. | `rp_shops`, `rp_bank`, `rp_clothing` | 🟡 | Bajo |
| Hora punta | A | Más tráfico a las 8 y las 18; menos de madrugada. Es solo variar `MAX_CARS` por hora. | `rp_citizens` CFG | 🟢 | Bajo |
| Noche: bandas y borrachos | A | Más presencia de bandas (ya existe `0.5` de noche), borrachos, menos familias. | `rp_citizens` | 🟢 | Bajo |
| Amanecer y atardecer | A | Cambios de población, pájaros, barrenderos, repartidores. | `rp_citizens` | 🟢 | Bajo |
| Tormenta con daños | C | Cadena: árboles caídos que bloquean una calle, apagón, accidentes. | evento en cadena | 🔴 | Medio |

### 3.6 NPC con vida propia

| Evento | Alc. | Descripción y reglas | Integra con | Esf. | Riesgo |
|---|---|---|---|---|---|
| Rutinas diarias | C | NPC "residentes" fijos que salen de casa por la mañana, van a trabajar, comen, vuelven. Pocos (10-20 por servidor), con nombre y casa. Base de rumores y de memoria. | `rp_properties` (`s_seed_ls.lua`) | 🔴 | Medio |
| Necesidades de NPC | C/A | Hambre, sed y sueño simplificados de los residentes: van a tiendas, comen en puestos, duermen. | `rp_needs` (lógica similar), `rp_shops` | 🟡 | Bajo |
| Paseador de perros / corredor / turista | A | Peatones con roles visibles que usan animaciones propias. | `rp_citizens` | 🟢 | Bajo |
| Trabajadores en turno | A | NPC con uniforme del trabajo (basurero, granjero) en su zona y horario. | `rp_jobs` | 🟡 | Bajo |
| Rumores y chismes | C | Ver sección 4.4. | `rp_phone`, `rp_notify` | 🟡 | Bajo |
| Eventos de vida (cumpleaños, boda, mudanza) | C | Camión de mudanza frente a una casa que se vende, globos y música en una casa. | `rp_properties` | 🟡 | Bajo |

### 3.7 Economía y sociedad

| Evento | Descripción | Integra con |
|---|---|---|
| Subida o bajada de precios | Escasez de combustible (sube `rp_vehicles` bencina), cosecha buena (baja el precio agrícola). | `rp_jobs` (`getMarketPrice`), `rp_vehicles` |
| Oferta de empleo temporal | "Se necesitan repartidores esta tarde": bonus por horas. | `rp_jobs`, `rp_agency` |
| Huelga | Un oficio no trabaja una hora; precios suben. | `rp_jobs` |
| Inauguración / liquidación | Tienda con descuento limitado; cola de NPC. | `rp_shops` |
| Subasta / mercado nocturno | Autos y propiedades con oferta temporal. | `rp_dealership`, `rp_properties` |
| Campaña de salud / vacunación | Rol para paramédicos, bonus de salud. | `rp_emergency`, `rp_needs` |

## 4. Interacción con jugadores y memoria de los NPC

### 4.1 Hooks de rol

- **Llamadas al 911.** Cada evento con víctimas o peligro se *anuncia* al sistema de emergencias: el director
  llama a `rp:emergency:onCall` (hook ya existente) con `source = nil` y un `dispatchId`, o a un export nuevo
  `exports.rp_emergency:createDispatch(tipo, x, y, z, texto)`. Policía y bomberos jugadores ven el aviso
  como los de la central de `rp_wanted` (punto en el mapa). Si nadie de la facción está de servicio, entra
  en juego la unidad IA (la ambulancia ya existe).
- **Misiones emergentes.** Un evento puede ofrecer una *oportunidad de rol* sin obligar a nada: cartel en el
  HUD ("Se oyen gritos en la calle Grove") y marcador discreto. Quien interviene suma "reputación" (ver 4.3).
- **Pistas.** Los eventos delictivos dejan rastros en el mundo (casquillos, matrícula del vehículo, sangre,
  cámara de seguridad) que el staff o la policía jugadora pueden consultar con una interacción. Se guardan
  en `event_clues` con vencimiento (24-72 h reales).
- **Teléfono.** Noticias o avisos en `rp_phone` (app de noticias/rumores) y SMS automáticos de la central
  ("accidente en Idlewood, evite la zona"), con el mismo patrón de `social_posts` de Fotogram.
- **Radio.** Anuncios de tráfico y clima en `rp_radio` cuando hay una emisora local.
- **Necesidades.** Calor, frío y lluvia afectan a `rp_needs` y `rp_injury` (hipotermia suave, golpe de calor).

### 4.2 Cómo reaccionan los NPC (sobre las fases de IA existentes)

`rp_citizens` ya tiene `FLEE`, `FIGHT`, `HONK`, `AVOID`. Los eventos añaden estados *transitorios* sobre esas
máquinas sin reescribirlas:

| Estado nuevo | Se activa por | Comportamiento |
|---|---|---|
| `WATCH` | Pelea, accidente, incendio | Se detiene a 6-12 m, mira hacia el evento (`setPedLookAt`), saca el teléfono; 20-40% grabará y lo publicará (rumor). |
| `HELP` | Emergencia médica, herido | Un NPC valiente se acerca; otros llaman al 911. |
| `CALL` | Testigo de un delito | Hace la animación del teléfono, tras 5-10 s se genera un aviso al 911 (con `witnessed = "civil"`, ya soportado por `reportCrime`). |
| `SHELTER` | Lluvia fuerte, tormenta | Camina a la entrada más cercana y espera. |
| `CROWD` | Concierto, manifestación | Sigue el centro del evento. |

Cada estado es una función registrada con la misma convención de `updatePed(ped, s, now, px, py, pz)`. El
evento solo cambia `s.state` y pone `s.event = eventId`; al terminar, `resumeWalk`.

### 4.3 Memoria de los NPC

Dos niveles, para no gastar ni BD ni CPU de más:

1. **Memoria corta (RAM, servidor).** Por evento: lista de *testigos* (NPC y jugadores) con qué vieron
   (`{ actor = characterId|"npc:id", acción, tick, confianza }`). Sirve para la policía durante la investigación y
   caduca con el evento.
2. **Memoria larga (BD, solo para residentes fijos y tiendas).** Tabla propuesta `npc_memory`
   `(npc_id, character_id, kind, value, updated_at)` con, por ejemplo, "este personaje me ayudó" (+1),
   "este personaje me robó" (-3), "me debe dinero". Uso: el vendedor te da mejor precio, el cajero desconfía
   de quien lo atracó antes, el residente te saluda por tu nombre. **Solo para NPC con identidad** (residentes
   y comerciantes); los peatones ambientales no recuerdan nada.

Reglas de equidad: la memoria *nunca* da ventajas mecánicas grandes ni castiga sin aviso al jugador;
todo es informativo o de pequeño impacto. Se limpia con el tiempo (decaimiento).

### 4.4 Rumores y chismes

- Cada evento con testigos produce un **rumor** `{ tema, zona, veracidad, edad }`.
- Los residentes y comerciantes lo "saben" y, si el jugador conversa con ellos (interacción tipo tienda), lo
  cuentan; también aparecen en el canal de noticias del teléfono.
- Los rumores se **deforman con el tiempo y la distancia**: más viejos o de otra zona cambian detalles
  (cantidad de armados, descripción del auto) → pista parcial y rol.
- Una lista corta (máx. 20 por zona) con expiración de pocas horas evita acumulación.

## 5. Integración con los recursos que ya existen

| Recurso | Qué recibe de `rp_events` | Qué aporta |
|---|---|---|
| `rp_citizens` | Estados `WATCH/CALL/SHELTER`, modificadores de población por hora y clima, bloqueo de tramos por obras | Red vial `getRoadGraph()`, spawns fuera de cámara, perfiles de zona |
| `rp_emergency` | Despachos de policía y bomberos (implementar `fire` y `police`, hoy `enabled = false`) | Unidades IA y patrón de cliente controlador |
| `rp_wanted` | `reportCrime(..., witnessed)` por delitos del evento, avisos a la central | Patrullas, controles, cárcel |
| `rp_robbery` | Atraco de NPC a una tienda con jugadores cerca | Interior, miedo, negociación |
| `rp_jobs` | Precios dinámicos y tareas bonus por eventos | `getMarketPrice`, `rp:jobs:onShiftEnd` |
| `rp_shops`, `rp_bank`, `rp_clothing` | Horarios de apertura, cortes de luz, ofertas | Tiendas con NPC y ubicaciones |
| `rp_needs`, `rp_injury` | Multiplicadores por calor/frío/lluvia; heridos de accidentes | Necesidades y abatidos |
| `rp_phone`, `rp_radio`, `rp_notify`, `rp_hud` | Noticias, rumores, SMS de la central, anuncios, iconos de evento | Canales de aviso |
| `rp_vehicles` | Combustible y multas de control policial; llave | Autos con dueño |
| `rp_factions` | Ofertas de rol por facción (policía, médicos, bomberos, electricistas) | Permisos, avisos, sueldos |
| `rp_adminpanel` | Lista de comandos de `/evento*` (según la regla de `CLAUDE.md`) | Panel F10 |

## 6. Plan por fases

Priorizado por **impacto en la sensación de vida**, **esfuerzo** y **riesgo**. Cada fase se puede lanzar sola.

### Fase 0 (opcional): reloj y clima compartidos
Esfuerzo bajo, riesgo bajo, impacto alto en ambiente. Es prerrequisito de los eventos de horario y clima.
- Recurso `rp_events` mínimo con solo `s_world.lua`: hora de juego acelerada, clima por máquina de estados,
  `getWorldState()`, `/clima`, `/hora` (admin).
- `rp_citizens` ajusta `MAX_PEDS/MAX_CARS` por hora y clima (hora punta, noche, lluvia).

### Fase 1 (la pequeña y segura): escenas ambientales y director mínimo
Esfuerzo bajo-medio, riesgo bajo. Solo cliente + un director servidor muy simple.
- Estructura `rp_events` con director, presupuesto, cooldowns y `/eventos`, `/eventoslista`, `/evento <id>`.
- **5-6 escenas ambientales** (cliente, sin consecuencias): discusión de peatones, avería con balizas,
  músico callejero, vendedor ambulante, paseador de perros, ambulancia/patrulla en tránsito, borracho de noche.
- **Estado `WATCH`** para peatones cercanos: se paran a mirar.
- **Lluvia** que cambia el comportamiento de `rp_citizens` (menos peatones, `SHELTER`, autos algo más lentos).
- Sin BD nueva, sin elementos del servidor, sin tocar `rp_wanted`. Reversible con un interruptor.

### Fase 2: eventos compartidos pequeños con 911
Esfuerzo medio, riesgo medio.
- Servidor crea elementos reales; streaming por proximidad.
- **Accidente leve** y **emergencia médica NPC** con llamada al 911 y la ambulancia que ya existe.
- Estado `CALL`/`HELP` y avisos a `rp_notify`.
- **Hora punta** y **comercios que abren/cierran** (solo horarios, bajo riesgo).

### Fase 3: delitos con testigos
Esfuerzo medio-alto, riesgo medio-alto (equilibrio y abuso).
- Pelea callejera con escalada, robo de auto NPC, atraco NPC a tienda con `rp_robbery`.
- Testigos que denuncian con `witnessed = "civil"` y pistas básicas (`event_clues`).
- Control policial de carretera (con policía jugadora o IA).

### Fase 4: servicios y obras
Esfuerzo alto, riesgo medio-alto.
- Implementar `fire` y `police` reales en `rp_emergency`; incendio con bomberos.
- Obras con desvío y bloqueo de tramos en `path_links`; apagón con semáforos apagados.

### Fase 5: NPC con identidad
Esfuerzo alto.
- Residentes con rutinas, necesidades, memoria en BD y rumores.
- Persecuciones, manifestaciones y festivales.

Resumen de prioridades:

| Fase | Impacto | Esfuerzo | Riesgo |
|---|---|---|---|
| 0 Reloj y clima | Alto | Bajo | Bajo |
| 1 Escenas y director | Alto | Bajo-medio | Bajo |
| 2 Accidentes y 911 | Medio-alto | Medio | Medio |
| 3 Delitos y testigos | Alto (rol) | Medio-alto | Medio-alto |
| 4 Incendios, obras, apagón | Medio | Alto | Alto |
| 5 NPC con identidad | Alto | Alto | Medio |

## 7. Riesgos a vigilar

- **Spam de eventos:** presupuesto de drama, intensidad configurable y cooldowns por zona; interruptor global.
- **Abuso y percepción de injusticia:** nada que robe o dañe a un jugador sin una oportunidad clara de reaccionar;
  no tocar autos de jugadores; carteristas y tiroteos solo tras probar la mecánica con staff.
- **Rendimiento:** fuego y muchos elementos del servidor son caros; límites duros y degradación a ambiental.
- **Elementos huérfanos:** una tabla de elementos por evento y limpieza en `finish` y `onResourceStop`.
- **Conflictos con `rp_citizens`:** los eventos comparten el cupo de población y no reescriben sus máquinas de
  estados, solo les ponen estados transitorios.
- **Datos sensibles de rol:** la memoria de NPC es informativa y con caducidad.
- **Pruebas:** reutilizar `resources/[test]/rp_test` para probar el director sin jugadores (sorteo, cooldowns,
  límites) y un modo "simulación" que ejecute N horas de juego en segundos y muestre la distribución.

## 8. Preguntas abiertas (decisiones de diseño)

1. Duración del día de juego (propuesta: 24 h de juego = 6 h reales).
2. ¿Los eventos deben respetar zonas "seguras" para nuevos (p. ej. sin tiroteos cerca del spawn)?
3. ¿Quieren calendario con festivos del servidor o solo eventos aleatorios?
4. ¿Cuánto poder tiene el staff sobre el director (`/evento`, aprobar eventos de impacto, apagar zonas)?

## 9. Estado de la implementación

Implementado (fases 0, 1 y parte de la 2, 3 y 4 de este plan), sin tablas nuevas:

| Pieza | Dónde | Qué hace |
|---|---|---|
| Reloj y clima compartidos | `rp_events/server/s_world.lua` | 24 h de juego = 6 h reales, continua entre reinicios; clima por máquina de estados con transiciones ponderadas. |
| Director | `rp_events/server/s_director.lua` | Presupuesto de drama, pesos, cooldowns, variedad, punto elegido por el cliente y validado en el servidor, 1 timer de mantenimiento, límites duros (3 eventos, 40 elementos). |
| Catálogo | `rp_events/server/s_catalog.lua` | Accidente de tránsito (patrulla y ambulancia por etapas), emergencia médica, control policial, obras, auto en llamas con bomberos, mercadillo y fiesta callejera. |
| API | exports de `rp_events` | `registerEvent`, `startEvent`, `endEvent`, `getActiveEvents`, `getWorldState`, `setWeatherState`. Eventos externos con `rp:events:ext:start/finish`. |
| Escenas ambientales | `rp_citizens/c_scenes.lua` | Charla, discusión, teléfono, fumador, vendedor, borracho, pelea y auto averiado con balizas; una sola a la vez y cuentan dentro del cupo de peatones. |
| Reacción de NPC | `rp_citizens/c_citizens.lua` | Estado `WATCH` (se paran a mirar) y cupos de población por hora punta, mediodía y lluvia. |
| Humo y fuego | `rp_events/client/c_events.lua` | Efectos solo mientras el vehículo está cargado. |
| Admin | `rp_events/server/s_admin.lua` | `/evento`, `/eventos`, `/eventoslista`, `/terminarevento`, `/eventosintensidad`, `/eventosinfo`, `/clima`, `/hora` (también en `rp_adminpanel`). |

Pendiente (fases siguientes): hooks reales a `rp_wanted`/`rp_emergency` (911 de policía y bomberos), bloqueo de
tramos viales por obras, apagones, memoria de NPC y rumores, residentes con rutinas, persecuciones y manifestaciones.

Puntos a validar **en juego** (el cliente no tiene tests): nombres de animaciones y de efectos de partículas
(`CRACK/crckdeth2`, `DANCING/dnce_M_*`, `MEDIC/CPR`, `smoke30m`, `fire`), altura de objetos (conos 1238, barreras
1423, carrito 1340) y que las patrullas y ambulancias de escenografía queden bien alineadas con la calzada.

### 9.1 Vida de barrio (`rp_citizens/c_hangouts.lua`)

Al entrar a un barrio hay gente fuera de las casas, siempre en los mismos rincones: un hash determinista de los
nodos de acera marca los "puntos de encuentro" (más en barrios ghetto, menos en industriales) y el barrio decide
quién está. Ghetto: bandas del barrio (Grove, Ballas, Vagos, Aztecas) con más presencia de noche, vecinos en la
cerca, gente en la puerta; barrios ricos: vecinos y llamadas; industriales: obreros en su descanso; resto: vecinos,
cerca, teléfono y fumadores. Cambian de gesto cada 12-24 s (hablan, ríen, fuman).

Rendimiento: solo se crea un grupo (2-5 peds) cuando el jugador está a 30-90 m de un punto y no lo ve, se destruye a
más de 125 m, máximo 3-5 grupos y 12-14 peatones (según intensidad y hora) dentro del cupo de `c_citizens.lua`
(siempre quedan 4 peatones caminando), 2 timers baratos y nada que hacer si no hay grupos. Con lluvia casi nadie
sale, de madrugada menos, y si los asustan (disparos, apuntar, golpes, explosiones) huyen y el punto descansa 3 min.
Se apaga con `/eventosintensidad 0`.

### 9.2 Mercadillo con compras

Los puestos del mercadillo se colocan en fila a lo largo de la acera: el vendedor queda del lado de las casas
(el cliente envía el vector "alejarse de la calzada") y los clientes del lado de la calle. Cada vendedor es una
**tienda temporal** de `rp_shops` (`addTempShop`/`removeTempShop`, sin SQL): E abre el mismo menú de compra, el precio
sale del catálogo del puesto (comida, bebidas o tabaco, en `MARKET.STALLS`) y la compra la valida el servidor como
en cualquier tienda. Al terminar el evento la tienda desaparece sola. La altura y la rotación del modelo 1340 se
calibran en juego con `/mercadoajuste <dz> <rotacion>` y luego se dejan fijas en `MARKET` (`shared/s_config.lua`).
