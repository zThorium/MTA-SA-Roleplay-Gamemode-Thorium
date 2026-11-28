--[[
    rp_logs / s_config.lua  (solo servidor)
]]

LOGS = {
    FLUSH_MS       = 5000,    -- cada cuánto se escribe la cola en la BD
    FLUSH_ROWS     = 50,      -- o antes, si la cola llega a estas filas
    RETENTION_DAYS = 90,      -- al arrancar se borran las filas más viejas
    WATCH_MS       = 30000,   -- red de seguridad: cada cuánto se mira el efectivo de cada jugador
    CASH_JUMP      = 50000,   -- salto de efectivo entre dos miradas que se registra como cash_jump
    SEARCH_ROWS    = 15,      -- filas que muestra /logs en el chat

    -- Tipos válidos. Un tipo que no esté aquí se rechaza (aviso en la consola) para que el
    -- registro se pueda filtrar. Al enganchar un sitio nuevo, añade su tipo aquí y en RECURSOS.md.
    TYPES = {
        -- Efectivo
        cash_give       = "Dar efectivo a otro jugador",
        cash_rob        = "Robar efectivo a otro jugador",
        cash_jump       = "Salto de efectivo no explicado (red de seguridad)",
        -- Banco
        bank_deposit    = "Depósito en el banco",
        bank_withdraw   = "Retiro del banco",
        bank_transfer   = "Transferencia entre cuentas",
        payday          = "Sueldo del payday",
        -- Admin
        admin_cash      = "Admin da efectivo",
        admin_setcash   = "Admin fija el efectivo",
        admin_bank      = "Admin da dinero al banco",
        admin_funds     = "Admin da fondos a una facción",
        -- Ítems
        item_give       = "Dar un ítem a otro jugador",
        item_rob        = "Quitar un ítem a otro jugador (cacheo)",
        item_drop       = "Soltar un ítem al suelo",
        item_pickup     = "Recoger un ítem del suelo",
        backpack_drop   = "Soltar la mochila",
        -- Propiedades y vehículos
        prop_buy        = "Comprar una casa",
        prop_sell       = "Vender una casa",
        vehicle_buy     = "Comprar un vehículo en la concesionaria",
        vehicle_key     = "Dar la llave de un vehículo",
    },
}
