--[[
    rp_characters / s_skins.lua  (compartido cliente/servidor)
    Skins civiles permitidas en la creacion de personajes, por genero.
    Se excluyen CJ, personajes de la historia, policias, militares y skins
    no aptas para rol. El servidor valida contra esta misma lista.
]]

SKINS = {
    -- 0 = masculino
    [0] = {
        1, 2, 7, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 28, 29, 30, 32, 33,
        34, 35, 36, 37, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 57, 58, 59, 60, 61, 62,
        66, 67, 68, 72, 73, 78, 79, 80, 81, 82, 83, 84, 94, 95, 96, 98, 100, 101, 102, 103,
        104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 120, 121, 122, 123, 124,
        125, 126, 127, 128, 132, 133, 134, 135, 136, 137, 142, 143, 144, 146, 147, 153, 154, 155, 156, 158,
        159, 160, 161, 162, 168, 170, 171, 173, 174, 175, 176, 177, 179, 180, 181, 182, 183, 184, 185, 186,
        187, 188, 189, 200, 202, 203, 204, 206, 209, 210, 212, 213, 217, 220, 221, 222, 223, 227, 228, 229,
        230, 234, 235, 236, 239, 240, 241, 242, 247, 248, 249, 250, 253, 254, 255, 258, 259, 260, 261, 262,
        268, 272,
    },
    -- 1 = femenino
    [1] = {
        9, 10, 11, 12, 13, 31, 38, 39, 40, 41, 53, 54, 55, 56, 69, 76, 77, 88, 89, 90,
        91, 93, 129, 130, 131, 138, 139, 140, 141, 148, 150, 151, 157, 169, 172, 190, 191, 192, 193, 194,
        195, 196, 197, 198, 199, 201, 205, 207, 211, 214, 215, 216, 218, 219, 224, 225, 226, 231, 232, 233,
        251, 263,
    },
}

local lookup = { [0] = {}, [1] = {} }
for gender, list in pairs(SKINS) do
    for _, id in ipairs(list) do lookup[gender][id] = true end
end

function isSkinAllowed(skin, gender)
    return lookup[gender] ~= nil and lookup[gender][skin] == true
end
