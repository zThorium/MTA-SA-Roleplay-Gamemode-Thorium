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

    -- rp_jobs: productos y hallazgos de los trabajos (se venden en los puntos de venta de rp_jobs)
    fish_sardine = {
        name = "Sardina", icon = "🐟", weight = 0.2, stack = 30,
        description = "Pescado pequeño. Se vende en la lonja del puerto.",
    },
    fish_bass = {
        name = "Lubina", icon = "🐟", weight = 0.6, stack = 15,
        description = "Buena pieza. Se vende en la lonja del puerto.",
    },
    fish_tuna = {
        name = "Atun", icon = "🐟", weight = 1.5, stack = 6,
        description = "Pez grande y peleon. Se vende bien en la lonja.",
    },
    fish_swordfish = {
        name = "Pez espada", icon = "🐟", weight = 3.0, stack = 3,
        description = "Trofeo de alta mar. La lonja paga mucho por el.",
    },
    old_boot = {
        name = "Bota vieja", icon = "🥾", weight = 0.5, stack = 5,
        description = "Salio del agua con el anzuelo. La lonja da unas monedas.",
    },
    message_bottle = {
        name = "Botella con mensaje", icon = "🍾", weight = 0.3, stack = 3,
        description = "Una botella con un papel enrollado. En la compraventa la quieren.",
    },
    pearl = {
        name = "Perla", icon = "🦪", weight = 0.05, stack = 10,
        description = "Perla natural. Se vende en la compraventa.",
    },
    meat_game = {
        name = "Carne de caza", icon = "🥩", weight = 1.0, stack = 10,
        description = "Carne fresca. Se vende en la carniceria de la cabaña de caza.",
    },
    hide_rabbit = {
        name = "Piel de conejo", icon = "🐇", weight = 0.3, stack = 10,
        description = "Se vende en la peleteria de la cabaña de caza.",
    },
    hide_deer = {
        name = "Piel de ciervo", icon = "🦌", weight = 1.5, stack = 5,
        description = "Se vende en la peleteria de la cabaña de caza.",
    },
    hide_boar = {
        name = "Piel de jabali", icon = "🐗", weight = 1.5, stack = 5,
        description = "Se vende en la peleteria de la cabaña de caza.",
    },
    hide_bear = {
        name = "Piel de oso", icon = "🐻", weight = 4.0, stack = 2,
        description = "Piel enorme y muy cotizada en la peleteria.",
    },
    antlers = {
        name = "Cornamenta", icon = "🦌", weight = 2.0, stack = 2,
        description = "Trofeo de ciervo. La peleteria paga bien por ella.",
    },
    ore_coal = {
        name = "Carbon", icon = "⚫", weight = 1.0, stack = 12,
        description = "Se vende en la fundicion de la cantera.",
    },
    ore_iron = {
        name = "Mineral de hierro", icon = "🪨", weight = 1.2, stack = 10,
        description = "Se vende en la fundicion de la cantera.",
    },
    ore_copper = {
        name = "Mineral de cobre", icon = "🟤", weight = 1.2, stack = 10,
        description = "Se vende en la fundicion de la cantera.",
    },
    ore_silver = {
        name = "Plata en bruto", icon = "⚪", weight = 0.8, stack = 10,
        description = "Se vende en la fundicion de la cantera.",
    },
    ore_gold = {
        name = "Pepita de oro", icon = "🟡", weight = 0.2, stack = 20,
        description = "Se vende en la fundicion de la cantera.",
    },
    gem_raw = {
        name = "Gema en bruto", icon = "💎", weight = 0.1, stack = 10,
        description = "Piedra preciosa sin tallar. Se vende en la compraventa.",
    },
    old_watch = {
        name = "Reloj antiguo", icon = "⌚", weight = 0.1, stack = 5,
        description = "Encontrado entre la basura. Se vende en la compraventa.",
    },
    gold_ring = {
        name = "Anillo de oro", icon = "💍", weight = 0.05, stack = 5,
        description = "Alguien lo tiro sin querer. Se vende en la compraventa.",
    },
    rare_vinyl = {
        name = "Vinilo raro", icon = "💿", weight = 0.3, stack = 5,
        description = "Edicion limitada. Se vende en la compraventa.",
    },
    old_coin = {
        name = "Moneda de coleccion", icon = "🪙", weight = 0.02, stack = 20,
        description = "Moneda antigua. Se vende en la compraventa.",
    },
    broken_phone = {
        name = "Telefono roto", icon = "📵", weight = 0.2, stack = 5,
        description = "No enciende, pero tiene piezas. Se vende en la compraventa.",
    },
}

function getItemDefinition(itemId)
    return ITEMS[itemId]
end

function getItemList()
    return ITEMS
end
