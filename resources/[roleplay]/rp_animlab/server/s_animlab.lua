--[[
    rp_animlab / s_animlab.lua
    Laboratorio de animaciones (admin nivel 2). Comando unico que reenvia la orden al cliente (engineLoadIFP es de cliente):

      /animlab cargar <escena> [p|anpk|orig]    carga anims/<escena>_p.ifp (ANP3), .ifp (ANPK renombrado) o _orig.ifp
      /animlab tocar <escena> <actor> [bucle 0|1] [mover 0|1] [p|anpk|orig]   (por defecto p = ANP3 de peds)
                                                 reproduce la pista del actor (cssweet, csryder, csplay, cssmoke...)
      /animlab ped [skin]                        crea un ped de prueba delante de ti (por defecto la skin de Sweet, 270)
      /animlab objetivo yo|ped                   sobre quien se reproduce
      /animlab segmento <escena> <actor> <inicio_s> <dur_s>   reproduce solo un tramo del clip (biblioteca de gestos)
      /animlab descargar                         suelta animaciones y destruye los IFP (HACERLO ANTES de reiniciar el recurso: crash conocido)
      /animlab parar                             detiene la animacion
]]

addEvent("rp:animlab:result", true)

addCommandHandler("animlab", function(player, _, ...)
    if (exports.rp_login:getPlayerAdminLevel(player) or 0) < 2 then
        return exports.rp_notify:notify(player, "No tienes permiso.", "error")
    end
    local args = { ... }
    if #args == 0 then
        return outputChatBox("Uso: /animlab cargar|tocar|ped|objetivo|parar  (ver cabecera de s_animlab.lua)", player, 255, 200, 80)
    end
    triggerClientEvent(player, "rp:animlab:run", resourceRoot, args)
end)

-- El cliente informa del resultado de engineLoadIFP/setPedAnimation
addEventHandler("rp:animlab:result", resourceRoot, function(text)
    if client then outputChatBox("[animlab] " .. tostring(text):sub(1, 200), client, 120, 220, 255) end
end)
