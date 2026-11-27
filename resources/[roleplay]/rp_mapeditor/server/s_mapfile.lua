--[[
    rp_mapeditor / s_mapfile.lua
    Importar y exportar el formato .map del editor de MTA.

    meExportMap(P) -> string XML
    meParseMap(xmlText) -> { filas sin validar }, avisos | nil, motivo
        Admite object, vehicle, ped, marker, pickup, spawnpoint y removeWorldObject.
]]

local function esc(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("\"", "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function f(v)
    local s = ("%.4f"):format(tonumber(v) or 0):gsub("0+$", ""):gsub("%.$", "")
    return s
end

local function attrs(t)
    local out = {}
    for _, kv in ipairs(t) do
        if kv[2] ~= nil then out[#out + 1] = ('%s="%s"'):format(kv[1], esc(kv[2])) end
    end
    return table.concat(out, " ")
end

local function hex(c)
    if not c then return nil end
    return ("#%02X%02X%02X%02X"):format(c[1] or 255, c[2] or 255, c[3] or 255, c[4] or 255)
end

local PICKUP_NAMES = { [0] = "health", [1] = "armor" }

function meExportMap(P)
    local lines = { '<map edf:definitions="editor_main">' }
    local rows = {}
    for _, row in pairs(P.rows) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b) return a.id < b.id end)
    local int, dim = P.interior, P.dimension
    for _, r in ipairs(rows) do
        local p, id = r.props or {}, ("%s (%d)"):format(r.etype, r.id)
        local pos = { { "posX", f(r.x) }, { "posY", f(r.y) }, { "posZ", f(r.z) } }
        local rot = { { "rotX", f(r.rx) }, { "rotY", f(r.ry) }, { "rotZ", f(r.rz) } }
        local base = { { "id", id }, { "interior", int }, { "dimension", dim } }
        local function line(tag, extra)
            local t = {}
            for _, l in ipairs({ base, extra, pos, rot }) do for _, kv in ipairs(l) do t[#t + 1] = kv end end
            lines[#lines + 1] = ("    <%s %s></%s>"):format(tag, attrs(t), tag)
        end
        if r.etype == "object" then
            local s = p.scale
            local scale = s and (s[1] == s[2] and s[2] == s[3] and f(s[1]) or (f(s[1]) .. "," .. f(s[2]) .. "," .. f(s[3]))) or "1"
            line("object", { { "model", r.model }, { "scale", scale }, { "alpha", p.alpha or 255 },
                { "doublesided", tostring(p.ds == true) }, { "collisions", tostring(p.col ~= false) },
                { "frozen", tostring(p.frozen ~= false) }, { "breakable", tostring(p.brk == true) } })
        elseif r.etype == "vehicle" then
            local c = p.color and table.concat(p.color, ",") or nil
            line("vehicle", { { "model", r.model }, { "plate", p.plate }, { "color", c },
                { "upgrades", p.upg and table.concat(p.upg, ",") or nil }, { "paintjob", p.paintjob or 3 },
                { "locked", tostring(p.locked ~= false) }, { "frozen", tostring(p.frozen ~= false) },
                { "engine", tostring(p.engine == true) }, { "sirens", tostring(p.sirens == true) } })
        elseif r.etype == "ped" then
            line("ped", { { "model", r.model }, { "frozen", tostring(p.frozen ~= false) },
                { "animBlock", p.block }, { "anim", p.anim } })
        elseif r.etype == "marker" then
            line("marker", { { "type", p.mtype or "cylinder" }, { "size", f(p.size or 1.5) }, { "color", hex(p.color) },
                { "icon", p.icon }, { "label", p.label } })
        elseif r.etype == "pickup" then
            local ptype = PICKUP_NAMES[p.ptype] or (p.ptype == 2 and tostring(p.amount)) or "custom"
            line("pickup", { { "type", ptype }, { "amount", p.ptype == 2 and p.ammo or p.amount },
                { "model", p.ptype == 3 and p.amount or nil }, { "respawn", p.respawn } })
        elseif r.etype == "point" then
            line("spawnpoint", { { "model", 0 }, { "name", p.name } })
        elseif r.etype == "removal" then
            lines[#lines + 1] = ("    <removeWorldObject %s></removeWorldObject>"):format(attrs({
                { "id", id }, { "radius", f(p.radius or 1) }, { "interior", int }, { "model", r.model },
                { "lodModel", p.lod or 0 }, { "posX", f(r.x) }, { "posY", f(r.y) }, { "posZ", f(r.z) },
                { "rotX", 0 }, { "rotY", 0 }, { "rotZ", 0 } }))
        end
    end
    lines[#lines + 1] = "</map>"
    return table.concat(lines, "\n")
end

----------------------------------------------------------------
-- Importar
----------------------------------------------------------------
local function boolAttr(v, def)
    if v == nil or v == false then return def end
    v = tostring(v):lower()
    return v == "true" or v == "1"
end

local function parseHexColor(s)
    s = tostring(s or ""):gsub("#", "")
    if #s ~= 6 and #s ~= 8 then return nil end
    local c = {}
    for i = 1, #s, 2 do c[#c + 1] = tonumber(s:sub(i, i + 1), 16) or 255 end
    c[4] = c[4] or 255
    return c
end

local function splitNums(s)
    local out = {}
    for v in tostring(s or ""):gmatch("[^,%s]+") do out[#out + 1] = tonumber(v) end
    return out
end

local function loadXml(text)
    if xmlLoadString then
        local ok, node = pcall(xmlLoadString, text)
        if ok and node then return node end
    end
    -- respaldo: archivo temporal dentro del recurso
    local path = "exports/_import.tmp"
    local fh = fileCreate(path)
    if not fh then return nil end
    fileWrite(fh, text)
    fileClose(fh)
    local node = xmlLoadFile(path)
    if fileExists(path) and not node then fileDelete(path) end
    return node, path
end

function meParseMap(text)
    if type(text) ~= "string" or #text < 10 then return nil, "El texto está vacío." end
    if #text > MAPEDIT.MAX_IMPORT_BYTES then return nil, "El .map es demasiado grande." end
    local root, tmp = loadXml(text)
    if not root then return nil, "No es un XML válido." end
    local rows, skipped = {}, 0
    for _, node in ipairs(xmlNodeGetChildren(root)) do
        local tag = xmlNodeGetName(node)
        local a = xmlNodeGetAttributes(node) or {}
        local raw = { x = a.posX, y = a.posY, z = a.posZ, rx = a.rotX, ry = a.rotY, rz = a.rotZ, props = {} }
        local p = raw.props
        if tag == "object" then
            raw.etype, raw.model = "object", a.model
            local s = splitNums(a.scale)
            if #s == 3 then p.scale = s elseif s[1] then p.scale = s[1] end
            p.alpha = tonumber(a.alpha)
            p.ds = boolAttr(a.doublesided, false)
            p.col = boolAttr(a.collisions, true)
            p.frozen = boolAttr(a.frozen, true)
            p.brk = boolAttr(a.breakable, false)
        elseif tag == "vehicle" then
            raw.etype, raw.model = "vehicle", a.model
            local c = splitNums(a.color)
            if #c >= 3 then
                p.color = { c[1], c[2], c[3], c[4] or c[1], c[5] or c[2], c[6] or c[3] }
            end
            p.upg = splitNums(a.upgrades)
            p.plate = a.plate
            p.paintjob = tonumber(a.paintjob)
            p.locked = boolAttr(a.locked, true)
            p.frozen = boolAttr(a.frozen, true)
            p.engine = boolAttr(a.engine, false)
            p.sirens = boolAttr(a.sirens, false)
        elseif tag == "ped" then
            raw.etype, raw.model = "ped", a.model
            raw.rz = a.rotZ or a.rotation
            p.frozen = boolAttr(a.frozen, true)
            p.block, p.anim = a.animBlock, a.anim
        elseif tag == "marker" then
            raw.etype = "marker"
            p.mtype = a.type
            p.size = tonumber(a.size)
            p.color = parseHexColor(a.color)
            p.icon, p.label = a.icon, a.label
        elseif tag == "pickup" then
            raw.etype = "pickup"
            local t = tostring(a.type or "")
            if t == "health" then p.ptype, p.amount = 0, a.amount
            elseif t == "armor" or t == "armour" then p.ptype, p.amount = 1, a.amount
            elseif tonumber(t) then p.ptype, p.amount, p.ammo = 2, tonumber(t), a.amount
            else p.ptype, p.amount = 3, a.model end
            p.respawn = a.respawn
        elseif tag == "spawnpoint" then
            raw.etype = "point"
            raw.rz = a.rotZ or a.rotation
            p.name = a.name or a.id
        elseif tag == "removeWorldObject" then
            raw.etype, raw.model = "removal", a.model
            raw.rx, raw.ry, raw.rz = 0, 0, 0
            p.radius, p.lod = a.radius, a.lodModel
        end
        if raw.etype then rows[#rows + 1] = raw else skipped = skipped + 1 end
    end
    xmlUnloadFile(root)
    if tmp and fileExists(tmp) then fileDelete(tmp) end
    return rows, skipped
end

-- Guarda la exportación también en el recurso (exports/<nombre>.map) para descargarla del servidor
function meWriteExport(P, text)
    local safe = P.name:gsub("[^%w_%-]", "_")
    local path = "exports/" .. safe .. ".map"
    if fileExists(path) then fileDelete(path) end
    local fh = fileCreate(path)
    if not fh then return nil end
    fileWrite(fh, text)
    fileClose(fh)
    return path
end

----------------------------------------------------------------
-- Exports (otros recursos y rp_test)
----------------------------------------------------------------
-- validateMapElement({ etype, model, x, y, z, rx, ry, rz, props }) -> fila limpia | false, motivo
function validateMapElement(raw)
    local row, why = MapEditRules.element(raw, meModelOk)
    if not row then return false, why end
    return row
end

-- parseMapFile(xml) -> lista de filas válidas, descartadas | false, motivo
function parseMapFile(text)
    local raws, skipped = meParseMap(text)
    if not raws then return false, skipped end
    local out, bad = {}, skipped or 0
    for _, raw in ipairs(raws) do
        local row = MapEditRules.element(raw, meModelOk)
        if row then out[#out + 1] = row else bad = bad + 1 end
    end
    return out, bad
end

-- rowsToMapFile(filas, interior, dimension) -> texto .map
function rowsToMapFile(rows, interior, dimension)
    local P = { rows = {}, interior = tonumber(interior) or 0, dimension = tonumber(dimension) or 0 }
    for i, r in ipairs(type(rows) == "table" and rows or {}) do
        r.id = r.id or i
        P.rows[r.id] = r
    end
    return meExportMap(P)
end
