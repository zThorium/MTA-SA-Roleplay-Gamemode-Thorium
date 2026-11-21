--[[
    rp_database / s_database.lua

    Abre una unica conexion MySQL (dbConnect) y la comparte con el resto de
    recursos via exports.rp_database:getConnection().

    Uso desde otro recurso (siempre asincrono, nunca dbPoll(qh, -1) en el
    hilo principal porque congela el servidor mientras espera a MySQL):

        local db = exports.rp_database:getConnection()
        dbQuery(function(qh)
            local rows = dbPoll(qh, 0)
            ...
        end, db, "SELECT * FROM accounts WHERE id = ?", id)
]]

local connection = nil
local ready = false

local function log(msg, level)
    outputDebugString("[rp_database] " .. msg, level or 3)
end

local function connect()
    local c = DB_CONFIG
    local host = ("dbname=%s;host=%s;port=%d;charset=%s"):format(c.dbname, c.host, c.port, c.charset)

    -- share=1 permite reutilizar la conexion; autoreconnect=1 recupera caidas de MySQL
    connection = dbConnect("mysql", host, c.user, c.password, "share=1;autoreconnect=1")
    if not connection then
        log("No se pudo conectar a MySQL en " .. c.host .. ":" .. c.port .. ". Revisa que MariaDB este encendido y config.lua.", 1)
        return false
    end

    log("Conectado a MySQL (" .. c.dbname .. "@" .. c.host .. ")")
    return true
end

-- Ejecuta las sentencias del esquema en orden y avisa cuando termina.
local function applySchema(index)
    index = index or 1
    local statement = SCHEMA[index]
    if not statement then
        ready = true
        log("Esquema verificado (" .. #SCHEMA .. " sentencias). Base de datos lista.")
        triggerEvent("rp:onDatabaseReady", resourceRoot)
        return
    end

    dbQuery(function(qh)
        local result, err, msg = dbPoll(qh, 0)
        if result == false then
            -- Se registra y se continua: una sentencia fallida no debe bloquear el resto
            log(("Error en sentencia %d del esquema: [%s] %s"):format(index, tostring(err), tostring(msg)), 1)
        end
        applySchema(index + 1)
    end, connection, statement)
end

addEvent("rp:onDatabaseReady", false)

addEventHandler("onResourceStart", resourceRoot, function()
    if not connect() then
        cancelEvent(true, "Sin conexion a MySQL")
        return
    end
    applySchema()
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if isElement(connection) then
        destroyElement(connection)
    end
end)

-- EXPORT: handle de la conexion (elemento db-connection)
function getConnection()
    return connection
end

-- EXPORT: true cuando la conexion existe y las tablas estan creadas
function isReady()
    return ready and isElement(connection)
end

-- EXPORT: copia de las sentencias de schema.lua (la usa rp_test para comprobar que
-- existen todas las tablas y columnas). Solo texto, sin credenciales.
function getSchema()
    local copy = {}
    for i, statement in ipairs(SCHEMA) do copy[i] = statement end
    return copy
end
