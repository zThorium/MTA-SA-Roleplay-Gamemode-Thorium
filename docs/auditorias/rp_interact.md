# Auditoría de rp_interact

## 2026-11-27 · crear
- **Foco**: menú de interacción con otras personas (M + clic derecho), con opciones para el jugador sin permisos y bloques por permiso.
- **Nota**: — → 100 (98 antes de crear este registro).
- **Cambios**:
  - Recurso nuevo `rp_interact`: con el cursor de **M** (`rp_vehicles`), al pasar sobre alguien sale su nombre con el clic derecho dibujado (UX-01); el clic derecho pide el menú al servidor, que decide las opciones según quién eres, la distancia y el estado del otro, y explica las bloqueadas con 🔒 (UX-02).
  - **Sin permisos**: saludar; dar la mano, saludo de pandilla y besar (los dos con animación de SA, el invitado se coloca enfrente); mostrar DNI y licencia (reutiliza `/mostrardni` y `/mostrarlicencia`); dar dinero (tope $5000, cooldown, log desde $1000); dar un objeto (sin equipo policial); reanimar con botiquín (RCP 8 s); invitar a tu vehículo; cachear; reportar (abre F1 con la persona elegida).
  - **Propuestas con permiso del otro**: tarjeta dx abajo con **E** / **Retroceso** dibujadas y cuenta atrás de 15 s; todo se revalida al aceptar (distancia, objeto, asiento, estado).
  - **Por permiso**: policía de servicio (acciones de `rp_police` con los exports nuevos `getPlayerActions` / `doPlayerAction`, misma validación que el menú K), médicos y bomberos de servicio (reanimar sin botiquín), invitar a la facción (`invite`, vía `/finvitar`) y bloque admin (vía los comandos de `rp_admin`, que validan nivel e IAM y dejan auditoría).
  - UI CEF con el lenguaje de `rp_npcrel` (Rubik, tarjeta oscura con barra de color por grupo, sonidos Kenney por evento, monedas al dar dinero), tutorial de 3 pasos con foco la primera vez y consejo dibujado (M + clic derecho) la primera vez que estás junto a alguien (UX-03, UX-05, UX-06).
  - Cambios en otros recursos: `rp_police` (exports de acciones sobre personas; el menú K usa la misma función), `rp_vehicles` (export de cliente `isCursorModeActive`), `rp_help` (export de cliente `openReport` y teclas M y E/Retroceso en la ayuda).
  - Arreglos tras la primera prueba en juego: las tarjetas dx se veían como un rectángulo vacío (faltaba `postGUI` en `DX.roundRect`/`DX.poly`, `dxDrawPrimitive` fallaba) y el panel del cacheo no se podía cerrar (seguía marcado como «cerrando» tras el menú). Nuevo: quitar objetos y efectivo en el cacheo a alguien reducido (delito `person_rob` añadido a `rp_wanted`). DNI, licencia, invitar a la facción y el bloque admin daban `Access denied @ executeCommandHandler`: grupo ACL `RPCommandRelay` solo con ese derecho para `rp_interact`, y aviso al jugador y en consola si falta.
  - Pruebas `interact_acciones_con_manejador` e `interact_exports_policia` en `rp_test`.
- **Reglas manuales revisadas**: SEG-02 ✔ (el cliente solo manda id de acción y objetivo; el servidor rehace permisos, distancia, dinero e inventario en cada acción y al aceptar), SEG-03 ✔ (cantidades enteras acotadas, ids de objeto contra el catálogo, JSON del CEF limitado a 400 caracteres), SEG-04 ✔ (cooldown por jugador, aparte el del dinero, una propuesta pendiente por persona), CIC-03 ✔ (abatido, muerto, lejos o cambio de personaje cierra el menú; la RCP se corta y descongela al salir, al morir, al quedar abatido o al parar el recurso), CLI-03 ✔ (texturas y fuentes creadas una vez; el modo cursor se consulta cada 100 ms, no por frame), UX-10 ✔ (assets de `assets/` con `CREDITOS.md`), UX-08 ✔ (la acción se hace sobre la persona donde haces clic).
- **Pendiente**: la tecla K de `rp_police` sigue funcionando por compatibilidad (ahora es redundante para personas); `rp_inventory` sigue permitiendo dar objetos desde el inventario sin permiso del otro y con equipo policial. Las invitaciones con **Y** de `rp_missions` y `rp_races` también abren el chat de susurro (`rp_chat`); por eso aquí se usa E / Retroceso.
- **Probar en juego**: M + pasar el ratón sobre alguien (nombre y ratón dibujados); clic derecho abre el menú con el tutorial la primera vez; dar dinero y un objeto (el otro acepta con E y rechaza con Retroceso; dejar que caduque); dar la mano, saludo de pandilla y besar (posición y animación de los dos); mostrar DNI y licencia; reanimar a un abatido con botiquín y alejarse a mitad; cachear a alguien esposado y a alguien que acepta; invitar al coche; Reportar abre F1 con la persona elegida; como policía de servicio esposar y escoltar desde el menú M; como admin `/check`, `/goto`, `/get` desde el menú; `restart rp_interact` con el menú abierto y durante una RCP; `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-27, commit 48927bc)

**Nota: 98/100** · OK 29 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_interact.md |
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
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| N/A | I | BD-05 | Espera a la BD al arrancar | no usa la BD |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>
