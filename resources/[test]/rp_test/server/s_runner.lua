--[[
    rp_test / s_runner.lua

    Mini framework de pruebas asincronas para el servidor (sin jugadores).
    Cada prueba recibe un objeto t y debe terminar con t.pass(detalle) o
    t.fail(motivo). Las pruebas corren en orden, una detras de otra, porque
    casi todas esperan respuestas de MySQL. Si una no termina en TIMEOUT_MS
    se marca FAIL y se sigue con la siguiente.

    Salida (consola y logs/server.log), pensada para leerla con grep:
        [rp_test] INICIO <n> pruebas
        [rp_test] PASS  nombre - detalle
        [rp_test] FAIL  nombre - motivo
        [rp_test] RESULTADO: <x> PASS, <y> FAIL
        [rp_test] FIN OK | FIN FALLOS

    Comando de consola del servidor: rptest   (vuelve a ejecutar todo)
]]

TIMEOUT_MS = 15000

local tests = {}
local running = false

local function out(msg)
    -- outputDebugString del servidor sale en la consola y en logs/server.log ("INFO: [rp_test] ...")
    outputDebugString("[rp_test] " .. msg, 3)
end

-- Registra una prueba. fn(t, ctx): ctx es una tabla compartida entre pruebas
function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

function runTests()
    if running then return out("Ya hay una ejecucion en curso") end
    running = true

    local ctx, passed, failed, index = {}, 0, 0, 0
    out(("INICIO %d pruebas"):format(#tests))

    local nextTest
    nextTest = function()
        index = index + 1
        local case = tests[index]
        if not case then
            -- Las pruebas pueden registrar una limpieza final en ctx.cleanup
            if type(ctx.cleanup) == "function" then pcall(ctx.cleanup) end
            out(("RESULTADO: %d PASS, %d FAIL"):format(passed, failed))
            out(failed == 0 and "FIN OK" or "FIN FALLOS")
            running = false
            return
        end

        local finished = false
        local timer
        local function finish(ok, detail)
            if finished then return end
            finished = true
            if isTimer(timer) then killTimer(timer) end
            if ok then passed = passed + 1 else failed = failed + 1 end
            out(("%s  %s%s"):format(ok and "PASS" or "FAIL", case.name, detail and (" - " .. tostring(detail)) or ""))
            -- setTimer en vez de llamada directa: corta la recursion entre callbacks de dbQuery
            setTimer(nextTest, 50, 1)
        end

        local t = {
            pass = function(detail) finish(true, detail) end,
            fail = function(reason) finish(false, reason or "sin detalle") end,
        }
        timer = setTimer(function() finish(false, "timeout (" .. TIMEOUT_MS .. " ms)") end, TIMEOUT_MS, 1)

        local ok, err = pcall(case.fn, t, ctx)
        if not ok then finish(false, "error Lua: " .. tostring(err)) end
    end

    nextTest()
end

-- Consulta asincrona: cb(rows, affected, insertId, errCode, errMsg)
function query(cb, sql, ...)
    local db = exports.rp_database:getConnection()
    if not db then return cb(false, nil, nil, -1, "sin conexion (rp_database)") end
    dbQuery(function(qh)
        local result, a, b = dbPoll(qh, 0)
        if result == false then
            cb(false, nil, nil, a, b)          -- a = codigo de error, b = mensaje
        else
            cb(result, a, b)                   -- a = filas afectadas, b = ultimo id insertado
        end
    end, db, sql, ...)
end

addCommandHandler("rptest", function(source)
    if getElementType(source) ~= "console" then return end
    runTests()
end)

addEventHandler("onResourceStart", resourceRoot, function()
    -- Pequena espera para que los recursos incluidos terminen su onResourceStart
    setTimer(runTests, 500, 1)
end)
