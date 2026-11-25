# Auditoría de rp_shootingrange

## 2026-11-25 · arreglar · puntería
- **Motivo** (probado en juego por Fabián): salían headshots sin haber dado ni cerca de la cabeza; el aviso se quedaba en "¡Prepárate! 1" y la siguiente oleada tardaba.
- **Causas**:
  - Los impactos se decidían en el servidor con esferas imaginarias, revisando la cabeza primero y con el radio inflado por latencia en blancos móviles (~0,5 m en la cabeza): cubría el pecho.
  - `indexOf("Prepárate") === 0` sobre un texto que empieza por "¡".
  - Blancos hasta 3,5 m a los lados: en el carril real quedaban dentro de las paredes y la ronda esperaba el tiempo entero.
- **Nota**: 100 → 100.
- **Cambios**:
  - La parte del cuerpo la da GTA (`onClientPedDamage` del blanco local, bodypart 9 = cabeza, 3-6 = torso, 7/8 = piernas). El servidor la acepta solo si casa con un disparo real registrado (uno por disparo, ventana `HIT_WINDOW_MS`) cuya trayectoria pase a menos de `HIT_MAX_MISS` m del cuerpo del blanco, vivo y activo (SEG-02). Si el aviso llega antes que el disparo, espera en una cola acotada.
  - "¡Fuego!" aparece al empezar la ronda; desvíos laterales recortados a `LANE_HALF_WIDTH`.
- **Probar en juego**: disparar al pecho (debe dar Torso), a la cabeza (Cabeza), a las piernas y fallar a propósito al lado de la cabeza (no debe contar).

## 2026-11-25 · mejorar · foco: munición infinita segura e historial con gráficas
- **Motivo**: que entrenar no gaste balas reales y que los resultados muestren el progreso histórico.
- **Nota**: 100 → 100.
- **Cambios**:
  - Munición de entrenamiento: el arma se da con `TRAINING_AMMO` (9999) y se rellena por debajo de `REFILL_BELOW`; no se lee ni se escribe el inventario. El arma se retira siempre en `finishSession` y `rp_ammunation` tiene las armas suspendidas (no sincroniza esa munición), así que nunca se convierte en balas reales. Ya no hace falta munición para entrenar.
  - Tope diario de habilidad (`SKILL_MAX_PER_DAY` = 300 en 24 h, 0 = sin tope), porque la munición ya no cuesta y antes era el freno al farmeo.
  - Tabla `range_sessions` (BD-04, al final de `schema.lua`) con cada sesión; los resultados traen las últimas 15 con esa arma y totales.
  - Resultados: fichas (sesiones, precisión media, mejor puntuación, tendencia) y gráficas SVG de precisión, puntuación y habilidad con umbrales Gangster/Hitman, tooltip al pasar el ratón (skill dataviz, modo oscuro).
  - Prueba `shootingrange_historial_existe` en `rp_test`.
- **Reglas manuales revisadas**: SEG-02 ✔ (impactos y habilidad los decide el servidor), BD-06 n/a (ya no se cobra munición), BD-07 ✔ (`range_sessions` con FK `ON DELETE CASCADE`), CIC-03 ✔, INT-07 ✔.
- **Pendiente**: si se apaga el servidor en plena sesión, esa sesión no queda en el historial (no hay balas que perder).
- **Probar en juego**: entrenar sin balas en el inventario; comprobar que las balas del inventario no cambian; salir y verificar que el arma vuelve con tus balas reales; varias sesiones y ver las gráficas; llegar al tope diario.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 09b1861)

**Nota: 100/100** · OK 32 · FALLA B 0 · FALLA I 0 · AVISO 0

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | R | EST-06 | Cabecera de comentario en cada .lua |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-01 | Handlers de eventos remotos usan client |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-03 | SQL parametrizado (sin concatenar) |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 22000 23000 |
| OK | R | INT-06 | Teclas sin choques con otros recursos | f2 |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |

</details>

## 2026-11-25 · arreglar
- **Motivo** (probado en juego por Fabián): "Salir" en los resultados no sacaba del campo; disparar a los blancos daba estrellas; los blancos eran CJ negros.
- **Causas**:
  - `client/c_main.lua`: `inside` solo se ponía al abrir el menú en el mostrador (false) y nunca pasaba a true al empezar a entrenar, así que "Salir" solo cerraba la ventana.
  - Los blancos son peds: dispararles cuenta como delito en `rp_wanted` y `rp_police` daba aviso de "disparos" con casquillos.
  - `TARGET_SKIN = 0` es el cuerpo de CJ sin ropa.
- **Nota**: 100 → 100.
- **Cambios**: `inside = true` en `rp:range:start`; búsqueda suspendida al entrar y restaurada al salir solo si la suspendimos nosotros (INT-07); `rp_police` ignora disparos con la búsqueda suspendida; `TARGET_SKINS` con pandilleros al azar.
- **Reglas manuales revisadas**: CIC-03 ✔, CIC-06 ✔, INT-07 ✔.
- **Pendiente**: desconectarse dentro del campo puede dejar al personaje en el interior 7 al volver (shortcut documentado en `s_main.lua`); coordenadas de las otras 6 armerías.
- **Probar en juego**: entrenar, terminar o F2, "Salir" → vuelves al mostrador; disparar sin que suban estrellas ni salga aviso a la policía; blancos con ropa.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 538aa22)

**Nota: 100/100** · OK 32 · FALLA B 0 · FALLA I 0 · AVISO 0

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | R | EST-06 | Cabecera de comentario en cada .lua |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-01 | Handlers de eventos remotos usan client |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-03 | SQL parametrizado (sin concatenar) |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 22000 23000 |
| OK | R | INT-06 | Teclas sin choques con otros recursos | f2 |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |

</details>

## 2026-11-25 · crear
- **Motivo**: campo de tiro de Ammu-Nation (solo Market): entrena la habilidad nativa de arma (stats 69-79) con armas y balas reales del inventario.
- **Nota**: — → 98 (sin FALLA B; AVISO DOC-04 resuelto con este archivo).
- **Cambios**: recurso nuevo; tabla `weapon_skills`; exports `suspendWeapons/resumeWeapons` en `rp_ammunation`; CEF con menú, HUD de esquina y resultados; sesiones aisladas en dimensión `23000+n`; cada disparo descuenta 1 bala (`takeItem`); impactos por rayo propio del servidor contra zonas (cabeza/torso/piernas), un impacto por blanco y tope de 120 puntos de habilidad por sesión; stat restaurada al valor entrenado tras cada disparo (los fallos no suben habilidad).
- **Reglas manuales revisadas**: SEG-02 ✔ (arma, balas y puntos salen de config e inventario), SEG-04 ✔, BD-06 ✔, PRU-02 ✔ (tabla y recurso en `rp_test`).
- **Pendiente**: coordenadas del campo (`RANGE.FIRE`, `RANGE.DESK`, interior 7) sin verificar en juego; las otras 6 armerías (faltan coordenadas); `scripts/test.sh` no pudo ejecutarse en Windows (entrypoint de Docker con CRLF), pasarlo en Mac/Linux.
- **Probar en juego**: E en el mostrador de Ammu-Nation Market; sin armas (mensaje); con arma y balas; las balas bajan al disparar y no se duplican al salir; blancos en su sitio y de cara; impactos por zona; las 3 rondas; F2 abandona; habilidad sube solo con aciertos y persiste tras reconectar; dos jugadores a la vez; abatido y desconexión dentro del campo; el arma de antes se vuelve a equipar al salir.
