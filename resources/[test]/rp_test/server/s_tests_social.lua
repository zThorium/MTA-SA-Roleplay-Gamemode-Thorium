--[[
    rp_test / s_tests_social.lua

    Fotogram (rp_phone/server/s_social.lua). Sin jugadores no se puede abrir el
    telefono, pero toda la logica esta en funciones por personaje que se llaman
    con el export socialAction(token, accion, characterId, ...): son las mismas
    que usan los handlers de la interfaz, con sus validaciones y esperas.

    Crea una cuenta con tres personajes (A publica, B sigue y da like, C comenta)
    y la borra al final (todo cuelga de ON DELETE CASCADE).
]]

local PREFIX = "rptest_"
local JPEG = "/9j/" .. string.rep("ABCD", 60)   -- base64 con cabecera JPEG; el servidor no decodifica

-- Llama a una accion de Fotogram y espera rp:social:actionDone con su token
local seq = 0
local function social(cb, action, characterId, ...)
    seq = seq + 1
    local token = "t" .. seq
    local handler
    handler = function(tok, ok, result)
        if tok ~= token then return end
        removeEventHandler("rp:social:actionDone", root, handler)
        cb(ok, result)
    end
    addEventHandler("rp:social:actionDone", root, handler)
    if not exports.rp_phone:socialAction(token, action, characterId, ...) then
        removeEventHandler("rp:social:actionDone", root, handler)
        cb(false, "socialAction rechazo la accion " .. tostring(action))
    end
end

local function reset(id) exports.rp_phone:socialResetCooldowns(id) end

local function countNotifications(cb, recipient, kind, actor)
    query(function(rows)
        cb(rows and rows[1] and tonumber(rows[1].n) or -1)
    end, "SELECT COUNT(*) AS n FROM social_notifications WHERE character_id = ? AND type = ? AND actor_id = ?", recipient, kind, actor)
end

----------------------------------------------------------------
test("fotogram_config_poses_y_filtros", function(t)
    local errors = exports.rp_phone:getCameraConfigErrors()
    if type(errors) ~= "table" then return t.fail("getCameraConfigErrors no responde (rp_phone arrancado?)") end
    if #errors > 0 then return t.fail(table.concat(errors, "; ")) end
    t.pass("poses, poses por defecto y filtros validos")
end)

test("fotogram_cuenta_y_tres_personajes", function(t, ctx)
    local stamp = tostring(getRealTime().timestamp)
    local s = { stamp = stamp, chars = {} }
    ctx.social = s
    query(function(rows, _, accountId, code, msg)
        if not rows then return t.fail(("INSERT accounts: [%s] %s"):format(tostring(code), tostring(msg))) end
        s.accountId = accountId
        local previous = ctx.cleanup
        ctx.cleanup = function()
            if previous then pcall(previous) end
            query(function() end, "DELETE FROM accounts WHERE id = ?", accountId)
        end
        local names = { "Fotoa_" .. stamp, "Fotob_" .. stamp, "Fotoc_" .. stamp }
        local function create(i)
            if i > #names then return t.pass("personajes " .. table.concat(s.chars, ", ")) end
            query(function(r, _, id, c2, m2)
                if not r then return t.fail(("INSERT characters: [%s] %s"):format(tostring(c2), tostring(m2))) end
                s.chars[i] = id
                create(i + 1)
            end, [[
                INSERT INTO characters (account_id, name, gender, age, weight, height, origin, story, skin, money)
                VALUES (?, ?, 0, 25, 75, 180, 'Los Santos', 'Prueba de Fotogram.', 0, 0)
            ]], accountId, names[i])
        end
        create(1)
    end, "INSERT INTO accounts (username, password_hash) VALUES (?, ?)", PREFIX .. "social_" .. stamp, "x")
end)

