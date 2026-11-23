> **Estado (2026-11-23):** la Fase 1 (sensores en abanico, personalidad de conductor, velocidad por curva con
> distancia de frenado, ceder ante sirenas, seguimiento de trayectoria en curvas cerradas, reenganche y
> resolución de atascos/solapes, deshacer Ctrl+Z y respaldo en el editor `/nodos`) ya está en `rp_citizens`.
> Pendiente: Fase 2 en adelante (prioridad en cruces, cambio de carril, peatones, rutinas, tráfico compartido).

# IA de NPCs y tráfico: análisis y plan de mejora

Alcance: lectura de `rp_citizens` (c_citizens.lua 1550 líneas, c_editor.lua, s_paths.lua, c_nodes_ls.lua), `rp_emergency` (c_driver, c_graph, c_offroad, c_walk, c_bubbles), `rp_wanted` (c_police, c_roads, s_units) y `rp_rides` (c_driver, c_graph). No se modificó ningún código.

## 1. Resumen ejecutivo

- Lo que hay hoy ya es una base sólida y bastante "estilo GTA SA": población 100% local en el cliente, grafo de carriles real de GTA (2538 sentidos viales, 12537 nodos peatonales), curvas Bezier en cruces, semáforos reales de GTA, LOD con "dummies" sin física, y máquinas de estados simples.
- Lo que limita la sensación de "inteligencia" no es el control del volante, sino **la percepción y la memoria**: los NPCs ven con 1 rayo al frente y 2 bigotes que solo ven paredes, no tienen noción de carril vecino, de quién llega primero, de sirenas, de choques ajenos ni de rutinas. Todo se decide con azar ponderado y temporizadores.
- El mayor problema técnico y de mantenimiento: **la lógica de conducción está copiada 4 veces** (citizens, emergency, rides, wanted) con pequeñas diferencias (rayo, pure pursuit, desvío, A*, grafo). Cada mejora hay que hacerla 4 veces.
- Recomendación: antes de añadir comportamientos, extraer un **módulo de conducción compartido** (recurso `rp_ai_core` o `rp_citizens` exportando) y sobre él construir percepción mejorada, prioridad en cruces, reacción a sirenas y pánico. Esto da el mayor salto con el menor riesgo.

## 2. Cómo funciona hoy

### 2.1 Red de rutas
- `c_nodes_ls.lua` (706 KB): `VEH_NODES/LINKS/LANES/OFFSET/LIGHT` y `PED_NODES/LINKS`, generados desde NODES*.DAT de GTA SA. Solo Los Santos.
- Rejilla espacial de celdas de 100 m para buscar nodos cercanos (`buildGrid`, `nearestNode`, `randomNodeAround`).
- El editor `/nodos` guarda diferencias en `path_nodes`/`path_links` (SQL) y las reparte en vivo (`s_paths.lua`). Los enlaces nuevos asumen 1 carril y 2.5 m de offset.
- Cada enlace a→b tiene nº de carriles y desplazamiento a la derecha; semáforo por enlace (`getLight`).

