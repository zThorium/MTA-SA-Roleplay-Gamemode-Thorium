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
| `rp_injury:isPlayerDowned(p)`, `downPlayer(p)`, `revivePlayer(p)`; cliente `isLocalPlayerDowned()` | |
| `rp_police:isCuffed(p)`, `isOnDuty(p)` | |
| `rp_missions:getPlayerMission(p)` | id de instancia o `false` |
| `rp_races:getPlayerRace(p)` | id o `false` |
| `rp_robbery:isPlayerRobbing(p)` | |
| `rp_driving:hasDriverLicense(p)`, `getDriverLicense(p)`, `isPlayerInDrivingTest(p)` | |
| `rp_agency:hasPlayerDNI(p)`, `getPlayerDNI(p)` | |
| `rp_jobs:getPlayerJob(p)`, `setPlayerJob(p, id, force)`, `isPlayerOnShift(p)`, `getPlayerJobLevel(p)`, `showJobLocation(p, id)`, `getMarketPrice(...)` | API completa en `docs/TRABAJOS.md` |
| `rp_backpacks:getBackpack(p)`, `getPackWeight(p)` | |

## Facciones y policía

| Export | |
|---|---|
| `rp_factions:getPlayerFaction(p)` | `id, nombre, rol, esLider, tipo` o `false` |
| `rp_factions:hasFactionPermission(p, clave)` | permisos de rol (p. ej. `pol_detain`) |
| `rp_factions:getPlayerRankLevel(p)`, `getFactionMembersOnline(id)` | |
| `rp_police:dispatchAlert(clave, x, y, z, extra, jugador)` | claves en `POLICE_CODES`: `shots`, `wanted`, `call`, `panic`, `robbery`... |
| `rp_wanted:reportCrime(p, delito, victima, dontCare, witnessed)` | delitos en `WANTED_CRIMES` (`rp_wanted/shared/s_config.lua`) |
| `rp_wanted:getWantedLevel(p)`, `setWantedLevel(p, n, force)`, `clearWanted(p)` | |
| `rp_wanted:setWantedSuspended(p, bool)`, `isWantedSuspended(p)` | no acumula estrellas (misiones, minijuegos) |
| `rp_wanted:jailPlayer(p, segundos, fianza, caos)`, `isPlayerJailed(p)`, `holdPursuit`, `setPursuitTerms` | ver `docs/BUSQUEDA_POLICIAL.md` |
| `rp_emergency:callService(p, "ambulance"|"police"|"fire")` | |

## Mundo, vehículos y propiedades

| Export | |
|---|---|
| `rp_vehicles:createOwnedVehicle(p, modelo, color, x, y, z, rz)` | vehículo personal persistente con llave |
| `rp_vehicles:getVehicleOwner(v)`, `getVehicleDatabaseId(v)`, `saveVehicle(v)`, `countOwnedVehicles(p)` | |
| `rp_vehicles:getVehicleFuel(v)`, `setVehicleFuel(v, litros)`, `getVehicleOdometer(v)` | |
| `rp_properties:getPropertyInfo(id)` | |
| `rp_shops:addTempShop(ped, nombre, {itemId = precio})`, `removeTempShop(id)` | tienda temporal con el menú de `rp_shops` |
| `rp_events:registerEvent{ id, name, duration = {min, max}, weight, cooldown, severity, elements, hours, rain, alert, kind }` | evento dinámico propio (`rp:events:ext:start/finish`) |
| `rp_events:getWorldState()`, `setWeatherState(...)` | hora y clima los gobierna `rp_events`: no uses `setTime`/`setWeather` |
| `rp_radio:getVehicleStation(v)`, `setVehicleStation(v, ...)` | |
| Cliente `rp_citizens:citizenWatch`, `citizenAdopt`, `getRoadGraph`; `rp_rides:findRoadRoute`, `nearestRoadNode` | red vial para IA |

## HUD, radio y cinemáticas (cliente)

| Export | |
|---|---|
| `rp_hud:setHudSuppressed(razon, bool)`, `isHudSuppressed()` | oculta HUD, chat y avisos; `razon` = nombre de tu recurso |
| `rp_radio:setRadioSuppressed(razon, bool)`, `isRadioSuppressed()` | silencia `rp_radio` y la radio nativa |
| `rp_jobs:playJobCinematic`, `stopJobCinematic`, `isJobCinematicPlaying` | cinemáticas cortas reutilizables |
| `rp_mocap` (servidor `play`, cliente `playClip`) | mocap de personajes; ver `rp_mocap/MOCAP_CATALOGO.md` |
| `rp_characters:applyPedLook(ped, look)` | vestir un ped como un personaje |
