-- rp_anims / shared / s_config.lua
-- Catalogo de animaciones. 8 por pagina (rueda del mouse cambia de pagina).
-- Cada entrada: { nombre, bloque, animacion, loop, congelarUltimoFrame }
-- Para agregar una: sumala a una pagina (maximo 8 por pagina). El id es pagina*8+slot.

ANIMS_KEY = "o"   -- la G la usa rp_furniture para interactuar con los muebles

ANIM_PAGES = {
    { title = "Social", list = {
        { "Saludar",           "ON_LOOKERS",  "wave_loop",       true  },
        { "Manos arriba",      "PED",         "handsup",         false, true },
        { "Brazos cruzados",   "COP_AMBIENT", "Coplook_loop",    true  },
        { "Apoyarse",          "GANGS",       "leanIDLE",        true  },
        { "Hablar",            "PED",         "IDLE_chat",       true  },
        { "Senalar",           "ON_LOOKERS",  "point_loop",      true  },
        { "Pensar",            "COP_AMBIENT", "Coplook_think",   true  },
        { "Asentir",           "COP_AMBIENT", "Coplook_nod",     false },
    }},
    { title = "Descanso", list = {
        { "Sentarse",          "BEACH",       "ParkSit_M_loop",  true  },
        { "Sentarse (ella)",   "BEACH",       "ParkSit_W_loop",  true  },
        { "Tumbarse",          "BEACH",       "Lay_Bac_Loop",    true  },
        { "Cansado",           "PED",         "IDLE_tired",      true  },
        { "Fumar",             "SMOKING",     "M_smklean_loop",  true  },
        { "Fumar de pie",      "SMOKING",     "M_smkstnd_loop",  true  },
        { "Esconderse",        "PED",         "cower",           true  },
        { "Llamar por tel.",   "PED",         "phone_talk",      true  },
    }},
    { title = "Expresion", list = {
        { "Bailar 1",          "DANCING",     "DAN_Loop_A",      true  },
        { "Bailar 2",          "DANCING",     "dnce_M_b",        true  },
        { "Rapear",            "RAPPING",     "RAP_A_Loop",      true  },
        { "Rapear 2",          "RAPPING",     "RAP_B_Loop",      true  },
        { "Tai chi",           "PARK",        "Tai_Chi_Loop",    true  },
        { "Gritar",            "ON_LOOKERS",  "shout_01",        false },
        { "Negar",             "COP_AMBIENT", "Coplook_shake",   false },
        { "Pose",              "MISC",        "Hiker_Pose",      false, true },
    }},
}

function getAnimById(id)
    id = tonumber(id)
    if not id or id ~= math.floor(id) or id < 0 then return nil end
    local page = ANIM_PAGES[math.floor(id / 8) + 1]
    return page and page.list[id % 8 + 1]
end

function getAnimByName(name)
    name = tostring(name):lower():gsub("%s+", "")
    for p, page in ipairs(ANIM_PAGES) do
        for s, a in ipairs(page.list) do
            if a[1]:lower():gsub("%s+", ""):gsub("[%(%)%.]", "") == name:gsub("[%(%)%.]", "") then
                return (p - 1) * 8 + s - 1, a
            end
        end
    end
end
