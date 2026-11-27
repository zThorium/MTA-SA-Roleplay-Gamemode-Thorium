--[[
    rp_achievements / c_badge.lua  (cliente)

    Globo de la ficha «Logros» del HUD (rp_hud/c_iconbar.lua), para que el jugador la vea y quiera abrirla:
      - "!" si nunca abrió los logros (se recuerda en @opened);
      - si no, el número de novedades = medallas nuevas sin ver + recompensas listas para reclamar.
    Lo publica en el elementData LOCAL (sin sincronizar) rp:achBadge, que lee rp_hud cada frame.
    Al abrir el panel las medallas cuentan como vistas; las recompensas siguen hasta reclamarlas.
    Clic en la ficha = evento de cliente rp:hud:action ("achievements") -> pide el panel al servidor.
]]

AchUI = AchUI or {}

local OPENED_FILE = "@opened"
local unseen, readyCount = 0, 0
local opened = fileExists(OPENED_FILE)

addEvent("rp:achievements:status", true)
addEvent("rp:hud:action", false)

local function publish()
    local value
    if not opened then value = "!"
    else value = unseen + readyCount end
    if getElementData(localPlayer, "rp:achBadge") ~= value then
        setElementData(localPlayer, "rp:achBadge", value, false)
    end
end

-- Al cargar el personaje: recompensas por reclamar y medallas ganadas mientras no estaba
addEventHandler("rp:achievements:status", resourceRoot, function(ready, gained)
    readyCount = math.max(0, tonumber(ready) or 0)
    unseen = math.max(0, tonumber(gained) or 0)
    publish()
end)

-- Medalla nueva en juego (c_toast.lua la anuncia)
function AchUI.onMedal(milestone)
    unseen = unseen + 1
    if milestone then readyCount = readyCount + 1 end
    publish()
end

-- El panel se abrió o se actualizó (datos del servidor): medallas vistas, recompensas exactas
function AchUI.onPanel(data)
    unseen = 0
    readyCount = math.max(0, tonumber(data and data.ready) or readyCount)
    if not opened then
        opened = true
        local f = fileCreate(OPENED_FILE)
        if f then fileWrite(f, "1"); fileClose(f) end
    end
    publish()
end

addEventHandler("rp:hud:action", root, function(id)
    if id == "achievements" then triggerServerEvent("rp:achievements:request", resourceRoot) end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    publish()
    triggerServerEvent("rp:achievements:statusRequest", resourceRoot)   -- tras un restart el servidor ya cargó antes que nosotros
end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    setElementData(localPlayer, "rp:achBadge", false, false)
end)
