--[[
    rp_jobs / jobs/s_hunter.lua  -  Cazador

    1. Ve a una zona de caza (quad incluido, se puede dejar aparcado).
    2. Sigue el rastro: en cada huella, minijuego "tracks" (elige la huella fresca entre tres).
       Fallar alarga el rastro; tardar más de HUNTER.TRACK_COLD_MS entre huellas lo enfría y se pierde.
    3. Al final del rastro, minijuego "scope": mira telescópica con viento y distancia.
       Disparo vital = pieza perfecta; al cuerpo = peor calidad; fallo = el animal huye
       (y si es un jabalí o un oso, carga contra ti).
    4. Minijuego "skin": preparar la pieza siguiendo la línea. Da carne, piel y a veces trofeo
       al inventario; se venden en la peletería (precios dinámicos).
]]

local H = HUNTER

local function newTrail(player, s, fromX, fromY, steps, reason)
    local d = s.data
    local zone = d.zone
    local x = fromX or (zone[1] + math.random(-50, 50))
    local y = fromY or (zone[2] + math.random(-50, 50))
    local heading = math.random(0, 359)
    d.trail, d.ti = {}, 0
    for i = 1, steps do
        heading = heading + math.random(-55, 55)
        local step = math.random(H.TRACK_STEP[1], H.TRACK_STEP[2])
        x = x + math.cos(math.rad(heading)) * step
        y = y + math.sin(math.rad(heading)) * step
        -- que no se aleje demasiado del centro de la zona
        local dx, dy = x - zone[1], y - zone[2]
        if dx * dx + dy * dy > 220 * 220 then heading = heading + 180 end
        d.trail[i] = { x, y, zone[3] }
    end
    d.animal = Jobs.pickWeighted(H.ANIMALS, Jobs.level(player, "hunter"))
    if reason then Jobs.notify(player, reason, "info", 6000) end
end

