# API de Thorium para recursos nuevos

Exports reales (sacados de los `meta.xml` y del código, nov. 2026). Llamada: `exports.<recurso>:<funcion>(...)`.
Si un export cambia o creas uno nuevo, actualiza este archivo. Para la lista completa por recurso:
`grep -oE '<export function="[^"]+"' resources/[roleplay]/rp_X/meta.xml`.

> Los exports no pueden recibir ni devolver funciones. Los que consultan la BD y devuelven un valor
> (`getBalance`, `chargeAccount`) son **síncronos** y bloquean: no los llames en bucles ni por frame.

## Eventos del ciclo de vida (servidor)

Declara con `addEvent(nombre, false)` y engánchate con `addEventHandler(nombre, root, fn)`.

| Evento | `source` | Argumentos | Lo dispara |
|---|---|---|---|
| `rp:onDatabaseReady` | `resourceRoot` de rp_database | — | `rp_database` tras aplicar el esquema |
| `rp:onAccountLogin` | jugador | `accountId, username` | `rp_login` |
| `rp:onAccountLogout` | jugador | `accountId` | `rp_login` |
| `rp:onCharacterSpawn` | jugador | `characterId, name` | `rp_characters` (al entrar con un personaje) |
| `rp:onCharacterLogout` | jugador | `characterId` | `rp_characters` (cambio de personaje o salida) |
| `rp:onPlayerDowned` | jugador | — | `rp_injury` (queda abatido) |
| `rp:onPlayerDownedEnd` | jugador | — | `rp_injury` (revivido o muerto y respawneado) |
| `rp:onDownedLogout` | jugador | — | `rp_characters` (sale estando abatido) |
| `rp:onItemUse` | jugador | `itemId` | `rp_inventory` (items con `use = { event = true }`) |
| `rp:onDrugUsed` | jugador | `drug` | `rp_inventory` |
| `rp:onWantedLevelChange` | jugador | `nuevo, anterior` | `rp_wanted` |
| `rp:jobs:onJobChanged`, `rp:jobs:onShiftEnd` | jugador | ver `docs/TRABAJOS.md` | `rp_jobs` |
| `rp:events:onStart`, `rp:events:onEnd`, `rp:events:onWorldChanged` | — | ver `docs/EVENTOS_DINAMICOS.md` | `rp_events` |

Cliente: `rp:onClientPlayerDowned` (source = `localPlayer`), `rp:jobs:onCinematicEnd`.

Patrón de arranque (ver `plantillas/s_main.lua`):

```lua
addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)
```

## Identidad y sesión

| Export | Devuelve |
|---|---|
| `rp_login:isPlayerLoggedIn(p)` | bool |
| `rp_login:getPlayerAccountId(p)` / `getPlayerAccountName(p)` | id / nombre o `nil` |
| `rp_login:getPlayerAdminLevel(p)` | número (0 = jugador). Úsalo como `(... or 0) >= N` |
| `rp_characters:getPlayerCharacterId(p)` | id del personaje o `nil` (sin personaje → no hacer nada) |
| `rp_characters:getPlayerCharacterName(p)` | "Nombre Apellido" |
| `rp_characters:saveCharacter(p, toHospital)` | guarda posición, efectivo, vida... (llamar tras tocar efectivo) |
| `rp_characters:respawnAtHospital(p)` | |
| `rp_characters:getBodyStats(p)` / `setBodyStats(p, grasa, musculo, resistencia, redibujar)` | 0-1000 |
| `rp_ids:getPlayerId(p)`, `getPlayerFromId(id)`, `findPlayer(texto)` | `findPlayer` acepta ID o parte del nombre |
| `rp_adminpanel:hasPermission(p, clave)` | permisos IAM/RBAC del panel de admin |

## Avisos (servidor y cliente)

