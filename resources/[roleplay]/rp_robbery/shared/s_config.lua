--[[
    rp_robbery / s_config.lua  (compartido cliente/servidor)

    Robo de tiendas 24/7 con interior propio. Flujo:
      1. Apuntar con un arma de fuego al cajero (o a un cliente) dentro de la
         tienda inicia el robo. Aparece la barra de MIEDO.
      2. El miedo baja solo; se rellena amenazando (H), apuntando al cajero o
         con un disparo de advertencia. Si llega a 0 el cajero saca la escopeta
         de debajo del mostrador y dispara, y un rehen aprovecha para huir.
      3. En la caja registradora (E) el personaje vacia la caja fardo a fardo
         con una cinematica de varias camaras. El dinero llega al instante.
      4. Al salir hay patrullas esperando: negociacion por turnos. Cada rehen
         vivo (cajero incluido) se puede canjear por segundos de ventaja, "sin
         trampas" (pinchos/controles) o "sin disparos a las llantas".
      5. Trato cerrado: al alejarse ESCAPE.RADIUS metros empieza la cuenta
         regresiva; en 0 sale la persecucion normal de rp_wanted.
      Estrellas: 3, 4 si murio un rehen, 5 si murio el cajero.

    IMPORTANTE: las coordenadas de dentro (cajero, caja, clientes) son una
    primera aproximacion y hay que verificarlas en juego. Un admin las corrige
    parado en el punto correcto con /robopunto <id> <punto> (ver RECURSOS.md).
]]

ROBBERY = {
    DIMENSION_BASE = 21000,      -- cada tienda usa la dimension 21000 + id
    ENTRANCE_PICKUP = 1239,      -- pickup "i"
    BLIP = 17,                   -- icono de 24/7 en el radar
    EXIT_RADIUS = 1.4,
    DOOR_RADIUS = 1.5,

    STORE_COOLDOWN = 30 * 60000, -- ms hasta que una tienda se puede volver a robar
    PLAYER_COOLDOWN = 10 * 60000,-- ms entre robos del mismo jugador
    PEDS_RESPAWN = 60000,        -- ms tras terminar un robo hasta que vuelven cajero y clientes
    AIM_DISTANCE = 14,           -- m: apuntar mas lejos no cuenta
    FIREARM_MIN = 22, FIREARM_MAX = 38,

    -- Barra de miedo (0-100)
    FEAR = {
        START = 100,
        DECAY = 3.2,             -- por segundo sin apuntar al cajero (~30 s de lleno a 0)
        DECAY_AIMING = 1.1,      -- por segundo mientras le apuntas
        INTIMIDATE = 30,         -- H: amenazar
        INTIMIDATE_COOLDOWN = 2500,
        WARNING_SHOT = 45,       -- disparo de advertencia (sin pegarle a nadie)
        WARNING_COOLDOWN = 2000,
        LOW = 30,                -- por debajo: aviso y la barra late
    },

    -- Caja registradora
    LOOT = {
        RADIUS = 1.6,            -- m de la caja para pulsar E
        BUNDLES = 8,             -- fardos
        BUNDLE_MS = 1100,        -- ms por fardo (la cinematica dura BUNDLES * BUNDLE_MS)
        BUNDLE_MIN = 150, BUNDLE_MAX = 420,
    },

    -- Patrullas que esperan afuera tras vaciar la caja
    POLICE = {
        CARS = 3,
        DISTANCE = 13,           -- m desde la puerta hasta la linea de patrullas
        SPACING = 6.5,           -- m entre patrullas
        COPS_PER_CAR = 2,
        WEAPON = 22,
        NEGOTIATOR_SKIN = 280,
        CITY = {
            ["Los Santos"]   = { model = 596, skin = 280 },
            ["San Fierro"]   = { model = 597, skin = 281 },
            ["Las Venturas"] = { model = 598, skin = 282 },
            rural            = { model = 599, skin = 283 },
        },
        INSIDE_PATIENCE = 120000,-- ms quedandose dentro tras el botin: la policia deja de negociar
        LEAVE_AFTER = 20000,     -- ms tras empezar la persecucion hasta que se borran las patrullas del cerco
    },

    -- Huida
    ESCAPE = {
        RADIUS = 60,             -- m desde la puerta para que empiece la cuenta regresiva
        MAX_WAIT = 120000,       -- ms: si no se aleja, la cuenta empieza igual
        BASE_SECONDS = 5,        -- ventaja sin canjear rehenes
        PER_HOSTAGE = 10,        -- segundos por rehen canjeado
        BLUFF_SECONDS = 8,
        MAX_SECONDS = 60,
        ABORT_STARS = 2,         -- salir sin vaciar la caja
    },

    -- Estrellas (forzadas: ignoran el tope por antiguedad de rp_wanted)
    STARS = { BASE = 3, HOSTAGE_KILLED = 4, CLERK_KILLED = 5 },

    -- Rendirse en la negociacion
    SURRENDER = { JAIL_SECONDS = 240, BAIL = 1500 },

    NEGOTIATION = {
        MAX_ROUNDS = 6,
        PATIENCE = 3,            -- faroles fallidos que aguanta el negociador
        BLUFF_CHANCE = 0.4,
        NEGOTIATOR = "Sgto. Ramirez",
    },

    CLERK_WEAPON = 25,           -- escopeta bajo el mostrador
    CUSTOMER_SKINS = { 7, 9, 10, 11, 12, 13, 14, 15, 17, 19, 20, 21, 22, 23, 24, 25, 26, 29, 31, 32, 34, 35, 36,
        37, 38, 39, 40, 41, 43, 44, 46, 47, 48, 54, 55, 56, 57, 58, 59, 60, 69, 72, 76, 88, 89, 90, 91, 93 },
    CLERK_SKINS = { 211, 217, 179, 205 },
    MAX_CUSTOMERS = 3,
}

