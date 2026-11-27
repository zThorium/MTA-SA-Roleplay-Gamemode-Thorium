# Auditoría de rp_achievements

## 2026-11-27 · crear (logros con bronce, plata, oro y platino, puntos e hitos)
- **Motivo**: Fabián pidió un sistema de logros que alimenten todos los recursos. Cada logro sube de bronce a plata, oro y platino, y al juntar logros se ganan recompensas. Decidió: panel CEF propio más app del teléfono, puntos con hitos reclamables, 4 medallas, todo por personaje y con el sistema de UI de la GM (GFX y SFX ya existentes).
- **Nota**: — → 100 (OK 31; el único aviso era este registro).
- **Cambios**:
  - Recurso nuevo con unos 45 logros en 8 categorías, 42 estadísticas y 9 hitos (`shared/s_achievements.lua`, `shared/s_config.lua`).
  - Integración desacoplada: `triggerEvent("rp:achievements:progress", jugador, stat, n)` (evento solo de servidor). Se añadió una línea en 22 recursos: jobs, pizzería, detector, autoescuela, carreras, tren, bicis, Vroom, búsqueda, cárcel, robo, policía, bomberos, gimnasio, campo de tiro, niveles, payday, concesionario, propiedades, ropa, restaurantes, mapa, misiones, Tinder y pool. También escucha los eventos que ya existían (`rp:jobs:onShiftEnd`, `rp:jobs:onMarketSale`, `rp:shop:onBought`, `rp:onPlayerDowned`).
  - Al entrar, lee lo que ya se tenía: nivel, % del mapa, cuerpo, licencia y saldo del banco (este también cada minuto, con una sola consulta).
  - Tablas `character_achievement_stats`, `character_achievements` y `character_achievement_milestones` (al final de `schema.lua`).
  - Reclamo atómico de hitos con `INSERT IGNORE`: solo se paga si se inserta la fila. Dinero con `bank_transactions` tipo `reward`, XP con `rp_levels` e items comprobando `canCarry` antes.
  - Cliente con el sistema de UI de la GM: `c_dx.lua` idéntico a `rp_notify`, fuentes de `rp_notify`, texturas propias (glow, sparkle, ring) y la paleta de sonidos. Aviso de medalla con la tarjeta de `rp_levels` y anuncio central (`popup` tipo `level`) al alcanzar un hito.
  - Panel CEF `/logros` y app «Logros» de `rp_phone`, con barra de hitos, pestañas, «Casi lo tienes» y entrenador la primera vez (UX-04).
  - Cosméticos de `rp_scoreboard` (`requires`): iconos 🏅 🏆 🐉 y efecto «Oro». El servidor los valida y el editor `/perfil` les pone candado.
  - Comandos de admin `/verlogros`, `/darlogro`, `/statlogro` y `/resetlogros` (con confirmación), en `admin_log` y en el catálogo de `rp_adminpanel`.
  - Pruebas en `rp_test` (`s_tests_achievements.lua`): catálogo sin errores, tablas, upsert y que un hito no se cobre dos veces.
- **Reglas manuales revisadas**:
  - SEG-02 ✔: el progreso solo entra por un evento de servidor (`addEvent(..., false)`) o por export. El cliente solo pide el panel y reclamar, y el servidor revalida puntos, reclamo e inventario.
  - SEG-04 ✔: cooldown de panel (1 s) y de reclamo (1,5 s), más un bloqueo mientras dura la consulta.
  - BD-06 ✔: el reclamo es atómico por la PK.
  - PRU-02 ✔: pruebas escritas, aún sin ejecutar en el servidor.
  - UX-10 ✔: todo sale de `assets/` y está en `CREDITOS.md`.
  - UX-01: no hay tecla nueva (comando y app).
  - UX-04, UX-06 y UX-07 ✔.
- **Antiabuso**:
  - Topes por aviso (`maxPerCall`).
  - El tren solo cuenta si bajas en otra estación.
  - El pool solo cuenta partidas hasta la 8 contra otro personaje.
  - Las carreras ganadas necesitan otro corredor.
  - El campo de tiro pide 20 disparos o más.
  - El ahorro mira el saldo y no los depósitos.
  - Escapar de la policía no cuenta al morir ni al quedar abatido.
- **Probar en juego**:
  - `/probarlogro` (4 medallas).
  - Terminar un turno o entregar una pizza y ver el aviso.
  - `/darlogro` hasta pasar un hito y reclamarlo: llega dinero y XP, y el segundo clic no paga.
  - Inventario lleno con el hito 3.
  - Cambiar de personaje.
  - App del teléfono.
  - Candados de `/perfil`.
  - `restart rp_achievements` con gente dentro.
  - `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-27, commit adfe9fd)

**Nota: 98/100** · OK 31 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_achievements.md |
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
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 1 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