### 2.2 Tráfico (rp_citizens)
- **Población**: máx. 16 autos de día, 9 de noche (+6 con búsqueda), 14/7 peatones. Aparecen a 70–130 m fuera de cámara (o 105–160 m por delante si el jugador va rápido) y desaparecen a 170 m. Perfil por zona (ghetto/rich/industrial) y 15 % motos, 8 % patrullas.
- **Ruta**: sin destino. En cada cruce `exitCandidates` elige al azar ponderado (recto ×4, giro suave ×2, cerrado ×1, sin giros en U). A* existe (`findRoute`) pero está sin usar.
- **Plan**: `planSegment` genera una cola de ~18 puntos: tramo recto cada 6 m + curva Bezier (radio 9–12 m) entre carril de entrada y salida; comprueba con un raycast que la curva no atraviese muros.
- **Control** (cada 80 ms, solo si el auto está a < 55 m / en pantalla): pure pursuit con lookahead 6 m + 0.1·v, volante proporcional al error de rumbo, asistencia que **sobrescribe velocidad lateral y velocidad angular** del vehículo (en la práctica es un "tren sobre raíles" disfrazado de conducción) y pedales todo/nada.
- **Velocidad objetivo**: crucero 50 km/h, bajada por curvas por tablas (18/26/36), por pared delante y por desvío.
- **Percepción**: 1 rayo frontal (8 + 0.3·v m) que ve autos, peatones y objetos; 3 rayos solo de pared (frente, ±25°) que solo corrigen el volante ±0.2.
- **Seguimiento**: si hay obstáculo, `target = min(target, otraVel + 3)`, o 0 si `gap < 4 + 0.12·v`.
- **Semáforos**: lee `getTrafficLightState()`; frena hasta la línea en rojo, o en amarillo si queda > 12 m.
- **Cruces**: reserva por nodo "uno a la vez por orden de llegada" (`tryLock`, 7 s de caducidad). Es solo local y no distingue direcciones; dos autos que no se cruzan esperan igualmente.
- **Bloqueos**: estados DRIVE/FOLLOW/RED/YIELD/DETOUR/FLEE/ABANDONED. Si el bloqueo es el jugador: bocina a 0.9 s, desvío a 2.8 s (`tryDetour`, 3 trayectorias fijas por la izquierda/derecha), y a 4.5 s marcha atrás 0.9 s. Si es un auto averiado, tras 8 s lo rodea. Atascado 3 veces: el conductor se baja y huye (`ABANDONED`).
- **Dummy (LOD)**: más de 80 m y fuera de cámara, sin física, se desliza por los puntos interpolando cada frame; velocidad por reglas simples (semáforo, auto a < 14 m delante en línea). Es muy barato pero **no ve nada que no sea otro auto de la lista o el jugador**.
- **Reacciones**: si el jugador dispara a menos de 40 m, o choca/dispara al auto → FLEE 8–10 s (acelera, bocina). Si el jugador entra al auto, el conductor desaparece y el auto se abandona. Choques entre NPCs (> 150 de fuerza): el de atrás frena.
- **Policía de tráfico**: patrullas del tráfico se "adoptan" en `rp_wanted` si el jugador tiene estrellas (`adoptLocalCop`).

### 2.3 Peatones
- Máquina de estados `WALK/IDLE/FLEE/FIGHT/DEAD`, tick 300 ms. Caminan por nodos peatonales (siguiente nodo aleatorio sin retroceder). 6 % de probabilidad de parar en un nodo y hacer 1 de 4 animaciones.
- Esquivan al jugador girando 50° si está a < 1.8 m delante. No esquivan a otros peatones, autos ni obstáculos (usan `setElementRotation` directo, no pathfinding).
- Huyen por disparos a < 35 m (solo los del jugador local), por apuntarles o por golpes; el 30 % "valiente" pelea cuerpo a cuerpo. Huir = alejarse en línea recta 8–12 s con ruido ±20°, sin considerar obstáculos ni lugares seguros.
- Bandas por barrio (skins), más presencia de noche.

### 2.4 Otros conductores IA
- **rp_emergency** (ambulancia): servidor crea elementos y nombra al cliente de quien llamó "syncer". A* por el grafo, pure pursuit, bocina, adelantamiento con `tryDetour`, rutas fuera de calle con A* sobre rejilla y raycasts (`offroadPath`), paramédicos que caminan por camino calculado y reproducido por todos los clientes (`c_walk`). Con sirena no espera semáforos.
- **rp_wanted** (policía): estados ROUTE/CHASE/STOP/LEAVE con predicción del movimiento del jugador, embestida desde 3 estrellas, roles (`assignRoles`/`chooseIntercept`), helicóptero, SWAT, controles de carretera, a pie corren y arrestan.
- **rp_rides** (Vroom): taxi IA con el mismo esquema que `rp_emergency`.

### 2.5 Sincronización y rendimiento
- Tráfico y peatones ambientales son **elementos locales del cliente**: cada jugador ve su propia población (cero tráfico de red, pero **dos jugadores nunca ven los mismos NPCs**; no se pueden chocar entre sí ni compartir una escena).
- Los conductores "con misión" (ambulancia, policía, taxi) son elementos de servidor controlados por un cliente "syncer" (`setElementSyncer`). Si ese cliente se aleja o no los tiene cargados, el conductor se queda sin control (en emergencias hay un mensaje de traza y `setElementStreamable(false)`).
- Coste: `carTick` cada 80 ms recorre todos los autos; `dummyDecide` compara cada dummy con todos los autos (`for other in pairs(cars)`) → O(n²), aceptable con 16 pero no escalará. 5–8 raycasts por auto por tick en modo real.
- `moveDummies` por frame con 2–3 raycasts de suelo por dummy.