--[[
    Interiores 24/7 de GTA SA. entry = donde apareces al entrar (junto a la
    puerta de dentro). clerk/register/customers: primera aproximacion; se
    corrigen por tienda con /robopunto (quedan guardados en robbery_stores.points).
    rot = grados (0 = norte, como getElementRotation).
]]
ROBBERY_TYPES = {
    ["247a"] = { name = "24/7 (grande)", interior = 17, multiplier = 1.2,
        entry = { x = -25.88, y = -185.87, z = 1003.55, rot = 0 },
        clerk = { x = -23.47, y = -181.35, z = 1003.55, rot = 180 },
        register = { x = -23.47, y = -182.40, z = 1003.55 },
        customers = { { x = -29.5, y = -180.0, z = 1003.55, rot = 270 }, { x = -27.0, y = -178.0, z = 1003.55, rot = 90 },
            { x = -21.0, y = -177.5, z = 1003.55, rot = 0 } } },
    ["247b"] = { name = "24/7 (mediano)", interior = 10, multiplier = 1.0,
        entry = { x = 6.09, y = -29.27, z = 1003.55, rot = 0 },
        clerk = { x = 2.05, y = -30.70, z = 1003.55, rot = 270 },
        register = { x = 3.10, y = -30.70, z = 1003.55 },
        customers = { { x = 2.5, y = -26.0, z = 1003.55, rot = 180 }, { x = 5.5, y = -23.5, z = 1003.55, rot = 90 },
            { x = -1.5, y = -23.0, z = 1003.55, rot = 0 } } },
    ["247c"] = { name = "24/7 (pasillos)", interior = 18, multiplier = 1.1,
        entry = { x = -30.95, y = -89.61, z = 1003.55, rot = 0 },
        clerk = { x = -28.15, y = -91.64, z = 1003.55, rot = 0 },
        register = { x = -28.15, y = -90.55, z = 1003.55 },
        customers = { { x = -33.5, y = -86.0, z = 1003.55, rot = 90 }, { x = -25.0, y = -84.0, z = 1003.55, rot = 270 },
            { x = -30.0, y = -81.5, z = 1003.55, rot = 180 } } },
    ["247d"] = { name = "24/7 (largo)", interior = 16, multiplier = 1.0,
        entry = { x = -25.13, y = -139.07, z = 1003.55, rot = 0 },
        clerk = { x = -22.60, y = -138.60, z = 1003.55, rot = 90 },
        register = { x = -23.65, y = -138.60, z = 1003.55 },
        customers = { { x = -27.5, y = -133.0, z = 1003.55, rot = 0 }, { x = -24.0, y = -130.0, z = 1003.55, rot = 180 },
            { x = -29.0, y = -127.0, z = 1003.55, rot = 270 } } },
    ["247e"] = { name = "24/7 (pequeno)", interior = 4, multiplier = 0.9,
        entry = { x = -27.31, y = -29.28, z = 1003.56, rot = 0 },
        clerk = { x = -28.00, y = -31.88, z = 1003.56, rot = 0 },
        register = { x = -28.00, y = -30.80, z = 1003.56 },
        customers = { { x = -31.0, y = -25.0, z = 1003.56, rot = 90 }, { x = -25.0, y = -23.0, z = 1003.56, rot = 270 } } },
    ["247f"] = { name = "24/7 (esquina)", interior = 6, multiplier = 1.0,
        entry = { x = -26.69, y = -55.71, z = 1003.55, rot = 0 },
        clerk = { x = -23.28, y = -57.32, z = 1003.55, rot = 0 },
        register = { x = -23.28, y = -56.25, z = 1003.55 },
        customers = { { x = -28.5, y = -50.5, z = 1003.55, rot = 90 }, { x = -22.0, y = -49.0, z = 1003.55, rot = 270 },
            { x = -26.0, y = -46.0, z = 1003.55, rot = 180 } } },
}

