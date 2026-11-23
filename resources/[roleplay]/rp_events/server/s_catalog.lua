--[[
    rp_events / s_catalog.lua
    Catalogo de eventos compartidos propios. Cada evento es DATOS (peso, horas, clima,
    cooldown...) mas una funcion build(H) que crea la escena con los ayudantes
    de s_director.lua. Las posiciones son relativas al punto elegido:
        f = metros hacia delante (sentido de la via), r = metros a la derecha.

    Otros recursos registran los suyos con exports.rp_events:registerEvent(def)
    (ver docs/EVENTOS_DINAMICOS.md).

    Campos de cada evento:
        id, name, category, kind ("road" = calzada | "walk" = acera), weight, cooldown (s),
        duration {min, max} (s), severity (1-3, coste del presupuesto), elements (maximo
        de elementos que crea), hours {desde, hasta} (hora de juego, admite cruce de
        medianoche), rain = "no" | "only" | nil, mult(world) -> multiplicador del peso,
        alert = texto para los jugadores cercanos.
]]

local CIVIL_SKINS = { 7, 14, 15, 17, 20, 21, 22, 23, 24, 26, 29, 32, 34, 35, 37, 43, 44, 46, 47, 48, 57, 58, 59, 60 }
local CARS = { 400, 401, 405, 410, 418, 421, 426, 436, 445, 458, 466, 467, 474, 479, 491, 492, 496,
    507, 516, 517, 518, 526, 527, 529, 540, 542, 546, 547, 549, 550, 551, 554, 566, 585, 600 }