local function nextTrack(player, s)
    local d = s.data
    d.ti = d.ti + 1
    d.lastTrack = getTickCount()
    if d.ti > #d.trail then
        local p = d.trail[#d.trail]
        Jobs.hud(player, "¡Hay algo cerca! Acércate con sigilo", "Rastro completo")
        return Jobs.waypoint(player, { kind = "animal", x = p[1], y = p[2], z = p[3], r = 4, mode = "foot", act = "press",
            flat = true, blip = false, marker = "corona", text = "Pulsa E para apuntar", label = "Animal" })
    end
    local p = d.trail[d.ti]
    Jobs.hud(player, "Sigue el rastro", ("Huella %d/%d"):format(d.ti, #d.trail))
    Jobs.waypoint(player, { kind = "track", x = p[1], y = p[2], z = p[3], r = 3, mode = "foot", act = "press", flat = true,
        blip = false, marker = "corona", small = true, text = "Pulsa E para examinar la huella", label = "Huella" })
end

local function goToZone(player, s)
    local d = s.data
    d.zone = H.ZONES[math.random(#H.ZONES)]
    Jobs.hud(player, "Ve a la zona de caza marcada", "")
    Jobs.waypoint(player, { kind = "zone", x = d.zone[1], y = d.zone[2], z = d.zone[3], r = 60, mode = "any", act = "enter",
        flat = true, label = "Zona de caza", marker = "none" })
end

Jobs.register("hunter", {
    perks = {
        "Con nivel 2 aparecen jabalíes; con nivel 4, osos.",
        "Un disparo vital y un buen despiece dan piel intacta y trofeos.",
    },

    start = function(player, s)
        Jobs.spawnVehicle(player, JOBS_BY_ID.hunter.vehicle)
        s.needsVehicle = false
        s.data = {}
        Jobs.notify(player, "Toma el quad si quieres y ve a la zona de caza. A partir de ahí, a pie y en silencio.", "info", 7000)
        goToZone(player, s)
    end,

    onReach = function(player, s, wp)
        local d = s.data
        if wp.kind == "zone" then
            newTrail(player, s, nil, nil, math.random(H.TRACKS[1], H.TRACKS[2]), "Encontraste un rastro. Bájate y síguelo a pie.")
            nextTrack(player, s)
        elseif wp.kind == "track" then
            Jobs.anim(player, "BOMBER", "BOM_Plant_Loop", true)
            Jobs.game(player, "tracks", { animal = d.animal.id, difficulty = Jobs.level(player) >= 3 and 0.6 or 0.4 }, 1500)
        elseif wp.kind == "animal" then
            Jobs.hold(player, 357, { 0, 0, 0, 0, 0, 0 })
            Jobs.anim(player, "RIFLE", "RIFLE_crouchload", false)
            d.wind = math.floor((math.random() * 2 - 1) * 100) / 100
            Jobs.game(player, "scope", { animal = d.animal.id, name = d.animal.name, difficulty = d.animal.difficulty,
                wind = d.wind, distance = math.random(70, 190) }, 2500)
        elseif wp.kind == "carcass" then
            Jobs.anim(player, "BOMBER", "BOM_Plant_Loop", true)
            Jobs.game(player, "skin", { animal = d.animal.id, points = 7 }, 4000)
        end
    end,

    onGame = function(player, s, name, r, ctx)
        local d = s.data
        Jobs.anim(player, false)
        if name == "tracks" then
            if r.cancel then return nextTrack(player, s) end
            if r.correct and not r.fail then
                Jobs.xp(player, 3)
                Jobs.notify(player, "Huella fresca. El rastro sigue.", "success")
            else
                -- Rastro falso: un tramo más
                local last = d.trail[d.ti]
                local extra = { last[1] + math.random(-35, 35), last[2] + math.random(-35, 35), last[3] }
                table.insert(d.trail, d.ti + 1, extra)
                Jobs.notify(player, "Esa huella era vieja. Pierdes tiempo dando un rodeo.", "warning")
            end
            return nextTrack(player, s)

        elseif name == "scope" then
            Jobs.hold(player, false)
            if r.cancel then
                local p = d.trail[#d.trail]
                return Jobs.waypoint(player, { kind = "animal", x = p[1], y = p[2], z = p[3], r = 4, mode = "foot", act = "press",
                    flat = true, blip = false, marker = "corona", text = "Pulsa E para apuntar", label = "Animal" })
            end
            local hit = (not r.fail) and r.hit
            if hit ~= "vital" and hit ~= "body" then
                if d.animal.charges then
                    setElementHealth(player, math.max(5, getElementHealth(player) - 20))
                    Jobs.notify(player, ("¡El %s te embistió antes de huir!"):format(d.animal.name:lower()), "error")
                else
                    Jobs.notify(player, ("Fallaste. El %s huyó."):format(d.animal.name:lower()), "warning")
                end
                local p = d.trail[#d.trail]
                newTrail(player, s, p[1], p[2], 2, nil)
                return nextTrack(player, s)
            end
            d.shot = hit
            Jobs.xp(player, hit == "vital" and 12 or 6)
            local p = d.trail[#d.trail]
            Jobs.hud(player, ("Prepara el %s"):format(d.animal.name:lower()), hit == "vital" and "Disparo limpio" or "Disparo al cuerpo")
            Jobs.waypoint(player, { kind = "carcass", x = p[1], y = p[2], z = p[3], r = 4, mode = "foot", act = "press",
                flat = true, blip = false, marker = "corona", text = "Pulsa E para preparar la pieza", label = "Pieza" })

        elseif name == "skin" then
            local acc = (r.cancel or r.fail) and 0.2 or math.max(0, math.min(1, tonumber(r.accuracy) or 0))
            local quality = (d.shot == "vital" and 1 or 0.6) * (0.5 + acc * 0.5)
            local a = d.animal
            local got = {}
            local meat = math.max(1, math.floor(a.meat * quality + 0.5))
            if Jobs.give(player, "meat_game", meat) > 0 then got[#got + 1] = meat .. "x carne" end
            if acc >= 0.45 then
                if Jobs.give(player, a.hide, 1) > 0 then got[#got + 1] = Jobs.itemName(a.hide):lower() end
            else
                Jobs.notify(player, "La piel quedó destrozada.", "warning")
            end
            if a.trophy and d.shot == "vital" and acc >= 0.75 and math.random() < 0.6 then
                if Jobs.give(player, a.trophy, 1) > 0 then got[#got + 1] = Jobs.itemName(a.trophy):lower() end
            end
            if #got > 0 then Jobs.notify(player, "Conseguiste: " .. table.concat(got, ", ") .. ".", "success", 6000) end
            Jobs.xp(player, 10 + math.floor(acc * 8))
            -- otro rastro cerca, en la misma zona
            local p = d.trail[#d.trail]
            newTrail(player, s, p[1], p[2], math.random(H.TRACKS[1], H.TRACKS[2]), "Hay otro rastro cerca. Las piezas se venden en la peletería de la cabaña.")
            nextTrack(player, s)
        end
    end,

    tick = function(player, s, now)
        local d = s.data
        if d.trail and d.ti and d.ti >= 1 and d.ti <= #d.trail and not s.game and d.lastTrack and now - d.lastTrack > H.TRACK_COLD_MS then
            local p = d.trail[d.ti]
            newTrail(player, s, p[1], p[2], math.random(H.TRACKS[1], H.TRACKS[2]), "El rastro se enfrió. Encontraste otro cerca de aquí.")
            nextTrack(player, s)
        end
    end,
})
