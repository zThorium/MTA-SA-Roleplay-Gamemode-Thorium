# Auditoría de rp_nametags

## 2026-11-26 · mejorar · foco: nametags y /ame con la línea visual de rp_notify
- **Motivo**: lo que se ve sobre la cabeza (nombre, vida, /ame, burbujas de `rp_chat`) debe tener un solo estilo.
- **Nota**: 91 → 100.
- **Cambios**:
  - Nombre en Kenney Future Narrow con sombra y el **ID en una pastilla** oscura.
  - Barra de vida redondeada que pasa de verde a ámbar y rojo, con **rastro de daño** (lo perdido queda en blanco un momento y se vacía). Chaleco en barra fina azul grisácea.
  - Los nametags **aparecen y desaparecen con fundido** al entrar o salir de la vista, en vez de saltar.
  - `/ame`: pastilla oscura con punto rosa (el color de `/me`) que salta al aparecer, con línea de luz que se abre desde el centro (antes, barra roja plana).
  - La lista de jugadores cercanos se refresca cada 500 ms y los anchos de nombre se cachean, en vez de calcularlos en cada frame (CLI-02).
  - El uso de `/ame` sale como aviso de `rp_notify` (INT-04). `cache="false"` en el cliente (EST-02).
- **Reglas manuales revisadas**: SEG-02 ✔ (sin cambios en el servidor salvo el aviso), CIC-06 ✔, CLI-03 ✔. PRU-02: pendiente de probar en juego.
- **Pendiente**: —
- **Probar en juego** (con 2 jugadores): nombre e ID, recibir daño (rastro blanco y cambio de color), chaleco, ponerse detrás de una pared (fundido), `/ame` propio y ajeno, cambiar de nombre o de ID.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit 6318518)

**Nota: 100/100** · OK 27 · FALLA B 0 · FALLA I 0 · AVISO 0

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
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
| N/A | B | SEG-01 | Handlers de eventos remotos usan client | sin eventos remotos |
| N/A | I | BD-05 | Espera a la BD al arrancar | no usa la BD |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | no usa personajes |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>
