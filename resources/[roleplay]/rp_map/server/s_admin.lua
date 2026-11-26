--[[
    rp_map / server/s_admin.lua  (servidor)
    Administracion del mapa: la pestana "Admin" del mapa F11 manda estos eventos y aqui se
    revalida TODO (nivel de admin, tipos, rangos). Cada cambio se guarda en la BD y se
    reparte a los jugadores conectados.

    Admin (catalogo en rp_adminpanel/server/s_catalog.lua):
        /mapaprogreso <jugador|id personaje>   exploracion de un personaje
        /resetmapa <jugador|id personaje>      borra la exploracion de un personaje
]]

local ADMIN_LEVEL = 1

addEvent("rp:map:admin:open", true)
addEvent("rp:map:admin:placeSave", true)
addEvent("rp:map:admin:placeDelete", true)
addEvent("rp:map:admin:catSave", true)
addEvent("rp:map:admin:catDelete", true)
addEvent("rp:map:admin:sectorSave", true)
addEvent("rp:map:admin:settingsSave", true)
addEvent("rp:map:admin:playerQuery", true)
addEvent("rp:map:admin:playerReset", true)

local lastAction = {}

local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= ADMIN_LEVEL end

-- Admin valido y sin spam. Devuelve true si puede seguir.
local function guard(p)
    if not isAdmin(p) then
        Map.notify(p, "No tienes permiso para usar este comando.", "error")
        return false
    end
    if not Map.isReady() then return false end
    local now = getTickCount()
    if lastAction[p] and now - lastAction[p] < 300 then return false end
    lastAction[p] = now
    return true
end

local function audit(p, text)
    Map.log(("ADMIN %s (%s): %s"):format(getPlayerName(p), tostring(Map.characterOf(p)), text))
end

