--[[
    rp_firefighters / s_admin.lua  (servidor)

    Admin (nivel 1; catálogo en rp_adminpanel/server/s_catalog.lua):
        /fdmover <vestuario|garaje|camion>   mueve un punto de la estación a tu posición
        /fdsitio crear <nombre>              crea un sitio de incendio; tu posición es la zona segura (ambulancia)
        /fdsitio foco <id>                   añade un foco de fuego donde estás (azotea, balcón...)
        /fdsitio civil <id>                  añade un punto de civil atrapado donde estás (y con tu rumbo)
        /fdsitio vaciar <id>                 quita todos los focos y civiles del sitio
        /fdsitio borrar <id>                 borra el sitio
        /fdsitios                            lista los sitios
        /fdincendio [id]                     lanza una emergencia ya (sin id, en un sitio al azar)
        /fdcancelar                          cancela la emergencia activa
    Solo en el mundo abierto (interior 0, dimensión 0).
]]

local KIND_OF = { vestuario = "locker", garaje = "garage", camion = "truck" }

local function where(p)
    if getElementInterior(p) ~= 0 or getElementDimension(p) ~= 0 then return nil end
    local x, y, z = getElementPosition(p)
    local _, _, rz = getElementRotation(p)
    return x, y, z, rz
end

local function say(p, text, kind) FD.notify(p, text, kind) end

addCommandHandler("fdmover", function(p, _, which)
    if not FD.isAdmin(p, 1) then return end
    local kind = KIND_OF[tostring(which or ""):lower()]
    if not kind then return say(p, "Uso: /fdmover <vestuario|garaje|camion>", "error") end
    local x, y, z, rz = where(p)
    if not x then return say(p, "Solo en el mundo abierto.", "error") end
    dbExec(FD.db(), "REPLACE INTO fire_points (kind, x, y, z, rot) VALUES (?, ?, ?, ?, ?)", kind, x, y, z, rz)
    FD.placePoint(kind, x, y, z, rz)
    say(p, ("Punto %s movido aquí."):format(which), "success")
    FD.log(("%s movió el punto %s"):format(getPlayerName(p), kind))
end)

local function siteCount(s) return #s.fires, #s.victims end

addCommandHandler("fdsitio", function(p, _, action, ...)
    if not FD.isAdmin(p, 1) then return end
    action = tostring(action or ""):lower()
    local args = { ... }
    local x, y, z, rz = where(p)
    if not x then return say(p, "Solo en el mundo abierto.", "error") end

    if action == "crear" then
        local name = table.concat(args, " "):gsub("[%c<>]", ""):sub(1, 48)
        if #name < 3 then return say(p, "Uso: /fdsitio crear <nombre> (de pie donde irá la ambulancia)", "error") end
        dbQuery(function(qh)
            local _, _, id = dbPoll(qh, 0)
            if not id then return say(p, "No se pudo crear el sitio.", "error") end
            FD.loadSites(function()
                if isElement(p) then say(p, ("Sitio #%d \"%s\" creado. Ahora sube y añade focos (/fdsitio foco %d) y civiles (/fdsitio civil %d)."):format(id, name, id, id), "success") end
            end)
        end, FD.db(), "INSERT INTO fire_sites (name, x, y, z) VALUES (?, ?, ?, ?)", name, x, y, z)
        return
    end

    local id = tonumber(args[1])
    local site = id and FD.getSites()[id]
    if action == "foco" or action == "civil" or action == "vaciar" or action == "borrar" then
        if not site then return say(p, "Uso: /fdsitio " .. action .. " <id> (lista con /fdsitios)", "error") end
        local inc = FD.getIncident()
        if inc and inc.site.id == id then return say(p, "Ese sitio tiene una emergencia activa (/fdcancelar).", "error") end
    end

    if action == "foco" or action == "civil" then
        local kind = action == "foco" and "fire" or "victim"
        if getDistanceBetweenPoints2D(x, y, site.x, site.y) > 120 then
            return say(p, "Demasiado lejos de la zona segura del sitio (máx. 120 m).", "error")
        end
        dbExec(FD.db(), "INSERT INTO fire_site_points (site_id, kind, x, y, z, rot) VALUES (?, ?, ?, ?, ?, ?)", id, kind, x, y, z, rz)
        FD.loadSites(function()
            local s = FD.getSites()[id]
            if isElement(p) and s then
                local f, v = siteCount(s)
                say(p, ("%s añadido a #%d. Tiene %d focos y %d civiles."):format(action == "foco" and "Foco" or "Civil", id, f, v), "success")
            end
        end)
    elseif action == "vaciar" then
        dbExec(FD.db(), "DELETE FROM fire_site_points WHERE site_id = ?", id)
        FD.loadSites()
        say(p, ("Sitio #%d sin focos ni civiles."):format(id), "success")
    elseif action == "borrar" then
        dbExec(FD.db(), "DELETE FROM fire_sites WHERE id = ?", id)   -- los puntos caen con ON DELETE CASCADE
        FD.loadSites()
        say(p, ("Sitio #%d borrado."):format(id), "success")
        FD.log(("%s borró el sitio %d"):format(getPlayerName(p), id))
    else
        say(p, "Uso: /fdsitio <crear|foco|civil|vaciar|borrar> ...", "error")
    end
end)

addCommandHandler("fdsitios", function(p)
    if not FD.isAdmin(p, 1) then return end
    local n = 0
    for id, s in pairs(FD.getSites()) do
        n = n + 1
        local f, v = siteCount(s)
        local d = FD.dist(p, s.x, s.y, s.z)
        outputChatBox(("#%d %s · %d focos · %d civiles · a %.0f m%s"):format(id, s.name, f, v, d,
            (f == 0 or v == 0) and " · INCOMPLETO" or ""), p, 235, 140, 80)
    end
    if n == 0 then say(p, "No hay sitios. Crea uno con /fdsitio crear <nombre>.", "info") end
end)

addCommandHandler("fdincendio", function(p, _, id)
    if not FD.isAdmin(p, 1) then return end
    id = tonumber(id)
    if not id then
        local list = {}
        for sid, s in pairs(FD.getSites()) do if #s.fires > 0 and #s.victims > 0 then list[#list + 1] = sid end end
        if #list == 0 then return say(p, "No hay sitios completos.", "error") end
        id = list[math.random(#list)]
    end
    local ok, why = FD.startIncident(id)
    say(p, ok and ("Emergencia lanzada en el sitio #%d."):format(id) or why, ok and "success" or "error")
end)

addCommandHandler("fdcancelar", function(p)
    if not FD.isAdmin(p, 1) then return end
    say(p, FD.cancelIncident() and "Emergencia cancelada." or "No hay emergencia activa.", "info")
end)
