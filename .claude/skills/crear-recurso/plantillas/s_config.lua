--[[
    rp_sistema / s_config.lua  (compartido cliente/servidor)

    Configuración del sistema. Todo lo que un diseñador querría ajustar sin tocar la
    lógica va aquí: precios, tiempos, radios, coordenadas, textos.
    Lo que el cliente no debe saber va en server/s_config.lua (type="server").
]]

SISTEMA = {
    -- Dimensión propia si el sistema usa interiores/instancias (bloque libre: ver referencia/REGISTROS.md)
    -- DIMENSION_BASE = 23000,

    INTERACT_RADIUS = 2.0,       -- metros para pulsar E
    COOLDOWN_MS = 800,           -- entre acciones del mismo jugador (lo vuelve a aplicar el servidor)

    PRICE = 100,                 -- $; 0 = gratis
    PAYMENT = "cash",            -- "cash" (efectivo) | "bank" (cuenta) | "none"
    XP_REWARD = 0,               -- XP de rp_levels por completar; 0 = nada

    MARKER = { type = "cylinder", size = 1.2, r = 245, g = 165, b = 36, a = 140 },
    -- Icono de un id que rp_hud conozca (KNOWN_BLIP_ICON_IDS), si no no se dibuja
    BLIP = { enabled = true, icon = 52, size = 2, r = 255, g = 255, b = 255, visibleDistance = 400 },

    -- Puntos fijos. Si los colocan los admins, van en una tabla de la BD (skill comando-admin) y no aquí.
    POINTS = {
        -- { name = "Ganton", x = 0, y = 0, z = 0, rot = 0, interior = 0, dimension = 0 },
    },
}
