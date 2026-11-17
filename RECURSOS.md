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
| `rp_vehicles` | Vehículos con dueño en la tabla `vehicles`. Tecla L o `/bloquear`. |
| `rp_dealership` | Concesionario Coutt and Schutz: autos al azar que cambian cada 60 min, compra con el banco, entrega segura. Admin: `/dealer puesto <n>`, `/dealer entrega`, `/dealer rotar`. |
| `rp_factions` | Facciones con panel en F3: el lider crea roles con nivel, sueldo y permisos (ver miembros, invitar, expulsar, cambiar rol, gestionar roles, fondos, registro, anuncio). Cada miembro solo ve lo que su rol permite. `/f`, `/finvitar`, `/aceptarfaccion`, `/salirfaccion`. Admin: `/crearfaccion <tipo> <siglas> <nombre>`, `/setlider <jugador> <id>`, `/darfondos`, `/borrarfaccion`, `/facciones`. |
| `rp_injury` | Estado **abatido**: en vez de morir, el personaje cae al suelo desangrandose (pantalla en escala de grises con desenfoque al mover la cámara, solo para el abatido; gotas y charco de sangre) durante 2 minutos, con un reloj de arena verde en el centro como contador: cuando se vacía, muere. No puede moverse, hablar, usar comandos, el telefono ni ninguna interfaz. Al terminar muere, aparece en el hospital con la vida completa y paga la tarifa (efectivo primero, el resto del banco). Salir estando abatido no salta la espera: el tiempo pendiente se guarda (`characters.downed_ms`) y al volver a entrar sigues abatido en el mismo sitio con el tiempo que te quedaba. Ajustes en `shared/s_config.lua`. Exports `isPlayerDowned`, `downPlayer`, `revivePlayer` (servidor) e `isLocalPlayerDowned` (cliente). Admin: `/revivir [jugador]`, `/abatir <jugador>`. |
| `rp_wanted` | Estrellas de búsqueda como GTA SA: cada delito (golpear, apuñalar o disparar a peatones o policías, atropellar, embestir patrullas, robar autos, explosiones...) suma puntos de caos y las estrellas suben a 50/180/550/1200/2400/4600. Sin policía a menos de 18 m bajan solas; morir, el arresto (te sacan del auto o te reducen en el suelo: cárcel con timer, o `/fianza`, y sales en la comisaría de Pershing Square) o un Pay 'n' Spray ($100, sin que te vean) las borran. Policía IA con sirena: patrullas (1-3, más las del tráfico que se suman), helicóptero desde 3★, controles de carretera, SWAT, FBI y ejército; a 1★ te arrestan, desde 2★ disparan. Estrellas propias en el HUD. La facción 1 (policía) de servicio (uniforme o vehículo policial) no acumula búsqueda, recibe el aviso de la central y ve un punto rojo en el mapa. `/busquedainfo` muestra tus estrellas y caos. Admin: `/busqueda <jugador> [0-6]`. Ver `docs/BUSQUEDA_POLICIAL.md`. |
| `rp_payday` | Sueldo cada 60 min de juego (sin contar AFK, se conserva entre sesiones) al banco: el del rol en la faccion (Estado o fondos de la faccion) o el sueldo base del Estado. `/payday`. Admin: `/forzarpayday <jugador>`. |
| `rp_emergency` | Emergencias **911** (`/911`, menú CEF con Policía, Bomberos y Ambulancia; teclas 1-3). La **ambulancia IA** aparece en la calle fuera de tu vista, conduce por la red vial de `rp_citizens` (A*, reutilizada de `rp_rides`), se detiene cerca, los 2 paramédicos bajan y reaniman con RCP a los abatidos en 45 m (por orden de cercanía); si no hay nadie, miran, vuelven a subir y se van. Un muerto se carga en una camilla simulada, se traslada al hospital más cercano, se entrega y reaparece tratado. Policía y bomberos solo disparan el evento `rp:emergency:onCall`. Contrato con el sistema de abatidos en `docs/EMERGENCIAS.md`. Exports (servidor): `isPlayerDowned`, `revivePlayer`, `getActiveCall`. Admin: `/cancelar911 <jugador>`. |
| `rp_help` | Panel de ayuda CEF con **F1** (o `/ayuda`): inicio, guia para nuevos, reglas, conceptos de rol (MG, PG, DM, PK, CK...), teclas, comandos con buscador y boton de Discord (enlace en `shared/s_config.lua`, `DISCORD_URL`). Pestana **Reportar** (o `/reportar`): motivo, jugador y descripcion; se guarda en la tabla `reports` (la crea el propio recurso) y avisa al instante al staff conectado. El jugador ve el estado de sus reportes. Admin: `/reportes`, `/atender <id>`, `/cerrarreporte <id> [nota]`. Todo el contenido se edita en `shared/s_config.lua`. |

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
