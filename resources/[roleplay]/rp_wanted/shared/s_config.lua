--[[
    rp_wanted / s_config.lua  (compartido cliente/servidor)

    Nivel de busqueda al estilo de GTA San Andreas. Los valores salen de la
    reconstruccion del codigo del juego (CWanted, proyecto gta-reversed):

      - Cada delito suma "puntos de caos". Las estrellas dependen del total:
        1 = 50, 2 = 180, 3 = 550, 4 = 1200, 5 = 2400, 6 = 4600 (tope 9200).
      - El mismo delito contra la misma victima solo cuenta una vez cada
        10 s (la cola de delitos de GTA). Se aplica medio segundo despues.
      - Si a la victima "a la policia no le importa" (pandilleros) el delito
        vale un tercio.
      - Cada segundo sin policia a menos de 18 m baja 1 punto (2 fuera de la
        ciudad o en un interior). Con policias encima no baja nunca.
      - Al morir o ser arrestado se borra. Si cometes otro delito en los 20 s
        siguientes a un arresto, vuelves al nivel que tenias ("libertad
        condicional").
]]

WANTED = {
    -- Puntos de caos minimos para cada estrella (indice = estrellas)
    THRESHOLDS = { 50, 180, 550, 1200, 2400, 4600 },
    MAX_CHAOS = 9200,
    MAX_LEVEL = 6,
    -- Caos con el que queda un nivel puesto a mano (/busqueda), como SetWantedLevel de GTA
    SET_LEVEL_CHAOS = { 70, 200, 570, 1220, 2420, 4620 },

    QUEUE_TIME = 10000,         -- ms: el mismo delito contra la misma victima no se repite
    REPORT_DELAY = 500,         -- ms hasta que el delito se aplica
    PAROLE_TIME = 20000,        -- ms de libertad condicional tras un arresto
    DONT_CARE_DIVISOR = 3,      -- victimas que "no le importan" a la policia

    DECAY_RADIUS = 18,          -- m: policia a esta distancia impide que baje el caos
    DECAY_CITY = 1,             -- puntos por segundo en la ciudad
    DECAY_ELUSIVE = 2,          -- fuera de la ciudad o en un interior
    DECAY_GRACE = 30000,
    EVADE_TIME = 10000,         -- ms sin que ningun policia te vea antes de que empiece a bajar
    CITY_EXIT_COOLDOWN = 60000, -- salir de la ciudad con 2+ estrellas quita una (como mucho 1 vez por minuto)        -- ms sin decaimiento despues de un delito o de subir de nivel

    -- Mas facil que GTA (pedido del servidor): todos los puntos se multiplican
    CRIME_SCALE = 2,
    -- Testigo: un policia (IA, del trafico o jugador) a esta distancia que ve el
    -- delito da estrella inmediata y el delito vale el doble
    WITNESS_RADIUS = 45,
    WITNESS_MULTIPLIER = 2,

    -- La policia (faccion reservada en rp_factions / rp_database) de servicio (con
    -- uniforme o en un vehiculo policial) no acumula busqueda; de civil, si
    POLICE_FACTION_ID = 1,
    -- Delitos contra otros jugadores (golpes, disparos, atropellos) tambien suman
    PLAYER_CRIMES = true,

    -- Al reconectar o cambiar de personaje la busqueda se conserva este tiempo
    REMEMBER_MINUTES = 30,

    -- Arresto ("Busted")
    -- Arresto ("Busted"): te sacan del auto o te reducen en el piso -> carcel
    BUST_TAKE_WEAPONS = true,
    BUST_RELEASE = { x = 1552.6, y = -1675.6, z = 16.2, rot = 90 },     -- puerta de la comisaria de Pershing Square (LSPD)
    BUST_FREEZE = 5000,         -- ms entre el arresto y aparecer en la celda

    -- Carcel: tiempo por estrella o fianza para salir antes (/fianza, en efectivo)
    JAIL_SECONDS_PER_STAR = 90,
    JAIL_BAIL_PER_STAR = 750,
    JAIL_CELL = { x = 263.9, y = 77.5, z = 1001.04, rot = 270, interior = 6 },   -- celdas de la comisaria de LS
    JAIL_MAX_DISTANCE = 7,      -- m: mas lejos de la celda te devuelven

    -- Pay 'n' Spray: pintura y reparacion borran la busqueda si ningun policia te ve entrar
    SPRAY_PRICE = 100,
    SPRAY_COP_RADIUS = 45,
    SPRAYS = {
        { name = "Pay 'n' Spray Idlewood",      x = 2063.2, y = -1831.3, z = 13.55 },
        { name = "Pay 'n' Spray Temple",        x = 1024.9, y = -1024.0, z = 32.10 },
        { name = "Pay 'n' Spray Santa Maria",   x = 487.6,  y = -1741.3, z = 11.10 },
        { name = "Pay 'n' Spray Dillimore",     x = 720.0,  y = -455.9,  z = 16.33 },
    },
}

--[[
    Delitos: puntos (multiplicador de CWanted::ReportCrimeNow) y texto.
    Como se detectan (ver client/c_crimes.lua y server/s_wanted.lua):
      ped_melee / cop_melee      golpe o arma blanca a un peaton / policia
      ped_stab / cop_stab        cuchillo
      ped_shoot / cop_shoot      arma de fuego o explosivo contra un peaton / policia
      ped_runover / cop_runover  atropellar (o embestir) a un peaton / policia
      cop_car                    chocar o danar un auto de la policia
      car_hit                    chocar un auto
      car_damage                 disparar a un auto
      car_steal                  robar un auto ocupado (sacar al conductor)
      car_destroy                hacer explotar un auto
      heli_destroy               derribar un helicoptero
      explosion                  provocar una explosion
      speeding                   exceso de velocidad delante de la policia
      aim_gun                    apuntar con un arma a alguien
]]
-- instant = N: el delito deja como minimo N estrellas al momento (aunque no haya testigos)
WANTED_CRIMES = {
    ped_melee    = { points = 5,   label = "Agresion" },
    cop_melee    = { points = 45,  label = "Agresion a un policia", instant = 1 },
    ped_stab     = { points = 35,  label = "Apunalar a un civil", instant = 1 },
    cop_stab     = { points = 100, label = "Apunalar a un policia", instant = 2 },
    ped_shoot    = { points = 30,  label = "Disparar a un civil", instant = 1 },
    cop_shoot    = { points = 80,  label = "Disparar a un policia", instant = 2 },
    ped_runover  = { points = 18,  label = "Atropello" },
    cop_runover  = { points = 80,  label = "Atropellar a un policia", instant = 2 },
    cop_car      = { points = 80,  label = "Embestir una patrulla", instant = 1 },
    car_hit      = { points = 2,   label = "Choque" },
    car_damage   = { points = 5,   label = "Danos a un vehiculo" },
    car_steal    = { points = 15,  label = "Robo de vehiculo" },
    car_destroy  = { points = 70,  label = "Destruccion de un vehiculo", instant = 1 },
    heli_destroy = { points = 400, label = "Derribar un helicoptero", instant = 1 },
    explosion    = { points = 25,  label = "Explosion" },
    speeding     = { points = 5,   label = "Exceso de velocidad" },
    aim_gun      = { points = 2,   label = "Amenaza con arma" },
}

-- Pandilleros: a la policia "no le importan" (PoliceDontCareAboutCrimesAgainstPedType)
WANTED_DONT_CARE_SKINS = {}
for _, id in ipairs({ 102, 103, 104, 105, 106, 107, 108, 109, 110, 114, 115, 116, 173, 174, 175, 195 }) do
    WANTED_DONT_CARE_SKINS[id] = true
end

--[[
    Unidades por estrellas (CWanted::UpdateWantedLevel y NumOfHelisRequired):
      cars       patrullas que persiguen a la vez
      heli       helicopteros
      roadblock  % de probabilidad de un control de carretera en cada despacho
      fleet      que patrulla sale (se elige en orden ciclico): police (la de la
                 ciudad), swat, fbi, army, tank
      shoot      los policias disparan (a 1 estrella solo intentan arrestarte)
      ram        las patrullas te embisten
]]
-- Mas duro que GTA (pedido del servidor): mas patrullas, embestidas desde 2
-- estrellas, controles y pinchos (spikes = % por despacho) por delante.
-- chasers: cuantas patrullas persiguen de cerca (GTA: 2 de 2 a 4 estrellas, 3 en 5-6);
-- las demas se adelantan por tu ruta para cortarte el paso.
WANTED_LEVELS = {
    [1] = { cars = 2, chasers = 1, heli = 0, roadblock = 0,  spikes = 0,  fleet = { "police" },                 shoot = false, ram = false },
    [2] = { cars = 3, chasers = 2, heli = 0, roadblock = 20, spikes = 25, fleet = { "police" },                 shoot = true,  ram = true },
    [3] = { cars = 4, chasers = 2, heli = 1, roadblock = 35, spikes = 40, fleet = { "police" },                 shoot = true,  ram = true },
    [4] = { cars = 4, chasers = 2, heli = 1, roadblock = 45, spikes = 45, fleet = { "swat", "police" },         shoot = true,  ram = true },
    [5] = { cars = 5, chasers = 3, heli = 2, roadblock = 55, spikes = 50, fleet = { "fbi", "police", "fbi" },   shoot = true,  ram = true },
    [6] = { cars = 5, chasers = 3, heli = 2, roadblock = 60, spikes = 50, fleet = { "tank", "army", "fbi" },    shoot = true,  ram = true },
}

-- Arma de los acompanantes para disparar desde la ventanilla (MP5)
WANTED_DRIVEBY_WEAPON = 29

-- Probabilidad de reventarte un neumatico: por bala de policia que pega en tu
-- vehiculo, y cada 1.5 s mientras te disparan desde una patrulla a menos de 30 m
WANTED_TIRE_HIT_CHANCE = 0.2
WANTED_TIRE_SHOT_CHANCE = 0.15

-- Multiplicadores del handling de las patrullas de la persecucion
WANTED_POLICE_HANDLING = { maxVelocity = 1.2, engineAcceleration = 1.5, tractionMultiplier = 1.15, brakeDeceleration = 1.2 }

-- Pinchos (stinger). MODEL 2899 es la tira de pinchos del juego.
WANTED_SPIKES = {
    MODEL = 2899, PIECES = 2, PIECE_LENGTH = 4.6, Z_OFFSET = 0.1, ROT_OFFSET = 90,
    AHEAD_MIN = 90, AHEAD_MAX = 170,  -- m por delante del jugador, en su ruta probable
    LIFE = 60000,
}

-- Vehiculos y agentes. police depende de la ciudad (getZoneName con citiesonly).
WANTED_FLEET = {
    police = {
        ["Los Santos"]   = { model = 596, skin = 280 },
        ["San Fierro"]   = { model = 597, skin = 281 },
        ["Las Venturas"] = { model = 598, skin = 282 },
        rural            = { model = 599, skin = 283 },
        crew = 2, weapon = 22, melee = 3,
    },
    swat = { model = 427, skin = 285, crew = 2, weapon = 29 },
    fbi  = { model = 490, skin = 286, crew = 2, weapon = 29 },
    army = { model = 433, skin = 287, crew = 2, weapon = 31 },
    tank = { model = 432, skin = 287, crew = 1, weapon = 31 },
    heli = { model = 497, skin = 280, crew = 1 },
}

-- A 1 estrella la patrulla lleva solo al conductor (GTA: 1 policia en persecucion)
WANTED_CREW_AT_ONE_STAR = 1

-- Skins de policia (uniforme): un miembro de la faccion con uno de estos esta de servicio
WANTED_POLICE_SKINS = {}
for id = 280, 288 do WANTED_POLICE_SKINS[id] = true end

-- Modelos que cuentan como vehiculo policial (presencia policial)
WANTED_POLICE_MODELS = { [596] = true, [597] = true, [598] = true, [599] = true, [523] = true,
    [427] = true, [490] = true, [497] = true, [432] = true, [433] = true }

WANTED_DISPATCH = {
    TICK = 1500,               -- ms entre despachos (aparece una unidad por despacho)
    FIRST_DELAY = 1200,        -- ms desde la primera estrella hasta la primera patrulla
    SPAWN_MIN = 45,            -- m desde el jugador donde aparece una patrulla (en la calle, fuera de la vista,
    SPAWN_MAX = 100,           --   preferentemente por delante si va en vehiculo)
    CATCHUP_DISTANCE = 100,    -- m: una patrulla mas lejos y fuera de la vista se adelanta por su ruta
    CATCHUP_TO = 60,           --   hasta quedar a esta distancia (como las de GTA, que aparecen cerca)
    HELI_SPAWN = 180,
    LOST_DISTANCE = 250,       -- m: una unidad mas lejos se retira y se manda otra
    LEAVE_TIME = 20000,        -- ms que tardan en irse al terminar la busqueda
    ROADBLOCK_AHEAD_MIN = 110,
    ROADBLOCK_AHEAD_MAX = 190,
    ROADBLOCK_LIFE = 90000,
    BODY_TIME = 30000,         -- ms hasta que desaparece un policia muerto
}

-- Nivel de estrellas para un total de caos
function wantedLevelFromChaos(chaos)
    local level = 0
    for i, t in ipairs(WANTED.THRESHOLDS) do
        if chaos >= t then level = i end
    end
    return level
end

-- Tipo de delito contra un ped segun el arma (CEventDamage::... de GTA SA)
-- weapon: id de arma de MTA. byVehicle: el atacante iba en un vehiculo (atropello).
function wantedCrimeForPedDamage(weapon, isCop, byVehicle)
    local prefix = isCop and "cop_" or "ped_"
    weapon = tonumber(weapon) or 0
    if byVehicle or weapon == 49 or weapon == 50 then return prefix .. "runover" end
    if weapon == 4 then return prefix .. "stab" end
    if weapon <= 15 then return prefix .. "melee" end            -- punos, armas blancas, regalos
    if weapon <= 40 or weapon == 41 or weapon == 51 then return prefix .. "shoot" end
    return nil
end
