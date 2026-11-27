--[[
    rp_achievements / shared/s_achievements.lua  (compartido)

    ESTADÍSTICAS: lo que los recursos informan con
        triggerEvent("rp:achievements:progress", jugador, "clave", cantidad)
      mode       "add" suma la cantidad; "max" guarda el valor más alto recibido (nivel, %, músculo)
      maxPerCall tope por aviso (protege de un fallo en otro recurso que mande 999999)

    LOGROS: cada uno lee una estadística y sube de medalla al llegar a cada umbral.
      tiers      umbrales: { bronce, plata, oro, platino } (pueden ser menos)
      medals     (opcional) medalla de cada umbral; por defecto 1, 2, 3, 4. Logro único: tiers = {1}, medals = {3}
      desc       texto con %s = umbral de la medalla siguiente
      unit       "money" ($1.234) o "%" para mostrar el umbral
      secret     no se ve en el panel hasta conseguir la primera medalla

    Para añadir un logro: una entrada en STATS (si la estadística es nueva) y otra en CATALOG,
    y el triggerEvent en el recurso que lo provoca. Ver docs/LOGROS.md.
]]

ACH.STATS = {
    -- Trabajo
    jobs_shifts      = { mode = "add", maxPerCall = 1 },
    jobs_earned      = { mode = "add", maxPerCall = 200000 },
    job_level        = { mode = "max", maxPerCall = 10 },
    market_sales     = { mode = "add", maxPerCall = 1 },
    pizza_delivered  = { mode = "add", maxPerCall = 1 },
    pizza_perfect    = { mode = "add", maxPerCall = 1 },
    -- Tesoros
    metal_finds      = { mode = "add", maxPerCall = 1 },
    metal_distinct   = { mode = "max", maxPerCall = 100 },
    metal_legendary  = { mode = "add", maxPerCall = 1 },
    -- Carretera
    driving_license  = { mode = "max", maxPerCall = 1 },
    driving_gold     = { mode = "max", maxPerCall = 20 },
    races_finished   = { mode = "add", maxPerCall = 1 },
    races_won        = { mode = "add", maxPerCall = 1 },
    train_trips      = { mode = "add", maxPerCall = 1 },
    bike_rentals     = { mode = "add", maxPerCall = 1 },
    rides_taken      = { mode = "add", maxPerCall = 1 },
    rides_driven     = { mode = "add", maxPerCall = 1 },
    -- Ley y calle
    wanted_escapes   = { mode = "add", maxPerCall = 1 },
    robberies        = { mode = "add", maxPerCall = 1 },
    jailed           = { mode = "add", maxPerCall = 1 },
    police_arrests   = { mode = "add", maxPerCall = 1 },
    police_fines     = { mode = "add", maxPerCall = 1 },
    drugs_bought     = { mode = "add", maxPerCall = 50 },
    -- Servicio
    fire_foci        = { mode = "add", maxPerCall = 1 },
    fire_rescues     = { mode = "add", maxPerCall = 1 },
    times_downed     = { mode = "add", maxPerCall = 1 },
    -- Físico
    gym_muscle       = { mode = "max", maxPerCall = 1000 },
    gym_stamina      = { mode = "max", maxPerCall = 1000 },
    gym_styles       = { mode = "max", maxPerCall = 3 },
    shooting_sessions = { mode = "add", maxPerCall = 1 },
    -- Vida
    char_level       = { mode = "max", maxPerCall = 100 },
    bank_balance     = { mode = "max", maxPerCall = 1000000000 },
    payday_count     = { mode = "add", maxPerCall = 1 },
    vehicles_bought  = { mode = "add", maxPerCall = 1 },
    property_bought  = { mode = "add", maxPerCall = 1 },
    clothes_bought   = { mode = "add", maxPerCall = 1 },
    meals_eaten      = { mode = "add", maxPerCall = 1 },
    -- Mundo y social
    map_explored     = { mode = "max", maxPerCall = 100 },
    places_found     = { mode = "add", maxPerCall = 10 },
    missions_done    = { mode = "add", maxPerCall = 1 },
    tinder_dates     = { mode = "add", maxPerCall = 1 },
    pool_wins        = { mode = "add", maxPerCall = 1 },
}