| Servidor | Cliente |
|---|---|
| `rp_notify:notify(p, texto, tipo, ms)` | `notify(texto, tipo, ms)` |
| `rp_notify:popup(p, titulo, texto, tipo, ms)` | `popup(titulo, texto, tipo, ms)` |
| `rp_notify:bubble(p, elemento, texto, ms)` | `bubble(elemento, texto, ms)` |

`tipo`: `"success"`, `"error"`, `"warning"`, `"info"`. `p` es un jugador o `root` (todos); para varios, recorre la lista.
`rp_nametags:setAme(p, texto, ms)` muestra una acción `/ame` sobre la cabeza.

## Dinero

| Export / patrón | Notas |
|---|---|
| Efectivo: `getPlayerMoney`, `takePlayerMoney`, `givePlayerMoney` + `rp_characters:saveCharacter(p)` | nativo de MTA |
| `rp_bank:getBalance(p)` | síncrono |
| `rp_bank:chargeAccount(characterId, n, concepto)` | cobro atómico del banco, `true/false`; registra `bank_transactions` |
| `rp_bank:payWithCard(p, ownerId, pin, n, concepto)` | `true` o `false, "card"|"locked"|"pin"|"funds"` |
| `rp_bank:getPlayerCards(p)` | tarjetas `bcard:<id>` que lleva |
| `rp_bank:isNearATM(p)` | |
| Ingreso al banco | `UPDATE characters SET bank_money = bank_money + ? WHERE id = ?` + `INSERT INTO bank_transactions (character_id, type, amount, other_name)` (ver `rp_payday`) |

## Inventario

| Export | Devuelve |
|---|---|
| `rp_inventory:canCarry(p, itemId, n)` | `true` o `false, motivo` (peso, stack, inventario no cargado) |
| `rp_inventory:giveItem(p, itemId, n)` | `true` o `false, motivo` (si no cabe va a la mochila) |
| `rp_inventory:takeItem(p, itemId, n)` | `true` o `false, motivo` |
| `rp_inventory:hasItem(p, itemId, n)`, `getItemAmount(p, itemId)` | incluye la mochila |
| `rp_inventory:getItemDefinition(itemId)` | tabla del catálogo (servidor y cliente) |
| `rp_inventory:getInventory(p)`, `getInventoryWeight(p)`, `getItemList()` | |
| `rp_inventory:setItemLabel(...)`, `refreshInventory(p)` | |
| `rp_inventory:spawnGroundItem(itemId, n, x, y, z, dim, int, contents)` | objeto en el suelo |
| Cliente: `isInventoryOpen()`, `closeInventory()` | |

Catálogo: `rp_inventory/shared/s_items.lua` (`name, icon, description, weight, stack, use, consumable, lot`).
Items con id dinámico usan prefijo: `vkey:<id>` (llave de vehículo), `bcard:<id>` (tarjeta).

## Personaje y estado

