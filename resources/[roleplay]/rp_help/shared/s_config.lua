--[[
    rp_help / s_config.lua
    Todo el contenido del panel F1 se edita aqui (no hace falta tocar el HTML).
    Se carga en cliente y servidor: el cliente lo manda al panel y el servidor
    usa las categorias y limites para validar los reportes.
]]

HELP = {
    KEY = "f1",
    SERVER_NAME = "Thorium Roleplay",
    WELCOME = "Bienvenido. Aqui tienes las reglas, los conceptos de rol, las teclas y un formulario para reportar. Si tienes dudas, pregunta a un administrador.",

    -- Deja la cadena vacia mientras no haya enlace: el boton dira "Proximamente".
    -- Con enlace, el boton lo copia al portapapeles (MTA no puede abrir el navegador del sistema).
    DISCORD_URL = "",

    -- Reportes
    REPORT_COOLDOWN = 120,       -- segundos entre reportes de la misma cuenta
    REPORT_MIN_TEXT = 15,
    REPORT_MAX_TEXT = 600,
    REPORT_ADMIN_LEVEL = 1,      -- nivel minimo de admin que recibe y gestiona reportes
    REPORT_CATEGORIES = {
        { id = "dm",     label = "DeathMatch / VDM" },
        { id = "mg",     label = "MetaGaming" },
        { id = "pg",     label = "PowerGaming" },
        { id = "antirol", label = "Antirol / Fail RP" },
        { id = "insult", label = "Insultos o toxicidad OOC" },
        { id = "cheat",  label = "Hacks, bugs o exploits" },
        { id = "other",  label = "Otro" },
    },
}

-- Reglas generales (OOC). Cada una: titulo corto + explicacion.
HELP.RULES = {
    { title = "Respeto ante todo", text = "No se permiten insultos, discriminacion ni acoso fuera del rol (OOC). Lo que pasa en el rol se queda en el rol." },
    { title = "Nombre de personaje", text = "Usa un nombre realista con formato Nombre_Apellido. No se permiten famosos, apodos ni nombres ofensivos." },
    { title = "Sin hacks ni exploits", text = "Cualquier programa externo, mod que de ventaja o abuso de bugs es motivo de ban. Si encuentras un bug, reportalo." },
    { title = "Rolea siempre", text = "Mientras estes en el servidor tu personaje esta en la ciudad. No salgas del rol para evitar consecuencias (evadir rol)." },
    { title = "Valora tu vida", text = "Actua como si tu personaje tuviera una sola vida: si te apuntan con un arma, coopera. No te enfrentes a situaciones imposibles." },
    { title = "Prohibido DM y VDM", text = "No mates, golpees ni atropelles sin un motivo de rol previo y suficiente." },
    { title = "Prohibido MG y PG", text = "No uses informacion OOC dentro del rol ni fuerces acciones irreales o sin dar opcion al otro jugador." },
    { title = "Zonas seguras", text = "Hospitales, comisarias, bancos y el concesionario son zonas seguras: no se permiten robos ni ataques en ellas." },
    { title = "Chat OOC con moderacion", text = "No hagas spam ni publicidad. Las dudas OOC se preguntan a los administradores." },
    { title = "Decisiones del staff", text = "Respeta las decisiones de los administradores. Si no estas de acuerdo, reclama por Discord, nunca en el juego." },
}

