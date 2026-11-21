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
    -- Documento (rp_driving): los datos viven en driving_licenses; el item es solo el papel
    driver_license = {
        name = "Licencia de conducir", icon = "🪪", weight = 0.02, stack = 1, document = true,
        description = "Licencia de conducir clase B. Usala para verla; /mostrarlicencia [id] para ensenarla.",
        use = { event = "driver_license" },
    },
}

function getItemDefinition(itemId)
    return ITEMS[itemId]
end

function getItemList()
    return ITEMS
end