ACH.CATALOG = {
    -- Trabajo ---------------------------------------------------------------
    { key = "currante",      cat = "work", icon = "⏱️", name = "Currante",            stat = "jobs_shifts",     tiers = { 5, 25, 100, 400 },          desc = "Termina %s turnos de trabajo" },
    { key = "sueldo",        cat = "work", icon = "💵", name = "Sueldo honrado",      stat = "jobs_earned",     tiers = { 5000, 50000, 250000, 1000000 }, unit = "money", desc = "Gana %s trabajando" },
    { key = "oficio",        cat = "work", icon = "🎓", name = "Maestro del oficio",  stat = "job_level",       tiers = { 2, 3, 4, 5 },               desc = "Llega al nivel %s en un trabajo" },
    { key = "comerciante",   cat = "work", icon = "⚖️", name = "Comerciante",         stat = "market_sales",    tiers = { 10, 50, 200, 1000 },        desc = "Vende %s veces en los mercados" },
    { key = "pizzero",       cat = "work", icon = "🍕", name = "Pizzero",             stat = "pizza_delivered", tiers = { 10, 50, 200, 1000 },        desc = "Entrega %s pizzas en Well Stacked Pizza" },
    { key = "pizza_perfecta", cat = "work", icon = "👌", name = "Pizza perfecta",     stat = "pizza_perfect",   tiers = { 5, 25, 100, 300 },          desc = "Entrega %s pizzas con nota de 95 o más" },

    -- Tesoros ---------------------------------------------------------------
    { key = "buscatesoros",  cat = "treasure", icon = "📡", name = "Buscatesoros",     stat = "metal_finds",     tiers = { 10, 50, 250, 1000 },        desc = "Desentierra %s objetos con el detector" },
    { key = "coleccionista", cat = "treasure", icon = "🗃️", name = "Coleccionista",    stat = "metal_distinct",  tiers = { 3, 6, 9, 12 },              desc = "Encuentra %s objetos distintos de la colección" },
    { key = "leyenda",       cat = "treasure", icon = "👑", name = "Leyenda enterrada", stat = "metal_legendary", tiers = { 1 }, medals = { 3 },         desc = "Desentierra un objeto legendario" },

    -- Carretera -------------------------------------------------------------
    { key = "licencia",      cat = "road", icon = "🪪", name = "Licencia en mano",    stat = "driving_license", tiers = { 1 }, medals = { 2 },         desc = "Aprueba la autoescuela y saca tu licencia" },
    { key = "conductor",     cat = "road", icon = "🚦", name = "Conductor ejemplar",  stat = "driving_gold",    tiers = { 1, 3, 5, 8 },               desc = "Consigue oro en %s pruebas de la autoescuela" },
    { key = "piloto",        cat = "road", icon = "🏁", name = "Piloto",              stat = "races_finished",  tiers = { 3, 15, 50, 150 },           desc = "Termina %s carreras" },
    { key = "campeon",       cat = "road", icon = "🥇", name = "Campeón",             stat = "races_won",       tiers = { 1, 10, 30, 100 },           desc = "Gana %s carreras" },
    { key = "tren",          cat = "road", icon = "🚆", name = "Pasajero frecuente",  stat = "train_trips",     tiers = { 3, 15, 50, 150 },           desc = "Viaja %s veces en tren" },
    { key = "ciclista",      cat = "road", icon = "🚲", name = "Ciclista",            stat = "bike_rentals",    tiers = { 3, 15, 50, 150 },           desc = "Arrienda una bicicleta %s veces" },
    { key = "vroom_pasajero", cat = "road", icon = "📱", name = "Cliente de Vroom",   stat = "rides_taken",     tiers = { 3, 15, 50, 150 },           desc = "Haz %s viajes como pasajero en Vroom" },
    { key = "vroom_chofer",  cat = "road", icon = "🚕", name = "Chofer de Vroom",     stat = "rides_driven",    tiers = { 5, 25, 100, 400 },          desc = "Lleva a %s pasajeros con Vroom" },

    -- Ley y calle -----------------------------------------------------------
    { key = "fantasma",      cat = "street", icon = "👻", name = "Fantasma",          stat = "wanted_escapes",  tiers = { 1, 10, 30, 100 },           desc = "Pierde a la policía %s veces" },
    { key = "atracador",     cat = "street", icon = "💰", name = "Atracador",         stat = "robberies",       tiers = { 1, 5, 20, 50 },             desc = "Sal con el botín de %s robos a tiendas" },
    { key = "rejas",         cat = "street", icon = "⛓️", name = "Entre rejas",       stat = "jailed",          tiers = { 1 }, medals = { 1 }, secret = true, desc = "Acaba en la cárcel" },
    { key = "placa",         cat = "street", icon = "🚔", name = "Placa y deber",     stat = "police_arrests",  tiers = { 5, 25, 100, 300 },          desc = "Arresta a %s personas" },
    { key = "multas",        cat = "street", icon = "🧾", name = "Talonario",         stat = "police_fines",    tiers = { 5, 25, 100, 300 },          desc = "Pon %s multas" },
    { key = "quimica",       cat = "street", icon = "💊", name = "Química dudosa",    stat = "drugs_bought",    tiers = { 5, 25, 100, 500 }, secret = true, desc = "Compra %s dosis a los traficantes" },

    -- Servicio --------------------------------------------------------------
    { key = "apagafuegos",   cat = "service", icon = "🧯", name = "Apagafuegos",      stat = "fire_foci",       tiers = { 10, 50, 200, 750 },         desc = "Apaga %s focos de incendio" },
    { key = "heroe",         cat = "service", icon = "🦸", name = "Héroe",            stat = "fire_rescues",    tiers = { 1, 10, 40, 120 },           desc = "Rescata a %s civiles atrapados" },
    { key = "superviviente", cat = "service", icon = "🩹", name = "Superviviente",    stat = "times_downed",    tiers = { 5, 25, 50, 100 }, secret = true, desc = "Queda abatido %s veces y sigue adelante" },

    -- Físico ----------------------------------------------------------------
    { key = "musculoso",     cat = "body", icon = "🏋️", name = "Musculoso",          stat = "gym_muscle",      tiers = { 250, 500, 750, 1000 },      desc = "Llega a %s de músculo en el gimnasio" },
    { key = "atleta",        cat = "body", icon = "🏃", name = "Atleta",             stat = "gym_stamina",     tiers = { 250, 500, 750, 1000 },      desc = "Llega a %s de resistencia en el gimnasio" },
    { key = "artes_marciales", cat = "body", icon = "🥋", name = "Artista marcial",  stat = "gym_styles",      tiers = { 1, 2, 3 },                  desc = "Aprende %s estilos de combate con los entrenadores" },
    { key = "tirador",       cat = "body", icon = "🎯", name = "Tirador",            stat = "shooting_sessions", tiers = { 3, 15, 50, 150 },         desc = "Completa %s entrenamientos en el campo de tiro" },

    -- Vida ------------------------------------------------------------------
    { key = "veterano",      cat = "life", icon = "⭐", name = "Veterano",            stat = "char_level",      tiers = { 5, 10, 25, 50 },            desc = "Llega al nivel %s" },
    { key = "ahorrador",     cat = "life", icon = "🏦", name = "Ahorrador",           stat = "bank_balance",    tiers = { 10000, 100000, 1000000, 5000000 }, unit = "money", desc = "Ten %s en tu cuenta del banco" },
    { key = "nomina",        cat = "life", icon = "📅", name = "Nómina",              stat = "payday_count",    tiers = { 5, 25, 100, 500 },          desc = "Cobra %s paydays" },
    { key = "motorizado",    cat = "life", icon = "🚘", name = "Motorizado",          stat = "vehicles_bought", tiers = { 1, 3, 6, 10 },              desc = "Compra %s vehículos en el concesionario" },
    { key = "propietario",   cat = "life", icon = "🏡", name = "Propietario",         stat = "property_bought", tiers = { 1 }, medals = { 3 },         desc = "Compra tu primera propiedad" },
    { key = "moda",          cat = "life", icon = "👕", name = "A la moda",           stat = "clothes_bought",  tiers = { 5, 20, 60, 150 },           desc = "Compra %s prendas o accesorios" },
    { key = "buen_diente",   cat = "life", icon = "🍔", name = "Buen diente",         stat = "meals_eaten",     tiers = { 10, 50, 200, 750 },         desc = "Come %s veces en restaurantes" },

    -- Mundo y social --------------------------------------------------------
    { key = "explorador",    cat = "world", icon = "🧭", name = "Explorador",         stat = "map_explored",    tiers = { 10, 25, 50, 90 }, unit = "%", desc = "Descubre el %s del mapa" },
    { key = "trotamundos",   cat = "world", icon = "📍", name = "Trotamundos",        stat = "places_found",    tiers = { 5, 20, 50, 100 },           desc = "Descubre %s lugares en el mapa" },
    { key = "misionero",     cat = "world", icon = "🎬", name = "Misionero",          stat = "missions_done",   tiers = { 1, 10, 30, 100 },           desc = "Completa %s misiones" },
    { key = "rompecorazones", cat = "world", icon = "💘", name = "Rompecorazones",    stat = "tinder_dates",    tiers = { 1, 5, 15, 40 },             desc = "Consigue %s citas en Tinder" },
    { key = "taco_oro",      cat = "world", icon = "🎱", name = "Taco de oro",        stat = "pool_wins",       tiers = { 1, 10, 40, 120 },           desc = "Gana %s partidas de pool" },
}

