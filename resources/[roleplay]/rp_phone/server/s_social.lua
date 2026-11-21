--[[
    rp_phone / s_social.lua
    Fotogram: la red social del telefono (estilo Instagram).

    - Perfiles (@usuario, biografia, foto de perfil), seguir / dejar de seguir.
    - Feed "Siguiendo" (tuyos + de quien sigues) y "Para ti" (todos), con paginas.
    - Likes, comentarios (con @menciones), borrar fotos y comentarios.
    - Busqueda de perfiles, Explorar (populares de la semana) y notificaciones.
    - Las fotos se piden una a una (rp:social:image, evento latente) y el
      telefono las guarda en cache: el feed solo lleva datos, no imagenes.

    Toda la logica esta en la tabla Social con funciones (characterId, ..., done).
    Los handlers de eventos validan al jugador (client, telefono, abatido) y
    llaman a esas funciones; rp_test usa las mismas mediante el export socialAction.

    Tablas: social_posts, social_likes, social_profiles, social_follows,
    social_comments, social_notifications (rp_database/schema.lua).
]]

local C = FOTOGRAM
local MAX_ID = 4294967295

Social = {}

local function db() return exports.rp_database:getConnection() end
local function notify(player, text, kind) exports.rp_notify:notify(player, text, kind) end
local function characterOf(player) return exports.rp_characters:getPlayerCharacterId(player) end
local function hasPhone(player) return characterOf(player) and exports.rp_inventory:hasItem(player, "phone", 1) end
local function isAdmin(player) return (exports.rp_login:getPlayerAdminLevel(player) or 0) >= 1 end

local function cleanText(s, maxLen)
    if type(s) ~= "string" then return nil end
    s = s:gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("  +", " ")
    if #s == 0 or #s > maxLen then return nil end
    return s
end

local function displayName(name) return (tostring(name or "?"):gsub("_", " ")) end

-- Escapa % _ y \ para usar el texto dentro de LIKE
local function likeEscape(s) return (s:gsub("[\\%%_]", "\\%0")) end

local function query(cb, sql, ...)
    local conn = db()
    if not conn then return cb(false) end
    dbQuery(function(qh)
        local result, a, b = dbPoll(qh, 0)
        cb(result, a, b)
    end, conn, sql, ...)
end

----------------------------------------------------------------
-- Esperas entre acciones (por personaje, no por jugador)
----------------------------------------------------------------
local lastAction = {}   -- [characterId] = { [accion] = tick }
local commentTicks = {} -- [characterId] = { tick, tick, ... } del ultimo minuto

local function cooldownOk(characterId, key)
    local now = getTickCount()
    local list = lastAction[characterId]
    if not list then list = {}; lastAction[characterId] = list end
    local wait = C.COOLDOWN[key] or 0
    if list[key] and now - list[key] < wait then return false end
    list[key] = now
    return true
end

