DEALERS = {
    SKINS = { [28] = true, [29] = true, [30] = true },   -- Drug Dealer de GTA SA
    DEFAULT_SKIN = 28,

    -- item de rp_inventory -> precio en efectivo
    CATALOG = { weed = 60, cocaine = 180, lsd = 120, meth = 250 },

    -- Policia a la vista: skins de policia de GTA SA (280-288) o ped con elementData rp:cop
    COP_SKINS = { [280] = true, [281] = true, [282] = true, [283] = true, [284] = true, [285] = true, [286] = true, [287] = true, [288] = true },
    COP_RADIUS = 30,        -- m: distancia maxima a la que un policia te ve comprar
    COP_REPORT_MS = 8000,   -- el aviso del cliente vale este tiempo para la compra
}

-- Efectos de las drogas (rp_dealers/server/s_drugs.lua y client/c_effects.lua)
DRUGS = {
    -- ms: duracion; dose: puntos de sobredosis; crash: necesidades que se restan al pasarse el efecto
    weed    = { ms = 90000,  dose = 1, crash = { hunger = -25 } },                -- relajado, ojos verdosos, mucha hambre despues
    cocaine = { ms = 60000,  dose = 2, crash = { energy = -30, thirst = -15 } },  -- acelerado y con energia, bajon despues
    lsd     = { ms = 120000, dose = 1, crash = { energy = -15 } },                -- alucinaciones visuales
    OD_LIMIT = 5,            -- sobredosis si los puntos recientes llegan a esto
    DOSE_DECAY_MS = 60000,   -- cada tanto baja 1 punto
}
