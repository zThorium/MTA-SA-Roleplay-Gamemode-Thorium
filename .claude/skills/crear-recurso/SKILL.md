---
name: crear-recurso
description: Crear un recurso rp_* nuevo del gamemode Thorium (estructura, meta.xml, servidor, cliente, registro en mtaserver.conf y documentación). Úsala siempre que haya que añadir un sistema o recurso nuevo al servidor MTA.
---

# Crear un recurso nuevo

Estándar con el que se hicieron `rp_shops`, `rp_payday`, `rp_factions` y el resto. Sigue los pasos
en orden y copia el estilo del recurso existente más parecido.

## 0. Antes de escribir

- Mira `docs/PLAN_MVP.md` y los PR abiertos: puede que el sistema ya esté planeado o en curso.
- Decide el nombre: `rp_<sistema>` en minúsculas y en español o inglés corto (`rp_bank`, `rp_rides`).
- Lista dependencias (casi siempre `rp_database`, `rp_notify`, `rp_login`, `rp_characters`; `rp_ids` si
  buscas jugadores por ID; `rp_inventory` si das items).

## 1. Estructura

```
resources/[roleplay]/rp_<sistema>/
  meta.xml
  shared/s_config.lua      tabla de config en MAYÚSCULAS (precios, coords, tiempos)
  server/s_<sistema>.lua   lógica y validación
  client/c_<sistema>.lua   solo si hay UI, teclas o dx
  html/                    solo si hay UI CEF (ver skill interfaz-cef)
```

Si el recurso es solo servidor y pequeño, los `.lua` pueden ir en la raíz (`rp_payday/s_payday.lua`).

## 2. meta.xml

```xml
<meta>
    <info author="Thorium" name="RP Sistema" description="Qué hace en una frase" version="1.0.0" type="script" />
    <min_mta_version server="1.6.0" client="1.6.0" />

    <include resource="rp_database" />
    <include resource="rp_notify" />
    <include resource="rp_login" />
    <include resource="rp_characters" />

    <script src="shared/s_config.lua" type="shared" />
    <script src="server/s_sistema.lua" type="server" />
    <script src="client/c_sistema.lua" type="client" cache="false" />

    <file src="html/index.html" />
    <file src="html/style.css" />
    <file src="html/app.js" />

    <export function="algoPublico" type="server" />
</meta>
```

- `cache="false"` en todo script de cliente.
- Config con datos sensibles (o que el cliente no debe ver) va como `type="server"`, no `shared`.
- Solo exporta lo que otro recurso necesita; los exports no pueden recibir ni devolver funciones.

## 3. Servidor: plantilla

```lua
--[[
    rp_sistema / s_sistema.lua

    Qué hace el recurso, en 2-4 líneas.

    Comandos:
        /comando <arg>          qué hace
        /comandoadmin <arg>     (admin) qué hace
]]

local state = {}      -- [player] = {...}
local cooldown = {}   -- [player] = tick

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:sistema:accion", true)       -- solo los que el cliente puede disparar llevan true

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function load()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        -- crear elementos del mundo, llenar caches...
        outputDebugString(("[rp_sistema] %d filas cargadas"):format(#rows))
    end, db(), "SELECT * FROM tabla")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then load() else addEventHandler("rp:onDatabaseReady", root, load) end
end)

addEventHandler("rp:onCharacterSpawn", root, function() --[[ source = jugador ]] end)
addEventHandler("rp:onCharacterLogout", root, function() state[source] = nil end)
addEventHandler("onPlayerQuit", root, function() state[source], cooldown[source] = nil, nil end)

addEventHandler("rp:sistema:accion", resourceRoot, function(id, cantidad)
    local player = client                                   -- nunca source
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 400 then return end
    cooldown[player] = now

    id, cantidad = tonumber(id), tonumber(cantidad)
    if not id or not cantidad or cantidad < 1 or cantidad ~= math.floor(cantidad) then return end
    if not characterOf(player) then return end
    -- revalidar distancia / interior / dimensión / item / permisos aquí
    -- ...
    notify(player, "Hecho.", "success")
end)
```

Reglas:
- **`client`** es el jugador en eventos remotos; ignora lo que diga el cliente sobre quién es.
- Convierte (`tonumber`, `type(x) == "string"`), acota rangos y longitudes, y aplica cooldown en acciones repetibles.
- Comprueba cercanía con interior + dimensión + distancia, igual que `isNear` en `rp_shops`.
- Dinero del banco: cobro atómico `UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?`
  y entrega solo si `affected > 0`. Dinero en mano: `getPlayerMoney` + `takePlayerMoney` + `exports.rp_characters:saveCharacter(player)`.
- Limpia timers, colshapes y estado por jugador al salir o cambiar de personaje.
- Logs con `outputDebugString("[rp_sistema] ...", nivel)`.

## 4. Base de datos

Si necesitas tablas o columnas, usa la skill **migracion-bd**.

## 5. Cliente / interfaz

- UI con HTML: skill **interfaz-cef**.
- Comandos de admin o elementos colocados en el mundo por admins: skill **comando-admin**.
- Teclas con `bindKey` dentro de `onClientResourceStart`, y no actuar si
  `isCursorShowing() or isChatBoxInputActive() or isConsoleActive()`.
- Avisos "Pulsa E para..." con dx como en `rp_shops/client/c_shops.lua`.

## 6. Registrar y documentar

1. `mtaserver.conf`: `<resource src="rp_sistema" startup="1" protected="0" />` **después** de sus dependencias.
2. `RECURSOS.md`: fila nueva en la tabla (qué hace, tecla, exports, comandos de jugador y de admin).
3. `README.md` si es una feature visible para jugadores; `docs/PLAN_MVP.md` si cierra un punto del plan.
4. `CLAUDE.md`: añadir el recurso a la lista de "Recursos actuales" si es un sistema nuevo.

## 7. Checklist antes del PR

- [ ] Arranca sin errores en la consola del servidor (`refresh`, `start rp_sistema`).
- [ ] `/debugscript 3` limpio en el cliente.
- [ ] Reiniciar el recurso con jugadores dentro no deja estado roto.
- [ ] Probado el flujo completo en juego con un personaje, y el caso de error (sin dinero, lejos, sin permiso).
- [ ] Ningún SQL concatenado; ninguna credencial en el código.
- [ ] Rama `feat/rp-sistema`, PR a `main` describiendo qué cambia en el juego y cómo probarlo.
