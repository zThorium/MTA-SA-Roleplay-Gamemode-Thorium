--[[
    rp_pizzeria / c_fx.lua
    Efectos en el mundo durante el turno (solo los ve el trabajador):
      - horno horneando: vapor suave; pasandose de punto: humo negro
      - freidora friendo: vapor
      - cliente encantado con su pizza: chispas doradas sobre la cabeza
    Se recalculan cada 300 ms a partir del estado del servidor.
]]
local fx = {}        -- [clave] = efecto

local function stop(key)
    if isElement(fx[key]) then destroyElement(fx[key]) end
    fx[key] = nil
end

local function stopAll()
    for key in pairs(fx) do stop(key) end
end

local function ensure(key, name, x, y, z, density)
    if isElement(fx[key]) then return end
    local e = createEffect(name, x, y, z, -90, 0, 0, 30, false)
    if not e then return end
    setElementInterior(e, PIZZERIA.INTERIOR)
    setElementDimension(e, Pz.dim)
    if density then setEffectDensity(e, density) end
    fx[key] = e
end

local function elapsed(ago) return ago + (getTickCount() - (Pz.stateTick or getTickCount())) end

local function update()
    if not Pz.onShift or not Pz.state then return stopAll() end
    local s, C = Pz.state, PIZZERIA
    for i = 1, 2 do
        local st, ov = C.STATION_BY_ID["oven" .. i], s.ovens[i]
        local o = st.obj
        if ov then
            local r = elapsed(ov.ago) / ov.target
            ensure("oven" .. i, "cigarette_smoke", o[2], o[3] - 0.25, o[4] + 0.35, 1.5)
            if r > 1.35 then ensure("burn" .. i, "overheat_car", o[2], o[3] - 0.2, o[4] + 0.3, 0.6) else stop("burn" .. i) end
        else
            stop("oven" .. i); stop("burn" .. i)
        end
    end
    local frying = s.fryer[1] or s.fryer[2]
    local fo = C.STATION_BY_ID.fryer.obj
    if frying then ensure("fryer", "cigarette_smoke", fo[2], fo[3] - 0.1, fo[4] + 1.0, 2) else stop("fryer") end
end

local prevShift, prevFx = Pz.onShiftChanged, Pz.onFx
Pz.onShiftChanged = function(on, dim)
    if prevShift then prevShift(on, dim) end
    stopAll()
end
Pz.onFx = function(kind, data)
    if prevFx then prevFx(kind, data) end
    if kind == "served" and data.reaction == "love" then
        -- chispas doradas cuando el cliente recoge la pizza (llega al mostrador en ~2 s)
        setTimer(function()
            local ped = Pz.customerPed and Pz.customerPed(data.id)
            if not ped then return end
            local x, y, z = getPedBonePosition(ped, 8)
            for _ = 1, 3 do fxAddSparks(x, y, z + 0.4, 0, 0, 1, 1.2, 12) end
        end, 2600, 1)
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(update, 300, 0)
end)
addEventHandler("onClientResourceStop", resourceRoot, stopAll)
