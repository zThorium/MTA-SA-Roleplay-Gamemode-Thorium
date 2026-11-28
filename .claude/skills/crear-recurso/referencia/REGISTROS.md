# Registros: lo que ya está ocupado

Antes de elegir una dimensión, tecla, elementData o blip, compruébalo aquí. Al ocupar uno nuevo,
**añádelo en el mismo PR**. Para verificar contra el código actual:

```bash
grep -rnoiE '(dim|dimension)[A-Z_]* *= *[0-9]{2,}' --include=*.lua "resources/[roleplay]"
grep -rnE 'bindKey\(\s*"<tecla>"' --include=*.lua "resources/[roleplay]"
grep -rhoE 'setElementData\([^,]+, *"rp:[^"]+"' --include=*.lua "resources/[roleplay]" | sort -u
```

## Dimensiones

| Rango | Recurso | Uso |
|---|---|---|
| 0 | — | mundo abierto |
| 1000-1199 | `rp_missions` | instancias de misión (`DIM_BASE + n`, `DIM_COUNT = 200`) |
| 4000+ | `rp_races` | una por carrera |
| 10000 + id | `rp_properties` / `rp_furniture` | interior de cada casa |
| 20000 + id | `rp_clothing` | tiendas de ropa |
| 21000 + id | `rp_robbery` | tiendas 24/7 |
| 21000 + slot | `rp_driving` | pistas de autoescuela ⚠️ **choca con `rp_robbery`** (pendiente de mover) |
| 22000 + id | `rp_ammunation` | armerías |
| 23000 + n | `rp_shootingrange` | una por jugador dentro del campo de tiro (`DIM_BASE + 1..500`) |
| 25000 + id | `rp_restaurants` | Burger Shot, Cluckin' Bell y pizzerías |
| 26000 + slot | `rp_pizzeria` | una por turno de pizzero (`DIM_BASE + 1..500`, interior 5) |
| 27000 + id | `rp_mapeditor` | borrador de cada proyecto de mapa (`DIMENSION_BASE + id`); la dimensión de publicación la elige el builder |
| 30001 | `rp_agency` | agencia de empleo |
| 65000 | `rp_pickupfx` | solo en el cliente: aparca los pickups originales mientras se ve su copia animada |

Para un recurso nuevo usa un bloque de 1000 libre (por ejemplo `24000 + id`, `27000 + n`...) en
`DIMENSION_BASE` de su config, y escríbelo aquí. Comprueba siempre **interior + dimensión + distancia**.

## Teclas

| Tecla | Uso |
|---|---|
| **E** | interacción universal (15 recursos: tiendas, cajeros, puertas, máquinas, trabajos...). Solo actúa junto a tu punto |
| G | muebles con función (`rp_furniture`) |
| H | interactuar con peatones (`rp_npcrel`), amenazar en robos (`rp_robbery`); bocina de GTA al volante (control `horn`: `rp_cartheft` cuenta dos bocinazos para apagar la alarma) |
| I | inventario |
| O | menú radial de animaciones (`rp_anims`, mantener), mochila (`rp_backpacks`), sirena (`rp_police`, en patrulla) ⚠️ saturada |
| C | cinturón de seguridad, solo dentro de un coche (`rp_seatbelt`) |
| J | motor del vehículo (`rp_vehicles`, rebindeable); sin llave en un auto forzado abre el puente de `rp_cartheft` (evento `rp:veh:onEngineNoKey`) |
| K | cursor de interacción policial (`rp_police`) |
| L / X / flechas | cerrar, freno de mano, intermitentes (`rp_vehicles`, rebindeables en Ajustes > Binds) |
| M | cursor (`rp_vehicles`): clic derecho en un vehículo = menú de vehículo, en una persona = menú de `rp_interact`; mapa/app en Vroom (`rp_rides`) |
| P | teléfono |
| R | radio del vehículo |
| T / Y / U / B | chat: decir, susurrar, gritar, OOC (`rp_chat`) |
| Y / N | aceptar / rechazar invitaciones (`rp_missions`, `rp_races`, `rp_citizens`). ⚠️ Y también abre el chat de susurro (`rp_chat`) |
| E / Retroceso | aceptar / rechazar propuestas de otra persona (`rp_interact`), solo mientras hay una en pantalla |
| Espacio, Retroceso, flechas, A/D | controles contextuales de minijuegos (`rp_gym`, `rp_driving`, `rp_races`) solo mientras estás en ellos |
| ALT (mantener) | vista de admin (`rp_admin`, solo nivel 1+): etiquetas con ID, dueño y creador sobre lo cercano |
| F1 | ayuda · F3 facciones · F4 decorar · F5 carreras · F6 MDT policial · F7 mostrar/ocultar HUD (`rp_hud`) · F9 recursos · F10 panel admin |
| F11 | mapa propio (`rp_map`, sustituye al de GTA; Esc lo cierra) |
| F12 / Tab / T | reservadas por MTA/GTA (captura, lista, chat) |

