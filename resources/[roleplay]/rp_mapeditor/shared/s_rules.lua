--[[
    rp_mapeditor / s_rules.lua (compartido)
    Limpieza y validación de elementos y ajustes. El servidor la aplica a todo lo que llega del
    cliente; el cliente la usa para no mandar basura. Funciones puras (las prueba rp_test).

    MapEditRules.element(raw, modelOk) -> fila limpia | nil, motivo
        raw     = { etype, model, x, y, z, rx, ry, rz, props }
        modelOk = function(etype, model) -> bool  (cada lado sabe qué modelos existen)
    MapEditRules.settings(raw) -> tabla limpia (solo claves conocidas y dentro de rango)
    MapEditRules.projectName(s) -> nombre | nil, motivo
]]

MapEditRules = {}

local function num(v, a, b, def)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return def end
    if a and v < a then v = a end
    if b and v > b then v = b end
    return v
end

local function int(v, a, b, def)
    v = num(v, a, b, def)
    return v and math.floor(v + 0.5) or v
end

local function bool(v, def)
    if v == nil then return def end
    return v == true or v == 1 or v == "1" or v == "true"
end

local function text(v, maxLen, pattern)
    if type(v) ~= "string" and type(v) ~= "number" then return "" end
    v = tostring(v):sub(1, maxLen)
    if pattern then v = v:gsub(pattern, "") end
    return v
end

local function color(t, n)
    local out = {}
    if type(t) ~= "table" then return nil end
    for i = 1, n do out[i] = int(t[i], 0, 255, 255) end
    return out
end

local function angle(v) return (num(v, nil, nil, 0) or 0) % 360 end

local PROPS = {}

PROPS.object = function(p)
    local out = {}
    if type(p.scale) == "table" then
        local C = MAPEDIT
        out.scale = { num(p.scale[1], C.SCALE_MIN, C.SCALE_MAX, 1), num(p.scale[2], C.SCALE_MIN, C.SCALE_MAX, 1),
                      num(p.scale[3], C.SCALE_MIN, C.SCALE_MAX, 1) }
        if out.scale[1] == 1 and out.scale[2] == 1 and out.scale[3] == 1 then out.scale = nil end
    elseif p.scale ~= nil then
        local s = num(p.scale, MAPEDIT.SCALE_MIN, MAPEDIT.SCALE_MAX, 1)
        if s ~= 1 then out.scale = { s, s, s } end
    end
    local a = int(p.alpha, 0, 255, 255)
    if a ~= 255 then out.alpha = a end
    if bool(p.col, true) == false then out.col = false end
    if bool(p.ds, false) then out.ds = true end
    if bool(p.frozen, true) == false then out.frozen = false end
    if bool(p.brk, false) then out.brk = true end
    return out
end

PROPS.vehicle = function(p)
    local out = {}
    out.color = color(p.color, 6)
    if type(p.upg) == "table" then
        out.upg = {}
        for i = 1, math.min(#p.upg, 17) do
            local u = int(p.upg[i], 1000, 1193)
            if u then out.upg[#out.upg + 1] = u end
        end
        if #out.upg == 0 then out.upg = nil end
    end
    local plate = text(p.plate, 8, "[^%w ]"):upper()
    if plate ~= "" then out.plate = plate end
    local pj = int(p.paintjob, 0, 3, 3)
    if pj ~= 3 then out.paintjob = pj end
    if bool(p.locked, true) == false then out.locked = false end
    if bool(p.engine, false) then out.engine = true end
    if bool(p.lights, false) then out.lights = true end
    if bool(p.sirens, false) then out.sirens = true end
    if bool(p.frozen, true) == false then out.frozen = false end
    return out
end

PROPS.ped = function(p)
    local out = {}
    local block = text(p.block, 32, "[^%w_]")
    local anim = text(p.anim, 32, "[^%w_]")
    if block ~= "" and anim ~= "" then out.block, out.anim = block, anim end
    if bool(p.frozen, true) == false then out.frozen = false end
    return out
end

PROPS.marker = function(p)
    local out = {}
    out.mtype = MAPEDIT.MARKER_TYPES[p.mtype] and p.mtype or "cylinder"
    out.size = num(p.size, 0.1, 20, 1.5)
    out.color = color(p.color, 4) or { 255, 200, 60, 160 }
    local icon = text(p.icon, 24, "[^%w_]")
    if icon ~= "" then out.icon = icon end
    local label = text(p.label, 48, "[%c<>]")
    if label ~= "" then out.label = label end
    return out
end

PROPS.pickup = function(p)
    local out = {}
    out.ptype = int(p.ptype, 0, 3, 0)
    if out.ptype == 2 then
        out.amount = int(p.amount, 1, 46, 22)
        out.ammo = int(p.ammo, 1, 9999, 50)
    elseif out.ptype == 3 then
        out.amount = int(p.amount, 1, 19999, 1239)
    else
        out.amount = int(p.amount, 1, 100, 100)
    end
    out.respawn = int(p.respawn, 1000, 3600000, 30000)
    return out
end

PROPS.point = function(p)
    local name = text(p.name, 32, "[%c<>\"]")
    return { name = name ~= "" and name or "punto" }
end

PROPS.removal = function(p)
    return { radius = num(p.radius, 0.1, MAPEDIT.REMOVAL_RADIUS_MAX, 1), lod = int(p.lod, 0, 19999, 0) }
end

function MapEditRules.element(raw, modelOk)
    if type(raw) ~= "table" then return nil, "datos inválidos" end
    local C = MAPEDIT
    local etype = tostring(raw.etype or "")
    if not PROPS[etype] then return nil, "tipo desconocido" end
    local model = int(raw.model, 0, 19999, nil)
    if etype == "point" or etype == "marker" then model = 0 end
    if etype == "pickup" then model = 0 end
    if model == nil then return nil, "modelo inválido" end
    if etype ~= "point" and etype ~= "marker" and etype ~= "pickup" and not (modelOk and modelOk(etype, model)) then
        return nil, "el modelo " .. model .. " no existe"
    end
    local x, y, z = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z)
    if not (x and y and z) or x ~= x or y ~= y or z ~= z then return nil, "posición inválida" end
    if math.abs(x) > C.COORD_MAX or math.abs(y) > C.COORD_MAX or z < C.Z_MIN or z > C.Z_MAX then
        return nil, "fuera del mapa"
    end
    local props = PROPS[etype](type(raw.props) == "table" and raw.props or {})
    if etype == "pickup" and props.ptype == 3 and modelOk and not modelOk("object", props.amount) then
        return nil, "el modelo del pickup no existe"
    end
    return {
        etype = etype, model = model, x = x, y = y, z = z,
        rx = angle(raw.rx), ry = angle(raw.ry), rz = angle(raw.rz), props = props,
    }
end

function MapEditRules.settings(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for key, r in pairs(MAPEDIT.SETTINGS) do
        if raw[key] ~= nil and raw[key] ~= false and raw[key] ~= "" then
            local v = num(raw[key], r[1], r[2], nil)
            if v and (key == "hour" or key == "minute" or key == "weather" or key == "farclip") then v = math.floor(v) end
            out[key] = v
        end
    end
    if out.minute and not out.hour then out.minute = nil end
    return out
end

function MapEditRules.projectName(s)
    s = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local C = MAPEDIT
    if #s < C.NAME_MIN or #s > C.NAME_MAX then
        return nil, ("El nombre debe tener entre %d y %d letras."):format(C.NAME_MIN, C.NAME_MAX)
    end
    if not s:find(C.NAME_PATTERN) then return nil, "Usa solo letras, números, espacios, guiones y puntos." end
    return s
end
