--[[
    rp_ammunation / s_config.lua
    Todas las armerias usan el interior 4 (Ammu-Nation 2) en su propia dimension (22000 + id).
    shortcut: la posicion del vendedor (CLERK) es estimada, ajustar en juego. Para otra armeria, anadir una fila.
]]
AMMU = {
    DOOR_DISTANCE = 2.0,
    INTERIOR = 4,
    ENTRY = { x = 285.8, y = -84.55, z = 1001.54, rot = 270 },   -- donde apareces y donde esta la puerta de salida
    CLERK = { x = 290.5, y = -84.5, z = 1001.52, rot = 90, skin = 179 },
    LOCATIONS = {
        { id = 1, name = "Ammu-Nation Market", x = 1368.1, y = -1279.8, z = 13.55 },
    },
    -- item = precio (municion: precio por lote, ver `lot` en rp_inventory)
    CATALOG = {
        wpn_colt45 = 600, wpn_deagle = 1800, wpn_shotgun = 1200, wpn_mp5 = 2200,
        wpn_ak47 = 3500, wpn_m4 = 4500, wpn_rifle = 2800,
        ammo_pistol = 60, ammo_shotgun = 50, ammo_smg = 80, ammo_rifle = 120,
    },
}

function ammuDimension(loc) return 22000 + loc.id end
