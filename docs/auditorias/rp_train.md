# Auditoría de rp_train

## 2026-11-26 · crear
- **Motivo**: devolver el tren de San Andreas al servidor, con bocina si hay alguien en la vía y pasos a nivel con barreras, campanas y tráfico IA que se detiene.
- **Nota**: — → 96/100  (OK 26, FALLA B 0, FALLA I 0, AVISO 2)
- **Cambios**: recurso nuevo. Vía principal desde `tracks.dat` (solo servidor); el servidor simula la posición de cada tren y solo el cliente que lo sincroniza aplica la velocidad (BD-05 espera a la BD, CLI-02 sin onClientRender: temporizador de 250 ms solo con trenes cargados). Tabla `rail_crossings`; comandos de admin en el panel (DOC-03); prueba en `rp_test` (PRU-01). `rp_citizens` frena ante barreras bajadas.
- **Reglas manuales revisadas**: SEG-02 ✔ (sin eventos remotos), BD-06 ✔ (INSERT/DELETE parametrizados), PRU-02 ✔ (4 pruebas PASS), UX-10 ✔ (sonido con CREDITOS.md). CIC-04: temporizadores permanentes que mueren con el recurso.
- **Pendiente**: calibrar en juego la posición y el giro del brazo 968 (`side`, `/crearbarrera inv`); comprobar que la bocina nativa suena con `setPedControlState` en clientes que no sincronizan el tren.
- **Probar en juego**: esperar el tren en Unity Station (para 20 s); pararse en la vía (bocina); `/crearbarrera` a cada lado de un cruce y ver bajar/subir barreras, campanas y autos IA detenidos; `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit 0f460db)

**Nota: 96/100** · OK 26 · FALLA B 0 · FALLA I 0 · AVISO 2

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | I | CIC-04 | Los timers se pueden cancelar | usa setTimer y nunca killTimer/isTimer |
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_train.md |
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | R | EST-06 | Cabecera de comentario en cada .lua |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-03 | SQL parametrizado (sin concatenar) |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 1 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | SEG-01 | Handlers de eventos remotos usan client | sin eventos remotos |
| N/A | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit | sin estado por jugador |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | sin estado por jugador |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
