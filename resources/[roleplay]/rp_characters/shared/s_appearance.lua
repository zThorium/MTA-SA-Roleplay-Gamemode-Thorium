--[[
    rp_characters / s_appearance.lua  (compartido cliente/servidor)

    Personajes masculinos: cuerpo de CJ (skin 0) sin cabeza + cabeza de rp_heads
    + ropa nativa de CJ (getClothesByTypeIndex). Personajes femeninos: skin.
]]

CUSTOM_SKIN = 0

-- Partes de ropa editables: clave del formulario -> tipo de ropa de CJ
CLOTHES_SLOTS = {
    { key = "torso", column = "clothes_torso", type = 0 },
    { key = "legs",  column = "clothes_legs",  type = 2 },
    { key = "shoes", column = "clothes_shoes", type = 3 },
}

-- Numero de prendas disponibles por tipo (se calcula una vez)
local clothesCount = {}

function getClothesCount(clothesType)
    if not clothesCount[clothesType] then
        local n = 0
        while getClothesByTypeIndex(clothesType, n) do n = n + 1 end
        clothesCount[clothesType] = n
    end
    return clothesCount[clothesType]
end

function isValidClothes(clothesType, index)
    return type(index) == "number" and index == math.floor(index)
        and index >= 0 and index < getClothesCount(clothesType)
end

-- Aplica la apariencia guardada (fila de la tabla characters) a un ped/jugador.
-- En el cliente solo funciona con peds locales; en el servidor se sincroniza.
function applyCharacterLook(ped, look)
    local head = tonumber(look.head)
    if head then
        if getElementModel(ped) ~= CUSTOM_SKIN then setElementModel(ped, CUSTOM_SKIN) end
        for _, slot in ipairs(CLOTHES_SLOTS) do
            removePedClothes(ped, slot.type)
            local index = tonumber(look[slot.column] or look[slot.key])
            local texture, model = getClothesByTypeIndex(slot.type, index or 0)
            if texture then addPedClothes(ped, texture, model, slot.type) end
        end
        setPedHeadless(ped, true)
    else
        setPedHeadless(ped, false)
        local skin = tonumber(look.skin)
        if skin and getElementModel(ped) ~= skin then setElementModel(ped, skin) end
    end
    return head
end