local function sendAdminData(p)
    local places = {}
    for _, pl in pairs(Map.getStaticPlaces()) do
        local o = Map.placeOut(pl)
        o.public = pl.public
        places[#places + 1] = o
    end
    local sectors = {}
    local over = Map.getSectorOver()
    for s, sec in ipairs(Map.getSectors()) do
        local o = over[sec.id] or {}
        sectors[s] = { id = sec.id, name = sec.name, city = sec.city, land = sec.land,
            customName = o.name, customCity = o.city, revealed = o.revealed == true }
    end
    triggerClientEvent(p, "rp:map:admin:data", resourceRoot, {
        places = places, cats = Map.categoryList(), sectors = sectors, settings = Map.getSettings(),
        icons = MAPA.ICONS, cities = MAPA_CITIES, defs = MAPA.SETTINGS,
    })
end

addEventHandler("rp:map:admin:open", resourceRoot, function()
    if not guard(client) then return end
    sendAdminData(client)
end)

----------------------------------------------------------------
-- Lugares
----------------------------------------------------------------
addEventHandler("rp:map:admin:placeSave", resourceRoot, function(data)
    local p = client
    if not guard(p) or type(data) ~= "table" then return end
    local name = Map.cleanText(data.name, 48)
    local desc = Map.cleanText(data.desc, 255) or ""
    local cat = type(data.cat) == "string" and Map.getCategories()[data.cat] and data.cat
    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z) or 0
    local public = data.public == true
    if not name or #name < 2 then return Map.notify(p, "El lugar necesita un nombre (2-48 letras).", "warning") end
    if not cat then return Map.notify(p, "Elige una categoría.", "warning") end
    if not Map.validCoord(x) or not Map.validCoord(y) or z ~= z or math.abs(z) > 2000 then
        return Map.notify(p, "Coordenadas fuera del mapa.", "warning")
    end
    local id = tonumber(data.id)
    local places = Map.getStaticPlaces()
    local con = Map.db()
    if id then
        local pl = places[id]
        if not pl then return Map.notify(p, "Ese lugar ya no existe.", "error") end
        dbExec(con, "UPDATE map_places SET name = ?, description = ?, cat_key = ?, x = ?, y = ?, z = ?, is_public = ? WHERE id = ?",
            name, desc, cat, x, y, z, public and 1 or 0, id)
        pl.name, pl.desc, pl.cat, pl.x, pl.y, pl.z, pl.public = name, desc, cat, x, y, z, public
        Map.indexPlaces()
        Map.pushPlacesAll()
        sendAdminData(p)
        audit(p, ("edita lugar #%d %s"):format(id, name))
        return Map.notify(p, ("Lugar #%d actualizado."):format(id), "success")
    end
    dbQuery(function(qh)
        local res, _, insertId = dbPoll(qh, 0)
        if not res or not insertId then return Map.notify(p, "No se pudo crear el lugar.", "error") end
        places[insertId] = { id = insertId, name = name, desc = desc, cat = cat, x = x, y = y, z = z, public = public, src = "db" }
        Map.indexPlaces()
        Map.pushPlacesAll()
        if isElement(p) then
            sendAdminData(p)
            audit(p, ("crea lugar #%d %s"):format(insertId, name))
            Map.notify(p, ("Lugar #%d creado: %s"):format(insertId, name), "success")
        end
    end, con, "INSERT INTO map_places (name, description, cat_key, x, y, z, is_public, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        name, desc, cat, x, y, z, public and 1 or 0, Map.characterOf(p))
end)

addEventHandler("rp:map:admin:placeDelete", resourceRoot, function(id)
    local p = client
    if not guard(p) then return end
    id = tonumber(id)
    local places = Map.getStaticPlaces()
    if not id or not places[id] then return Map.notify(p, "Ese lugar no existe.", "error") end
    local name = places[id].name
    dbExec(Map.db(), "DELETE FROM map_places WHERE id = ?", id)
    places[id] = nil
    Map.indexPlaces()
    Map.pushPlacesAll()
    sendAdminData(p)
    audit(p, ("borra lugar #%d %s"):format(id, name))
    Map.notify(p, ("Lugar #%d borrado."):format(id), "success")
end)

----------------------------------------------------------------
-- Categorias
----------------------------------------------------------------
local function validIcon(icon)
    for _, i in ipairs(MAPA.ICONS) do if i == icon then return true end end
    return false
end

addEventHandler("rp:map:admin:catSave", resourceRoot, function(data)
    local p = client
    if not guard(p) or type(data) ~= "table" then return end
    local key = type(data.key) == "string" and data.key:lower() or ""
    local name = Map.cleanText(data.name, 40)
    local icon = data.icon
    local color = type(data.color) == "string" and data.color:lower() or ""
    if not key:match("^[a-z0-9_]+$") or #key < 2 or #key > 24 then return Map.notify(p, "Clave inválida (2-24 letras minúsculas, números o _).", "warning") end
    if not name or #name < 2 then return Map.notify(p, "La categoría necesita un nombre.", "warning") end
    if not validIcon(icon) then return Map.notify(p, "Icono desconocido.", "warning") end
    if not color:match("^#%x%x%x%x%x%x$") then return Map.notify(p, "Color inválido (#rrggbb).", "warning") end
    local cats = Map.getCategories()
    local sort = cats[key] and cats[key].sort or 100
    dbExec(Map.db(), "INSERT INTO map_categories (cat_key, name, icon, color, is_public, sort) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), icon = VALUES(icon), color = VALUES(color), is_public = VALUES(is_public)",
        key, name, icon, color, data.public == true and 1 or 0, sort)
    cats[key] = { key = key, name = name, icon = icon, color = color, public = data.public == true, sort = sort }
    Map.pushConfigAll()
    sendAdminData(p)
    audit(p, "guarda categoría " .. key)
    Map.notify(p, "Categoría guardada: " .. name, "success")
end)

addEventHandler("rp:map:admin:catDelete", resourceRoot, function(key)
    local p = client
    if not guard(p) then return end
    local cats = Map.getCategories()
    if type(key) ~= "string" or not cats[key] then return Map.notify(p, "Esa categoría no existe.", "error") end
    for _, pl in pairs(Map.getStaticPlaces()) do
        if pl.cat == key then return Map.notify(p, "Hay lugares con esa categoría: cámbialos o bórralos antes.", "warning") end
    end
    for _, c in pairs(MAPA.BLIP_CATEGORIES) do
        if c == key then return Map.notify(p, "Esa categoría la usan puntos importados de otros recursos.", "warning") end
    end
    if key == "cajero" or key == "casa" or key == "apartamento" then
        return Map.notify(p, "Esa categoría la usan cajeros o casas importados.", "warning")
    end
    dbExec(Map.db(), "DELETE FROM map_categories WHERE cat_key = ?", key)
    cats[key] = nil
    Map.pushConfigAll()
    sendAdminData(p)
    audit(p, "borra categoría " .. key)
    Map.notify(p, "Categoría borrada.", "success")
end)

----------------------------------------------------------------
-- Cuadriculas (sectores)
----------------------------------------------------------------
addEventHandler("rp:map:admin:sectorSave", resourceRoot, function(sid, data)
    local p = client
    if not guard(p) or type(data) ~= "table" or not MapGrid.sectorIndex(sid) then return end
    local name = Map.cleanText(data.name, 40)
    local city = nil
    if type(data.city) == "string" then
        for _, c in ipairs(MAPA_CITIES) do if c == data.city then city = c end end
    end
    local revealed = data.revealed == true
    dbExec(Map.db(), "INSERT INTO map_sectors (sector_id, name, city, revealed) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), city = VALUES(city), revealed = VALUES(revealed)",
        sid, name, city, revealed and 1 or 0)
    Map.getSectorOver()[sid] = { name = name, city = city, revealed = revealed }
    Map.rebuildStartCells()
    Map.pushConfigAll()
    sendAdminData(p)
    audit(p, ("guarda cuadrícula %s (%s, visible desde el inicio: %s)"):format(sid, tostring(name), tostring(revealed)))
    Map.notify(p, "Cuadrícula " .. sid .. " guardada.", "success")
end)

----------------------------------------------------------------
-- Ajustes
----------------------------------------------------------------
addEventHandler("rp:map:admin:settingsSave", resourceRoot, function(data)
    local p = client
    if not guard(p) or type(data) ~= "table" then return end
    local settings = Map.getSettings()
    local con = Map.db()
    local changed = {}
    for key, def in pairs(MAPA.SETTINGS) do
        local v = tonumber(data[key])
        if v then
            if def[1] == "b" then v = v == 1 and 1 or 0 else v = math.floor(math.max(def[3], math.min(def[4], v))) end
            if settings[key] ~= v then
                settings[key] = v
                changed[#changed + 1] = key .. "=" .. v
                dbExec(con, "INSERT INTO map_settings (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)", key, tostring(v))
            end
        end
    end
    if #changed == 0 then return Map.notify(p, "No hay cambios.", "info") end
    Map.restartExploreTimer()
    Map.refreshDynamic(true)
    Map.pushConfigAll()
    sendAdminData(p)
    audit(p, "ajustes " .. table.concat(changed, ", "))
    Map.notify(p, "Ajustes del mapa guardados.", "success")
end)

----------------------------------------------------------------
-- Progreso de jugadores
----------------------------------------------------------------
-- Busca un jugador conectado (id o nombre) o, si es un numero sin jugador, un id de personaje.
local function resolveTarget(query)
    if type(query) ~= "string" and type(query) ~= "number" then return nil end
    query = tostring(query)
    local target = exports.rp_ids:findPlayer(query)
    if target and Map.characterOf(target) then return target, Map.characterOf(target) end
    local cid = tonumber(query:match("^#?(%d+)$"))
    if cid then
        for p, st in pairs(Map.getPlayers()) do if st.cid == cid then return p, cid end end
        return nil, cid
    end
    return nil
end

local function progressOf(target, cid, cb)
    local st = target and Map.getPlayers()[target]
    if st and st.loaded then
        local sectorsDone = 0
        for s, sec in ipairs(Map.getSectors()) do
            if sec.land > 0 and (st.sectorLand[s] or 0) >= math.ceil(sec.land * MAPA.SECTOR_DISCOVERED_PCT / 100) then sectorsDone = sectorsDone + 1 end
        end
        return cb({ name = getPlayerName(target):gsub("_", " "), cid = cid, online = true, land = st.landCount,
            pct = Map.percentOf(st.landCount, Map.getLandTotal()), sectors = sectorsDone, markers = #st.markers })
    end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local land = rows and rows[1] and tonumber(rows[1].explored) or 0
        cb({ name = rows and rows[1] and rows[1].name or ("Personaje #" .. cid), cid = cid, online = false, land = land,
            pct = Map.percentOf(land, Map.getLandTotal()) })
    end, Map.db(), "SELECT e.explored, c.name FROM characters c LEFT JOIN map_exploration e ON e.character_id = c.id WHERE c.id = ?", cid)
end

local function describe(info)
    return ("%s (personaje #%d%s): %.1f%% del mapa, %d celdas de tierra%s"):format(tostring(info.name), info.cid,
        info.online and ", conectado" or "", info.pct, info.land, info.sectors and (", %d cuadrículas completas"):format(info.sectors) or "")
end

local function resetTarget(admin, target, cid)
    if target and Map.getPlayers()[target] then
        Map.resetPlayer(target)
        Map.notify(target, "Un administrador reinició la exploración de tu mapa.", "warning")
    else
        dbExec(Map.db(), "DELETE FROM map_exploration WHERE character_id = ?", cid)
    end
    audit(admin, "reinicia la exploración del personaje #" .. cid)
    Map.notify(admin, ("Exploración del personaje #%d reiniciada."):format(cid), "success")
end

addEventHandler("rp:map:admin:playerQuery", resourceRoot, function(query)
    local p = client
    if not guard(p) then return end
    local target, cid = resolveTarget(query)
    if not cid then return triggerClientEvent(p, "rp:map:admin:player", resourceRoot, nil) end
    progressOf(target, cid, function(info)
        if isElement(p) then triggerClientEvent(p, "rp:map:admin:player", resourceRoot, info) end
    end)
end)

addEventHandler("rp:map:admin:playerReset", resourceRoot, function(cid)
    local p = client
    if not guard(p) then return end
    cid = tonumber(cid)
    if not cid then return end
    local target
    for pl, st in pairs(Map.getPlayers()) do if st.cid == cid then target = pl end end
    resetTarget(p, target, cid)
end)

addCommandHandler("mapaprogreso", function(p, _, query)
    if not isAdmin(p) then return Map.notify(p, "No tienes permiso para usar este comando.", "error") end
    local target, cid = resolveTarget(query)
    if not cid then return Map.notify(p, "Uso: /mapaprogreso <id o nombre de jugador | id de personaje>", "warning") end
    progressOf(target, cid, function(info) if isElement(p) then Map.notify(p, describe(info), "info", 8000) end end)
end)

addCommandHandler("resetmapa", function(p, _, query)
    if not isAdmin(p) then return Map.notify(p, "No tienes permiso para usar este comando.", "error") end
    local target, cid = resolveTarget(query)
    if not cid then return Map.notify(p, "Uso: /resetmapa <id o nombre de jugador | id de personaje>", "warning") end
    resetTarget(p, target, cid)
end)

addEventHandler("onPlayerQuit", root, function() lastAction[source] = nil end)
