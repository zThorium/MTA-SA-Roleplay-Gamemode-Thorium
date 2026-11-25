--[[
    rp_balizas / s_config.lua

    Basado en EmergencyLight (nyolc8, CLEO): posiciones y colores de vehicles.ini.
    Cada modelo tiene una baliza con lado izquierdo (L) y derecho (R); x se espeja.
    Las luces se encienden con la sirena del vehiculo (getVehicleSirensOn).
]]

BALIZAS = {
    MAX_DIST      = 140,   -- distancia maxima para dibujar coronas
    SURFACE_DIST  = 55,    -- distancia maxima para reflejar en paredes y piso
    MAX_SURFACE   = 3,     -- vehiculos mas cercanos que reflejan en superficies
    MAX_LIGHTS    = 2,     -- vehiculos mas cercanos con luz dinamica real
    RAY_RANGE     = 13.0,  -- alcance del destello sobre superficies (m)
    RAY_REFRESH   = 90,    -- ms entre recalculos de rayos
    YAWS          = 8,     -- rayos horizontales por lado
    PITCHES       = { -6, -28, -58 }, -- grados: pared lejana, pared/piso, piso cercano
    CORONA_SIZE   = 0.55,
    SURFACE_ALPHA = 150,   -- 0-255, intensidad maxima del reflejo
    LIGHT_RADIUS  = 14,
}

-- Patron por lado: 16 ranuras de 50 ms (800 ms). 1 = encendido.
BALIZAS.PATTERN = {
    L = { 1,0,1,0,1,0,0,0, 0,0,0,0,0,0,0,0 },
    R = { 0,0,0,0,0,0,0,0, 1,0,1,0,1,0,0,0 },
}

local BLUE, RED = { 0, 40, 255 }, { 255, 0, 0 }
local function police(y, z) return { x = 0.5, y = y, z = z, cL = BLUE, cR = RED } end
local function red(x, y, z) return { x = x, y = y, z = z, cL = RED, cR = RED } end

-- [modelo] = { x, y, z (offset del lado derecho), cL, cR }
BALIZAS.MODELS = {
    [596] = police(-0.35, 0.90), -- copcarla
    [597] = police(-0.35, 0.90), -- copcarsf
    [598] = police(-0.35, 0.90), -- copcarvg
    [599] = police(-0.10, 1.15), -- copcarru
    [490] = police( 0.20, 1.15), -- FBI Rancher
    [407] = red(0.75, 3.30, 1.35), -- firetruk
    [544] = red(0.75, 3.30, 1.35), -- firetruk LS
    [416] = red(0.50, 0.90, 1.20), -- ambulan
    [427] = red(0.40, 1.15, 1.40), -- enforcer
}
