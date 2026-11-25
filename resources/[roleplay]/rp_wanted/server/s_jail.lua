--[[
    rp_wanted / s_jail.lua
    Carcel tras un arresto: celda de la comisaria de Los Santos con un timer
    (JAIL_SECONDS_PER_STAR por estrella) o fianza (/fianza, en efectivo).
    Al salir quedas en la puerta de la comisaria de Pershing Square.

      - El tiempo solo corre conectado y se conserva al reconectar o cambiar de
        personaje (en memoria, por personaje).
      - Si te alejas de la celda, mueres o reapareces, vuelves a la celda.
      - elementData publico del preso: rp:jail = segundos restantes,
        rp:jailBail = fianza (el HUD de client/c_jail.lua los muestra).

    Admin: /liberar <jugador>, /encarcelar <jugador> <minutos>
]]

local jailed = {}       -- [player] = { left, bail, chaos }
local savedJail = {}    -- [characterId] = { left, bail, chaos }

local function characterOf(p) return getElementData(p, "rp:characterId") end
local function popup(p, title, text, kind) exports.rp_notify:popup(p, title, text, kind) end
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function putInCell(player)
    local c = WANTED.JAIL_CELL
    if isPedInVehicle(player) then removePedFromVehicle(player) end
    setElementInterior(player, c.interior)
    setElementDimension(player, 0)
    setElementPosition(player, c.x, c.y, c.z)
    setElementRotation(player, 0, 0, c.rot)
    setElementVelocity(player, 0, 0, 0)
    setCameraTarget(player, player)
    fadeCamera(player, true, 1.0)
end

local function publish(player, j)
    setElementData(player, "rp:jail", j and math.max(0, math.ceil(j.left)) or false)
    setElementData(player, "rp:jailBail", j and j.bail or false)
end

local function release(player, reason)
    local j = jailed[player]
    if not j then return end
    jailed[player] = nil
    publish(player, nil)
    local r = WANTED.BUST_RELEASE
    fadeCamera(player, false, 0.6)
    setTimer(function()
        if not isElement(player) then return end
        setElementInterior(player, 0)
        setElementDimension(player, 0)
        setElementPosition(player, r.x, r.y, r.z)
        setElementRotation(player, 0, 0, r.rot)
        setCameraTarget(player, player)
        fadeCamera(player, true, 1.0)
        setWantedParole(player, j.chaos)
        popup(player, "Comisaria", reason or "Cumpliste tu condena. Quedas en libertad.", "success")
    end, 700, 1)
end

function jailPlayer(player, seconds, bail, chaos)
    if not isElement(player) then return false end
    local j = { left = math.max(1, seconds), bail = math.max(0, math.floor(bail or 0)), chaos = chaos or 0 }
    jailed[player] = j
    putInCell(player)
    publish(player, j)
    popup(player, "Carcel", ("Condena: %d:%02d. Puedes salir antes pagando la fianza de $%d con /fianza.")
        :format(math.floor(j.left / 60), j.left % 60, j.bail), "warning")
    outputServerLog(("[rp_wanted] %s encarcelado %d s (fianza $%d)"):format(getPlayerName(player), j.left, j.bail))
    return true
end

function isPlayerJailed(player)
    return jailed[player] ~= nil
end

-- Cada segundo: descuenta y vigila que siga en la celda
setTimer(function()
    local c = WANTED.JAIL_CELL
    for player, j in pairs(jailed) do
        if not isElement(player) then
            jailed[player] = nil
        else
            j.left = j.left - 1
            if j.left <= 0 then
                release(player)
            else
                publish(player, j)
                if not isPedDead(player) then
                    local x, y, z = getElementPosition(player)
                    if getElementInterior(player) ~= c.interior
                        or getDistanceBetweenPoints3D(x, y, z, c.x, c.y, c.z) > WANTED.JAIL_MAX_DISTANCE then
                        putInCell(player)
                    end
                end
            end
        end
    end
end, 1000, 0)