## 3. Qué falla o se ve poco natural

| # | Problema | Causa |
|---|---|---|
| 1 | Se ven "sobre raíles": no derrapan ni se desvían, pero tampoco reaccionan de forma humana | La asistencia reescribe velocidad lateral/angular; el control real del volante apenas importa |
| 2 | Chocan por detrás / se montan unos sobre otros en curvas y cruces | Un único rayo frontal; sin predicción de trayectorias; los dummies solo miran 14 m al frente |
| 3 | Cruces absurdos: dos autos que no se cruzan se esperan; o ceden mal a la derecha | Cerrojo por nodo sin considerar direcciones, giros ni carril de destino; sin prioridad real ni "stop" |
| 4 | Ignoran sirenas y vehículos de emergencia | No existe lógica de apartarse; el tráfico no distingue sirena |
| 5 | Siempre 50 km/h con curvas por tabla | Sin límites por tipo de vía ni por personalidad del conductor (agresivo/prudente) |
| 6 | No adelantan nunca | Solo rodean objetos fijos tras 8 s; nunca adelantan a un lento ni cambian de carril |
| 7 | Todos los autos del carril exterior de una vía de varios carriles se comportan igual | No hay cambio de carril (se ignoran `VEH_LANES > 1`) |
| 8 | Pánico plano: "acelera y vete" | FLEE solo escapa en línea recta; no mira peligro real ni choques ajenos ni explosiones |
| 9 | Peatones sin vida: caminan al azar | Sin destinos, horarios, relaciones, ni uso del entorno (bancos, paradas, tiendas) |
| 10 | Peatones atraviesan a otros peatones y objetos | Sin evitación local; `setElementRotation` forzado |
| 11 | Poca densidad y repetición | Techo de 16 autos / 14 peatones, spawn solo por skin/modelo aleatorio |
| 12 | Cada jugador ve una ciudad distinta | Todo es local; no sirve para escenas compartidas (policías, accidentes, rol) |
| 13 | Tras abandonar el auto el NPC "huye" y desaparece | Sin respuesta emocional ni testigos |
| 14 | 4 copias de la lógica de conducción | `ray`, `tryDetour`, pure pursuit, A*, grafo duplicados entre recursos |
| 15 | Solo Los Santos | Grafo generado solo para LS (el resto del mapa queda sin tráfico) |

## 4. Plan priorizado (impacto vs. esfuerzo)

Escala: Impacto 1–5, Esfuerzo 1–5 (días de trabajo aprox. en paréntesis para una persona).

