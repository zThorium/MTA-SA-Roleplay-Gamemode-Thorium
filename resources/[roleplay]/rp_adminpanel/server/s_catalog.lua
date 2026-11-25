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
            { cmd = "/freecam", args = "", desc = "Camara libre, solo super admin (WASD, Espacio/Ctrl, Shift rapido, Alt lento, rueda = velocidad, F = teletransportar al punto de la camara). El personaje queda congelado.", res = "rp_admin" },
            { cmd = "/nodos", args = "", desc = "Editor de la red vial y peatonal de los ciudadanos IA (mover, crear y enlazar nodos).", res = "rp_citizens" },
        },
    },
    {
        id = "jugadores", name = "Jugadores",
        items = {
            { cmd = "/revivir", args = "[id o nombre]", desc = "Reanima a un jugador abatido y le devuelve la vida.", res = "rp_injury" },
            { cmd = "/abatir", args = "<id o nombre>", desc = "Deja abatido a un jugador (empieza la cuenta atras de 2 minutos).", res = "rp_injury" },
            { cmd = "/cancelar911", args = "<id o nombre>", desc = "Cancela la emergencia 911 activa de un jugador.", res = "rp_emergency" },
            { cmd = "/borrarpost", args = "<id>", desc = "Borra una foto de Fotogram (con sus likes, comentarios y avisos). El id sale en la base de datos (social_posts).", res = "rp_phone" },
            { cmd = "/darlicencia", args = "<id o nombre>", desc = "Entrega o rehabilita la licencia de conducir sin hacer las pruebas.", res = "rp_driving" },
            { cmd = "/forzarpayday", args = "[id o nombre]", desc = "Paga el sueldo (payday) al instante a un jugador; sin argumento, a ti.", res = "rp_payday" },
            { cmd = "/pmlog", args = "<id o nombre> [cantidad]", desc = "Historial de PMs (OOC) enviados o recibidos por un personaje, para revisar MG.", res = "rp_chat" },
            { cmd = "/darxp", args = "<id o nombre> <cantidad>", desc = "Da XP (RP) a un jugador; si llega al siguiente nivel, sube con la animacion.", res = "rp_levels" },
        },
    },
    {
        id = "economia", name = "Economia",
        items = {
            { cmd = "/dardinero", args = "<id o nombre> <cantidad>", desc = "Ingresa dinero en la cuenta bancaria del personaje (cantidad negativa para restar).", res = "rp_bank" },
            { cmd = "/darfondos", args = "<idFaccion> <cantidad>", desc = "Suma o resta fondos de la caja de una faccion (negativa para quitar).", res = "rp_factions" },
            { cmd = "/setjob", args = "<id o nombre> <trabajo|ninguno>", desc = "Asigna un trabajo civil (garbage, farmer, lumber, hunter, fisher, miner) o lo quita, sin espera entre cambios.", res = "rp_jobs" },
            { cmd = "/darxptrabajo", args = "<id o nombre> <xp>", desc = "Suma experiencia al jugador en su trabajo actual (sube de nivel y de pago).", res = "rp_jobs" },
            { cmd = "/crearatm", args = "", desc = "Coloca un cajero automatico 1 m delante de ti, en tu interior y dimension.", res = "rp_bank" },
            { cmd = "/borraratm", args = "<id>", desc = "Elimina un cajero automatico.", res = "rp_bank" },
            { cmd = "/crearexpendedora", args = "<bebida|comida>", desc = "Coloca una maquina expendedora delante de ti, mirandote: bebida (Sprunk) o comida (snacks). Vende productos que van al inventario.", res = "rp_vending" },
            { cmd = "/borrarexpendedora", args = "[id]", desc = "Elimina una expendedora. Sin id, borra la mas cercana (a menos de 5 m).", res = "rp_vending" },
            { cmd = "/nearbyexpendedoras", args = "[radio]", desc = "Lista en el chat las expendedoras cercanas (por defecto 50 m) con id, tipo y distancia.", res = "rp_vending" },
            { cmd = "/expendedoras", args = "", desc = "Lista las expendedoras con id, tipo y posicion.", res = "rp_vending" },
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
            { cmd = "/agenciacola", args = "", desc = "Muestra en el chat la cola de la agencia de empleo y el estado de cada mostrador.", res = "rp_agency" },
            { cmd = "/agenciareset", args = "", desc = "Vacia la cola de turnos de la agencia y libera los mostradores.", res = "rp_agency" },
            { cmd = "/crearshop", args = "<nombre>", desc = "Crea una tienda con NPC en tu posicion.", res = "rp_shops" },
            { cmd = "/creartraficante", args = "[28|29|30]", desc = "Crea un traficante de drogas (marihuana, cocaina, LSD) en tu posicion.", res = "rp_dealers" },
            { cmd = "/borrartraficante", args = "<id>", desc = "Elimina un traficante.", res = "rp_dealers" },
            { cmd = "/traficantes", args = "", desc = "Lista los traficantes con id y posicion.", res = "rp_dealers" },
            { cmd = "/crearrobo", args = "<tipo> <nombre>", desc = "Crea una tienda 24/7 robable. Parate en la puerta mirando a la calle (ahi esperan las patrullas).", res = "rp_robbery" },
            { cmd = "/borrarrobo", args = "<id>", desc = "Elimina una tienda robable.", res = "rp_robbery" },
            { cmd = "/robos", args = "", desc = "Lista las tiendas robables y si estan disponibles, vacias o con un robo en curso.", res = "rp_robbery" },
            { cmd = "/tiposrobo", args = "", desc = "Tipos de interior 24/7 para /crearrobo.", res = "rp_robbery" },
            { cmd = "/robopunto", args = "<id> puerta|salida|cajero|caja|cliente|clientes", desc = "Corrige un punto de la tienda parado en el sitio (cajero mirando a los clientes; cliente anade un sitio, clientes los borra).", res = "rp_robbery" },
            { cmd = "/resetrobo", args = "<id>", desc = "Termina el robo en curso, quita la espera y repone cajero y clientes.", res = "rp_robbery" },
            { cmd = "/borrarshop", args = "<id>", desc = "Elimina una tienda.", res = "rp_shops" },
            { cmd = "/crearmesapool", args = "", desc = "Coloca una mesa de pool 2 m delante de ti, en tu interior y dimension (las de Ten Green Bottles ya vienen sembradas).", res = "rp_pool" },
            { cmd = "/borrarmesapool", args = "<id>", desc = "Elimina una mesa de pool; si hay partida en curso se devuelven las apuestas.", res = "rp_pool" },
            { cmd = "/mmover", args = "<sweet|ryder|cesar>", desc = "Mueve a tu posicion el punto de inicio de misiones de un contacto (admin nivel 2).", res = "rp_missions" },
            { cmd = "/mocap", args = "<personaje> <gesture|idle> [n]  |  lista", desc = "Reproduce en ti un clip de la biblioteca de mocap (solo lo ves tu). /mocap lista muestra personajes y clips.", res = "rp_mocap" },
            { cmd = "/mocapped", args = "<personaje>", desc = "Crea un ped de prueba con la skin del personaje que alterna idle y gestos de mocap; otra vez lo quita.", res = "rp_mocap" },
            { cmd = "/mocapparar", args = "", desc = "Quita la animacion de mocap que tengas puesta.", res = "rp_mocap" },
            { cmd = "/animlab", args = "cargar|tocar|segmento|ped|objetivo|parar|descargar", desc = "Laboratorio de mocap de cinematicas (recurso rp_animlab): prueba tramos de cuts.img. /animlab descargar antes de reiniciar el recurso.", res = "rp_animlab" },
            { cmd = "/mskip", args = "", desc = "Salta la etapa actual de tu mision en curso (para pruebas).", res = "rp_missions" },
            { cmd = "/mesaspool", args = "", desc = "Lista en el chat las mesas de pool con id, posicion y estado.", res = "rp_pool" },
            { cmd = "/crearcasa", args = "<tipo> <precio> <nombre>", desc = "Crea una propiedad en venta frente a la puerta (solo en exteriores). Tipos con /tiposcasa.", res = "rp_properties" },
            { cmd = "/borrarcasa", args = "<id>", desc = "Elimina una propiedad.", res = "rp_properties" },
            { cmd = "/muebleinfo", args = "", desc = "Muestra muebles, capacidad, residentes y sesion de decoracion de la casa en la que estas.", res = "rp_furniture" },
            { cmd = "/limpiarmuebles", args = "<idCasa>", desc = "Devuelve todos los muebles de una casa a la bodega del dueno (nivel 3).", res = "rp_furniture" },
            { cmd = "/crearropa", args = "<tipo> <nombre>", desc = "Crea una tienda de ropa (Binco, SubUrban, ProLaps, ZIP, Victim, Didier Sachs). Sin argumentos lista los tipos.", res = "rp_clothing" },
            { cmd = "/ropapunto", args = "<id> entrada|interior", desc = "Mueve a tu posicion el punto de entrada o el interior de una tienda de ropa.", res = "rp_clothing" },
            { cmd = "/borrarropa", args = "<id>", desc = "Elimina una tienda de ropa.", res = "rp_clothing" },
            { cmd = "/tiendasropa", args = "", desc = "Lista en el chat las tiendas de ropa con id, tipo y coordenadas.", res = "rp_clothing" },
            { cmd = "/dealer puesto", args = "<n>", desc = "Guarda tu posicion (o la de tu auto) como puesto de exhibicion n del concesionario.", res = "rp_dealership" },
            { cmd = "/dealer entrega", args = "", desc = "Guarda tu posicion como punto de entrega de los autos comprados.", res = "rp_dealership" },
            { cmd = "/dealer rotar", args = "", desc = "Renueva al instante los autos del concesionario.", res = "rp_dealership" },
            { cmd = "/crearautoescuela", args = "", desc = "Crea una autoescuela con el instructor en tu posicion y rumbo.", res = "rp_driving" },
            { cmd = "/borrarautoescuela", args = "<id>", desc = "Elimina una autoescuela.", res = "rp_driving" },
            { cmd = "/arenaautoescuela", args = "<id>", desc = "Fija la pista de pruebas en tu posicion y rumbo (terreno plano, ~200 m libres hacia delante y 30 m a los lados).", res = "rp_driving" },
            { cmd = "/autoescuelas", args = "", desc = "Lista las autoescuelas con su instructor y su pista.", res = "rp_driving" },
            { cmd = "/evento", args = "[id]", desc = "Crea un evento dinamico (accidente, emergencia medica, control policial, obras, auto en llamas, mercadillo, fiesta) junto a ti. Sin id lista los disponibles.", res = "rp_events" },
            { cmd = "/eventos", args = "", desc = "Lista los eventos dinamicos activos con distancia, tiempo restante y barrio.", res = "rp_events" },
            { cmd = "/eventoslista", args = "", desc = "Catalogo de eventos con peso, horario, cooldown y coste de presupuesto.", res = "rp_events" },
            { cmd = "/terminarevento", args = "<n|todos>", desc = "Termina un evento activo (o todos) y limpia sus elementos.", res = "rp_events" },
            { cmd = "/eventosintensidad", args = "[0-3]", desc = "Intensidad del mundo vivo: 0 apagado (sin eventos ni escenas), 1 tranquilo, 2 normal, 3 movido.", res = "rp_events" },
            { cmd = "/eventosinfo", args = "", desc = "Presupuesto de drama, elementos en uso e intensidad del director de eventos.", res = "rp_events" },
            { cmd = "/clima", args = "[nombre]", desc = "Cambia el clima compartido (sun, smog, cloudy, rain, storm, fog). Sin nombre muestra el actual.", res = "rp_events" },
            { cmd = "/hora", args = "<0-23> [minutos]", desc = "Cambia la hora de juego (el reloj sigue avanzando desde ahi).", res = "rp_events" },
            { cmd = "/mercadoajuste", args = "<dz> <rotacion>", desc = "Calibra los puestos del mercadillo: metros que se suben (por si quedan enterrados) y rotacion extra 0/90/180/270 para que miren a la calle. Luego crea otro con /evento market.", res = "rp_events" },
        },
    },
    {
        id = "gimnasio", name = "Gimnasio",
        items = {
            { cmd = "/crearmaquina", args = "<cinta|bici|banca|mancuernas> [gimnasio]", desc = "Crea una maquina de gimnasio en tu posicion y rumbo (el personaje quedara donde estas).", res = "rp_gym" },
            { cmd = "/borrarmaquina", args = "<id>", desc = "Elimina una maquina de gimnasio.", res = "rp_gym" },
            { cmd = "/maquinas", args = "", desc = "Lista las maquinas de gimnasio con id y posicion.", res = "rp_gym" },
            { cmd = "/crearentrenador", args = "<boxeo|kungfu|kickboxing>", desc = "Crea un entrenador de estilo de combate en tu posicion y rumbo.", res = "rp_gym" },
            { cmd = "/borrarentrenador", args = "<id>", desc = "Elimina un entrenador de combate.", res = "rp_gym" },
            { cmd = "/entrenadores", args = "", desc = "Lista los entrenadores de combate con id y posicion.", res = "rp_gym" },
        },
    },
}
