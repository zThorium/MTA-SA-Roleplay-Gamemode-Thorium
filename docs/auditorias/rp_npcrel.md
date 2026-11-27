# Auditoría de rp_npcrel

## 2026-11-27 · mejorar
- **Foco**: rehacer toda la UI de los vínculos con NPC y ampliar los diálogos.
- **Nota**: 85 → 100.
- **Cambios**:
  - **UI en CEF** (antes todo dx con fuente por defecto): ficha de la persona con avatar, camino de 6 etapas, barras de amistad y romance con umbrales marcados (Conocido, Amigo, Se gustan, Salir, Estable), ganancias flotantes (+4 / −2), meta siguiente 🎯, rasgos que se descubren («???» hasta Conocido/Amigo), humor y barra de «ganas de charlar»; acciones agrupadas por tipo con efecto, precio, candado con el requisito y avisos «Aburre» / «Arriesgado» / «Solo te ve como amigo»; atajos 1–0 (UX-01, UX-02).
  - Diálogo: se ve lo que dice el jugador («Tú») y la respuesta con efecto máquina de escribir; la frase de nueva etapa y la de cansancio llegan en cola. Cartel animado de nueva etapa y aviso cuando te recuerda o te da su número (UX-06).
  - Tecla **H** dibujada (Kenney) en el aviso sobre el peatón, con corazón si es un vínculo que vino a verte (UX-01). Globo de emoción (Kenney Emotes) sobre la cabeza según el resultado: risa, corazón, corazón roto, enojo, puntos suspensivos al aburrirse, estrellas al subir de etapa (UX-07).
  - Sonidos por evento (Kenney, CC0) y tutorial guiado de 3 pasos con foco la primera vez (se recuerda en un archivo privado del cliente) (UX-05, UX-06).
  - `/vinculos` abre un panel con filtros por etapa, teléfono, días sin hablar, aviso de que se enfría y la meta de cada persona (antes eran líneas en el chat: INT-04).
  - **Diálogos**: de ~40 a ~300 frases en `server/s_lines.lua` (solo servidor): saludos por etapa, hora, visita tras llamada y ausencia larga; frases del jugador por acción; respuestas por nivel de confianza; reacciones según rasgo; frases al subir de etapa; teléfono (contesta / no contesta).
  - Arreglo: «Qué atrevid@» usaba el género de la persona aunque hablaba del jugador; ahora hay marcas separadas `{o}` (persona) y `{e}` (jugador), y `{p}` con el nombre del personaje.
  - Robustez: timers con nombre que se cancelan (CIC-04), dependencias opcionales `rp_citizens` y `rp_levels` comprobadas (EST-03), no se abre nada si la BD no está lista (BD-05), si el servidor no responde se vuelve a poder elegir.
  - Prueba `npcrel_banco_de_dialogos` en `rp_test` (todas las acciones y etapas tienen frases y ninguna deja marcas sin sustituir) (PRU-01).
- **Reglas manuales revisadas**: SEG-02 ✔ (el servidor decide resultado, dinero y etapa; el cliente solo reenvía el id de acción), SEG-04 ✔ (cooldown por acción y por conversación), UX-10 ✔ (assets CC0/OFL, `CREDITOS.md`), CLI-03 ✔ (texturas creadas una vez al arrancar), CIC-03 ✔ (abatido, muerto, en vehículo o lejos cierra la escena).
- **Pendiente**: el regalo sigue cobrando con `takePlayerMoney` (dinero en mano, igual que antes); revisar si debe pasar por el cobro atómico de `rp_characters`.
- **Probar en juego**: la primera charla muestra el tutorial; clic y teclas 1–0; Backspace para irse; subir a Conocido (aviso «te recuerda»), a Amigo y a Coqueteo (número automático); rechazo romántico; quedarse sin ganas de charlar; llamar por teléfono a un vínculo y que llegue; `/vinculos` y cerrar con Esc; morir y `restart rp_npcrel` con la escena abierta.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-27, commit de4323d)

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
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 3 outputChatBox |
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
