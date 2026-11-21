--[[
    rp_admin / c_debug.lua
    /copiardebug [X]: copia al portapapeles las ultimas X lineas del debugscript.

    El cliente guarda en un buffer circular (DEBUG_BUFFER_MAX lineas) todo lo que
    llega por onClientDebugMessage. MTA solo envia esos mensajes cuando el debug esta
    activo, asi que antes hay que hacer /debug 3. El servidor decide quien puede usar
    el comando (admin_level >= 1) y manda aqui el evento rp:admin:copyDebug.
]]

local DEBUG_BUFFER_MAX = 300
local LEVEL_NAME = { [0] = "CUSTOM", [1] = "ERROR", [2] = "WARNING", [3] = "INFO" }

local buffer, head, size = {}, 0, 0   -- buffer circular

addEvent("rp:admin:copyDebug", true)

addEventHandler("onClientDebugMessage", root, function(message, level, file, line)
    head = head % DEBUG_BUFFER_MAX + 1
    buffer[head] = {
        time = getRealTime(),
        level = level, file = file, line = line, text = tostring(message),
    }
    if size < DEBUG_BUFFER_MAX then size = size + 1 end
end)

local function format(entry)
    local t = entry.time
    local where = entry.file and entry.file ~= "" and ("%s:%s: "):format(entry.file, tostring(entry.line or "?")) or ""
    return ("[%02d:%02d:%02d] %s %s%s"):format(t.hour, t.minute, t.second, LEVEL_NAME[entry.level] or "?", where, entry.text)
end

addEventHandler("rp:admin:copyDebug", resourceRoot, function(count)
    count = math.floor(tonumber(count) or 10)
    if size == 0 then
        return exports.rp_notify:notify("No hay lineas de debug guardadas. Activa el debug con /debug 3 y repite el problema.", "warning")
    end
    count = math.max(1, math.min(count, size))
    local lines = {}
    for i = count - 1, 0, -1 do
        local idx = (head - 1 - i) % DEBUG_BUFFER_MAX + 1
        lines[#lines + 1] = format(buffer[idx])
    end
    if setClipboard(table.concat(lines, "\n")) then
        exports.rp_notify:notify(("Copiadas %d lineas del debug al portapapeles."):format(count), "success")
    else
        exports.rp_notify:notify("No se pudo copiar al portapapeles (la ventana de MTA debe tener el foco).", "error")
    end
end)
