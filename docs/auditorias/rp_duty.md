# Auditoría de rp_duty

## 2026-11-28 · crear (#104, servicio genérico de facción)
- **Motivo**: issue #104 [F0.2]. Médicos, gobierno, mecánicos, noticias, taxis... necesitan servicio (uniforme, equipo y sueldo solo de servicio) sin repetir el código de `rp_police` y `rp_firefighters`. Tipos elegidos por Fabián: servicios y empresas (`gobierno`, `medicos`, `mecanicos`, `noticias`, `transporte`, `logistica`, `seguros`, `seguridad`, `concesionaria`); `banda`, `mafia`, `empresa` y `otra` siguen sin servicio.
- **Nota**: 98/100 (OK 31, FALLA 0, AVISO 1: DOC-04, resuelto con este archivo).
- **Cambios**:
  - Recurso nuevo `rp_duty`; `FACTION_TYPES` de `rp_factions` apunta esos tipos a `duty = "rp_duty"`, `dutyData = "rp:factionDuty"` (así `isPlayerOnDuty`, nametags y sueldo de servicio funcionan sin tocar `rp_factions`).
  - Tablas `faction_lockers`, `faction_loadouts` y `faction_duty_items` (al final de `schema.lua`; validadas en la BD local).
  - Vestuario por facción colocado por admins (`/makelocker`, alias `/crearvestuario`), con `rp_markers` (`registerMarker` + `ownerSaves`, guardado en `rp:markers:moved`) y tipo `locker` en `WORLD_TYPES` de `rp_admin`.
  - Panel CEF: pestaña Servicio (elegir uniforme según nivel de rol, entrar, cambiar o salir) y pestaña Uniformes para el líder o quien tenga `manage_ranks`.
  - Ayuda F1, catálogo del panel de admin, `RECURSOS.md`, `CLAUDE.md`, `API.md` y `REGISTROS.md`.
- **Reglas manuales revisadas**:
  - SEG-02 ✔: el cliente solo manda el id del vestuario y del uniforme; el servidor comprueba cercanía (colshape + distancia, interior y dimensión), facción del vestuario, tipo con `rp_duty`, nivel de rol del uniforme y permiso de gestión. Los uniformes se validan (nombre, nivel 1-99, skin existente, ítems del catálogo, cantidades, sin repetidos, máximo 6).
  - SEG-04 ✔: cooldown de 800 ms por acción.
  - BD-06 ✔: todo con `dbQuery`/`dbExec` parametrizado; cada `UPDATE`/`DELETE` de uniformes lleva `AND faction_id = ?`.
  - PRU-02 ✔: `rp_test/server/s_tests_duty.lua` (exports, tipos con servicio, un registro de equipo por personaje).
  - CIC-03 ✔: sale de servicio y devuelve el equipo al salir, cambiar de personaje, dejar la facción (revisión cada 5 s) y al parar el recurso; reaplica el uniforme al reaparecer. El equipo pendiente de una caída se recoge al entrar o al arrancar el recurso con el jugador dentro.
  - INT-09: N/A, entrar y salir de servicio es pasivo y se farmea gratis; los logros irán en los sistemas de cada facción (atenciones médicas, reparaciones...).
  - UX-01 ✔: E dibujada (Kenney) en el aviso junto al vestuario.
  - UX-02 ✔: un marcador por vestuario y un solo aviso.
  - UX-04/05 ✔: guía «1 Elige un uniforme → 2 Entrar de servicio» la primera vez que entras (se oculta de servicio); estado vacío que explica quién crea los uniformes.
  - UX-06 ✔: sonidos de abrir, clic, entrar, salir, error y cerrar (paleta estándar).
  - UX-10 ✔: `CREDITOS.md`; assets copiados de `assets/`.
- **Pendiente** [A]:
  - Si alguien regala el equipo de servicio antes de salir, no se recupera: se anota en el registro de la facción cuántas unidades faltaron.
  - El rol médico (`rp_rol_medico`, de otro compañero) puede pasar `medicos` a su propio recurso cambiando `duty` en `FACTION_TYPES`.

<details><summary>Informe del script</summary>

### Auditoría automática (2026-11-28, commit a3a9fdc)

**Nota: 98/100** · OK 31 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_duty.md |
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
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
</details>

## 2026-11-28 · mejorar (#105, vehículos de facción y garaje)
- **Motivo**: issue #105 [F0.3]: ambulancias, grúas, taxis, camiones y furgones de noticias propiedad de la facción.
- **Cambios**:
  - `server/s_garage.lua`: garajes por facción (`/makefgarage`, tabla `faction_garages`, `rp_markers` movible con ALT, tipo `fgarage` en `WORLD_TYPES`) y vehículos de facción (`faction_vehicles`: modelo, color, nivel mínimo, matrícula, combustible, daño, precio).
  - Sacar (de servicio y con nivel), guardar al volante con E, bloqueo de conductor en `onVehicleStartEnter`, vuelta sola al garaje tras 15 min abandonado o al explotar, combustible (`rp_vehicles:get/setVehicleFuel`) y daño guardados.
  - Compra con los fondos de la facción: exports nuevos de `rp_factions` `getFactionFunds`, `takeFactionFunds` (comprueba y descuenta en memoria y la BD lleva `AND bank >= ?`) y `addFactionFunds`; si el `INSERT` falla se devuelve el dinero. Venta con `DELETE ... AND faction_id = ?` y reembolso solo si borró una fila (no se paga dos veces).
  - Vista de garaje en el mismo panel CEF; ayuda F1, catálogo de admin, `RECURSOS.md`, `API.md`, `REGISTROS.md`.
- **Reglas manuales revisadas**:
  - SEG-02 ✔: el cliente manda ids; el servidor comprueba garaje de su facción a menos de 6 m, servicio, nivel, permiso de gestión, catálogo del tipo y fondos.
  - BD-06 ✔: cobro atómico y venta idempotente (arriba).
  - PRU-02 ✔: `duty_fondos_de_faccion` (cobro e ingreso exactos; sin saldo no cobra) y `duty_garaje_exports`.
  - CIC-03 ✔: al parar el recurso se guardan y quitan los vehículos fuera; timer de abandonados cancelado.
  - INT-09: N/A (sacar un vehículo no es lograble; los logros irán en el trabajo de cada facción).
  - UX-01/04 ✔: E dibujada a pie y al volante («Guardar el vehículo en el garaje»); guía de 3 pasos en el panel; venta con doble clic de confirmación.
- **Pendiente** [A]: el megáfono de `rp_chat` (#107) podría aceptar también `rp:factionVehicle`; el modelo de cada vehículo comprado no se puede cambiar de color desde el panel.
