--[[
    rp_inventory / s_icons.lua (compartido)
    Iconos fotorrealistas de los items: html/icons/<id>.webp (CC0, SwisserDev/fivem-icons-photoreal; ver html/CREDITOS.md).
    applyItemIcons() (al final de s_items.lua) pone iconImg a cada item con icono; las interfaces CEF lo pintan como <img>
    y, si falta, usan el emoji de `icon`. La URL http://mta/rp_inventory/... sirve desde cualquier panel CEF de otro recurso.
    Al anadir un item: descarga su icono a html/icons/<id>.webp, anadelo aqui y como <file> en meta.xml.
]]

local ICON_URL = "http://mta/rp_inventory/html/icons/%s.webp"

-- Items con icono propio (el archivo se llama como el item)
local WITH_ICON = {
    "water", "sandwich", "burger", "coffee", "soda_sprunk", "soda_ecola", "energy_drink",
    "snack_chips", "snack_chocolate", "snack_cookies", "medkit", "vest", "cigarettes", "lighter",
    "phone", "id_card", "train_ticket",
    "bp_small", "bp_school", "bp_hiking", "bp_tactical", "bp_expedition",
    "fish_sardine", "fish_bass", "fish_tuna", "fish_swordfish", "old_boot", "message_bottle", "pearl",
    "meat_game", "hide_rabbit", "hide_deer", "hide_boar", "hide_bear", "antlers",
    "ore_coal", "ore_iron", "ore_copper", "ore_silver", "ore_gold", "gem_raw",
    "old_watch", "gold_ring", "old_coin", "broken_phone", "driver_license",
    "weed", "cocaine", "lsd", "meth",
    "ammo_pistol", "ammo_shotgun", "ammo_smg", "ammo_rifle",
    "pol_cuffs", "pol_taser", "pol_baton", "pol_vest", "pol_kit",
    -- detector de metales (rp_metaldetector)
    "shovel", "rusty_can", "scrap_metal", "rusty_key", "lost_keys", "old_compass",
    "gold_earrings", "gold_chain", "doubloon", "jeweled_tiara",
}

-- Familias (vkey:12, bcard:3): icono por plantilla
local FAMILY_ICON = { ["^vkey:%d+$"] = "vkey", ["^bcard:%d+$"] = "bcard" }

-- Items con icono .png propio (render del modelo 3D): html/icons/<id>.png
local WITH_PNG_ICON = {
    -- detectores de metales (rp_metaldetector/tools/render_icons.py), un color por nivel
    "metal_detector_1", "metal_detector_2", "metal_detector_3", "metal_detector_4", "metal_detector_5",
}

function applyItemIcons(items, families)
    for _, id in ipairs(WITH_ICON) do
        if items[id] then items[id].iconImg = ICON_URL:format(id) end
    end
    for _, id in ipairs(WITH_PNG_ICON) do
        if items[id] then items[id].iconImg = ("http://mta/rp_inventory/html/icons/%s.png"):format(id) end
    end
    for _, family in ipairs(families) do
        local file = FAMILY_ICON[family.pattern]
        if file then family.base.iconImg = ICON_URL:format(file) end
    end
end
