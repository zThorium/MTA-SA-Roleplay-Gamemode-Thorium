# Auditoría de rp_logs

## 2026-11-28 · crear
- **Motivo**: issue #109 ([O0.1] de `docs/AUDITORIA_OWLGAMING.md`, Fase 0 "antes de abrir"): sin un registro de economía no se puede investigar un dupeo ni un abuso. El efectivo se mueve con `givePlayerMoney`/`takePlayerMoney` en ~30 recursos y `bank_money` con SQL directo en 14; solo existían `admin_log` (acciones de admin) y `bank_transactions` (solo banco). Lo necesita también #106 (F0.4, facturas).
- **Nota**: — → 100.
- **Cambios**: recurso nuevo, solo servidor. Tabla `economy_log` al final de `schema.lua` (BD-04), sin FK a `characters` para que el registro sobreviva al borrado o CK; índices por actor, objetivo, tipo y fecha; purga a los 90 días. Export `log(tipo, actor, objetivo, cantidad, detalle)` con cola en memoria y `INSERT` multi-fila cada 5 s o 50 filas y al parar (BD-02: nunca bloquea; BD-03: solo se concatenan marcadores `?`, marcado `estandar:sql-seguro`). Tipos cerrados en `LOGS.TYPES`. Red de seguridad `cash_jump` (saltos de efectivo ≥ $50.000 en 30 s). Enganchado en `rp_admin` (`/givemoney`, `/apagar`, `/setmoney`), `rp_bank` (depósito, retiro, transferencia, `/dardinero`), `rp_factions` (`/darfondos`), `rp_interact` (dar dinero, dar ítem, robos del cacheo), `rp_inventory` (soltar, recoger, dar, soltar mochila), `rp_properties` (comprar y vender casa), `rp_dealership` (comprar), `rp_vehicles` (`/darllave`, `/allave`) y `rp_payday`. `rp_adminpanel`: permiso `logs.economy` (rango 2), pestaña **Economía** y `/logs` en el catálogo.
- **Reglas manuales revisadas**: SEG-02 N/A (sin eventos remotos propios; la pestaña del panel pasa por `rp:adminpanel:req`, que revalida con `hasPermission`) · SEG-04 ✔ (búsqueda del panel acotada a 32 caracteres, sin `%` ni `\`, tipo validado contra la lista; `/logs` con cooldown de 2 s) · BD-06 ✔ (las filas se escriben como mucho 5 s después de la acción y al parar el recurso) · PRU-02 ✔ (`s_tests_logs.lua`) · INT-04: los `outputChatBox` son el listado de `/logs` y su uso (permitido para listados) · INT-09: N/A, infraestructura de moderación (no es algo que haga el jugador) · UX-*: N/A (sin interfaz para jugadores).
- **Pendiente**: enganchar el resto de sitios que pagan o cobran (trabajos, tiendas, restaurantes, robos de tienda, misiones, multas, tuning, bencina...) y los `UPDATE bank_money` restantes; mejor con un helper común de dinero que registre solo (issue de seguimiento). `/vendercasa` no es atómico (se comprueba el dueño en memoria antes de un `UPDATE` sin `AND owner_id = ?`): ahora queda registrado, pero conviene arreglarlo con `arreglar-recurso rp_properties`.
- **Probar en juego**: con un admin de rango 2: dar dinero con M a otro jugador, soltar y recoger un ítem, dar un ítem desde el inventario, `/givemoney`, depositar y transferir en un cajero, comprar una casa → en `/adminpanel` › Economía aparecen con nombres, ids, cantidades y recurso; clic en un nombre filtra sus movimientos; el desplegable filtra por tipo; `/logs <nombre>` lista los últimos 15; un admin de rango 1 no ve la pestaña y `/logs` lo rechaza; `/debugscript 3` limpio tras `restart rp_logs`.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-28, commit e11a629)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 6 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | SEG-01 | Handlers de eventos remotos usan client | sin eventos remotos |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