| Export | |
|---|---|
| `rp_needs:addNeed(p, "hunger"|"thirst"|"energy", n)`, `getNeed`, `getNeeds`, `addSanity`, `getSanity` | |
| `rp_levels:giveXP(p, n, motivo)`, `getPlayerLevel(p)`, `getPlayerXP(p)` | |
| `triggerEvent("rp:achievements:progress", p, "stat", n)` | **logros** (`rp_achievements`): avisa un hecho lograble tras validarlo en el servidor; sin `<include>` (si el recurso está parado, no pasa nada). Estadística nueva = entrada en `ACH.STATS` + logro en `ACH.CATALOG` (`docs/LOGROS.md`) |
| `rp_achievements:hasAchievement(p, "ach:<clave>[:<1-4>]"\|"points:<n>"\|"milestone:<n>")`, `getPlayerPoints(p)`, `getPlayerAchievements(p)` | leer logros (cosméticos de `rp_scoreboard`: `requires`) |
| `rp_injury:isPlayerDowned(p)`, `downPlayer(p)`, `revivePlayer(p)`; cliente `isLocalPlayerDowned()` | |
| `rp_police:isCuffed(p)`, `isOnDuty(p)` | |
| `rp_police:getPlayerActions(oficial, objetivo)`, `doPlayerAction(oficial, objetivo, id)` | acciones policiales sobre una persona (las del menú K); las usa `rp_interact` |
| `rp_worldobjects:isPlayerSeated(p)`, `standPlayer(p)` (levanta sin animación), `getWorldObjectStats()` | sentado en una banca o silla del mapa; levántalo antes de teletransportarlo o animarlo |
| `rp_missions:getPlayerMission(p)` | id de instancia o `false` |
| `rp_races:getPlayerRace(p)` | id o `false` |
| `rp_robbery:isPlayerRobbing(p)` | |
| `rp_driving:hasDriverLicense(p)`, `getDriverLicense(p)`, `isPlayerInDrivingTest(p)` | |
| `rp_agency:hasPlayerDNI(p)`, `getPlayerDNI(p)` | |
| `rp_jobs:getPlayerJob(p)`, `setPlayerJob(p, id, force)`, `isPlayerOnShift(p)`, `getPlayerJobLevel(p)`, `showJobLocation(p, id)`, `getMarketPrice(...)` | API completa en `docs/TRABAJOS.md` |
| `rp_jobs:startExternalShift(p, id)`, `endExternalShift(p, motivo)`, `payExternalJob(p, base, concepto)`, `giveExternalJobXP(p, n)` | trabajos externos (`external = "rp_x"` en `JOBS`): otro recurso juega el turno y `rp_jobs` lleva puesto, XP y pagos. Ejemplo: `rp_pizzeria` |
| `rp_pizzeria:isPlayerOnPizzaShift(p)` | si está de turno en la pizzería |
| `rp_metaldetector:isPlayerDetecting(p)`, `getMetalDetectorLoot()`, `getPlayerDetectorLevel(p)` | si lleva un detector en la mano; tabla de botín; nivel de buscador (1-5) |
| `rp_backpacks:getBackpack(p)`, `getPackWeight(p)` | |

## Facciones y policía

`rp_factions` es la **única fuente** de facciones: nadie lee `faction_members` ni decide con el element data
`rp:faction`. Se pregunta **por tipo** (`"policia"`, `"bomberos"`, `"medicos"`...; ver `FACTION_TYPES`), nunca por
un id fijo. `which` = id de facción (número) o tipo (texto); sin `which`, cualquier facción.

