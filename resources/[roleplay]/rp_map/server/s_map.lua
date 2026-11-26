--[[
    rp_map / server/s_map.lua  (servidor)

    Mapa F11 estilo GTA VI: el servidor es la unica fuente de verdad de
      - la exploracion de cada personaje (celdas de 50 m, niebla), que descubre el mismo
        leyendo la posicion del jugador cada pocos segundos (el cliente no puede marcar celdas);
      - los lugares del mapa (map_places + los que se importan de otros recursos) y cuales
        ve cada jugador (publicos o en una celda que ya exploro);
      - marcadores personales y preferencias.
    El cliente solo recibe lo que puede ver. Ver docs/MAPA.md.

    Exports (servidor):
        getPlayerExplorationPercent(player)  -> % de tierra explorada o nil
        revealPlayerArea(player, x, y, r)    -> descubre un area (misiones, eventos)
        getMapStats()                        -> { places, categories, sectors, landCells }
]]

Map = Map or {}

local players = {}       -- [player] = estado (ver loadPlayer)
local cooldown = {}      -- [player] = tick
local staticPlaces = {}  -- [id] = lugar de map_places
local dynPlaces = {}     -- [id texto] = lugar importado (blips, cajeros, casas)
local placesByCell = {}  -- [celda] = { lugar, ... }
local categories = {}    -- [clave] = categoria
local sectorOver = {}    -- [id sector] = { name, city, revealed }
local settings = {}      -- ajustes efectivos (MAPA.SETTINGS + map_settings)
local startCells = {}    -- [celda] = true: descubiertas para todos
local sectors, cellCity  -- MapGrid.buildSectors()
local landTotal = 0
local ready = false

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:map:request", true)
addEvent("rp:map:prefs", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function log(msg, level) outputDebugString("[rp_map] " .. msg, level or 3) end
Map.db, Map.notify, Map.log, Map.characterOf = db, notify, log, characterOf

-- Un cooldown por accion: que pedir el mapa no se coma el guardado de preferencias
local function takeCooldown(p, ms, key)
    local now = getTickCount()
    cooldown[p] = cooldown[p] or {}
    key = key or "default"
    if cooldown[p][key] and now - cooldown[p][key] < (ms or 250) then return false end
    cooldown[p][key] = now
    return true
end

local function cleanText(s, maxLen)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #s == 0 then return nil end
    if #s > maxLen then s = s:sub(1, maxLen) end
    return s
end
Map.cleanText = cleanText

local function validCoord(n) return type(n) == "number" and n == n and n >= -3000 and n <= 3000 end
Map.validCoord = validCoord

----------------------------------------------------------------
-- Ajustes, categorias, sectores
----------------------------------------------------------------
local function applySettingsDefaults()
    for key, def in pairs(MAPA.SETTINGS) do
        if settings[key] == nil then settings[key] = def[2] end
    end
end

function Map.getSettings() return settings end
function Map.getCategories() return categories end
function Map.getSectorOver() return sectorOver end
function Map.getSectors() return sectors end

-- Celdas visibles para todos: zonas de inicio + cuadriculas marcadas por los admins
function Map.rebuildStartCells()
    startCells = {}
    for _, z in ipairs(MAPA.START_ZONES) do
        MapGrid.eachCellInRadius(z[1], z[2], z[3], function(i) startCells[i] = true end)
    end
    for sid, o in pairs(sectorOver) do
        if o.revealed then
            local s = MapGrid.sectorIndex(sid)
            if s then
                local x1, y1, x2, y2 = MapGrid.sectorBounds(s)
                for x = x1 + 25, x2 - 25, 50 do
                    for y = y2 + 25, y1 - 25, 50 do
                        local c = MapGrid.cellOf(x, y)
                        if c then startCells[c] = true end
                    end
                end
            end
        end
    end
end

local function categoryList()
    local list = {}
    for _, c in pairs(categories) do list[#list + 1] = c end
    table.sort(list, function(a, b) return (a.sort or 0) < (b.sort or 0) end)
    return list
end
Map.categoryList = categoryList

----------------------------------------------------------------
-- Lugares
----------------------------------------------------------------
local function indexPlaces()
    placesByCell = {}
    local function add(pl)
        pl.cell = MapGrid.cellOf(pl.x, pl.y)
        if pl.cell then
            placesByCell[pl.cell] = placesByCell[pl.cell] or {}
            table.insert(placesByCell[pl.cell], pl)
        end
    end
    for _, pl in pairs(staticPlaces) do add(pl) end
    for _, pl in pairs(dynPlaces) do add(pl) end
end
Map.indexPlaces = indexPlaces

function Map.setStaticPlaces(list) staticPlaces = list; indexPlaces() end
function Map.getStaticPlaces() return staticPlaces end

local function isPublic(pl)
    if pl.public then return true end
    local c = categories[pl.cat]
    return c and c.public or false
end

local function canSee(st, pl)
    if not pl.cell then return false end
    if settings.fog == 0 or isPublic(pl) then return true end
    return st.cells[pl.cell] or startCells[pl.cell] or false
end

local function placeOut(pl)
    return { id = pl.id, name = pl.name, desc = pl.desc or "", cat = pl.cat, x = pl.x, y = pl.y, z = pl.z or 0, src = pl.src }
end
Map.placeOut = placeOut

-- st.adminView (solo admins, /mapajugador lo alterna): ve todos los lugares sin explorar
local function visiblePlaces(st)
    local list = {}
    local seeAll = st.adminView
    local function scan(t)
        for _, pl in pairs(t) do
            if (pl.src ~= "house" or settings.houses == 1) and categories[pl.cat] and pl.cell and (seeAll or canSee(st, pl)) then
                list[#list + 1] = placeOut(pl)
            end
        end
    end
    scan(staticPlaces)
    if settings.blips == 1 or settings.houses == 1 then scan(dynPlaces) end
    return list
end

-- Totales por ciudad (sin posiciones) para "lugares pendientes"
local function placeTotals()
    local totals = { all = 0, city = {} }
    local function scan(t)
        for _, pl in pairs(t) do
            if categories[pl.cat] and (pl.src ~= "house" or settings.houses == 1) then
                local city = pl.cell and cellCity[pl.cell] or getZoneName(pl.x, pl.y, 30, true)
                totals.all = totals.all + 1
                totals.city[city] = (totals.city[city] or 0) + 1
            end
        end
    end
    scan(staticPlaces)
    if settings.blips == 1 or settings.houses == 1 then scan(dynPlaces) end
    return totals
end

-- Nombre singular de la categoria (Gasolineras -> Gasolinera) para los puntos importados
local SINGULAR = {
    hospital = "Emergencias", policia = "Policía", tienda = "Tienda", super = "Tienda 24/7", restaurante = "Restaurante",
    gasolinera = "Gasolinera", cajero = "Cajero", concesionario = "Concesionario", taller = "Taller",
    transporte = "Arriendo de bicicletas", trabajo = "Trabajo",
}

-- Importa puntos de otros recursos: blips con icono conocido, cajeros (rp:atm) y casas (rp:property).
-- Ids estables a partir de la posicion para que no "parpadeen" entre refrescos.
local function nearStatic(cat, x, y)
    for _, pl in pairs(staticPlaces) do
        if pl.cat == cat and math.abs(pl.x - x) < 40 and math.abs(pl.y - y) < 40 then return true end
    end
    return false
end

function Map.refreshDynamic(force)
    local found, sig = {}, {}
    if settings.blips == 1 then
        for _, blip in ipairs(getElementsByType("blip")) do
            local cat = MAPA.BLIP_CATEGORIES[getBlipIcon(blip)]
            if cat and getElementDimension(blip) == 0 and getElementInterior(blip) == 0 then
                local x, y, z = getElementPosition(blip)
                if validCoord(x) and validCoord(y) and not nearStatic(cat, x, y) then
                    local id = ("b%d_%d"):format(math.floor(x), math.floor(y))
                    local owner = getElementAttachedTo(blip)
                    local name = owner and getElementData(owner, "rp:shopName")
                    local zone = getZoneName(x, y, z)
                    found[id] = { id = id, src = "blip", cat = cat, x = x, y = y, z = z,
                        name = type(name) == "string" and name or ((SINGULAR[cat] or "Lugar") .. " de " .. zone),
                        desc = zone .. ", " .. getZoneName(x, y, z, true) }
                end
            end
        end
        for _, obj in ipairs(getElementsByType("object")) do
            local atm = getElementData(obj, "rp:atm")
            if atm and getElementDimension(obj) == 0 and getElementInterior(obj) == 0 then
                local x, y, z = getElementPosition(obj)
                local id = "a" .. tostring(atm)
                local zone = getZoneName(x, y, z)
                found[id] = { id = id, src = "atm", cat = "cajero", x = x, y = y, z = z, name = "Cajero de " .. zone,
                    desc = "Retira, deposita y transfiere dinero. " .. zone .. "." }
            end
        end
    end
    if settings.houses == 1 then
        for _, pk in ipairs(getElementsByType("pickup")) do
            local info = getElementData(pk, "rp:property")
            if type(info) == "table" and info.id and getElementDimension(pk) == 0 and getElementInterior(pk) == 0 then
                local x, y, z = getElementPosition(pk)
                local tname = tostring(info.typeName or "")
                local cat = (tname:lower():find("apart") or tname:lower():find("depart")) and "apartamento" or "casa"
                local status = info.owner and ("Propietario: " .. tostring(info.owner)) or ("En venta por $" .. tostring(info.price or 0))
                local id = "h" .. tostring(info.id)
                found[id] = { id = id, src = "house", cat = cat, x = x, y = y, z = z,
                    name = tostring(info.name or "Propiedad"), desc = tname .. ". " .. status }
            end
        end
    end
    for id, pl in pairs(found) do sig[#sig + 1] = id .. pl.name .. pl.desc end
    table.sort(sig)
    local newSig = table.concat(sig, "|")
    if not force and newSig == Map.dynSig then return end
    Map.dynSig = newSig
    dynPlaces = found
    indexPlaces()
    Map.pushPlacesAll()
end

----------------------------------------------------------------
-- Envio al cliente
----------------------------------------------------------------
local function sectorOverList()
    local out = {}
    for sid, o in pairs(sectorOver) do out[sid] = { name = o.name, city = o.city, revealed = o.revealed } end
    return out
end

local function cellsList(st)
    local list = {}
    for i in pairs(st.cells) do list[#list + 1] = i end
    return list
end

local function startList()
    local list = {}
    for i in pairs(startCells) do list[#list + 1] = i end
    return list
end

local function sendInit(p)
    local st = players[p]
    if not st or not st.loaded then return end
    triggerClientEvent(p, "rp:map:init", resourceRoot, {
        cells = cellsList(st), start = startList(), places = visiblePlaces(st), cats = categoryList(),
        sectors = sectorOverList(), settings = settings, prefs = st.prefs,
        totals = placeTotals(), isAdmin = (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1, adminView = st.adminView == true,
    })
end
Map.sendInit = sendInit

function Map.pushPlacesAll()
    for p, st in pairs(players) do
        if st.loaded then
            triggerClientEvent(p, "rp:map:places", resourceRoot, visiblePlaces(st), placeTotals())
        end
    end
end

function Map.pushConfigAll()
    local data = { cats = categoryList(), sectors = sectorOverList(), settings = settings, start = startList() }
    for p, st in pairs(players) do
        if st.loaded then triggerClientEvent(p, "rp:map:config", resourceRoot, data) end
    end
    Map.pushPlacesAll()
end

----------------------------------------------------------------
-- Carga / guardado por personaje
----------------------------------------------------------------
local function countSectors(st)
    st.sectorLand, st.landCount = {}, 0
    for i in pairs(st.cells) do
        if MapGrid.isLand(i) then
            local s = MapGrid.sectorOfCell(i)
            st.sectorLand[s] = (st.sectorLand[s] or 0) + 1
            st.landCount = st.landCount + 1
        end
    end
end

local function savePlayer(p)
    local st = players[p]
    if not st or not st.loaded or not st.dirty then return end
    st.dirty = false
    dbExec(db(), "INSERT INTO map_exploration (character_id, cells, explored) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE cells = VALUES(cells), explored = VALUES(explored)",
        st.cid, MapGrid.encode(st.cells), st.landCount)
end
Map.savePlayer = savePlayer

local function loadPlayer(p, cid)
    if players[p] and players[p].cid == cid then sendInit(p); return end
    if players[p] then savePlayer(p) end
    local st = { cid = cid, cells = {}, landCount = 0, sectorLand = {}, prefs = {}, loaded = false, pending = 2,
        adminView = (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 }
    players[p] = st
    local function done()
        st.pending = st.pending - 1
        if st.pending == 0 and players[p] == st then
            st.loaded = true
            countSectors(st)
            sendInit(p)
        end
    end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if players[p] ~= st then return end
        if rows and rows[1] then st.cells = MapGrid.decode(rows[1].cells) end
        done()
    end, db(), "SELECT cells FROM map_exploration WHERE character_id = ?", cid)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if players[p] ~= st then return end
        if rows and rows[1] then st.prefs = fromJSON(rows[1].prefs) or {} end
        done()
    end, db(), "SELECT prefs FROM map_prefs WHERE character_id = ?", cid)
end

local function unloadPlayer(p)
    savePlayer(p)
    players[p] = nil
    cooldown[p] = nil
end

----------------------------------------------------------------
-- Exploracion: el servidor mira donde esta cada jugador y descubre celdas
----------------------------------------------------------------
local function percentOf(n, total) return total > 0 and math.floor(n / total * 1000 + 0.5) / 10 or 0 end

local function reveal(p, st, list)
    local newPlaces, sectorsDone = {}, {}
    for _, i in ipairs(list) do
        if MapGrid.isLand(i) then
            local s = MapGrid.sectorOfCell(i)
            local before = st.sectorLand[s] or 0
            st.sectorLand[s] = before + 1
            st.landCount = st.landCount + 1
            local land = sectors[s].land
            local need = math.ceil(land * MAPA.SECTOR_DISCOVERED_PCT / 100)
            if land > 0 and before < need and before + 1 >= need then sectorsDone[#sectorsDone + 1] = s end
        end
        if not startCells[i] and settings.fog == 1 and not st.adminView then
            for _, pl in ipairs(placesByCell[i] or {}) do
                if not isPublic(pl) and categories[pl.cat] and (pl.src ~= "house" or settings.houses == 1) then
                    newPlaces[#newPlaces + 1] = placeOut(pl)
                end
            end
        end
    end
    st.dirty = true
    triggerClientEvent(p, "rp:map:cells", resourceRoot, list, newPlaces)
    for _, s in ipairs(sectorsDone) do
        local o = sectorOver[sectors[s].id] or {}
        notify(p, ("Cuadrícula %s descubierta: %s"):format(sectors[s].id, o.name or sectors[s].name), "success")
    end
    if #newPlaces == 1 then
        notify(p, "Nuevo lugar en tu mapa: " .. newPlaces[1].name, "info")
    elseif #newPlaces > 1 then
        notify(p, ("%d lugares nuevos en tu mapa (F11)"):format(#newPlaces), "info")
    end
end

local function explorePlayer(p, st, now)
    if getElementInterior(p) ~= 0 or getElementDimension(p) ~= 0 then st.lastX = nil; return end
    local x, y = getElementPosition(p)
    if not validCoord(x) or not validCoord(y) then return end
    local r = settings.radius
    local veh = getPedOccupiedVehicle(p)
    if veh then
        local vt = getVehicleType(veh)
        if vt == "Plane" or vt == "Helicopter" then r = r * MAPA.AIR_FACTOR end
    end
    local new = {}
    local function revealAt(px, py, rr)
        MapGrid.eachCellInRadius(px, py, rr, function(i)
            if not st.cells[i] then st.cells[i] = true; new[#new + 1] = i end
        end)
    end
    if st.lastX then
        local d = getDistanceBetweenPoints2D(st.lastX, st.lastY, x, y)
        local dt = math.max(0.25, (now - st.lastTick) / 1000)
        if d > MAPA.TELEPORT_METERS then
            revealAt(x, y, r)
        else
            local kmh = d / dt * 3.6
            local f = kmh > MAPA.SPEED_FULL_KMH and math.max(MAPA.SPEED_MIN_FACTOR, MAPA.SPEED_FULL_KMH / kmh) or 1
            local rr = r * f
            local steps = math.max(1, math.ceil(d / math.max(rr, 15)))
            for k = 1, steps do
                local t = k / steps
                revealAt(st.lastX + (x - st.lastX) * t, st.lastY + (y - st.lastY) * t, rr)
            end
        end
    else
        revealAt(x, y, r)
    end
    st.lastX, st.lastY, st.lastTick = x, y, now
    if #new > 0 then reveal(p, st, new) end
end

local exploreTimer
function Map.restartExploreTimer()
    if isTimer(exploreTimer) then killTimer(exploreTimer) end
    exploreTimer = setTimer(function()
        local now = getTickCount()
        for p, st in pairs(players) do
            if st.loaded and isElement(p) then explorePlayer(p, st, now) end
        end
    end, settings.interval, 0)
end

----------------------------------------------------------------
-- Eventos del cliente
----------------------------------------------------------------
addEventHandler("rp:map:request", resourceRoot, function()
    if not takeCooldown(client, 1000, "request") then return end
    local cid = characterOf(client)
    if not cid or not ready then return end
    loadPlayer(client, cid)
end)

-- Preferencias: solo claves conocidas y con tipo correcto
addEventHandler("rp:map:prefs", resourceRoot, function(prefs)
    local p = client
    local st = players[p]
    if not st or not st.loaded or type(prefs) ~= "table" or not takeCooldown(p, 300, "prefs") then return end
    local clean = {}
    if prefs.mode == "2d" or prefs.mode == "3d" then clean.mode = prefs.mode end
    clean.tutorial = prefs.tutorial == true or st.prefs.tutorial == true   -- una vez visto, no vuelve
    clean.grid = prefs.grid ~= false
    if type(prefs.hidden) == "table" then
        clean.hidden = {}
        local n = 0
        for k, v in pairs(prefs.hidden) do
            if type(k) == "string" and categories[k] and v == true and n < 64 then clean.hidden[k] = true; n = n + 1 end
        end
    end
    st.prefs = clean
    dbExec(db(), "INSERT INTO map_prefs (character_id, prefs) VALUES (?, ?) ON DUPLICATE KEY UPDATE prefs = VALUES(prefs)",
        st.cid, toJSON(clean, true))
end)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    if ready and characterId then loadPlayer(source, characterId) end
end)

addEventHandler("rp:onCharacterLogout", root, function() unloadPlayer(source) end)
addEventHandler("onPlayerQuit", root, function() unloadPlayer(source) end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(players) do savePlayer(p) end
end)

-- Carga de categorias, lugares, sectores y ajustes (y siembra la primera vez)
local function loadWorld(onDone)
    local con = db()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, r in ipairs(rows) do
            local def = MAPA.SETTINGS[r.setting_key]
            local v = tonumber(r.setting_value)
            if def and v then
                if def[1] == "b" then v = v == 1 and 1 or 0 else v = math.max(def[3], math.min(def[4], v)) end
                settings[r.setting_key] = v
            elseif r.setting_key:sub(1, 7) == "seeded_" then
                settings[r.setting_key] = 1
            end
        end
        applySettingsDefaults()

        local function seedThen(fn)
            if settings.seeded_categories ~= 1 then
                for i, c in ipairs(MAPA.CATEGORIES) do
                    dbExec(con, "INSERT IGNORE INTO map_categories (cat_key, name, icon, color, is_public, sort) VALUES (?, ?, ?, ?, ?, ?)",
                        c.key, c.name, c.icon, c.color, c.public and 1 or 0, i)
                end
                dbExec(con, "INSERT IGNORE INTO map_settings (setting_key, setting_value) VALUES ('seeded_categories', '1')")
                settings.seeded_categories = 1
            end
            if settings.seeded_places ~= 1 then
                for _, s in ipairs(MAP_SEED) do
                    dbExec(con, "INSERT IGNORE INTO map_places (seed_key, name, description, cat_key, x, y, z) VALUES (?, ?, ?, ?, ?, ?, ?)",
                        s[1], s[2], s[7], s[3], s[4], s[5], s[6])
                end
                dbExec(con, "INSERT IGNORE INTO map_settings (setting_key, setting_value) VALUES ('seeded_places', '1')")
                settings.seeded_places = 1
            end
            fn()
        end

        seedThen(function()
            dbQuery(function(qh2)
                local cats = dbPoll(qh2, 0) or {}
                categories = {}
                for _, c in ipairs(cats) do
                    categories[c.cat_key] = { key = c.cat_key, name = c.name, icon = c.icon, color = c.color,
                        public = tonumber(c.is_public) == 1, sort = tonumber(c.sort) or 0 }
                end
                dbQuery(function(qh3)
                    local rows3 = dbPoll(qh3, 0) or {}
                    local list = {}
                    for _, r in ipairs(rows3) do
                        list[r.id] = { id = r.id, name = r.name, desc = r.description, cat = r.cat_key, x = r.x, y = r.y, z = r.z,
                            public = tonumber(r.is_public) == 1, src = "db" }
                    end
                    staticPlaces = list
                    dbQuery(function(qh4)
                        local rows4 = dbPoll(qh4, 0) or {}
                        sectorOver = {}
                        for _, r in ipairs(rows4) do
                            sectorOver[r.sector_id] = { name = r.name ~= false and r.name or nil, city = r.city ~= false and r.city or nil,
                                revealed = tonumber(r.revealed) == 1 }
                        end
                        onDone()
                    end, con, "SELECT sector_id, name, city, revealed FROM map_sectors")
                end, con, "SELECT id, name, description, cat_key, x, y, z, is_public FROM map_places")
            end, con, "SELECT cat_key, name, icon, color, is_public, sort FROM map_categories")
        end)
    end, con, "SELECT setting_key, setting_value FROM map_settings")
end

local function start()
    if ready then return end
    sectors, cellCity = MapGrid.buildSectors()
    landTotal = 0
    for _, s in ipairs(sectors) do landTotal = landTotal + s.land end
    loadWorld(function()
        Map.rebuildStartCells()
        indexPlaces()
        ready = true
        Map.refreshDynamic(true)
        Map.restartExploreTimer()
        setTimer(function() Map.refreshDynamic(false) end, 30000, 0)
        setTimer(function() for p in pairs(players) do savePlayer(p) end end, MAPA.SAVE_INTERVAL_MS, 0)
        local n = 0
        for _ in pairs(staticPlaces) do n = n + 1 end
        log(("listo: %d lugares, %d celdas de tierra, %d sectores"):format(n, landTotal, #sectors))
        -- Rehidratar a los que ya estan dentro (reinicio en caliente)
        for _, p in ipairs(getElementsByType("player")) do
            local cid = characterOf(p)
            if cid then loadPlayer(p, cid) end
        end
    end)
end

addEventHandler("rp:onDatabaseReady", root, start)
addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then start() end
end)

----------------------------------------------------------------
-- Para s_admin.lua
----------------------------------------------------------------
function Map.getPlayers() return players end
function Map.getLandTotal() return landTotal end
function Map.percentOf(n, total) return percentOf(n, total) end
function Map.isReady() return ready end
function Map.setAdminView(p, on)
    local st = players[p]
    if not st or not st.loaded then return false end
    st.adminView = on == true
    sendInit(p)
    return true
end

function Map.resetPlayer(p)
    local st = players[p]
    if not st then return false end
    st.cells, st.lastX = {}, nil
    countSectors(st)
    st.dirty = true
    savePlayer(p)
    sendInit(p)
    return true
end

----------------------------------------------------------------
-- Exports
----------------------------------------------------------------
function getPlayerExplorationPercent(player)
    local st = players[player]
    if not st or not st.loaded then return nil end
    return percentOf(st.landCount, landTotal)
end

function revealPlayerArea(player, x, y, r)
    local st = players[player]
    if not st or not st.loaded or not validCoord(x) or not validCoord(y) then return false end
    local new = {}
    MapGrid.eachCellInRadius(x, y, math.max(10, math.min(1000, tonumber(r) or 100)), function(i)
        if not st.cells[i] then st.cells[i] = true; new[#new + 1] = i end
    end)
    if #new > 0 then reveal(player, st, new) end
    return true
end

function getMapStats()
    local n, c = 0, 0
    for _ in pairs(staticPlaces) do n = n + 1 end
    for _ in pairs(dynPlaces) do n = n + 1 end
    for _ in pairs(categories) do c = c + 1 end
    return { places = n, categories = c, sectors = sectors and #sectors or 0, landCells = landTotal, ready = ready }
end
