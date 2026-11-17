--[[
    rp_adminpanel / s_catalog.lua

    Catalogo de comandos de administracion que muestra el panel.
    Vive solo en el servidor: el cliente lo recibe unicamente si es admin.

    IMPORTANTE: al crear un comando de admin nuevo en cualquier recurso,
    anadelo aqui para que aparezca en el panel.

    Campos: cmd = "/comando", args = argumentos, desc = que hace, res = recurso.
]]

ADMIN_CATALOG = {
    {
        id = "herramientas", name = "Herramientas",
        items = {
            { cmd = "/adminpanel", args = "", alt = "/apanel, F10", desc = "Abre este panel con todos los comandos de administracion.", res = "rp_adminpanel" },
            { cmd = "/freecam", args = "", desc = "Camara libre (WASD, Espacio/Ctrl suben y bajan, Shift rapido, Alt lento). El personaje queda congelado.", res = "rp_admin" },
            { cmd = "/nodos", args = "", desc = "Editor de la red vial y peatonal de los ciudadanos IA (mover, crear y enlazar nodos).", res = "rp_citizens" },
        },
    },
    {
        id = "jugadores", name = "Jugadores",
        items = {
            { cmd = "/revivir", args = "[id o nombre]", desc = "Reanima a un jugador abatido y le devuelve la vida.", res = "rp_injury" },
            { cmd = "/abatir", args = "<id o nombre>", desc = "Deja abatido a un jugador (empieza la cuenta atras de 2 minutos).", res = "rp_injury" },
            { cmd = "/cancelar911", args = "<id o nombre>", desc = "Cancela la emergencia 911 activa de un jugador.", res = "rp_emergency" },
            { cmd = "/forzarpayday", args = "[id o nombre]", desc = "Paga el sueldo (payday) al instante a un jugador; sin argumento, a ti.", res = "rp_payday" },
        },
    },
    {
        id = "economia", name = "Economia",
        items = {
            { cmd = "/dardinero", args = "<id o nombre> <cantidad>", desc = "Ingresa dinero en la cuenta bancaria del personaje (cantidad negativa para restar).", res = "rp_bank" },
            { cmd = "/darfondos", args = "<idFaccion> <cantidad>", desc = "Suma o resta fondos de la caja de una faccion (negativa para quitar).", res = "rp_factions" },
            { cmd = "/crearatm", args = "", desc = "Coloca un cajero automatico 1 m delante de ti, en tu interior y dimension.", res = "rp_bank" },
            { cmd = "/borraratm", args = "<id>", desc = "Elimina un cajero automatico.", res = "rp_bank" },
        },
    },
    {
        id = "facciones", name = "Facciones",
        items = {
            { cmd = "/crearfaccion", args = "<tipo> <siglas 2-8> <nombre>", desc = "Crea una faccion con los roles por defecto. Sin argumentos lista los tipos disponibles.", res = "rp_factions" },
            { cmd = "/borrarfaccion", args = "<id>", desc = "Disuelve una faccion; sus miembros en linea son avisados.", res = "rp_factions" },
            { cmd = "/setlider", args = "<id o nombre> <idFaccion>", desc = "Asigna a un jugador como lider (rol mas alto) de una faccion.", res = "rp_factions" },
            { cmd = "/facciones", args = "", desc = "Lista en el chat todas las facciones con id, tipo, fondos y miembros en linea.", res = "rp_factions" },
        },
    },
    {
        id = "mundo", name = "Mundo y propiedades",
        items = {
            { cmd = "/crearshop", args = "<nombre>", desc = "Crea una tienda con NPC en tu posicion.", res = "rp_shops" },
            { cmd = "/borrarshop", args = "<id>", desc = "Elimina una tienda.", res = "rp_shops" },
            { cmd = "/crearcasa", args = "<tipo> <precio> <nombre>", desc = "Crea una propiedad en venta frente a la puerta (solo en exteriores). Tipos con /tiposcasa.", res = "rp_properties" },
            { cmd = "/borrarcasa", args = "<id>", desc = "Elimina una propiedad.", res = "rp_properties" },
            { cmd = "/crearropa", args = "<tipo> <nombre>", desc = "Crea una tienda de ropa (Binco, SubUrban, ProLaps, ZIP, Victim, Didier Sachs). Sin argumentos lista los tipos.", res = "rp_clothing" },
            { cmd = "/ropapunto", args = "<id> entrada|interior", desc = "Mueve a tu posicion el punto de entrada o el interior de una tienda de ropa.", res = "rp_clothing" },
            { cmd = "/borrarropa", args = "<id>", desc = "Elimina una tienda de ropa.", res = "rp_clothing" },
            { cmd = "/tiendasropa", args = "", desc = "Lista en el chat las tiendas de ropa con id, tipo y coordenadas.", res = "rp_clothing" },
            { cmd = "/dealer puesto", args = "<n>", desc = "Guarda tu posicion (o la de tu auto) como puesto de exhibicion n del concesionario.", res = "rp_dealership" },
            { cmd = "/dealer entrega", args = "", desc = "Guarda tu posicion como punto de entrega de los autos comprados.", res = "rp_dealership" },
            { cmd = "/dealer rotar", args = "", desc = "Renueva al instante los autos del concesionario.", res = "rp_dealership" },
        },
    },
}
