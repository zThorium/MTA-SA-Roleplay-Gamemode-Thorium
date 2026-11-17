# Gamemode Roleplay (MTA:SA 1.6)

## Recursos (en orden de arranque, ver `mtaserver.conf`)
| Recurso | Qué hace |
|---|---|
| `rp_database` | Conexión MySQL única (`dbConnect`) y esquema (`schema.lua`, se aplica solo al iniciar). Exports `getConnection()`, `isReady()`. Credenciales en `config.lua` (solo servidor). |
| `rp_notify` | Notificaciones reutilizables con sonido: `notify`, `popup` y `bubble` (exports de cliente y servidor). `/silenciarnotis`. |
| `rp_ids` | ID libre más bajo por jugador (elementData `id`). Exports `getPlayerId`, `getPlayerFromId`, `findPlayer`. Comando `/id`. |
| `rp_login` | Login/registro CEF, contraseñas bcrypt. Evento de servidor `rp:onAccountLogin`. Exports `isPlayerLoggedIn`, `getPlayerAccountId`, `getPlayerAccountName`, `getPlayerAdminLevel`. |
| `bone_attach` | Bone Attach 1.2.0 de CrystalMV (solo fuentes .lua). |
| `rp_heads` | 78 cabezas personalizadas (modelos de Countryside-RP, de Aleks) en IDs nuevos con `engineRequestModel`; oculta la sangre del cuello. `/ajustecabeza` para calibrar. |
| `rp_characters` | Selección y creación de personajes (3 slots, CEF con vista previa). Hombres = cuerpo de CJ + cabeza + ropa; mujeres = skin. Eventos `rp:onCharacterSpawn` / `rp:onCharacterLogout`. Exports `getPlayerCharacterId`, `getPlayerCharacterName`, `saveCharacter`. |
| `rp_needs` | Hambre, sed y energía por personaje. `/dormir` solo en interiores. Exports `addNeed`, `getNeed`, `getNeeds`. |
| `rp_inventory` | Inventario por personaje (`character_items`), tecla I. Catálogo en `shared/s_items.lua`. Exports `giveItem`, `takeItem`, `hasItem`, `canCarry`... |
| `rp_shops` | Tiendas con NPC (`shops`/`shop_items`), E para comprar. Admin: `/crearshop <nombre>`, `/borrarshop <id>`. |
| `rp_clothing` | Tiendas de ropa con interior propio (Binco, SubUrban, ProLaps, ZIP, Victim, Didier Sachs). E en la puerta para entrar; dentro, E abre el probador: ropa de CJ (o conjuntos/skins) que se prueba en vivo y solo se guarda al comprar. Accesorios (toys) pegados a un hueso con `bone_attach`, con editor de hueso, posicion, rotacion y escala por eje (`/accesorios`). Admin: `/crearropa <tipo> <nombre>`, `/ropapunto <id> entrada\|interior`, `/borrarropa <id>`, `/tiendasropa`. |
| `rp_bank` | Cuenta bancaria + cajeros (retiro solo en cajero). Admin: `/crearatm`, `/borraratm <id>`, `/dardinero <id> <cantidad>`. |
| `rp_phone` | Teléfono (tecla P o usar el item): Notas, Contactos, Banco, Fotogram (fotos del juego) y Ajustes. |
| `rp_properties` | 138 casas de Los Santos generadas de los datos del juego (`server/s_seed_ls.lua`: ENEX con interior real + edificios residenciales de los IPL). Pickup verde = en venta (modal Comprar / Previsualizar 1 min), flecha blanca = con dueño. `/cerrarcasa`, `/vendercasa`. Admin: `/crearcasa <tipo> <precio> <nombre>`, `/borrarcasa <id>`, `/tiposcasa`. |
| `rp_vehicles` | Vehículos con dueño (`vehicles`). Tecla L o `/bloquear`. |
| `rp_dealership` | Concesionario Coutt and Schutz: autos al azar que cambian cada 60 min, compra con el banco, entrega segura. Admin: `/dealer puesto <n>`, `/dealer entrega`, `/dealer rotar`. |
| `rp_nametags` | Nombre Apellido (ID) sobre la cabeza con barras de vida y chaleco. |
| `rp_scoreboard` | Mantener Tab: servidor, jugadores activos, ID, nombre y ping. |
| `rp_hud` | HUD propio: minimapa giratorio (radar extraído de gta3.img, `tools/RadarExtract.cs`), barras, hora, dinero. `/hud`. |
| `rp_citizens` | Peatones y tráfico 100% en el cliente sobre la red de caminos de GTA SA (`c_nodes_ls.lua`). Máquina de estados: pasear, esperar, huir, pelear / conducir, frenar, bocina, esquivar, huir. Parte del tráfico va en moto y hay patrullas de policía (auto de la ciudad o moto HPV1000 con su agente) que prenden la sirena si estás buscado. `/poblacion`, `/poblacioninfo`. Editor de rutas para admins: `/nodos` (cambios en `path_nodes` / `path_links`, aplicados en vivo). |
| `rp_admin` | Herramientas de administración: `/freecam`. |
| `rp_factions` | Facciones con panel en F3: el lider crea roles con nivel, sueldo y permisos (ver miembros, invitar, expulsar, cambiar rol, gestionar roles, fondos, registro, anuncio). Cada miembro solo ve lo que su rol permite. `/f`, `/finvitar`, `/aceptarfaccion`, `/salirfaccion`. Admin: `/crearfaccion <tipo> <siglas> <nombre>`, `/setlider <jugador> <id>`, `/darfondos`, `/borrarfaccion`, `/facciones`. |
| `rp_wanted` | Estrellas de búsqueda como GTA SA: cada delito (golpear, apuñalar o disparar a peatones o policías, atropellar, embestir patrullas, robar autos, explosiones...) suma puntos de caos y las estrellas suben a 50/180/550/1200/2400/4600. Sin policía a menos de 18 m bajan solas; morir, el arresto o un Pay 'n' Spray ($100, sin que te vean) las borran. Policía IA con sirena: patrullas (1-3), helicóptero desde 3★, controles de carretera, SWAT, FBI y ejército; a 1★ te arrestan, desde 2★ disparan. Estrellas propias en el HUD. La facción 1 (policía) de servicio (uniforme o vehículo policial) no acumula búsqueda, recibe el aviso de la central y ve un punto rojo en el mapa. `/busquedainfo` muestra tus estrellas y caos. Admin: `/busqueda <jugador> [0-6]`. Ver `docs/BUSQUEDA_POLICIAL.md`. |
| `rp_payday` | Sueldo cada 60 min de juego (sin contar AFK, se conserva entre sesiones) al banco: el del rol en la faccion (Estado o fondos de la faccion) o el sueldo base del Estado. `/payday`. Admin: `/forzarpayday <jugador>`. |

