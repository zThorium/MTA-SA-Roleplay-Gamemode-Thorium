# Referencia de recursos y comandos

## Recursos
| Recurso | Qué hace |
|---|---|
| `rp_database` | Conexión MySQL única (`dbConnect`) y creación automática de tablas. Export: `getConnection()`, `isReady()`. Credenciales en `config.lua` (solo servidor). |
| `rp_login` | Login/registro CEF (`html/`), contraseñas bcrypt (`passwordHash`/`passwordVerify` asíncronos). Al iniciar sesión dispara el evento de servidor `rp:onAccountLogin`. Exports: `isPlayerLoggedIn`, `getPlayerAccountId`, `getPlayerAccountName`. |
| `rp_characters` | Selección y creación de personajes (3 slots) en CEF con vista previa del ped y cambio de skin; complexión (grasa/músculo con `setPedStat`), altura y color de piel (shader `fx/body.fx`, elementData `rp:body`); historia de mínimo 30 caracteres. Spawn, guardado periódico y respawn en el hospital. Evento `rp:onCharacterSpawn`. Exports: `getPlayerCharacterId`, `getPlayerCharacterName`, `saveCharacter`. `/ajustepiel <ref>` (local) calibra el tono de piel. Columnas `characters.body_fat`, `body_muscle`, `skin_tone`. |
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
| `rp_vehicles` | Vehículos con dueño en la tabla `vehicles`. Tecla L o `/bloquear`. |
| `rp_radio` | Radio de vehículos con emisoras de internet (LOS40 y variantes, Radio Corazón, Radio Carolina, Cadena Dial, M80, Cadena SER, etc.). Tecla R o `/radio` abre el panel (emisoras + volumen) siendo conductor o copiloto; las teclas de radio siguiente/anterior de GTA cambian de emisora y la radio nativa queda anulada. Todos los cercanos oyen el stream en 3D desde el vehículo; el dato `rp:radio` del vehículo va sincronizado. Emisoras en `shared/s_config.lua`. `/radio apagar`. Exports (servidor): `getVehicleStation`, `setVehicleStation`. |
| `rp_dealership` | Concesionario Coutt and Schutz: autos al azar que cambian cada 60 min, compra con el banco, entrega segura. Admin: `/dealer puesto <n>`, `/dealer entrega`, `/dealer rotar`. |
| `rp_factions` | Facciones con panel en F3: el lider crea roles con nivel, sueldo y permisos (ver miembros, invitar, expulsar, cambiar rol, gestionar roles, fondos, registro, anuncio). Cada miembro solo ve lo que su rol permite. `/f`, `/finvitar`, `/aceptarfaccion`, `/salirfaccion`. Admin: `/crearfaccion <tipo> <siglas> <nombre>`, `/setlider <jugador> <id>`, `/darfondos`, `/borrarfaccion`, `/facciones`. |
| `rp_injury` | Estado **abatido**: en vez de morir, el personaje cae al suelo desangrandose (pantalla en escala de grises con desenfoque al mover la cámara, solo para el abatido; gotas y charco de sangre) durante 2 minutos, con un reloj de arena verde en el centro como contador: cuando se vacía, muere. No puede moverse, hablar, usar comandos, el telefono ni ninguna interfaz. Al terminar muere, aparece en el hospital con la vida completa y paga la tarifa (efectivo primero, el resto del banco). Salir estando abatido no salta la espera: el tiempo pendiente se guarda (`characters.downed_ms`) y al volver a entrar sigues abatido en el mismo sitio con el tiempo que te quedaba. Ajustes en `shared/s_config.lua`. Exports `isPlayerDowned`, `downPlayer`, `revivePlayer` (servidor) e `isLocalPlayerDowned` (cliente). Admin: `/revivir [jugador]`, `/abatir <jugador>`. |
| `rp_payday` | Sueldo cada 60 min de juego (sin contar AFK, se conserva entre sesiones) al banco: el del rol en la faccion (Estado o fondos de la faccion) o el sueldo base del Estado. `/payday`. Admin: `/forzarpayday <jugador>`. |
| `rp_emergency` | Emergencias **911** (`/911`, menú CEF con Policía, Bomberos y Ambulancia; teclas 1-3). La **ambulancia IA** aparece en la calle fuera de tu vista, conduce por la red vial de `rp_citizens` (A*, reutilizada de `rp_rides`), se detiene cerca, los 2 paramédicos bajan y reaniman con RCP a los abatidos en 45 m (por orden de cercanía); si no hay nadie, miran, vuelven a subir y se van. Un muerto se carga en una camilla simulada, se traslada al hospital más cercano, se entrega y reaparece tratado. Policía y bomberos solo disparan el evento `rp:emergency:onCall`. Contrato con el sistema de abatidos en `docs/EMERGENCIAS.md`. Exports (servidor): `isPlayerDowned`, `revivePlayer`, `getActiveCall`. Admin: `/cancelar911 <jugador>`. |
| `rp_adminpanel` | Panel CEF para administradores con todos los comandos de admin agrupados por categoría (herramientas, jugadores, economía, facciones, mundo), descripción, argumentos y recurso de origen; búsqueda y clic para copiar el comando. El catálogo está en `server/s_catalog.lua` y solo se envía a admins (`admin_level` ≥ 1). **Al crear un comando de admin nuevo, añádelo al catálogo.** Admin: `/adminpanel` (o `/apanel`, tecla `F10`). |

Hombres = cuerpo de CJ (skin 0) sin cabeza + cabeza + ropa nativa de CJ. Mujeres = skin.

## Créditos
- Modelos y ajustes de cabezas: Aleks (https://forum.mtasa.com/profile/40470-mraleks/), Countryside-RP, publicado por Neus. Su licencia prohíbe vender estos recursos.
- bone_attach: CrystalMV.

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
