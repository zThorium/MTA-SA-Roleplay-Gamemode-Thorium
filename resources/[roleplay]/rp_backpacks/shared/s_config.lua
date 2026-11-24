--[[
    rp_backpacks / s_config.lua (compartido)
    Cada mochila es un item de rp_inventory (mismo id). Al usarla se equipa en la espalda.
      capacity  kg que caben dentro
      weight    kg que pesa la mochila vacia (se suma a la carga del personaje)
      model     modelo GTA SA que se ve en la espalda; scale = tamano
    shortcut: el unico modelo de mochila de vanilla es 3026; la variedad se logra con la escala.
    Offsets y rotacion a ojo: ajustarlos en juego con /mochilaoffset.
]]
BACKPACKS = {
    bp_small      = { capacity = 5,  weight = 0.4, model = 3026, scale = 0.75 },
    bp_school     = { capacity = 10, weight = 0.6, model = 3026, scale = 0.9 },
    bp_hiking     = { capacity = 20, weight = 1.2, model = 3026, scale = 1.15 },
    bp_tactical   = { capacity = 30, weight = 1.8, model = 3026, scale = 1.3 },
    bp_expedition = { capacity = 45, weight = 2.5, model = 3026, scale = 1.5 },
}

BACKPACK_BONE = 3                                -- columna (bone_attach)
BACKPACK_OFFSET = { 0, -0.17, 0.02, 90, 0, 0 }   -- x, y, z, rx, ry, rz relativos al hueso (el modelo 3026 nace tumbado: rx 90 lo levanta)
