--[[
    rp_medics / s_admin.lua  (servidor)

    Admin (nivel 1; catálogo en rp_adminpanel/server/s_catalog.lua):
        /medmover <vestuario|garaje|ambulancia>   mueve un punto del hospital a tu posición
                                                   (ambulancia = donde aparece, con tu rumbo)
    Solo en el mundo abierto (interior 0, dimensión 0).
]]

local KIND_OF = { vestuario = "locker", garaje = "garage", ambulancia = "ambulance" }

addCommandHandler("medmover", function(p, _, which)
    if not MD.isAdmin(p, 1) then return end
    local kind = KIND_OF[tostring(which or ""):lower()]
    if not kind then return MD.notify(p, "Uso: /medmover <vestuario|garaje|ambulancia>", "error") end
    if getElementInterior(p) ~= 0 or getElementDimension(p) ~= 0 then return MD.notify(p, "Solo en el mundo abierto.", "error") end
    local x, y, z = getElementPosition(p)
    local _, _, rz = getElementRotation(p)
    dbExec(MD.db(), "REPLACE INTO medic_points (kind, x, y, z, rot) VALUES (?, ?, ?, ?, ?)", kind, x, y, z, rz)
    MD.placePoint(kind, x, y, z, rz)
    MD.notify(p, ("Punto %s movido aquí."):format(which), "success")
    MD.log(("%s movió el punto %s"):format(getPlayerName(p), kind))
end)
