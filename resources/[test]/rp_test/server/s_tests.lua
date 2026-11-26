--[[
    rp_test / s_tests.lua

    Pruebas de humo del lado servidor. No hay jugadores conectados, asi que no se
    llaman los handlers de la interfaz: se reproducen las mismas consultas que usan
    rp_login, rp_characters, rp_inventory y rp_bank (mismas columnas, mismo patron de
    cobro atomico) contra la base real, con una cuenta de prueba que se borra al final.

    Para anadir una prueba: test("nombre", function(t, ctx) ... t.pass() / t.fail("motivo") end)
    Mantener el orden: las de cuenta/personaje dejan ids en ctx para las siguientes.
]]

local PREFIX = "rptest_"   -- toda cuenta de prueba empieza asi (se limpia al empezar y al acabar)
local PASSWORD = "Prueba-1234"

----------------------------------------------------------------
-- Base de datos
----------------------------------------------------------------
test("bd_conectada_y_esquema_aplicado", function(t)
    local tries = 0
    local function check()
        if exports.rp_database:isReady() then
            return query(function(rows, _, _, code, msg)
                if not rows then return t.fail(("SELECT 1 fallo: [%s] %s"):format(tostring(code), tostring(msg))) end
                t.pass("rp_database:isReady() = true")
            end, "SELECT 1 AS ok")
        end
        tries = tries + 1
        if tries > 20 then return t.fail("rp_database no quedo listo en 10 s (mira 'Error en sentencia' en el log)") end
        setTimer(check, 500, 1)
    end
    check()
end)

