--[[
    rp_phone / s_tinder_npcs.lua
    Personas simuladas de Tinder. Cada NPC nace de un arquetipo (s_tinder_data.lua) con skin,
    edad, barrio, trabajo, gustos, biografia, respuestas del perfil y una forma de escribir.

    La simulacion:
      - Tu like no es match al instante: el NPC "ve" tu perfil minutos despues y decide segun
        lo exigente que es, lo completo que esta tu perfil, los gustos en comun y la edad.
        Si ya te habia dado like (sale en "Le gustas"), el match es inmediato.
      - Mientras estas conectado, algunos NPC te dan like solos (mas si tu perfil es bueno).
      - Tras el match, algunos escriben primero. En el chat cada NPC tiene un interes oculto
        en ti (0-100) que sube o baja con lo que escribes: preguntas, gustos en comun, humor,
        cumplidos a destiempo, groserias, mensajes vacios, dejarle en visto, escribir 5 seguidos...
      - Contestan con retraso (rapidos o lentos segun su energia, y duermen de noche), marcan
        "Visto", aparecen "escribiendo...", mandan varias burbujas, preguntan cosas, recuerdan
        lo que ya hablaron, insisten si los ignoras, te ghostean o deshacen el match.
      - Con interes alto aceptan una cita (o la proponen) y te dan su numero: se crea un vinculo
        en rp_npcrel y al llamarle viene a verte al mundo.
      - Fotos: las saca el estudio (/tinderstudio, admin) en el mundo real de San Andreas con la
        hora y el clima de cada escenario; hasta entonces la app dibuja un fondo del escenario.

    Tablas: tinder_npcs, tinder_npc_photos, tinder_npc_links, tinder_npc_messages.
]]

local T = Tinder

T.npcs = {}          -- [id] = npc
local npcList = {}   -- lista para recorrer
local busyLink = {}  -- ["char:npc"] = true mientras se procesa
local typingSent = {}-- [messageId] = true
local studio = {}    -- [player] = { ids = {[photoId]=true} }
local ready = false

addEvent("rp:onDatabaseReady", false)
addEvent("rp:npcrel:dateContact", false)
addEvent("rp:tinder:studio:photo", true)
addEvent("rp:tinder:studio:next", true)
addEvent("rp:tinder:studio:stop", true)