| Prio | Mejora | Impacto | Esfuerzo | Riesgo |
|---|---|---|---|---|
| P0 | **Núcleo de conducción compartido** (`rp_ai_core`): grafo, carriles, pure pursuit, sensores, A*, control de velocidad | 4 | 3 (4–6 d) | Medio: hay que migrar 4 recursos sin romperlos |
| P1 | **Sensores mejorados**: abanico de 5–7 rayos (frontal + laterales con distancia, ve autos y peatones), detección por caja delante del vehículo, TTC (tiempo hasta colisión) | 5 | 2 (2–3 d) | Bajo |
| P1 | **Control de velocidad realista**: velocidad por curvatura real (v² ≤ a·R), aceleración/frenada suaves con perfil, límite por tipo de vía, personalidad (prudente/normal/agresivo: velocidad, distancia, paciencia) | 4 | 2 (2 d) | Bajo |
| P1 | **Reacción a sirenas y emergencias**: si hay patrulla/ambulancia con sirena detrás a < 60 m, arrimarse a la derecha y frenar; despejar cruces | 5 | 2 (2 d) | Bajo (rp_wanted ya marca `rp:cop`) |
| P2 | **Prioridad real en cruces**: tabla de conflictos por (entrada, salida), reserva de ventana de tiempo, ceda/stop, cola ordenada; semáforo en verde espera a que el cruce se despeje | 4 | 3 (3–4 d) | Medio |
| P2 | **Cambio de carril y adelantamientos** en vías de ≥ 2 carriles/sentido y en bloqueos (con comprobación del carril vecino por rayos y por la lista de autos cercanos) | 4 | 3 (3–4 d) | Medio |
| P2 | **Pánico y huida inteligente**: contagio de miedo por radio, choques ajenos, explosiones, disparos de cualquiera (no solo local); huir hacia nodos lejanos alejados de la amenaza, esconderse/entrar a interiores, volver a la normalidad gradualmente | 4 | 3 (3 d) | Bajo |
| P2 | **Peatones con evitación local** (steering: separación, alineación, evitar autos y otros peatones; cruzar en semáforo/paso peatonal) | 4 | 3 (3 d) | Bajo |
| P3 | **Rutinas con horarios y roles** (trabajador, turista, pandillero, vendedor, vagabundo): destinos reales (paradas, tiendas, bancos), horas de comida y sueño, memoria básica (te vio cometer un delito, te recuerda) | 5 | 4 (5–7 d) | Medio: diseño de contenido |
| P3 | **Memoria y reputación** persistente por barrio/facción: reacciones distintas a un jugador conocido | 3 | 3 (3–4 d) | Medio (SQL, convención del repo) |
| P3 | **Optimización**: partir por tiempo (budgeted updates), hash espacial para vecinos (eliminar O(n²) en dummies), pooling de peds/vehículos, subir techo de NPCs sin pérdida de FPS | 4 | 3 (3 d) | Bajo |
| P4 | **Tráfico compartido en servidor** para zonas de rol (autos y peatones sincronizados: choques, escenas, policía) con `setElementSyncer` en el jugador más cercano | 5 | 5 (10+ d) | Alto: sincronización, carga, anti-abuso |
| P4 | **Grafo para todo el mapa** (SF, LV, rural) y heli/bote | 3 | 4 | Medio |
| P4 | **Animaciones y vida**: gestos al conductor, saludos, charlas en grupo, fumar, llamadas | 2 | 2 | Bajo |

## 5. Detalle técnico de las mejoras clave

### 5.1 Núcleo compartido (P0)
Un recurso con: carga del grafo (hoy `getRoadGraph` ya lo exporta), A*, `planSegment`, controlador (`drive(vehicle, plan, params)`), sensores y desvíos. `rp_citizens`, `rp_emergency`, `rp_rides` y `rp_wanted` solo definen *qué* quieren (destino, estilo, sirena). Así cada mejora de física, sensores o prioridad se hace una vez.
Cuidado: las exports de MTA no pueden pasar funciones ni correr en cada tick sin coste. Dos opciones: (a) un archivo Lua compartido que cada `meta.xml` lista como `<script>` (misma ruta con `:rp_ai_core/...` no es posible para scripts, habría que copiarlo o usar un build), o (b) exports de cliente del recurso núcleo que se llaman en cada tick (más lento, pero simple). Hay que probar el coste de (b) antes de decidir.

### 5.2 Sensores
- 5 rayos en abanico (0°, ±15°, ±35°) con alcance variable según velocidad; devolver distancia, elemento y velocidad relativa.
- Punto de vista a la altura del parachoques y a 2 alturas (bajo/alto) para ver motos y objetos bajos.
- Cálculo de TTC = distancia / velocidad de cierre: frenado progresivo si TTC < 2.5 s, de emergencia si < 1.2 s.
- Detección de vehículos del lado y de camino cruzado (rayos laterales largos en cruces).
- Para dummies: usar la rejilla espacial (celdas de 20 m) y proyección en el carril, en vez de recorrer todos los autos.

### 5.3 Control del vehículo
Hoy la asistencia fuerza velocidad lateral y angular; con control más suave (PID sobre el error de ángulo con tasa limitada, y asistencia solo cuando |derrape| es alto) los autos parecerán conducir de verdad, derraparán en frenadas bruscas y reaccionarán a golpes. Riesgo: con latencia o rampas reales puede aparecer inestabilidad; mitigar con un modo "raíl" solo para dummies y velocidades bajas.

