--[[
    rp_police / s_config.lua  (compartido)
    Policia de Los Santos (faccion 1). Los permisos viven en rp_factions
    (pol_detain, pol_fine, pol_mdt, pol_bolo, pol_armory, pol_garage, pol_evidence).
]]

POLICE = {
    FACTION_ID = 1,
    KEY_INTERACT = "k",       -- cursor de interaccion (jugadores y vehiculos)
    KEY_MDT = "F6",
    KEY_SIREN = "o",
    KEY_USE = "e",            -- puntos (vestuario, armeria...) y evidencia
    INTERACT_DISTANCE = 3.5,
    POINT_RADIUS = 1.8,
    BOOKING_RADIUS = 35,      -- m al punto de calabozos para poder encarcelar
    MAX_JAIL_MIN = 60,
    BAIL_PER_MIN = 60,
    MAX_FINE = 5000,
    MAX_BOLO_REWARD = 20000,
    TASER_RANGE = 18,
    TASER_SECONDS = 8,
    TASER_COOLDOWN = 4000,
    ALERTS_KEEP = 40,
    ALERT_BLIP_MS = 120000,
    SHOT_ALERT_COOLDOWN = 45000,
    WANTED_ALERT_COOLDOWN = 60000,
    EVIDENCE_LIFE = 25 * 60 * 1000,
    EVIDENCE_MAX = 60,
    EVIDENCE_PICKUP = 2.5,
    SCRATCHED_SERIAL_CHANCE = 0.25,
}

-- Puntos por defecto (ajustables en juego con /pmover <tipo>; z = suelo)
POLICE_POINTS = {
    -- Puerta de la comisaria (publica): E en la puerta entra, E en la salida del interior sale.
    -- rot = hacia donde mira el jugador al aparecer; aparece 2 m por delante del marcador.
    entrance      = { label = "Comisaria LSPD", x = 1554.6, y = -1675.6, z = 16.2, rot = 90, interior = 0, public = true, color = { 255, 255, 255 } },
    exit          = { label = "Salir",          x = 246.4,  y = 62.8,    z = 1003.6, rot = 0, interior = 6, public = true, color = { 255, 255, 255 } },
    -- Dentro del interior 6 (posiciones ajustadas en juego con /pmover)
    locker        = { label = "Vestuario",    x = 240.2, y = 73.1, z = 1005.0, rot = 190, interior = 6, color = { 59, 111, 224 } },
    armory        = { label = "Armeria",      x = 254.7, y = 78.8, z = 1003.6, rot = 10, interior = 6, color = { 229, 72, 77 } },
    lab           = { label = "Laboratorio",  x = 218.4, y = 78.9, z = 1005.0, rot = 100, interior = 6, color = { 163, 91, 255 } },
    booking       = { label = "Calabozos",    x = 267.8, y = 85.2, z = 1001.0, rot = 180, interior = 6, color = { 245, 165, 36 } },
    -- Fuera, junto a la comisaria
    garage        = { label = "Garaje",       x = 1558.4, y = -1610.6, z = 13.4, rot = 169, interior = 0, color = { 76, 211, 138 } },
    garage_spawn  = { label = "Salida de patrullas", x = 1535.8, y = -1671.5, z = 13.1, rot = 0, interior = 0, hidden = true },
}

-- Articulos de armeria. issued = entrega gratis el Estado; si no, se paga con efectivo propio.
-- level = nivel de rol minimo. amount = unidades por compra.
POLICE_ARMORY = {
    { item = "pol_cuffs", price = 0,    level = 1, amount = 1, issued = true },
    { item = "pol_taser", price = 0,    level = 1, amount = 1, issued = true },
    { item = "pol_baton", price = 0,    level = 1, amount = 1, issued = true },
    { item = "pol_vest",  price = 0,    level = 1, amount = 1, issued = true },
    { item = "pol_kit",   price = 0,    level = 2, amount = 2, issued = true },
    { item = "wpn_colt45",   price = 400,  level = 1, amount = 1 },
    { item = "ammo_pistol",  price = 60,   level = 1, amount = 30 },
    { item = "wpn_shotgun",  price = 1100, level = 3, amount = 1 },
    { item = "ammo_shotgun", price = 80,   level = 3, amount = 10 },
    { item = "wpn_mp5",      price = 1500, level = 3, amount = 1 },
    { item = "ammo_smg",     price = 90,   level = 3, amount = 30 },
    { item = "wpn_m4",       price = 3200, level = 7, amount = 1 },
    { item = "ammo_rifle",   price = 150,  level = 7, amount = 30 },
}