-- Tienda inicial cuando la tabla esta vacia: 24/7 de Idlewood (cerca de la estacion Unity).
-- x, y, z = la puerta por fuera; rot = hacia donde mira la puerta (la calle).
ROBBERY_SEED = { { name = "24/7 Idlewood", type = "247f", x = 1833.78, y = -1842.61, z = 13.58, rot = 270 } }

----------------------------------------------------------------
-- Logica pura (sin elementos): la usan el servidor, el cliente y rp_test
----------------------------------------------------------------

-- Estrellas al terminar: 3 base, 4 si murio un rehen, 5 si murio el cajero
function robberyStarsFor(clerkKilled, hostagesKilled)
    if clerkKilled then return ROBBERY.STARS.CLERK_KILLED end
    if (tonumber(hostagesKilled) or 0) > 0 then return ROBBERY.STARS.HOSTAGE_KILLED end
    return ROBBERY.STARS.BASE
end

-- Estado inicial de la negociacion. chips = rehenes vivos (cajero incluido)
function robberyNewDeal(chips)
    return {
        chips = math.max(0, math.floor(tonumber(chips) or 0)),
        released = 0,
        seconds = ROBBERY.ESCAPE.BASE_SECONDS,
        noTraps = false, noTires = false,
        patience = ROBBERY.NEGOTIATION.PATIENCE,
        round = 1, done = false, result = nil,
    }
end

