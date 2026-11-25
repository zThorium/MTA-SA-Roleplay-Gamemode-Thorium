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
| 30001 | `rp_agency` | agencia de empleo |

Para un recurso nuevo usa un bloque de 1000 libre (por ejemplo `23000 + id`, `24000 + n`...) en
`DIMENSION_BASE` de su config, y escríbelo aquí. Comprueba siempre **interior + dimensión + distancia**.

## Teclas

| Tecla | Uso |
|---|---|
| **E** | interacción universal (15 recursos: tiendas, cajeros, puertas, máquinas, trabajos...). Solo actúa junto a tu punto |
| G | muebles con función (`rp_furniture`) |
| H | interactuar con peatones (`rp_npcrel`), amenazar en robos (`rp_robbery`) |
| I | inventario |
| O | menú radial de animaciones (`rp_anims`, mantener), mochila (`rp_backpacks`), sirena (`rp_police`, en patrulla) ⚠️ saturada |
| J | misiones (`rp_missions`); motor del vehículo (`rp_vehicles`, rebindeable) |
| K | cursor de interacción policial (`rp_police`) |
| L / X / flechas | cerrar, freno de mano, intermitentes (`rp_vehicles`, rebindeables en Ajustes > Binds) |
| M | cursor y menú de vehículo (`rp_vehicles`), mapa/app en Vroom (`rp_rides`) |
| P | teléfono |
| R | radio del vehículo |
| T / Y / U / B | chat: decir, susurrar, gritar, OOC (`rp_chat`) |
| Y / N | aceptar / rechazar invitaciones (`rp_missions`, `rp_races`, `rp_citizens`) |
| Espacio, Retroceso, flechas, A/D | controles contextuales de minijuegos (`rp_gym`, `rp_driving`, `rp_races`) solo mientras estás en ellos |
| F1 | ayuda · F3 facciones · F4 decorar · F5 carreras · F6 MDT policial · F7 mostrar/ocultar HUD (`rp_hud`) · F9 recursos · F10 panel admin |
| F11 / F12 / Tab / T | reservadas por MTA/GTA (mapa, captura, lista, chat) |

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
  `rp:meth`, `rp:respect`, `rp:wanted`, `rp:wantedHeld`, `rp:wantedLost`, `rp:wantedNoTires`.
- Vehículos: `rp:vehicleId`, `rp:vehicleOwner`, `rp:indicator`, `rp:copCar`, `rp:perf`, `rp:radio`, `rp:rides:ai`.
- Peds / objetos: `rp:citizen`, `rp:cop`, `rp:dealer`, `rp:shopId`, `rp:shopName`, `rp:robberyPed`,
  `rp:robberyStore`, `rp:emergency`, `rp:npcrel`, `rp:furn`, `rp:eventProp`, `rp:toy`, `rp:property`.
- Root: `rp:world` (hora y clima), `rp:events`.
- Blips: `rp:radarEdge` (el blip se queda en el borde del minimapa).

## Blips del minimapa (`rp_hud`)

`rp_hud` **solo dibuja** los iconos listados en `KNOWN_BLIP_ICON_IDS` (`rp_hud/c_hud.lua`); el resto
no aparece. Iconos con PNG propio en `rp_hud/images/blips/`:

| Icono | Uso actual |
|---|---|
| 17 | tiendas 24/7 (`rp_robbery`) |
| 22 | emergencias (`rp_emergency`) |
| 27 | talleres (`rp_vehicles`) |
| 36 | autoescuela, agencia, sedes de trabajo, Vroom (`rp_driving`, `rp_agency`, `rp_jobs`, `rp_rides`) |
| 41 | waypoint (siempre visible) |
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
→ rp_missions
```

Un recurso nuevo va **al final** salvo que otro existente dependa de él. Aun así, declara las
dependencias con `<include>`: es lo que garantiza el orden si alguien lo reinicia a mano.

## Prefijos de eventos en uso

`rp:admin:`, `rp:adminpanel:`, `rp:agency:`, `rp:ammu:`, `rp:anims:`, `rp:atm:`, `rp:auth:`, `rp:bank:`,
`rp:bikes:`, `rp:bp:`, `rp:chars:`, `rp:chat:`, `rp:citizens:`, `rp:cloth:`, `rp:clothing:`, `rp:dealer:`,
`rp:dealers:`, `rp:driving:`, `rp:drugs:`, `rp:emergency:`, `rp:events:`, `rp:fac:`, `rp:fuel:`, `rp:furn:`,
`rp:gallery:`, `rp:gym:`, `rp:help:`, `rp:hooker:`, `rp:injury:`, `rp:inv:`, `rp:jobs:`, `rp:levels:`,
`rp:missions:`, `rp:mocap:`, `rp:music:`, `rp:notify:`, `rp:npcrel:`, `rp:paths:`, `rp:phone:`, `rp:pol:`,
`rp:pool:`, `rp:prop:`, `rp:races:`, `rp:radio:`, `rp:resmgr:`, `rp:rides:`, `rp:robbery:`, `rp:shop:`,
`rp:social:`, `rp:tinder:`, `rp:toyed:`, `rp:toys:`, `rp:tune:`, `rp:ui:`, `rp:veh:`, `rp:vending:`, `rp:wanted:`.

Usa uno nuevo y único, igual al nombre del recurso sin `rp_`: `rp:<sistema>:<accion>` (y
`rp:<sistema>:ui:<accion>` para lo que viene del CEF). Los `rp:on<Algo>` son hooks globales del ciclo
de vida (ver `API.md`); crea uno nuevo solo si está pensado para que otros recursos se enganchen.
