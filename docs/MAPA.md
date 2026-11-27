# Mapa F11 (`rp_map`)

Mapa propio inspirado en el de GTA VI que sustituye al F11 de GTA. Interfaz CEF (HTML/CSS/JS)
con vista 2D en canvas y vista 3D con Three.js (WebGL), sobre la geografía real de GTA SA.

## Qué ve y hace el jugador

| Pieza | Cómo funciona |
|---|---|
| **Abrir / cerrar** | F11 abre y cierra; Esc o la X cierran. El mapa nativo de GTA no se abre nunca. Mientras está abierto el personaje no se mueve (`guiSetInputEnabled`) y al cerrar recupera los controles. Ocupa **toda la pantalla**: barra superior con buscador y selector 2D/3D, panel lateral, mapa (unas tres cuartas partes de la ventana) y barra inferior. |
| **Música** | Al abrir suena `sounds/map_theme.mp3` («Calm Relax 1» de cynicmusic, ver `CREDITOS.md`) desde el inicio y en bucle; al cerrar se corta y al reabrir empieza de nuevo. Se puede desactivar en Admin › Ajustes. (El tema anterior, de Rockstar, se quitó por derechos de autor.) La radio (`rp_radio`, emisoras de internet y radio de GTA) y la música del teléfono (`rp_phone`: privada, altavoz y vehículo) se silencian mientras el mapa está abierto y vuelven al cerrarlo. |
| **Niebla (fog of war)** | El mapa empieza oscuro. El servidor mira cada 2 s dónde está cada personaje y descubre las celdas de 50 m a menos de 100 m. Lo descubierto no se vuelve a tapar y se guarda por personaje. |
| **Cuadrículas** | 12 × 12 sectores de 500 m (`A1`..`L12`; la letra es la columna de oeste a este y el número la fila de norte a sur), con nombre y territorio sacados de las zonas del juego (`getZoneName`). Estados: desconocida, parcialmente explorada y descubierta (≥ 90 % de su tierra). Al pasar el ratón se ve el estado, el % y los lugares. |
| **Lugares** | Iconos por categoría (19 por defecto). Solo aparecen si su celda está explorada o si el lugar o su categoría son públicos (hospitales, comisarías y aeropuertos). Clic: nombre, descripción, distancia, zona, cuadrícula, coordenadas, botón de **Ruta GPS** (y **Editar lugar** para admins). |
| **Destino** | Clic en cualquier punto del mapa (2D o 3D): se marca el punto y el GPS calcula **al momento** la ruta, que se ve en el minimapa. «Quitar ruta» la cancela. Los jugadores **no** crean marcadores: los iconos los ponen los admins y cada jugador los ve al descubrir su zona. |
| **GPS** | Ruta por las calles reales (A* sobre los nodos de GTA SA). En coche respeta el sentido de las calles; a pie, no. Se recalcula si te desvías más de 45 m o si cambias entre coche y a pie, y avisa al llegar. Sigue con el mapa cerrado: la ruta se dibuja en el minimapa de `rp_hud`, hay un blip de destino y una tarjeta arriba con «Gira a la izquierda en 120 m». `/gps` cancela. |
| **3D** | Relieve aproximado con la textura y la niebla del 2D, unos 4400 edificios con su posición, giro y altura reales, iconos, jugador y ruta. Botón izquierdo para mover, derecho para girar e inclinar y rueda para el zoom. Al hacer clic en un edificio se ve su altura, su modelo y el lugar que hay en él, con botón de GPS. |
| **Buscador** | Lugares, barrios, territorios y cuadrículas, **solo si ya los conoces** (barrios y ciudades con alguna celda explorada). |
| **Progreso** | % total, cuadrículas descubiertas, a medias y desconocidas, celdas, lugares descubiertos y pendientes, barra por territorio y lista de cuadrículas. |
| **Tutorial** | Solo la **primera vez** que se abre el mapa: entrenador de 6 pasos con el gesto dibujado (arrastrar, rueda, clic, niebla, 3D, pestañas). Se marca como visto al mostrarse (preferencias del personaje y `@map_tutorial.xml` del PC), aunque se salte o se cierre a medias. |