F2 la usa `rp_shootingrange` (abandonar entrenamiento, solo mientras entrenas). Libre hoy: ninguna tecla F fiable (F8 es la consola de MTA: no usar). Muchas letras ya se usan
dentro de minijuegos (Z, 1-4, Enter...), así que antes de usar una compruébala con el `grep` de arriba.
Casi siempre es mejor **E contextual** + comando. Si el sistema se usa poco, prefiere un comando o un elemento en el
teléfono antes que gastar una tecla global.

## elementData `rp:*` en uso

Sincronizado (visible en todos los clientes) solo si los clientes lo necesitan; si no, guárdalo en una
tabla Lua del servidor. Prefijo `rp:` siempre.

- Jugador / sesión: `rp:accountId`, `rp:characterId`, `rp:loaded`, `rp:body`, `rp:head`, `rp:needs`,
  `rp:hudHidden` (no lo toques: usa `setHudSuppressed`), `rp:downed`, `rp:carried`, `rp:cuffed`, `rp:tased`,
  `rp:faction`, `rp:policeDuty`, `rp:job`, `rp:jobShift`, `rp:race`, `rp:drivingTest`, `rp:packWeight`,
  `rp:meth`, `rp:respect`, `rp:fireDuty`, `rp:factionDuty` (rp_duty), `rp:wanted`, `rp:wantedHeld`, `rp:wantedLost`, `rp:wantedNoTires`.
- Vehículos: `rp:carAlarm` (`rp_cartheft`, alarma sonando), `rp:vehicleId`, `rp:vehicleOwner`, `rp:indicator`, `rp:copCar`, `rp:fireTruck`, `rp:perf`, `rp:radio`, `rp:rides:ai`,
  trenes (`rp_train`): `rp:train`, `rp:train:wagon`, `rp:train:of`, `rp:train:idx`, `rp:train:v`, `rp:train:passenger`, `rp:train:dwell`, `rp:train:horn`.
- Jugador en el tren: `rp:train:rider` (`rp_train`, viaja como pasajero). Root del recurso: `rp:train:eta` (`rp_train`).
- Objeto en la mano (no arma): `rp:heldItem` en el jugador = id del item (lo pone el recurso que lo maneja; `rp_inventory` lo marca con ✓ y su botón dice «Guardar»). Hoy: `rp_metaldetector` (`metal_detector_<n>`); al quitarlo, borra solo si el valor es tuyo.
- Detector de metales (`rp_metaldetector`): `rp:mdShop` en el ped vendedor.
- Logros (`rp_achievements`): `rp:achBadge` en `localPlayer`, **solo local** (`setElementData(..., false)`): globo de la ficha «Logros» del HUD (número de novedades o `"!"` si nunca abrió los logros); lo lee `rp_hud/c_iconbar.lua`.
- Peds / objetos: `rp:citizen`, `rp:cop`, `rp:dealer`, `rp:shopId`, `rp:shopName`, `rp:robberyPed`,
- Objetos: `rp:text3d` (texto de `rp_3dtext`, icono 1239).
- Pickups: `rp:pickupUsed` (recogido y esperando reaparecer; `rp_pickupfx` no lo hace brillar).
- Marcadores: `rp:marker` (estilo de `rp_markers`; ponlo solo con `setMarkerStyle`).
  `rp:robberyStore`, `rp:fireVictim`, `rp:restaurantClerk`, `rp:emergency`, `rp:npcrel`, `rp:furn`, `rp:eventProp`, `rp:toy`, `rp:property`.
- Root: `rp:world` (hora y clima), `rp:events`.
- Blips: `rp:radarEdge` (el blip se queda en el borde del minimapa).

## Blips del minimapa (`rp_hud`)

`rp_hud` **solo dibuja** los iconos listados en `KNOWN_BLIP_ICON_IDS` (`rp_hud/c_hud.lua`); el resto
no aparece. Iconos con PNG propio en `rp_hud/images/blips/`:

| Icono | Uso actual |
|---|---|
| 10 | Burger Shot (`rp_restaurants`) |
| 14 | Cluckin' Bell (`rp_restaurants`) |
| 17 | tiendas 24/7 (`rp_robbery`) |
| 22 | emergencias (`rp_emergency`), estación de bomberos (`rp_firefighters`) |
| 29 | Well Stacked Pizza (`rp_restaurants`) |
| 27 | talleres (`rp_vehicles`) |
| 36 | autoescuela, agencia, sedes de trabajo, Vroom (`rp_driving`, `rp_agency`, `rp_jobs`, `rp_rides`) |
| 41 | waypoint y destino del GPS de `rp_map` (siempre visible) |
| 45 | tiendas de ropa (`rp_clothing`) |
| 51 | bencineras (`rp_vehicles`) |
| 52 | tiendas y mercados (`rp_shops`, `rp_jobs`) |
| 54 | bicicletas (`rp_bikes`) |
| 55 | concesionario (`rp_dealership`) |
| 56 | trabajos y agencia (`rp_jobs`, `rp_agency`) |
| 63 | policía (`rp_wanted`, `rp_police`) |