-- Opciones del jugador en este turno: { id, label (burbuja), say (lo que dice) }
function robberyOptionsFor(deal)
    local list = {}
    if deal.done then return list end
    local hasChip = deal.chips > 0
    if hasChip and deal.seconds < ROBBERY.ESCAPE.MAX_SECONDS then
        list[#list + 1] = { id = "seconds", label = ("Soltar un rehen: +%d s de ventaja"):format(ROBBERY.ESCAPE.PER_HOSTAGE),
            say = "Suelto a uno ahora mismo... pero me dan tiempo para irme." }
    end
    if hasChip and not deal.noTraps then
        list[#list + 1] = { id = "traps", label = "Soltar un rehen: sin pinchos ni barricadas",
            say = "Les doy a otro si me prometen: nada de pinchos ni barricadas en mi camino." }
    end
    if hasChip and not deal.noTires then
        list[#list + 1] = { id = "tires", label = "Soltar un rehen: no disparar a las llantas",
            say = "Y a este lo suelto si nadie le dispara a mis llantas. ¡Son nuevas!" }
    end
    if deal.patience > 0 and (deal.seconds < ROBBERY.ESCAPE.MAX_SECONDS or not deal.noTraps or not deal.noTires) then
        list[#list + 1] = { id = "bluff", label = "Farolear: ¡tengo explosivos!",
            say = "¡Tengo C4 pegado al congelador de helados! ¡Denme lo que pido o adios al sabor fresa!" }
    end
    list[#list + 1] = { id = "deal", label = "Cerrar el trato", say = "Tenemos un trato. Me voy." }
    list[#list + 1] = { id = "surrender", label = "Rendirse", say = "...Esta bien. Me rindo. Salgo con las manos arriba." }
    return list
end

local function hasOption(deal, id)
    for _, o in ipairs(robberyOptionsFor(deal)) do
        if o.id == id then return true end
    end
    return false
end

--[[
    Aplica una opcion. roll = numero 0..1 para el farol (el servidor usa
    math.random; las pruebas pasan uno fijo). Devuelve ok y el "efecto" para
    la respuesta del negociador:
      release_seconds, release_traps, release_tires, bluff_ok_<term>,
      bluff_fail, bluff_broken, deal, surrender, invalid
]]
function robberyApplyOption(deal, id, roll)
    if deal.done or not hasOption(deal, id) then return false, "invalid" end
    local E = ROBBERY.ESCAPE
    local effect
    if id == "seconds" or id == "traps" or id == "tires" then
        deal.chips = deal.chips - 1
        deal.released = deal.released + 1
        if id == "seconds" then deal.seconds = math.min(E.MAX_SECONDS, deal.seconds + E.PER_HOSTAGE)
        elseif id == "traps" then deal.noTraps = true
        else deal.noTires = true end
        effect = "release_" .. id
    elseif id == "bluff" then
        roll = tonumber(roll) or math.random()
        if roll < ROBBERY.NEGOTIATION.BLUFF_CHANCE then
            -- se lleva lo que le falte, en este orden
            if not deal.noTraps then deal.noTraps = true effect = "bluff_ok_traps"
            elseif not deal.noTires then deal.noTires = true effect = "bluff_ok_tires"
            else deal.seconds = math.min(E.MAX_SECONDS, deal.seconds + E.BLUFF_SECONDS) effect = "bluff_ok_seconds" end
        else
            deal.patience = deal.patience - 1
            deal.seconds = math.max(0, deal.seconds - 3)
            effect = deal.patience <= 0 and "bluff_broken" or "bluff_fail"
            if deal.patience <= 0 then
                -- se acabo la paciencia: sin condiciones ni ventaja
                deal.noTraps, deal.noTires, deal.seconds = false, false, 0
                deal.done, deal.result = true, "broken"
            end
        end
    elseif id == "deal" then
        deal.done, deal.result, effect = true, "deal", "deal"
    elseif id == "surrender" then
        deal.done, deal.result, effect = true, "surrender", "surrender"
    end
    if not deal.done then
        deal.round = deal.round + 1
        if deal.round > ROBBERY.NEGOTIATION.MAX_ROUNDS then
            deal.done, deal.result = true, "deal"
            effect = effect .. "+timeout"
        end
    end
    return true, effect
end

-- Frases del negociador. {name} = nombre del jugador. effect -> lista (se elige una)
ROBBERY_LINES = {
    intro = {
        "¡Atencion, {name}! ¡Habla el Sargento Ramirez! Tienes la tienda rodeada... digo, ¡ESTAS rodeado!",
        "¡{name}! ¡Sabemos que estas ahi dentro! ¡Las camaras te grabaron robando... y comprando chicle!",
    },
    intro_nochips = {
        "¡{name}! Ya no queda nadie ahi dentro con quien negociar... ¿Que vas a ofrecernos, cupones de descuento?",
    },
    ask = {
        "Bien. ¿Que mas quieres?",
        "Te escucho. Y te advierto que tengo el cafe frio, asi que no tengo paciencia.",
        "Habla rapido, que el estacionamiento es de 15 minutos.",
    },
    release_seconds = {
        "Hmm... Un rehen por unos segundos de ventaja. ¡Hecho! Cuando te alejes empezamos a contar.",
        "¡Trato! Mis hombres esperaran un poco mas. Cronometro en mano.",
    },
    release_traps = {
        "Ni pinchos ni barricadas. Palabra de sargento. ...Juro que no tengo pinchos en el maletero.",
    },
    release_tires = {
        "¡Muchachos, nadie le dispara a las llantas! ...Si, Gomez, tampoco a la de repuesto.",
    },
    bluff_ok_traps = {
        "¡¿C-C4?! ¡Esta bien, esta bien! ¡Nada de pinchos ni barricadas! ¡Que nadie toque los helados!",
    },
    bluff_ok_tires = {
        "¡¿Explosivos?! ¡Ok! ¡Nadie dispara a las llantas! ¡Gomez, baja esa arma!",
    },
    bluff_ok_seconds = {
        "¡¿Bombas?! ¡Bueno, bueno! ¡Te damos mas tiempo, pero cuidado con el helado!",
    },
    bluff_fail = {
        "¿C4? ¡Eso es un control remoto de la tele! ¡Lo veo desde aqui! Te quito unos segundos por gracioso.",
        "Jajaja... ¿Explosivos? ¡Si apenas te alcanzo para el pasamontanas! Menos ventaja para ti.",
    },
    bluff_broken = {
        "¡SE ACABO! ¡Ni un farol mas! ¡A TODAS LAS UNIDADES: SIN TRATO!",
    },
    deal = {
        "Trato hecho. Sal despacio... y nada de tonterias. ¡Hablo en serio, {name}!",
        "Muy bien. Puedes irte... por ahora. Te vamos a estar esperando.",
    },
    surrender = {
        "¡Por fin alguien razonable! Manos arriba, {name}. Hoy duermes en la comisaria.",
    },
    timeout = {
        "¡Basta de charla! Tienes lo que tienes. ¡Largate antes de que me arrepienta!",
    },
}

-- Exclamaciones gigantes al estilo de tribunal (arte propio, solo texto)
ROBBERY_BURSTS = {
    intro = "¡ALTO AHI!",
    bluff_fail = "¡MENTIRA!",
    bluff_broken = "¡SIN TRATO!",
    bluff_ok_traps = "¡¿QUE?!",
    bluff_ok_tires = "¡¿QUE?!",
    bluff_ok_seconds = "¡¿QUE?!",
    deal = "¡TRATO!",
    surrender = "¡ATRAPADO!",
}

function robberyLine(effect, name)
    local base = tostring(effect or ""):gsub("%+timeout$", "")
    local list = ROBBERY_LINES[base] or ROBBERY_LINES.ask
    local text = list[math.random(#list)]
    return (text:gsub("{name}", tostring(name or "")))
end