-- Conceptos de rol: sigla, nombre y explicacion con ejemplo.
HELP.CONCEPTS = {
    { tag = "IC",  name = "In Character",   text = "Todo lo que hace y dice tu personaje dentro del rol." },
    { tag = "OOC", name = "Out Of Character", text = "Lo que dices tu como jugador, fuera del rol. No se mezcla con lo IC." },
    { tag = "MG",  name = "MetaGaming",     text = "Usar en el rol informacion que tu personaje no conoce. Ej.: saber el nombre de alguien por su nametag o por Discord." },
    { tag = "PG",  name = "PowerGaming",    text = "Hacer acciones imposibles o forzar el rol sin dar opcion al otro. Ej.: seguir corriendo con un disparo en la pierna." },
    { tag = "DM",  name = "DeathMatch",     text = "Atacar o matar a alguien sin motivo de rol. Siempre debe haber un rol previo." },
    { tag = "VDM", name = "Vehicle DeathMatch", text = "Usar un vehiculo como arma (atropellar o embestir) sin motivo de rol." },
    { tag = "RK",  name = "Revenge Kill",   text = "Volver a vengarte de quien te mato tras reaparecer. Al morir olvidas lo ocurrido en ese rol." },
    { tag = "PK",  name = "Player Kill",    text = "Tu personaje muere en el rol y olvida lo sucedido, pero sigue existiendo." },
    { tag = "CK",  name = "Character Kill", text = "Muerte definitiva del personaje. Requiere autorizacion del staff o del propio jugador." },
    { tag = "FR",  name = "Fear RP",        text = "Temer por la vida de tu personaje: si te superan en numero o te apuntan, actua con miedo." },
    { tag = "ER",  name = "Evadir rol",     text = "Desconectarse, ir AFK o usar comandos para escapar de un rol en curso." },
    { tag = "BH",  name = "Bunny Hop",      text = "Saltar repetidamente para moverte mas rapido. No es realista y esta prohibido." },
    { tag = "CJ",  name = "Car Jacking",    text = "Robar un vehiculo sin rol previo (ej.: sacar al conductor sin motivo)." },
    { tag = "RE",  name = "Rol de entorno",  text = "Tener en cuenta lo que pasa alrededor: testigos, policia, camaras. No actues como si estuvieras solo." },
}

-- Teclas del servidor, agrupadas
HELP.KEYS = {
    { group = "General", items = {
        { key = "F1",  text = "Abrir o cerrar este panel de ayuda" },
        { key = "Tab", text = "Mantener para ver los jugadores conectados" },
        { key = "T",   text = "Hablar por el chat" },
        { key = "I",   text = "Inventario" },
        { key = "P",   text = "Telefono (mensajes, notas, contactos, banco, Fotogram, Tinder, Vroom)" },
        { key = "F11", text = "Mapa: lugares que descubres, clic en un punto para poner ruta GPS y vista 3D (Esc cierra)" },
        { key = "E",   text = "Interactuar: tiendas, restaurantes, cajeros, casas, probadores y concesionario. Junto a una banca, silla o sofa del mapa: sentarse (E otra vez para levantarse)" },
        { key = "F3",  text = "Panel de tu faccion" },
    } },
    { group = "Vehiculos", items = {
        { key = "L",   text = "Abrir o cerrar tu vehiculo" },
        { key = "J",   text = "Encender o apagar el motor (necesitas la llave)" },
        { key = "X",   text = "Freno de mano" },
        { key = "C",   text = "Ponerte o quitarte el cinturon. Sin el, un choque fuerte te lanza por el parabrisas" },
        { key = "\226\134\144 \226\134\146", text = "Intermitentes izquierdo y derecho" },
        { key = "\226\134\147", text = "Balizas" },
        { key = "M",   text = "Muestra el cursor: click derecho sobre un vehiculo abre su menu (maletero, matricula, multas) y sobre una persona, el de interaccion (saludar, dar dinero u objetos, documentos, reanimar, cachear). En Vroom alterna app y mapa" },
        { key = "E / Retroceso", text = "Aceptar o rechazar lo que te propone otra persona (darte la mano, un objeto, subir a su coche, cachearte)" },
    } },
    { group = "Bomberos", items = {
        { key = "E",   text = "En la estacion: vestuario (entrar o salir de servicio) y garaje (autobomba). En una emergencia: cargar a un civil y dejarlo en la zona segura" },
        { key = "Clic izq.", text = "Con el extintor en la mano: apagar el foco al que apuntas" },
        { key = "Clic izq. / Ctrl", text = "En la autobomba: disparar el canon de agua hacia donde mira la camara" },
    } },
    { group = "Staff", items = {
        { key = "F10", text = "Panel de administracion (solo administradores)" },
        { key = "F9", text = "Gestor de recursos (solo super admin)" },
    } },
}