-- Índices derivados (no tocar)
ACH.BY_KEY, ACH.BY_STAT = {}, {}
for i, a in ipairs(ACH.CATALOG) do
    a.order = i
    if not a.medals then             -- por defecto bronce, plata, oro, platino (tantas como umbrales)
        a.medals = {}
        for t = 1, #a.tiers do a.medals[t] = t end
    end
    ACH.BY_KEY[a.key] = a
    ACH.BY_STAT[a.stat] = ACH.BY_STAT[a.stat] or {}
    table.insert(ACH.BY_STAT[a.stat], a)
end

-- Medalla (1-4) del tier `tier` (1..#tiers) de un logro; nil si no tiene
function ACH.medalOf(a, tier)
    return a and tier and tier > 0 and a.medals[tier] or nil
end

-- Puntos acumulados de un logro con `tier` medallas conseguidas
function ACH.pointsOf(a, tier)
    local p = 0
    for i = 1, math.min(tier or 0, #a.tiers) do
        local m = ACH.MEDALS[a.medals[i]]
        p = p + (m and m.points or 0)
    end
    return p
end

-- Tier (0..#tiers) que corresponde a un valor de la estadística
function ACH.tierFor(a, value)
    local t = 0
    for i, need in ipairs(a.tiers) do
        if (value or 0) >= need then t = i else break end
    end
    return t
end

-- Umbral formateado para el texto
function ACH.formatGoal(a, n)
    if a.unit == "money" then return "$" .. ACH.fmt(n) end
    if a.unit == "%" then return ACH.fmt(n) .. " %" end
    return ACH.fmt(n)
end

-- Puntos máximos posibles (para el panel)
function ACH.maxPoints()
    local total = 0
    for _, a in ipairs(ACH.CATALOG) do total = total + ACH.pointsOf(a, #a.tiers) end
    return total
end