local isNull = T.isNull
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function pick(list) return list[math.random(#list)] end
local function rand(a, b) return a + math.random() * (b - a) end
local function keyOf(characterId, npcId) return characterId .. ":" .. npcId end

local function shuffle(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    for i = #out, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

----------------------------------------------------------------
-- Texto: normalizar, rellenar y "ensuciar" segun como escribe cada NPC
----------------------------------------------------------------
local ACCENTS = { ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n",
                  ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ñ"] = "n" }
local function normalize(s)
    s = tostring(s or ""):lower()
    for k, v in pairs(ACCENTS) do s = s:gsub(k, v) end
    s = s:gsub("¿", ""):gsub("¡", "")   -- caracteres de 2 bytes: nunca en una clase [..]
    return s
end
T.normalize = normalize

local function stripAccents(s)
    for k, v in pairs(ACCENTS) do
        if k:lower() == k then s = s:gsub(k, v) end
    end
    return s
end

local function lowerFirst(s)
    local first = s:sub(1, 1)
    if first:match("%u") then return first:lower() .. s:sub(2) end
    return s
end
local function upperFirst(s)
    local first = s:sub(1, 1)
    if first:match("%l") then return first:upper() .. s:sub(2) end
    return s
end

local function fill(text, ctx)
    local npc = ctx.npc
    for _ = 1, 2 do   -- dos pasadas: {jobtalk} trae {job} y {z} dentro
        text = text:gsub("{(%w+)}", function(k)
            if k == "o" then return npc.gender == 1 and "a" or "o" end
            if k == "pe" then return ctx.playerGender == 1 and "a" or "o" end
            if k == "p" then return ctx.playerName or "" end
            if k == "n" then return npc.first end
            if k == "z" then return npc.zoneT and npc.zoneT.label or "" end
            if k == "c" then return npc.zoneT and npc.zoneT.city or "" end
            if k == "job" then return npc.job:sub(1, 1):lower() .. npc.job:sub(2) end
            if k == "age" then return tostring(npc.age) end
            if k == "i1" or k == "i2" then
                local it = TINDER_INTEREST_BY_ID[npc.interests[k == "i1" and 1 or 2] or npc.interests[1]]
                return it and it.label:lower() or "salir"
            end
            if ctx[k] ~= nil then return tostring(ctx[k]) end
            return "{" .. k .. "}"
        end)
    end
    return text
end

local LAUGHS = { "jaja", "jajaja", "jajaj", "JAJAJA", "jsjsjs", "jajsj", "jeje", "haha", "jajajaja" }

local function stylize(text, npc)
    local t = npc.traits
    local s = text
    if t.laugh and t.laugh ~= "jaja" then s = s:gsub("[jJ][aA][jJ][aA]+[jJ]?", t.laugh) end
    if t.sloppy > 0.55 then
        s = s:gsub("¿", ""):gsub("¡", "")
        if math.random() < t.sloppy - 0.2 then s = stripAccents(s) end
        if math.random() < t.sloppy * 0.6 then s = s:gsub("(%s)que(%s)", "%1q%2"):gsub("^que ", "q ") end
        s = s:gsub("porque", math.random() < t.sloppy * 0.5 and "xq" or "porque")
        s = s:gsub("también", math.random() < t.sloppy * 0.5 and "tmb" or "también")
        s = s:gsub("por favor", "porfa")
        if math.random() < t.sloppy then s = lowerFirst(s) end
        s = s:gsub("%.$", "")
    elseif t.sloppy < 0.25 then
        s = upperFirst(s)
    end
    if t.energy > 0.75 and math.random() < 0.18 then
        s = s:gsub("!$", "!!"):gsub("(%a)$", "%1%1")
    end
    if math.random() < t.emoji * 0.45 and not s:find("[\240-\244]") then
        s = s .. " " .. pick(npc.arch.emojis)
    end
    return s
end

----------------------------------------------------------------
-- NPC: carga y generacion
----------------------------------------------------------------
local function npcFromRow(r)
    local arch = TINDER_ARCHETYPE_BY_ID[r.archetype] or TINDER_ARCHETYPES[1]
    local traits = r.traits and r.traits ~= "" and fromJSON(r.traits) or nil
    if type(traits) ~= "table" then traits = {} end
    for k, range in pairs(arch.traits) do
        if type(traits[k]) ~= "number" then traits[k] = (range[1] + range[2]) / 2 end
    end
    local prompts = r.prompts and fromJSON(r.prompts) or nil
    local npc = {
        id = tonumber(r.id), name = r.name, first = T.firstName(r.name), age = tonumber(r.age),
        gender = tonumber(r.gender) == 1 and 1 or 0, skin = tonumber(r.skin), arch = arch, archId = arch.id,
        job = r.job or "", zone = r.zone, zoneT = TINDER_ZONES[r.zone] or TINDER_ZONES.ganton,
        bio = r.bio or "", interests = T.parseInterests(r.interests), prompts = type(prompts) == "table" and prompts or {},
        traits = traits, likes = r.likes or "a", ageMin = tonumber(r.age_min) or 18, ageMax = tonumber(r.age_max) or 70,
        thumb = nil, scene = nil, photoCount = 0,
    }
    return npc
end

local function rollLikes(gender)
    local r = math.random()
    if r < 0.1 then return "a" end
    local target = r < 0.2 and gender or (1 - gender)
    return target == 1 and "f" or "m"
end

local function weightedArchetype()
    local total = 0
    for _, a in ipairs(TINDER_ARCHETYPES) do total = total + (a.weight or 1) end
    local r = math.random() * total
    for _, a in ipairs(TINDER_ARCHETYPES) do
        r = r - (a.weight or 1)
        if r <= 0 then return a end
    end
    return TINDER_ARCHETYPES[1]
end

-- Fotos de un NPC: la primera siempre con la persona; un paisaje como mucho
local function planPhotos(arch)
    local count = math.random(3, 4)
    local scenes = shuffle(arch.scenes)
    local poses = shuffle(arch.poses)
    local plan, landscape = {}, false
    for slot = 1, count do
        local pose = poses[(slot - 1) % #poses + 1]
        if slot == 1 and (pose == "paisaje" or pose == "auto") then pose = math.random() < 0.6 and "selfie" or "portrait" end
        if pose == "paisaje" then
            if landscape then pose = "full" end
            landscape = true
        end
        if pose == "auto" and not arch.cars then pose = "full" end
        local scene = scenes[(slot - 1) % #scenes + 1]
        if not TINDER_SCENES[scene] then scene = "beach_sunset" end
        plan[#plan + 1] = { slot = slot, scene = scene, pose = pose }
    end
    return plan
end

local function generateOne(gender, callback)
    local arch
    for _ = 1, 20 do
        local a = weightedArchetype()
        for _, g in ipairs(a.genders) do if g == gender then arch = a break end end
        if arch then break end
    end
    arch = arch or TINDER_ARCHETYPES[1]
    local age = math.random(arch.age[1], arch.age[2])
    local zone = pick(arch.zones)
    local traits = {}
    for k, range in pairs(arch.traits) do traits[k] = math.floor(rand(range[1], range[2]) * 100 + 0.5) / 100 end
    traits.laugh = traits.sloppy > 0.6 and pick(LAUGHS) or pick({ "jaja", "jajaja", "haha" })
    local interests, seen = {}, {}
    for _, id in ipairs(shuffle(arch.core)) do
        if #interests < 3 and not seen[id] then seen[id] = true interests[#interests + 1] = id end
    end
    for _, id in ipairs(shuffle(arch.extra)) do
        if #interests < math.random(4, 5) and not seen[id] then seen[id] = true interests[#interests + 1] = id end
    end
    local name = pick(TINDER_FIRST[gender]) .. " " .. pick(TINDER_LAST)
    local tmp = { gender = gender, first = T.firstName(name), age = age, zoneT = TINDER_ZONES[zone], interests = interests,
                  job = "", traits = traits, arch = arch }
    local job = fill(pick(arch.jobs[gender]), { npc = tmp })
    tmp.job = job
    local bio = fill(pick(arch.bios), { npc = tmp })
    if math.random() < 0.5 then bio = bio .. " " .. pick(arch.emojis) end
    if traits.sloppy > 0.85 then bio = stripAccents(bio) end
    local promptKeys = {}
    for k in pairs(arch.prompts) do promptKeys[#promptKeys + 1] = k end
    table.sort(promptKeys)
    local prompts = {}
    for i, k in ipairs(shuffle(promptKeys)) do
        if i > math.random(2, 3) then break end
        prompts[#prompts + 1] = { k = k, a = fill(pick(arch.prompts[k]), { npc = tmp }) }
    end
    local ageMin = math.max(18, age - math.random(3, 9))
    local ageMax = math.min(80, age + math.random(4, 12))

    dbQuery(function(qh)
        local _, _, id = dbPoll(qh, 0)
        if not id then return callback(false) end
        for _, ph in ipairs(planPhotos(arch)) do
            dbExec(T.db(), "INSERT IGNORE INTO tinder_npc_photos (npc_id, slot, scene, pose) VALUES (?, ?, ?, ?)", id, ph.slot, ph.scene, ph.pose)
        end
        callback(true)
    end, T.db(), [[
        INSERT INTO tinder_npcs (name, age, gender, skin, archetype, job, zone, home_x, home_y, bio, interests, prompts, traits, likes, age_min, age_max)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], name, age, gender, pick(arch.skins[gender]), arch.id, job, zone, TINDER_ZONES[zone].x, TINDER_ZONES[zone].y,
        bio, table.concat(interests, ","), toJSON(prompts, true), toJSON(traits, true), rollLikes(gender), ageMin, ageMax)
end

local function loadNpcs(callback)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return callback and callback(false) end
        T.npcs, npcList = {}, {}
        for _, r in ipairs(rows) do
            local npc = npcFromRow(r)
            T.npcs[npc.id] = npc
            npcList[#npcList + 1] = npc
        end
        dbQuery(function(qh2)
            local photos = dbPoll(qh2, 0) or {}
            for _, p in ipairs(photos) do
                local npc = T.npcs[tonumber(p.npc_id)]
                if npc then
                    npc.photoCount = npc.photoCount + 1
                    if not npc.scene then npc.scene = p.scene end
                    if not npc.thumb and p.thumb and p.pose ~= "paisaje" then npc.thumb = p.thumb end
                end
            end
            if callback then callback(true) end
        end, T.db(), "SELECT npc_id, slot, scene, pose, thumb FROM tinder_npc_photos ORDER BY npc_id, slot")
    end, T.db(), "SELECT * FROM tinder_npcs ORDER BY id")
end

local function ensureNpcs()
    local missing = TINDER.NPC_TARGET - #npcList
    if missing <= 0 then
        ready = true
        return outputDebugString(("[rp_phone] Tinder: %d personas simuladas cargadas"):format(#npcList), 3)
    end
    local males = 0
    for _, n in ipairs(npcList) do if n.gender == 0 then males = males + 1 end end
    local done = 0
    local function step()
        if done >= missing then
            return loadNpcs(function()
                ready = true
                outputDebugString(("[rp_phone] Tinder: generadas %d personas simuladas (total %d). Fotos: /tinderstudio"):format(missing, #npcList), 3)
            end)
        end
        local gender = (males <= #npcList + done - males) and 0 or 1
        if gender == 0 then males = males + 1 end
        generateOne(gender, function()
            done = done + 1
            step()
        end)
    end
    step()
end

local starting = false
local function start()
    if starting then return end
    starting = true
    loadNpcs(function(ok)
        if ok then ensureNpcs() else starting = false end
    end)
end
addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() == true then start() end
end)
addEventHandler("rp:onDatabaseReady", root, start)

----------------------------------------------------------------
-- Compatibilidad, atraccion y actividad
----------------------------------------------------------------
local function wants(interested, gender)
    return interested == "a" or (interested == "m" and gender == 0) or (interested == "f" and gender == 1)
end

local function compatible(npc, me)
    return wants(npc.likes, me.gender) and wants(me.interested, npc.gender)
        and npc.age >= me.ageMin and npc.age <= me.ageMax
        and me.age >= npc.ageMin - 2 and me.age <= npc.ageMax + 2
end

local function attraction(npc, me, super)
    local a = (0.85 - npc.traits.picky * 0.6) * (0.35 + 0.65 * me.quality)
    a = a + 0.07 * math.min(3, #T.sharedOf(me.interests, npc.interests))
    if me.age < npc.ageMin or me.age > npc.ageMax then a = a * 0.3 end
    if super then a = a * 1.5 end
    return clamp(a, 0.03, 0.92)
end

-- Hora real del servidor y si el NPC esta durmiendo
local function hourNow() return getRealTime().hour end
local function sleepWindow(npc)
    if npc.traits.night > 0.7 then return 4, 11 end
    if npc.traits.night > 0.4 then return 2, 9 end
    return 0, 7
end
local function isAsleep(npc)
    local h = hourNow()
    local s, e = sleepWindow(npc)
    return h >= s and h < e
end
-- Segundos hasta que se despierte (con un margen al azar)
local function untilAwake(npc)
    local t = getRealTime()
    local _, e = sleepWindow(npc)
    local secs = ((e - t.hour) % 24) * 3600 - t.minute * 60
    return math.max(60, secs) + math.random(0, 5400)
end

local function activeLabel(npc)
    local o = npc.gender == 1 and "a" or "o"
    if isAsleep(npc) then return ("Activ%s hace %d h"):format(o, math.random(2, 7)), false end
    local seed = (npc.id * 7 + hourNow() * 3) % 10
    if seed < 2 then return "En línea", true end
    if seed < 7 then return "Activ" .. o .. " recientemente", false end
    return ("Activ%s hace %d h"):format(o, 1 + seed % 4), false
end

local function replyDelay(npc, interest)
    if isAsleep(npc) then return untilAwake(npc) end
    local base = 25 + (1 - npc.traits.energy) * 300
    base = base * (1.5 - (interest or 50) / 100) * rand(0.5, 1.6)
    return math.floor(clamp(base, 8, 3 * 3600))
end

----------------------------------------------------------------
-- Tarjetas
----------------------------------------------------------------
function T.npcCard(player, me, npcId, callback)
    local npc = T.npcs[npcId]
    if not npc then return callback(nil) end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local photos = {}
        for _, p in ipairs(rows) do
            local scene = TINDER_SCENES[p.scene]
            photos[#photos + 1] = { img = p.image or false, scene = p.scene, label = scene and scene.label or "", pose = p.pose }
        end
        dbQuery(function(qh2)
            local lrows = dbPoll(qh2, 0) or {}
            local l = lrows[1]
            local label, online = activeLabel(npc)
            local prompts = {}
            for _, pr in ipairs(npc.prompts) do
                if TINDER_PROMPTS[pr.k] then prompts[#prompts + 1] = { q = TINDER_PROMPTS[pr.k], a = pr.a } end
            end
            callback({
                key = "n" .. npc.id, kind = "n", id = npc.id, name = npc.first, age = npc.age,
                gender = npc.gender == 1 and "f" or "m", bio = npc.bio, job = npc.job,
                city = npc.zoneT.city, zone = npc.zoneT.label, km = T.distanceKm(player, npc.zoneT.x, npc.zoneT.y),
                interests = npc.interests, shared = T.sharedOf(me.interests, npc.interests), prompts = prompts,
                photos = photos, active = label, online = online,
                superLiked = l and tonumber(l.npc_swipe) == 2 and isNull(l.npc_decide_at) or false,
            })
        end, T.db(), "SELECT npc_swipe, npc_decide_at FROM tinder_npc_links WHERE character_id = ? AND npc_id = ?", me.id, npc.id)
    end,T.db(), "SELECT slot, scene, pose, image FROM tinder_npc_photos WHERE npc_id = ? ORDER BY slot", npc.id)
end

function T.npcNextCard(player, me, exclude, callback)
    if not ready or #npcList == 0 then return callback(nil) end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local links = {}
        for _, r in ipairs(rows) do links[tonumber(r.npc_id)] = r end
        local now = getRealTime().timestamp
        local all, likers = {}, {}
        for _, npc in ipairs(npcList) do
            local l = links[npc.id]
            if not exclude[npc.id] and compatible(npc, me) then
                local ok = false
                if not l then ok = true
                elseif isNull(l.matched_at) and (l.state or "") == "" then
                    local ps = tonumber(l.player_swipe)
                    if ps == nil then ok = true
                    elseif ps == 0 and now - (tonumber(l.sw) or now) > TINDER.NPC_RECYCLE_DAYS * 86400 then ok = true end
                end
                if ok then
                    all[#all + 1] = npc
                    if l and (tonumber(l.npc_swipe) or 0) >= 1 and isNull(l.npc_decide_at) and isNull(l.player_swipe) then likers[#likers + 1] = npc end
                end
            end
        end
        local chosen
        if #likers > 0 and math.random() < 0.35 then chosen = pick(likers)
        elseif #all > 0 then chosen = pick(all) end
        if not chosen then return callback(nil) end
        T.npcCard(player, me, chosen.id, callback)
    end, T.db(), [[
        SELECT npc_id, player_swipe, UNIX_TIMESTAMP(swiped_at) AS sw, npc_swipe, npc_decide_at, matched_at, state
        FROM tinder_npc_links WHERE character_id = ?
    ]], me.id)
end

----------------------------------------------------------------
-- Match y mensajes programados
----------------------------------------------------------------
-- Programa un mensaje del NPC dentro de `delay` segundos (lo entrega el bucle de salida)
local function queueNpcMessage(characterId, npcId, body, delay)
    dbExec(T.db(), [[
        INSERT INTO tinder_npc_messages (character_id, npc_id, from_npc, body, send_at, delivered)
        VALUES (?, ?, 1, ?, NOW() + INTERVAL ? SECOND, 0)
    ]], characterId, npcId, body, math.max(0, math.floor(delay)))
end

local function playerCtx(npc, me)
    return { npc = npc, playerName = me and T.firstName(me.name) or "", playerGender = me and me.gender or 0 }
end

local function matchNpc(characterId, npc, me, super)
    local a = attraction(npc, me, super)
    local shared = T.sharedOf(me.interests, npc.interests)
    local interest = math.floor(clamp(30 + 25 * a + 5 * #shared + math.random(-5, 5) + (super and 8 or 0), 20, 75))
    dbExec(T.db(), [[
        UPDATE tinder_npc_links SET matched_at = NOW(), npc_swipe = COALESCE(npc_swipe, 1), npc_decide_at = NULL,
            interest = ?, state = '', memory = NULL, exchanges = 0, followups = 0, reply_at = NULL
        WHERE character_id = ? AND npc_id = ?
    ]], interest, characterId, npc.id)
    T.announceMatch(characterId, { key = "n" .. npc.id, kind = "n", id = npc.id, name = npc.first, thumb = npc.thumb, scene = npc.scene })
    -- Algunos escriben primero
    if math.random() < 0.2 + npc.traits.energy * 0.45 then
        local ctx = playerCtx(npc, me)
        local O = TINDER_LINES.opener
        local line
        if #shared > 0 and math.random() < 0.5 then
            ctx.si = TINDER_INTEREST_BY_ID[shared[1]].label:lower()
            line = pick(O.interest)
        elseif #me.interests > 0 and math.random() < 0.25 then
            ctx.pi = TINDER_INTEREST_BY_ID[me.interests[1]].label:lower()
            line = pick(O.player)
        elseif #me.bio > 20 and math.random() < 0.3 then
            line = pick(O.bio)
        else
            ctx.now = pick(npc.arch.day[hourNow() < 12 and "morning" or (hourNow() < 19 and "afternoon" or "night")])
            line = pick(O.plain)
        end
        local delay = isAsleep(npc) and untilAwake(npc) or rand(40, 600)
        queueNpcMessage(characterId, npc.id, stylize(fill(line, ctx), npc), delay)
    end
end

function T.npcSwipe(player, me, npcId, action)
    local npc = T.npcs[npcId]
    if not npc or not compatible(npc, me) then return end
    local val = action == "super" and 2 or (action == "like" and 1 or 0)
    local characterId = me.id
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local l = rows[1]
        if l and not isNull(l.matched_at) then return end
        local npcSwipe = l and tonumber(l.npc_swipe)
        if val == 0 then
            return dbExec(T.db(), [[
                INSERT INTO tinder_npc_links (character_id, npc_id, player_swipe, swiped_at) VALUES (?, ?, 0, NOW())
                ON DUPLICATE KEY UPDATE player_swipe = 0, swiped_at = NOW()
            ]], characterId, npcId)
        end
        if npcSwipe and npcSwipe >= 1 and isNull(l.npc_decide_at) then
            -- Ya le gustabas: match al instante
            dbQuery(function(qh2)
                dbPoll(qh2, 0)
                matchNpc(characterId, npc, me, val == 2)
            end, T.db(), "UPDATE tinder_npc_links SET player_swipe = ?, swiped_at = NOW() WHERE character_id = ? AND npc_id = ?", val, characterId, npcId)
            return
        end
        if npcSwipe == 0 and val ~= 2 then
            -- Ya te habia descartado; un super like le da otra oportunidad
            return dbExec(T.db(), "UPDATE tinder_npc_links SET player_swipe = ?, swiped_at = NOW() WHERE character_id = ? AND npc_id = ?", val, characterId, npcId)
        end
        local delay = rand(TINDER.DECIDE_MIN, TINDER.DECIDE_MAX) * (1.4 - npc.traits.energy)
        if val == 2 then delay = delay * 0.3 end
        if isAsleep(npc) then delay = untilAwake(npc) end
        dbExec(T.db(), [[
            INSERT INTO tinder_npc_links (character_id, npc_id, player_swipe, swiped_at, npc_swipe, npc_decide_at)
            VALUES (?, ?, ?, NOW(), NULL, NOW() + INTERVAL ? SECOND)
            ON DUPLICATE KEY UPDATE player_swipe = VALUES(player_swipe), swiped_at = NOW(), npc_swipe = NULL,
                npc_decide_at = VALUES(npc_decide_at)
        ]], characterId, npcId, val, math.floor(delay))
    end, T.db(), "SELECT npc_swipe, npc_decide_at, matched_at FROM tinder_npc_links WHERE character_id = ? AND npc_id = ?", characterId, npcId)
end

----------------------------------------------------------------
-- Listas para la app
----------------------------------------------------------------
function T.npcMatches(characterId, callback)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local list = {}
        for _, r in ipairs(rows) do
            local npc = T.npcs[tonumber(r.npc_id)]
            if npc then
                local label, online = activeLabel(npc)
                list[#list + 1] = {
                    key = "n" .. npc.id, kind = "n", id = npc.id, name = npc.first, age = npc.age, thumb = npc.thumb, scene = npc.scene,
                    last = r.body and T.preview(r.body) or nil, lastMine = tonumber(r.from_npc) == 0,
                    ts = tonumber(r.ts) or 0, unread = tonumber(r.unread) or 0, online = online,
                }
            end
        end
        callback(list)
    end, T.db(), [[
        SELECT k.npc_id, m.body, m.from_npc, UNIX_TIMESTAMP(COALESCE(m.send_at, k.matched_at)) AS ts,
               (SELECT COUNT(*) FROM tinder_npc_messages u WHERE u.character_id = k.character_id AND u.npc_id = k.npc_id
                AND u.from_npc = 1 AND u.delivered = 1 AND u.read_at IS NULL) AS unread
        FROM tinder_npc_links k
        LEFT JOIN tinder_npc_messages m ON m.id = (SELECT MAX(x.id) FROM tinder_npc_messages x
            WHERE x.character_id = k.character_id AND x.npc_id = k.npc_id AND x.delivered = 1)
        WHERE k.character_id = ? AND k.matched_at IS NOT NULL AND k.state NOT IN ('unmatched', 'leaving')
    ]], characterId)
end

function T.npcLikesYou(characterId, callback)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local list = {}
        for _, r in ipairs(rows) do
            local npc = T.npcs[tonumber(r.npc_id)]
            if npc then
                list[#list + 1] = { key = "n" .. npc.id, name = npc.first, age = npc.age, thumb = npc.thumb, scene = npc.scene, super = tonumber(r.npc_swipe) == 2 }
            end
        end
        callback(list)
    end, T.db(), [[
        SELECT npc_id, npc_swipe FROM tinder_npc_links
        WHERE character_id = ? AND npc_swipe >= 1 AND player_swipe IS NULL AND matched_at IS NULL AND npc_decide_at IS NULL
        LIMIT 30
    ]], characterId)
end

----------------------------------------------------------------
-- Chat con un NPC
----------------------------------------------------------------
local function decodeMemory(text)
    local m = text and text ~= "" and fromJSON(text) or nil
    if type(m) ~= "table" then m = {} end
    m.answered = type(m.answered) == "table" and m.answered or {}
    m.asked = type(m.asked) == "table" and m.asked or {}
    m.shared = type(m.shared) == "table" and m.shared or {}
    m.recent = type(m.recent) == "table" and m.recent or {}
    return m
end

-- Primeros mensajes sugeridos (rompehielos) segun su perfil
local function icebreakers(npc, me)
    local out = {}
    local shared = T.sharedOf(me.interests, npc.interests)
    if shared[1] then out[#out + 1] = "Vi que te gusta " .. TINDER_INTEREST_BY_ID[shared[1]].label:lower() .. " 👀" end
    local pr = npc.prompts[1]
    if pr and TINDER_PROMPTS[pr.k] then out[#out + 1] = "Tu \"" .. TINDER_PROMPTS[pr.k]:lower() .. "\" me hizo reír jaja" end
    out[#out + 1] = "Hola " .. npc.first .. "! ¿Qué tal tu día?"
    out[#out + 1] = "¿Qué haces en " .. npc.zoneT.label .. " un día normal?"
    return out
end

function T.npcChatOpen(player, characterId, npcId)
    local npc = T.npcs[npcId]
    if not npc then return end
    T.withProfile(player, function(me)
        dbQuery(function(qh)
            local lrows = dbPoll(qh, 0) or {}
            local l = lrows[1]
            if not l or isNull(l.matched_at) or l.state == "unmatched" or l.state == "leaving" or not isElement(player) then return end
            dbQuery(function(qh2)
                local rows = dbPoll(qh2, 0) or {}
                if not isElement(player) then return end
                local msgs, mineCount = {}, 0
                for i = #rows, 1, -1 do
                    local r = rows[i]
                    local mine = tonumber(r.from_npc) == 0
                    if mine then mineCount = mineCount + 1 end
                    msgs[#msgs + 1] = { mine = mine, body = r.body, ts = tonumber(r.ts), read = not isNull(r.read_at) }
                end
                local mem = decodeMemory(l.memory)
                local label, online = activeLabel(npc)
                triggerLatentClientEvent(player, "rp:tinder:chat", 300000, false, resourceRoot, {
                    key = "n" .. npcId, kind = "n", id = npcId, name = npc.first, age = npc.age, thumb = npc.thumb, scene = npc.scene,
                    messages = msgs, online = online, active = label, typing = tonumber(l.pending) and tonumber(l.pending) > 0 or false,
                    number = mem.number, spot = mem.spot, suggestions = mineCount == 0 and icebreakers(npc, me) or nil,
                })
                dbExec(T.db(), [[
                    UPDATE tinder_npc_messages SET read_at = NOW()
                    WHERE character_id = ? AND npc_id = ? AND from_npc = 1 AND delivered = 1 AND read_at IS NULL
                ]], characterId, npcId)
            end, T.db(), [[
                SELECT from_npc, body, read_at, UNIX_TIMESTAMP(send_at) AS ts FROM tinder_npc_messages
                WHERE character_id = ? AND npc_id = ? AND delivered = 1 ORDER BY id DESC LIMIT 80
            ]], characterId, npcId)
        end, T.db(), [[
            SELECT k.*, (SELECT COUNT(*) FROM tinder_npc_messages p WHERE p.character_id = k.character_id AND p.npc_id = k.npc_id
                AND p.delivered = 0 AND p.send_at <= NOW() + INTERVAL 8 SECOND) AS pending
            FROM tinder_npc_links k WHERE k.character_id = ? AND k.npc_id = ?
        ]], characterId, npcId)
    end)
end

function T.npcChatSend(player, characterId, npcId, text)
    local npc = T.npcs[npcId]
    if not npc then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local l = rows[1]
        if not l or isNull(l.matched_at) or l.state == "unmatched" or l.state == "leaving" or not isElement(player) then
            if isElement(player) then T.notify(player, "Ya no puedes escribirle a esta persona.", "info") end
            return
        end
        dbQuery(function(qh2)
            local _, _, id = dbPoll(qh2, 0)
            if not id or not isElement(player) then return end
            triggerClientEvent(player, "rp:tinder:message", resourceRoot, "n" .. npcId, { mine = true, body = text, ts = getRealTime().timestamp })
            if l.state == "ghost" then
                return dbExec(T.db(), "UPDATE tinder_npc_links SET last_player_at = NOW() WHERE character_id = ? AND npc_id = ?", characterId, npcId)
            end
            if isNull(l.reply_at) then
                dbExec(T.db(), [[
                    UPDATE tinder_npc_links SET last_player_at = NOW(), reply_at = NOW() + INTERVAL ? SECOND
                    WHERE character_id = ? AND npc_id = ?
                ]], replyDelay(npc, tonumber(l.interest)), characterId, npcId)
            else
                dbExec(T.db(), "UPDATE tinder_npc_links SET last_player_at = NOW() WHERE character_id = ? AND npc_id = ?", characterId, npcId)
            end
        end, T.db(), "INSERT INTO tinder_npc_messages (character_id, npc_id, from_npc, body) VALUES (?, ?, 0, ?)", characterId, npcId, text)
    end, T.db(), "SELECT matched_at, state, reply_at, interest FROM tinder_npc_links WHERE character_id = ? AND npc_id = ?", characterId, npcId)
end

----------------------------------------------------------------
-- Motor de conversacion
----------------------------------------------------------------
local INTENT_ORDER = { "rude", "greet", "howareyou", "name", "age", "job", "zone", "hobbies", "seek", "now", "bot",
                       "thanks", "compliment", "flirt", "date", "number", "laugh", "bye" }
local YES = { "^si", "^dale", "claro", "obvio", "me encantaria", "de una", "por supuesto", "^ok", "^vamos", "me parece", "^bueno", "^va" }

local function detect(norm)
    local found = {}
    for intent, patterns in pairs(TINDER_INTENTS) do
        for _, p in ipairs(patterns) do
            if norm:find(p) then found[intent] = true break end
        end
    end
    return found
end

local function mentionedInterests(norm)
    -- Ordenados por donde aparecen en el texto: el primero que nombra es el que cuenta
    local found = {}
    for _, it in ipairs(TINDER_INTERESTS) do
        local best
        for _, w in ipairs(it.words) do
            local pos = norm:find("%f[%w]" .. w:gsub("%s", "%%s") .. "%f[%W]")
            if pos and (not best or pos < best) then best = pos end
        end
        if best then found[#found + 1] = { id = it.id, pos = best } end
    end
    table.sort(found, function(a, b) return a.pos < b.pos end)
    local out = {}
    for i, f in ipairs(found) do out[i] = f.id end
    return out
end

local function tierOf(interest)
    if interest >= 65 then return "hi" end
    if interest >= 35 then return "mid" end
    return "lo"
end

local function dayPart()
    local h = hourNow()
    if h < 12 then return "morning" end
    if h < 19 then return "afternoon" end
    return "night"
end

--[[
    Decide la respuesta del NPC a los mensajes sin leer del jugador.
    Devuelve: bubbles (lista de textos ya estilizados), mem, interest, state, actions
    actions.number = lugar de la cita (pedir numero a rp_npcrel)
]]
local function compose(npc, me, link, texts)
    local mem = decodeMemory(link.memory)
    local interest = tonumber(link.interest) or 40
    local exchanges = tonumber(link.exchanges) or 0
    local t = npc.traits
    local ctx = playerCtx(npc, me)
    ctx.now = pick(npc.arch.day[dayPart()])
    ctx.jobtalk = pick(npc.arch.jobtalk)
    ctx.seek = pick(npc.arch.seeking)
    ctx.num = mem.number and (tostring(mem.number):gsub("^(%d%d%d)(%d+)$", "%1-%2")) or ""
    local out, actions = {}, {}
    local L = TINDER_LINES

    local function say(list, extra)
        if not list or #list == 0 then return end
        -- evita repetir frases recientes
        local line
        for _ = 1, 6 do
            line = pick(list)
            local used = false
            for _, r in ipairs(mem.recent) do if r == line then used = true break end end
            if not used then break end
        end
        mem.recent[#mem.recent + 1] = line
        while #mem.recent > 14 do table.remove(mem.recent, 1) end
        if extra then for k, v in pairs(extra) do ctx[k] = v end end
        out[#out + 1] = fill(line, ctx)
    end
    local function tiered(group) say(group[tierOf(interest)] or group.mid) end

    local full = table.concat(texts, " \n ")
    local norm = normalize(full)
    local found = detect(norm)
    local letters = #norm:gsub("[^%a]", "")

    -- Ritmo de la conversacion
    if #texts >= 4 then interest = interest - 3 end   -- muchos mensajes seguidos sin respuesta
    if link.gap and link.gap > 86400 then interest = interest - 4 end   -- tardaste mas de un dia en contestar

    -- Groserias: se va
    if found.rude then
        interest = interest - 45
        say(L.rude)
        return out, mem, clamp(interest, 0, 100), "leaving", actions
    end

    -- ¿Responde a una cita que propuso el NPC?
    local acceptsNpcDate = mem.npcAsked and not mem.spot and (function()
        for _, y in ipairs(YES) do if norm:find(y) then return true end end
        return false
    end)()

    local answered = 0
    local askBack = false
    if found.greet then
        if exchanges == 0 and not mem.greeted then tiered(L.greet) mem.greeted = true
        elseif letters < 8 then say(L.hola_only) interest = interest - 2
        elseif math.random() < 0.3 then say(L.greet_again) end
    end
    if found.howareyou then
        tiered(L.howareyou)
        interest = interest + 2 * t.warmth
        if not mem.askedBack and math.random() < t.warmth then askBack = true mem.askedBack = true end
        answered = answered + 1
    end
    local QA = { name = L.name, age = L.age, job = L.job, zone = L.zone, hobbies = L.hobbies, seek = L.seek, now = L.now }
    for _, intent in ipairs(INTENT_ORDER) do
        if QA[intent] and found[intent] and answered < 3 then
            if mem.answered[intent] and intent ~= "now" then
                say({ "Ya te lo dije jaja", "Eso ya te lo conté 😅" })
                interest = interest - 1
            else
                say(QA[intent])
                interest = interest + (intent == "age" and 0.5 or 2.5)
                mem.answered[intent] = true
                if intent == "job" or intent == "zone" or intent == "seek" then mem.asked[intent] = true end
            end
            answered = answered + 1
        end
    end
    if askBack then say(L.askback) end
    if found.bot then say(L.bot) end
    if found.thanks and answered == 0 then say(L.thanks) end

    -- Gustos que el jugador menciona
    for _, id in ipairs(mentionedInterests(norm)) do
        local it = TINDER_INTEREST_BY_ID[id]
        local has = false
        for _, mine in ipairs(npc.interests) do if mine == id then has = true break end end
        if has and not mem.shared[id] then
            mem.shared[id] = true
            say(L.shared, { si = it.label:lower() })
            interest = interest + 7
            break
        elseif not has and math.random() < 0.25 then
            say(L.mention, { mi = it.label:lower() })
            interest = interest + 1
            break
        end
    end

    if found.compliment then
        if interest < 35 then
            tiered(L.compliment)
            interest = interest + (t.flirt > 0.6 and 1 or -2 * t.picky)
        else
            tiered(L.compliment)
            interest = interest + 1 + 4 * t.flirt
        end
        if exchanges < 2 and t.picky > 0.6 then interest = interest - 3 end
    end
    if found.flirt then
        if interest < 45 then say(L.flirt.bad) interest = interest - 6 * (1 - t.flirt)
        elseif interest < 70 then say(L.flirt.mid) interest = interest + 5 * t.flirt
        else say(L.flirt.hi) interest = interest + 6 end
    end
    if found.laugh then
        interest = interest + 2 * t.humor
        if #out == 0 and math.random() < 0.4 + t.humor * 0.4 then say(L.laugh) end
    end

    -- Citas y numero
    local spot = pick(npc.arch.spots)
    if acceptsNpcDate then
        mem.spot = mem.npcAsked
        say({ "Genial! entonces {spot} 😊" }, { spot = mem.spot })
        actions.number = mem.spot
        interest = interest + 4
    elseif found.date or (found.number and not mem.number) then
        if mem.number then say(L.number_given)
        elseif interest >= 60 - t.flirt * 10 and exchanges >= TINDER.DATE_MIN_EXCHANGES then
            mem.spot = fill(spot, ctx)
            say(found.date and L.date_accept or { "Bueno, ya que insistes jaja" }, { spot = mem.spot })
            actions.number = mem.spot
            interest = interest + 5
        elseif interest >= 35 then
            say(found.date and L.date_soon or L.number_soon)
            interest = interest - 1
        else
            say(L.date_no)
            interest = interest - 4
        end
    end

    if found.bye then say(L.goodnight) end

    -- Si no hubo nada concreto: reaccion al contenido
    if #out == 0 then
        if mem.pendingQ then
            tiered(L.ack)
            interest = interest + (letters > 20 and 3 or 1)
        elseif letters < 6 and exchanges > 0 then
            if math.random() < 0.6 then say(L.low_effort) end
            interest = interest - 3
        elseif full:find("%?") then
            say(L.question)
            interest = interest + 1
        elseif letters >= 25 then
            tiered(L.about)
            interest = interest + 2
        else
            tiered(L.vague)
        end
    end
    mem.pendingQ = nil

    -- Seguir la charla con una pregunta
    local alreadyAsks = false
    for _, line in ipairs(out) do if line:find("%?%s*$") or line:find("%?%s*%S+$") then alreadyAsks = true end end
    if #out < 3 and not alreadyAsks and interest >= 25 and not actions.number and math.random() < 0.3 + t.warmth * 0.4 then
        local topics = {}
        for _, k in ipairs({ "job", "weekend", "music", "food", "zone", "travel", "pets", "seek", "place" }) do
            if not mem.asked[k] then topics[#topics + 1] = k end
        end
        local notShared = {}
        for _, id in ipairs(me.interests) do
            local shared = false
            for _, n in ipairs(npc.interests) do if n == id then shared = true break end end
            if not shared then notShared[#notShared + 1] = id end
        end
        if #notShared > 0 and not mem.asked.pi then
            topics[#topics + 1] = "pi"
            ctx.pi = TINDER_INTEREST_BY_ID[notShared[1]].label:lower()
        end
        if #topics > 0 then
            local k = pick(topics)
            mem.asked[k] = true
            mem.pendingQ = k
            say(L.ask[k])
        end
    end

    -- El NPC propone verse
    if not mem.spot and not mem.npcAsked and not actions.number and interest >= 78 and exchanges >= 8 and math.random() < t.flirt * 0.6 then
        mem.npcAsked = fill(spot, ctx)
        say(L.npc_date, { spot = mem.npcAsked })
    end

    interest = clamp(math.floor(interest + 0.5), 0, 100)
    local state = ""
    if interest < TINDER.UNMATCH_BELOW then state = "leaving"
    elseif interest < TINDER.GHOST_BELOW then state = "ghost" out = {} end

    while #out > 3 do table.remove(out) end
    for i, line in ipairs(out) do out[i] = stylize(line, npc) end
    return out, mem, interest, state, actions
end

-- Pide a rp_npcrel que cree el vinculo (con numero) para la cita
local pendingNumbers = {}   -- [ref] = { characterId, npcId, spot }
local function requestNumber(characterId, npc, me, spot)
    local res = getResourceFromName("rp_npcrel")
    if not res or getResourceState(res) ~= "running" then return false end
    local ref = keyOf(characterId, npc.id)
    pendingNumbers[ref] = { characterId = characterId, npcId = npc.id, spot = spot, me = me }
    local friendship = 25
    local romance = 32
    return exports.rp_npcrel:createDateContact(characterId, {
        ref = ref, name = npc.name, gender = npc.gender, skin = npc.skin, traits = npc.arch.npcrel,
        likes = npc.likes, friendship = friendship, romance = romance,
    }) == true
end

addEventHandler("rp:npcrel:dateContact", root, function(ref, number)
    local p = pendingNumbers[ref]
    if not p then return end
    pendingNumbers[ref] = nil
    local npc = T.npcs[p.npcId]
    if not npc then return end
    if not number then
        return queueNpcMessage(p.characterId, p.npcId, stylize("Mejor escríbeme por acá y coordinamos 😊", npc), 4)
    end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not rows[1] then return end
        local mem = decodeMemory(rows[1].memory)
        mem.number = tonumber(number)
        dbExec(T.db(), "UPDATE tinder_npc_links SET memory = ? WHERE character_id = ? AND npc_id = ?", toJSON(mem, true), p.characterId, p.npcId)
        -- Logros (rp_achievements): cita conseguida (te da su número para quedar)
        local player = T.playerOf(p.characterId)
        if player then triggerEvent("rp:achievements:progress", player, "tinder_dates", 1) end
        local ctx = playerCtx(npc, p.me)
        ctx.num = tostring(number):gsub("^(%d%d%d)(%d+)$", "%1-%2")
        queueNpcMessage(p.characterId, p.npcId, stylize(fill(pick(TINDER_LINES.number_give), ctx), npc), rand(6, 14))
    end, T.db(), "SELECT memory FROM tinder_npc_links WHERE character_id = ? AND npc_id = ?", p.characterId, p.npcId)
end)

-- Procesa una respuesta pendiente (reply_at vencido)
local function processReply(characterId, npcId)
    local key = keyOf(characterId, npcId)
    local npc = T.npcs[npcId]
    if busyLink[key] or not npc then return end
    busyLink[key] = true
    dbExec(T.db(), "UPDATE tinder_npc_links SET reply_at = NULL WHERE character_id = ? AND npc_id = ?", characterId, npcId)
    T.loadProfile(characterId, function(me)
        if not me then busyLink[key] = nil return end
        dbQuery(function(qh)
            local rows = dbPoll(qh, 0) or {}
            local link = rows[1]
            if not link or link.state == "unmatched" or link.state == "leaving" then busyLink[key] = nil return end
            dbQuery(function(qh2)
                local msgs = dbPoll(qh2, 0) or {}
                local texts = {}
                for _, m in ipairs(msgs) do texts[#texts + 1] = m.body end
                if #texts == 0 then busyLink[key] = nil return end
                link.gap = tonumber(link.gap)
                local bubbles, mem, interest, state, actions = compose(npc, me, link, texts)
                -- "Visto"
                dbExec(T.db(), [[
                    UPDATE tinder_npc_messages SET read_at = NOW()
                    WHERE character_id = ? AND npc_id = ? AND from_npc = 0 AND read_at IS NULL
                ]], characterId, npcId)
                T.push(characterId, "rp:tinder:read", "n" .. npcId)
                local delay = rand(1.5, 4)
                for _, text in ipairs(bubbles) do
                    delay = delay + math.min(9, 1.2 + (utf8.len(text) or #text) * 0.06)
                    queueNpcMessage(characterId, npcId, text, delay)
                end
                dbExec(T.db(), [[
                    UPDATE tinder_npc_links SET interest = ?, exchanges = exchanges + 1, memory = ?, state = ?, followups = 0
                    WHERE character_id = ? AND npc_id = ?
                ]], interest, toJSON(mem, true), state, characterId, npcId)
                if actions.number and not mem.number then
                    if not requestNumber(characterId, npc, me, actions.number) then
                        queueNpcMessage(characterId, npcId, stylize("Escríbeme cuando vayas para allá y nos vemos ahí 😊", npc), delay + 5)
                    end
                end
                busyLink[key] = nil
            end, T.db(), [[
                SELECT body FROM tinder_npc_messages
                WHERE character_id = ? AND npc_id = ? AND from_npc = 0 AND read_at IS NULL ORDER BY id
            ]], characterId, npcId)
        end, T.db(), [[
            SELECT *, TIMESTAMPDIFF(SECOND, last_npc_at, last_player_at) AS gap
            FROM tinder_npc_links WHERE character_id = ? AND npc_id = ?
        ]], characterId, npcId)
    end)
end

----------------------------------------------------------------
-- Bucles de la simulacion
----------------------------------------------------------------
-- Entrega de mensajes del NPC (con "escribiendo..." unos segundos antes)
local function outboxTick()
    if not ready then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local now = getRealTime().timestamp
        for _, r in ipairs(rows) do
            local id, characterId, npcId = tonumber(r.id), tonumber(r.character_id), tonumber(r.npc_id)
            local wait = tonumber(r.wait) or 0
            if wait > 0 then
                if not typingSent[id] then
                    typingSent[id] = true
                    T.push(characterId, "rp:tinder:typing", "n" .. npcId, true)
                end
            else
                typingSent[id] = nil
                dbQuery(function(qh2)
                    local _, affected = dbPoll(qh2, 0)
                    if not affected or affected < 1 then return end
                    dbExec(T.db(), "UPDATE tinder_npc_links SET last_npc_at = NOW() WHERE character_id = ? AND npc_id = ?", characterId, npcId)
                    local npc = T.npcs[npcId]
                    local p = T.push(characterId, "rp:tinder:message", "n" .. npcId,
                        { mine = false, body = r.body, ts = now, name = npc and npc.first or "" })
                    -- Si se iba (grosero), al terminar de hablar deshace el match
                    dbQuery(function(qh3)
                        local lr = dbPoll(qh3, 0) or {}
                        local l = lr[1]
                        if l and l.state == "leaving" and tonumber(l.pending) == 0 then
                            dbExec(T.db(), "UPDATE tinder_npc_links SET state = 'unmatched' WHERE character_id = ? AND npc_id = ?", characterId, npcId)
                            setTimer(function() T.push(characterId, "rp:tinder:unmatched", "n" .. npcId) end, 4000, 1)
                        end
                    end, T.db(), [[
                        SELECT k.state, (SELECT COUNT(*) FROM tinder_npc_messages x WHERE x.character_id = k.character_id
                            AND x.npc_id = k.npc_id AND x.delivered = 0) AS pending
                        FROM tinder_npc_links k WHERE k.character_id = ? AND k.npc_id = ?
                    ]], characterId, npcId)
                    if p then T.push(characterId, "rp:tinder:typing", "n" .. npcId, false) end
                end, T.db(), "UPDATE tinder_npc_messages SET delivered = 1, send_at = NOW() WHERE id = ? AND delivered = 0", id)
            end
        end
    end, T.db(), [[
        SELECT id, character_id, npc_id, body, UNIX_TIMESTAMP(send_at) - UNIX_TIMESTAMP() AS wait
        FROM tinder_npc_messages WHERE delivered = 0 AND send_at <= NOW() + INTERVAL 6 SECOND ORDER BY send_at LIMIT 60
    ]])
end

local function repliesTick()
    if not ready then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, r in ipairs(rows) do processReply(tonumber(r.character_id), tonumber(r.npc_id)) end
    end, T.db(), [[
        SELECT character_id, npc_id FROM tinder_npc_links
        WHERE reply_at IS NOT NULL AND reply_at <= NOW() AND state IN ('', 'ghost') LIMIT 20
    ]])
end

-- El NPC ve tu like y decide
local function decisionsTick()
    if not ready then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, r in ipairs(rows) do
            local characterId, npcId = tonumber(r.character_id), tonumber(r.npc_id)
            local npc, key = T.npcs[npcId], keyOf(characterId, npcId)
            if npc and not busyLink[key] then
                busyLink[key] = true
                T.loadProfile(characterId, function(me)
                    busyLink[key] = nil
                    if not me then return end
                    local ps = tonumber(r.player_swipe) or 0
                    local likes = math.random() < attraction(npc, me, ps == 2)
                    dbExec(T.db(), "UPDATE tinder_npc_links SET npc_swipe = ?, npc_decide_at = NULL WHERE character_id = ? AND npc_id = ?",
                        likes and 1 or 0, characterId, npcId)
                    if likes and ps >= 1 then matchNpc(characterId, npc, me, ps == 2) end
                end)
            end
        end
    end, T.db(), [[
        SELECT character_id, npc_id, player_swipe FROM tinder_npc_links
        WHERE npc_swipe IS NULL AND npc_decide_at IS NOT NULL AND npc_decide_at <= NOW() LIMIT 40
    ]])
end

-- Mientras juegas, algunos NPC te dan like (salen en "Le gustas")
local function passiveTick()
    if not ready then return end
    for _, player in ipairs(getElementsByType("player")) do
        local characterId = T.characterOf(player)
        if characterId and exports.rp_inventory:hasItem(player, "phone", 1) then
            T.loadProfile(characterId, function(me)
                if not me or not me.exists or not me.active or not me.hasPhoto then return end
                dbQuery(function(qh)
                    local rows = dbPoll(qh, 0) or {}
                    local linked, pending = {}, 0
                    for _, r in ipairs(rows) do
                        linked[tonumber(r.npc_id)] = true
                        if (tonumber(r.npc_swipe) or 0) >= 1 and isNull(r.player_swipe) and isNull(r.matched_at) then pending = pending + 1 end
                    end
                    if pending >= TINDER.LIKES_YOU_MAX then return end
                    local options = {}
                    for _, npc in ipairs(npcList) do
                        if not linked[npc.id] and compatible(npc, me) and not isAsleep(npc) then options[#options + 1] = npc end
                    end
                    if #options == 0 then return end
                    local npc = pick(options)
                    if math.random() > attraction(npc, me, false) * 0.5 then return end
                    local super = math.random() < 0.08 and 2 or 1
                    dbExec(T.db(), "INSERT IGNORE INTO tinder_npc_links (character_id, npc_id, npc_swipe) VALUES (?, ?, ?)", characterId, npc.id, super)
                    if isElement(player) then
                        T.sendBadge(player)
                        if super == 2 then T.notify(player, "⭐ Alguien te dio un Super Like en Tinder.", "info")
                        elseif math.random() < 0.4 then T.notify(player, "🔥 Le gustas a alguien en Tinder.", "info") end
                    end
                end, T.db(), "SELECT npc_id, npc_swipe, player_swipe, matched_at FROM tinder_npc_links WHERE character_id = ?", characterId)
            end)
        end
    end
end

-- Insistir si lo ignoras, rendirse si sigues sin contestar, y los ghosts se van
local function staleTick()
    if not ready then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, r in ipairs(rows) do
            local npc = T.npcs[tonumber(r.npc_id)]
            if npc and not isAsleep(npc) then
                local ctx = playerCtx(npc, nil)
                ctx.playerGender = tonumber(r.gender) == 1 and 1 or 0
                queueNpcMessage(tonumber(r.character_id), npc.id, stylize(fill(pick(TINDER_LINES.followup), ctx), npc), rand(5, 120))
                dbExec(T.db(), "UPDATE tinder_npc_links SET followups = followups + 1, interest = interest - 5 WHERE character_id = ? AND npc_id = ?", r.character_id, r.npc_id)
            end
        end
    end, T.db(), [[
        SELECT k.character_id, k.npc_id, c.gender FROM tinder_npc_links k JOIN characters c ON c.id = k.character_id
        WHERE k.matched_at IS NOT NULL AND k.state = '' AND k.followups = 0 AND k.reply_at IS NULL AND k.interest >= 40
          AND k.last_npc_at IS NOT NULL AND (k.last_player_at IS NULL OR k.last_player_at < k.last_npc_at)
          AND k.last_npc_at < NOW() - INTERVAL ? HOUR
        LIMIT 20
    ]], TINDER.STALE_HOURS)
    dbExec(T.db(), [[
        UPDATE tinder_npc_links SET state = 'unmatched'
        WHERE matched_at IS NOT NULL AND state = '' AND followups >= 1
          AND last_npc_at < NOW() - INTERVAL ? DAY AND (last_player_at IS NULL OR last_player_at < last_npc_at)
    ]], TINDER.GIVEUP_DAYS)
    dbExec(T.db(), [[
        UPDATE tinder_npc_links SET state = 'unmatched'
        WHERE state = 'ghost' AND (last_player_at IS NULL OR last_player_at < NOW() - INTERVAL 2 DAY)
    ]])
end

setTimer(outboxTick, 2000, 0)
setTimer(repliesTick, 3000, 0)
setTimer(decisionsTick, 20000, 0)
setTimer(passiveTick, TINDER.PASSIVE_EVERY, 0)
setTimer(staleTick, 5 * 60000, 0)

----------------------------------------------------------------
-- Estudio de fotos (/tinderstudio): el cliente del admin saca las fotos en el mundo
----------------------------------------------------------------
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function sendStudioBatch(player)
    local s = studio[player]
    if not s then return end
    -- estandar:sql-seguro solo se anade "AND p.npc_id = ?" (texto fijo); el id va como parametro
    local sql = [[
        SELECT p.id, p.npc_id, p.slot, p.scene, p.pose, n.skin, n.gender, n.archetype
        FROM tinder_npc_photos p JOIN tinder_npcs n ON n.id = p.npc_id
        WHERE p.image IS NULL ]] .. (s.npcId and "AND p.npc_id = ? " or "") .. [[
        ORDER BY p.scene, p.pose = 'paisaje', p.id LIMIT 200
    ]]
    local function onRows(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or not studio[player] then return end
        -- Las que ya se intentaron en esta sesion (y fallaron) no se repiten
        local fresh = {}
        for _, r in ipairs(rows) do
            if not s.tried[tonumber(r.id)] and #fresh < 30 then fresh[#fresh + 1] = r end
        end
        rows = fresh
        if #rows == 0 then
            studio[player] = nil
            triggerClientEvent(player, "rp:tinder:studio:done", resourceRoot, s.total)
            loadNpcs()
            return T.notify(player, ("Estudio terminado: %d fotos nuevas."):format(s.total), "success")
        end
        local jobs = {}
        for _, r in ipairs(rows) do
            local arch = TINDER_ARCHETYPE_BY_ID[r.archetype]
            local id = tonumber(r.id)
            s.ids[id] = true
            s.tried[id] = true
            jobs[#jobs + 1] = {
                id = id, npc = tonumber(r.npc_id), scene = r.scene, pose = r.pose, skin = tonumber(r.skin),
                gender = tonumber(r.gender), car = arch and arch.cars and pick(arch.cars) or 411,
            }
        end
        triggerClientEvent(player, "rp:tinder:studio:jobs", resourceRoot, jobs)
    end
    -- dbQuery no admite nil como parametro
    if s.npcId then dbQuery(onRows, T.db(), sql, s.npcId) else dbQuery(onRows, T.db(), sql) end
end

local function startStudio(player, npcId)
    studio[player] = { npcId = npcId, total = 0, ids = {}, tried = {} }
    if npcId then
        dbQuery(function(qh)
            dbPoll(qh, 0)
            sendStudioBatch(player)
        end, T.db(), "UPDATE tinder_npc_photos SET image = NULL, thumb = NULL WHERE npc_id = ?", npcId)
    else
        sendStudioBatch(player)
    end
end

local function studioCommand(player, _, arg)
    if not isAdmin(player) then return T.notify(player, "No tienes permiso para usar este comando.", "error") end
    if studio[player] then
        studio[player] = nil
        triggerClientEvent(player, "rp:tinder:studio:done", resourceRoot, -1)
        return T.notify(player, "Estudio de fotos detenido.", "info")
    end
    if not ready then return T.notify(player, "Tinder aún está cargando.", "warning") end
    if isPedInVehicle(player) then return T.notify(player, "Bájate del vehículo para usar el estudio.", "warning") end
    local npcId = tonumber(arg)
    if arg and (not npcId or not T.npcs[npcId]) then return T.notify(player, "Uso: /tinderstudio [id del NPC] (sin id: todas las fotos que faltan)", "warning") end
    T.notify(player, "Estudio de Tinder: no toques nada mientras se sacan las fotos. Repite el comando para detenerlo.", "info")
    startStudio(player, npcId)
end
addCommandHandler("tinderstudio", studioCommand)
addCommandHandler("tinderestudio", studioCommand)

addEventHandler("rp:tinder:studio:photo", resourceRoot, function(photoId, image, thumb)
    local player = client
    local s = studio[player]
    photoId = tonumber(photoId)
    if not s or not photoId or not s.ids[photoId] or not isAdmin(player) then return end
    local function ok(str, max) return type(str) == "string" and #str > 100 and #str <= max and str:sub(1, 4) == "/9j/" and str:match("^[%w%+/=]+$") end
    if not ok(image, TINDER.PHOTO_MAX) or not ok(thumb, TINDER.THUMB_MAX) then return end
    s.ids[photoId] = nil
    s.total = s.total + 1
    dbExec(T.db(), "UPDATE tinder_npc_photos SET image = ?, thumb = ?, taken_at = NOW() WHERE id = ?", image, thumb, photoId)
end)

addEventHandler("rp:tinder:studio:next", resourceRoot, function()
    if studio[client] and isAdmin(client) then setTimer(sendStudioBatch, 1500, 1, client) end
end)

addEventHandler("rp:tinder:studio:stop", resourceRoot, function()
    if studio[client] then
        studio[client] = nil
        loadNpcs()
    end
end)

-- Estadisticas para admins
addCommandHandler("tinderstats", function(player)
    if not isAdmin(player) then return T.notify(player, "No tienes permiso para usar este comando.", "error") end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local r = rows[1] or {}
        if not isElement(player) then return end
        outputChatBox(("[Tinder] NPC: %d · fotos: %d/%d · matches con NPC: %d · mensajes: %d"):format(#npcList,
            tonumber(r.done) or 0, tonumber(r.total) or 0, tonumber(r.matches) or 0, tonumber(r.msgs) or 0), player, 255, 120, 160)
    end, T.db(), [[
        SELECT (SELECT COUNT(*) FROM tinder_npc_photos WHERE image IS NOT NULL) AS done,
               (SELECT COUNT(*) FROM tinder_npc_photos) AS total,
               (SELECT COUNT(*) FROM tinder_npc_links WHERE matched_at IS NOT NULL) AS matches,
               (SELECT COUNT(*) FROM tinder_npc_messages) AS msgs
    ]])
end)

addEventHandler("onPlayerQuit", root, function() studio[source] = nil end)

----------------------------------------------------------------
-- Para rp_test
----------------------------------------------------------------
-- Valida el catalogo (escenarios, poses, gustos, arquetipos) y devuelve la lista de errores
function getTinderConfigErrors()
    local errors = {}
    for _, a in ipairs(TINDER_ARCHETYPES) do
        for _, s in ipairs(a.scenes) do if not TINDER_SCENES[s] then errors[#errors + 1] = a.id .. ": escenario " .. s end end
        for _, p in ipairs(a.poses) do if not TINDER_POSES[p] then errors[#errors + 1] = a.id .. ": pose " .. p end end
        for _, list in ipairs({ a.core, a.extra }) do
            for _, i in ipairs(list) do if not TINDER_INTEREST_BY_ID[i] then errors[#errors + 1] = a.id .. ": gusto " .. i end end
        end
        for _, z in ipairs(a.zones) do if not TINDER_ZONES[z] then errors[#errors + 1] = a.id .. ": barrio " .. z end end
        for _, g in ipairs(a.genders) do
            if not a.skins[g] or #a.skins[g] == 0 then errors[#errors + 1] = a.id .. ": sin skins " .. g end
            if not a.jobs[g] then errors[#errors + 1] = a.id .. ": sin trabajos " .. g end
        end
        for k in pairs(a.prompts) do if not TINDER_PROMPTS[k] then errors[#errors + 1] = a.id .. ": pregunta " .. k end end
        for _, part in ipairs({ "morning", "afternoon", "night" }) do
            if not a.day[part] then errors[#errors + 1] = a.id .. ": falta day." .. part end
        end
    end
    return errors
end

-- Simula una respuesta de un NPC (no toca la BD). Devuelve las burbujas y el interes final.
function tinderSimulateReply(npcId, text, interest, exchanges)
    local npc = T.npcs[tonumber(npcId) or 0] or npcList[1]
    if not npc then return false end
    local me = { name = "Prueba", gender = 0, interests = {}, bio = "", age = 25 }
    local bubbles, _, newInterest, state = compose(npc, me, { interest = interest or 50, exchanges = exchanges or 3 }, { tostring(text or "") })
    return { bubbles = bubbles, interest = newInterest, state = state, npc = npc.first }
end

function getTinderNpcCount() return #npcList end