### 5.4 Cruces con prioridad
Modelo: cada maniobra (entrada→salida) reserva un conjunto de "celdas de cruce" en una ventana de tiempo `[t_in, t_out]` calculada con la distancia y velocidad. Dos maniobras que no comparten celdas pasan a la vez (p. ej. dos rectos opuestos). Los giros a la izquierda ceden. El verde del semáforo no garantiza paso: sigue exigiendo cruce libre ("no bloquear la intersección").

### 5.5 Sirenas y emergencias
Condición barata: en el tick, buscar vehículos con sirena activa (`getVehicleSirensOn`) o con element data `rp:copCar` + sirena en una rejilla a 80 m, detrás y aproximándose. Respuesta: acción "ceder" (orientar el objetivo lateral a la derecha, reducir a 15 km/h, parar si es cruce) y reanudar al pasar. Funciona también con la ambulancia (ya tiene sirena).

### 5.6 Peatones
- Steering behaviors (separación + evitación de obstáculos con 2–3 rayos cortos) en vez de rotación fija.
- Objetivos con propósito: "ir a la parada", "esperar al semáforo", "cruzar", "sentarse en banco".
- Horarios: perfil por rol con tabla hora→actividad. Reutilizar `getTime()` ya presente en el módulo.
- Miedo con contagio: radio de 20 m, decae en el tiempo; los que están asustados corren a nodos alejados de la fuente.
- Pánico global: eventos de disparo, explosión y atropello del resto de jugadores (no solo el local) vía un evento de servidor rebotado a clientes cercanos.

### 5.7 Optimización
- `dummyDecide`: sustituir `for other in pairs(cars)` por una consulta a rejilla (O(1) por auto) y una clave por segmento de carril.
- Raycasts: espaciar por LOD (cerca = cada tick, lejos = cada 3 ticks), reutilizar resultados cuando la velocidad es baja.
- Subir `MAX_CARS` solo con presupuesto de ms por frame medido (`getTickCount` por bucle) y adaptar dinámicamente.
- Pooling: reutilizar vehículos/peds alejados en lugar de `createVehicle/destroyElement` (el coste de streaming es alto).

## 6. Por dónde empezar (propuesta de fases)

1. **Fase 1 (≈1 semana, bajo riesgo, mucho efecto visual)**: sensores mejorados + control de velocidad + reacción a sirenas + optimización de dummies. Todo dentro de `rp_citizens`, sin tocar los otros recursos.
2. **Fase 2 (≈1–2 semanas)**: prioridad en cruces + cambio de carril/adelantamientos + peatones con evitación y pánico mejorado.
3. **Fase 3 (≈2 semanas)**: núcleo compartido, migrar rp_emergency/rp_rides/rp_wanted a él (eliminar las 3 copias).
4. **Fase 4 (continuo)**: rutinas, roles, memoria y reputación; ampliar mapa.
5. **Fase 5 (opcional, más cara)**: tráfico compartido de servidor para escenas de rol.

## 7. Riesgos generales

- **Regresiones**: no hay pruebas automáticas del cliente. Mitigar con un modo de depuración (`/poblacion debug` que dibuje rayos, estados y planes) y probar en el servidor de prueba antes de fusionar.
- **Rendimiento**: más rayos y más NPCs pueden hundir los FPS; medir con presupuesto de ms por tick y bajar LOD cuando se excede.
- **Sincronización**: tráfico compartido en servidor es la mejora de mayor impacto de rol pero la más cara y con más riesgo de abuso/desincronización.
- **Mantenimiento**: sin el núcleo compartido (P0) cada mejora se paga 4 veces.
- **Física de MTA**: los vehículos de peds locales pueden desincronizarse al ser "tomados" por el jugador; ya existe lógica de abandono, hay que conservarla.

## 8. Qué necesito de Fabián

Elegir por dónde empezar. Mi recomendación es la **Fase 1** (sensores + velocidad + sirenas + optimización), porque es la mejora más visible con el menor riesgo, y después decidir si merece la pena la Fase 3 (núcleo compartido) antes de añadir comportamientos nuevos.