local function pick(list) return list[math.random(#list)] end
local function civil() return pick(CIVIL_SKINS) end

CATALOG = {}

----------------------------------------------------------------
-- Accidente de transito: dos autos chocados, humo, conductores discutiendo;
-- a los 45 s llega una patrulla y, si hay herido, una ambulancia.
----------------------------------------------------------------
CATALOG[#CATALOG + 1] = {
    id = "accident", name = "Accidente de transito", category = "traffic", kind = "road",
    weight = 10, cooldown = 360, duration = { 260, 420 }, severity = 2, elements = 11,
    mult = function(w) return (w.raining and 2.2 or 1) * (w.night and 1.4 or 1) end,
    alert = "Se oye un choque cerca: hay un accidente de transito.",
    build = function(H)
        local a = H.veh(pick(CARS), 0, 0, math.random(-10, 10), { health = math.random(420, 650) })
        local side = math.random() < 0.5 and 1 or -1
        local b = H.veh(pick(CARS), 5.4, -0.6, side * math.random(35, 75),
            { health = math.random(380, 600), smoke = true, hood = true })
        if a then H.panels(a) end
        if b then H.panels(b) end

        local d1 = H.ped(civil(), 1.5, 3.4)
        local d2 = H.ped(civil(), 4.2, 3.6)
        H.faceEachOther(d1, d2)
        H.anim(d1, "RIOT", "RIOT_ANGRY")
        H.anim(d2, "GANGS", "prtial_gngtlkD")

        local injured = math.random() < 0.55
        local patient
        if injured then
            patient = H.ped(civil(), 2.6, 6.0)
            H.anim(patient, "CRACK", "crckdeth2")
        end

        -- t = 45 s: llega la patrulla, se estaciona detras con la sirena puesta
        H.stage(45, function()
            H.veh(596, -11, 1.2, 14, { sirens = true })
            local c1 = H.ped(280, -8.6, 3.4)
            local c2 = H.ped(280, -6.4, 4.2)
            H.faceTo(c1, 2, 3.4) H.faceTo(c2, 3, 4)
            H.anim(c1, "COP_AMBIENT", "Coplook_loop")
            H.anim(c2, "COP_AMBIENT", "Coplook_loop")
            H.say("Llegó una patrulla al lugar del accidente.")
        end)
        if injured then
            -- t = 80 s: ambulancia; los paramedicos atienden al herido y a los 170 s se levanta
            H.stage(80, function()
                H.veh(416, -19, 0.8, -6, { sirens = true })
                local m1 = H.ped(274, 1.5, 5.2)
                local m2 = H.ped(275, 3.6, 5.4)
                H.faceTo(m1, 2.6, 6.0) H.faceTo(m2, 2.6, 6.0)
                H.anim(m1, "MEDIC", "CPR")
                H.anim(m2, "COP_AMBIENT", "Coplook_loop")
                H.say("Una ambulancia atiende a un herido en el accidente.")
            end)
            H.stage(170, function()
                if patient and isElement(patient) then setPedAnimation(patient) end
            end)
        end
    end,
}

----------------------------------------------------------------
-- Emergencia medica: alguien se desploma en la acera, testigos llaman
-- y llega una ambulancia.
----------------------------------------------------------------
CATALOG[#CATALOG + 1] = {
    id = "medical", name = "Emergencia medica", category = "health", kind = "road",
    weight = 6, cooldown = 480, duration = { 220, 360 }, severity = 1, elements = 7,
    alert = "Alguien se ha desplomado en la acera y la gente se agolpa.",
    build = function(H)
        local patient = H.ped(civil(), 2, 5.4)
        H.anim(patient, "CRACK", "crckdeth2")
        local w1 = H.ped(civil(), 1.2, 7.4)
        local w2 = H.ped(civil(), 3.4, 7.0)
        H.faceTo(w1, 2, 5.4) H.faceTo(w2, 2, 5.4)
        H.anim(w1, "ped", "phone_talk")
        H.anim(w2, "ped", "IDLE_chat")
        H.stage(55, function()
            H.veh(416, -9, 0.8, 4, { sirens = true })
            local m1 = H.ped(274, 0.6, 4.4)
            local m2 = H.ped(275, 3.4, 4.6)
            H.faceTo(m1, 2, 5.4) H.faceTo(m2, 2, 5.4)
            H.anim(m1, "MEDIC", "CPR")
            H.anim(m2, "COP_AMBIENT", "Coplook_loop")
            H.say("Una ambulancia llegó por la persona desplomada.")
        end)
        H.stage(140, function()
            if patient and isElement(patient) then setPedAnimation(patient) end
        end)
    end,
}

----------------------------------------------------------------
-- Control policial de carretera
----------------------------------------------------------------
CATALOG[#CATALOG + 1] = {
    id = "checkpoint", name = "Control policial", category = "police", kind = "road",
    weight = 5, cooldown = 600, duration = { 420, 720 }, severity = 1, elements = 10,
    hours = { 18, 5 },
    mult = function(w) return w.night and 1.6 or 1 end,
    alert = "Hay un control policial en la via.",
    build = function(H)
        H.veh(596, 0, 0.2, 22, { sirens = true })
        H.veh(596, 7, 1.0, -12, { sirens = true })
        for i = 0, 4 do H.obj(1238, -(8 + i * 1.3), 2.4 - i * 0.9, 0, 0) end
        local c1 = H.ped(280, 2.0, 3.2)
        local c2 = H.ped(281, 4.2, 3.0)
        H.faceTo(c1, 0, 0) H.faceTo(c2, 0, 0)
        H.anim(c1, "COP_AMBIENT", "Coplook_loop")
        H.anim(c2, "COP_AMBIENT", "Coplook_loop")
    end,
}

----------------------------------------------------------------
-- Obras en la via
----------------------------------------------------------------
CATALOG[#CATALOG + 1] = {
    id = "roadworks", name = "Obras viales", category = "works", kind = "road",
    weight = 5, cooldown = 900, duration = { 600, 1200 }, severity = 1, elements = 11,
    hours = { 7, 17 }, rain = "no",
    alert = "Hay obras en la calle, con operarios trabajando.",
    build = function(H)
        H.obj(1423, 0, 3.0, 0, 0)
        H.obj(1423, 3.4, 3.0, 0, 0)
        for i = 0, 2 do H.obj(1238, -(3 + i * 1.5), 2.6 - i * 0.4, 0, 0) end
        H.veh(478, -2, 6.2, 8, {})
        local w1 = H.ped(260, 1.6, 4.4)
        local w2 = H.ped(27, 4.6, 4.8)
        H.faceTo(w1, 1.6, 3.0) H.faceTo(w2, 4.6, 3.0)
        H.anim(w1, "BOMBER", "BOM_Plant_Loop")
        H.anim(w2, "COP_AMBIENT", "Coplook_loop")
    end,
}

----------------------------------------------------------------
-- Auto en llamas con bomberos
----------------------------------------------------------------
CATALOG[#CATALOG + 1] = {
    id = "car_fire", name = "Auto en llamas", category = "fire", kind = "road",
    weight = 3, cooldown = 900, duration = { 240, 400 }, severity = 2, elements = 7,
    alert = "Un auto se esta quemando en la calle: hay humo y llamas.",
    build = function(H)
        local v = H.veh(pick(CARS), 0, 0.6, 25, { health = 420, fire = true })
        if v then setVehicleColor(v, 0, 0, 0, 0) H.panels(v) end
        local b1 = H.ped(civil(), 6.5, 5.0)
        local b2 = H.ped(civil(), 8.0, 3.6)
        H.faceTo(b1, 0, 0.6) H.faceTo(b2, 0, 0.6)
        H.anim(b1, "ped", "phone_talk")
        H.anim(b2, "ped", "IDLE_chat")
        H.stage(40, function()
            H.veh(407, -13, 1.2, 8, { sirens = true })
            local f1 = H.ped(277, -7.4, 3.6)
            local f2 = H.ped(279, -6.0, 2.6)
            H.faceTo(f1, 0, 0.6) H.faceTo(f2, 0, 0.6)
            H.anim(f1, "COP_AMBIENT", "Coplook_loop")
            H.anim(f2, "COP_AMBIENT", "Coplook_loop")
            H.say("Los bomberos llegaron al auto en llamas.")
        end)
        H.stage(120, function()
            -- fuego apagado: solo queda humo
            if v and isElement(v) then setElementData(v, "rp:fx", "smoke") end
        end)
    end,
}

----------------------------------------------------------------
-- Mercadillo ambulante (de dia, en la acera)
----------------------------------------------------------------
CATALOG[#CATALOG + 1] = {
    id = "market", name = "Mercadillo ambulante", category = "social", kind = "walk",
    weight = 4, cooldown = 1200, duration = { 600, 1200 }, severity = 1, elements = 9,
    hours = { 9, 19 }, rain = "no",
    alert = "Hay puestos de venta ambulante en la acera: puedes comprarles (E).",
    build = function(H)
        -- Puestos en fila a lo largo de la acera; el vendedor queda del lado de las casas y los
        -- clientes del lado de la calle. H.side = lado de las casas (+1 derecha, -1 izquierda).
        local s = H.side
        local kinds = {}
        for i, st in ipairs(MARKET.STALLS) do kinds[i] = st end
        for i = #kinds, 2, -1 do local j = math.random(i) kinds[i], kinds[j] = kinds[j], kinds[i] end
        for n = -1, 1 do
            local f = n * MARKET.STALL_GAP
            -- el frente del puesto mira a la calle: rotacion = rumbo + 90 * lado (+ ajuste del modelo)
            H.obj(1340, f, 0, 90 * s + MARKET.CART_ROT, MARKET.CART_DZ)
            local vendor = H.ped(civil(), f, s * 1.5)
            H.faceTo(vendor, f, -s * 5)
            H.anim(vendor, "DEALER", "DEALER_IDLE")
            local stall = kinds[(n + 1) % #kinds + 1]
            H.shop(vendor, stall.name, stall.items)
        end
        for i = 1, 3 do
            local f = (i - 2) * MARKET.STALL_GAP + math.random(-6, 6) / 10
            local c = H.ped(civil(), f, -s * 1.9)
            H.faceTo(c, f, 0)
            H.anim(c, "ped", "IDLE_chat")
        end
    end,
}

----------------------------------------------------------------
-- Fiesta callejera (de noche)
----------------------------------------------------------------
CATALOG[#CATALOG + 1] = {
    id = "party", name = "Fiesta callejera", category = "social", kind = "walk",
    weight = 3, cooldown = 1200, duration = { 360, 700 }, severity = 2, elements = 6,
    hours = { 21, 5 }, rain = "no",
    alert = "Hay un grupo bailando y de fiesta en la calle.",
    build = function(H)
        local dances = { "dnce_M_a", "dnce_M_b", "dnce_M_c", "dnce_M_d", "dnce_M_e" }
        for i = 1, 6 do
            local a = (i / 6) * math.pi * 2
            local p = H.ped(civil(), math.cos(a) * 2.0, math.sin(a) * 2.0)
            H.faceTo(p, 0, 0)
            H.anim(p, "DANCING", pick(dances))
        end
    end,
}
