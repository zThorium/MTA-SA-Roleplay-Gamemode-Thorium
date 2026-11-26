# Comparativa: Thorium frente a OwlGaming

Análisis del 26-11-2026 de la carpeta `resources` de `MTA-6.6.4.1.zip`: es el gamemode **OwlGaming**
(roleplay en inglés, 144 recursos y ~257 000 líneas de Lua, de las que ~58 000 son datos de `gps` y del editor `guied`).
La comparación es con `main` de Thorium después del PR #88 (65 recursos y ~92 000 líneas de Lua, más las interfaces CEF).

> **Licencia.** Los archivos de OwlGaming llevan la cabecera *"All rights reserved… Proprietary and confidential"*.
> Se usan **solo como referencia de ideas**: no se copia código, imágenes ni sonidos. La barra de iconos de `rp_hud`
> (abajo) se escribió desde cero con iconos SVG propios.

## Resumen

Thorium ya supera a OwlGaming en **contenido jugable y presentación**: misiones con cinemáticas y voces, ciudad viva
(peatones, tráfico, trenes, eventos), trabajos con minijuegos, interfaces CEF con tutorial, policía IA y estrellas,
gimnasio, carreras, pool, muebles estilo Los Sims, relaciones con NPC... Nada de eso existe en OwlGaming.

Donde OwlGaming nos lleva ventaja es en **lo que sostiene un servidor de rol con muchos jugadores durante años**:
moderación, registros, interiores genéricos, servicios de emergencia jugadores y pequeñas herramientas de rol
(descripciones, idiomas, frecuencias de radio, anuncios). Eso es lo que hay que priorizar.

## Lo que tiene OwlGaming y nosotros no

Comprobado buscando en nuestro código (no solo por el nombre del recurso).

### Prioridad 1: imprescindible antes de abrir a jugadores

| Sistema de OwlGaming | Qué hace allí | Qué tenemos | Propuesta |
|---|---|---|---|
| `logs`, `OwlGamingLogs` | Registro en BD de dinero, objetos, comandos de admin, chat y transferencias | Solo `login_log`, `faction_log`, `chat_pm_log`, `furniture_log` y la auditoría de `rp_adminpanel` | **`rp_logs`** (plan, fase 1 n.º 8): export `log(tipo, actor, objetivo, datos)` y que banco, inventario, tiendas, vehículos y admin lo llamen |
| `report` | Cola de reportes con aceptar, transferir, cerrar, falso; caja arriba a la derecha para el staff; estadísticas por admin | `rp_help` guarda el reporte y avisa al staff; `/reportes` lo lista | Ampliar `rp_help`: estados (abierto/atendido/cerrado), asignado a quién, `/ar` `/cr`, aviso persistente al staff y estadísticas |
| `admin-system`, `bans` | `/spec`, jail OOC, avisos (*warns*), historial de sanciones en SQL, desbaneo, servicio de admin | `rp_admin`: `/ban` con el baneo nativo de MTA (sin tabla ni desbaneo), `/kick`, `/goto`, `/get`... | Tabla `sanctions` (avisos, jail, kick, ban) con historial por cuenta, `/unban`, `/spec`, `/ajail` y servicio de admin (`/aduty`) |
| `apps` | Solicitud con preguntas de reglas antes de poder jugar (*whitelist*) | Nada | Opcional según el tipo de servidor: test de 10 preguntas de rol en `rp_login` antes del primer personaje |

### Prioridad 2: profundidad de rol que se nota enseguida

| Sistema | Qué hace allí | Qué tenemos | Propuesta |
|---|---|---|---|
| `[interior]/interior_system`, `official-interiors`, `interior_keypad`, `elevator-system` | Entradas/salidas genéricas que crea un admin, lista de todos los interiores del juego, cerradura con teclado numérico, ascensores entre plantas | Cada recurso hace sus puertas; `rp_properties` solo casas | **`rp_interiors`** (plan, fase 2 n.º 9): puertas genéricas, negocios y edificios públicos, ascensores y teclado (lo usarían comisaría, hospital, bomberos y facciones) |
| `es-system` | Médicos jugadores: cargar heridos, camilla, examinar, recetar, revivir, facturar | `rp_injury` (abatido) y ambulancia IA en `rp_emergency`; falta la facción | **`rp_medics`** (plan, fase 1 n.º 3) sobre `rp_factions` y el export `revivePlayer` |
| `tow-system` | Grúa, depósito municipal y liberar vehículos pagando | Cepo y multas en `rp_police`; nada de grúa ni depósito | Depósito (tabla, `/liberar`, pago) y grúa como trabajo o facción |
| `license-system` | Licencias de armas, piloto, pesca... | DNI y licencia de conducir | Licencia de armas exigida por `rp_ammunation` (plan, fase 1 n.º 4) |
| `chat-system` (frecuencias, `/dep`) | Radio por frecuencias (walkie) y canal entre departamentos | `/f` de facción | Radio de frecuencias (ítem walkie) y canal interdepartamental para policía, bomberos y médicos |
| `description`, `social` (`/look`) | Descripción física del personaje, de vehículos y propiedades al acercarse | Nada | `/descripcion` por personaje con etiqueta al mirar (barato y muy de rol) |
| `language-system` | Idiomas: los que no hablan el tuyo ven el texto revuelto | Nada | Idiomas por personaje en `rp_chat` (inglés, ruso, chino...) |
| `advertisements` | Anuncios clasificados y subastas | Nada | App "Anuncios" en `rp_phone` con cobro y tiempo de espera |
| `selfck-system`, `death` | Muerte permanente (CK) con cementerio | Solo reglas en `rp_help` | CK por petición del jugador o por admin, con lápida en el cementerio |

