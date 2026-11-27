--[[
    rp_worldobjects / shared/s_config.lua
    Objetos del mapa original de GTA SA con los que el jugador puede interactuar.

    Para anadir un modelo: ponlo en WO.MODELS con su tipo (kind) y ejecuta
    tools/generar-objetos.ps1, que vuelve a escribir shared/s_data.lua con sus posiciones.
    Para anadir un tipo de interaccion nuevo: entrada en WO.KINDS y su rama en server/s_worldobjects.lua.
]]

WO = {
    SCAN_RADIUS   = 3.0,     -- metros a los que se busca un objeto alrededor del jugador
    USE_DISTANCE  = 2.2,     -- distancia maxima al asiento para usarlo (el servidor da 1 m de margen)
    PROMPT_RANGE  = 2.2,     -- a partir de aqui se dibuja la tecla sobre el asiento
    SEAT_WIDTH    = 0.7,     -- ancho de una plaza: una banca de 2,1 m tiene 3 plazas
    COOLDOWN      = 700,     -- ms entre usos
    CELL          = 50,      -- tamano de la cuadricula espacial (m)
    DEPTH_SAMPLES = 3,       -- muestras de altura a cada lado del centro para hallar asiento y respaldo

    KINDS = {
        sit = {
            label   = "Sentarse",
            -- Animacion de los peatones de GTA en las bancas del parque
            anim    = { "ped", "SEAT_idle" },
            animIn  = { "ped", "SEAT_down", 1400 },  -- al sentarse, luego anim (ms)
            animOut = { "ped", "SEAT_up", 900 },     -- al levantarse
            -- Altura de la raiz del ped sobre el asiento y retroceso hacia el respaldo (ajustar en juego)
            zOffset = 0.48,
            back    = 0.08,
        },
    },

    -- [modelo] = { kind, name, seats (opcional: plazas fijas; si no, salen del ancho del modelo),
    --             zOffset, back, rot (opcionales: postura propia del modelo; se sacan con /setseatoffset) }
    MODELS = {
        -- Exterior
        [1280]  = { kind = "sit", name = "Banca" },                 -- parkbench1
        [1256]  = { kind = "sit", name = "Banca de piedra", zOffset = 0.40, back = -0.44, rot = 0.5 },  -- Stonebench1 (ajustado en juego)
        [1368]  = { kind = "sit", name = "Banca" },                 -- CJ_BLOCKER_BENCH
        [3657]  = { kind = "sit", name = "Asientos" },              -- airseata_LAS
        -- Sofas y sillones
        [1702]  = { kind = "sit", name = "Sofa" },  [1703] = { kind = "sit", name = "Sofa" },
        [1706]  = { kind = "sit", name = "Sofa" },  [1707] = { kind = "sit", name = "Sofa" },
        [1710]  = { kind = "sit", name = "Sofa" },
        [1712]  = { kind = "sit", name = "Sofa" },  [1713] = { kind = "sit", name = "Sofa" },
        [1753]  = { kind = "sit", name = "Sofa" },  [1756] = { kind = "sit", name = "Sofa" },
        [1757]  = { kind = "sit", name = "Sofa" },  [1760] = { kind = "sit", name = "Sofa" },
        [1761]  = { kind = "sit", name = "Sofa" },  [1763] = { kind = "sit", name = "Sofa" },
        [1764]  = { kind = "sit", name = "Sofa" },  [1766] = { kind = "sit", name = "Sofa" },
        [1768]  = { kind = "sit", name = "Sofa" },  [2290] = { kind = "sit", name = "Sofa" },
        [1704]  = { kind = "sit", name = "Sillon", seats = 1 }, [1705] = { kind = "sit", name = "Sillon", seats = 1 },
        [1708]  = { kind = "sit", name = "Sillon", seats = 1 }, [1711] = { kind = "sit", name = "Sillon", seats = 1 },
        [1735]  = { kind = "sit", name = "Sillon", seats = 1 }, [2096] = { kind = "sit", name = "Mecedora", seats = 1 },
        -- Sillas
        [1663]  = { kind = "sit", name = "Silla", seats = 1 }, [1671] = { kind = "sit", name = "Silla", seats = 1 },
        [1714]  = { kind = "sit", name = "Silla", seats = 1 }, [1715] = { kind = "sit", name = "Silla", seats = 1 },
        [1720]  = { kind = "sit", name = "Silla", seats = 1 }, [1721] = { kind = "sit", name = "Silla", seats = 1 },
        [1722]  = { kind = "sit", name = "Silla", seats = 1 }, [1739] = { kind = "sit", name = "Silla", seats = 1 },
        [1806]  = { kind = "sit", name = "Silla", seats = 1 }, [1810] = { kind = "sit", name = "Silla", seats = 1 },
        [1811]  = { kind = "sit", name = "Silla", seats = 1 }, [2079] = { kind = "sit", name = "Silla", seats = 1 },
        [2120]  = { kind = "sit", name = "Silla", seats = 1 }, [2121] = { kind = "sit", name = "Silla", seats = 1 },
        [2122]  = { kind = "sit", name = "Silla", seats = 1 }, [2123] = { kind = "sit", name = "Silla", seats = 1 },
        [2124]  = { kind = "sit", name = "Silla", seats = 1 }, [2125] = { kind = "sit", name = "Silla", seats = 1 },
        [2309]  = { kind = "sit", name = "Silla", seats = 1 }, [2310] = { kind = "sit", name = "Silla", seats = 1 },
        [2343]  = { kind = "sit", name = "Silla", seats = 1 }, [2356] = { kind = "sit", name = "Silla", seats = 1 },
        [2636]  = { kind = "sit", name = "Silla", seats = 1 },
        [2724]  = { kind = "sit", name = "Silla", seats = 1 },
        [2776]  = { kind = "sit", name = "Silla", seats = 1 },
        [2777]  = { kind = "sit", name = "Silla", seats = 1 }, [2788] = { kind = "sit", name = "Silla", seats = 1 },
        [2807]  = { kind = "sit", name = "Silla", seats = 1 },
        -- Taburetes y bancos de diner
        [1716]  = { kind = "sit", name = "Taburete", seats = 1 }, [1805] = { kind = "sit", name = "Taburete", seats = 1 },
        [2350]  = { kind = "sit", name = "Taburete", seats = 1 }, [2723] = { kind = "sit", name = "Taburete", seats = 1 },
        [1723]  = { kind = "sit", name = "Asientos" }, [1724] = { kind = "sit", name = "Asientos" },
        [1726]  = { kind = "sit", name = "Asientos" }, [1727] = { kind = "sit", name = "Asientos" },
        [1728]  = { kind = "sit", name = "Asientos" }, [1729] = { kind = "sit", name = "Asientos" },
    },
}