local function commentRateOk(characterId)
    local now, kept = getTickCount(), {}
    for _, t in ipairs(commentTicks[characterId] or {}) do
        if now - t < 60000 then kept[#kept + 1] = t end
    end
    commentTicks[characterId] = kept
    if #kept >= C.COMMENTS_PER_MINUTE then return false end
    kept[#kept + 1] = now
    return true
end

-- Solo para rp_test: olvida las esperas de un personaje
function Social.resetCooldowns(characterId)
    lastAction[characterId], commentTicks[characterId] = nil, nil
end

----------------------------------------------------------------
-- Perfiles
----------------------------------------------------------------
-- "Juan_Perez" -> "juan.perez" (a-z 0-9 . _ ; 3 a 24 caracteres)
function Social.makeUsername(name, characterId)
    local u = tostring(name or ""):lower():gsub("_", "."):gsub("[^a-z0-9%._]", "")
    u = u:gsub("%.%.+", "."):gsub("^%.+", ""):gsub("%.+$", "")
    if #u < 3 then u = "usuario" .. tostring(characterId) end
    return u:sub(1, 24)
end

function Social.validUsername(u)
    return type(u) == "string" and #u >= 3 and #u <= 24 and u:match("^[a-z0-9%._]+$") ~= nil
        and not u:match("^%.") and not u:match("%.$") and not u:match("%.%.")
end

-- Crea el perfil la primera vez que el personaje abre Fotogram
function Social.ensureProfile(characterId, done)
    query(function(rows)
        if rows and rows[1] then return done(true, rows[1]) end
        query(function(chars)
            if not chars or not chars[1] then return done(false, "El personaje no existe.") end
            local base = Social.makeUsername(chars[1].name, characterId)
            local suffix = "." .. characterId
            local attempts = { base, base:sub(1, 24 - #suffix) .. suffix }
            local function try(i)
                if not attempts[i] then return done(false, "No se pudo crear el perfil.") end
                query(function(_, affected)
                    if affected and affected > 0 then
                        return done(true, { character_id = characterId, username = attempts[i], bio = "" })
                    end
                    try(i + 1)   -- usuario ocupado: prueba con el id
                end, "INSERT IGNORE INTO social_profiles (character_id, username) VALUES (?, ?)", characterId, attempts[i])
            end
            try(1)
        end, "SELECT name FROM characters WHERE id = ?", characterId)
    end, "SELECT character_id, username, bio, avatar_post_id FROM social_profiles WHERE character_id = ?", characterId)
end

function Social.profile(characterId, targetId, done)
    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then targetId = characterId end
    query(function(rows)
        local r = rows and rows[1]
        if not r then return done(false, "Ese perfil no existe.") end
        local profile = {
            id = tonumber(r.id), name = displayName(r.name), username = r.username, bio = r.bio or "",
            avatar = tonumber(r.avatar_post_id) or 0, posts = tonumber(r.posts) or 0,
            followers = tonumber(r.followers) or 0, following = tonumber(r.following) or 0,
            isFollowing = tonumber(r.is_following) == 1, followsYou = tonumber(r.follows_you) == 1,
            mine = tonumber(r.id) == characterId,
        }
        query(function(grid)
            profile.grid = {}
            for _, g in ipairs(grid or {}) do
                profile.grid[#profile.grid + 1] = { id = tonumber(g.id), likes = tonumber(g.likes) or 0, comments = tonumber(g.comments) or 0 }
            end
            done(true, profile)
        end, [[
            SELECT p.id,
                   (SELECT COUNT(*) FROM social_likes l WHERE l.post_id = p.id) AS likes,
                   (SELECT COUNT(*) FROM social_comments m WHERE m.post_id = p.id) AS comments
            FROM social_posts p WHERE p.character_id = ? ORDER BY p.id DESC LIMIT ?
        ]], profile.id, C.GRID_SIZE)
    end, [[
        SELECT c.id, c.name, sp.username, sp.bio, sp.avatar_post_id,
               (SELECT COUNT(*) FROM social_posts p WHERE p.character_id = c.id) AS posts,
               (SELECT COUNT(*) FROM social_follows f WHERE f.followed_id = c.id) AS followers,
               (SELECT COUNT(*) FROM social_follows f WHERE f.follower_id = c.id) AS following,
               EXISTS(SELECT 1 FROM social_follows f WHERE f.follower_id = ? AND f.followed_id = c.id) AS is_following,
               EXISTS(SELECT 1 FROM social_follows f WHERE f.follower_id = c.id AND f.followed_id = ?) AS follows_you
        FROM social_profiles sp JOIN characters c ON c.id = sp.character_id
        WHERE sp.character_id = ?
    ]], characterId, characterId, targetId)
end

function Social.editProfile(characterId, username, bio, done)
    if not cooldownOk(characterId, "profile") then return done(false, "Espera un momento antes de volver a guardar.") end
    username = type(username) == "string" and username:lower():gsub("^@", "") or ""
    if not Social.validUsername(username) then
        return done(false, "Usuario no valido: 3 a 24 caracteres, letras minusculas, numeros, punto o guion bajo.")
    end
    bio = type(bio) == "string" and (cleanText(bio, C.BIO_MAX) or (bio:match("^%s*$") and "")) or nil
    if not bio then return done(false, ("La biografia admite hasta %d caracteres."):format(C.BIO_MAX)) end
    query(function(ok, code)
        if ok == false then
            if code == 1062 then return done(false, "Ese nombre de usuario ya esta en uso.") end
            return done(false, "No se pudo guardar el perfil.")
        end
        done(true, { username = username, bio = bio })
    end, "UPDATE social_profiles SET username = ?, bio = ? WHERE character_id = ?", username, bio, characterId)
end

-- postId 0 quita la foto de perfil. Solo se puede usar una foto propia
function Social.setAvatar(characterId, postId, done)
    postId = tonumber(postId) or 0
    if not cooldownOk(characterId, "avatar") then return done(false, "Espera un momento.") end
    if postId <= 0 then
        return query(function() done(true, { avatar = 0 }) end,
            "UPDATE social_profiles SET avatar_post_id = NULL WHERE character_id = ?", characterId)
    end
    query(function(_, affected)
        if not affected or affected == 0 then
            -- 0 filas tambien si ya era esa foto: se comprueba
            return query(function(rows)
                if rows and rows[1] and tonumber(rows[1].avatar_post_id) == postId then return done(true, { avatar = postId }) end
                done(false, "Solo puedes usar una de tus fotos.")
            end, "SELECT avatar_post_id FROM social_profiles WHERE character_id = ?", characterId)
        end
        done(true, { avatar = postId })
    end, [[
        UPDATE social_profiles SET avatar_post_id = ?
        WHERE character_id = ? AND EXISTS(SELECT 1 FROM social_posts p WHERE p.id = ? AND p.character_id = ?)
    ]], postId, characterId, postId, characterId)
end

----------------------------------------------------------------
-- Notificaciones
----------------------------------------------------------------
local function playerByCharacter(characterId)
    for _, p in ipairs(getElementsByType("player")) do
        if characterOf(p) == characterId then return p end
    end
end

local PUSH_TEXT = {
    like = "le gusto tu foto", comment = "comento tu foto", follow = "empezo a seguirte", mention = "te menciono en un comentario",
}

function Social.unread(characterId, done)
    query(function(rows)
        done(true, rows and rows[1] and tonumber(rows[1].n) or 0)
    end, "SELECT COUNT(*) AS n FROM social_notifications WHERE character_id = ? AND is_read = 0", characterId)
end

local function pushBadge(characterId, actorName)
    local player = playerByCharacter(characterId)
    if not player then return end
    Social.unread(characterId, function(_, n)
        if isElement(player) then triggerClientEvent(player, "rp:social:badge", resourceRoot, n) end
    end)
    return player
end

-- Crea una notificacion para recipientId (nunca para uno mismo). like y follow no se repiten
function Social.addNotification(recipientId, actorId, kind, postId, text)
    if not recipientId or recipientId == actorId then return end
    local function insert()
        query(function(ok)
            if not ok then return end
            local player = pushBadge(recipientId)
            if player then
                query(function(rows)
                    local who = rows and rows[1] and rows[1].username or "Alguien"
                    if isElement(player) then notify(player, ("Fotogram: @%s %s."):format(who, PUSH_TEXT[kind] or ""), "info") end
                end, "SELECT username FROM social_profiles WHERE character_id = ?", actorId)
            end
        end, "INSERT INTO social_notifications (character_id, actor_id, type, post_id, text) VALUES (?, ?, ?, ?, ?)",
            recipientId, actorId, kind, postId, (text or ""):sub(1, 100))
    end
    if kind == "like" or kind == "follow" then
        query(insert, "DELETE FROM social_notifications WHERE character_id = ? AND actor_id = ? AND type = ? AND (post_id <=> ?)",
            recipientId, actorId, kind, postId)
    else
        insert()
    end
end

function Social.notifications(characterId, done)
    query(function(rows)
        local list = {}
        for _, r in ipairs(rows or {}) do
            list[#list + 1] = {
                id = tonumber(r.id), type = r.type, postId = tonumber(r.post_id) or 0, text = r.text or "",
                read = tonumber(r.is_read) == 1, date = r.date, actorId = tonumber(r.actor_id),
                username = r.username or Social.makeUsername(r.name, r.actor_id), avatar = tonumber(r.avatar_post_id) or 0,
                following = tonumber(r.following) == 1,
            }
        end
        query(function() done(true, list) end,
            "UPDATE social_notifications SET is_read = 1 WHERE character_id = ? AND is_read = 0", characterId)
    end, [[
        SELECT n.id, n.type, n.post_id, n.text, n.is_read, n.actor_id, c.name, sp.username, sp.avatar_post_id,
               DATE_FORMAT(n.created_at, '%d/%m %H:%i') AS date,
               EXISTS(SELECT 1 FROM social_follows f WHERE f.follower_id = ? AND f.followed_id = n.actor_id) AS following
        FROM social_notifications n
        JOIN characters c ON c.id = n.actor_id
        LEFT JOIN social_profiles sp ON sp.character_id = n.actor_id
        WHERE n.character_id = ?
        ORDER BY n.id DESC LIMIT 40
    ]], characterId, characterId)
end

----------------------------------------------------------------
-- Publicaciones
----------------------------------------------------------------
local POST_COLUMNS = [[
    p.id, p.caption, p.filter, p.character_id, c.name, sp.username, sp.avatar_post_id,
    DATE_FORMAT(p.created_at, '%d/%m %H:%i') AS date,
    (SELECT COUNT(*) FROM social_likes l WHERE l.post_id = p.id) AS likes,
    EXISTS(SELECT 1 FROM social_likes l WHERE l.post_id = p.id AND l.character_id = ?) AS liked,
    (SELECT COUNT(*) FROM social_comments m WHERE m.post_id = p.id) AS comments
]]

local function formatPost(r, viewerId)
    local authorId = tonumber(r.character_id)
    return {
        id = tonumber(r.id), caption = r.caption or "", filter = r.filter or "", date = r.date,
        authorId = authorId, author = displayName(r.name),
        username = r.username or Social.makeUsername(r.name, authorId), avatar = tonumber(r.avatar_post_id) or 0,
        likes = tonumber(r.likes) or 0, liked = tonumber(r.liked) == 1, comments = tonumber(r.comments) or 0,
        mine = authorId == viewerId,
    }
end

-- mode: "following" (tuyas y de quien sigues) o "all" (Para ti). beforeId para paginar
function Social.feed(characterId, mode, beforeId, done)
    beforeId = tonumber(beforeId)
    if not beforeId or beforeId <= 0 then beforeId = MAX_ID end
    local filter, args = "", { characterId, beforeId }
    if mode == "following" then
        filter = "AND (p.character_id = ? OR p.character_id IN (SELECT followed_id FROM social_follows WHERE follower_id = ?))"
        args[#args + 1] = characterId
        args[#args + 1] = characterId
    end
    args[#args + 1] = C.FEED_PAGE
    query(function(rows)
        local list = {}
        for _, r in ipairs(rows or {}) do list[#list + 1] = formatPost(r, characterId) end
        done(true, list)
    end, "SELECT " .. POST_COLUMNS .. [[
        FROM social_posts p JOIN characters c ON c.id = p.character_id
        LEFT JOIN social_profiles sp ON sp.character_id = p.character_id
        WHERE p.id < ? ]] .. filter .. " ORDER BY p.id DESC LIMIT ?", unpack(args))
end

function Social.getPost(characterId, postId, done)
    postId = tonumber(postId)
    if not postId then return done(false, "Publicacion no valida.") end
    query(function(rows)
        if not rows or not rows[1] then return done(false, "Esa publicacion ya no existe.") end
        done(true, formatPost(rows[1], characterId))
    end, "SELECT " .. POST_COLUMNS .. [[
        FROM social_posts p JOIN characters c ON c.id = p.character_id
        LEFT JOIN social_profiles sp ON sp.character_id = p.character_id
        WHERE p.id = ?
    ]], characterId, postId)
end

function Social.image(postId, done)
    postId = tonumber(postId)
    if not postId then return done(false) end
    query(function(rows)
        if not rows or not rows[1] then return done(false) end
        done(true, rows[1].image)
    end, "SELECT image FROM social_posts WHERE id = ?", postId)
end

-- JPEG en base64 (empieza por /9j/), tamano razonable y solo caracteres base64
function Social.validImage(image)
    return type(image) == "string" and #image >= 100 and #image <= C.MAX_IMAGE
        and image:sub(1, 4) == "/9j/" and image:match("^[%w%+/=]+$") ~= nil
end

function Social.post(characterId, caption, image, filter, done)
    caption = cleanText(caption or "", C.CAPTION_MAX) or ""
    if not Social.validImage(image) then return done(false, "La foto no es valida o es demasiado grande.") end
    filter = FOTOGRAM_FILTER_SET[filter] and filter or ""
    if not cooldownOk(characterId, "post") then return done(false, "Espera un poco antes de publicar otra foto.") end
    query(function(rows)
        local today = rows and rows[1] and tonumber(rows[1].n) or 0
        if today >= C.POSTS_PER_DAY then
            return done(false, ("Llegaste al maximo de %d fotos por dia."):format(C.POSTS_PER_DAY))
        end
        query(function(ok, _, insertId)
            if not ok then return done(false, "No se pudo publicar la foto.") end
            done(true, { id = insertId })
            Social.notifyMentions(characterId, insertId, caption, nil)
        end, "INSERT INTO social_posts (character_id, caption, filter, image) VALUES (?, ?, ?, ?)", characterId, caption, filter, image)
    end, "SELECT COUNT(*) AS n FROM social_posts WHERE character_id = ? AND created_at > NOW() - INTERVAL 1 DAY", characterId)
end

function Social.deletePost(characterId, postId, admin, done)
    postId = tonumber(postId)
    if not postId then return done(false, "Publicacion no valida.") end
    query(function(_, affected)
        if not affected or affected == 0 then return done(false, "No puedes borrar esa publicacion.") end
        done(true, { id = postId })
    end, "DELETE FROM social_posts WHERE id = ? AND (character_id = ? OR ? = 1)", postId, characterId, admin and 1 or 0)
end

-- Alterna el like. Devuelve el estado final y el total
function Social.like(characterId, postId, done)
    postId = tonumber(postId)
    if not postId then return done(false, "Publicacion no valida.") end
    if not cooldownOk(characterId, "like") then return done(false, nil) end
    local function finish(liked)
        query(function(rows)
            done(true, { id = postId, liked = liked, likes = rows and rows[1] and tonumber(rows[1].n) or 0 })
        end, "SELECT COUNT(*) AS n FROM social_likes WHERE post_id = ?", postId)
    end
    query(function(_, removed)
        if removed and removed > 0 then
            dbExec(db(), "DELETE FROM social_notifications WHERE actor_id = ? AND type = 'like' AND post_id = ?", characterId, postId)
            return finish(false)
        end
        -- INSERT ... SELECT: si la foto no existe no inserta nada
        query(function(_, added)
            if not added or added == 0 then return done(false, "Esa publicacion ya no existe.") end
            query(function(rows)
                if rows and rows[1] then Social.addNotification(tonumber(rows[1].character_id), characterId, "like", postId, "") end
            end, "SELECT character_id FROM social_posts WHERE id = ?", postId)
            finish(true)
        end, "INSERT IGNORE INTO social_likes (post_id, character_id) SELECT id, ? FROM social_posts WHERE id = ?", characterId, postId)
    end, "DELETE FROM social_likes WHERE post_id = ? AND character_id = ?", postId, characterId)
end

----------------------------------------------------------------
-- Comentarios
----------------------------------------------------------------
-- @usuario en un texto (hasta 3 distintos)
function Social.parseMentions(text)
    local found, seen = {}, {}
    for u in tostring(text or ""):gmatch("@([%w%._]+)") do
        u = u:lower():gsub("%.+$", "")
        if #u >= 3 and not seen[u] then
            seen[u] = true
            found[#found + 1] = u
            if #found == 3 then break end
        end
    end
    return found
end

-- Avisa a los mencionados (salvo al autor y a skipId, que ya recibe su propia notificacion)
function Social.notifyMentions(characterId, postId, text, skipId)
    local names = Social.parseMentions(text)
    if #names == 0 then return end
    local marks = ("?, "):rep(#names):sub(1, -3)
    query(function(rows)
        for _, r in ipairs(rows or {}) do
            local id = tonumber(r.character_id)
            if id ~= skipId then Social.addNotification(id, characterId, "mention", postId, text) end
        end
    end, "SELECT character_id FROM social_profiles WHERE username IN (" .. marks .. ")", unpack(names))
end

function Social.comments(characterId, postId, beforeId, admin, done)
    postId = tonumber(postId)
    if not postId then return done(false, "Publicacion no valida.") end
    beforeId = tonumber(beforeId)
    if not beforeId or beforeId <= 0 then beforeId = MAX_ID end
    query(function(rows)
        local list = {}
        for _, r in ipairs(rows or {}) do
            local authorId = tonumber(r.character_id)
            list[#list + 1] = {
                id = tonumber(r.id), body = r.body, date = r.date, authorId = authorId,
                username = r.username or Social.makeUsername(r.name, authorId), avatar = tonumber(r.avatar_post_id) or 0,
                canDelete = admin or authorId == characterId or tonumber(r.post_owner) == characterId,
            }
        end
        done(true, { postId = postId, comments = list, more = #list == C.COMMENTS_PAGE })
    end, [[
        SELECT m.id, m.body, m.character_id, c.name, sp.username, sp.avatar_post_id, p.character_id AS post_owner,
               DATE_FORMAT(m.created_at, '%d/%m %H:%i') AS date
        FROM social_comments m
        JOIN social_posts p ON p.id = m.post_id
        JOIN characters c ON c.id = m.character_id
        LEFT JOIN social_profiles sp ON sp.character_id = m.character_id
        WHERE m.post_id = ? AND m.id < ?
        ORDER BY m.id DESC LIMIT ?
    ]], postId, beforeId, C.COMMENTS_PAGE)
end

function Social.comment(characterId, postId, text, done)
    postId = tonumber(postId)
    text = cleanText(text, C.COMMENT_MAX)
    if not postId then return done(false, "Publicacion no valida.") end
    if not text then return done(false, ("El comentario debe tener entre 1 y %d caracteres."):format(C.COMMENT_MAX)) end
    if not cooldownOk(characterId, "comment") then return done(false, "Vas muy rapido, espera un momento.") end
    if not commentRateOk(characterId) then return done(false, "Demasiados comentarios seguidos. Espera un minuto.") end
    query(function(ok, affected, insertId)
        if not ok then return done(false, "No se pudo publicar el comentario.") end
        if not affected or affected == 0 then return done(false, "Esa publicacion ya no existe.") end
        query(function(rows)
            local owner = rows and rows[1] and tonumber(rows[1].character_id)
            Social.addNotification(owner, characterId, "comment", postId, text)
            Social.notifyMentions(characterId, postId, text, owner)
        end, "SELECT character_id FROM social_posts WHERE id = ?", postId)
        done(true, { id = insertId, postId = postId })
    end, "INSERT INTO social_comments (post_id, character_id, body) SELECT id, ?, ? FROM social_posts WHERE id = ?", characterId, text, postId)
end

-- Borra el autor del comentario, el autor de la foto o un admin
function Social.deleteComment(characterId, commentId, admin, done)
    commentId = tonumber(commentId)
    if not commentId then return done(false, "Comentario no valido.") end
    query(function(rows)
        local postId = rows and rows[1] and tonumber(rows[1].post_id)
        if not postId then return done(false, "Ese comentario ya no existe.") end
        query(function(_, affected)
            if not affected or affected == 0 then return done(false, "No puedes borrar ese comentario.") end
            done(true, { id = commentId, postId = postId })
        end, [[
            DELETE m FROM social_comments m JOIN social_posts p ON p.id = m.post_id
            WHERE m.id = ? AND (? = 1 OR m.character_id = ? OR p.character_id = ?)
        ]], commentId, admin and 1 or 0, characterId, characterId)
    end, "SELECT post_id FROM social_comments WHERE id = ?", commentId)
end

----------------------------------------------------------------
-- Seguir
----------------------------------------------------------------
function Social.follow(characterId, targetId, follow, done)
    targetId = tonumber(targetId)
    if not targetId then return done(false, "Perfil no valido.") end
    if targetId == characterId then return done(false, "No puedes seguirte a ti mismo.") end
    if not cooldownOk(characterId, "follow") then return done(false, "Espera un momento.") end
    local function finish()
        query(function(rows)
            local r = rows and rows[1] or {}
            done(true, { id = targetId, following = tonumber(r.following) == 1, followers = tonumber(r.followers) or 0 })
        end, [[
            SELECT (SELECT COUNT(*) FROM social_follows WHERE followed_id = ?) AS followers,
                   EXISTS(SELECT 1 FROM social_follows WHERE follower_id = ? AND followed_id = ?) AS following
        ]], targetId, characterId, targetId)
    end
    if follow then
        -- Solo se puede seguir a quien tiene perfil
        query(function(ok, affected)
            if not ok then return done(false, "No se pudo seguir a ese perfil.") end
            if affected and affected > 0 then
                Social.addNotification(targetId, characterId, "follow", nil, "")
                return finish()
            end
            query(function(rows)
                if not rows or not rows[1] then return done(false, "Ese perfil no existe.") end
                finish()   -- ya lo seguia
            end, "SELECT 1 FROM social_profiles WHERE character_id = ?", targetId)
        end, "INSERT IGNORE INTO social_follows (follower_id, followed_id) SELECT ?, character_id FROM social_profiles WHERE character_id = ?", characterId, targetId)
    else
        query(function()
            dbExec(db(), "DELETE FROM social_notifications WHERE character_id = ? AND actor_id = ? AND type = 'follow'", targetId, characterId)
            finish()
        end, "DELETE FROM social_follows WHERE follower_id = ? AND followed_id = ?", characterId, targetId)
    end
end

-- which: "followers" (le siguen) o "following" (a quien sigue)
function Social.follows(characterId, targetId, which, done)
    targetId = tonumber(targetId)
    if not targetId then return done(false, "Perfil no valido.") end
    local joinCol, whereCol = "f.follower_id", "f.followed_id"
    if which == "following" then joinCol, whereCol = "f.followed_id", "f.follower_id" else which = "followers" end
    query(function(rows)
        local list = {}
        for _, r in ipairs(rows or {}) do
            local id = tonumber(r.id)
            list[#list + 1] = {
                id = id, name = displayName(r.name), username = r.username or Social.makeUsername(r.name, id),
                avatar = tonumber(r.avatar_post_id) or 0, following = tonumber(r.following) == 1, me = id == characterId,
            }
        end
        done(true, { id = targetId, which = which, list = list })
    end, ([[
        SELECT %s AS id, c.name, sp.username, sp.avatar_post_id,
               EXISTS(SELECT 1 FROM social_follows x WHERE x.follower_id = ? AND x.followed_id = %s) AS following
        FROM social_follows f
        JOIN characters c ON c.id = %s
        LEFT JOIN social_profiles sp ON sp.character_id = %s
        WHERE %s = ?
        ORDER BY f.created_at DESC LIMIT 100
    ]]):format(joinCol, joinCol, joinCol, joinCol, whereCol), characterId, targetId)
end

----------------------------------------------------------------
-- Busqueda y Explorar
----------------------------------------------------------------
function Social.search(characterId, text, done)
    text = cleanText(text, 32)
    if not text or #text < 2 then return done(true, {}) end
    if not cooldownOk(characterId, "search") then return done(false, nil) end
    text = text:lower():gsub("^@", "")
    local asName = likeEscape(text:gsub(" ", "_"))
    local pattern = "%" .. likeEscape(text) .. "%"
    query(function(rows)
        local list = {}
        for _, r in ipairs(rows or {}) do
            local id = tonumber(r.id)
            list[#list + 1] = {
                id = id, name = displayName(r.name), username = r.username, avatar = tonumber(r.avatar_post_id) or 0,
                followers = tonumber(r.followers) or 0, following = tonumber(r.following) == 1, me = id == characterId,
            }
        end
        done(true, list)
    end, [[
        SELECT sp.character_id AS id, c.name, sp.username, sp.avatar_post_id,
               (SELECT COUNT(*) FROM social_follows f WHERE f.followed_id = sp.character_id) AS followers,
               EXISTS(SELECT 1 FROM social_follows f WHERE f.follower_id = ? AND f.followed_id = sp.character_id) AS following
        FROM social_profiles sp JOIN characters c ON c.id = sp.character_id
        WHERE sp.username LIKE ? OR c.name LIKE ?
        ORDER BY (sp.username LIKE ?) DESC, followers DESC, sp.username
        LIMIT 20
    ]], characterId, pattern, "%" .. asName .. "%", likeEscape(text) .. "%")
end

-- Las mas gustadas de la ultima semana y, detras, las mas recientes
function Social.explore(characterId, done)
    query(function(rows)
        local list = {}
        for _, r in ipairs(rows or {}) do
            list[#list + 1] = { id = tonumber(r.id), likes = tonumber(r.likes) or 0, comments = tonumber(r.comments) or 0 }
        end
        done(true, list)
    end, [[
        SELECT p.id,
               (SELECT COUNT(*) FROM social_likes l WHERE l.post_id = p.id) AS likes,
               (SELECT COUNT(*) FROM social_comments m WHERE m.post_id = p.id) AS comments
        FROM social_posts p
        ORDER BY (p.created_at > NOW() - INTERVAL 7 DAY) DESC, likes DESC, p.id DESC
        LIMIT ?
    ]], C.GRID_SIZE)
end

----------------------------------------------------------------
-- Export para otros recursos del servidor (y rp_test). No se pueden pasar
-- funciones entre recursos, asi que el resultado llega con el evento
-- "rp:social:actionDone" (token, ok, resultado) disparado en el root.
----------------------------------------------------------------
local EXPORTED = {
    ensureProfile = true, profile = true, editProfile = true, setAvatar = true, feed = true, getPost = true,
    post = true, deletePost = true, like = true, comments = true, comment = true, deleteComment = true,
    follow = true, follows = true, search = true, explore = true, notifications = true, unread = true,
}
addEvent("rp:social:actionDone", false)

function socialAction(token, action, characterId, ...)
    characterId = tonumber(characterId)
    if not EXPORTED[action] or not characterId then return false end
    local args = { ... }
    args[#args + 1] = function(ok, result) triggerEvent("rp:social:actionDone", root, token, ok == true, result) end
    Social[action](characterId, unpack(args))
    return true
end

function socialResetCooldowns(characterId) Social.resetCooldowns(tonumber(characterId)) return true end

----------------------------------------------------------------
-- Eventos del telefono
----------------------------------------------------------------
local CLIENT_EVENTS = {
    "open", "feed", "image", "post", "like", "deletePost", "getPost", "comments", "comment", "deleteComment",
    "profile", "editProfile", "setAvatar", "follow", "follows", "search", "explore", "notifications",
}
for _, name in ipairs(CLIENT_EVENTS) do addEvent("rp:social:" .. name, true) end

-- Comprueba al jugador y llama fn(player, characterId) si puede usar Fotogram
local function handle(name, fn)
    addEventHandler("rp:social:" .. name, resourceRoot, function(...)
        local player = client
        if not player or getElementData(player, "rp:downed") or not hasPhone(player) then return end
        fn(player, characterOf(player), ...)
    end)
end

local function reply(player, event, ...)
    if isElement(player) then triggerClientEvent(player, event, resourceRoot, ...) end
end

-- Respuesta generica: si falla avisa con rp_notify; si va bien manda el evento al telefono
local function answer(player, event, silentFail)
    return function(ok, result)
        if not isElement(player) then return end
        if not ok then
            if result and not silentFail then notify(player, result, "error") end
            return
        end
        if event then reply(player, event, result) end
    end
end

handle("open", function(player, characterId)
    Social.ensureProfile(characterId, function(ok, profile)
        if not ok then return answer(player)(ok, profile) end
        Social.unread(characterId, function(_, n)
            reply(player, "rp:social:me", { id = characterId, username = profile.username, avatar = tonumber(profile.avatar_post_id) or 0, unread = n })
        end)
    end)
end)

handle("feed", function(player, characterId, mode, beforeId)
    mode = mode == "all" and "all" or "following"
    Social.feed(characterId, mode, beforeId, function(ok, list)
        if ok then reply(player, "rp:social:feed", list, mode, tonumber(beforeId) and tonumber(beforeId) > 0) end
    end)
end)

-- Fotos bajo demanda, con limite por jugador (las pide el telefono segun las muestra)
local imageWindow = {}
handle("image", function(player, _, postId)
    postId = tonumber(postId)
    if not postId then return end
    local now = getTickCount()
    local w = imageWindow[player]
    if not w or now - w.start > 10000 then w = { start = now, n = 0 }; imageWindow[player] = w end
    w.n = w.n + 1
    if w.n > 120 then return reply(player, "rp:social:image", postId, false, true) end   -- el telefono reintenta luego
    Social.image(postId, function(ok, data)
        if not isElement(player) then return end
        if ok then triggerLatentClientEvent(player, "rp:social:image", 200000, false, resourceRoot, postId, data)
        else reply(player, "rp:social:image", postId, false) end
    end)
end)

local posting = {}
handle("post", function(player, characterId, caption, image, filter)
    if posting[player] then return end
    posting[player] = true
    Social.post(characterId, caption, image, filter, function(ok, result)
        posting[player] = nil
        if not isElement(player) then return end
        if not ok then
            notify(player, result, "error")
            return reply(player, "rp:social:posted", false)
        end
        notify(player, "Publicaste una foto en Fotogram.", "success")
        reply(player, "rp:social:posted", result.id)
    end)
end)

handle("like", function(player, characterId, postId)
    Social.like(characterId, postId, answer(player, "rp:social:likeState", true))
end)

handle("deletePost", function(player, characterId, postId)
    Social.deletePost(characterId, postId, isAdmin(player), function(ok, result)
        answer(player, "rp:social:postDeleted")(ok, result)
        if ok and isElement(player) then notify(player, "Publicacion eliminada.", "info") end
    end)
end)

handle("getPost", function(player, characterId, postId)
    Social.getPost(characterId, postId, answer(player, "rp:social:post"))
end)

handle("comments", function(player, characterId, postId, beforeId)
    Social.comments(characterId, postId, beforeId, isAdmin(player), function(ok, result)
        if ok then result.append = tonumber(beforeId) ~= nil and tonumber(beforeId) > 0 end
        answer(player, "rp:social:comments")(ok, result)
    end)
end)

handle("comment", function(player, characterId, postId, text)
    Social.comment(characterId, postId, text, function(ok, result)
        if not ok then return answer(player)(ok, result) end
        -- Devuelve la lista actualizada a quien comento
        Social.comments(characterId, result.postId, nil, isAdmin(player), answer(player, "rp:social:comments"))
    end)
end)

handle("deleteComment", function(player, characterId, commentId)
    Social.deleteComment(characterId, commentId, isAdmin(player), function(ok, result)
        if not ok then return answer(player)(ok, result) end
        Social.comments(characterId, result.postId, nil, isAdmin(player), answer(player, "rp:social:comments"))
    end)
end)

handle("profile", function(player, characterId, targetId)
    Social.profile(characterId, targetId, answer(player, "rp:social:profile"))
end)

handle("editProfile", function(player, characterId, username, bio)
    Social.editProfile(characterId, username, bio, function(ok, result)
        if not ok then return answer(player)(ok, result) end
        notify(player, "Perfil actualizado.", "success")
        Social.profile(characterId, characterId, answer(player, "rp:social:profile"))
    end)
end)

handle("setAvatar", function(player, characterId, postId)
    Social.setAvatar(characterId, postId, function(ok, result)
        if not ok then return answer(player)(ok, result) end
        notify(player, result.avatar > 0 and "Foto de perfil actualizada." or "Foto de perfil quitada.", "success")
        Social.profile(characterId, characterId, answer(player, "rp:social:profile"))
    end)
end)

handle("follow", function(player, characterId, targetId, follow)
    Social.follow(characterId, targetId, follow == true, answer(player, "rp:social:followState"))
end)

handle("follows", function(player, characterId, targetId, which)
    Social.follows(characterId, targetId, which, answer(player, "rp:social:follows"))
end)

handle("search", function(player, characterId, text)
    Social.search(characterId, text, function(ok, list)
        if ok then reply(player, "rp:social:search", tostring(text or ""), list) end
    end)
end)

handle("explore", function(player, characterId)
    Social.explore(characterId, answer(player, "rp:social:explore"))
end)

handle("notifications", function(player, characterId)
    Social.notifications(characterId, function(ok, list)
        answer(player, "rp:social:notifications")(ok, list)
        if ok then reply(player, "rp:social:badge", 0) end
    end)
end)

addEventHandler("onPlayerQuit", root, function()
    posting[source], imageWindow[source] = nil, nil
end)

----------------------------------------------------------------
-- Mantenimiento y admin
----------------------------------------------------------------
local function pruneNotifications()
    local conn = db()
    if conn then
        dbExec(conn, "DELETE FROM social_notifications WHERE created_at < NOW() - INTERVAL ? DAY", C.NOTIFY_DAYS)
    end
end
addEvent("rp:onDatabaseReady", false)
addEventHandler("rp:onDatabaseReady", root, pruneNotifications)
addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then pruneNotifications() end
end)

-- /borrarpost <id>: un admin elimina una foto de Fotogram (con sus likes y comentarios)
addCommandHandler("borrarpost", function(player, _, id)
    if not isAdmin(player) then return end
    id = tonumber(id)
    if not id then return outputChatBox("Uso: /borrarpost <id de la publicacion>", player, 255, 200, 0) end
    Social.deletePost(characterOf(player) or 0, id, true, function(ok, result)
        if not isElement(player) then return end
        if ok then outputChatBox(("Publicacion %d de Fotogram eliminada."):format(id), player, 120, 220, 120)
        else outputChatBox(result or "No existe esa publicacion.", player, 255, 120, 120) end
    end)
end)