test("fotogram_perfil_se_crea_una_vez", function(t, ctx)
    local s = ctx.social
    if not s or not s.chars[3] then return t.fail("sin personajes") end
    local A = s.chars[1]
    social(function(ok, p)
        if not ok then return t.fail(tostring(p)) end
        local expected = "fotoa." .. s.stamp
        if p.username ~= expected then return t.fail(("usuario %s, se esperaba %s"):format(tostring(p.username), expected)) end
        social(function(ok2, p2)
            if not ok2 or p2.username ~= expected then return t.fail("el segundo ensureProfile cambio el perfil") end
            -- B y C tambien abren Fotogram
            social(function()
                social(function(ok3, p3)
                    if not ok3 then return t.fail(tostring(p3)) end
                    s.userB = "fotob." .. s.stamp
                    t.pass("@" .. expected .. " (y @fotob, @fotoc)")
                end, "ensureProfile", s.chars[3])
            end, "ensureProfile", s.chars[2])
        end, "ensureProfile", A)
    end, "ensureProfile", A)
end)

test("fotogram_editar_perfil_valida_usuario", function(t, ctx)
    local s = ctx.social
    local B = s.chars[2]
    social(function(ok, msg)
        if ok then return t.fail("acepto un usuario de 2 letras") end
        reset(B)
        social(function(ok2, msg2)
            if ok2 then return t.fail("acepto el usuario de otro personaje") end
            if not tostring(msg2):find("en uso") then return t.fail("mensaje inesperado: " .. tostring(msg2)) end
            reset(B)
            local newName = "fotob_" .. s.stamp
            social(function(ok3, r3)
                if not ok3 then return t.fail("no guardo un usuario valido: " .. tostring(r3)) end
                s.userB = newName
                query(function(rows)
                    local r = rows and rows[1]
                    if not r or r.username ~= newName or r.bio ~= "Hola, soy B" then return t.fail("la BD no tiene los datos nuevos") end
                    t.pass("rechaza 'ab' y duplicados; guarda @" .. newName)
                end, "SELECT username, bio FROM social_profiles WHERE character_id = ?", B)
            end, "editProfile", B, "@" .. newName:upper(), "  Hola, soy B  ")
        end, "editProfile", B, "fotoa." .. s.stamp, "")
    end, "editProfile", B, "ab", "")
end)

test("fotogram_publicar_valida_foto_y_espera", function(t, ctx)
    local s = ctx.social
    local A = s.chars[1]
    social(function(ok)
        if ok then return t.fail("acepto una imagen que no es JPEG") end
        social(function(ok2, r2)
            if not ok2 then return t.fail("no publico una foto valida: " .. tostring(r2)) end
            s.postA = r2.id
            social(function(ok3, msg3)
                if ok3 then return t.fail("dejo publicar dos fotos seguidas") end
                query(function(rows)
                    local r = rows and rows[1]
                    if not r then return t.fail("no esta el post en la BD") end
                    if r.filter ~= "" then return t.fail("guardo un filtro inexistente: " .. tostring(r.filter)) end
                    if r.caption ~= "Mi primera foto con @" .. s.userB then return t.fail("pie de foto distinto: " .. tostring(r.caption)) end
                    t.pass("post " .. s.postA .. "; rechaza no-JPEG, filtro invalido y spam (" .. tostring(msg3) .. ")")
                end, "SELECT caption, filter FROM social_posts WHERE id = ?", s.postA)
            end, "post", A, "otra", JPEG, "noir")
        end, "post", A, "Mi primera foto con @" .. s.userB, JPEG, "filtro-que-no-existe")
    end, "post", A, "mala", "hola que tal", "noir")
end)

test("fotogram_mencion_en_pie_de_foto", function(t, ctx)
    local s = ctx.social
    -- La notificacion se crea despues de responder: se da un margen
    setTimer(function()
        countNotifications(function(n)
            if n ~= 1 then return t.fail(("B tiene %d menciones de A (esperado 1)"):format(n)) end
            t.pass("B recibe la mencion del pie de foto")
        end, s.chars[2], "mention", s.chars[1])
    end, 300, 1)
end)

