--[[
    rp_inventory / s_items.lua  (compartido cliente/servidor)
    Catalogo de items. La cantidad que tiene cada personaje se guarda en la
    tabla character_items; aqui solo se definen los tipos de item.

    Campos:
      name        nombre visible
      icon        emoji que muestra la interfaz
      description texto de ayuda
      weight      kg por unidad
      stack       maximo de unidades de este item
      use         efecto al usarlo (nil = no se puede usar):
                  health, armor, hunger, thirst, energy (rp_needs), message,
                  event = dispara rp:onItemUse en el servidor (no se gasta)
      consumable  true si se gasta al usarlo
]]

INVENTORY = {
    MAX_WEIGHT = 15,   -- kg que puede cargar un personaje
}

ITEMS = {
    water = {
        name = "Botella de agua", icon = "💧", weight = 0.5, stack = 10, consumable = true,
        description = "Agua mineral. Quita la sed.",
        use = { thirst = 40, health = 5, message = "Bebes la botella de agua." },
    },
    sandwich = {
        name = "Sandwich", icon = "🥪", weight = 0.3, stack = 10, consumable = true,
        description = "Sandwich de jamon y queso. Quita algo de hambre.",
        use = { hunger = 30, health = 10, message = "Te comes el sandwich." },
    },
    burger = {
        name = "Hamburguesa", icon = "🍔", weight = 0.4, stack = 10, consumable = true,
        description = "Hamburguesa doble. Quita mucha hambre.",
        use = { hunger = 55, thirst = -5, health = 15, message = "Te comes la hamburguesa." },
    },
    coffee = {
        name = "Cafe", icon = "☕", weight = 0.3, stack = 10, consumable = true,
        description = "Cafe cargado. Quita el cansancio.",
        use = { energy = 35, thirst = 5, message = "Te tomas el cafe y te despejas." },
    },
    medkit = {
        name = "Botiquin", icon = "🩹", weight = 1.0, stack = 3, consumable = true,
        description = "Kit de primeros auxilios. Restaura toda la salud.",
        use = { health = 100, message = "Usas el botiquin y te sientes mucho mejor." },
    },
    vest = {
        name = "Chaleco antibalas", icon = "🦺", weight = 3.0, stack = 1, consumable = true,
        description = "Chaleco de kevlar. Te otorga blindaje completo.",
        use = { armor = 100, message = "Te pones el chaleco antibalas." },
    },
    cigarettes = {
        name = "Cigarrillos", icon = "🚬", weight = 0.1, stack = 20, consumable = true,
        description = "Paquete de cigarrillos.",
        use = { message = "Enciendes un cigarrillo y le das una calada." },
    },
    lighter = {
        name = "Encendedor", icon = "🔥", weight = 0.05, stack = 1,
        description = "Un encendedor de bolsillo.",
    },
    phone = {
        name = "Telefono movil", icon = "📱", weight = 0.2, stack = 1,
        description = "Telefono movil: notas, agenda, banco y Fotogram. Tambien se abre con la tecla P.",
        use = { event = "phone" },
    },
}

--[[
    Familias de items: ids con un sufijo variable que comparten definicion.
    Ej.: "vkey:12" es la llave del vehiculo 12. Cada id es un item distinto
    (se guardan por separado en character_items) y usan la plantilla "base".
    Otro recurso puede darle un nombre propio a un id con setItemLabel
    (p. ej. la matricula en la llave).
]]
ITEM_FAMILIES = {
    { pattern = "^vkey:%d+$", base = {
        name = "Llave de vehiculo", icon = "🔑", weight = 0.05, stack = 1,
        description = "Llave de un vehiculo. Usala cerca del vehiculo para abrirlo o cerrarlo.",
        use = { event = "vehicle_key" },
    } },
    -- "bcard:12" es la tarjeta de debito de la cuenta del personaje 12 (rp_bank)
    { pattern = "^bcard:%d+$", base = {
        name = "Tarjeta de debito", icon = "💳", weight = 0.01, stack = 1,
        description = "Tarjeta de debito. Sirve para pagar en los datafonos (p. ej. en la bencinera).",
    } },
}

local itemLabels = {}   -- [itemId] = { name, description, private, owner }

-- private: texto extra que solo ve en su inventario el personaje ownerId
-- (p. ej. el numero y la clave de una tarjeta)
function setItemLabel(itemId, name, description, private, ownerId)
    if type(itemId) ~= "string" then return false end
    itemLabels[itemId] = { name = name, description = description, private = private, owner = tonumber(ownerId) }
    return true
end

function getItemPrivateNote(itemId, characterId)
    local label = itemLabels[itemId]
    if label and label.private and label.owner and label.owner == tonumber(characterId) then return label.private end
    return nil
end

function getItemDefinition(itemId)
    if type(itemId) ~= "string" then return nil end
    local def = ITEMS[itemId]
    if def then return def end
    for _, family in ipairs(ITEM_FAMILIES) do
        if itemId:find(family.pattern) then
            local label = itemLabels[itemId]
            if not label then return family.base end
            local copy = {}
            for k, v in pairs(family.base) do copy[k] = v end
            copy.name = label.name or copy.name
            copy.description = label.description or copy.description
            return copy
        end
    end
    return nil
end

function getItemList()
    return ITEMS
end