test("recursos_roleplay_arrancados", function(t)
    local down = {}
    local total = 0
    for _, res in ipairs(getResources()) do
        if getResourceOrganizationalPath(res) == "[roleplay]" then
            total = total + 1
            local state = getResourceState(res)
            if state ~= "running" then
                local reason = getResourceLoadFailureReason(res)
                down[#down + 1] = getResourceName(res) .. "=" .. state .. (reason ~= "" and (" (" .. reason .. ")") or "")
            end
        end
    end
    if total == 0 then return t.fail("no se encontro ningun recurso en [roleplay]") end
    if #down > 0 then return t.fail(table.concat(down, ", ")) end
    t.pass(total .. " recursos en marcha")
end)

-- Recorre las sentencias de rp_database/schema.lua y comprueba que existen todas las
-- tablas (CREATE TABLE) y columnas (ALTER TABLE ... ADD COLUMN) en la base
test("esquema_tablas_y_columnas", function(t)
    local schema = exports.rp_database:getSchema()
    if type(schema) ~= "table" or #schema == 0 then return t.fail("rp_database:getSchema() vacio") end
    -- Se anade "]]" al final de cada sentencia para poder cortar los ALTER con el mismo patron
    local src = table.concat(schema, "]]\n") .. "]]"

    local tables, columns = {}, {}
    for name in src:gmatch("CREATE TABLE IF NOT EXISTS%s+`?([%w_]+)") do tables[#tables + 1] = name end
    for tbl, body in src:gmatch("ALTER TABLE%s+`?([%w_]+)`?(.-)%]%]") do
        for col in body:gmatch("ADD COLUMN IF NOT EXISTS%s+`?([%w_]+)") do
            columns[#columns + 1] = { tbl, col }
        end
    end

    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("information_schema: [%s] %s"):format(tostring(code), tostring(msg))) end
        local have = {}
        for _, r in ipairs(rows) do have[r.t:lower() .. "." .. r.c:lower()] = true; have[r.t:lower()] = true end

        local missing = {}
        for _, name in ipairs(tables) do
            if not have[name:lower()] then missing[#missing + 1] = "tabla " .. name end
        end
        for _, tc in ipairs(columns) do
            if not have[tc[1]:lower() .. "." .. tc[2]:lower()] then missing[#missing + 1] = tc[1] .. "." .. tc[2] end
        end
        if #missing > 0 then return t.fail("faltan: " .. table.concat(missing, ", ")) end
        t.pass(("%d tablas y %d columnas añadidas por ALTER"):format(#tables, #columns))
    end, [[
        SELECT TABLE_NAME AS t, COLUMN_NAME AS c FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
    ]])
end)

----------------------------------------------------------------
-- Cuentas (rp_login)
----------------------------------------------------------------
test("limpiar_restos_de_pruebas_anteriores", function(t)
    query(function(rows, affected, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass((affected or 0) .. " cuentas de prueba antiguas borradas")
    end, "DELETE FROM accounts WHERE username LIKE ?", PREFIX .. "%")
end)

test("bcrypt_hash_y_verificacion", function(t, ctx)
    passwordHash(PASSWORD, "bcrypt", { cost = 10 }, function(hash)
        if not hash then return t.fail("passwordHash devolvio false") end
        ctx.hash = hash
        passwordVerify(PASSWORD, hash, {}, function(ok)
            if not ok then return t.fail("la contraseña correcta no verifica") end
            passwordVerify("otra-cosa", hash, {}, function(bad)
                if bad then return t.fail("una contraseña incorrecta verifica") end
                t.pass("hash " .. hash:sub(1, 7) .. "...")
            end)
        end)
    end)
end)

test("registro_de_cuenta", function(t, ctx)
    if not ctx.hash then return t.fail("sin hash (fallo la prueba anterior)") end
    ctx.username = PREFIX .. getRealTime().timestamp
    -- Misma consulta que rp_login/server/s_auth.lua
    query(function(rows, _, insertId, code, msg)
        if not rows then return t.fail(("INSERT accounts: [%s] %s"):format(tostring(code), tostring(msg))) end
        ctx.accountId = insertId
        ctx.cleanup = function()
            query(function() end, "DELETE FROM accounts WHERE id = ?", insertId)
        end
        t.pass("cuenta " .. ctx.username .. " id " .. tostring(insertId))
    end, "INSERT INTO accounts (username, password_hash, serial, ip) VALUES (?, ?, ?, ?)",
        ctx.username, ctx.hash, string.rep("0", 32), "127.0.0.1")
end)

test("registro_duplicado_rechazado", function(t, ctx)
    if not ctx.accountId then return t.fail("sin cuenta de prueba") end
    query(function(rows, _, _, code)
        if rows then return t.fail("se pudo registrar dos veces el mismo usuario") end
        if code ~= 1062 then return t.fail("error inesperado " .. tostring(code) .. " (se esperaba 1062)") end
        t.pass("1062 duplicate entry")
    end, "INSERT INTO accounts (username, password_hash) VALUES (?, ?)", ctx.username, ctx.hash)
end)

test("login_de_cuenta", function(t, ctx)
    if not ctx.accountId then return t.fail("sin cuenta de prueba") end
    query(function(rows)
        local row = rows and rows[1]
        if not row then return t.fail("no se encuentra la cuenta por username") end
        passwordVerify(PASSWORD, row.password_hash, {}, function(ok)
            if not ok then return t.fail("passwordVerify con la contraseña guardada fallo") end
            query(function(res, _, _, code, msg)
                if not res then return t.fail(("login_log: [%s] %s"):format(tostring(code), tostring(msg))) end
                t.pass("verificado y registrado en login_log")
            end, "INSERT INTO login_log (account_id, username, serial, ip, success) VALUES (?, ?, ?, ?, 1)",
                row.id, ctx.username, string.rep("0", 32), "127.0.0.1")
        end)
    end, "SELECT id, password_hash, admin_level FROM accounts WHERE username = ? LIMIT 1", ctx.username)
end)

----------------------------------------------------------------
-- Personajes (rp_characters)
----------------------------------------------------------------
test("creacion_de_personaje", function(t, ctx)
    if not ctx.accountId then return t.fail("sin cuenta de prueba") end
    local skins = exports.rp_characters:getAllowedSkins(0)
    if type(skins) ~= "table" or #skins == 0 then return t.fail("rp_characters:getAllowedSkins(0) vacio") end

    ctx.charName = "Prueba_" .. getRealTime().timestamp
    -- Misma consulta que rp_characters/server/s_characters.lua (variante sin cabeza)
    query(function(rows, _, insertId, code, msg)
        if not rows then return t.fail(("INSERT characters: [%s] %s"):format(tostring(code), tostring(msg))) end
        ctx.characterId = insertId
        query(function(r)
            local c = r and r[1]
            if not c then return t.fail("no se lee el personaje recien creado") end
            if tonumber(c.hunger) ~= 100 or tonumber(c.bank_money) ~= 0 then
                return t.fail(("valores por defecto raros: hunger=%s bank_money=%s"):format(tostring(c.hunger), tostring(c.bank_money)))
            end
            t.pass(ctx.charName .. " id " .. tostring(insertId) .. ", skin " .. skins[1])
        end, "SELECT * FROM characters WHERE id = ?", insertId)
    end, [[
        INSERT INTO characters (account_id, name, gender, age, weight, height, origin, story, skin, money)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], ctx.accountId, ctx.charName, 0, 25, 75, 180, "Los Santos", "Personaje de prueba automatica.", skins[1], 500)
end)

test("nombre_de_personaje_duplicado_rechazado", function(t, ctx)
    if not ctx.characterId then return t.fail("sin personaje de prueba") end
    query(function(rows, _, _, code)
        if rows then return t.fail("se creo un segundo personaje con el mismo nombre") end
        if code ~= 1062 then return t.fail("error inesperado " .. tostring(code)) end
        t.pass("1062 duplicate entry")
    end, [[
        INSERT INTO characters (account_id, name, gender, age, weight, height, origin, story, skin, money)
        VALUES (?, ?, 0, 25, 75, 180, 'x', 'x', 26, 0)
    ]], ctx.accountId, ctx.charName)
end)

----------------------------------------------------------------
-- Perfil del Tab (rp_scoreboard)
----------------------------------------------------------------
test("perfil_tab_guardar_y_leer", function(t, ctx)
    if not ctx.characterId then return t.fail("sin personaje de prueba") end
    -- Mismo upsert que saveRow de rp_scoreboard/server/s_scoreboard.lua (dos veces: inserta y actualiza)
    local upsert = [[
        INSERT INTO scoreboard_profiles (character_id, name_color, name_color2, name_effect, icon, flag, avatar, avatar_version)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE name_color = VALUES(name_color), name_color2 = VALUES(name_color2), name_effect = VALUES(name_effect),
        icon = VALUES(icon), flag = VALUES(flag), avatar = VALUES(avatar), avatar_version = VALUES(avatar_version)
    ]]
    query(function(r1, _, _, c1, m1)
        if not r1 then return t.fail(("upsert: [%s] %s"):format(tostring(c1), tostring(m1))) end
        query(function(r2)
            if not r2 then return t.fail("segundo upsert fallo") end
            query(function(rows)
                local p = rows and rows[1]
                if not p then return t.fail("no se lee el perfil") end
                if p.name_effect ~= "rainbow" or p.flag ~= "mx" or p.avatar ~= "" or tonumber(p.avatar_version) ~= 0 then
                    return t.fail(("valores raros: efecto=%s bandera=%s"):format(tostring(p.name_effect), tostring(p.flag)))
                end
                t.pass("perfil insertado y actualizado")
            end, "SELECT * FROM scoreboard_profiles WHERE character_id = ?", ctx.characterId)
        end, upsert, ctx.characterId, "#ff4d6d", "", "rainbow", "fire", "mx", "", 0)
    end, upsert, ctx.characterId, "#f5a524", "#ff6a3d", "shine", "crown", "cl", "data:image/png;base64,AA==", 1)
end)

----------------------------------------------------------------
-- Inventario (rp_inventory)
----------------------------------------------------------------
test("inventario_dar_y_quitar_items", function(t, ctx)
    if not ctx.characterId then return t.fail("sin personaje de prueba") end
    local def = exports.rp_inventory:getItemDefinition("water")
    if type(def) ~= "table" or not def.name then return t.fail("rp_inventory:getItemDefinition('water') no devuelve el item") end

    -- Mismo upsert que giveItem
    local give = [[
        INSERT INTO character_items (character_id, item_id, amount) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)
    ]]
    query(function(r1, _, _, c1, m1)
        if not r1 then return t.fail(("giveItem SQL: [%s] %s"):format(tostring(c1), tostring(m1))) end
        query(function(r2)
            if not r2 then return t.fail("segundo giveItem fallo") end
            query(function(r3, affected)
                if not r3 or affected ~= 1 then return t.fail("no se pudo quitar 1 unidad") end
                query(function(r4, affectedBad)
                    if affectedBad ~= 0 then return t.fail("se pudieron quitar mas unidades de las que hay") end
                    query(function(rows)
                        local amount = rows and rows[1] and tonumber(rows[1].amount)
                        if amount ~= 2 then return t.fail("cantidad final " .. tostring(amount) .. ", se esperaba 2") end
                        t.pass(def.name .. ": 2 + 1 - 1 = 2, y no deja quedar en negativo")
                    end, "SELECT amount FROM character_items WHERE character_id = ? AND item_id = ?", ctx.characterId, "water")
                end, "UPDATE character_items SET amount = amount - ? WHERE character_id = ? AND item_id = ? AND amount >= ?",
                    99, ctx.characterId, "water", 99)
            end, "UPDATE character_items SET amount = amount - ? WHERE character_id = ? AND item_id = ? AND amount >= ?",
                1, ctx.characterId, "water", 1)
        end, give, ctx.characterId, "water", 1)
    end, give, ctx.characterId, "water", 2)
end)

----------------------------------------------------------------
-- Banco (rp_bank) y cobro atomico (regla 5 de CLAUDE.md)
----------------------------------------------------------------
test("banco_deposito_y_cobro_atomico", function(t, ctx)
    if not ctx.characterId then return t.fail("sin personaje de prueba") end
    local id = ctx.characterId
    local charge = "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?"

    query(function(r1, _, _, c1, m1)
        if not r1 then return t.fail(("deposito: [%s] %s"):format(tostring(c1), tostring(m1))) end
        query(function(r2, ok1)
            if ok1 ~= 1 then return t.fail("el cobro de 300 con saldo 1000 no afecto filas") end
            query(function(r3, ok2)
                if ok2 ~= 0 then return t.fail("el cobro de 5000 con saldo 700 paso (deberia afectar 0 filas)") end
                query(function(r4, _, _, c4, m4)
                    if not r4 then return t.fail(("bank_transactions: [%s] %s"):format(tostring(c4), tostring(m4))) end
                    query(function(rows)
                        local balance = rows and rows[1] and tonumber(rows[1].bank_money)
                        if balance ~= 700 then return t.fail("saldo final " .. tostring(balance) .. ", se esperaba 700") end
                        t.pass("1000 - 300 = 700; cobro sin saldo rechazado")
                    end, "SELECT bank_money FROM characters WHERE id = ?", id)
                end, "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, ?, ?, ?)",
                    id, "deposit", 1000, "")
            end, charge, 5000, id, 5000)
        end, charge, 300, id, 300)
    end, "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", 1000, id)
end)

----------------------------------------------------------------
-- Limpieza
----------------------------------------------------------------
test("borrar_cuenta_en_cascada", function(t, ctx)
    if not ctx.accountId then return t.fail("sin cuenta de prueba") end
    query(function(rows, affected)
        if not rows or affected ~= 1 then return t.fail("no se borro la cuenta de prueba") end
        ctx.cleanup = nil
        -- login_log usa ON DELETE SET NULL: sus filas se quedarian; se borran aparte
        query(function() end, "DELETE FROM login_log WHERE username LIKE ?", PREFIX .. "%")
        query(function(r)
            local left = r and r[1] and tonumber(r[1].n)
            if left ~= 0 then return t.fail(tostring(left) .. " filas huerfanas (personajes/items) tras borrar la cuenta") end
            t.pass("cuenta, personaje, items y movimientos borrados")
        end, [[
            SELECT (SELECT COUNT(*) FROM characters WHERE id = ?)
                 + (SELECT COUNT(*) FROM character_items WHERE character_id = ?)
                 + (SELECT COUNT(*) FROM bank_transactions WHERE character_id = ?) AS n
        ]], ctx.characterId or 0, ctx.characterId or 0, ctx.characterId or 0)
    end, "DELETE FROM accounts WHERE id = ?", ctx.accountId)
end)
