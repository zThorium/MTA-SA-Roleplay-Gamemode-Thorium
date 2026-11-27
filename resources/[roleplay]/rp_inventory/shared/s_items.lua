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
                  meth = segundos de efecto de metanfetamina (elementData "rp:meth")
                  event = dispara rp:onItemUse en el servidor (no se gasta)
      consumable  true si se gasta al usarlo
      lot         unidades que entrega cada compra en una tienda (el precio es por lote)
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
    -- Expendedoras (rp_vending)
    soda_sprunk = {
        name = "Lata de Sprunk", icon = "🥤", weight = 0.35, stack = 10, consumable = true,
        description = "Refresco de lima-limon bien frio. Quita la sed.",
        use = { thirst = 30, message = "Abres la lata de Sprunk y te la tomas." },
    },
    soda_ecola = {
        name = "Lata de eCola", icon = "🥤", weight = 0.35, stack = 10, consumable = true,
        description = "Cola con mucha azucar. Quita la sed y despierta un poco.",
        use = { thirst = 28, energy = 5, message = "Te tomas la eCola de un trago." },
    },
    energy_drink = {
        name = "Bebida energetica", icon = "⚡", weight = 0.35, stack = 6, consumable = true,
        description = "Lata de energetica. Quita el cansancio y algo de sed.",
        use = { energy = 30, thirst = 12, message = "Te tomas la energetica y se te pasa el sueno." },
    },
    snack_chips = {
        name = "Papas fritas", icon = "🥔", weight = 0.15, stack = 10, consumable = true,
        description = "Bolsa de papas fritas. Quita algo de hambre (y da sed).",
        use = { hunger = 22, thirst = -4, message = "Te comes la bolsa de papas fritas." },
    },
    snack_chocolate = {
        name = "Barra de chocolate", icon = "🍫", weight = 0.1, stack = 10, consumable = true,
        description = "Chocolate con mani. Quita algo de hambre y da energia.",
        use = { hunger = 15, energy = 8, message = "Te comes la barra de chocolate." },
    },
    snack_cookies = {
        name = "Galletas", icon = "🍪", weight = 0.2, stack = 10, consumable = true,
        description = "Paquete de galletas. Quita el hambre.",
        use = { hunger = 28, thirst = -3, message = "Te comes el paquete de galletas." },
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
    id_card = {
        name = "DNI", icon = "🆔", weight = 0.02, stack = 1, document = true,
        description = "Documento Nacional de Identidad. Usalo para verlo o ensenalo con /mostrardni [id]. Se tramita en la agencia de empleo.",
        use = { event = "id_card" },
    },

    -- rp_train: se compra en la boleteria de una estacion y se gasta al subir al tren de pasajeros
    train_ticket = {
        name = "Boleto de tren", icon = "🎫", weight = 0.01, stack = 10,
        description = "Un viaje en el tren de pasajeros. Pulsa E junto a un vagón cuando el tren esté en el andén; se gasta al subir.",
    },

    -- rp_backpacks: al usarlas se equipan en la espalda (capacidad y peso en rp_backpacks/shared/s_config.lua)
    bp_small = {
        name = "Mochila pequena", icon = "🎒", iconImg = ITEM_ICON_IMG.bp_small, weight = 0.4, stack = 1,
        description = "Mochila compacta. Capacidad 5 kg.", use = { event = "backpack" },
    },
    bp_school = {
        name = "Mochila escolar", icon = "🎒", iconImg = ITEM_ICON_IMG.bp_school, weight = 0.6, stack = 1,
        description = "Mochila de uso diario. Capacidad 10 kg.", use = { event = "backpack" },
    },
    bp_hiking = {
        name = "Mochila de senderismo", icon = "🎒", iconImg = ITEM_ICON_IMG.bp_hiking, weight = 1.2, stack = 1,
        description = "Mochila grande para excursiones. Capacidad 20 kg.", use = { event = "backpack" },
    },
    bp_tactical = {
        name = "Mochila tactica", icon = "🎒", iconImg = ITEM_ICON_IMG.bp_tactical, weight = 1.8, stack = 1,
        description = "Mochila reforzada de gran capacidad. Capacidad 30 kg.", use = { event = "backpack" },
    },
    bp_expedition = {
        name = "Mochila de expedicion", icon = "🎒", iconImg = ITEM_ICON_IMG.bp_expedition, weight = 2.5, stack = 1,
        description = "La mochila mas grande. Capacidad 45 kg, pero te frena y te cansa mas.", use = { event = "backpack" },
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
    -- Documento (rp_driving): los datos viven en driving_licenses; el item es solo el papel
    driver_license = {
        name = "Licencia de conducir", icon = "🪪", weight = 0.02, stack = 1, document = true,
        description = "Licencia de conducir clase B. Usala para verla; /mostrarlicencia [id] para ensenarla.",
        use = { event = "driver_license" },
    },
    -- Drogas (rp_dealers): solo se compran a los traficantes. "drug" avisa a rp_dealers (evento rp:onDrugUsed) que aplica el efecto.
    weed = {
        name = "Marihuana", icon = "🌿", weight = 0.05, stack = 30, consumable = true,
        description = "Bolsita de marihuana. Ilegal.",
        use = { message = "Te fumas un porro.", drug = "weed" },
    },
    cocaine = {
        name = "Cocaina", icon = "❄️", weight = 0.05, stack = 30, consumable = true,
        description = "Bolsita de cocaina. Ilegal.",
        use = { message = "Esnifas una linea de cocaina.", drug = "cocaine" },
    },
    lsd = {
        name = "LSD", icon = "🌀", weight = 0.01, stack = 30, consumable = true,
        description = "Carton de LSD. Ilegal.",
        use = { message = "Te pones el carton de LSD bajo la lengua.", drug = "lsd" },
    },
    meth = {
        name = "Metanfetamina", icon = "💎", weight = 0.05, stack = 30, consumable = true,
        description = "Cristales de metanfetamina. Ilegal. 1 minuto corriendo mas rapido y sin gastar estamina.",
        use = { meth = 60, message = "Fumas metanfetamina: te sientes imparable." },
    },

    -- rp_ammunation: armas (use.event = "weapon": equipar/guardar) y municion (balas sueltas en el inventario).
    -- weapon = id de arma GTA, ammo = item de municion que gasta. lot = balas por compra en la tienda.
    wpn_colt45 = { name = "Colt 45", icon = "🔫", weight = 1.0, stack = 1, weapon = 22, ammo = "ammo_pistol",
        description = "Pistola de 9mm.", use = { event = "weapon" } },
    wpn_deagle = { name = "Desert Eagle", icon = "🔫", weight = 1.5, stack = 1, weapon = 24, ammo = "ammo_pistol",
        description = "Pistola pesada.", use = { event = "weapon" } },
    wpn_shotgun = { name = "Escopeta", icon = "🔫", weight = 3.0, stack = 1, weapon = 25, ammo = "ammo_shotgun",
        description = "Escopeta de caza.", use = { event = "weapon" } },
    wpn_mp5 = { name = "MP5", icon = "🔫", weight = 2.5, stack = 1, weapon = 29, ammo = "ammo_smg",
        description = "Subfusil.", use = { event = "weapon" } },
    wpn_ak47 = { name = "AK-47", icon = "🔫", weight = 4.0, stack = 1, weapon = 30, ammo = "ammo_rifle",
        description = "Fusil de asalto.", use = { event = "weapon" } },
    wpn_m4 = { name = "M4", icon = "🔫", weight = 3.5, stack = 1, weapon = 31, ammo = "ammo_rifle",
        description = "Fusil de asalto.", use = { event = "weapon" } },
    wpn_rifle = { name = "Rifle de caza", icon = "🔫", weight = 3.5, stack = 1, weapon = 33, ammo = "ammo_rifle",
        description = "Rifle de cerrojo.", use = { event = "weapon" } },
    ammo_pistol = { name = "Municion de pistola", icon = "🔸", weight = 0.02, stack = 120, lot = 30,
        description = "Balas 9mm / .50. Se gastan al disparar el arma equipada." },
    ammo_shotgun = { name = "Cartuchos de escopeta", icon = "🔸", weight = 0.04, stack = 40, lot = 10,
        description = "Cartuchos del calibre 12." },
    ammo_smg = { name = "Municion de subfusil", icon = "🔸", weight = 0.015, stack = 150, lot = 30,
        description = "Balas para subfusil." },
    ammo_rifle = { name = "Municion de fusil", icon = "🔸", weight = 0.025, stack = 90, lot = 30,
        description = "Balas para fusiles y rifles." },

    -- rp_police: equipo reglamentario (se entrega en la armeria y se devuelve al salir de servicio)
    pol_cuffs = { name = "Esposas", icon = "⛓️", weight = 0.3, stack = 3, police = true,
        description = "Esposas reglamentarias. Se usan con la tecla K sobre un sospechoso." },
    pol_taser = { name = "Taser", icon = "⚡", weight = 0.5, stack = 1, police = true, use = { event = "police_equip" },
        description = "Pistola de descargas. Usala para equiparla; deja al objetivo aturdido unos segundos." },
    pol_baton = { name = "Porra", icon = "🏏", weight = 0.5, stack = 1, police = true, use = { event = "police_equip" },
        description = "Porra policial. Usala para equiparla." },
    pol_vest = { name = "Chaleco policial", icon = "🦺", weight = 1.5, stack = 1, police = true, consumable = true,
        description = "Chaleco antibalas reglamentario.", use = { armor = 100, message = "Te pones el chaleco policial." } },
    pol_kit = { name = "Kit de evidencia", icon = "🧪", weight = 0.2, stack = 8, police = true,
        description = "Bolsas y guantes para recolectar evidencia en la escena." },
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

--[[
    Modelo 3D (GTA SA) con el que se ve el item al tirarlo al suelo.
    { modelo, escala }. IDs verificados en data/*.ide del juego.
    Sin entrada = bolsa de dinero (1550). Al crear un item nuevo, anadele su modelo aqui.
    shortcut: sin modelo exacto en vanilla (agua, botiquin, encendedor, pescado...) se usa el mas parecido.
]]
local BOTTLE, CUP, BURGER, WRAP = { 1484, 1.0 }, { 2647, 1.0 }, { 2880, 1.0 }, { 2821, 1.0 }
local SACK, MEAT_A, MEAT_B, BOX = { 2060, 0.5 }, { 2803, 0.6 }, { 2805, 0.6 }, { 1558, 0.6 }
local CARD = { 1581, 1.0 }

local ITEM_MODELS = {
    water = BOTTLE, message_bottle = BOTTLE,
    coffee = CUP,
    burger = BURGER,
    sandwich = WRAP,
    medkit = { 1240, 0.8 },
    vest = { 1242, 0.8 },
    cigarettes = { 1485, 2.5 }, lighter = { 1485, 2.5 },
    phone = { 330, 1.5 }, broken_phone = { 330, 1.5 },
    id_card = CARD, driver_license = CARD, train_ticket = CARD,
    bp_small = { 3026, 0.75 }, bp_school = { 3026, 0.9 }, bp_hiking = { 3026, 1.15 },
    bp_tactical = { 3026, 1.3 }, bp_expedition = { 3026, 1.5 },
    old_watch = { 2710, 1.0 },
    rare_vinyl = { 1210, 0.6 },
    fish_sardine = BOX, fish_bass = BOX, fish_tuna = BOX, fish_swordfish = BOX, old_boot = BOX,
    meat_game = MEAT_A,
    hide_rabbit = MEAT_B, hide_deer = MEAT_B, hide_boar = MEAT_B, hide_bear = MEAT_B, antlers = MEAT_B,
    ore_coal = SACK, ore_iron = SACK, ore_copper = SACK, ore_silver = SACK,
}

function getItemGroundModel(itemId)
    local entry = ITEM_MODELS[itemId]
    if not entry and type(itemId) == "string" and (itemId:find("^vkey:") or itemId:find("^bcard:")) then entry = CARD end
    entry = entry or { 1550, 0.7 }
    return entry[1], entry[2]
end