test("fotogram_seguir_y_no_duplicar_aviso", function(t, ctx)
    local s = ctx.social
    local A, B = s.chars[1], s.chars[2]
    social(function(ok)
        if ok then return t.fail("se pudo seguir a si mismo") end
        social(function(ok2)
            if ok2 then return t.fail("se pudo seguir a un perfil inexistente") end
            reset(B)
            social(function(ok3, r3)
                if not ok3 or not r3.following or r3.followers ~= 1 then return t.fail("B no sigue a A: " .. tostring(r3 and r3.followers)) end
                reset(B)
                social(function()
                    reset(B)
                    social(function(ok5, r5)
                        if not ok5 or not r5.following or r5.followers ~= 1 then return t.fail("seguir de nuevo dejo un estado raro") end
                        setTimer(function()
                            countNotifications(function(n)
                                if n ~= 1 then return t.fail(("A tiene %d avisos de 'te sigue' de B (esperado 1)"):format(n)) end
                                t.pass("sigue, deja de seguir y vuelve: 1 seguidor y 1 aviso")
                            end, A, "follow", B)
                        end, 300, 1)
                    end, "follow", B, A, true)
                end, "follow", B, A, false)
            end, "follow", B, A, true)
        end, "follow", B, 4000000000, true)
    end, "follow", B, B, true)
end)

test("fotogram_feed_siguiendo_y_para_ti", function(t, ctx)
    local s = ctx.social
    local B, C = s.chars[2], s.chars[3]
    local function has(list, id)
        for _, p in ipairs(list or {}) do if p.id == id then return p end end
    end
    social(function(ok, listB)
        if not ok then return t.fail(tostring(listB)) end
        local p = has(listB, s.postA)
        if not p then return t.fail("B sigue a A y no ve su foto en Siguiendo") end
        if p.username ~= "fotoa." .. s.stamp or p.mine or p.image then return t.fail("datos del post incorrectos (o incluye la imagen)") end
        social(function(_, listC)
            if has(listC, s.postA) then return t.fail("C ve en Siguiendo la foto de alguien a quien no sigue") end
            social(function(_, allC)
                if not has(allC, s.postA) then return t.fail("C no ve la foto en Para ti") end
                social(function(_, older)
                    if has(older, s.postA) then return t.fail("la paginacion (beforeId) devuelve el mismo post") end
                    t.pass("Siguiendo filtra por seguidos, Para ti muestra todo y pagina por id")
                end, "feed", C, "all", s.postA)
            end, "feed", C, "all", 0)
        end, "feed", C, "following", 0)
    end, "feed", B, "following", 0)
end)

test("fotogram_like_alterna_y_avisa", function(t, ctx)
    local s = ctx.social
    local A, B = s.chars[1], s.chars[2]
    social(function(ok, r)
        if not ok or not r.liked or r.likes ~= 1 then return t.fail("el primer like no quedo") end
        setTimer(function()
            countNotifications(function(n)
                if n ~= 1 then return t.fail(("A tiene %d avisos de like (esperado 1)"):format(n)) end
                reset(B)
                social(function(ok2, r2)
                    if not ok2 or r2.liked or r2.likes ~= 0 then return t.fail("quitar el like no funciono") end
                    countNotifications(function(n2)
                        if n2 ~= 0 then return t.fail("el aviso de like sigue tras quitarlo") end
                        reset(B)
                        social(function(ok3, r3)
                            if not ok3 or not r3.liked then return t.fail("no se pudo volver a dar like") end
                            social(function(ok4)
                                if ok4 then return t.fail("dio like a un post inexistente") end
                                t.pass("like / quitar / like; aviso solo mientras dura el like")
                            end, "like", s.chars[3], 4000000000)
                        end, "like", B, s.postA)
                    end, A, "like", B)
                end, "like", B, s.postA)
            end, A, "like", B)
        end, 300, 1)
    end, "like", B, s.postA)
end)

