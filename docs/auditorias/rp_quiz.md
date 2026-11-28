# Auditoría de rp_quiz

## 2026-11-28 · crear (#111, cuestionario de rol y tutorial jugable)
- **Motivo**: issue #111 [O1.1]: filtrar a quien no quiere rolear y enseñar lo básico sin que nadie lo explique.
- **Cambios**:
  - Recurso nuevo `rp_quiz`: cuestionario CEF (estilo `rp_login`) con 8 preguntas en `server/s_config.lua` (solo servidor), opciones barajadas por sesión, 7 aciertos para aprobar, repaso de las falladas con la respuesta y el motivo, y espera de 30 s para repetir.
  - `accounts.quiz_passed_at`; `rp_characters` no crea personaje sin aprobar (dependencia opcional: si `rp_quiz` está parado no bloquea). Las cuentas anteriores al 2026-11-29 que ya tenían personaje quedan exentas.
  - Tutorial jugable con `characters.tutorial_done` (los personajes anteriores quedan exentos): 6 pasos con tecla dibujada que se cumplen al hacerlos; `/saltartutorial`.
  - Logro «Primer día» (`tutorial_done`, único, bronce) en `rp_achievements`; ayuda F1; `RECURSOS.md`, `CLAUDE.md`, `REGISTROS.md`.
- **Reglas manuales revisadas**:
  - SEG-02 ✔: el cliente solo manda índices; el servidor corrige con el orden barajado de esa sesión, que se borra al corregir (no se puede reenviar), y respeta la espera tras suspender.
  - BD-06 ✔: aprobado con `WHERE quiz_passed_at IS NULL`; tutorial con `WHERE tutorial_done = 0` y logro solo si afectó una fila (no se farmea).
  - PRU-02 ✔: `quiz_recurso_y_exports`, `quiz_aprobado_se_guarda_una_vez`.
  - CIC-03 ✔: al cambiar de personaje se corta el tutorial; al cerrar el cuestionario se devuelve el estado de entrada de texto de la pantalla de personajes.
  - INT-09 ✔: «Primer día», una vez por personaje y solo terminando el tutorial (saltarlo no lo da).
  - UX-01/03 ✔: teclas dibujadas en cada paso, un paso a la vez, sonido al cumplirlo; cuestionario con progreso y teclas 1-4/Enter.
- **Pendiente** [A]: el tutorial no lleva aún a la agencia de empleo con el GPS (solo lo sugiere); prueba del jugador nuevo con alguien que no conozca el servidor.

<details><summary>Informe del script</summary>

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
