--[[
    rp_relojflores · configuración compartida

    Las medidas del modelo (TILT, CENTER_Z, HAND_Z) las imprime tools/build_flower_clock.py al final
    y tienen que coincidir con las de aquí: si cambias el modelo, cópialas.
]]

FLOWERCLOCK = {
    PLACEHOLDER = 1337,         -- ancla invisible del servidor; el cliente monta el reloj encima (createBuilding)
    NATIVE_TXD_FROM = 4821,     -- BTOLAND2_LAS: su TXD (union_las) trae 'hedge2', el césped del bandejón de Unity
    FORWARD = 9.0,              -- /crearrelojflores lo pone a esta distancia delante del admin (el reloj mide ~15 m)
    DROP = 1.0,                 -- del centro del admin al suelo (el origen del modelo está a ras del suelo)
    LOD_DISTANCE = 300,         -- reloj y pasto de cerca (tope 325); más lejos, el LOD (setLowLODElement)
    LOD_FAR_DISTANCE = 300,     -- distancia del modelo LOD (GTA la multiplica para los LOD)
    FLORA_DISTANCE = 200,       -- matas con alfa y faldón que se funde con el pasto
    HANDS_DISTANCE = 160,       -- las agujas se ven y se mueven a menos de esto de la cámara

    -- Medidas del modelo (tools/build_flower_clock.py)
    TILT = 8.0,                 -- grados que se inclina la esfera hacia el frente
    CENTER_Z = 0.9027,          -- altura del centro de la esfera sobre el origen
    HAND_Z = { hour = 0.44, minute = 0.51, second = 0.57 },   -- alturas de las agujas sobre la esfera

    -- Hora que marca: "game" = hora del juego (la del HUD; el minutero avanza suave entre minutos y el
    -- segundero marca los segundos reales para que se vea andar) o "real" = hora local del jugador.
    TIME_SOURCE = "game",
}