test("fotogram_comentar_valida_y_menciona", function(t, ctx)
    local s = ctx.social
    local A, B, C = s.chars[1], s.chars[2], s.chars[3]
    local tricky = "Que buena!! @" .. s.userB .. " mira esto '); DROP TABLE social_posts; --"
    social(function(ok)
        if ok then return t.fail("acepto un comentario vacio") end
        social(function(ok2)
            if ok2 then return t.fail("acepto un comentario de 201 caracteres") end
            social(function(ok3, r3)
                if not ok3 then return t.fail("no comento: " .. tostring(r3)) end
                s.commentC = r3.id
                social(function(ok4)
                    if ok4 then return t.fail("dejo comentar dos veces seguidas (sin espera)") end
                    reset(C)
                    social(function(ok5)
                        if ok5 then return t.fail("comento en un post inexistente") end
                        setTimer(function()
                            countNotifications(function(nA)
                                countNotifications(function(nB)
                                    if nA ~= 1 or nB ~= 1 then return t.fail(("avisos: comentario a A=%d, mencion a B=%d"):format(nA, nB)) end
                                    query(function(rows)
                                        if not rows or not rows[1] or rows[1].body ~= tricky then return t.fail("el texto no se guardo tal cual") end
                                        t.pass("valida largo, espera y post; avisa al autor y al mencionado; SQL parametrizado")
                                    end, "SELECT body FROM social_comments WHERE id = ?", s.commentC)
                                end, B, "mention", C)
                            end, A, "comment", C)
                        end, 300, 1)
                    end, "comment", C, 4000000000, "hola")
                end, "comment", C, s.postA, "otra vez")
            end, "comment", C, s.postA, tricky)
        end, "comment", C, s.postA, string.rep("a", 201))
    end, "comment", C, s.postA, "    ")
end)

test("fotogram_lista_de_comentarios_y_permisos", function(t, ctx)
    local s = ctx.social
    local A, B, C = s.chars[1], s.chars[2], s.chars[3]
    social(function(ok, r)
        if not ok or #r.comments ~= 1 then return t.fail("la lista no trae el comentario") end
        local cmt = r.comments[1]
        if not cmt.canDelete then return t.fail("el autor del post no puede borrar comentarios de su foto") end
        social(function(_, rB)
            if rB.comments[1].canDelete then return t.fail("B podria borrar el comentario de C") end
            social(function(okDel)
                if okDel then return t.fail("B borro el comentario de C") end
                social(function(ok2)
                    if not ok2 then return t.fail("el autor del post no pudo borrar el comentario") end
                    query(function(rows)
                        if tonumber(rows[1].n) ~= 0 then return t.fail("el comentario sigue en la BD") end
                        t.pass("solo autor del comentario, autor del post o admin pueden borrar")
                    end, "SELECT COUNT(*) AS n FROM social_comments WHERE id = ?", s.commentC)
                end, "deleteComment", A, s.commentC, false)
            end, "deleteComment", B, s.commentC, false)
        end, "comments", B, s.postA, 0, false)
    end, "comments", A, s.postA, 0, false)
end)

test("fotogram_busqueda_escapa_comodines", function(t, ctx)
    local s = ctx.social
    local C = s.chars[3]
    social(function(ok, list)
        if not ok then return t.fail(tostring(list)) end
        local found
        for _, u in ipairs(list) do if u.username == s.userB then found = u end end
        if not found then return t.fail("no encuentra a B por su usuario") end
        reset(C)
        social(function(_, list2)
            if #list2 > 0 then return t.fail(("'%%%%' devolvio %d perfiles (LIKE sin escapar)"):format(#list2)) end
            reset(C)
            social(function(_, list3)
                local byName
                for _, u in ipairs(list3 or {}) do if u.id == s.chars[1] then byName = u end end
                if not byName then return t.fail("no encuentra a A por su nombre con espacio") end
                t.pass("por @usuario y por nombre; % y _ no son comodines")
            end, "search", C, "Fotoa " .. s.stamp)
        end, "search", C, "%%")
    end, "search", C, s.userB)
end)

test("fotogram_perfil_contadores_y_avatar", function(t, ctx)
    local s = ctx.social
    local A, B = s.chars[1], s.chars[2]
    social(function(ok)
        if ok then return t.fail("B puso de avatar una foto de A") end
        social(function(ok2)
            if not ok2 then return t.fail("A no pudo usar su foto de avatar") end
            social(function(ok3, p)
                if not ok3 then return t.fail(tostring(p)) end
                if p.posts ~= 1 or p.followers ~= 1 or p.following ~= 0 or not p.isFollowing or p.followsYou then
                    return t.fail(("contadores raros: posts=%s seguidores=%s siguiendo=%s"):format(p.posts, p.followers, p.following))
                end
                if p.avatar ~= s.postA or #p.grid ~= 1 or p.grid[1].likes ~= 1 then return t.fail("avatar o cuadricula incorrectos") end
                t.pass("1 foto, 1 seguidor, avatar y cuadricula con likes")
            end, "profile", B, A)
        end, "setAvatar", A, s.postA)
    end, "setAvatar", B, s.postA)
end)

