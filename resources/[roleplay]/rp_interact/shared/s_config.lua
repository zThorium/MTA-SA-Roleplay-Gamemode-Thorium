--[[
    rp_interact / s_config.lua  (compartido)
    Ajustes del menú de interacción con jugadores (M + clic derecho sobre una persona).
]]

INTERACT = {
    DISTANCE = 3.5,              -- m: distancia máxima para las acciones normales
    PICK_DISTANCE = 7,           -- m: hasta dónde se puede señalar a alguien con el cursor
    PICK_RADIUS = 60,            -- px: margen alrededor de la persona al hacer clic
    ADMIN_DISTANCE = 80,         -- m: los admins pueden abrir el menú (solo bloque admin) desde más lejos
    VEHICLE_INVITE_DISTANCE = 8, -- m: distancia del invitado a tu vehículo
    COOLDOWN_MS = 600,           -- entre acciones del mismo jugador
    REQUEST_SECONDS = 15,        -- tiempo para aceptar una propuesta
    MONEY_MAX = 5000,            -- $ máximo por entrega en mano
    MONEY_COOLDOWN_MS = 5000,
    MONEY_LOG_FROM = 1000,       -- entregas desde esta cifra quedan en el log del servidor
    ROB_CASH_MAX = 5000,         -- $ máximo que se le quita por clic a alguien reducido en el cacheo
    TAKE_COOLDOWN_MS = 1500,     -- entre cosas quitadas en el cacheo
    CPR_SECONDS = 8,             -- reanimar con botiquín (civil)
    MED_CPR_SECONDS = 5,         -- reanimar siendo médico o bombero de servicio
    MEDKIT_ITEM = "medkit",
    TIP_DISTANCE = 4,            -- m: a esta distancia de alguien aparece el consejo de la primera vez
    TIP_SECONDS = 2,             -- s cerca de alguien antes de mostrar el consejo
}

-- Gestos con otra persona (los dos deben aceptar). Animaciones originales de GTA SA.
-- gap = metros entre los dos durante el gesto (el invitado se coloca frente a ti).
INTERACT_GESTURES = {
    handshake = { label = "Dar la mano",        icon = "🤝", gap = 1.0, ms = 3200,
                  me = { "GANGS", "hndshkfa" }, them = { "GANGS", "hndshkfa" }, ame = "le da la mano a %s" },
    gang      = { label = "Saludo de pandilla", icon = "✊", gap = 1.0, ms = 3600,
                  me = { "GANGS", "hndshkca" }, them = { "GANGS", "hndshkca" }, ame = "choca el saludo con %s" },
    kiss      = { label = "Besar",              icon = "💋", gap = 0.85, ms = 4200,
                  me = { "KISSING", "Playa_Kiss_02" }, them = { "KISSING", "Grlfrd_Kiss_02" }, ame = "besa a %s" },
}

-- Comandos de rp_admin que se ofrecen en el bloque de administración (se ejecutan con su
-- propia validación de nivel e IAM, así quedan igual en la auditoría del panel).
INTERACT_ADMIN = {
    { id = "adm_check",  cmd = "check",  label = "Ficha (/check)",     icon = "📋" },
    { id = "adm_recon",  cmd = "recon",  label = "Espectar (/recon)",  icon = "👁️" },
    { id = "adm_goto",   cmd = "goto",   label = "Ir hacia él (/goto)", icon = "➡️" },
    { id = "adm_get",    cmd = "get",    label = "Traerlo (/get)",     icon = "⬅️" },
    { id = "adm_freeze", cmd = "freeze", label = "Congelar / soltar",  icon = "🧊" },
    { id = "adm_heal",   cmd = "heal",   label = "Curar (/heal)",      icon = "❤️" },
}