-- Comandos utiles para jugadores
HELP.COMMANDS = {
    { cmd = "/ayuda",          text = "Abre este panel" },
    { cmd = "/reportar",       text = "Abre directamente el formulario de reporte" },
    { cmd = "/id <nombre>",    text = "Busca el ID de un jugador" },
    { cmd = "/bloquear",       text = "Abre o cierra tu vehiculo (igual que L)" },
    { cmd = "/dormir",         text = "Dormir para recuperar energia (solo en interiores)" },
    { cmd = "/accesorios",     text = "Editar los accesorios que llevas puestos" },
    { cmd = "/vroom",          text = "Abrir la app de viajes" },
    { cmd = "/tunear",         text = "Abrir el taller dentro de un taller de tuning (circulo naranja)" },
    { cmd = "/darllave <jugador>", text = "Dar una copia de la llave de tu vehiculo" },
    { cmd = "/cerrarcasa",     text = "Cerrar o abrir tu casa" },
    { cmd = "/vendercasa",     text = "Vender tu casa" },
    { cmd = "/f <texto>",      text = "Chat de tu faccion" },
    { cmd = "/aceptarfaccion", text = "Aceptar una invitacion a una faccion" },
    { cmd = "/salirfaccion",   text = "Salir de tu faccion" },
    { cmd = "/payday",         text = "Ver cuanto falta para tu sueldo" },
    { cmd = "/stats",          text = "Ver tus estadisticas (musculo, resistencia, sex appeal, armas, conduccion...)" },
    { cmd = "/hud",            text = "Mostrar u ocultar el HUD (F7). Opciones: /hud necesidades, mapa, velocimetro, sonidos" },
    { cmd = "/gps",            text = "Cancelar la ruta del GPS (la pones desde el mapa, F11)" },
    { cmd = "/hud tutorial",   text = "Repite la guia del HUD: minimapa, vida, hambre, sed, energia, dinero..." },
    { cmd = "/silenciarnotis", text = "Silenciar el sonido de las notificaciones" },
}

-- Guia para jugadores nuevos: pasos en orden
HELP.GUIDE = {
    { title = "1. Lee las reglas y los conceptos", text = "Son cortos y te ahorran sanciones. Si no entiendes una sigla, la tienes en la pestana Conceptos de rol." },
    { title = "2. Consigue dinero",                text = "Cada 60 minutos de juego cobras un sueldo en el banco (/payday). Si entras a una faccion, cobras el sueldo de tu rol." },
    { title = "3. Usa el banco y los cajeros",     text = "Puedes depositar y transferir desde el telefono (P). Para retirar efectivo ve a un cajero y pulsa E." },
    { title = "4. Compra lo basico",               text = "En las tiendas (E junto al dependiente) hay comida y bebida. Vigila el hambre, la sed y la energia en el HUD." },
    { title = "5. Muevete por la ciudad",          text = "Pide un viaje con Vroom desde el telefono o compra tu propio auto en el concesionario Coutt and Schutz." },
    { title = "6. Busca tu lugar",                 text = "Unete a una faccion, compra una casa (pickup verde) o cambia tu ropa en Binco, SubUrban y demas tiendas." },
    { title = "7. Si algo va mal",                 text = "Usa la pestana Reportar (o /reportar). Un administrador lo vera al momento y queda registrado." },
}

local categoryIndex = {}
for _, c in ipairs(HELP.REPORT_CATEGORIES) do categoryIndex[c.id] = c.label end
function getReportCategoryLabel(id) return categoryIndex[id] end
