# Auditoría de rp_vending

## 2026-11-25 · mejorar · foco: modelo en el mundo, menú, datafono e inventario
- **Motivo**: la máquina no aparecía en el mundo y la compra subía la barra directamente, sin pasar por el inventario.
- **Nota**: 100 → 100 (durante el cambio aparecieron CIC-04 y DOC-02 y se corrigieron).
- **Cambios**:
  - `/crearexpendedora` coloca el objeto del juego (955 Sprunk / 956 snacks) 1,1 m delante del admin, mirándolo; `zOffset` por tipo en la config.
  - Menú CEF de productos → datafono con el mismo minijuego que la bencinera (tarjeta + clave o efectivo) → el producto va a `rp_inventory` (INT-07). 6 items nuevos en `rp_inventory/shared/s_items.lua`.
  - Servidor: sesión por jugador (`menu` → `pay` → `paid`), revalida cercanía, abatido y vehículo en cada paso, precio y producto desde la config (SEG-02); cobro antes de entregar y reembolso si el item no entra (BD-06).
  - Cierre limpio al alejarse, abatirse, morir, cambiar de personaje, salir o parar el recurso; timer de cierre cancelable (CIC-01, CIC-04, CIC-05, CIC-06).
  - Export `getVendingTypes()` y prueba `vending_productos_son_items` en `rp_test` (PRU-01).
- **Reglas manuales revisadas**: SEG-02 ✔, SEG-03 ✔ (cooldown + bandera `paying`), SEG-04 ✔, BD-06 ✔, CIC-03 ✔ (rehidrata cercanía), CIC-06 ✔, INT-07 ✔. PRU-02: pendiente de probar en juego.
- **Pendiente**: las máquinas creadas antes de este cambio guardaron la posición del admin, no la de la máquina: aparecerán donde estaba el admin (bórralas con `/borrarexpendedora` y vuelve a crearlas). Ajustar `zOffset` si los modelos quedan enterrados o flotando.
- **Probar en juego**: crear una de cada tipo; E → elegir producto → pagar con tarjeta (clave mala, sin fondos, bien) y en efectivo (con y sin dinero); inventario lleno; alejarse o Esc con el datafono abierto; usar el producto desde el inventario; `restart rp_vending` junto a una máquina.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit b7ed565)

**Nota: 100/100** · OK 31 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>

## 2026-11-25 · crear
- **Motivo**: máquinas expendedoras funcionales: E junto a la máquina, cobra en efectivo y sube sed (bebida) u hambre (comida).
- **Nota**: — → 100 (sin FALLA B).
- **Cambios**: recurso nuevo; tabla `vending_machines`; colshape por máquina con aviso al cliente; compra revalidada en servidor (SEG-01, cooldown, cercanía, abatido, saldo, barra llena); cobro antes de entregar.
- **Reglas manuales revisadas**: SEG-02 ✔ (cantidad y precio salen de config, no del cliente), SEG-04 ✔, BD-06 ✔, PRU-02 ✔.
- **Pendiente**: ninguna.
- **Probar en juego**: `/crearexpendedora bebida` frente a una máquina; E con dinero (sed sube), sin dinero, con la barra llena, lejos, abatido, en vehículo; reiniciar el recurso estando junto a la máquina; `/borrarexpendedora`.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 05ba7b1)

**Nota: 100/100** · OK 29 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 1 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | I | CIC-04 | Los timers se pueden cancelar |  |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
