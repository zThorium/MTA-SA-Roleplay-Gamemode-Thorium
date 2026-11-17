--[[
    rp_dealership / s_config.lua  (compartido)
    Catalogo, puestos de exhibicion y punto de entrega del concesionario.
    Los puestos se pueden mover en juego con /dealer (admin); los cambios se
    guardan en dealer_spots.json dentro del recurso.
]]

DEALER = {
    NAME = "Coutt and Schutz",
    ROTATION_INTERVAL = 60 * 60000,   -- cada 60 minutos cambian los autos
    MAX_VEHICLES = 3,                 -- vehiculos por personaje
    VIEW_RADIUS = 3.2,
}

-- Puestos de exhibicion y entrega por defecto (lote de Coutt and Schutz, Los Santos).
-- z queda un poco alta a proposito: el vehiculo cae al suelo en vez de atravesarlo.
DEFAULT_SPOTS = {
    display = {
        { 2119.6, -1131.4, 25.6, 0, 0, 270 },
        { 2119.6, -1137.4, 25.6, 0, 0, 270 },
        { 2119.6, -1143.4, 25.6, 0, 0, 270 },
        { 2131.2, -1131.4, 25.6, 0, 0, 90 },
        { 2131.2, -1137.4, 25.6, 0, 0, 90 },
        { 2131.2, -1143.4, 25.6, 0, 0, 90 },
    },
    delivery = { 2125.5, -1122.0, 26.2, 0, 0, 0 },
}

-- model, nombre, precio, categoria
CATALOG = {
    { 400, "Landstalker", 28000, "SUV" },
    { 401, "Bravura", 9000, "Compacto" },
    { 404, "Perennial", 7500, "Familiar" },
    { 405, "Sentinel", 21000, "Sedan" },
    { 410, "Manana", 6500, "Compacto" },
    { 412, "Voodoo", 16000, "Lowrider" },
    { 418, "Moonbeam", 12000, "Furgoneta" },
    { 421, "Washington", 24000, "Sedan" },
    { 426, "Premier", 19000, "Sedan" },
    { 436, "Previon", 8500, "Compacto" },
    { 439, "Stallion", 22000, "Clasico" },
    { 445, "Admiral", 18000, "Sedan" },
    { 458, "Solair", 14000, "Familiar" },
    { 466, "Glendale", 11000, "Sedan" },
    { 467, "Oceanic", 13000, "Clasico" },
    { 474, "Hermes", 17000, "Clasico" },
    { 475, "Sabre", 26000, "Muscle" },
    { 479, "Regina", 10500, "Familiar" },
    { 489, "Rancher", 27000, "SUV" },
    { 491, "Virgo", 12500, "Sedan" },
    { 492, "Greenwood", 11500, "Sedan" },
    { 496, "Blista Compact", 15500, "Compacto" },
    { 507, "Elegant", 23000, "Sedan" },
    { 516, "Nebula", 20000, "Sedan" },
    { 517, "Majestic", 21500, "Clasico" },
    { 518, "Buccaneer", 19500, "Muscle" },
    { 526, "Fortune", 18500, "Coupe" },
    { 527, "Cadrona", 14500, "Coupe" },
    { 529, "Willard", 13500, "Sedan" },
    { 534, "Remington", 30000, "Lowrider" },
    { 535, "Slamvan", 33000, "Lowrider" },
    { 540, "Vincent", 15000, "Sedan" },
    { 542, "Clover", 12000, "Muscle" },
    { 546, "Intruder", 14000, "Sedan" },
    { 547, "Primo", 12500, "Sedan" },
    { 549, "Tampa", 9500, "Muscle" },
    { 550, "Sunrise", 16500, "Sedan" },
    { 551, "Merit", 22500, "Sedan" },
    { 554, "Yosemite", 25000, "Pickup" },
    { 560, "Sultan", 52000, "Deportivo" },
    { 562, "Elegy", 48000, "Deportivo" },
    { 565, "Flash", 26000, "Compacto" },
    { 566, "Tahoma", 17500, "Lowrider" },
    { 567, "Savanna", 29000, "Lowrider" },
    { 575, "Broadway", 24000, "Lowrider" },
    { 576, "Tornado", 21000, "Lowrider" },
    { 579, "Huntley", 45000, "SUV" },
    { 580, "Stafford", 60000, "Lujo" },
    { 585, "Emperor", 19000, "Sedan" },
    { 587, "Euros", 42000, "Deportivo" },
    { 589, "Club", 23000, "Compacto" },
    { 600, "Picador", 10000, "Pickup" },
    { 602, "Alpha", 39000, "Deportivo" },
    { 603, "Phoenix", 55000, "Muscle" },
    { 402, "Buffalo", 65000, "Deportivo" },
    { 411, "Infernus", 180000, "Superdeportivo" },
    { 415, "Cheetah", 150000, "Superdeportivo" },
    { 429, "Banshee", 120000, "Superdeportivo" },
    { 451, "Turismo", 170000, "Superdeportivo" },
    { 461, "PCJ-600", 18000, "Moto" },
    { 462, "Faggio", 3500, "Moto" },
    { 463, "Freeway", 22000, "Moto" },
    { 468, "Sanchez", 12000, "Moto" },
    { 521, "FCR-900", 26000, "Moto" },
}

COLORS = {
    { "Blanco", 245, 245, 245 }, { "Negro", 20, 20, 22 }, { "Gris", 120, 124, 130 }, { "Rojo", 170, 20, 30 },
    { "Azul", 25, 60, 150 }, { "Verde", 30, 110, 60 }, { "Amarillo", 230, 190, 40 }, { "Plata", 190, 194, 200 },
}

function getCatalogEntry(model)
    for _, c in ipairs(CATALOG) do
        if c[1] == model then return { model = c[1], name = c[2], price = c[3], category = c[4] } end
    end
end
