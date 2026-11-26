--[[
    rp_map / shared/s_grid.lua
    Cuadricula del mundo real de GTA SA (servidor y cliente):
      - celdas de exploracion de 50 m: indice 1..14400, fila 0 = norte (y = 3000), columna 0 = oeste
      - sectores ("cuadriculas") de 500 m: 12 x 12, id "A1".."L12" (letra = columna oeste->este, numero = fila norte->sur)
    Nombre y ciudad de cada sector salen de getZoneName (mismas zonas que usa el juego).
]]

MapGrid = {}

local N = 120              -- celdas por lado (WORLD / CELL)
local SECTORS = 12         -- sectores por lado
local LETTERS = "ABCDEFGHIJKL"

function MapGrid.size() return N end

function MapGrid.cellOf(x, y)
    local cx = math.floor((x + 3000) / 50)
    local cy = math.floor((3000 - y) / 50)
    if cx < 0 or cy < 0 or cx >= N or cy >= N then return nil end
    return cy * N + cx + 1
end

function MapGrid.cellCenter(i)
    local i0 = i - 1
    local cx, cy = i0 % N, math.floor(i0 / N)
    return -3000 + cx * 50 + 25, 3000 - cy * 50 - 25
end

function MapGrid.isLand(i)
    return MAP_LAND and MAP_LAND:byte(i) == 49
end

function MapGrid.sectorOfCell(i)
    local i0 = i - 1
    local cx, cy = i0 % N, math.floor(i0 / N)
    return math.floor(cy / 10) * SECTORS + math.floor(cx / 10) + 1
end

function MapGrid.sectorId(s)
    local s0 = s - 1
    local sx, sy = s0 % SECTORS, math.floor(s0 / SECTORS)
    return LETTERS:sub(sx + 1, sx + 1) .. (sy + 1)
end

function MapGrid.sectorIndex(id)
    if type(id) ~= "string" then return nil end
    local letter, num = id:match("^(%u)(%d%d?)$")
    if not letter then return nil end
    local sx = LETTERS:find(letter, 1, true)
    num = tonumber(num)
    if not sx or not num or num < 1 or num > SECTORS then return nil end
    return (num - 1) * SECTORS + sx
end

-- Bordes del sector en coordenadas del mundo: x1 (oeste), y1 (norte), x2 (este), y2 (sur)
function MapGrid.sectorBounds(s)
    local s0 = s - 1
    local sx, sy = s0 % SECTORS, math.floor(s0 / SECTORS)
    return -3000 + sx * 500, 3000 - sy * 500, -3000 + (sx + 1) * 500, 3000 - (sy + 1) * 500
end

-- Celdas cuyo centro queda dentro del radio. Llama fn(indice) por cada una.
function MapGrid.eachCellInRadius(x, y, r, fn)
    local r2 = r * r
    local cx0, cx1 = math.floor((x - r + 3000) / 50), math.floor((x + r + 3000) / 50)
    local cy0, cy1 = math.floor((3000 - y - r) / 50), math.floor((3000 - y + r) / 50)
    for cy = math.max(0, cy0), math.min(N - 1, cy1) do
        local my = 3000 - cy * 50 - 25
        for cx = math.max(0, cx0), math.min(N - 1, cx1) do
            local mx = -3000 + cx * 50 + 25
            local dx, dy = mx - x, my - y
            if dx * dx + dy * dy <= r2 then fn(cy * N + cx + 1) end
        end
    end
end

-- Sectores con nombre y ciudad dominantes (segun las celdas de tierra) y, por celda, su ciudad.
-- Devuelve sectors[s] = { id, name, city, land }, cellCity[i] = ciudad (solo celdas de tierra)
function MapGrid.buildSectors()
    local sectors, cellCity = {}, {}
    for s = 1, SECTORS * SECTORS do
        sectors[s] = { id = MapGrid.sectorId(s), land = 0, zones = {}, cities = {} }
    end
    for i = 1, N * N do
        if MapGrid.isLand(i) then
            local x, y = MapGrid.cellCenter(i)
            local zone = getZoneName(x, y, 30, false)
            local city = getZoneName(x, y, 30, true)
            local sec = sectors[MapGrid.sectorOfCell(i)]
            sec.land = sec.land + 1
            sec.zones[zone] = (sec.zones[zone] or 0) + 1
            sec.cities[city] = (sec.cities[city] or 0) + 1
            cellCity[i] = city
        end
    end
    for _, sec in ipairs(sectors) do
        local best, bestN = "Océano", 0
        for name, n in pairs(sec.zones) do if n > bestN then best, bestN = name, n end end
        local city, cityN = "San Andreas", 0
        for name, n in pairs(sec.cities) do if n > cityN then city, cityN = name, n end end
        sec.name, sec.city, sec.zones, sec.cities = best, city, nil, nil
    end
    return sectors, cellCity
end

-- Celdas exploradas <-> texto hexadecimal (4 celdas por letra): 14400 celdas = 3600 letras
local HEX = "0123456789abcdef"
function MapGrid.encode(cells)
    local out = {}
    for g = 0, N * N / 4 - 1 do
        local v = 0
        for k = 1, 4 do
            v = v * 2 + (cells[g * 4 + k] and 1 or 0)
        end
        out[#out + 1] = HEX:sub(v + 1, v + 1)
    end
    return table.concat(out)
end

function MapGrid.decode(text)
    local cells, count = {}, 0
    if type(text) ~= "string" then return cells, 0 end
    for g = 1, math.min(#text, N * N / 4) do
        local v = (HEX:find(text:sub(g, g), 1, true) or 1) - 1
        for k = 4, 1, -1 do
            if v % 2 == 1 then cells[(g - 1) * 4 + k] = true; count = count + 1 end
            v = math.floor(v / 2)
        end
    end
    return cells, count
end
