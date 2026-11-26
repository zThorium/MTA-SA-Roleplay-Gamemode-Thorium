# Auditoría de rp_map

## 2026-11-26 · mejorar
- **Motivo**: pedido de Fabián: quitar la música del mapa (derechos de autor), tutorial solo la primera vez, mapa a pantalla completa, clic en un punto = destino con ruta en el minimapa, solo los admins crean iconos y dos vistas para el admin con `/mapajugador`.
- **Nota**: 100/100 → 100/100  (OK 32, FALLA B 0, FALLA I 0, AVISO 0)
- **Cambios**: el tema de Rockstar se sustituye por «Calm Relax 1» de cynicmusic (`sounds/map_theme.mp3`, 128 kbps, en bucle desde el inicio y desactivable en Ajustes; licencia por confirmar en `CREDITOS.md`); la radio y la música del teléfono siguen pausándose. Se quitan los marcadores de jugador (eventos `rp:map:marker*`, pestaña y buscador; `map_markers` queda sin uso). El clic en el mapa marca el punto y lanza el GPS al instante. El tutorial se marca como visto al mostrarse (preferencia del personaje, que ya no vuelve a `false`, y `@map_tutorial.xml` local); el cooldown del servidor es por acción para que no se pierda el guardado de preferencias. La ventana ocupa el 100 % de la pantalla. Vista de admin (todos los lugares, sin niebla) y vista de jugador con `/mapajugador` o el botón «Vista»; «Crear lugar aquí» y «Editar lugar» desde las tarjetas.
- **Reglas manuales revisadas**: SEG-02 ✔ (se quitan eventos remotos), SEG-04 ✔ (`/mapajugador` y `rp:map:admin:view` comprueban el nivel de admin en el servidor), PRU-02 ✔ (`map_*` PASS; CEF revisado sin ventana en `#demo`).
- **Probar en juego**: abrir dos veces (el tutorial sale solo la primera); clic en un punto (ruta en el minimapa); `/mapajugador` con un admin; cuenta de nivel 0 sin botón «Vista» ni Admin.

## 2026-11-26 · crear
- **Motivo**: sustituir el mapa F11 de GTA por un mapa propio estilo GTA VI: niebla de exploración por personaje, cuadrículas por ciudad, lugares que se descubren, marcadores, GPS con rutas reales, buscador, estadísticas, vista 3D con edificios y panel de admin; tema musical mientras está abierto y la radio y la música del teléfono en pausa.
- **Nota**: — → 100/100  (OK 32, FALLA B 0, FALLA I 0, AVISO 0)
- **Cambios**: recurso nuevo (ver `docs/MAPA.md`). Datos reales de GTA SA generados con `tools/generar-datos.ps1` (radar, `NODES*.DAT` con el sentido de las calles, IPL + COL de los edificios y relieve). El servidor descubre las celdas por posición (SEG-02: el cliente no puede marcar nada; solo recibe los lugares que puede ver). Siete tablas nuevas al final de `schema.lua` (BD-07: `character_id` con CASCADE en exploración, marcadores y preferencias). Admin revalidado en el servidor (SEG-04) y en el catálogo del panel (DOC-03). `rp_hud:setNavRoute` y `rp_phone:setMusicSuppressed` nuevos. Pruebas en `rp_test` (PRU-01).
- **Reglas manuales revisadas**: SEG-02 ✔ (tipos, rangos, longitudes, propiedad del marcador y `client`), SEG-04 ✔ (`guard` en cada evento de admin y en los comandos), BD-06 N/A (no cobra), PRU-02 ✔ (`map_*` PASS en `scripts/test.sh`; GPS y cuadrícula probados aparte con Lua 5.1 sobre los datos reales; CEF revisado en Edge sin ventana con `#demo`, `#demo3d` y `#demotuto`), UX-10 ✔ (teclas y sonidos de `assets/` con `CREDITOS.md`; Three.js MIT), UX-01/03/05 (gesto dibujado y entrenador de 6 pasos), INT-08 (textos con tildes).
- **Pendiente**: probar el cliente en el juego; confirmar que `toggleControl("radar", false)` y la cancelación de F11 en `onClientKey` impiden siempre el mapa nativo (además, `forcePlayerMap(false)` en cada frame).
- **Probar en juego**: F11 y Esc (sin moverse, con música en bucle desde el inicio y la radio y el teléfono en pausa); caminar y conducir para ver abrirse la niebla; marcadores; GPS con el mapa cerrado, desviándose y llegando; 3D; buscador; pestaña Admin con nivel 0 y con nivel 1; reconectar; `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit f8baccc)

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
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
