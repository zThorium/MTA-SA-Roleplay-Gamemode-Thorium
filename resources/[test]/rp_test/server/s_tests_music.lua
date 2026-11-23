test("musica_config_y_catalogo", function(t)
    local errors = exports.rp_phone:getMusicConfigErrors()
    if type(errors) ~= "table" then
        return t.fail("getMusicConfigErrors no responde")
    end
    if #errors > 0 then
        return t.fail(table.concat(errors, "; "))
    end
    t.pass("catalogo local y configuracion musical validos")
end)

test("musica_proveedor_internet_archive", function(t)
    if type(MUSIC_PROVIDER_CONFIG) ~= "table" then
        return t.fail("MUSIC_PROVIDER_CONFIG no esta disponible")
    end
    if MUSIC_PROVIDER_CONFIG.provider ~= "archive" then
        return t.fail("el proveedor activo no es Internet Archive")
    end
    t.pass("proveedor remoto Internet Archive configurado")
end)
