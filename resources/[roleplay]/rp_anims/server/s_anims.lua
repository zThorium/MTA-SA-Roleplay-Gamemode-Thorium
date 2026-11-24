--[[
    rp_anims / s_anims.lua

    Animaciones de personaje. El cliente solo envia el id del catalogo
    (shared/s_config.lua); el servidor valida estado y aplica la animacion.

    Uso:    mantener G -> radial, soltar sobre la animacion (ver c_anims.lua)
    Comandos:
        /anim <nombre>     reproduce una animacion por nombre (ej. /anim saludar)
        /anim              lista las animaciones
        /stopanim          cancela la animacion actual
]]

addEvent("rp:anims:play", true)
addEvent("rp:anims:stop", true)

local cooldown = {}

local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end

local function canAnimate(p)
    if not exports.rp_characters:getPlayerCharacterId(p) then return false end
    if isPedDead(p) or isPedInVehicle(p) then return false end
    if getElementData(p, "rp:downed") then return false end
    if isElementFrozen(p) then return false end
    return true
end

local function play(p, a)
    setPedAnimation(p, a[2], a[3], -1, a[4] and true or false, false, true, a[5] and true or false)
end

local function stop(p)
    setPedAnimation(p)
end

addEventHandler("rp:anims:play", resourceRoot, function(id)
    local p = client
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < 400 then return end
    cooldown[p] = now
    local a = getAnimById(id)
    if not a or not canAnimate(p) then return end
    play(p, a)
end)

addEventHandler("rp:anims:stop", resourceRoot, function()
    local p = client
    if not isElement(p) or getElementData(p, "rp:downed") then return end
    stop(p)
end)

addCommandHandler("stopanim", function(p)
    if canAnimate(p) then stop(p) end
end)

addCommandHandler("anim", function(p, _, ...)
    local name = table.concat({ ... }, " ")
    if name == "" then
        local names = {}
        for _, page in ipairs(ANIM_PAGES) do
            for _, a in ipairs(page.list) do names[#names + 1] = a[1] end
        end
        notify(p, "Animaciones: " .. table.concat(names, ", ") .. ". Tambien: mantener " .. ANIMS_KEY:upper() .. ".", "info")
        return
    end
    local id, a = getAnimByName(name)
    if not a then notify(p, "No existe esa animacion. Usa /anim para ver la lista.", "error") return end
    if not canAnimate(p) then return end
    play(p, a)
end)

addEventHandler("onPlayerQuit", root, function() cooldown[source] = nil end)
