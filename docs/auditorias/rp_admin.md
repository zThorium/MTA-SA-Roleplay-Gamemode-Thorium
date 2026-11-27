# Auditoría de rp_admin

## 2026-11-27 · arreglar (giro de los NPC al moverlos)
- **Síntoma**: Fabián: al mover y girar un ped (tienda, traficante, entrenador, autoescuela, boletería) el giro no se guarda.
- **Causa raíz (probable, sin prueba en juego)**: la vista previa de `c_move.lua` giraba el ped con `setElementRotation` sin `conformPedRotation`, que en MTA aplica el giro de los peds de forma distinta a `createPed`; lo que se veía al girar no coincidía con lo guardado y al guardar el NPC aparecía con otra orientación. El admin suele ser quien sincroniza ese ped, así que el giro de la vista previa también podía llegar al servidor.
- **Arreglo**: en la vista previa (y al cancelar), los peds se giran con `setElementRotation(ped, 0, 0, giro, "default", true)` usando el mismo giro que se guarda. En `s_move.lua`, tras guardar, si el elemento nuevo es un ped se le fija el giro guardado con `conformPedRotation`.
- **Prueba de regresión**: sin prueba automática (es cliente y sincronización de peds); `admin_exports_mover` sigue cubriendo el servidor.
- **Probar en juego**: girar 90° un NPC de tienda con el anillo, guardar, alejarse y volver (o reconectar): mira hacia donde se dejó, y otro jugador lo ve igual.

## 2026-11-27 · mejorar (mover elementos con ALT o M + clic derecho)
- **Motivo**: Fabián pide mover lo mal colocado sin comandos: con la vista ALT, clic derecho sobre lo que se mira abre un editor tipo Blender (fácil); con el cursor M, clic derecho sobre un elemento abre opciones de admin, entre ellas Mover.
- **Nota**: 68 → 70 (FALLA anteriores sin cambios: BD-04 por `admin_log` en `s_commands.lua` y EST-02 de `c_freecam.lua`).
- **Cambios**: `c_move.lua` (editor: flechas 3D X/Y/Z y anillo de giro arrastrables, panel con − / + y campos que se arrastran, Mayús = fino, «Al suelo» manteniendo la altura sobre el suelo, «A mis pies», «Deshacer», Enter guarda, Retroceso cancela, clic derecho mantenido para mirar; vista previa moviendo solo en el cliente el elemento principal alrededor del punto guardado; menú del cursor M: Mover · Copiar /goto · Borrar con confirmación). `s_move.lua` revalida admin, tipo, números finitos, mismo interior/dimensión, máx. 60 m desde la posición anterior y admin a menos de 120 m; llama al export nuevo `adminMove` del recurso dueño y deja `/mover` en `admin_log`. Export `adminMove` en `rp_bank`, `rp_shops`, `rp_clothing`, `rp_vending`, `rp_dealers`, `rp_robbery` (no durante un robo), `rp_gym` (no con alguien entrenando, ni el entrenador fijo ni en combate), `rp_driving`, `rp_pool` (no mesas del mapa ni con partida), `rp_train` (barreras y piezas de estación), `rp_properties` (puerta o salida interior) y `rp_3dtext` (queda como edición en `text3d_log`): actualizan la fila y vuelven a crear el elemento con sus funciones de siempre. Solo giro Z: las tablas no guardan rx/ry.
- **Reglas manuales revisadas**: SEG-02 ✔ (eventos remotos con `client`, nivel admin, cooldown 0,5 s y todo revalidado en el servidor) · BD-06 ✔ · UX-01 ✔ (Enter, Retroceso, Mayús y ratón dibujados) · UX-06 ✔ (sonidos del juego al abrir, arrastrar, guardar y fallar) · UX-10 ✔ (iconos de `assets/`, `CREDITOS.md`).
- **Pendiente**: rx/ry (haría falta columna nueva en cada tabla); mover vehículos y elementos sueltos (no tienen dueño con `adminMove`).
- **Probar en juego**: ALT + clic derecho sobre una expendedora, una máquina del gym, un torniquete y la salida de una casa; arrastrar cada flecha, el anillo y los números; Al suelo / A mis pies / Deshacer; Enter guarda y otro jugador lo ve movido; Retroceso deja todo como estaba; M + clic derecho sobre un cajero → Mover / Copiar / Borrar (pide confirmación); intentar mover más de 60 m o una mesa con partida → aviso de error.