test("fotogram_notificaciones_se_marcan_leidas", function(t, ctx)
    local s = ctx.social
    local A = s.chars[1]
    social(function(_, before)
        if (before or 0) < 3 then return t.fail("A deberia tener al menos 3 sin leer (seguidor, like, comentario): " .. tostring(before)) end
        social(function(ok, list)
            if not ok or #list < 3 then return t.fail("la lista de notificaciones esta incompleta") end
            local kinds = {}
            for _, n in ipairs(list) do kinds[n.type] = true end
            if not (kinds.follow and kinds.like and kinds.comment) then return t.fail("faltan tipos de notificacion") end
            social(function(_, after)
                if after ~= 0 then return t.fail("siguen " .. tostring(after) .. " sin leer tras abrirlas") end
                t.pass(before .. " sin leer -> 0 al abrir la lista")
            end, "unread", A)
        end, "notifications", A)
    end, "unread", A)
end)

test("fotogram_borrar_post_en_cascada", function(t, ctx)
    local s = ctx.social
    local A, B = s.chars[1], s.chars[2]
    social(function(ok)
        if ok then return t.fail("B borro la foto de A") end
        social(function(ok2)
            if not ok2 then return t.fail("A no pudo borrar su foto") end
            query(function(rows)
                local r = rows and rows[1]
                if not r then return t.fail("consulta de restos fallo") end
                local left = tonumber(r.likes) + tonumber(r.notif) + tonumber(r.comments)
                if left ~= 0 then return t.fail(left .. " filas de likes/comentarios/avisos quedaron huerfanas") end
                if r.avatar ~= nil and r.avatar ~= false then return t.fail("el avatar sigue apuntando a la foto borrada") end
                t.pass("borra likes, comentarios y avisos; quita el avatar")
            end, [[
                SELECT (SELECT COUNT(*) FROM social_likes WHERE post_id = ?) AS likes,
                       (SELECT COUNT(*) FROM social_notifications WHERE post_id = ?) AS notif,
                       (SELECT COUNT(*) FROM social_comments WHERE post_id = ?) AS comments,
                       (SELECT avatar_post_id FROM social_profiles WHERE character_id = ?) AS avatar
            ]], s.postA, s.postA, s.postA, A)
        end, "deletePost", A, s.postA, false)
    end, "deletePost", B, s.postA, false)
end)

test("fotogram_borrar_cuenta_limpia_todo", function(t, ctx)
    local s = ctx.social
    if not s or not s.accountId then return t.fail("sin cuenta") end
    query(function()
        query(function(rows)
            local n = rows and rows[1] and tonumber(rows[1].n)
            if n ~= 0 then return t.fail(tostring(n) .. " filas de Fotogram quedaron tras borrar la cuenta") end
            t.pass("perfiles, seguidores y avisos borrados en cascada")
        end, [[
            SELECT (SELECT COUNT(*) FROM social_profiles WHERE character_id IN (?, ?, ?))
                 + (SELECT COUNT(*) FROM social_follows WHERE follower_id IN (?, ?, ?) OR followed_id IN (?, ?, ?))
                 + (SELECT COUNT(*) FROM social_notifications WHERE character_id IN (?, ?, ?) OR actor_id IN (?, ?, ?)) AS n
        ]], s.chars[1], s.chars[2], s.chars[3], s.chars[1], s.chars[2], s.chars[3], s.chars[1], s.chars[2], s.chars[3],
            s.chars[1], s.chars[2], s.chars[3], s.chars[1], s.chars[2], s.chars[3])
    end, "DELETE FROM accounts WHERE id = ?", s.accountId)
end)
