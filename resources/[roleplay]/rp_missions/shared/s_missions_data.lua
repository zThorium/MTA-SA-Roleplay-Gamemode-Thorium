--[[
    rp_missions / shared / s_missions_data.lua

    Definicion de misiones. Cada una es una lista ordenada de etapas (stages); una etapa se
    completa cuando TODOS sus componentes estan hechos. Componentes disponibles en una etapa:

      cutscene = { shots = { {from={x,y,z}, to={x,y,z}, look={x,y,z}, lookTo={x,y,z}, dur=ms, fov=70} },
                   lines = { {who="sweet"|"me"|..., text="...", dur=ms?} },
                   place = {x,y,z,rot,spread}, anim = {block, name, loop} , letterbox = true }
      radio    = { {who=, text=} }                  -- llamada de contacto sin bloquear la accion
      goto     = {x,y,z,r, vehicle=true?}           -- todos los vivos deben llegar (r = radio)
      getin    = "clave"                            -- todos los vivos dentro del vehiculo con esa clave
      vehicles = { {key=, model=, x,y,z,rot, color={a,b}} }
      objects  = { {key=, model=, x,y,z} }          -- props (cajas); se borran al completar el punto con key
      enemies  = { {skins={...}, weapon=, ammo=, x,y,z, radius=, count=, per=, label=} }
      waves    = lista de grupos como enemies, uno tras otro (cada oleada aparece al limpiar la anterior)
      interact = { time=ms, text=, anim={block,name}, points = { {x,y,z, key=?} } }
      deliver  = { vehicle="clave", x,y,z,r, minHealth=?, ambush = { {at={x,y,z}, group={...}} } }
      wait     = ms
      text     = texto del objetivo (HUD) ; pos = {x,y,z} punto del blip por defecto
      snap     = {x,y,z,rot} punto seguro (reaparicion) a partir de esta etapa

    "who" de los dialogos: clave de MISSIONS.CONTACTS o "me" (el propio jugador).
]]

local function P(x, y, z) return { x, y, z } end

-- Planos estandar de una conversacion (docs/CINEMATICAS.md), RELATIVOS al actor para que siempre vean su cara:
-- general (coordenadas del mundo) -> medio con empuje lento -> reaccion del jugador -> contrapicado -> sobre el hombro
local function TalkShots(npc, wide)
    return {
        wide,
        { from = { npc = npc, fwd = 2.7, right = 0.8, dz = 0.25 }, to = { npc = npc, fwd = 2.1, right = 0.5, dz = 0.25 }, look = { npc = npc, dz = 0.0 }, dur = 4200, fov = 46, fovTo = 40, shake = 1 },
        { from = { me = true, fwd = 1.7, right = -0.55, dz = 0.2 }, look = { me = true, dz = 0.0 }, dur = 2200, fov = 40, shake = 1.3 },
        { from = { npc = npc, fwd = 1.9, right = -0.9, dz = -0.6 }, to = { npc = npc, fwd = 1.6, right = -0.6, dz = -0.5 }, look = { npc = npc, dz = 0.1 }, dur = 4500, fov = 50, roll = 5, rollTo = 3, shake = 0.8 },
        { from = { me = true, fwd = -0.9, right = 0.55, dz = 0.3 }, to = { me = true, fwd = -0.8, right = 0.45, dz = 0.3 }, look = { npc = npc, dz = 0.0 }, dur = 4000, fov = 48, shake = 1 },
    }
end

-- Plano general de una escena a partir del punto donde se coloca el grupo (coordenadas del mundo, aproximadas)
local function Wide(x, y, z, dur, fov)
    return { from = P(x + 9, y - 8, z + 3.2), to = P(x + 5, y - 6, z + 2.2), look = P(x, y + 1, z + 0.8), dur = dur or 3600, fov = fov or 60 }
end

