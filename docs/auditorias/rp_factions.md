# Auditoría de rp_factions

## 2026-11-26 · mejorar
- **Foco**: que `rp_factions` sea el único punto por el que los demás recursos saben si un personaje pertenece a una facción, su rol y si está de servicio.
- **Nota**: 89/100 → 96/100
- **Cambios**:
  - INT (API central): exports `isPlayerInFaction`, `isPlayerOnDuty`, `getPlayerFactionId`, `getPlayerFactionType`, `isPlayerFactionLeader`, `getPlayerFactionInfo`, `getFactionInfo`, `getFactions`, `getFactionPlayers`, `getCharacterFaction` (servidor) e `isPlayerInFaction`, `getPlayerFactionId`, `getPlayerFactionType`, `getPlayerFactionInfo` (cliente, `client/c_api.lua`). Evento `rp:faction:onMembershipChange`. Los exports anteriores no cambian.
  - Servicio centralizado: `FACTION_TYPES[tipo].duty` dice qué recurso lleva el servicio (`rp_police`, `rp_firefighters`); `isPlayerOnDuty` y `collectPaydaySalary` le preguntan a ese recurso en vez de llamadas escritas a mano por tipo.
  - Consumidores migrados (pertenencia por **tipo**, no por el id 1 fijo): `rp_police` (`isOfficer`), `rp_wanted` (`isWantedPolice`), `rp_vehicles` (`isPolice`, que leía el element data), `rp_driving`, `rp_agency`, `rp_firefighters`, `rp_scoreboard` (cliente). Quitado `POLICE_FACTION_ID` de `rp_wanted`, `rp_vehicles` y `rp_driving`; `rp_police` conserva `FACTION_ID = 1` solo para sembrar los roles y el registro de la LSPD.
  - PRU-01: `rp_test/server/s_tests_factions.lua` (exports, facción 1 encontrada por tipo, sin falsos positivos).
  - DOC: regla en `docs/CONVENCIONES.md`, tabla en `crear-recurso/referencia/API.md`, fila de `RECURSOS.md`.
- **Reglas manuales revisadas**: SEG-02 ✔ (la API solo lee memoria del servidor; el cliente solo muestra), INT-03 ✔ (evento `rp:`), compatibilidad ✔ (ningún export renombrado; la facción 1 del esquema es de tipo `policia`, así que nadie gana ni pierde acceso hoy).
- **Pendiente**: `getCharacterFaction` solo responde para personajes conectados (los demás exigirían consulta asíncrona).
- **Probar en juego**: policía (facción 1): vestuario, `/consultardni`, `/retirarlicencia`, cepo y multa de `rp_vehicles`, sin estrellas de servicio; bombero de servicio cobra sueldo en el payday y fuera de servicio no; Tab muestra la facción; expulsar a alguien de la facción y comprobar que pierde el acceso al momento.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit cf1fb3c)

**Nota: 98/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_factions.md |
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
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | I | CIC-04 | Los timers se pueden cancelar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>

## 2026-11-28 · mejorar (#102, tipos de facción nuevos)
- **Qué**: `FACTION_TYPES` registra `mecanicos`, `noticias`, `transporte`, `logistica`, `seguros`, `seguridad`, `concesionaria` y `mafia` (nombre, color y `state = false`; sin `duty` hasta que su recurso lleve el servicio). Export nuevo `getFactionTypes()`.
- **Sin cambios necesarios**: `/crearfaccion`, el panel F3, `rp_scoreboard` y `rp_nametags` ya leen el tipo y el color desde `FACTION_TYPES` / la facción.
- **Prueba**: `rp_test` › `fac_tipos_registrados` (todos los tipos, color `#rrggbb`, clave ≤ 16 caracteres, `duty` con `dutyData`).
- **Probar en juego**: `/crearfaccion` sin argumentos lista los 15 tipos; `/crearfaccion mecanicos MEC Taller Prueba` crea la facción con el color del tipo y F3 muestra «Mecanicos».
- **INT-09**: N/A, catálogo de configuración sin hecho lograble.

## 2026-11-28 · mejorar (#106, facturas a clientes y comisiones)
- **Qué**: permiso nuevo `bill` (bit 131072), `INVOICES` en la config, `server/s_invoices.lua` (`/facturar`, export `bill`, pago, caducidad y datos de la pestaña), `client/c_invoice.lua` (ventana dx del cliente con teclas 1/2/Retroceso dibujadas, sonidos Kenney), comisión por rol (`faction_ranks.commission`, editable en Roles), tabla `faction_invoices` y pestaña **Facturas** en F3. El pago usa `addFactionFunds` (#105).
- **Reglas manuales revisadas**:
  - SEG-02 ✔: el cliente solo responde «cash», «bank» o rechaza; el servidor exige factura pendiente suya y sin caducar, el empleado a 5 m y el saldo. Monto entero 1-100.000, concepto limpio 3-60, una pendiente por cliente.
  - SEG-04 ✔: 3 s entre facturas del mismo empleado; la acción de F3 lleva el cooldown general.
  - BD-06 ✔: banco con `UPDATE ... AND bank_money >= ?` y entrega solo con fila afectada; efectivo con `getPlayerMoney` + `takePlayerMoney` + `saveCharacter`; la factura se cierra con `WHERE status = 'pending'` (no se cobra dos veces).
  - PRU-02 ✔: `fac_facturas_export_y_permiso` y `fac_facturas_cobro_atomico` (cobra el monto exacto; sin saldo no mueve nada).
  - CIC-03 ✔: al salir el cliente o parar el recurso, las pendientes pasan a `expired`.
  - INT-09: N/A por ahora: facturar entre amigos se farmea gratis; los logros irán en cada trabajo (reparaciones, atenciones...).
  - UX-01/06 ✔: teclas dibujadas en la ventana, barra de tiempo que se pone roja al final, sonido al llegar, pagar y rechazar.
- **Pendiente** [A]: registrar los pagos en `rp_logs` cuando se fusione #109.
