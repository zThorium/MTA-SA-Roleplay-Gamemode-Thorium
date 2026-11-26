--[[
    rp_markers / s_markers.lua  (servidor)

    API para que otros recursos den icono y texto a sus marcadores. El dibujo es solo
    del cliente: aquí únicamente se valida el estilo (MARKERS.sanitizeStyle) y se guarda
    como elementData sincronizado (MARKERS.ELEMENT_DATA) en el propio marcador.

    exports.rp_markers:setMarkerStyle(marker, { icon = "shop", label = "Tienda 24/7" })

    El marcador lo crea SIEMPRE el recurso que lo usa (createMarker normal): así muere con
    él y no depende de que rp_markers se reinicie. Si rp_markers no está, se ve el cilindro nativo.
]]

--- Pone (o quita, con style = nil) el icono/texto/color de un marcador. Devuelve true si se aplicó.
function setMarkerStyle(marker, style)
    if not isElement(marker) or getElementType(marker) ~= "marker" then return false end
    local clean = MARKERS.sanitizeStyle(style)
    if style ~= nil and not clean then
        outputDebugString("[rp_markers] setMarkerStyle: estilo sin campos válidos (icono desconocido?)", 2)
    end
    if clean then
        setElementData(marker, MARKERS.ELEMENT_DATA, clean)
    else
        removeElementData(marker, MARKERS.ELEMENT_DATA)
    end
    return true
end

function getMarkerIcons()
    return MARKERS.ICONS
end

----------------------------------------------------------------
-- /markerdemo: muestra todos los iconos alrededor del admin (solo en su cliente)
----------------------------------------------------------------
addCommandHandler("markerdemo", function(player)
    if (exports.rp_login:getPlayerAdminLevel(player) or 0) < MARKERS.DEMO_ADMIN_LEVEL then
        exports.rp_notify:notify(player, "No tienes permiso para usar este comando.", "error")
        return
    end
    triggerClientEvent(player, "rp:markers:demo", resourceRoot)
end)