### Prioridad 3: ampliaciones cuando lo anterior esté

| Sistema | Idea útil para nosotros |
|---|---|
| `job-system`, `job-system-trucker` | Trabajos que faltan: **taxista** (taxímetro), **camionero**, **conductor de bus**, **mecánico**, cerrajero, fotógrafo, barrendero. Encajan en la API de `rp_jobs` |
| `business-system`, `npc` | Negocios comprables que generan ingresos (plan, fase 2 n.º 10) |
| `gate-manager` | Portones y barreras con permiso de facción o código (sedes de facción, garajes) |
| `toll`, `insurance`, `paynspray-system`, `ramp-system` | Peajes en los puentes, seguro de vehículo, Pay 'n' Spray, elevadores de taller |
| `realism` | Estilo de caminar, control de crucero, ventanillas, ocultarse en el auto |
| `weapon`, `driveby` | Armas visibles en el cuerpo, modo semi/automático, drive-by real |
| `dynamic_lighting_flash` | Linterna |
| `account/f10-settings` | Un panel único de ajustes del jugador (hoy cada recurso guarda los suyos) |
| `social` | Lista de amigos |
| `achievement` | Logros (complementan `rp_levels`) |
| `pd-system` | Perro K9, cámaras de velocidad, barreras, pinchos y descenso en cuerda para la policía jugadora |
| `computers-system` | Ordenadores y webs del juego (mejor como apps de `rp_phone`) |

### No merece la pena

`mdc` (ya tenemos MDT), `LSFD` (ya tenemos `rp_firefighters`), `phone`, `bank`, `payday`, `scoreboard`, `carradio`,
`freecam` (tenemos versiones mejores); `gps` (32 000 líneas de nodos: nuestra navegación A* ya funciona); `sfia`
(control aéreo), `cargo`, `superman`, `snow`/`xmas`, `cards`, `lottery`, `chance-system`, `elections`, `clubtec`,
`dancer-system`, `fakevideo`, `grid`, `donators` (decisión de negocio, no técnica), `anticheat` y `serialwhitelist`
(muy básicos).

## Orden recomendado

1. **`rp_logs`** y **sanciones en SQL** (`/unban`, `/spec`, `/ajail`, avisos): sin esto no se puede moderar.
2. **Reportes con cola** en `rp_help`.
3. **`rp_interiors`** (puertas, ascensores, teclado): lo necesitan casi todos los sistemas que vienen después.
4. **Médicos jugadores** y **radio de frecuencias**: completan los servicios de emergencia.
5. **Depósito y grúa**, **licencia de armas**.
6. Rol barato y visible: **descripciones**, **idiomas**, **anuncios** en el teléfono, **CK**.
7. Trabajos nuevos (taxista, camionero, bus, mecánico) y negocios.

## El HUD de OwlGaming y lo que se replicó

**Cómo funciona allí** (`hud/c_hud.lua`): dos filas de iconos PNG de 34 px dibujados con dx, una arriba a la derecha
(servicio de admin, nametag dorado, estilo de caminar, giro de cabeza, PM, anuncios, vida, chaleco, esposas,
modo de arma...) y otra abajo a la derecha solo en vehículo (motor, freno de mano, luces, cinturón, ventanillas,
seguro, control de crucero, velocímetro, autoaparcado, MDC). Apagado = icono gris. Con el cursor visible, al pasar
el ratón sale un recuadro negro con el estado y la tecla, y el clic hace la acción. Puntos débiles: un `if/elseif`
de 400 líneas, el estado se busca por texto, todo en inglés, sin animación y con el área de clic a media altura.

**Lo que se hizo en Thorium** (`rp_hud/c_iconbar.lua`, rama `feat/hud-iconos-clicables`):

- **Fichas a la izquierda del dinero**, con el estilo elegido: cuadro negro redondeado con muesca arriba, nombre en mayúsculas e icono debajo.
- **Accesos rápidos** (fila de arriba): facción (F3, solo si tienes), inventario (I), teléfono (P), ayuda (F1) y
  ocultar HUD (F7). Estados en rojo que laten: **esposado** y **abatido**.
- **Controles del vehículo** (segunda fila, solo en un vehículo, a la izquierda del arma, las estrellas y el nivel): motor (J), freno de mano (X), cerradura (L, el candado
  se abre o se cierra), cinturón (C, late en rojo si vas a más de 30 km/h sin él), balizas (↓) y radio (R). Solo
  salen los que tienen sentido (conductor, tipo de vehículo, asiento delantero para la radio).
- Encendido = icono y borde de color; apagado = gris; alerta = ficha roja que late. Iconos SVG propios (`svgCreate`), nítidos en cualquier resolución.
- Con el cursor (M) cada icono muestra **su tecla dibujada** (Kenney) y, al pasar el ratón, crece, suena y abre una
  tarjeta: nombre, estado y "[tecla] o [clic] para …". Las teclas del vehículo se leen de los binds del jugador.
- El clic hace **lo mismo que la tecla**: comandos de `rp_vehicles` o el evento de cliente `rp:hud:action` (id)
  que escucha cada recurso con sus mismas comprobaciones; el servidor revalida todo igual que con la tecla.
- Paso nuevo en el tutorial del HUD ("Accesos rápidos") y consejo la primera vez que subes a un vehículo.

Para añadir un icono: una entrada en `PLAYER_BUTTONS` o `VEHICLE_BUTTONS` de `c_iconbar.lua` y, si abre algo de
otro recurso, un `addEventHandler("rp:hud:action", localPlayer, ...)` en ese recurso.
