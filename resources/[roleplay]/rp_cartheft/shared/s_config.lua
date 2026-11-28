--[[
    rp_cartheft / shared/s_config.lua  (compartido)
    Robo de vehiculos cerrados: ganzua -> cerradura -> alarma -> puente -> dos bocinazos.
]]

CARTHEFT = {
    ITEM = "lockpick",              -- item de rp_inventory (se vende en las tiendas de rp_shops)
    DOOR_RADIUS = 1.8,              -- m desde la puerta del conductor para forzarla
    REACH = 4.0,                    -- m (servidor) desde el centro del vehiculo: tolerancia al validar
    COOLDOWN_MS = 1500,             -- entre intentos de abrir el minijuego

    -- Tipos de vehiculo que tienen cerradura y se pueden robar
    TYPES = { Automobile = true, ["Monster Truck"] = true, Quad = true },

    -- Minijuego de la cerradura (CEF)
    PICK = {
        PINS = 3,                   -- pines que hay que levantar
        ZONE = { 22, 16, 11 },      -- ancho de la zona buena de cada pin (% de la barra)
        SPEED = { 0.9, 1.15, 1.4 }, -- vueltas por segundo de la aguja en cada pin
        MISSES = 3,                 -- fallos que aguanta la ganzua
        MIN_MS = 2500,              -- tiempo minimo creible (el servidor rechaza un "abierto" antes)
    },
    BREAK_CHANCE = 0.5,             -- probabilidad de que la ganzua se rompa al fallar la cerradura

    -- Minijuego del puente (CEF)
    WIRE = {
        PAIRS = 3,                  -- pares de cables que hay que unir
        MISSES = 3,                 -- calambres que aguantas antes de soltar los cables
        SPARK_ZONE = 18,            -- ancho de la zona de chispa (%)
        SPARK_SPEED = 1.1,
        MIN_MS = 2500,
    },

    -- Alarma
    ALARM_MS = 90000,               -- suena como mucho esto si nadie la apaga
    ALARM_SOUND_DISTANCE = 70,      -- m hasta donde se oye
    HORN_PRESSES = 2,               -- bocinazos para apagarla
    HORN_WINDOW_MS = 1500,          -- entre el primero y el ultimo

    -- Policia que te sorprende (1 estrella con rp_wanted, delito car_steal)
    COP_RADIUS = 25,                -- m: un policia a la vista dentro de este radio te ve
    COP_RADIUS_ALARM = 45,          -- m: con la alarma sonando se acerca a mirar desde mas lejos
    COP_SKINS = { [280] = true, [281] = true, [282] = true, [283] = true, [284] = true, [285] = true, [286] = true, [287] = true, [288] = true },
    POLICE_CAR_MODELS = { [596] = true, [597] = true, [598] = true, [599] = true, [523] = true, [427] = true, [490] = true, [528] = true },

    XP = 15,                        -- rp_levels al apagar la alarma (robo completo)
}
