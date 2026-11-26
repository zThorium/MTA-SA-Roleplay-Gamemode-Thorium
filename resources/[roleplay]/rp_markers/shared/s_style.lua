--[[
    rp_markers / s_style.lua  (compartido)

    Validación del estilo de un marcador, igual en servidor y cliente.
    Campos: icon (de MARKERS.ICONS), label (texto, 48 máx.), color {r, g, b},
            native = true (deja el cilindro original), beam = false (sin haz de luz).
]]

local iconSet = {}
for _, name in ipairs(MARKERS.ICONS) do iconSet[name] = true end

local function byte(v)
    v = tonumber(v)
    if not v then return nil end
    return math.floor(math.max(0, math.min(255, v)))
end

--- Copia solo los campos conocidos y con el tipo correcto. Devuelve la tabla limpia o nil.
function MARKERS.sanitizeStyle(style)
    if type(style) ~= "table" then return nil end
    local out = {}
    if type(style.icon) == "string" and iconSet[style.icon] then out.icon = style.icon end
    if type(style.label) == "string" and style.label ~= "" then out.label = style.label:sub(1, 48) end
    if type(style.color) == "table" then
        local r, g, b = byte(style.color[1]), byte(style.color[2]), byte(style.color[3])
        if r and g and b then out.color = { r, g, b } end
    end
    if style.native == true then out.native = true end
    if style.beam == false then out.beam = false end
    return next(out) and out or nil
end
