# Auditoría de rp_medics

## 2026-11-28 · crear
- **Motivo**: fase 0 de la facción de médicos (issue #101 `rp_rol_medico`): servicio en el vestuario del hospital con casillero personal (ítems y mochila) y ambulancias. Plan completo (heridas tipo ACE, llamadas 912, incidentes NPC, hospital) en fases siguientes.
- **Nota**: nuevo → 100/100 (0 FALLA B).
- **Diseño**:
  - Copia el molde de `rp_firefighters` (vestuario, garaje, puntos en BD movibles con `rp_markers`, blips de compañeros). El tipo `medicos` de `FACTION_TYPES` ahora tiene `duty = "rp_medics"` y `dutyData = "rp:medDuty"`: el sueldo de rol solo se cobra de servicio.
  - Casillero personal genérico por tipo de facción (`faction_locker_items`, `faction_locker_backpack`) para que el vestuario genérico de F0.2 (#104) lo reutilice. Memoria autoritativa con escritura en el momento; mover = quitar de un lado y poner en el otro, y si la entrega falla se deshace.
  - La mochila se guarda entera con `rp_backpacks:stowBackpack` (nuevo) y se devuelve con `equipFromGround`. La mochila médica `bp_medic` (`duty = true`) no se tira y `rp_backpacks` la borra al reconectar, así el material no sale del servicio aunque el jugador se desconecte de servicio.
  - Las armas se enfundan con `rp_ammunation:suspendWeapons/resumeWeapons` antes de guardarlas (se vuelcan las balas gastadas).
  - `rp_interact`: «Reanimar (servicio)» ahora exige estar de servicio (antes bastaba con ser de la facción).
- **Reglas manuales revisadas**: SEG-02 ✔ (`client`, acción en lista blanca, tipos, facción, cercanía al vestuario con interior/dimensión, sin vehículo, no abatido/esposado/cargado), SEG-03 ✔ (cooldown 500 ms), SEG-04 ✔ (`/medmover` con nivel 1), BD-06 ✔ (no mueve dinero), BD-07 ✔ (tablas con FK `ON DELETE CASCADE`, escritura en el momento), CIC-03 ✔ (rehidrata casillero y puntos al reiniciar; al parar quita uniforme y mochila médica), CIC-06 ✔ (abatido/esposado bloquea el vestuario; al echarlo de la facción sale de servicio y sus cosas siguen en el casillero), INT-07 ✔ (rp_factions, rp_inventory, rp_backpacks, rp_ammunation, rp_markers, rp_characters:restoreCharacterLook), INT-09: **N/A** en esta fase (entrar de servicio o usar el casillero es trivial y farmeable; los logros llegan con la atención de pacientes en la fase 1), UX-01 ✔ (E y clic dibujados), UX-02/05 ✔ (una sola indicación en el panel según el estado, botón principal destacado), UX-06 ✔ (sonido por acción), UX-10 ✔ (`CREDITOS.md`), PRU-01/02: `rp_test` con 4 pruebas (recurso, exports, mochila de servicio, casillero en BD con cascada); **el cliente lo debe probar Fabián en juego**.
- **Pendiente**:
  - Coordenadas del hospital aproximadas (All Saints): ajustar con `/medmover` o el editor ALT.
  - `takeKit` retira hasta los botiquines entregados aunque el médico tuviera propios encima (`shortcut:` en `s_core.lua`); con «Guardar todo» los propios quedan en el casillero.
  - Ambulancias temporales por jugador como en bomberos; el garaje de facción con fondos es F0.3 (#105).
- **Probar en juego**: `/crearfaccion medicos LSMD Servicios medicos`, entrar en la facción; vestuario (E): pasar objetos a mano, guardar y sacar la mochila con contenido, «Guardar todo y entrar de servicio» (uniforme + mochila médica con 3 botiquines), intentar `/tirarmochila` de servicio, intentar entrar con un arma encima, garaje (E) sacar y guardar ambulancia, «Sacar todo y salir de servicio» con el inventario casi lleno (aviso de lo que queda), desconectar de servicio y volver (sin mochila médica, cosas en el casillero), `restart rp_medics` de servicio. `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-28, commit 7ce33c0)

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