## 2026-11-27 · mejorar (vista de admin con ALT)
- **Motivo**: Fabián pide que, manteniendo ALT, un admin vea sobre cada entidad su ID, quién la creó y su dueño (vehículos, casas, expendedoras, torniquetes, máquinas del gym...) para administrar y corregir lo mal puesto sin buscar a ciegas.
- **Nota**: 68 → 68 (las dos FALLA son anteriores: `admin_log` se crea en `s_commands.lua` (BD-04) y `c_freecam.lua` sin `cache="false"` (EST-02); no se tocan en este cambio).
- **Cambios**: `s_inspect.lua` (servidor) y `c_inspect.lua` (cliente). El servidor recorre todos los tipos de `WORLD_TYPES` (`adminElements`), los vehículos y los objetos/pickups/marcadores/peds sueltos de cualquier recurso (se ignoran `rp_citizens`, `bone_attach`, `rp_heads` y lo adjunto) en el mismo interior y dimensión, resuelve nombres de dueños en la BD y manda la lista solo a admins (cooldown 0,8 s). El cliente dibuja etiquetas por color (naranja = elemento de admin, verde = casa, azul = vehículo, gris = suelto) y amplía lo que está en el centro de la pantalla con dueño, creador, fecha, recurso, posición y comandos `/goto`/`/del`. Tabla nueva `admin_world_creators` al final de `schema.lua`; el creador se apunta vigilando el comando `create` de cada tipo (diferencia de IDs antes/después durante 10 s) y se borra con `/del<tipo>`. `adminElements` admite campos opcionales: `rp_properties` añade dueño, fecha, tipo/precio y la salida interior; `rp_3dtext` su creador.
- **Reglas manuales revisadas**: SEG-02 ✔ (el único evento remoto revalida nivel admin con `client` y tiene cooldown; no recibe argumentos) · BD-06 ✔ (el creador se escribe al crear) · PRU-02 ✔ (`admin_creadores_de_elementos` en `s_tests_admin.lua`) · UX-01 ✔ (tecla ALT dibujada en la cabecera) · UX-10 ✔ (`images/tecla_alt.png` de `assets/`, `CREDITOS.md`) · CLI-02 ✔ (render solo mientras ALT está pulsado; datos refrescados cada 1,5 s, no por fotograma).
- **Pendiente**: lo creado antes de este cambio sale "sin registro" de creador (no había dónde guardarlo). Las FALLA anteriores (BD-04, EST-02 de `c_freecam.lua`).
- **Probar en juego**: como admin, mantener ALT junto a un cajero, una máquina del gym, un torniquete, una expendedora, una casa (fuera y dentro, en la salida) y vehículos propios y de tráfico; mirar uno al centro y comprobar la ficha; crear algo con `/crearexpendedora` y ver tu nombre como creador; soltar ALT (y Alt+Tab) y que desaparezca; un jugador sin admin no ve nada.

<details><summary>Informe del auditor</summary>

### Auditoría automática (2026-11-27, commit 88ac7db)

**Nota: 68/100** · OK 24 · FALLA B 1 · FALLA I 1 · AVISO 6

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| FALLA | I | EST-02 | Scripts de cliente con cache="false" | meta.xml:16 c_freecam.lua |
| FALLA | B | BD-04 | Esquema solo en rp_database/schema.lua | resources/[roleplay]/rp_admin/s_commands.lua:90:        CREATE TABLE IF NOT EXISTS admin_log ( |
| AVISO | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | estado por jugador ligado a personaje sin rp:onCharacterLogout |
| AVISO | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 18 outputChatBox: revisar si son avisos de acciones |
| AVISO | R | INT-06 | Teclas sin choques con otros recursos |  f: rp_driving ; |
| AVISO | I | DOC-02 | Exports documentados en RECURSOS.md | isFreecamActive |
| AVISO | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda | /admins ; /apagar ; /copiardebug ; /debug ; /setarmor ; /sethp |
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_admin.md |
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
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
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
