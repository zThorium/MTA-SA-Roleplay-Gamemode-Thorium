--[[
    rp_heads / s_heads.lua  (compartido cliente/servidor)

    Cabezas personalizadas para el cuerpo de CJ (skin 0). Cada modelo se carga
    en models/<id>.dff/.txd y se pega al cuello (hueso 2 de bone_attach) con
    estos desplazamientos.

    CREDITOS: modelos y ajustes de las cabezas tomados de Countryside-RP,
    desarrollado por Aleks (https://forum.mtasa.com/profile/40470-mraleks/)
    y publicado por Neus. Su licencia prohibe vender estos recursos.
]]

RACES = {
    [1] = "Blanco",
    [2] = "Negro",
    [3] = "Latino",
    [4] = "Asiatico",
}

HEADS = {
    [1] = { race = 4, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [2] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [3] = { race = 1, x = -0.002, y = 0.04, z = -0.255, rx = 3, ry = -90, rz = 8, scale = 1 },
    [4] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [5] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [6] = { race = 2, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [7] = { race = 2, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [8] = { race = 2, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [9] = { race = 2, x = -0.002, y = -0.006, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [10] = { race = 2, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [11] = { race = 1, x = -0.002, y = 0.015, z = -0.2, rx = 0, ry = -90, rz = 14, scale = 1.05 },
    [12] = { race = 1, x = -0.002, y = 0.015, z = -0.18, rx = 0, ry = -90, rz = 13, scale = 1 },
    [13] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [14] = { race = 1, x = -0.002, y = 0.015, z = -0.29, rx = 0, ry = -90, rz = 8, scale = 1 },
    [15] = { race = 1, x = -0.002, y = 0.015, z = -0.22, rx = 0, ry = -90, rz = 8, scale = 1 },
    [16] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [17] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [18] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [19] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [20] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [21] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [22] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [23] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [24] = { race = 4, x = -0.002, y = 0.015, z = -0.22, rx = 0, ry = -90, rz = 8, scale = 1 },
    [25] = { race = 4, x = -0.002, y = 0.015, z = -0.22, rx = 0, ry = -90, rz = 8, scale = 1 },
    [26] = { race = 4, x = -0.006, y = 0.02, z = -0.200, rx = 0, ry = -90, rz = 15, scale = 1 },
    [27] = { race = 1, x = -0.002, y = 0.015, z = -0.230, rx = 0, ry = -90, rz = 8, scale = 1.02 },
    [28] = { race = 3, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [29] = { race = 2, x = -0.002, y = 0.007, z = -0.27, rx = 0, ry = -90, rz = 8, scale = 1 },
    [30] = { race = 4, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [31] = { race = 4, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [32] = { race = 4, x = -0.002, y = 0.015, z = -0.3, rx = 0, ry = -90, rz = 8, scale = 1 },
    [33] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [34] = { race = 1, x = -0.002, y = 0.015, z = -0.17, rx = 0, ry = -90, rz = 8, scale = 1.02 },
    [35] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [36] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [37] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [38] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [39] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [40] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [41] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [42] = { race = 1, x = -0.002, y = 0.015, z = -0.28, rx = 0, ry = -90, rz = 12, scale = 1 },
    [43] = { race = 1, x = -0.002, y = 0.015, z = -0.16, rx = 0, ry = -90, rz = 8, scale = 1 },
    [44] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [45] = { race = 3, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [46] = { race = 3, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [47] = { race = 3, x = -0.002, y = 0, z = -0.15, rx = 0, ry = -90, rz = 10, scale = 1.02 },
    [48] = { race = 3, x = -0.002, y = 0.015, z = -0.21, rx = 0, ry = -90, rz = 8, scale = 1.1 },
    [49] = { race = 3, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [50] = { race = 3, x = -0.002, y = 0.015, z = -0.2, rx = 0, ry = -90, rz = 15, scale = 0.92 },
    [51] = { race = 3, x = -0.002, y = 0.03, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [52] = { race = 2, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [53] = { race = 2, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [54] = { race = 2, x = -0.006, y = 0.02, z = -0.27, rx = 0, ry = -90, rz = 15, scale = 1 },
    [55] = { race = 4, x = -0.002, y = 0.015, z = -0.15, rx = 0, ry = -90, rz = 8, scale = 0.9 },
    [56] = { race = 1, x = -0.002, y = 0.015, z = -0.15, rx = 0, ry = -90, rz = 8, scale = 0.9 },
    [57] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [58] = { race = 1, x = -0.002, y = 0.015, z = -0.272, rx = 0, ry = -90, rz = 8, scale = 1 },
    [62] = { race = 1, x = -0.002, y = 0.015, z = -0.275, rx = 0, ry = -90, rz = 8, scale = 1 },
    [63] = { race = 2, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [65] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [67] = { race = 1, x = -0.002, y = 0.015, z = -0.255, rx = 0, ry = -90, rz = 8, scale = 1 },
    [68] = { race = 1, x = -0.002, y = 0.019, z = -0.217, rx = 0, ry = -90, rz = 8, scale = 1 },
    [69] = { race = 3, x = -0.002, y = 0.019, z = -0.22, rx = 2, ry = -90, rz = 8, scale = 0.9 },
    [70] = { race = 3, x = -0.002, y = 0.019, z = -0.2, rx = 1, ry = -90, rz = 8, scale = 0.9 },
    [71] = { race = 2, x = -0.002, y = 0.015, z = -0.29, rx = 2, ry = -90, rz = 8, scale = 1 },
    [72] = { race = 2, x = -0.002, y = 0.015, z = -0.31, rx = -1, ry = -90, rz = 8, scale = 1 },
    [73] = { race = 2, x = -0.002, y = 0.015, z = -0.31, rx = 1, ry = -90, rz = 8, scale = 1 },
    [74] = { race = 3, x = -0.002, y = 0.015, z = -0.29, rx = 2, ry = -90, rz = 8, scale = 1 },
    [75] = { race = 2, x = -0.002, y = 0.015, z = -0.29, rx = 2, ry = -90, rz = 8, scale = 1 },
    [76] = { race = 2, x = -0.002, y = 0.015, z = -0.260, rx = 0, ry = -90, rz = 8, scale = 1 },
    [77] = { race = 2, x = -0.002, y = 0.015, z = -0.40, rx = 0, ry = -90, rz = 8, scale = 1.1 },
    [78] = { race = 2, x = -0.002, y = 0.015, z = -0.320, rx = -4, ry = -90, rz = 8, scale = 1 },
    [79] = { race = 3, x = -0.002, y = 0.015, z = -0.3, rx = 0, ry = -90, rz = 8, scale = 1 },
    [80] = { race = 2, x = -0.002, y = 0.015, z = -0.3, rx = 0, ry = -90, rz = 8, scale = 1 },
    [81] = { race = 3, x = -0.002, y = 0.015, z = -0.20, rx = 3, ry = -90, rz = 8, scale = 1 },
    [82] = { race = 3, x = -0.002, y = 0.015, z = -0.275, rx = 0, ry = -90, rz = 8, scale = 1 },
    [83] = { race = 3, x = -0.002, y = 0.015, z = -0.29, rx = 0, ry = -90, rz = 8, scale = 1 },
}

function getRaces()
    return RACES
end

-- Lista ordenada de ids de cabeza para una raza
function getHeadsByRace(race)
    local list = {}
    for id, head in pairs(HEADS) do
        if head.race == race then list[#list + 1] = id end
    end
    table.sort(list)
    return list
end

function isValidHead(id, race)
    local head = HEADS[tonumber(id)]
    return head ~= nil and (race == nil or head.race == race)
end