-- Fianza: en efectivo
addCommandHandler("fianza", function(player)
    local j = jailed[player]
    if not j then return notify(player, "No estas en la carcel.", "info") end
    if getPlayerMoney(player) < j.bail then
        return notify(player, ("La fianza es de $%d y no tienes suficiente efectivo."):format(j.bail), "error")
    end
    takePlayerMoney(player, j.bail)
    release(player, ("Pagaste la fianza de $%d. Quedas en libertad."):format(j.bail))
end)

-- Reaparecer (muerte) dentro de la condena: de vuelta a la celda
addEventHandler("onPlayerSpawn", root, function()
    local player = source
    if jailed[player] then
        setTimer(function() if isElement(player) and jailed[player] then putInCell(player) end end, 500, 1)
    end
end)

-- Conservar la condena al salir o cambiar de personaje
local function store(player)
    local j, id = jailed[player], characterOf(player)
    if j and id then savedJail[id] = j end
    jailed[player] = nil
end
addEventHandler("onPlayerQuit", root, function() store(source) end)
addEventHandler("rp:onCharacterLogout", root, function() store(source) publish(source, nil) end)

addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    local player = source
    publish(player, nil)
    local j = savedJail[characterId]
    savedJail[characterId] = nil
    setTimer(function()
        if not isElement(player) or characterOf(player) ~= characterId then return end
        if j then
            jailed[player] = j
            putInCell(player)
            publish(player, j)
            notify(player, ("Sigues en la carcel: te quedan %d:%02d."):format(math.floor(j.left / 60), j.left % 60), "warning")
        else
            -- Guardado dentro de la celda sin condena (p. ej. tras reiniciar el servidor): a la salida
            local c = WANTED.JAIL_CELL
            local x, y, z = getElementPosition(player)
            if getElementInterior(player) == c.interior and getDistanceBetweenPoints3D(x, y, z, c.x, c.y, c.z) < 15 then
                local r = WANTED.BUST_RELEASE
                setElementInterior(player, 0)
                setElementPosition(player, r.x, r.y, r.z)
            end
        end
    end, 1500, 1)
end)

-- Admin
-- "Nombre Apellido (ID 3)" para los mensajes
local function label(p)
    local name = exports.rp_characters:getPlayerCharacterName(p) or getPlayerName(p)
    return ("%s (ID %s)"):format((tostring(name):gsub("_", " ")), tostring(exports.rp_ids:getPlayerId(p) or "?"))
end

addCommandHandler("liberar", function(admin, _, query)
    if not isAdmin(admin) then return notify(admin, "No tienes permiso para usar este comando.", "error") end
    if not query then return notify(admin, "Uso: /liberar <id o nombre>", "warning") end
    local target = exports.rp_ids:findPlayer(query)
    if not target then return notify(admin, "No se encontró un único jugador con ese nombre o ID.", "warning") end
    local j = jailed[target]
    if not j then return notify(admin, label(target) .. " no está en la cárcel.", "info") end
    local left = math.max(0, math.ceil(j.left))
    release(target, "Un administrador te liberó.")
    notify(admin, ("Liberaste a %s (le quedaban %d:%02d)."):format(label(target), math.floor(left / 60), left % 60), "success")
end)

addCommandHandler("encarcelar", function(admin, _, query, minutes)
    if not isAdmin(admin) then return notify(admin, "No tienes permiso para usar este comando.", "error") end
    local usage = "Uso: /encarcelar <id o nombre> <minutos 1-600>"
    local target = query and exports.rp_ids:findPlayer(query)
    minutes = tonumber(minutes)
    if not query or not minutes or minutes <= 0 or minutes > 600 then return notify(admin, usage, "warning") end
    if not target then return notify(admin, "No se encontró un único jugador con ese nombre o ID.", "warning") end
    local bail = math.floor(minutes * WANTED.JAIL_BAIL_PER_STAR / 1.5)
    jailPlayer(target, math.floor(minutes * 60), bail, 0)
    notify(admin, ("Encarcelaste a %s durante %s min (fianza $%d)."):format(label(target), tostring(minutes), bail), "success")
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(jailed) do
        if isElement(player) then publish(player, nil) end
    end
end)
