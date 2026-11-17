# Referencia de recursos y comandos

## Recursos
| Recurso | Qué hace |
|---|---|
| `rp_database` | Conexión MySQL única (`dbConnect`) y creación automática de tablas. Export: `getConnection()`, `isReady()`. Credenciales en `config.lua` (solo servidor). |
| `rp_login` | Login/registro CEF (`html/`), contraseñas bcrypt (`passwordHash`/`passwordVerify` asíncronos). Al iniciar sesión dispara el evento de servidor `rp:onAccountLogin`. Exports: `isPlayerLoggedIn`, `getPlayerAccountId`, `getPlayerAccountName`. |
| `rp_characters` | Selección y creación de personajes (3 slots) en CEF con vista previa del ped y cambio de skin; spawn, guardado periódico y respawn en el hospital. Evento `rp:onCharacterSpawn`. Exports: `getPlayerCharacterId`, `getPlayerCharacterName`, `saveCharacter`. |
| `bone_attach` | Bone Attach 1.2.0 de CrystalMV (solo fuentes .lua). Pega objetos a huesos de peds. |
| `rp_heads` | 78 cabezas personalizadas (modelos de Countryside-RP, de Aleks) cargadas en IDs nuevos con `engineRequestModel`. Se dibujan en cada cliente según el elementData `rp:head`. |
| `rp_notify` | Notificaciones reutilizables con sonido: `notify`, `popup` y `bubble` (exports de cliente y servidor). `/silenciarnotis` para silenciar. |
| `rp_ids` | ID libre más bajo por jugador (elementData `id`). Exports `getPlayerId`, `getPlayerFromId`, `findPlayer`. Comando `/id`. |
| `rp_scoreboard` | Mantener Tab: nombre del servidor, jugadores activos y lista con ID, nombre y ping. |
| `rp_nametags` | Nombre Apellido (ID) sobre la cabeza con barras de vida y chaleco. |
| `rp_inventory` | Inventario por personaje en `character_items` (tecla I). Catálogo en `shared/s_items.lua`. Exports `giveItem`, `takeItem`, `hasItem`, `canCarry`... |
| `rp_shops` | Tiendas con NPC en `shops`/`shop_items`. E para comprar. Admin: `/crearshop <nombre>`, `/borrarshop <id>` (`accounts.admin_level` ≥ 1). |
| `rp_clothing` | Tiendas de ropa con interior propio (Binco, SubUrban, ProLaps, ZIP, Victim, Didier Sachs). E en la puerta para entrar; dentro, E abre el probador: ropa de CJ (o conjuntos/skins) que se prueba en vivo y solo se guarda al comprar. Accesorios (toys) pegados a un hueso con `bone_attach`, con editor de hueso, posicion, rotacion y escala por eje (`/accesorios`). Admin: `/crearropa <tipo> <nombre>`, `/ropapunto <id> entrada\|interior`, `/borrarropa <id>`, `/tiendasropa`. |
| `rp_needs` | Hambre, sed y energía por personaje (columnas en `characters`). `/dormir` solo en interiores. Exports `addNeed`, `getNeed`, `getNeeds`. |
| `rp_hud` | HUD propio: minimapa giratorio (radar extraído de gta3.img, ver `tools/RadarExtract.cs`), barras, hora, dinero. `/hud`. |
| `rp_bank` | Cuenta bancaria + cajeros (retiro solo en cajero). Admin: `/crearatm`, `/borraratm <id>`, `/dardinero <id> <cantidad>`. |
| `rp_phone` | Teléfono (tecla P o usar el item): Notas, Contactos, Banco, Fotogram (fotos del juego) y Ajustes. |
| `rp_rides` | App de viajes **Vroom** en el teléfono (o `/vroom`): eliges destino en el mapa (antes o ya arriba), se busca conductor y la app anima la búsqueda A* de la ruta. Los jugadores toman viajes desde la pestaña Conducir; el pedido llega antes a los mejor calificados (4.5★ al instante, 3.5★ a los 5 s, resto a los 10 s). Si nadie lo toma en 25 s, viene un auto IA que te espera, te lleva por la red vial y se va al dejarte. Cobro por banco (o efectivo), 80% al conductor. Al terminar se califica (1 a 5★) y se puede dejar propina. M alterna app y mapa. Tablas `rides` y `ride_drivers`. |
| `rp_properties` | Casas comprables: pickup verde (en venta) / flecha blanca (con dueño), visita de 1 min. `/cerrarcasa`, `/vendercasa`. Admin: `/crearcasa <tipo> <precio> <nombre>`, `/borrarcasa <id>`, `/tiposcasa`. |
| `rp_vehicles` | Vehículos personales (`vehicles`). Llave en el inventario (`vkey:<id>`): **L** abre/cierra, **J** o `/toggleengine` motor, **X** freno de mano, **flechas ←/→** intermitentes y **↓** balizas (rebindeables en Ajustes > Binds). **M** muestra el cursor y click derecho sobre un auto abre el menú: maletero, matrícula, multas (dueño), policía (facción 1: cepo, multas, historial) y admin (vista 3D, golpes y ocupantes de las últimas 24 h). Taller de tuning (círculo naranja, E o `/tunear`): colores, faros, paintjob y piezas, guardado en BD. `/copiallave`, `/darllave <jugador>`, admin `/allave <idVeh> <jugador>`. |
| `rp_dealership` | Concesionario Coutt and Schutz: autos al azar que cambian cada 60 min, compra con el banco, entrega segura. Admin: `/dealer puesto <n>`, `/dealer entrega`, `/dealer rotar`. |
| `rp_factions` | Facciones con panel en F3: el lider crea roles con nivel, sueldo y permisos (ver miembros, invitar, expulsar, cambiar rol, gestionar roles, fondos, registro, anuncio). Cada miembro solo ve lo que su rol permite. `/f`, `/finvitar`, `/aceptarfaccion`, `/salirfaccion`. Admin: `/crearfaccion <tipo> <siglas> <nombre>`, `/setlider <jugador> <id>`, `/darfondos`, `/borrarfaccion`, `/facciones`. |
| `rp_payday` | Sueldo cada 60 min de juego (sin contar AFK, se conserva entre sesiones) al banco: el del rol en la faccion (Estado o fondos de la faccion) o el sueldo base del Estado. `/payday`. Admin: `/forzarpayday <jugador>`. |