POLICE_GARAGE = {
    { model = 596, name = "Patrulla LSPD",     level = 1 },
    { model = 599, name = "Patrulla Ranger",   level = 2 },
    { model = 523, name = "Moto HPV1000",      level = 2 },
    { model = 490, name = "FBI Rancher",       level = 5 },
    { model = 427, name = "Enforcer (SWAT)",   level = 7 },
    { model = 497, name = "Helicoptero Police Maverick", level = 8 },
}

-- Vehiculos que cuentan como policiales (sirena, radar, acceso)
POLICE_VEHICLE_MODELS = { [596] = true, [597] = true, [598] = true, [599] = true, [523] = true, [427] = true, [490] = true, [497] = true }

-- Roles de la faccion 1 (nombre, nivel, sueldo, permisos). Los lideres lo tienen todo.
POLICE_RANKS = {
    { name = "Cadete",     level = 1,  salary = 600,  perms = { "members", "pol_detain", "pol_armory", "pol_garage" } },
    { name = "Oficial I",  level = 2,  salary = 800,  perms = { "members", "pol_detain", "pol_fine", "pol_mdt", "pol_armory", "pol_garage" } },
    { name = "Oficial II", level = 3,  salary = 950,  perms = { "members", "pol_detain", "pol_fine", "pol_mdt", "pol_armory", "pol_garage", "pol_evidence" } },
    { name = "Sargento",   level = 5,  salary = 1150, perms = { "members", "invite", "pol_detain", "pol_fine", "pol_mdt", "pol_armory", "pol_garage", "pol_evidence", "pol_bolo", "log_view" } },
    { name = "Teniente",   level = 7,  salary = 1350, perms = { "members", "invite", "kick", "set_rank", "log_view", "bank_view", "pol_detain", "pol_fine", "pol_mdt", "pol_armory", "pol_garage", "pol_evidence", "pol_bolo" } },
    { name = "Comisario",  level = 10, salary = 2000, perms = "all" },
}

-- Codigos de despacho
POLICE_CODES = {
    shots   = { code = "10-71", title = "Disparos",              color = { 229, 72, 77 } },
    wanted  = { code = "10-80", title = "Persona buscada",       color = { 245, 165, 36 } },
    call    = { code = "10-21", title = "Llamada ciudadana",     color = { 76, 154, 255 } },
    panic   = { code = "10-99", title = "Oficial pide ayuda",    color = { 255, 60, 60 } },
    robbery = { code = "10-90", title = "Robo en curso",         color = { 229, 72, 77 } },
}

-- Bits de rp_factions/shared/s_config.lua (para sembrar los roles de la faccion 1)
POLICE_PERM_BITS = {
    members = 1, invite = 2, kick = 4, set_rank = 8, manage_ranks = 16, bank_view = 32, bank_deposit = 64,
    bank_withdraw = 128, log_view = 256, edit_motd = 512,
    pol_detain = 1024, pol_fine = 2048, pol_mdt = 4096, pol_bolo = 8192, pol_armory = 16384, pol_garage = 32768, pol_evidence = 65536,
}
function policePermMask(list)
    local mask = 0
    if list == "all" then
        for _, b in pairs(POLICE_PERM_BITS) do mask = mask + b end
        return mask
    end
    for _, k in ipairs(list) do mask = mask + (POLICE_PERM_BITS[k] or 0) end
    return mask
end
