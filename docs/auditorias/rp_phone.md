# Auditoría de rp_phone

## 2026-11-27 · mejorar
- **Foco**: Tinder completo, como la app real, con jugadores reales y personas simuladas (NPC) que se sienten vivas.
- **Nota**: 59/100 (las 3 fallas que quedan son previas y ajenas a Tinder: SQL concatenado en `s_social.lua`, `rp:hudHidden` en `c_camera.lua` y `rp_radio` sin `<include>` en la música).
- **Cambios**:
  - Servidor reescrito y partido por responsabilidad: `s_tinder.lua` (perfil, mazo, likes, Super Like, cupo diario, Gold, matches, chat entre jugadores, «Le gustas», globo), `s_tinder_npcs.lua` (generación, decisiones, motor de chat, bucles de simulación, estudio), `s_tinder_data.lua` (16 arquetipos) y `s_tinder_lines.lua` (frases e intenciones). Catálogo compartido en `shared/s_tinder.lua`.
  - 72 personas simuladas con skin, edad, barrio, trabajo, gustos, biografía, preguntas del perfil y forma de escribir propias. Deciden tu like con retraso según exigencia, perfil, gustos y edad; dan like solas; escriben primero; contestan con retraso y duermen de noche; «Visto» y «escribiendo...»; interés oculto que sube y baja con lo que escribes; insisten, ghostean, deshacen el match; aceptan o proponen citas y dan su número (vínculo de `rp_npcrel` con `createDateContact`).
  - Estudio de fotos `/tinderstudio` (admin): la cámara recorre 21 escenarios de San Andreas con su hora y clima y saca selfies, retratos, cuerpo entero, sentado, tumbado, junto a su auto y paisajes; sube foto 360×450 y miniatura. Mientras no hay foto, la app dibuja el escenario.
  - Interfaz CEF nueva: tarjetas que se arrastran con sellos LIKE/NOPE/SUPER, carrusel de fotos, perfil completo, Le gustas (difuminado sin Gold), mensajes, chat con rompehielos, match animado, perfil con 4 fotos, pasiones, rango de edad y % de perfil completo, Gold con cobro del banco.
  - Experiencia: teclas y ratón dibujados en el mazo y en el tutorial de 4 pasos de primera vez (UX-01, UX-03); una cosa a la vez: la acción importante destacada y el resto en pestañas (UX-02); sonidos Kenney por evento (UX-06); aviso cuando llega un mensaje con el teléfono cerrado o en otra pestaña; Esc cierra primero lo abierto en la app.
  - Seguridad: todo evento usa `client`, valida claves `p<id>`/`n<id>`, longitudes, JPEG base64, match vigente antes de escribir o ver fotos, cooldowns y tope de 25 mensajes por minuto (SEG-01..04). Cobro de Gold con `rp_bank:chargeAccount` (atómico).
  - Base de datos: 7 entradas nuevas al final de `schema.lua` (columnas de `tinder_profiles` y tablas `tinder_profile_photos`, `tinder_npcs`, `tinder_npc_photos`, `tinder_npc_links`, `tinder_npc_messages`, `tinder_messages`).
  - Pruebas en `rp_test` (`s_tests_tinder.lua`): catálogo, tablas, NPC con fotos planificadas y motor de chat (contesta sin marcas, grosería → se va, aburrido con interés bajo → ghost, cita con interés alto → acepta).
- **Reglas manuales revisadas**: SEG-02 ✔ (el servidor decide likes, matches, interés y respuestas; el cliente solo reenvía), SEG-04 ✔ (cooldowns por acción y tope de mensajes), BD-06 ✔ (todo escrito en el momento; la simulación vive en la BD y sobrevive reinicios), PRU-02 ✔, UX-10 ✔ (`CREDITOS.md`), CIC-03 ✔ (estudio: muerte o parada del recurso devuelven cámara, controles, HUD, hora y clima).
- **Pendiente**: las 3 fallas previas de Fotogram/cámara/música; afinar en juego las coordenadas de los escenarios del estudio si alguno queda mal encuadrado.
- **Probar en juego**: `/tinderstudio` con un admin (que termine y las fotos se vean); perfil con foto y pasiones; deslizar con ratón y flechas; Super Like; quedarse sin likes; match con un NPC (esperar unos minutos); chatear (preguntas, gustos en común, grosería, «ok» repetido); pedir una cita y llamar al número; dos jugadores dándose like y chateando; Gold con y sin saldo; `restart rp_phone` con el chat abierto.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-27, commit 48927bc)

**Nota: 59/100** · OK 26 · FALLA B 2 · FALLA I 1 · AVISO 3

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| FALLA | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) | sin include: rp_radio |
| FALLA | B | BD-03 | SQL parametrizado (sin concatenar) | resources/[roleplay]/rp_phone/server/s_social.lua:314:    end, "SELECT " .. POST_COLUMNS .. [[ ; resources/[roleplay]/rp_phone/server/s_social.lua:326:    end, "SELECT " .. POST_COLUMNS .. [[ ; resources/[roleplay]/rp_phone/server/s_social.lua:428:    end, "SELECT character_id FROM social_profiles WHERE username IN (" .. marks .. ") |
| FALLA | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed | resources/[roleplay]/rp_phone/client/c_camera.lua:153:    setElementData(localPlayer, "rp:hudHidden", false, false) ; resources/[roleplay]/rp_phone/client/c_camera.lua:171:        setElementData(localPlayer, "rp:hudHidden", true, false) |
| AVISO | R | EST-06 | Cabecera de comentario en cada .lua | resources/[roleplay]/rp_phone/config.music.lua |
| AVISO | I | DOC-02 | Exports documentados en RECURSOS.md | getCameraConfigErrors ; socialResetCooldowns ; stopVehicleMusic |
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_phone.md |
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-01 | Handlers de eventos remotos usan client |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 8 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos | p |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