Hombres = cuerpo de CJ (skin 0) sin cabeza + cabeza + ropa nativa de CJ. Mujeres = skin.

## Créditos
- Modelos y ajustes de cabezas: Aleks (https://forum.mtasa.com/profile/40470-mraleks/), Countryside-RP, publicado por Neus. Su licencia prohíbe vender estos recursos.
- bone_attach: CrystalMV.
- object_preview 0.7.0: Ren712 (https://community.multitheftauto.com/index.php?p=resources&s=details&id=11836), sin cambios. Lo usa la vista 3D del panel de admin de vehiculos.

## Base de datos
- MariaDB (XAMPP sirve), puerto 3306.
- Base `mtarp`, usuario dedicado `mtarp` (sin permisos fuera de esa base).
- Tablas: `accounts`, `login_log`, `characters`, `character_items`, `shops`, `shop_items` (ver `rp_database/schema.lua`).

## Arrancar
1. Abre el XAMPP Control Panel y pulsa **Start** en MySQL.
2. Ejecuta `MTA Server.exe`. `mtaserver.conf` arranca `rp_database`, `rp_login`, `bone_attach`, `rp_heads` y `rp_characters`.

## Seguridad aplicada
- Toda validación se repite en el servidor; el cliente solo reenvía.
- Consultas parametrizadas (`?`), nunca SQL concatenado.
- Máx. 5 intentos fallidos → kick; 5 min para iniciar sesión; máx. 3 cuentas por serial; una sesión por cuenta.
- Chat bloqueado sin sesión; registro de intentos en `login_log`.