| Export | |
|---|---|
| `rp_factions:isPlayerInFaction(p [, which])` | ¿pertenece? — **la consulta normal** (también en cliente) |
| `rp_factions:isPlayerOnDuty(p [, which])` | ¿pertenece y está de servicio? Lo responde el recurso de `FACTION_TYPES[tipo].duty` (`rp_police`, `rp_firefighters`, `rp_duty` para médicos, gobierno, mecánicos, noticias, taxis...); tipos sin servicio: `false` |
| `rp_factions:getPlayerFactionId(p)`, `getPlayerFactionType(p)`, `isPlayerFactionLeader(p)` | id / tipo o `false` (los dos primeros también en cliente) |
| `rp_factions:getPlayerFactionInfo(p)` | `{ id, name, tag, type, color, stateFunded, rank, rankLevel, leader }` o `false` (en cliente, sin `stateFunded`/`rankLevel`) |
| `rp_factions:getFactionInfo(id)`, `getFactions([tipo])` | `{ id, name, tag, type, color, stateFunded, leaderId, online }` / lista |
| `rp_factions:getFactionPlayers(which [, soloDeServicio])` | jugadores conectados de esas facciones |
| `rp_factions:getCharacterFaction(characterId)` | `id, tipo` si el personaje está conectado; `false` si no |
| evento `rp:faction:onMembershipChange` | `source` = jugador; `(idNuevo\|false, tipoNuevo\|false, idAnterior\|false)` al entrar, salir o cambiar |
| `rp_factions:getPlayerFaction(p)` | `id, nombre, rol, esLider, tipo` o `false` (anterior; sigue valiendo) |
| `rp_factions:hasFactionPermission(p, clave)` | permisos de rol (p. ej. `pol_detain`) |
| `rp_factions:getPlayerRankLevel(p)`, `getFactionMembersOnline(id)` | |
| `rp_police:dispatchAlert(clave, x, y, z, extra, jugador)` | claves en `POLICE_CODES`: `shots`, `wanted`, `call`, `panic`, `robbery`... |
| `rp_wanted:reportCrime(p, delito, victima, dontCare, witnessed)` | delitos en `WANTED_CRIMES` (`rp_wanted/shared/s_config.lua`) |
| `rp_wanted:getWantedLevel(p)`, `setWantedLevel(p, n, force)`, `clearWanted(p)` | |
| `rp_wanted:setWantedSuspended(p, bool)`, `isWantedSuspended(p)` | no acumula estrellas (misiones, minijuegos) |
| `rp_wanted:jailPlayer(p, segundos, fianza, caos)`, `isPlayerJailed(p)`, `holdPursuit`, `setPursuitTerms` | ver `docs/BUSQUEDA_POLICIAL.md` |
| `rp_emergency:callService(p, "ambulance"|"police"|"fire")` | |
| `rp_firefighters:isOnDuty(p)`, `isFirefighter(p)`, `getFirefightersOnDuty()` | bomberos (facciones de tipo `bomberos`) y quién está de servicio |
| `rp_duty:isOnDuty(p)`, `getDutyLoadout(p)` | vestuario genérico de facción: ¿de servicio? y uniforme puesto (`{ id, name, factionId }` o `false`) |
| `rp_duty:getFactionVehicleInfo(v)` | vehículo de facción del garaje: `{ id, factionId, minLevel }` o `false` (también element data `rp:factionVehicle`) |
| `rp_factions:getFactionFunds(id)`, `takeFactionFunds(id, n [, registro])`, `addFactionFunds(id, n [, registro])` | fondos de una facción; `takeFactionFunds` es atómico y devuelve `false` si no alcanza |
| `rp_factions:bill(empleado, cliente, monto, concepto)` | factura a un cliente cercano (permiso `bill`): `true` o `false, motivo`; el pago llega después (evento `rp:faction:onInvoicePaid`, source = empleado) |

## Mundo, vehículos y propiedades

| Export | |
|---|---|
| `rp_vehicles:createOwnedVehicle(p, modelo, color, x, y, z, rz)` | vehículo personal persistente con llave |
| `rp_vehicles:getVehicleOwner(v)`, `getVehicleDatabaseId(v)`, `saveVehicle(v)`, `countOwnedVehicles(p)` | |
| `rp_vehicles:setVehicleLockState(v, cerrado)`, `setVehicleHotwired(v, bool)` | abrir sin llave (guardado) y puente; evento cancelable `rp:veh:onEngineNoKey` (source = jugador, vehículo) |
| `rp_cartheft:isPlayerStealing(p)`, `isVehicleAlarmOn(v)` | robo de vehículo en curso / alarma sonando |
| `rp_vehicles:getVehicleFuel(v)`, `setVehicleFuel(v, litros)`, `getVehicleOdometer(v)` | |
| `rp_properties:getPropertyInfo(id)` | |
| `rp_shops:addTempShop(ped, nombre, {itemId = precio})`, `removeTempShop(id)` | tienda temporal con el menú de `rp_shops` |
| `rp_events:registerEvent{ id, name, duration = {min, max}, weight, cooldown, severity, elements, hours, rain, alert, kind }` | evento dinámico propio (`rp:events:ext:start/finish`) |
| `rp_events:getWorldState()`, `setWeatherState(...)` | hora y clima los gobierna `rp_events`: no uses `setTime`/`setWeather` |
| `rp_radio:getVehicleStation(v)`, `setVehicleStation(v, ...)` | |
| `rp_train:getTrainState()`, `getTrainRoute()`, `getTrackLength()`, `getTrainEta()` | trenes, recorrido desde Unity y llegada estimada a cada estación |
| Cliente `rp_citizens:citizenWatch`, `citizenAdopt`, `getRoadGraph`; `rp_rides:findRoadRoute`, `nearestRoadNode` | red vial para IA |