## Cómo se protege la información

- El servidor es el **único** que descubre celdas: lee la posición del jugador; el cliente no puede marcar nada.
- A más de 80 km/h el radio se encoge (hasta un 30 %), en avión o helicóptero el radio es la mitad y un salto de más de 600 m (teletransporte) no descubre el camino entre los dos puntos.
- Al cliente solo le llegan los lugares que puede ver. Para «lugares pendientes» recibe cuántos hay, no dónde están.
- El buscador solo busca en lo que el cliente ya tiene.
- Todos los eventos de admin vuelven a comprobar `admin_level ≥ 1` y validan tipos, rangos, longitudes, colores e iconos en el servidor.

## Datos reales de GTA SA (`tools/generar-datos.ps1`)

Se generan desde la instalación local de GTA SA (la ruta se lee del registro de MTA o se pasa con `-Gta`):

| Archivo | Origen | ¿En el repo? |
|---|---|---|
| `html/data/map.jpg` | 144 tiles del radar (`gta3.img`, mismo lector que `rp_hud/tools/RadarExtract.cs`), 3072 px | Sí (subido a petición del dueño del repo) |
| `html/data/roads.js`, `client/c_roads.lua` | `data/Paths/NODES0-63.DAT`: 28 991 nodos de calle y 29 810 tramos, 11 524 de ellos de un solo sentido (calzadas separadas). El sentido sale de los carriles de los navi nodes; el script elige solo la convención comprobando que en las autovías la calzada contraria quede a la izquierda (13 478 casos frente a 1988) | Sí (datos derivados, como `rp_citizens/c_nodes_veh.lua`) |
| `html/data/buildings.js` | IDE + IPL de texto + IPL binarios de `gta3.img` + caja de colisión de cada modelo (`.col`). Se descartan los LOD, el terreno, las carreteras, la vegetación y las piezas inclinadas | Sí |
| `html/data/terrain.js`, `shared/s_land.lua` | Relieve por vértice de 50 m (media de la altura de calles y edificios) y máscara de tierra y agua del radar | Sí |

Calibración: mundo `-3000..3000` en los dos ejes, con la `y` hacia el norte. Píxel del radar: `u = (x + 3000) / 6000 · ancho`, `v = (3000 − y) / 6000 · alto`. Se comprobó superponiendo calles y edificios generados sobre el radar.

## Base de datos

`map_exploration` (celdas en hexadecimal, 3600 caracteres por personaje, y el número de celdas de tierra), `map_markers` (sin uso desde que los jugadores no crean marcadores; se conserva porque el esquema solo avanza), `map_prefs` (JSON validado), `map_categories`, `map_places` (con `seed_key`), `map_sectors` (nombre, territorio y si es visible desde el inicio) y `map_settings`. La exploración se guarda cada 60 s si cambió, y también al cambiar de personaje, al salir y al parar el recurso.

Las categorías y los lugares conocidos de GTA SA (`server/s_seed.lua`: hospitales, comisarías, aeropuertos, estaciones, gimnasios, bares, discotecas, concesionarios, talleres, Ammu-Nation y lugares especiales) se siembran **una sola vez**. Si un admin borra uno, no vuelve a aparecer.

Lugares importados en vivo, cada 30 s y sin guardarse: los blips de otros recursos con un icono conocido (`MAPA.BLIP_CATEGORIES`: tiendas con su nombre de `rp:shopName`, 24/7, restaurantes, bencineras, talleres, concesionario, trabajos, bicicletas, policía y emergencias), los cajeros (`rp:atm`) y las casas de `rp_properties` (`rp:property`, como casa o apartamento según el tipo, con dueño o precio).

## Configuración (`shared/s_config.lua`)

