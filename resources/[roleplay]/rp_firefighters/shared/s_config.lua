--[[
    rp_firefighters / s_config.lua  (compartido cliente/servidor)

    Facción de bomberos: servicio en el vestuario, autobombas en el garaje y
    emergencias dinámicas (incendio en altura con focos y civiles atrapados).
    Lo que se ajusta sin tocar la lógica va aquí.
]]

FIRE = {
    -- Una facción es de bomberos si su tipo es este (FACTION_TYPES de rp_factions)
    FACTION_TYPE = "bomberos",

    INTERACT_RADIUS = 2.0,       -- metros para pulsar E en vestuario, garaje o civil
    COOLDOWN_MS = 600,           -- entre acciones del mismo jugador

    -- Uniformes del vestuario (skins de bombero de GTA SA)
    SKINS = {
        { id = 277, name = "Estructural" },
        { id = 278, name = "Forestal" },
        { id = 279, name = "Rescate" },
    },
    -- Equipo reglamentario: se entrega al entrar de servicio y se retira al salir.
    -- GTA SA no tiene hacha: la herramienta de entrada forzada es la motosierra de rescate.
    EQUIPMENT = {
        { weapon = 42, ammo = 9000, name = "Extintor" },
        { weapon = 9,  ammo = 1,    name = "Motosierra de rescate" },
    },
    TRUCKS = { 407, 544 },       -- autobomba (con cañón de agua) y escala; el garaje alterna entre ellas

    -- Puntos de la estación. Valores aproximados de la estación de Doherty (San Fierro):
    -- un admin los deja exactos con /fdmover <vestuario|garaje|camion> (se guardan en fire_points).
    POINTS = {
        locker = { x = -2041.2, y = 85.0,  z = 28.4, rot = 0 },
        garage = { x = -2051.6, y = 77.8,  z = 28.4, rot = 0 },
        truck  = { x = -2056.0, y = 84.0,  z = 28.6, rot = 90 },
    },
    STATION_BLIP = { icon = 22, visibleDistance = 500 },

    -- Generador de emergencias: tiempo aleatorio entre una y otra (segundos)
    ALERT_MIN_S = 420,
    ALERT_MAX_S = 900,
    ALERT_FIRST_S = 180,         -- primera tras arrancar el recurso
    MIN_ON_DUTY = 1,             -- bomberos de servicio necesarios para generar una

    -- Incidente
    INCIDENT_TIME_S = 480,       -- si los focos siguen vivos al acabar, el edificio se pierde
    VICTIM_LIFE_S = 300,         -- aire que le queda a cada civil atrapado
    MAX_FOCI = 6,
    MIN_VICTIMS = 1, MAX_VICTIMS = 3,
    FOCUS_HP = 100,
    REGEN_IDLE_S = 12,           -- un foco que nadie ataca en este tiempo vuelve a crecer
    REGEN_PER_S = 1.5,
    EXTRACT_RADIUS = 7.0,        -- radio de la zona segura (ambulancia)
    CLEANUP_S = 20,              -- segundos que la escena queda tras terminar

    -- Chorro: el cliente detecta a qué foco apunta y el servidor revalida distancia y arma
    EXTINGUISHER = { range = 7.5, angle = 38, dps = 9 },     -- a pie con extintor (arma 42)
    CANNON = { range = 40, angle = 16, dps = 24, models = { [407] = true } },   -- cañón de la autobomba

    -- Civil a hombros (relativo al bombero)
    CARRY = { X = 0.0, Y = 0.0, Z = 0.45, RX = 0, RY = 0, RZ = 90 },
    VICTIM_SKINS = { 12, 13, 15, 41, 55, 56, 59, 69, 76, 91, 93, 98, 141, 150, 170, 185, 188, 223, 233 },

    -- Recompensas (al banco, las paga el Estado) y experiencia de facción
    REWARD = {
        BASE = 450,              -- por participar en un incidente resuelto
        PER_RESCUE = 300,        -- por cada civil que llevaste a la zona segura
        PER_FOCUS = 60,          -- por cada foco que apagaste tú (el golpe final)
        XP_BASE = 30, XP_RESCUE = 20, XP_FOCUS = 5,
        LEVEL_XP = 25,           -- XP de rp_levels
        MIN_HITS = 15,           -- daño mínimo al fuego para contar como participante (si no rescató)
    },
    -- Rangos por experiencia de facción (solo título; los roles de verdad son los de rp_factions)
    RANKS = {
        { xp = 0,    name = "Recluta" },
        { xp = 250,  name = "Bombero" },
        { xp = 700,  name = "Bombero 1.ª" },
        { xp = 1600, name = "Teniente" },
        { xp = 3500, name = "Capitán" },
    },
}

-- Rango (índice, nombre, xp del siguiente o nil) de una experiencia
function fireRankOf(xp)
    xp = tonumber(xp) or 0
    local idx = 1
    for i, r in ipairs(FIRE.RANKS) do if xp >= r.xp then idx = i end end
    local nextRank = FIRE.RANKS[idx + 1]
    return idx, FIRE.RANKS[idx].name, nextRank and nextRank.xp or nil, FIRE.RANKS[idx].xp
end
