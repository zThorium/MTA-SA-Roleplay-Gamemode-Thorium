# Auditoría de rp_wanted

## 2026-11-27 · mejorar · foco: IA de combate y persecución
- **Contexto**: Fabián pidió mejorar la inteligencia de la policía IA en combate y persecución. Decisiones: modelo de búsqueda por última posición conocida (GTA V), «más lista, no más letal».
- **Diagnóstico**:
  1. Policía omnisciente: todas las unidades usaban la posición real del jugador (rutas, persecución, a pie, heli, puntos de aparición), así que esconderse no servía.
  2. Puntería perfecta (`setPedAimTarget` exacto) y disparo sincronizado dentro de cada unidad.
  3. A pie, todos en línea recta al jugador, parados al descubierto, sin cobertura ni flanqueo, con fuego amigo y atascados en vallas.
  4. En vehículo: volante solo proporcional (zigzag), todas las patrullas al mismo punto (choques entre ellas), PIT sin criterio, `obstacleAhead` sin edificios (se estrellaban contra muros en la persecución directa) y heli que nunca te pierde.
  5. Bug: al subir de 2 a 4+★ las unidades que ya estaban no cambiaban de arma.
- **Fase 1 · búsqueda (P5)**: nuevo `client/c_knowledge.lua` con los modos `live`, `predict` y `search` (`WANTED_SEARCH`).
  - Si no te ven van a tu última posición y barren calles; si ibas a pie, se bajan; el heli orbita y barre con el foco.
  - Un delito denunciado (`rp:wanted:reveal`) o disparar con policías cerca te delata.
  - Sin avistamiento no hay atajos (salto por delante, intercepción, controles, pinchos).
  - Arreglada la caché de `pathPointAhead`.
- **Fase 1b · CLI-04**: la nueva vista arrancaba un timer al cargar con la config compartida; ahora arranca en `onClientResourceStart`.
- **Fase 2 · combate (P5)**: nuevo `client/c_combat.lua` (`WANTED_COMBAT`).
  - Puntería con error por distancia, velocidad, estrellas y daño.
  - Ritmo propio con recarga y sin fuego amigo.
  - Anillo alrededor del jugador con desplazamiento lateral al disparar.
  - Cobertura al ser apuntados, heridos o con poca vida.
  - Rendición (uno arresta, el resto cubre) y salida de atascos a pie.
  - Los tiradores de patrullas y lanchas usan el mismo error y ritmo.
- **Fase 3 · persecución (P5)**:
  - Volante amortiguado.
  - Huecos laterales entre patrullas.
  - Encajonar (detrás, delante y costado) si vas lento.
  - PIT con ángulo y espera entre intentos.
  - Rayo contra muros que devuelve a la ruta por calles.
  - Arreglo del arma al subir de nivel (`s_units.lua`).
  - Pruebas en `rp_test` (`s_tests_wanted.lua`) con los exports `getCopWeapon` y `getPoliceAIConfigErrors`.
- **Fase 4 · EST-03 y DOC-02**:
  - `rp_police` es dependencia opcional comprobada con `getResourceFromName`; no se puede usar `<include>` porque `rp_police` incluye a `rp_wanted`.
  - Exports documentados en `RECURSOS.md` y sección «IA policial» en `docs/BUSQUEDA_POLICIAL.md`.
- **Nota**: 89 → 96 (0 FALLA).
- **Reglas manuales revisadas**:
  - SEG-02: el cliente sigue sin decidir nada que el servidor no valide; `rp:wanted:reveal` va del servidor al cliente y los arrestos siguen midiendo la distancia en el servidor.
  - CIC-03: las unidades nuevas no existen; el estado de combate y búsqueda vive en tablas de claves débiles o en la unidad y muere con ella.
  - INT-07: `rp_police` y `rp_citizens` son opcionales y van protegidos.
  - CLI-02: nada nuevo en `onClientRender`; la vista se mira cada 250 ms y la cobertura hace como mucho una búsqueda por tick.
- **Pendiente**:
  - BD-05 y DOC-03 (avisos previos).
  - Cono de visión (hoy los policías ven en 360° con línea de visión).
  - Búsqueda dentro de interiores.
  - Los valores de `WANTED_COMBAT` y `WANTED_SEARCH` son de diseño: hay que ajustarlos a oído en juego.
- **Probar en juego** (no hay Docker ni servidor local en esta máquina; la sintaxis se comprobó con un parser de Lua 5.1, pero `scripts/test.sh` no se pudo ejecutar):
  - Con 2★, rompe la línea de visión y escóndete: las patrullas van a tu última posición y barren calles; si ibas a pie, se bajan a buscar; las estrellas parpadean y bajan; si disparas, te encuentran.
  - A 3★, bajo un puente o túnel el heli te pierde y barre con el foco.
  - A pie a 2-3★: te rodean, se desplazan de lado, se cubren al apuntarles, no se disparan entre ellos y fallan más de lejos o corriendo. Quieto sin apuntar, uno te arresta.
  - En auto: no zigzaguean ni se chocan entre ellas; si vas lento, te encajonan; no se estrellan contra muros.
  - Regresión: arresto en la puerta, controles, pinchos, lanchas, SWAT a rapel, Pay 'n' Spray, `rp_robbery` (persecución retenida y condiciones) y `/debugscript 3` limpio.

