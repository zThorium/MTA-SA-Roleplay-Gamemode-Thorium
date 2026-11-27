--[[
    rp_worldobjects / shared/s_objects.lua
    Indice de los objetos del mapa (WO_DATA, generado) igual en servidor y cliente:
    cada objeto tiene un numero (WO_LIST[i]) que el cliente manda y el servidor comprueba.
]]

WO_LIST = {}     -- [i] = { model, x, y, z, rz, int, seats, radius }
WO_GRID = {}     -- ["cx:cy"] = { i, i, ... }

local function cellKey(x, y)
    return math.floor(x / WO.CELL) .. ":" .. math.floor(y / WO.CELL)
end

-- Plazas de un modelo: fijas en la config o segun el largo de su caja
function WO_seatCount(model)
    local def, b = WO.MODELS[model], WO_BOX[model]
    if not def or not b then return 0 end
    if def.seats then return def.seats end
    local long = math.max(b[4] - b[1], b[5] - b[2])
    return math.max(1, math.floor(long / WO.SEAT_WIDTH))
end

-- Objetos cerca de un punto (misma celda y vecinas)
function WO_nearby(x, y, interior, radius, out)
    out = out or {}
    local cx, cy = math.floor(x / WO.CELL), math.floor(y / WO.CELL)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local cell = WO_GRID[(cx + dx) .. ":" .. (cy + dy)]
            if cell then
                for _, i in ipairs(cell) do
                    local o = WO_LIST[i]
                    if o.int == interior then
                        local ddx, ddy = o.x - x, o.y - y
                        local r = radius + o.radius
                        if ddx * ddx + ddy * ddy <= r * r then out[#out + 1] = i end
                    end
                end
            end
        end
    end
    return out
end

do
    local models = {}
    for model in pairs(WO_DATA) do
        if WO.MODELS[model] and WO_BOX[model] then models[#models + 1] = model end
    end
    table.sort(models)   -- mismo orden en servidor y cliente
    for _, model in ipairs(models) do
        local d, b = WO_DATA[model], WO_BOX[model]
        local radius = math.sqrt(math.max(b[1] * b[1], b[4] * b[4]) + math.max(b[2] * b[2], b[5] * b[5]))
        local seats = WO_seatCount(model)
        for k = 1, #d, 5 do
            local o = { model = model, x = d[k], y = d[k + 1], z = d[k + 2], rz = d[k + 3], int = d[k + 4], seats = seats, radius = radius }
            WO_LIST[#WO_LIST + 1] = o
            local key = cellKey(o.x, o.y)
            WO_GRID[key] = WO_GRID[key] or {}
            table.insert(WO_GRID[key], #WO_LIST)
        end
    end
end