Icono nuevo: PNG en `rp_hud/images/blips/<id>.png` + id en `BLIP_ICON_IDS` y `KNOWN_BLIP_ICON_IDS`.
Pon `visibleDistance` (300-900) para no llenar el radar.

## Niveles de administración (`accounts.admin_level`)

| Nivel | Uso |
|---|---|
| 0 | jugador |
| 1 | admin: comandos de admin normales (`/crear...`, `/borrar...`, ayudas a jugadores) |
| 2 | admin con herramientas de prueba de contenido (`/mskip`, `/mmover` en `rp_missions`) |
| 3 | super admin: `rp_resmanager`, `/freecam`, `/pmover` de `rp_police`, todo el IAM |

Comprobación: `(exports.rp_login:getPlayerAdminLevel(p) or 0) >= N`. Para permisos finos del panel:
`exports.rp_adminpanel:hasPermission(p, clave)`. Todo comando de admin nuevo va al catálogo de
`rp_adminpanel/server/s_catalog.lua` (skill **comando-admin**).

## Orden de arranque (`mtaserver.conf`)

```
rp_database → rp_notify → rp_ids → rp_login → bone_attach → rp_heads → rp_characters → rp_needs
→ rp_inventory → rp_shops → rp_clothing → rp_bank → rp_phone → rp_rides → rp_properties
→ object_preview → rp_vehicles → rp_radio → rp_dealership → rp_nametags → rp_chat → rp_scoreboard
→ rp_hud → rp_citizens → rp_npcrel → rp_admin → rp_resmanager → rp_factions → rp_wanted → rp_pickups
→ rp_robbery → rp_dealers → rp_ammunation → rp_backpacks → rp_gym → rp_payday → rp_driving
→ rp_injury → rp_shootingrange → rp_emergency → rp_help → rp_agency → rp_adminpanel → rp_bikes → rp_jobs → rp_events
→ rp_levels → rp_pool → rp_hookers → rp_anims → rp_furniture → rp_races → rp_police → rp_mocap
→ rp_missions → rp_vending → rp_restaurants → rp_pizzeria → rp_firefighters → rp_map → rp_worldobjects → rp_interact → rp_metaldetector → rp_cartheft → rp_achievements
```

Herramientas de desarrollo que no arrancan con el servidor (p. ej. `rp_animlab`): no van en `mtaserver.conf` y llevan
`devtool="true"` en el `<info>` de su `meta.xml`, para que `rp_test` no las exija en marcha.

Un recurso nuevo va **al final** salvo que otro existente dependa de él. Aun así, declara las
dependencias con `<include>`: es lo que garantiza el orden si alguien lo reinicia a mano.

## Prefijos de eventos en uso

`rp:admin:`, `rp:adminpanel:`, `rp:agency:`, `rp:ammu:`, `rp:anims:`, `rp:atm:`, `rp:auth:`, `rp:bank:`,
`rp:achievements:`, `rp:bikes:`, `rp:bp:`, `rp:cartheft:`, `rp:chars:`, `rp:chat:`, `rp:citizens:`, `rp:cloth:`, `rp:clothing:`, `rp:dealer:`,
`rp:dealers:`, `rp:driving:`, `rp:duty:`, `rp:firefighters:`, `rp:drugs:`, `rp:emergency:`, `rp:events:`, `rp:fac:`, `rp:fuel:`, `rp:furn:`,
`rp:gallery:`, `rp:gym:`, `rp:help:`, `rp:hooker:`, `rp:injury:`, `rp:interact:`, `rp:inv:`, `rp:jobs:`, `rp:levels:`, `rp:metaldetector:`,
`rp:map:`, `rp:missions:`, `rp:mocap:`, `rp:music:`, `rp:notify:`, `rp:npcrel:`, `rp:paths:`, `rp:phone:`, `rp:pol:`,
`rp:pizzeria:`, `rp:pool:`, `rp:prop:`, `rp:races:`, `rp:radio:`, `rp:restaurants:`, `rp:resmgr:`, `rp:rides:`, `rp:robbery:`, `rp:shop:`,
`rp:social:`, `rp:tinder:`, `rp:toyed:`, `rp:toys:`, `rp:tune:`, `rp:ui:`, `rp:veh:`, `rp:vending:`, `rp:wanted:`.

Usa uno nuevo y único, igual al nombre del recurso sin `rp_`: `rp:<sistema>:<accion>` (y
`rp:<sistema>:ui:<accion>` para lo que viene del CEF). Los `rp:on<Algo>` son hooks globales del ciclo
de vida (ver `API.md`); crea uno nuevo solo si está pensado para que otros recursos se enganchen.
