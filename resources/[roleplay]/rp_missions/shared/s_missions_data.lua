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
                        { who = "ryder", text = "Escuchen, esto es oro puro. Un almacen en el puerto, lleno de cajas del ejercito." },
                        { who = "ryder", text = "Dos cargan el camion, el resto cubre las entradas. La guardia llega por oleadas." },
                        { who = "me",    text = "¿Cuanto tiempo tenemos?" },
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
                    { who = "ryder", text = "Busca el camion, ¡ya! Si te lo revientan, perdimos todo." },
                },
            },
            {
                text = "Habla con Ryder",
                cutscene = {
                    letterbox = true,
                    shots = TalkShots("ryder", { from = P(2462.0, -1684.0, 16.0), to = P(2459.0, -1688.0, 15.6), look = P(2455.0, -1695.0, 14.6), dur = 6000, fov = 58 }),
                    lines = {
                        { who = "ryder", text = "¡Ja ja! Mira esas cajas. Con esto compramos medio barrio." },
                        { who = "me",    text = "Cuando quieras otro soplo, avisame." },
                        { who = "ryder", text = "Aqui tienes tu parte. Ni una palabra a Sweet." },
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
                        { who = "cesar", text = "Necesito unas piezas de un taller del centro. La reja esta cerrada y el dueño no quiere vender." },
                        { who = "cesar", text = "Abran el candado, carguen la furgoneta y llevenla al taller sin un rasguño." },
                        { who = "me",    text = "¿Y si alguien se mete?" },
                        { who = "cesar", text = "Entonces ya saben que hacer. Cuidenme esa carga." },
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
                radio = { { who = "cesar", text = "El taller esta en el centro, cerca de la estacion. Ve con cuidado." } },
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
                radio = { { who = "cesar", text = "Mientras trabajan, ojo. Alguien aviso a los vecinos." } },
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
                        { who = "cesar", text = "Las piezas estan intactas. Eres de los pocos en quienes puedo confiar." },
                        { who = "me",    text = "Un trabajo mas." },
                        { who = "cesar", text = "Con esto ya eres de la familia. Esto es tuyo." },
                    },
                    place = { 2176.0, -1735.0, 13.5, 0, spread = 1.6 },
                    npcs = { { key = "cesar", contact = "cesar", skin = 292, rel = 2.6 } },
                },
            },
        },
    },
}

CONTACT_LABEL = function(key) return (MISSIONS.CONTACTS[key] or {}).name or "Contacto" end
