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
| `rp_characters` | Selección y creación de personajes (3 slots, CEF con vista previa). Hombres = cuerpo de CJ + cabeza + ropa + complexión (grasa/músculo) y color de piel; mujeres = skin. Altura para ambos (shader `fx/body.fx`, `/ajustepiel` para calibrar el tono). Eventos `rp:onCharacterSpawn` / `rp:onCharacterLogout`. Exports `getPlayerCharacterId`, `getPlayerCharacterName`, `saveCharacter`. |
| `rp_needs` | Hambre, sed y energía por personaje. `/dormir` solo en interiores. Exports `addNeed`, `getNeed`, `getNeeds`. |
| `rp_inventory` | Inventario por personaje (`character_items`), tecla I. Catálogo en `shared/s_items.lua`. Exports `giveItem`, `takeItem`, `hasItem`, `canCarry`... |
| `rp_shops` | Tiendas con NPC (`shops`/`shop_items`), E para comprar. Admin: `/crearshop <nombre>`, `/borrarshop <id>`. |
| `rp_clothing` | Tiendas de ropa con interior propio (Binco, SubUrban, ProLaps, ZIP, Victim, Didier Sachs). E en la puerta para entrar; dentro, E abre el probador: ropa de CJ (o conjuntos/skins) que se prueba en vivo y solo se guarda al comprar. Accesorios (toys) pegados a un hueso con `bone_attach`, con editor de hueso, posicion, rotacion y escala por eje (`/accesorios`). Admin: `/crearropa <tipo> <nombre>`, `/ropapunto <id> entrada\|interior`, `/borrarropa <id>`, `/tiendasropa`. |
| `rp_bank` | Cuenta bancaria + cajeros (retiro solo en cajero). Tarjeta de débito automática con clave de 4 dígitos (`bank_cards`); si se pierde, el cajero entrega otra. Admin: `/crearatm`, `/borraratm <id>`, `/dardinero <id> <cantidad>`. |
| `rp_phone` | Teléfono (tecla P o usar el item): Notas, Contactos, Banco, Fotogram (fotos del juego) y Ajustes. |
| `rp_properties` | 138 casas de Los Santos generadas de los datos del juego (`server/s_seed_ls.lua`: ENEX con interior real + edificios residenciales de los IPL). Pickup verde = en venta (modal Comprar / Previsualizar 1 min), flecha blanca = con dueño. `/cerrarcasa`, `/vendercasa`. Admin: `/crearcasa <tipo> <precio> <nombre>`, `/borrarcasa <id>`, `/tiposcasa`. |
| `rp_vehicles` | Vehículos personales (`vehicles`). Llave en el inventario (`vkey:<id>`): **L** abre/cierra, **J** o `/toggleengine` motor, **X** freno de mano, **flechas ←/→** intermitentes y **↓** balizas (rebindeables en Ajustes > Binds). **M** muestra el cursor y click derecho sobre un auto abre el menú: maletero, matrícula, multas (dueño), policía (facción 1: cepo, multas, historial) y admin (vista 3D, golpes y ocupantes de las últimas 24 h). Taller de tuning (círculo naranja, E o `/tunear`): colores, faros, paintjob y piezas, guardado en BD. `/copiallave`, `/darllave <jugador>`, admin `/allave <idVeh> <jugador>`, `/nearbyvehs`, `/vehinfo`, `/fixveh`, `/blowveh`, `/getveh <id>`, `/gotoveh <id>`, `/nearbytalleres`, `/movertaller <n>`, `/nearbybencineras`, `/moverbencinera <n>`, `/moverbombero <n>`, `/setfuel [litros]`. Taller: reparación en el panel. **Bencina**: los autos gastan bencina al andar (velocímetro y medidor en el HUD); en las bencineras (círculo amarillo) **E** llama al bombero, se eligen los litros, carga y se paga en el datafono con la tarjeta de débito (`bcard:<id>`, número y clave visibles solo para su dueño en el inventario) o en efectivo. |
| `rp_dealership` | Concesionario Coutt and Schutz: autos al azar que cambian cada 60 min, compra con el banco, entrega segura. Admin: `/dealer puesto <n>`, `/dealer entrega`, `/dealer rotar`. |
| `rp_nametags` | Nombre Apellido (ID) sobre la cabeza con barras de vida y chaleco. |
| `rp_scoreboard` | Mantener Tab: servidor, jugadores activos, ID, nombre y ping. |
| `rp_hud` | HUD propio: minimapa giratorio (radar extraído de gta3.img, `tools/RadarExtract.cs`), barras, hora, dinero. `/hud`. |
| `rp_citizens` | Peatones y tráfico 100% en el cliente sobre la red de caminos de GTA SA (`c_nodes_ls.lua`). Máquina de estados: pasear, esperar, huir, pelear / conducir, frenar, bocina, esquivar, huir. `/poblacion`, `/poblacioninfo`. Editor de rutas para admins: `/nodos` (cambios en `path_nodes` / `path_links`, aplicados en vivo). |
| `rp_admin` | Administración: `/freecam`, `/goto`, `/get`, `/tp`, `/heal`, `/sethp`, `/freeze`, `/slap`, `/kick`, `/givemoney`, `/a`, `/admins`, `/ahelp`, `/debug [0-3]` (activa el debugscript) y `/copiardebug [X]` (copia al portapapeles las ultimas X lineas del debug) (nivel 1) y `/setmoney`, `/ban` (nivel 3). Registra todo en `admin_log`. |
| `rp_factions` | Facciones con panel en F3: el lider crea roles con nivel, sueldo y permisos (ver miembros, invitar, expulsar, cambiar rol, gestionar roles, fondos, registro, anuncio). Cada miembro solo ve lo que su rol permite. `/f`, `/finvitar`, `/aceptarfaccion`, `/salirfaccion`. Admin: `/crearfaccion <tipo> <siglas> <nombre>`, `/setlider <jugador> <id>`, `/darfondos`, `/borrarfaccion`, `/facciones`. |
| `rp_wanted` | Estrellas de búsqueda como GTA SA: cada delito (golpear, apuñalar o disparar a peatones o policías, atropellar, embestir patrullas, robar autos, explosiones...) suma puntos de caos y las estrellas suben a 50/180/550/1200/2400/4600. Sin policía a menos de 18 m bajan solas; morir, el arresto (te sacan del auto o te reducen en el suelo: cárcel con timer, o `/fianza`, y sales en la comisaría de Pershing Square) o un Pay 'n' Spray ($100, sin que te vean) las borran. Policía IA con sirena: patrullas (1-3, más las del tráfico que se suman), helicóptero desde 3★, controles de carretera, SWAT, FBI y ejército; a 1★ te arrestan, desde 2★ disparan. Estrellas propias en el HUD. La facción 1 (policía) de servicio (uniforme o vehículo policial) no acumula búsqueda, recibe el aviso de la central y ve un punto rojo en el mapa. `/busquedainfo` muestra tus estrellas y caos. Admin: `/busqueda <jugador> [0-6]`. Ver `docs/BUSQUEDA_POLICIAL.md`. |
| `rp_payday` | Sueldo cada 60 min de juego (sin contar AFK, se conserva entre sesiones) al banco: el del rol en la faccion (Estado o fondos de la faccion) o el sueldo base del Estado. `/payday`. Admin: `/forzarpayday <jugador>`. |
| `rp_help` | Panel de ayuda CEF con **F1** (o `/ayuda`): inicio, guia para nuevos, reglas, conceptos de rol (MG, PG, DM, PK, CK...), teclas, comandos con buscador y boton de Discord (enlace en `shared/s_config.lua`, `DISCORD_URL`). Pestana **Reportar** (o `/reportar`): motivo, jugador y descripcion; se guarda en la tabla `reports` (la crea el propio recurso) y avisa al instante al staff conectado. El jugador ve el estado de sus reportes. Admin: `/reportes`, `/atender <id>`, `/cerrarreporte <id> [nota]`. Todo el contenido se edita en `shared/s_config.lua`. |

## Créditos
- Modelos y ajustes de cabezas: Aleks (https://forum.mtasa.com/profile/40470-mraleks/), Countryside-RP, publicado por Neus. Su licencia prohíbe vender estos recursos.
- bone_attach: CrystalMV.
- object_preview 0.7.0: Ren712 (https://community.multitheftauto.com/index.php?p=resources&s=details&id=11836), sin cambios. Lo usa la vista 3D del panel de admin de vehiculos.
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