## HUD, radio y cinemáticas (cliente)

| Export | |
|---|---|
| `rp_hud:setHudSuppressed(razon, bool)`, `isHudSuppressed()` | oculta HUD, chat y avisos; `razon` = nombre de tu recurso |
| `rp_hud:setHudHidden(razon, bool)` (cliente) | oculta **solo** el HUD de `rp_hud` (minimapa, necesidades, velocímetro), como F7; chat y avisos siguen. Para recursos con HUD propio (ej. `rp_pizzeria`) |
| `rp_hud:getTopRightBottom()` (cliente) | Y en px donde termina el bloque de arriba a la derecha (hora, dinero, banco, arma, estrellas, nivel). Pon tus paneles de esa esquina debajo, preguntando unas veces por segundo, no en cada frame (ej. `rp_robbery`) |
| `rp_radio:setRadioSuppressed(razon, bool)`, `isRadioSuppressed()` | silencia `rp_radio` y la radio nativa |
| `rp_phone:setMusicSuppressed(razon, bool)` (cliente) | pausa la música del teléfono (privada, altavoz y vehículo) mientras haya algún motivo |
| `rp_npcrel:createDateContact(characterId, datos)` (servidor) | crea un vínculo con número guardado en el teléfono (citas de Tinder); responde con el evento de servidor `rp:npcrel:dateContact` (ref, número o nil) |
| `rp_vehicles:isCursorModeActive()` (cliente) | `true` con el cursor de la tecla M activo y sin panel de vehículo abierto (lo usa `rp_interact`) |
| `rp_help:openReport(jugador)` (cliente) | abre F1 en Reportar con esa persona ya elegida |
| `rp_hud:setNavRoute(puntos)` (cliente) | dibuja una ruta `{x1, y1, x2, y2, ...}` en el minimapa (`nil` la quita); la usa el GPS de `rp_map` |
| `rp_map:getPlayerExplorationPercent(p)`, `revealPlayerArea(p, x, y, r)`, `getMapStats()` (servidor) | % de mapa explorado; descubrir un área del mapa F11 (misiones, eventos) |
| `rp_jobs:playJobCinematic`, `stopJobCinematic`, `isJobCinematicPlaying` | cinemáticas cortas reutilizables |
| `rp_mocap` (servidor `play`, cliente `playClip`) | mocap de personajes; ver `rp_mocap/MOCAP_CATALOGO.md` |
| `rp_markers:setMarkerStyle(marker, { icon, label, color, beam, native })` | icono 3D y texto en un marcador de cilindro (servidor: sincronizado; cliente: marcadores de cliente). Iconos: `getMarkerIcons()`. Todo cilindro ya sale con el estilo moderno sin llamar a nada |
| `rp_markers:placePoint(clave, x, y, z)` (servidor y cliente) y `registerMarker(marker, clave, { label, point, ownerSaves, level })` (servidor) | **todo marcador fijo** (puerta, mostrador, punto de servicio): pide su posición con `placePoint` (puede haberla movido un admin) y regístralo para que se mueva con el editor ALT/M; reconstrúyelo en el evento `rp:markers:moved (recurso, clave, x, y, z, admin)`. Con `ownerSaves = true` lo guardas tú en tu BD. Si el marcador lo crea el **cliente**, el servidor apunta el punto con `registerPoint(clave, { label, point, interior, dimension })` (también en `rp:markers:ready`). Ejemplos: `rp_ammunation` (config), `rp_police` y `rp_robbery` (BD propia) |
| `rp_characters:applyPedLook(ped, look)` | vestir un ped como un personaje |
