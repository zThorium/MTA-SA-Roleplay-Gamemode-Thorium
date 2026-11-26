--[[
    rp_map / server/s_seed.lua
    Lugares conocidos del mapa original de GTA SA (coordenadas reales del juego) que se
    siembran UNA vez en map_places. Despues los gestionan los admins desde la pestana Admin
    del mapa (si borran uno, no vuelve). Tiendas, bencineras, talleres, cajeros, casas,
    restaurantes y trabajos NO van aqui: se importan solos de sus recursos (ver s_places.lua).
    Formato: { clave unica, nombre, categoria, x, y, z, descripcion }
]]

MAP_SEED = {
    -- Hospitales
    { "hosp_allsaints", "All Saints General Hospital", "hospital", 1172.4, -1323.4, 15.4, "Hospital de Market, Los Santos. Aquí despiertas si te hieren de gravedad." },
    { "hosp_county", "County General Hospital", "hospital", 2034.1, -1404.7, 17.3, "Hospital de Jefferson, Los Santos." },
    { "hosp_sf", "San Fierro Medical Center", "hospital", -2655.1, 635.6, 14.5, "Hospital de Santa Flora, San Fierro." },
    { "hosp_lv", "Las Venturas Hospital", "hospital", 1607.4, 1817.6, 10.8, "Hospital de Las Venturas." },
    { "hosp_carson", "Fort Carson Medical Center", "hospital", -320.2, 1048.4, 20.3, "Centro médico de Fort Carson, Bone County." },
    { "hosp_quebrados", "El Quebrados Medical Center", "hospital", -1514.9, 2525.4, 55.8, "Centro médico de El Quebrados, Tierra Robada." },
    { "hosp_angelpine", "Angel Pine Medical Center", "hospital", -2201.0, -2306.6, 30.6, "Centro médico de Angel Pine, Whetstone." },
    -- Comisarías
    { "pd_ls", "Comisaría de Los Santos (LSPD)", "policia", 1555.5, -1675.6, 16.2, "Departamento de Policía de Los Santos, Pershing Square." },
    { "pd_sf", "Comisaría de San Fierro (SFPD)", "policia", -1605.5, 711.0, 13.9, "Departamento de Policía de San Fierro, Downtown." },
    { "pd_lv", "Comisaría de Las Venturas (LVPD)", "policia", 2287.0, 2431.0, 10.8, "Departamento de Policía de Las Venturas, Roca Escalante." },
    { "pd_dillimore", "Comisaría de Dillimore", "policia", 627.6, -571.7, 17.6, "Policía del condado de Red County." },
    { "pd_carson", "Sheriff de Fort Carson", "policia", -217.8, 979.2, 19.5, "Oficina del sheriff de Bone County." },
    { "pd_angelpine", "Sheriff de Angel Pine", "policia", -2161.3, -2385.3, 30.6, "Oficina del sheriff de Whetstone." },
    -- Aeropuertos
    { "air_ls", "Aeropuerto Internacional de Los Santos", "aeropuerto", 1682.0, -2290.0, 13.5, "Terminal de pasajeros del aeropuerto de Los Santos." },
    { "air_sf", "Aeropuerto Easter Bay (San Fierro)", "aeropuerto", -1423.0, -290.0, 14.1, "Aeropuerto internacional de San Fierro." },
    { "air_lv", "Aeropuerto de Las Venturas", "aeropuerto", 1672.0, 1447.0, 10.8, "Terminal del aeropuerto de Las Venturas." },
    { "air_verdant", "Aeródromo Verdant Meadows", "aeropuerto", 414.0, 2533.0, 16.5, "Aeródromo abandonado del desierto." },
    -- Estaciones de tren
    { "tr_unity", "Estación Unity", "transporte", 1743.0, -1862.0, 13.6, "Estación de tren de El Corona, Los Santos." },
    { "tr_market", "Estación Market", "transporte", 816.6, -1352.6, 13.5, "Estación de tren de Market, Los Santos." },
    { "tr_cranberry", "Estación Cranberry", "transporte", -1974.0, 138.0, 27.7, "Estación de tren de San Fierro." },
    { "tr_linden", "Estación Linden", "transporte", 2847.0, 1290.0, 11.4, "Estación de tren de Las Venturas." },
    { "tr_yellowbell", "Estación Yellow Bell", "transporte", 1433.4, 2620.4, 11.4, "Estación de tren del norte de Las Venturas." },
    -- Gimnasios
    { "gym_ganton", "Gimnasio de Ganton", "gimnasio", 2229.9, -1721.3, 13.6, "Gimnasio y ring de boxeo de Los Santos." },
    { "gym_cobra", "Cobra Martial Arts", "gimnasio", -2270.5, -155.9, 35.3, "Gimnasio de artes marciales de San Fierro." },
    { "gym_belt", "Below the Belt Gym", "gimnasio", 1968.8, 2295.4, 16.5, "Gimnasio de Las Venturas." },
    -- Bares y discotecas
    { "bar_tgb", "Ten Green Bottles", "bar", 2310.0, -1643.5, 14.8, "Bar de Ganton." },
    { "bar_misty", "Misty's", "bar", -2242.4, -88.1, 35.3, "Bar de Garcia, San Fierro." },
    { "bar_probe", "Lil' Probe Inn", "bar", -89.6, 1378.3, 10.5, "Bar de carretera en Lil' Probe Inn." },
    { "bar_pump", "Welcome Pump", "bar", 681.6, -473.4, 16.5, "Bar de Dillimore." },
    { "club_alhambra", "Alhambra", "disco", 1837.0, -1682.4, 13.3, "Discoteca de Idlewood." },
    { "club_jizzy", "Jizzy's Pleasure Domes", "disco", -2624.4, 1412.5, 7.1, "Club de Battery Point, San Fierro." },
    { "club_gaydar", "Gaydar Station", "disco", -2551.1, 193.8, 6.2, "Discoteca de Queens, San Fierro." },
    -- Concesionarios y talleres
    { "car_grotti", "Grotti", "concesionario", 541.0, -1290.0, 17.2, "Concesionario de autos de lujo de Rodeo." },
    { "car_wang", "Wang Cars", "concesionario", -1957.0, 290.0, 35.5, "Concesionario de Doherty, San Fierro." },
    { "car_otto", "Otto's Autos", "concesionario", -1660.0, 1210.0, 7.3, "Concesionario de Downtown, San Fierro." },
    { "tun_ls", "Transfender (Los Santos)", "taller", 1041.0, -1015.0, 32.1, "Taller de tuning de Temple." },
    { "tun_loco", "Loco Low Co.", "taller", 2644.0, -2039.0, 13.6, "Taller de lowriders de Willowfield." },
    { "tun_waa", "Wheel Arch Angels", "taller", -2723.0, 217.0, 4.5, "Taller de tuning de Ocean Flats, San Fierro." },
    { "tun_sf", "Transfender (San Fierro)", "taller", -1936.0, 236.0, 34.3, "Taller de tuning de Doherty." },
    { "tun_lv", "Transfender (Las Venturas)", "taller", 2386.0, 1051.0, 10.8, "Taller de tuning de Las Venturas." },
    { "pns_idle", "Pay 'n' Spray de Idlewood", "taller", 2072.0, -1831.0, 13.5, "Pintura y reparacion." },
    -- Armerias
    { "ammu_ls", "Ammu-Nation (Market)", "tienda", 1368.0, -1279.0, 13.5, "Armería de Los Santos." },
    { "ammu_lv", "Ammu-Nation (Las Venturas)", "tienda", 2158.0, 943.0, 10.8, "Armería de Las Venturas." },
    { "ammu_sf", "Ammu-Nation (San Fierro)", "tienda", -2626.0, 208.0, 4.6, "Armería de Ocean Flats, San Fierro." },
    -- Lugares especiales
    { "sp_grove", "Grove Street", "especial", 2495.0, -1687.0, 13.5, "El barrio de las Grove Street Families." },
    { "sp_vinewood", "Letrero de Vinewood", "especial", 1415.0, -805.0, 85.0, "El letrero de las colinas de Mulholland." },
    { "sp_pier", "Muelle de Santa Maria", "especial", 836.0, -2047.0, 12.9, "Muelle y noria de Santa Maria Beach." },
    { "sp_chiliad", "Cima del Monte Chiliad", "especial", -2321.0, -1638.0, 483.7, "El punto más alto de San Andreas." },
    { "sp_sherman", "Presa Sherman", "especial", -912.0, 2007.0, 60.9, "Presa de Tierra Robada." },
    { "sp_area69", "Área 69", "especial", 213.0, 1875.0, 17.6, "Base militar restringida." },
    { "sp_dragons", "Casino Four Dragons", "especial", 2019.4, 1007.7, 10.8, "Casino del Strip de Las Venturas." },
    { "sp_caligula", "Caligula's Palace", "especial", 2196.4, 1677.0, 12.4, "Casino del Strip de Las Venturas." },
    { "sp_maddogg", "Mansión de Madd Dogg", "especial", 1298.0, -798.0, 84.1, "Mansión de Mulholland." },
}