## Créditos
- Modelos y ajustes de cabezas: Aleks (https://forum.mtasa.com/profile/40470-mraleks/), Countryside-RP, publicado por Neus. Su licencia prohíbe vender estos recursos.
- bone_attach: CrystalMV.
- Mapa del radar, caminos y casas: generados a partir de los archivos de la instalación local de GTA SA.

## Base de datos
- MariaDB de XAMPP (`C:\Users\fabia\Documents\Programas`), puerto 3306.
- Base `mtarp`, usuario dedicado `mtarp` (sin permisos fuera de esa base).
- Tablas: `accounts`, `login_log`, `characters`, `character_items`, `shops`, `shop_items`, `bank_transactions`, `atms`, `phone_notes`, `phone_contacts`, `social_posts`, `social_likes`, `properties`, `vehicles`, `factions`, `faction_ranks`, `faction_members`, `faction_log`.

## Arrancar
1. Abre el XAMPP Control Panel y pulsa **Start** en MySQL.
2. Ejecuta `MTA Server.exe`.

## Seguridad aplicada
- Toda validación se repite en el servidor; el cliente solo reenvía.
- Consultas parametrizadas (`?`), nunca SQL concatenado; cobros con `UPDATE ... WHERE saldo >= ?` atómicos.
- Máx. 5 intentos fallidos → kick; 5 min para iniciar sesión; máx. 3 cuentas por serial; una sesión por cuenta.
- Chat bloqueado sin personaje; registro de intentos en `login_log`.