Valores por defecto del radio, el intervalo, el factor de velocidad, el avión, el teletransporte, el guardado, el % para dar una cuadrícula por descubierta, las zonas de inicio (`START_ZONES`), el GPS y la música, además de las categorías iniciales, los iconos y la relación entre blips y categorías. En caliente, desde la pestaña Admin, se cambian el radio, el intervalo, la niebla, el GPS, el 3D, la música, la importación de blips y las casas (`map_settings`).

## Administración

Pestaña **Admin** del mapa (solo `admin_level ≥ 1`):

- **Lugares**: son los únicos iconos del mapa; los jugadores los ven al descubrir su zona. Crear, editar o borrar con nombre, descripción, categoría, coordenadas («Mi posición» o «Elegir en mapa») y la opción de verse desde el inicio.
- **Categorías**: crear o editar la clave, el nombre, el color, el icono (24 disponibles) y si es pública. No se borra una categoría que esté en uso.
- **Cuadrículas**: nombre, territorio y si es visible para todos desde el inicio.
- **Ajustes**: los descritos arriba.
- **Jugadores**: consultar el progreso por id o nombre de jugador o por id de personaje, y reiniciar la exploración.

Comandos: `/mapaprogreso <jugador|id personaje>`, `/resetmapa <jugador|id personaje>` y `/mapajugador`.

**Dos vistas** para admins: por defecto ven el mapa entero con **todos** los lugares (vista Admin). `/mapajugador`, o el botón «Vista» de la barra superior, cambia a la vista de un jugador normal: niebla e iconos según lo que su personaje ha descubierto. Al cambiar de nuevo se vuelve a la vista Admin. Desde la tarjeta de un punto, el admin tiene **Crear lugar aquí**, y desde la de un lugar, **Editar lugar**.

## Integración

- `rp_hud:setNavRoute(puntos)` (cliente): dibuja la ruta en el minimapa. El blip 41 de destino ya lo trata `rp_hud` como siempre visible.
- `rp_hud:setHudHidden("rp_map", ...)` oculta el HUD mientras el mapa está abierto.
- `rp_radio:setRadioSuppressed("rp_map", ...)` y `rp_phone:setMusicSuppressed("rp_map", ...)` (export nuevo) silencian la música.
- Exports de servidor: `getPlayerExplorationPercent(player)`, `revealPlayerArea(player, x, y, r)` (para misiones y eventos) y `getMapStats()`.

## Limitaciones conocidas

- GTA SA no tiene **nombres de calles**: el buscador encuentra barrios (zonas del juego), territorios, cuadrículas y lugares.
- Los edificios 3D son **cajas** con la huella, el giro y la altura de su colisión real, no el modelo del juego: CEF no puede leer los DFF. Los edificios muy pequeños, las piezas inclinadas y el terreno se descartan.
- El relieve 3D es aproximado: 50 m por vértice, con la altura de calles y edificios; las montañas sin caminos quedan suavizadas.
- Los tramos de la ruta que van del jugador a la calle más cercana y de la calle al destino son rectos, porque fuera de la red no hay calle. Lo demás sigue las calles.
- El GPS usa la red vial; a pie no usa las aceras ni los atajos peatonales.

## Probar

- Servidor: `scripts/test.sh` (`s_tests_map.lua`: recurso cargado, siembra, 144 sectores, tablas y exploración en hexadecimal de ida y vuelta).
- Interfaz sin el juego: abrir `html/index.html#demo` (o `#demo3d`, `#demotuto`) en un navegador con `--allow-file-access-from-files`.
- En el juego: F11 y Esc para abrir y cerrar (pantalla completa, el personaje no se mueve y suena el tema desde el inicio); radio o música del teléfono sonando al abrir (deben callarse y volver al cerrar); caminar y conducir rápido (la niebla se abre menos a toda velocidad); clic en un punto (la ruta sale en el minimapa al instante); el tutorial no vuelve a salir al reabrir; poner un GPS, cerrar el mapa, desviarse y llegar; 3D (girar, inclinar, clic en un edificio); buscador; pestaña Admin con una cuenta de nivel 0 (no debe salir) y con una de nivel 1; reconectar y comprobar que el progreso sigue ahí.