<details><summary>scripts/auditar-recurso.sh rp_wanted --md</summary>

### Auditoría automática (2026-11-27, commit 150bd64)

**Nota: 96/100** · OK 28 · FALLA B 0 · FALLA I 0 · AVISO 2

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | I | BD-05 | Espera a la BD al arrancar | usa getConnection sin isReady()/rp:onDatabaseReady (revisa si consulta antes de que la BD esté lista) |
| AVISO | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda | /delitosdebug ; /encarcelar ; /liberar |
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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 8 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | no usa personajes |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>

## 2026-11-27 · mejorar · foco: persecución por mar y SEG-01
- **Contexto**: al planear el helicóptero policial para `rp_citizens` se vio que `rp_wanted` ya lo tiene completo (círculo sobre el jugador, foco de noche, tirador desde 4★ y SWAT a rapel), así que no se duplicó. El hueco real era el agua: si huías en barco, las patrullas se quedaban en la orilla.
- **Fase 1 · SEG-01 (bloqueante, previo)**: `rp:wanted:garages` (abre los portones de los Pay 'n' Spray que el cliente localiza con `getGarageBoundingBox`) no comprobaba `client`: cualquier cliente podía abrir cualquier garaje del juego cuantas veces quisiera. Ahora exige `client`, acepta como mucho 10 IDs (hay 4 Pay 'n' Spray) y una petición cada 5 s por jugador (limpieza en `onPlayerQuit`).
- **Fase 2 · persecución por mar**: nueva unidad `boat` (lancha Predator 430, piloto y tirador con el uniforme de la ciudad, `rp:copCar`). Mientras el buscado va en barco o nadando (`atSea`: vehículo de tipo `Boat` o `isElementInWater`), el despacho no manda patrullas de calle, controles ni pinchos: pide lanchas (`WANTED_BOAT.PER_LEVEL`: 1-1-2-2-2-3) y sigue mandando el helicóptero que toque. El cliente elige el punto con el nuevo export de `rp_citizens` `citizenBoatSpot` (nodo de barcos a 110-220 m, fuera de la vista, en `pcall`: sin `rp_citizens` no salen lanchas) y la maneja con `boatTick`: va hacia donde estará el jugador en 1,5 s; por debajo de 3★ lo ronda a 18 m y desde 3★ lo embiste; si se atasca contra la orilla da marcha atrás. El tirador reutiliza `carGunners` (dispara desde 2★, como en las patrullas). Tras 15 s en tierra (`LAND_LEAVE_MS`) las lanchas se retiran y vuelven las patrullas. Se aprovechan sin cambios la retirada por distancia (`unitLost`), los cuerpos, el abandono al terminar la búsqueda y el fundido al retirarse.
- **Nota**: 72 → 87 (0 FALLA B).
- **Reglas manuales revisadas**: SEG-02 (el punto de aparición de la lancha lo valida el servidor con la misma distancia 30-320 m que las patrullas; si el cliente mintiera, solo se perjudica él), CIC-03 (las unidades `boat` usan el mismo ciclo de vida que las demás), INT-07 (dependencia opcional de `rp_citizens` con `pcall`).
- **Pendiente**: EST-03 (dependencia sin `<include>`, previa). Las lanchas no arrestan: como en GTA SA, en el agua solo persiguen y disparan; al llegar a tierra te esperan las patrullas.
- **Probar en juego**: con estrellas, sube a un barco (o nada) en la bahía de SF o en la costa de LS: deben aparecer lanchas Predator fuera de la vista y perseguirte; a 1-2★ te rodean y el tirador dispara (desde 2★); a 3★ te embisten; al bajar a tierra, a los 15 s se van y vuelven las patrullas. Que no se queden atascadas en los muelles y que `/debugscript 3` siga limpio. Abrir y usar un Pay 'n' Spray sigue funcionando.

<details><summary>scripts/auditar-recurso.sh rp_wanted --md</summary>

### Auditoría automática (2026-11-27, commit a2ce04e)

**Nota: 87/100** · OK 25 · FALLA B 0 · FALLA I 1 · AVISO 4

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| FALLA | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) | sin include: rp_police |
| AVISO | I | BD-05 | Espera a la BD al arrancar | usa getConnection sin isReady()/rp:onDatabaseReady (revisa si consulta antes de que la BD esté lista) |
| AVISO | I | DOC-02 | Exports documentados en RECURSOS.md | adoptLocalCop ; clearWanted ; getWantedChaos ; getWantedLevel ; isPlayerJailed ; isWantedPolice |
| AVISO | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda | /delitosdebug ; /encarcelar ; /liberar |
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_wanted.md |
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 8 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | no usa personajes |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