MISSION_DEFS = {

    ----------------------------------------------------------------
    -- 1. Sweet: Territorio Grove (conduccion + tiroteo desde el auto)
    ----------------------------------------------------------------
    {
        key = "grove_turf",
        title = "Ojo por ojo",
        contact = "sweet",
        desc = "Los Ballas han pintado sobre nuestros muros. Sweet quiere que les devuelvas el mensaje: sube al Greenwood, ve a su barrio y limpia la esquina.",
        minP = 1, maxP = 4, recommended = 3,
        minLevel = 1, minRespect = 0,
        cash = 2400, respect = 60, xpBonus = 0,
        weather = 0, hour = 19,
        roles = {
            { id = "driver",  name = "Conductor", max = 1, weapons = { { 22, 80 } }, desc = "Maneja el Greenwood" },
            { id = "shooter", name = "Artillero", max = 2, weapons = { { 28, 300 }, { 22, 60 } }, desc = "Micro Uzi para el tiroteo" },
            { id = "gang",    name = "Pandillero", max = 4, weapons = { { 22, 90 }, { 4, 1 } }, desc = "Pistola y cuchillo" },
        },
        spawns = { { 2491.5, -1676.0, 13.4, 90 }, { 2491.5, -1678.2, 13.4, 90 }, { 2491.5, -1680.4, 13.4, 90 }, { 2491.5, -1682.6, 13.4, 90 } },
        snap = { 2495.0, -1678.0, 13.4, 180 },
        victory = { 2495.3, -1680.0, 13.4, 180, spread = 1.6 },
        victoryCam = { from = P(2500.5, -1670.0, 16.5), look = P(2495.3, -1680.0, 14.4) },
        stages = {
            {
                text = "Habla con Sweet",
                cutscene = {
                    letterbox = true,
                    -- Ejemplo del estandar (docs/CINEMATICAS.md): plano general -> media figura con seguimiento -> reaccion -> contrapicado
                    shots = TalkShots("sweet", { from = P(2506.0, -1694.0, 17.0), to = P(2502.0, -1690.0, 16.0), look = P(2495.0, -1685.0, 14.4), dur = 3200, fov = 62 }),
                    lines = {
                        { who = "sweet", text = "Oye, mira esos muros. Los Ballas pintaron la calle entera mientras dormiamos." },
                        { who = "me",    text = "Eso no se queda asi." },
                        { who = "sweet", text = "Exacto. Toma el Greenwood, llega a su esquina y dales una leccion. Sin pasarse.", overlap = 450 },
                        { who = "sweet", text = "Y cuidense, que no estan solos. Si caemos todos, la calle es suya.", gap = 500 },
                    },
                    place = { 2493.8, -1679.5, 13.4, 90, spread = 1.4 },
                    npcs = { { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 } } },
                },
            },
            {
                text = "Sube al Greenwood",
                pos = P(2487.5, -1674.5, 13.4),
                vehicles = { { key = "car", model = 492, x = 2487.5, y = -1674.5, z = 13.4, rot = 90, color = { 86, 86 } } },
                getin = "car",
                radio = { { who = "sweet", text = "Ese es. Maneja tu, ¡y que los demas se suban!" } },
                snap = { 2495.0, -1678.0, 13.4, 180 },
            },
            {
                text = "Conduce hasta el territorio de los Ballas",
                pos = P(2161.5, -1259.0, 23.9),
                goto = { 2161.5, -1259.0, 23.9, 18, vehicle = true },
                boardNpc = { "sweet", "car" },
                radio = {
                    { who = "sweet", text = "Es en Jefferson, junto al motel. Se ven por los colores morados." },
                    { who = "sweet", text = "Disparen desde las ventanillas. ¡Y no choquen mi coche!" },
                },
            },
            {
                text = "Elimina a los Ballas",
                pos = P(2161.5, -1259.0, 23.9),
                enemies = {
                    { skins = { 102, 103, 104 }, weapon = 22, ammo = 200, x = 2148.0, y = -1262.0, z = 23.9, radius = 16, count = 4, per = 2, label = "Ballas" },
                    { skins = { 102, 103, 104 }, weapon = 28, ammo = 300, x = 2172.0, y = -1252.0, z = 23.9, radius = 12, count = 2, per = 1, label = "Ballas" },
                },
                radio = { { who = "sweet", text = "¡Ahi estan! ¡Fuego!" } },
                snap = { 2150.0, -1240.0, 23.9, 0 },
            },
            {
                text = "Vuelve a Grove Street",
                pos = P(2495.0, -1668.0, 13.4),
                goto = { 2495.0, -1668.0, 13.4, 14, vehicle = false },
                radio = { { who = "sweet", text = "Bien hecho. Vengan a casa antes de que lleguen los refuerzos." } },
            },
            {
                text = "Habla con Sweet",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("sweet", { from = P(2501.0, -1662.0, 16.0), to = P(2498.0, -1666.0, 15.4), look = P(2495.3, -1672.0, 14.4), dur = 5600, fov = 58 }),
                    lines = {
                        { who = "sweet", text = "Eso fue limpio. La gente va a hablar de esto en la esquina toda la semana." },
                        { who = "me",    text = "Cuando quieras repetirlo, avisame." },
                        { who = "sweet", text = "Grove Street para siempre. Aqui tienes tu parte." },
                    },
                    place = { 2495.3, -1670.0, 13.4, 180, spread = 1.5 },
                    npcs = { { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 } } },
                },
            },
        },
    },

    ----------------------------------------------------------------
    -- 2. Ryder: Almacen del Tio Sam (tareas simultaneas: cargar + defender)
    ----------------------------------------------------------------
    {
        key = "uncle_sam",
        requires = { "grove_turf" },
        title = "El almacen del Tio Sam",
        contact = "ryder",
        desc = "Ryder tiene un soplo: un almacen del puerto guarda cajas de armas militares. Unos cargan el camion mientras los otros cubren las entradas contra la guardia.",
        minP = 2, maxP = 4, recommended = 4,
        minLevel = 3, minRespect = 40,
        cash = 4800, respect = 90, xpBonus = 150,
        weather = 1, hour = 2,
        roles = {
            { id = "loader", name = "Cargador", max = 2, weapons = { { 24, 70 } }, desc = "Se encarga de las cajas" },
            { id = "cover",  name = "Cobertura", max = 3, weapons = { { 31, 240 }, { 22, 60 } }, desc = "Rifle para cubrir" },
        },
        spawns = { { 2456.0, -1698.0, 13.5, 270 }, { 2456.0, -1700.5, 13.5, 270 }, { 2456.0, -1703.0, 13.5, 270 }, { 2456.0, -1705.5, 13.5, 270 } },
        snap = { 2458.0, -1700.0, 13.5, 270 },
        victory = { 2455.4, -1700.0, 13.5, 270, spread = 1.6 },
        victoryCam = { from = P(2465.0, -1692.0, 16.0), look = P(2455.4, -1700.0, 14.4) },
        stages = {
            {
                text = "Escucha el plan de Ryder",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("ryder", { from = P(2466.0, -1712.0, 17.0), to = P(2462.0, -1708.0, 16.0), look = P(2455.0, -1702.0, 14.4), dur = 4000, fov = 62 }),
                    lines = {
                        { who = "ryder", text = "Escuchen, esto es oro puro. Un almacén en el puerto, lleno de cajas del ejército." },
                        { who = "ryder", text = "Dos cargan el camión, el resto cubre las entradas. La guardia llega por oleadas." },
                        { who = "me",    text = "¿Cuánto tiempo tenemos?" },
                        { who = "ryder", text = "El que tarde, se queda. No se queden a conversar." },
                    },
                    place = { 2455.2, -1700.0, 13.5, 90, spread = 1.4 },
                    npcs = { { key = "ryder", contact = "ryder", skin = 271, rel = 2.6 } },
                },
            },
            {
                text = "Ve al puerto",
                pos = P(2768.0, -2417.5, 13.6),
                goto = { 2768.0, -2417.5, 13.6, 26 },
                snap = { 2760.0, -2420.0, 13.6, 90 },
                radio = { { who = "ryder", text = "Roba un coche si hace falta. Yo los espero al otro lado de la reja." } },
            },
            {
                text = "Carga las cajas y repele a la guardia",
                pos = P(2790.0, -2417.5, 13.6),
                objects = {
                    { key = "c1", model = 2912, x = 2784.0, y = -2411.0, z = 13.1 },
                    { key = "c2", model = 2912, x = 2790.0, y = -2424.0, z = 13.1 },
                    { key = "c3", model = 2912, x = 2797.0, y = -2411.0, z = 13.1 },
                    { key = "c4", model = 2912, x = 2802.0, y = -2424.0, z = 13.1 },
                },
                interact = {
                    time = 5000, text = "Cargando caja",
                    anim = { "BOMBER", "BOM_Plant_Loop" },
                    points = {
                        { 2784.0, -2411.0, 13.6, "c1" }, { 2790.0, -2424.0, 13.6, "c2" },
                        { 2797.0, -2411.0, 13.6, "c3" }, { 2802.0, -2424.0, 13.6, "c4" },
                    },
                },
                waves = {
                    { skins = { 287 }, weapon = 30, ammo = 300, x = 2770.0, y = -2400.0, z = 13.6, radius = 10, count = 3, per = 2, label = "Guardia Nacional" },
                    { skins = { 287 }, weapon = 31, ammo = 300, x = 2815.0, y = -2430.0, z = 13.6, radius = 10, count = 4, per = 2, label = "Guardia Nacional" },
                    { skins = { 287, 286 }, weapon = 31, ammo = 300, x = 2790.0, y = -2440.0, z = 13.6, radius = 8, count = 5, per = 2, label = "Refuerzos" },
                },
                radio = {
                    { who = "ryder", text = "¡Alarma! ¡La guardia viene por el norte!" },
                    { who = "ryder", text = "Mantengan a esos tipos lejos de las cajas. ¡Mantengan E para cargar!" },
                },
                snap = { 2770.0, -2418.0, 13.6, 90 },
            },
            {
                text = "Conduce el camion hasta la guarida",
                pos = P(2455.4, -1690.0, 13.5),
                vehicles = { { key = "truck", model = 414, x = 2795.0, y = -2418.0, z = 13.8, rot = 90, color = { 0, 0 } } },
                deliver = {
                    vehicle = "truck", x = 2455.0, y = -1690.0, z = 13.5, r = 14, minHealth = 250,
                    ambush = {
                        { at = P(2650.0, -2150.0, 13.5), group = { skins = { 287 }, weapon = 31, ammo = 250, x = 2655.0, y = -2145.0, z = 13.6, radius = 10, count = 3, per = 1 } },
                        { at = P(2500.0, -1850.0, 13.5), group = { skins = { 102, 103 }, weapon = 28, ammo = 250, x = 2505.0, y = -1845.0, z = 13.6, radius = 12, count = 3, per = 1 } },
                    },
                },
                radio = {
                    { who = "ryder", text = "Busca el camión, ¡ya! Si te lo revientan, perdimos todo." },
                },
            },
            {
                text = "Habla con Ryder",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("ryder", { from = P(2462.0, -1684.0, 16.0), to = P(2459.0, -1688.0, 15.6), look = P(2455.0, -1695.0, 14.6), dur = 6000, fov = 58 }),
                    lines = {
                        { who = "ryder", text = "¡Ja ja! Mira esas cajas. Con esto compramos medio barrio." },
                        { who = "me",    text = "Cuando quieras otro soplo, avísame." },
                        { who = "ryder", text = "Aquí tienes tu parte. Ni una palabra a Sweet." },
                    },
                    place = { 2455.4, -1693.0, 13.5, 0, spread = 1.5 },
                    npcs = { { key = "ryder", contact = "ryder", skin = 271, rel = 2.6 } },
                },
            },
        },
    },

    ----------------------------------------------------------------
    -- 3. Cesar: Cargamento de Cesar (hackeo + escolta + emboscadas)
    ----------------------------------------------------------------
    {
        key = "cesar_cargo",
        requires = { "uncle_sam" },
        title = "Cargamento de Cesar",
        contact = "cesar",
        desc = "Cesar necesita piezas de un taller del centro. Abre la reja, carga la furgoneta y escoltala por la ciudad: habra quien intente quitartela.",
        minP = 1, maxP = 4, recommended = 2,
        minLevel = 5, minRespect = 100,
        cash = 7200, respect = 120, xpBonus = 250,
        weather = 0, hour = 23,
        roles = {
            { id = "driver", name = "Conductor", max = 1, weapons = { { 22, 80 } }, desc = "Lleva la furgoneta" },
            { id = "hacker", name = "Tecnico", max = 1, weapons = { { 24, 60 } }, desc = "Abre la reja del taller" },
            { id = "escort", name = "Escolta", max = 3, weapons = { { 28, 300 }, { 25, 40 } }, desc = "Cubre al conductor" },
        },
        spawns = { { 2178.0, -1727.0, 13.5, 180 }, { 2180.5, -1727.0, 13.5, 180 }, { 2183.0, -1727.0, 13.5, 180 }, { 2185.5, -1727.0, 13.5, 180 } },
        snap = { 2180.0, -1730.0, 13.5, 180 },
        victory = { 2176.0, -1732.0, 13.5, 0, spread = 1.7 },
        victoryCam = { from = P(2185.0, -1722.0, 16.5), look = P(2176.0, -1732.0, 14.4) },
        stages = {
            {
                text = "Escucha a Cesar",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("cesar", { from = P(2186.0, -1738.0, 16.5), to = P(2182.0, -1736.0, 15.5), look = P(2176.0, -1731.0, 14.2), dur = 4200, fov = 60 }),
                    lines = {
                        { who = "cesar", text = "Necesito unas piezas de un taller del centro. La reja está cerrada y el dueño no quiere vender." },
                        { who = "cesar", text = "Abran el candado, carguen la furgoneta y llévenla al taller sin un rasguño." },
                        { who = "me",    text = "¿Y si alguien se mete?" },
                        { who = "cesar", text = "Entonces ya saben qué hacer. Cuídenme esa carga." },
                    },
                    place = { 2176.0, -1730.0, 13.5, 0, spread = 1.4 },
                    npcs = { { key = "cesar", contact = "cesar", skin = 292, rel = 2.6 } },
                },
            },
            {
                text = "Llega al taller",
                pos = P(1655.0, -1540.0, 13.5),
                goto = { 1655.0, -1540.0, 13.5, 20 },
                snap = { 1640.0, -1545.0, 13.5, 0 },
                radio = { { who = "cesar", text = "El taller está en el centro, cerca de la estación. Ve con cuidado." } },
            },
            {
                text = "Abre el candado de la reja",
                pos = P(1660.0, -1546.0, 13.5),
                interact = {
                    time = 7000, text = "Forzando candado",
                    anim = { "BOMBER", "BOM_Plant_Loop" },
                    points = { { 1660.0, -1546.0, 13.5, "lock" } },
                },
                waves = {
                    { skins = { 103, 104 }, weapon = 22, ammo = 200, x = 1672.0, y = -1535.0, z = 13.5, radius = 10, count = 2, per = 1, label = "Matones" },
                },
                radio = { { who = "cesar", text = "Mientras trabajan, ojo. Alguien avisó a los vecinos." } },
            },
            {
                text = "Sube a la furgoneta y escoltala a destino",
                pos = P(2176.0, -1740.0, 13.5),
                vehicles = { { key = "van", model = 498, x = 1666.0, y = -1552.0, z = 13.7, rot = 180, color = { 3, 3 } } },
                deliver = {
                    vehicle = "van", x = 2176.0, y = -1740.0, z = 13.5, r = 12, minHealth = 300,
                    ambush = {
                        { at = P(1720.0, -1640.0, 13.5), group = { skins = { 102, 103, 104 }, weapon = 28, ammo = 250, x = 1725.0, y = -1635.0, z = 13.6, radius = 12, count = 3, per = 2 } },
                        { at = P(1960.0, -1740.0, 13.5), group = { skins = { 107, 108 }, weapon = 30, ammo = 250, x = 1965.0, y = -1735.0, z = 13.6, radius = 12, count = 4, per = 2 } },
                        { at = P(2100.0, -1745.0, 13.5), group = { skins = { 107, 108, 109 }, weapon = 31, ammo = 250, x = 2105.0, y = -1740.0, z = 13.6, radius = 10, count = 3, per = 1 } },
                    },
                },
                radio = { { who = "cesar", text = "Ya van. Si le pasa algo a la furgoneta, esto se acaba." } },
            },
            {
                text = "Habla con Cesar",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("cesar", { from = P(2184.0, -1745.0, 16.5), to = P(2180.0, -1742.0, 15.6), look = P(2176.0, -1735.0, 14.4), dur = 6400, fov = 58 }),
                    lines = {
                        { who = "cesar", text = "Las piezas están intactas. Eres de los pocos en quienes puedo confiar." },
                        { who = "me",    text = "Un trabajo más." },
                        { who = "cesar", text = "Con esto ya eres de la familia. Esto es tuyo." },
                    },
                    place = { 2176.0, -1735.0, 13.5, 0, spread = 1.6 },
                    npcs = { { key = "cesar", contact = "cesar", skin = 292, rel = 2.6 } },
                },
            },
        },
    },

    ----------------------------------------------------------------
    -- HISTORIA "Sangre de Grove" (misiones 4-10). Cada una exige haber completado la anterior (requires).
    -- Hilo: Cesar y su emergencia -> los Ballas vuelven con rifles del ejercito -> alguien vendio el almacen -> Ryder.
    -- Coordenadas APROXIMADAS (inventadas): ajustar en juego con /mmover y /mskip.
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- 4. Cesar: la emergencia delicada (mision comica) -- NO se le paro el amigo y viene Kendl
    ----------------------------------------------------------------
    {
        key = "cesar_viagra",
        requires = { "cesar_cargo" },
        title = "Una emergencia delicada",
        contact = "cesar",
        desc = "Cesar está sudando, no quiere decir por qué y Kendl llega en minutos. Solo tú puedes ayudarlo: ve a la farmacia de Idlewood, consigue lo que necesita y vuelve antes de que sea tarde. Discreción absoluta.",
        minP = 1, maxP = 2, recommended = 1,
        minLevel = 5, minRespect = 200,
        cash = 3200, respect = 70, xpBonus = 100,
        weather = 0, hour = 17,
        roles = {
            { id = "mensajero", name = "Mensajero", max = 1, weapons = { { 22, 80 } }, desc = "Va por la 'medicina' sin hacer preguntas" },
            { id = "apoyo", name = "Apoyo discreto", max = 1, weapons = { { 22, 80 }, { 4, 1 } }, desc = "Cubre al mensajero y se calla la boca" },
        },
        spawns = { { 2178.0, -1727.0, 13.5, 180 }, { 2180.5, -1727.0, 13.5, 180 } },
        snap = { 2180.0, -1730.0, 13.5, 180 },
        victory = { 2176.0, -1732.0, 13.5, 0, spread = 1.7 },
        victoryCam = { from = P(2185.0, -1722.0, 16.5), look = P(2176.0, -1732.0, 14.4) },
        stages = {
            {
                text = "Escucha a Cesar (si se anima a hablar)",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("cesar", Wide(2176.0, -1730.0, 13.5, 3600, 60)),
                    lines = {
                        { who = "cesar", text = "Oye... tú. Ven acá. Necesito pedirte algo y, antes de que digas nada, te advierto: si se lo cuentas a alguien, lo niego todo." },
                        { who = "me",    text = "Cesar, estás sudando. ¿Qué pasó?" },
                        { who = "cesar", text = "Es un asunto personal. Muy personal. De esos que un hombre no le cuenta ni a su espejo." },
                        { who = "me",    text = "¿Te metiste en problemas con alguien?" },
                        { who = "cesar", text = "¡No, no! Es peor. Es que anoche... el amigo... ¿cómo te lo digo? El amigo no se paró.", gap = 600 },
                        { who = "me",    text = "..." },
                        { who = "cesar", text = "¡Y justo hoy viene Kendl! ¡La hermana de CJ! Llega en veinte minutos y yo no puedo quedar mal con ella.", overlap = 350 },
                        { who = "cesar", text = "Necesito viagra. ¡Urgente! Ve a la farmacia de Idlewood, compra lo que sea y vuelve volando." },
                        { who = "me",    text = "Voy a hacer como que no escuché nada." },
                        { who = "cesar", text = "Eres un amigo de verdad. ¡Corre, corre, corre!", overlap = 300 },
                    },
                    place = { 2176.0, -1730.0, 13.5, 0, spread = 1.4 },
                    npcs = { { key = "cesar", contact = "cesar", skin = 292, rel = 2.6 } },
                },
            },
            {
                text = "Sube a la scooter de la sobrina de Cesar",
                pos = P(2182.0, -1736.0, 13.5),
                vehicles = { { key = "moto", model = 462, x = 2182.0, y = -1736.0, z = 13.5, rot = 180, color = { 6, 6 } } },
                getin = "moto",
                radio = { { who = "cesar", text = "Llévate la scooter de mi sobrina, es lo único que tiene gasolina. ¡Y no le cuentes que la usé!" } },
                snap = { 2180.0, -1730.0, 13.5, 180 },
            },
            {
                text = "Ve a la farmacia de Idlewood",
                pos = P(1960.0, -1776.0, 13.5),
                goto = { 1960.0, -1776.0, 13.5, 16, vehicle = true },
                radio = {
                    { who = "cesar", text = "¿Ya vas en camino? ¡Kendl me escribió que sale ahora mismo!" },
                    { who = "cesar", text = "Si el farmacéutico pregunta, tú eres mi sobrino y es para mi abuelo. Mi abuelo tiene... muchos años." },
                },
            },
            {
                text = "Saca a los ladrones de la farmacia",
                pos = P(1960.0, -1776.0, 13.5),
                enemies = {
                    { skins = { 108, 109, 110 }, weapon = 22, ammo = 200, x = 1958.0, y = -1782.0, z = 13.5, radius = 10, count = 3, per = 1, label = "Ladrones" },
                },
                radio = { { who = "cesar", text = "¿Qué es ese ruido? ¿Disparos? ¡Mi cita no puede esperar a que terminen de robar!" } },
                snap = { 1962.0, -1770.0, 13.5, 0 },
            },
            {
                text = "Busca la cajita azul en la farmacia",
                pos = P(1960.0, -1776.0, 13.5),
                interact = {
                    time = 4200, text = "Buscando la cajita azul",
                    anim = { "BOMBER", "BOM_Plant_Loop" },
                    points = { { 1960.0, -1776.0, 13.5, "estante" } },
                },
                radio = {
                    { who = "cesar", text = "¡La cajita azul! ¡Es azul, ¿ves una azul?! ¡Que sea la grande!" },
                    { who = "cesar", text = "Y si ves algo con forma de zanahoria, no lo toques. No sé por qué lo menciono." },
                },
            },
            {
                text = "Vuelve con Cesar antes de que llegue Kendl",
                pos = P(2176.0, -1738.0, 13.5),
                deliver = {
                    vehicle = "moto", x = 2176.0, y = -1738.0, z = 13.5, r = 12, minHealth = 250,
                    ambush = {
                        { at = P(2060.0, -1750.0, 13.5), group = { skins = { 108, 109, 110 }, weapon = 22, ammo = 200, x = 2065.0, y = -1746.0, z = 13.5, radius = 10, count = 3, per = 1 } },
                    },
                },
                radio = {
                    { who = "cesar", text = "¡Ya veo la camioneta de Kendl dando la vuelta a la manzana! ¡Corre!" },
                    { who = "cesar", text = "¡Más rápido! ¡La caja azul no se toma sola!" },
                },
            },
            {
                text = "Habla con Cesar",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("cesar", Wide(2176.0, -1735.0, 13.5, 4200, 58)),
                    lines = {
                        { who = "cesar", text = "¡Lo trajiste! Eres mi héroe. Dame esa cajita... ¿Dos pastillas? ¿Tres? ¿La caja entera?" },
                        { who = "me",    text = "Cesar, la caja dice una sola." },
                        { who = "cesar", text = "Una sola. Claro, claro. Yo sé lo que hago.", gap = 400 },
                        { who = "cesar", text = "Ya me siento... eh... mejor. Mucho mejor. ¡Demasiado mejor!  Oye, la caja dice que si dura más de cuatro horas hay que llamar a un médico." },
                        { who = "me",    text = "Y dice muchas cosas más." },
                        { who = "cesar", text = "Las leo después. Kendl ya está en la puerta... Por cierto, ayer vi la camioneta de Ryder del lado de los morados. Él me dijo que estaba en su casa.", overlap = 250 },
                        { who = "cesar", text = "Algo huele mal. Pero eso será mañana. Ahora déjame solo con mi destino." },
                        { who = "me",    text = "Hablaré con Sweet. Suerte, Cesar." },
                    },
                    place = { 2176.0, -1735.0, 13.5, 0, spread = 1.6 },
                    npcs = { { key = "cesar", contact = "cesar", skin = 292, rel = 2.6 } },
                },
            },
        },
    },

    ----------------------------------------------------------------
    -- 5. Sweet: Humo en Grove (los Ballas contraatacan con rifles del ejercito)
    ----------------------------------------------------------------
    {
        key = "humo_grove",
        requires = { "cesar_viagra" },
        title = "Humo en Grove",
        contact = "sweet",
        desc = "Los Ballas quemaron una casa del barrio y vienen mejor armados que nunca. Persíguelos por el callejón, devuelve el golpe y examina el rifle que dejaron atrás: algo no cuadra.",
        minP = 1, maxP = 4, recommended = 3,
        minLevel = 6, minRespect = 300,
        cash = 5200, respect = 100, xpBonus = 150,
        weather = 9, hour = 20,
        roles = {
            { id = "frontal", name = "Frontal", max = 2, weapons = { { 31, 240 }, { 22, 60 } }, desc = "Rifle para abrir paso" },
            { id = "flanco", name = "Flanco", max = 2, weapons = { { 25, 60 }, { 22, 80 } }, desc = "Escopeta para el callejón" },
            { id = "gang", name = "Pandillero", max = 4, weapons = { { 22, 90 }, { 4, 1 } }, desc = "Pistola y cuchillo" },
        },
        spawns = { { 2491.5, -1676.0, 13.4, 90 }, { 2491.5, -1678.2, 13.4, 90 }, { 2491.5, -1680.4, 13.4, 90 }, { 2491.5, -1682.6, 13.4, 90 } },
        snap = { 2495.0, -1678.0, 13.4, 180 },
        victory = { 2495.3, -1680.0, 13.4, 180, spread = 1.6 },
        victoryCam = { from = P(2500.5, -1670.0, 16.5), look = P(2495.3, -1680.0, 14.4) },
        stages = {
            {
                text = "Habla con Sweet",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("sweet", Wide(2495.3, -1680.0, 13.4, 3600, 62)),
                    lines = {
                        { who = "sweet", text = "Mira eso. Quemaron la casa de la vieja Jackson. La gente se está yendo del barrio." },
                        { who = "me",    text = "¿Fueron los Ballas?" },
                        { who = "sweet", text = "¿Quién más? Después de lo de su esquina y lo del almacén, están furiosos. Y vienen armados como nunca." },
                        { who = "me",    text = "¿Cómo de armados?" },
                        { who = "sweet", text = "Eso vamos a averiguarlo juntos. Los vi cruzar el callejón hace un minuto. Sígueme y no te separes.", overlap = 300 },
                    },
                    place = { 2493.8, -1679.5, 13.4, 90, spread = 1.4 },
                    npcs = { { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 } } },
                },
            },
            {
                text = "Sigue a Sweet hasta el callejón",
                pos = P(2465.0, -1712.0, 13.5),
                goto = { 2465.0, -1712.0, 13.5, 16 },
                radio = { { who = "sweet", text = "Quédense juntos. Si se separan, los cazan uno por uno." } },
                snap = { 2485.0, -1695.0, 13.4, 200 },
            },
            {
                text = "Rechaza el ataque de los Ballas",
                pos = P(2465.0, -1712.0, 13.5),
                waves = {
                    { skins = { 102, 103, 104 }, weapon = 22, ammo = 200, x = 2458.0, y = -1720.0, z = 13.5, radius = 10, count = 3, per = 2, label = "Ballas" },
                    { skins = { 102, 103, 104 }, weapon = 28, ammo = 300, x = 2470.0, y = -1722.0, z = 13.5, radius = 10, count = 3, per = 2, label = "Ballas" },
                    { skins = { 102, 103, 104 }, weapon = 30, ammo = 300, x = 2460.0, y = -1730.0, z = 13.5, radius = 10, count = 3, per = 2, label = "Ballas con rifles" },
                },
                radio = {
                    { who = "sweet", text = "¡Ahí vienen! ¡Cúbranse detrás de los coches!" },
                    { who = "sweet", text = "Esos tienen rifles... Rifles de verdad. ¿De dónde sacaron eso?" },
                },
                snap = { 2470.0, -1700.0, 13.5, 180 },
            },
            {
                text = "Examina el rifle que dejaron los Ballas",
                pos = P(2462.0, -1722.0, 13.5),
                interact = {
                    time = 3500, text = "Examinando el rifle",
                    anim = { "BOMBER", "BOM_Plant_Loop" },
                    points = { { 2462.0, -1722.0, 13.5, "rifle" } },
                },
                radio = { { who = "sweet", text = "Ese rifle... Tráelo, déjame verlo de cerca." } },
            },
            {
                text = "Habla con Sweet",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("sweet", Wide(2462.0, -1722.0, 13.5, 3600, 58)),
                    lines = {
                        { who = "sweet", text = "Número de serie del ejército. Este rifle salió de aquel almacén del puerto." },
                        { who = "me",    text = "Nosotros lo vaciamos. ¿Cómo llegó a manos de los Ballas?" },
                        { who = "sweet", text = "Eso mismo me pregunto. Solo unas pocas personas sabían de ese almacén.", gap = 400 },
                        { who = "me",    text = "Sweet, yo no..." },
                        { who = "sweet", text = "Tranquilo, no dudo de ti. Pero alguien vendió esas armas. Habla con Cesar: ese hombre lo ve todo desde su ventana.", overlap = 250 },
                    },
                    place = { 2460.0, -1721.0, 13.5, 180, spread = 1.5 },
                    npcs = { { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 } } },
                },
            },
        },
    },

    ----------------------------------------------------------------
    -- 6. Cesar: La sombra de Ryder (vigilancia del intercambio)
    ----------------------------------------------------------------
    {
        key = "sombra_ryder",
        requires = { "humo_grove" },
        title = "La sombra de Ryder",
        contact = "cesar",
        desc = "Cesar sospecha de Ryder y quiere comprobarlo con sus propios ojos. Vigilen el intercambio desde las alturas de Jefferson, sin que los vean... aunque probablemente los vean.",
        minP = 1, maxP = 3, recommended = 2,
        minLevel = 7, minRespect = 380,
        cash = 6400, respect = 110, xpBonus = 200,
        weather = 0, hour = 22,
        roles = {
            { id = "driver", name = "Conductor", max = 1, weapons = { { 22, 80 } }, desc = "Maneja el Blade de Cesar" },
            { id = "vigia", name = "Vigía", max = 1, weapons = { { 34, 20 }, { 22, 60 } }, desc = "Observa el intercambio" },
            { id = "escolta", name = "Escolta", max = 2, weapons = { { 28, 300 }, { 25, 40 } }, desc = "Cubre la retirada" },
        },
        spawns = { { 2178.0, -1727.0, 13.5, 180 }, { 2180.5, -1727.0, 13.5, 180 }, { 2183.0, -1727.0, 13.5, 180 } },
        snap = { 2180.0, -1730.0, 13.5, 180 },
        victory = { 2495.3, -1680.0, 13.4, 180, spread = 1.6 },
        victoryCam = { from = P(2500.5, -1670.0, 16.5), look = P(2495.3, -1680.0, 14.4) },
        stages = {
            {
                text = "Escucha a Cesar",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("cesar", Wide(2176.0, -1730.0, 13.5, 3600, 60)),
                    lines = {
                        { who = "cesar", text = "Sweet ya me contó lo de los rifles. Y yo tengo algo que no te había querido decir." },
                        { who = "me",    text = "Habla, Cesar." },
                        { who = "cesar", text = "El día de... la emergencia, vi la camioneta de Ryder del lado de los morados. Y él me dijo que estaba durmiendo." },
                        { who = "me",    text = "Capaz tiene una explicación." },
                        { who = "cesar", text = "Seguro. Pero las explicaciones no andan escondidas detrás de una camioneta llena de cajas. Vamos a verlo con nuestros ojos.", gap = 300 },
                        { who = "cesar", text = "Y esta vez, por favor, nada de preguntas sobre la farmacia." },
                        { who = "me",    text = "Ya lo olvidé." },
                    },
                    place = { 2176.0, -1730.0, 13.5, 0, spread = 1.4 },
                    npcs = { { key = "cesar", contact = "cesar", skin = 292, rel = 2.6, ally = true, weapon = { 22, 200 } } },
                },
            },
            {
                text = "Sube al Blade de Cesar",
                pos = P(2182.0, -1736.0, 13.5),
                vehicles = { { key = "blade", model = 536, x = 2182.0, y = -1736.0, z = 13.5, rot = 180, color = { 3, 3 } } },
                getin = "blade",
                radio = { { who = "cesar", text = "Mi Blade no tiene ni un rasguño. Devuélvemela igual." } },
                snap = { 2180.0, -1730.0, 13.5, 180 },
            },
            {
                text = "Conduce hasta las alturas de Jefferson",
                pos = P(2105.0, -1262.0, 23.9),
                goto = { 2105.0, -1262.0, 23.9, 18, vehicle = true },
                boardNpc = { "cesar", "blade" },
                radio = {
                    { who = "cesar", text = "Apaga las luces cuando estemos cerca. Los morados no son tontos... bueno, no todos." },
                    { who = "cesar", text = "Es en el motel de Jefferson. Ahí hacen los intercambios, lo oí en la peluquería." },
                },
            },
            {
                text = "Vigila el intercambio sin que te vean",
                pos = P(2124.0, -1268.0, 23.9),
                interact = {
                    time = 6000, text = "Vigilando el intercambio",
                    anim = { "BOMBER", "BOM_Plant_Loop" },
                    points = { { 2124.0, -1268.0, 23.9, "vigia" } },
                },
                waves = {
                    { skins = { 102, 103 }, weapon = 22, ammo = 150, x = 2112.0, y = -1255.0, z = 23.9, radius = 8, count = 2, per = 1, label = "Vigías Ballas" },
                },
                radio = { { who = "cesar", text = "Ahí está la camioneta. Es la de Ryder... y está hablando con alguien de morado." } },
            },
            {
                text = "Observa a Ryder",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("cesar", { from = P(2113.0, -1262.0, 27.0), to = P(2116.0, -1264.0, 26.6), look = P(2138.0, -1262.0, 24.8), dur = 3800, fov = 52, shake = 1.5 }),
                    lines = {
                        { who = "cesar", text = "Mira nada más... es él. Ryder, con los morados, repartiendo cajas como si fuera Navidad." },
                        { who = "me",    text = "Esas cajas llevan el sello del ejército." },
                        { who = "cesar", text = "Vendió el almacén. Nuestro almacén.", gap = 400 },
                        { who = "me",    text = "Hay que decírselo a Sweet." },
                        { who = "cesar", text = "Sí, pero antes salgamos de aquí. Creo que nos vieron.", overlap = 200 },
                    },
                    place = { 2124.0, -1268.0, 23.9, 270, spread = 1.4 },
                    npcs = {
                        { key = "cesar", contact = "cesar", skin = 292, rel = 2.6, ally = true, weapon = { 22, 200 } },
                        { key = "ryder", contact = "ryder", skin = 271, x = 2138.0, y = -1262.0, z = 23.9, rot = 270 },
                    },
                },
            },
            {
                text = "¡Te vieron! Elimina a los Ballas",
                pos = P(2124.0, -1268.0, 23.9),
                waves = {
                    { skins = { 102, 103, 104 }, weapon = 28, ammo = 300, x = 2132.0, y = -1262.0, z = 23.9, radius = 10, count = 3, per = 2, label = "Ballas" },
                    { skins = { 102, 103, 104 }, weapon = 30, ammo = 300, x = 2110.0, y = -1245.0, z = 23.9, radius = 10, count = 3, per = 2, label = "Ballas con rifles" },
                },
                radio = { { who = "cesar", text = "¡Nos vieron! ¡Agáchense y disparen!" } },
                snap = { 2115.0, -1262.0, 23.9, 270 },
            },
            {
                text = "Vuelve a Grove Street con la noticia",
                pos = P(2495.0, -1668.0, 13.4),
                goto = { 2495.0, -1668.0, 13.4, 14, vehicle = true },
                boardNpc = { "cesar", "blade" },
                radio = { { who = "cesar", text = "A Grove, rápido. Sweet tiene que enterarse antes que Ryder haga otra de las suyas." } },
            },
            {
                text = "Habla con Sweet",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("sweet", Wide(2495.3, -1670.0, 13.4, 3600, 58)),
                    lines = {
                        { who = "cesar", text = "Sweet, lo vimos con nuestros propios ojos. Ryder. Con los Ballas. Entregando las armas del almacén." },
                        { who = "sweet", text = "No. Ryder no. Ryder y yo crecimos en la misma calle." },
                        { who = "me",    text = "Los rifles no mienten, Sweet." },
                        { who = "sweet", text = "Ya lo sé. Y eso es lo que más me duele.", gap = 500 },
                        { who = "sweet", text = "Esta noche hay otra entrega, en el puerto. Si es verdad, quiero oírselo decir en la cara." },
                    },
                    place = { 2495.3, -1670.0, 13.4, 180, spread = 1.5 },
                    npcs = {
                        { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 } },
                        { key = "cesar", contact = "cesar", skin = 292, x = 2493.4, y = -1672.2, z = 13.4, rot = 15, ally = true, weapon = { 22, 200 } },
                    },
                },
            },
        },
    },

    ----------------------------------------------------------------
    -- 7. Sweet: Trato sucio (emboscada en el puerto y confrontacion con Ryder)
    ----------------------------------------------------------------
    {
        key = "trato_sucio",
        requires = { "sombra_ryder" },
        title = "Trato sucio",
        contact = "sweet",
        desc = "Sweet quiere llegar al puerto antes que Ryder y los Ballas. Una emboscada, una confesión y una decisión que puede romper Grove Street para siempre.",
        minP = 2, maxP = 4, recommended = 3,
        minLevel = 8, minRespect = 480,
        cash = 7800, respect = 130, xpBonus = 300,
        weather = 8, hour = 23,
        roles = {
            { id = "driver", name = "Conductor", max = 1, weapons = { { 22, 80 } }, desc = "Maneja el Greenwood" },
            { id = "shooter", name = "Artillero", max = 2, weapons = { { 31, 300 }, { 22, 60 } }, desc = "Rifle para la emboscada" },
            { id = "gang", name = "Pandillero", max = 4, weapons = { { 25, 60 }, { 22, 90 } }, desc = "Escopeta para el muelle" },
        },
        spawns = { { 2491.5, -1676.0, 13.4, 90 }, { 2491.5, -1678.2, 13.4, 90 }, { 2491.5, -1680.4, 13.4, 90 }, { 2491.5, -1682.6, 13.4, 90 } },
        snap = { 2495.0, -1678.0, 13.4, 180 },
        victory = { 2495.3, -1680.0, 13.4, 180, spread = 1.6 },
        victoryCam = { from = P(2500.5, -1670.0, 16.5), look = P(2495.3, -1680.0, 14.4) },
        stages = {
            {
                text = "Habla con Sweet",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("sweet", Wide(2495.3, -1680.0, 13.4, 3600, 62)),
                    lines = {
                        { who = "sweet", text = "Ryder cerró otra entrega para esta noche en el puerto. Se lo escuché a uno de sus chicos." },
                        { who = "me",    text = "¿Y si hay una explicación?" },
                        { who = "sweet", text = "Hay una sola: traición. Pero quiero oírselo decir a la cara." },
                        { who = "sweet", text = "Vamos a llegar antes que él. Los Ballas caen primero; después, Ryder habla conmigo.", gap = 350 },
                    },
                    place = { 2493.8, -1679.5, 13.4, 90, spread = 1.4 },
                    npcs = { { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 } } },
                },
            },
            {
                text = "Sube al Greenwood",
                pos = P(2487.5, -1674.5, 13.4),
                vehicles = { { key = "car", model = 492, x = 2487.5, y = -1674.5, z = 13.4, rot = 90, color = { 86, 86 } } },
                getin = "car",
                radio = { { who = "sweet", text = "Maneja tú. Y todos adentro, que no quiero esperar a nadie." } },
                snap = { 2495.0, -1678.0, 13.4, 180 },
            },
            {
                text = "Conduce hasta el puerto",
                pos = P(2768.0, -2417.5, 13.6),
                goto = { 2768.0, -2417.5, 13.6, 24, vehicle = true },
                boardNpc = { "sweet", "car" },
                radio = {
                    { who = "sweet", text = "Es la misma zona del almacén. Qué ironía." },
                    { who = "sweet", text = "Apaguen las luces al llegar. Que no nos vean venir." },
                },
            },
            {
                text = "Embosca a los Ballas del intercambio",
                pos = P(2790.0, -2417.5, 13.6),
                waves = {
                    { skins = { 102, 103, 104 }, weapon = 22, ammo = 200, x = 2780.0, y = -2410.0, z = 13.6, radius = 10, count = 3, per = 2, label = "Ballas" },
                    { skins = { 102, 103, 104 }, weapon = 30, ammo = 300, x = 2800.0, y = -2425.0, z = 13.6, radius = 10, count = 4, per = 2, label = "Ballas con rifles" },
                    { skins = { 102, 103, 104 }, weapon = 25, ammo = 100, x = 2790.0, y = -2435.0, z = 13.6, radius = 8, count = 3, per = 2, label = "Refuerzos" },
                },
                radio = {
                    { who = "sweet", text = "¡Ahí están! ¡Fuego a discreción!" },
                    { who = "sweet", text = "Nadie sale de este muelle hasta que Ryder aparezca." },
                },
                snap = { 2770.0, -2418.0, 13.6, 90 },
            },
            {
                text = "Habla con Ryder",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("sweet", Wide(2790.0, -2417.5, 13.6, 3800, 60)),
                    lines = {
                        { who = "ryder", text = "Sweet, ¿qué haces aquí? Esto... esto no es lo que parece." },
                        { who = "sweet", text = "¿No? Tienes una camioneta llena de rifles del ejército y a los Ballas esperándote con el dinero." },
                        { who = "ryder", text = "Les debía, Sweet. Me prestaron para el negocio de las armas y me tenían agarrado del cuello. Amenazaron a mi familia." },
                        { who = "sweet", text = "¡Pudiste decírmelo! ¡Somos Grove Street!", overlap = 300 },
                        { who = "ryder", text = "¿Y qué ibas a hacer tú? ¿Matarlos a todos?", overlap = 300 },
                        { who = "me",    text = "Ryder, nos vendiste." },
                        { who = "ryder", text = "Lo sé. Y me odio por eso. Dame una oportunidad de arreglarlo.", gap = 500 },
                        { who = "sweet", text = "Tienes una. Una sola. Y si me fallas, tú mismo cavas tu tumba." },
                    },
                    place = { 2790.0, -2417.5, 13.6, 90, spread = 1.5 },
                    npcs = {
                        { key = "sweet", contact = "sweet", skin = 270, x = 2791.8, y = -2416.0, z = 13.6, rot = 270, ally = true, weapon = { 28, 500 } },
                        { key = "ryder", contact = "ryder", skin = 271, rel = 2.6 },
                    },
                },
            },
            {
                text = "Vuelve a Grove Street",
                pos = P(2495.0, -1668.0, 13.4),
                goto = { 2495.0, -1668.0, 13.4, 14, vehicle = true },
                boardNpc = { "sweet", "car" },
                radio = { { who = "sweet", text = "Vámonos. Esto no ha terminado." } },
            },
            {
                text = "Habla con Sweet",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("sweet", Wide(2495.3, -1670.0, 13.4, 4200, 58)),
                    lines = {
                        { who = "sweet", text = "Ryder tiene su oportunidad. Si te llama, ve. Pero no le des la espalda." },
                        { who = "me",    text = "¿Y tú?" },
                        { who = "sweet", text = "Yo tengo que decidir si lo perdono o lo entierro. Y todavía no sé cuál duele menos." },
                    },
                    place = { 2495.3, -1670.0, 13.4, 180, spread = 1.5 },
                    npcs = { { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 } } },
                },
            },
        },
    },

    ----------------------------------------------------------------
    -- 8. Ryder: Redencion (volar el arsenal de los Ballas)
    ----------------------------------------------------------------
    {
        key = "redencion",
        requires = { "trato_sucio" },
        title = "Redención",
        contact = "ryder",
        desc = "Ryder busca arreglar lo que rompió. Los Ballas guardan el resto de los rifles del ejército en una casa de Jefferson: pon las cargas, que Ryder te cubre... si es que esta vez cumple.",
        minP = 2, maxP = 4, recommended = 3,
        minLevel = 9, minRespect = 560,
        cash = 9000, respect = 140, xpBonus = 400,
        weather = 0, hour = 3,
        roles = {
            { id = "demolicion", name = "Demolición", max = 2, weapons = { { 24, 70 } }, desc = "Pone las cargas" },
            { id = "cobertura", name = "Cobertura", max = 3, weapons = { { 31, 300 }, { 22, 60 } }, desc = "Rifle para cubrir" },
        },
        spawns = { { 2456.0, -1698.0, 13.5, 270 }, { 2456.0, -1700.5, 13.5, 270 }, { 2456.0, -1703.0, 13.5, 270 }, { 2456.0, -1705.5, 13.5, 270 } },
        snap = { 2458.0, -1700.0, 13.5, 270 },
        victory = { 2455.4, -1700.0, 13.5, 270, spread = 1.6 },
        victoryCam = { from = P(2465.0, -1692.0, 16.0), look = P(2455.4, -1700.0, 14.4) },
        stages = {
            {
                text = "Escucha a Ryder",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("ryder", Wide(2455.0, -1702.0, 13.5, 3800, 62)),
                    lines = {
                        { who = "ryder", text = "Gracias por venir. Sé que Sweet no me quiere ni ver." },
                        { who = "me",    text = "Tienes una oportunidad. Úsala bien." },
                        { who = "ryder", text = "Los Ballas guardan el resto de los rifles en una casa de Jefferson. Si la volamos, se quedan sin nada." },
                        { who = "ryder", text = "Conozco las entradas. Yo te cubro, tú pones las cargas." },
                        { who = "me",    text = "Más te vale que no sea otra trampa." },
                        { who = "ryder", text = "Lo juro por mi madre. Esta vez no fallo.", gap = 350 },
                    },
                    place = { 2455.2, -1700.0, 13.5, 90, spread = 1.4 },
                    npcs = { { key = "ryder", contact = "ryder", skin = 271, rel = 2.6, ally = true, weapon = { 31, 400 } } },
                },
            },
            {
                text = "Sube al Sentinel",
                pos = P(2462.0, -1696.0, 13.5),
                vehicles = { { key = "car", model = 405, x = 2462.0, y = -1696.0, z = 13.5, rot = 270, color = { 0, 0 } } },
                getin = "car",
                radio = { { who = "ryder", text = "Ese Sentinel es el de mi primo. Si lo rayan, me mata antes de que me maten los Ballas." } },
                snap = { 2458.0, -1700.0, 13.5, 270 },
            },
            {
                text = "Conduce hasta la casa de Jefferson",
                pos = P(2150.0, -1280.0, 23.9),
                goto = { 2150.0, -1280.0, 23.9, 18, vehicle = true },
                boardNpc = { "ryder", "car" },
                radio = {
                    { who = "ryder", text = "Voy a estar con ustedes hasta el final. Quiero que lo sepan." },
                    { who = "ryder", text = "La casa está pasando el motel. La reconocerás por los grafitis morados." },
                },
            },
            {
                text = "Limpia la calle de la casa",
                pos = P(2150.0, -1280.0, 23.9),
                waves = {
                    { skins = { 102, 103, 104 }, weapon = 28, ammo = 300, x = 2140.0, y = -1285.0, z = 23.9, radius = 10, count = 3, per = 2, label = "Ballas" },
                    { skins = { 102, 103, 104 }, weapon = 30, ammo = 300, x = 2160.0, y = -1272.0, z = 23.9, radius = 10, count = 4, per = 2, label = "Ballas con rifles" },
                    { skins = { 102, 103 }, weapon = 25, ammo = 100, x = 2150.0, y = -1295.0, z = 23.9, radius = 8, count = 3, per = 2, label = "Guardia del arsenal" },
                },
                radio = { { who = "ryder", text = "¡A la derecha! ¡Dos por la ventana! ¡Yo me encargo, ustedes avancen!" } },
                snap = { 2158.0, -1262.0, 23.9, 180 },
            },
            {
                text = "Coloca las cargas en el arsenal",
                pos = P(2150.0, -1285.0, 23.9),
                interact = {
                    time = 4500, text = "Colocando la carga",
                    anim = { "BOMBER", "BOM_Plant_Loop" },
                    points = {
                        { 2146.0, -1284.0, 23.9, "c1" }, { 2152.0, -1288.0, 23.9, "c2" }, { 2155.0, -1280.0, 23.9, "c3" },
                    },
                },
                radio = {
                    { who = "ryder", text = "Tres cargas: una por pared. Rápido, que esto tiene un temporizador." },
                    { who = "ryder", text = "¡Los vecinos llamaron a los morados! ¡Más rápido!" },
                },
            },
            {
                text = "Huye de la casa antes de que explote",
                pos = P(2455.0, -1690.0, 13.5),
                deliver = {
                    vehicle = "car", x = 2455.0, y = -1690.0, z = 13.5, r = 14, minHealth = 400,
                    ambush = {
                        { at = P(2250.0, -1380.0, 23.9), group = { skins = { 102, 103, 104 }, weapon = 30, ammo = 250, x = 2255.0, y = -1375.0, z = 23.9, radius = 10, count = 3, per = 2 } },
                        { at = P(2380.0, -1580.0, 13.5), group = { skins = { 102, 103, 104 }, weapon = 28, ammo = 250, x = 2385.0, y = -1575.0, z = 13.5, radius = 10, count = 3, per = 1 } },
                    },
                },
                radio = { { who = "ryder", text = "¡Corre! ¡Cuenta hasta diez y se acabó el arsenal!" } },
            },
            {
                text = "Habla con Ryder",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("ryder", Wide(2455.0, -1693.0, 13.5, 4600, 58)),
                    lines = {
                        { who = "ryder", text = "¿Escuchaste eso? Los Ballas se quedaron sin rifles y sin casa." },
                        { who = "me",    text = "Y tú, sin deuda." },
                        { who = "ryder", text = "No del todo. Pero mi conciencia respira mejor. Gracias por no dejarme tirado." },
                        { who = "ryder", text = "Dile a Sweet que lo siento. Y que voy a pagar lo que haga falta.", gap = 350 },
                        { who = "me",    text = "Díselo tú. Mañana es el cumpleaños de Kendl." },
                        { who = "ryder", text = "¿Fiesta? Nadie me invitó. Pero ahí estaré. Con regalo.", overlap = 250 },
                    },
                    place = { 2455.4, -1693.0, 13.5, 0, spread = 1.5 },
                    npcs = { { key = "ryder", contact = "ryder", skin = 271, rel = 2.6 } },
                },
            },
        },
    },

    ----------------------------------------------------------------
    -- 9. Cesar: Pastel para Kendl (la calma antes de la tormenta)
    ----------------------------------------------------------------
    {
        key = "pastel_kendl",
        requires = { "redencion" },
        title = "Pastel para Kendl",
        contact = "cesar",
        desc = "Hoy es el cumpleaños de Kendl y a Cesar solo le falta el pastel. Esta vez nada de farmacias: recoge el pastel de tres pisos y llévalo entero hasta su casa, con los Ballas rondando.",
        minP = 1, maxP = 3, recommended = 2,
        minLevel = 10, minRespect = 650,
        cash = 5800, respect = 80, xpBonus = 200,
        weather = 0, hour = 16,
        roles = {
            { id = "driver", name = "Conductor", max = 1, weapons = { { 22, 80 } }, desc = "Lleva el pastel sin un bache" },
            { id = "escolta", name = "Escolta", max = 2, weapons = { { 28, 300 }, { 22, 60 } }, desc = "Cuida el pastel de los Ballas" },
        },
        spawns = { { 2178.0, -1727.0, 13.5, 180 }, { 2180.5, -1727.0, 13.5, 180 }, { 2183.0, -1727.0, 13.5, 180 } },
        snap = { 2180.0, -1730.0, 13.5, 180 },
        victory = { 2176.0, -1732.0, 13.5, 0, spread = 1.7 },
        victoryCam = { from = P(2185.0, -1722.0, 16.5), look = P(2176.0, -1732.0, 14.4) },
        stages = {
            {
                text = "Habla con Cesar",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("cesar", Wide(2176.0, -1730.0, 13.5, 3600, 60)),
                    lines = {
                        { who = "cesar", text = "Qué bueno que viniste. Hoy es el cumpleaños de Kendl y tengo todo listo, menos el pastel." },
                        { who = "me",    text = "¿Otra emergencia?" },
                        { who = "cesar", text = "¡Esta vez es de pasteles, no de pastillas! Y no me lo recuerdes, que todavía me da vergüenza." },
                        { who = "cesar", text = "El pastel está en la panadería de Willowfield. Tres pisos, de fresa. Si le pasa algo, Kendl me mata. O peor: me deja de hablar.", overlap = 250 },
                        { who = "me",    text = "Será un viaje tranquilo." },
                        { who = "cesar", text = "Ojalá. Pero con los Ballas sueltos, no me fío ni de mi sombra." },
                    },
                    place = { 2176.0, -1730.0, 13.5, 0, spread = 1.4 },
                    npcs = { { key = "cesar", contact = "cesar", skin = 292, rel = 2.6 } },
                },
            },
            {
                text = "Sube al Blade de Cesar",
                pos = P(2182.0, -1736.0, 13.5),
                vehicles = { { key = "blade", model = 536, x = 2182.0, y = -1736.0, z = 13.5, rot = 180, color = { 3, 3 } } },
                getin = "blade",
                radio = { { who = "cesar", text = "Cuidado con las hidráulicas. Hoy no queremos saltitos." } },
                snap = { 2180.0, -1730.0, 13.5, 180 },
            },
            {
                text = "Ve a la panadería de Willowfield",
                pos = P(2285.0, -1752.0, 13.5),
                goto = { 2285.0, -1752.0, 13.5, 14, vehicle = true },
                radio = { { who = "cesar", text = "La panadera se llama doña Lupe. No le digas que es para Kendl, le tiene cariño y te lo regala." } },
            },
            {
                text = "Carga el pastel con mucho cuidado",
                pos = P(2285.0, -1752.0, 13.5),
                interact = {
                    time = 3500, text = "Cargando el pastel",
                    anim = { "BOMBER", "BOM_Plant_Loop" },
                    points = { { 2285.0, -1752.0, 13.5, "pastel" } },
                },
                radio = { { who = "cesar", text = "¿Está entero? ¿Tiene las fresas arriba? ¡No lo inclines!" } },
            },
            {
                text = "Lleva el pastel a casa de Cesar sin dañar el coche",
                pos = P(2176.0, -1738.0, 13.5),
                deliver = {
                    vehicle = "blade", x = 2176.0, y = -1738.0, z = 13.5, r = 12, minHealth = 700,
                    ambush = {
                        { at = P(2250.0, -1745.0, 13.5), group = { skins = { 102, 103, 104 }, weapon = 22, ammo = 200, x = 2255.0, y = -1740.0, z = 13.5, radius = 10, count = 3, per = 1 } },
                        { at = P(2200.0, -1735.0, 13.5), group = { skins = { 102, 103, 104 }, weapon = 28, ammo = 200, x = 2205.0, y = -1730.0, z = 13.5, radius = 10, count = 3, per = 1 } },
                    },
                },
                radio = {
                    { who = "cesar", text = "¡Me dijeron que hay morados siguiéndote! ¡Que no toquen el pastel!" },
                    { who = "cesar", text = "¡Frena suave! ¡Frena suave! ¡Es de tres pisos!" },
                },
            },
            {
                text = "Habla con Cesar",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("cesar", Wide(2176.0, -1735.0, 13.5, 4200, 58)),
                    lines = {
                        { who = "cesar", text = "¡El pastel! ¡Entero! Eres un genio... Un genio con cara de querer cobrar." },
                        { who = "me",    text = "Y también quiero un trozo." },
                        { who = "cesar", text = "Hecho. Mira, ahí llegan Sweet y Ryder. Se saludaron sin matarse. Milagros." },
                        { who = "sweet", text = "Cesar, ¿me escuchas? ¡Los Ballas vienen para Grove con todo lo que tienen!", overlap = 200 },
                        { who = "cesar", text = "Se acabó la fiesta. Vamos, no hay tiempo." },
                    },
                    place = { 2176.0, -1735.0, 13.5, 0, spread = 1.6 },
                    npcs = { { key = "cesar", contact = "cesar", skin = 292, rel = 2.6 } },
                },
            },
        },
    },

    ----------------------------------------------------------------
    -- 10. Sweet: Grove Street, para siempre (final: defensa del barrio con Sweet, Ryder y Cesar)
    ----------------------------------------------------------------
    {
        key = "grove_siempre",
        requires = { "pastel_kendl" },
        title = "Grove Street, para siempre",
        contact = "sweet",
        desc = "Los Ballas vienen con todo lo que les queda. Sweet, Ryder y Cesar defienden el barrio a tu lado: aguanta cada oleada y demuestra que Grove Street no se rinde.",
        minP = 2, maxP = 4, recommended = 4,
        minLevel = 12, minRespect = 700,
        cash = 15000, respect = 160, xpBonus = 600,
        weather = 0, hour = 20,
        roles = {
            { id = "rifle", name = "Fusilero", max = 2, weapons = { { 31, 400 }, { 22, 80 } }, desc = "Rifle para las oleadas" },
            { id = "escopeta", name = "Escopetero", max = 2, weapons = { { 25, 80 }, { 22, 80 } }, desc = "Control de cerca" },
            { id = "apoyo", name = "Apoyo", max = 3, weapons = { { 28, 400 }, { 22, 60 } }, desc = "Fuego de supresión" },
        },
        spawns = { { 2491.5, -1676.0, 13.4, 90 }, { 2491.5, -1678.2, 13.4, 90 }, { 2491.5, -1680.4, 13.4, 90 }, { 2491.5, -1682.6, 13.4, 90 } },
        snap = { 2495.0, -1678.0, 13.4, 180 },
        victory = { 2495.3, -1680.0, 13.4, 180, spread = 1.6 },
        victoryCam = { from = P(2500.5, -1670.0, 16.5), look = P(2495.3, -1680.0, 14.4) },
        stages = {
            {
                text = "Escucha a Sweet",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("sweet", Wide(2495.3, -1678.0, 13.4, 3800, 62)),
                    lines = {
                        { who = "sweet", text = "Escúchenme todos. Los Ballas vienen con lo poco que les queda. Esta es la última vez que nos buscan." },
                        { who = "ryder", text = "Y esta vez no me escondo. Que vengan.", overlap = 250 },
                        { who = "cesar", text = "Yo cuido el flanco derecho. Y si me ven temblar, es el frío." },
                        { who = "me",    text = "Dime dónde me pongo." },
                        { who = "sweet", text = "Defiendan las tres entradas del barrio. Las oleadas vienen una tras otra. Si cae Grove, cae todo lo que hemos hecho.", gap = 300 },
                    },
                    place = { 2495.3, -1676.0, 13.4, 180, spread = 1.4 },
                    npcs = {
                        { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 800 } },
                        { key = "ryder", contact = "ryder", skin = 271, x = 2493.4, y = -1678.8, z = 13.4, rot = 20, ally = true, weapon = { 31, 800 } },
                        { key = "cesar", contact = "cesar", skin = 292, x = 2497.4, y = -1678.8, z = 13.4, rot = 340, ally = true, weapon = { 25, 200 } },
                    },
                },
            },
            {
                text = "Ocupa tu posición en la calle",
                pos = P(2495.0, -1668.0, 13.4),
                goto = { 2495.0, -1668.0, 13.4, 12 },
                radio = { { who = "sweet", text = "A sus puestos. En cuanto se oiga el primer tiro, no paren." } },
            },
            {
                text = "Defiende Grove Street",
                pos = P(2495.0, -1668.0, 13.4),
                waves = {
                    { skins = { 102, 103, 104 }, weapon = 22, ammo = 200, x = 2495.0, y = -1635.0, z = 13.4, radius = 10, count = 4, per = 2, label = "Ballas del norte" },
                    { skins = { 102, 103, 104 }, weapon = 28, ammo = 300, x = 2455.0, y = -1690.0, z = 13.4, radius = 10, count = 4, per = 2, label = "Ballas del oeste" },
                    { skins = { 102, 103, 104 }, weapon = 30, ammo = 300, x = 2495.0, y = -1730.0, z = 13.4, radius = 10, count = 4, per = 2, label = "Ballas del sur" },
                    { skins = { 102, 103, 104 }, weapon = 31, ammo = 300, x = 2495.0, y = -1635.0, z = 13.4, radius = 12, count = 5, per = 2, label = "Ballas con rifles" },
                    { skins = { 102, 103, 104 }, weapon = 30, ammo = 400, x = 2455.0, y = -1690.0, z = 13.4, radius = 12, count = 6, per = 3, label = "Los últimos Ballas" },
                },
                radio = {
                    { who = "sweet", text = "¡Aquí vienen, hermanos! ¡Mantengan la calle!" },
                    { who = "ryder", text = "¡Por el oeste! ¡Yo me encargo, ustedes cubran el sur!" },
                    { who = "cesar", text = "¡Les juro que mi Blade vale más que todos ustedes juntos! ¡Fuera de mi calle!" },
                },
                snap = { 2495.0, -1672.0, 13.4, 180 },
            },
            {
                text = "Habla con Sweet",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("sweet", Wide(2495.3, -1670.0, 13.4, 4200, 58)),
                    lines = {
                        { who = "sweet", text = "Se acabó. Los Ballas no van a pisar esta calle por mucho tiempo." },
                        { who = "ryder", text = "Sweet, yo... gracias por no matarme." },
                        { who = "sweet", text = "Todavía puedo cambiar de opinión.", gap = 400 },
                        { who = "cesar", text = "Entonces celebremos rápido. Hay pastel de fresa en mi casa. Sobró un trozo." },
                        { who = "me",    text = "Y nada de pastillas." },
                        { who = "cesar", text = "¡Eso no se dice en voz alta!", overlap = 200 },
                        { who = "sweet", text = "Grove Street, hermanos. Para siempre.", gap = 500 },
                    },
                    place = { 2495.3, -1670.0, 13.4, 180, spread = 1.4 },
                    npcs = {
                        { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 } },
                        { key = "ryder", contact = "ryder", skin = 271, x = 2493.4, y = -1672.4, z = 13.4, rot = 20, ally = true, weapon = { 31, 500 } },
                        { key = "cesar", contact = "cesar", skin = 292, x = 2497.4, y = -1672.4, z = 13.4, rot = 340, ally = true, weapon = { 25, 200 } },
                    },
                },
            },
        },
    },
}

CONTACT_LABEL = function(key) return (MISSIONS.CONTACTS[key] or {}).name or "Contacto" end
