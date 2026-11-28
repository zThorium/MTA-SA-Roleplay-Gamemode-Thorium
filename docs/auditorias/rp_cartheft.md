# Auditoría de rp_cartheft

## 2026-11-28 · crear (robo de vehículos con ganzúa, alarma, puente y bocina)
- **Motivo**: pedido de Fabián: robar vehículos cerrados con una ganzúa comprada en las tiendas, minijuego para forzar la cerradura, alarma al abrir, otro minijuego para encender, una estrella si un policía te sorprende y dos bocinazos para apagar la alarma.
- **Nota**: 98/100 (OK 29, FALLA 0, AVISO 1: INT-06, ver abajo).
- **Cambios**:
  - Recurso nuevo `rp_cartheft` sin BD propia: sesiones en memoria (`pick` → `open` → `wire` → `horn`), un ladrón por vehículo.
  - Solo vehículos con dueño de `rp_vehicles` (los únicos que se cierran) y de tipo auto, quad o monster truck.
  - Item `lockpick` en `rp_inventory` (uso por evento) y a $60 en `DEFAULT_CATALOG` de `rp_shops`, con `INSERT IGNORE` para las tiendas ya creadas.
  - `rp_vehicles`: exports `setVehicleLockState` (ya existía como global) y `setVehicleHotwired`, y evento cancelable `rp:veh:onEngineNoKey` al pulsar J sin llave. El puente se borra cuando el dueño cierra con llave.
  - Alarma: elementData `rp:carAlarm` en el vehículo; cada cliente pone sirena 3D (`sounds/alarma_auto.wav`, sintetizada con `tools/gen_sounds.ps1`) y luces intermitentes. Se apaga con dos bocinazos, al agotarse (90 s) o al parar el recurso.
  - Policía testigo: el servidor mira policías jugadores (`rp_wanted:isWantedPolice`) en 25 m (45 m con la alarma); los policías IA y patrullas solo existen en el cliente, que mide línea de visión (patrón de `rp_dealers`) y avisa con `rp:cartheft:copSeen`. Una vez por robo: `reportCrime(p, "car_steal", ..., "police")` = 1 estrella.
  - Logro `ganzua` / estadística `cars_stolen` en `rp_achievements`, ayuda F1, `RECURSOS.md`, `CLAUDE.md`, `REGISTROS.md` y `API.md`.
- **Reglas manuales revisadas**:
  - SEG-02 ✔: el cliente solo informa «abierto» o «fallado»; el servidor exige etapa correcta, tiempo mínimo (`MIN_MS`), cercanía, ganzúa en el inventario, vehículo aún cerrado y ser el conductor. El fallo rompe la ganzúa en el servidor.
  - SEG-04 ✔: cooldown de 1,5 s para abrir el minijuego y un ladrón por vehículo.
  - BD-06 ✔: sin consultas propias; la cerradura la guarda `rp_vehicles`.
  - PRU-02 ✔: `rp_test/server/s_tests_cartheft.lua` (catálogo, ganzúa en todas las tiendas, exports, exports nuevos de `rp_vehicles` con vehículos sin dueño). Pasa en Docker.
  - CIC-03 ✔: la sesión termina al salir, cambiar de personaje, quedar abatido, morir o destruirse el vehículo; `onResourceStop` apaga las alarmas.
  - INT-06 (aviso): `horn` también lo usa `rp_hookers`, pero cada uno solo actúa en su propio estado (sesión de robo en fase `horn` / prostituta cerca). Sin choque real.
  - INT-09 ✔: logro «Manos de seda» (1/10/30/100 robos completos); solo cuentan autos de otro personaje y un mismo auto una vez por hora (anti-farmeo con un amigo).
  - UX-01 ✔: E sobre la puerta, J y bocina (tecla real con `getBoundKeys`) dibujadas; Espacio, clic y Esc en el CEF.
  - UX-02 ✔: un solo aviso a la vez según la etapa.
  - UX-03/05 ✔: entrenador la primera vez de cada minijuego (paso N de M, foco sobre la barra o el cable que toca).
  - UX-06 ✔: sonido por evento (pin, raspón, cable, calambre, chispa, éxito, fallo) y destello verde/rojo.
  - UX-08 ✔: el puente se acepta al pulsar J, donde el jugador intenta encender.
  - UX-10 ✔: `CREDITOS.md`.
- **Pendiente** [A]:
  - Afinar en juego la posición de la puerta (`doorPosition`), la animación `BOMBER/BOM_Plant_Loop` y el volumen de la sirena.
  - Línea de visión de policías jugadores: el servidor solo mide distancia (MTA no tiene `isLineOfSightClear` en el servidor).
- **Probar en juego**:
  - Comprar una ganzúa en una 24/7; E junto a la puerta de un auto cerrado de otro personaje; fallar 3 veces (rotura 50 %).
  - Abrir: alarma y luces vistas por otro jugador; subir, J, puente; dos bocinazos con la tecla de bocina.
  - Bajarse a mitad del puente, volver a subir y seguir; Esc en cada minijuego.
  - Con un policía de servicio a menos de 25 m: una estrella. Sin policía: ninguna.
  - El dueño vuelve a cerrar con L: el puente deja de servir.
  - `restart rp_cartheft` con la alarma sonando.

<details><summary>Informe del auditor</summary>

### Auditoría automática (2026-11-28, commit e11a629)

**Nota: 98/100** · OK 29 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | INT-06 | Teclas sin choques con otros recursos |  horn: rp_hookers ; |
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
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| N/A | I | BD-05 | Espera a la BD al arrancar | no usa la BD |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>
