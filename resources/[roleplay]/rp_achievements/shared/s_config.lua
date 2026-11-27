--[[
    rp_achievements / shared/s_config.lua  (compartido)

    Medallas, puntos, hitos y recompensas. El catálogo de logros está en s_achievements.lua.
    Se lee dentro de funciones (nunca copiar ACH a un local al cargar: CLI-04).
]]

ACH = {}

-- Medallas: 1 bronce, 2 plata, 3 oro, 4 platino. Puntos que da cada una al conseguirla.
ACH.MEDALS = {
    { key = "bronze",   name = "Bronce",  label = "BRONCE",  points = 10,  color = { 205, 127, 50 },  hex = "#cd7f32" },
    { key = "silver",   name = "Plata",   label = "PLATA",   points = 25,  color = { 200, 210, 222 }, hex = "#c8d2de" },
    { key = "gold",     name = "Oro",     label = "ORO",     points = 50,  color = { 255, 196, 64 },  hex = "#ffc440" },
    { key = "platinum", name = "Platino", label = "PLATINO", points = 100, color = { 127, 232, 255 }, hex = "#7fe8ff" },
}

-- Categorías (orden de las pestañas del panel)
ACH.CATEGORIES = {
    { key = "work",     name = "Trabajo",        icon = "🛠️" },
    { key = "treasure", name = "Tesoros",        icon = "🪙" },
    { key = "road",     name = "Carretera",      icon = "🚗" },
    { key = "street",   name = "Ley y calle",    icon = "🚔" },
    { key = "service",  name = "Servicio",       icon = "🚒" },
    { key = "body",     name = "Físico",         icon = "💪" },
    { key = "life",     name = "Vida",           icon = "🏠" },
    { key = "world",    name = "Mundo y social", icon = "🗺️" },
}

--[[
    Hitos: al llegar a `points` puntos de logro se puede reclamar la recompensa en el panel.
      bank     dinero a la cuenta bancaria
      xp       experiencia de rp_levels
      items    { { itemId, cantidad } } (tienen que caber en el inventario al reclamar)
      cosmetic texto que se enseña en el panel (lo desbloquea rp_scoreboard con requires = "milestone:<n>")
]]
ACH.MILESTONES = {
    { points = 50,   bank = 1000,  xp = 500 },
    { points = 150,  bank = 2500,  xp = 1000,  cosmetic = "Icono 🏅 Medalla para tu fila del Tab (/perfil)" },
    { points = 300,  bank = 5000,  xp = 2000,  items = { { "medkit", 2 } } },
    { points = 500,  bank = 8000,  xp = 3000,  items = { { "bp_hiking", 1 } } },
    { points = 800,  bank = 12000, xp = 4000,  cosmetic = "Icono 🏆 Trofeo para tu fila del Tab (/perfil)" },
    { points = 1200, bank = 18000, xp = 6000,  items = { { "bp_tactical", 1 } } },
    { points = 1800, bank = 25000, xp = 8000,  cosmetic = "Letras «Oro» para tu nombre en el Tab (/perfil)" },
    { points = 2500, bank = 35000, xp = 10000, items = { { "bp_expedition", 1 } } },
    { points = 3500, bank = 50000, xp = 15000, cosmetic = "Icono 🐉 Dragón para tu fila del Tab (/perfil)" },
}

ACH.SAVE_INTERVAL = 60000       -- ms entre guardados de las estadísticas cambiadas
ACH.PANEL_COOLDOWN = 1000       -- ms entre aperturas del panel
ACH.CLAIM_COOLDOWN = 1500       -- ms entre reclamos
ACH.BANK_CONCEPT = "Logros"     -- other_name en bank_transactions
ACH.COMMAND = "logros"

-- Índices derivados (no tocar)
ACH.CATEGORY_BY_KEY = {}
for i, c in ipairs(ACH.CATEGORIES) do c.order = i; ACH.CATEGORY_BY_KEY[c.key] = c end

-- 12345 -> "12.345"
function ACH.fmt(n)
    local s = tostring(math.floor((tonumber(n) or 0) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
    return (out:gsub("^%.", ""))
end
