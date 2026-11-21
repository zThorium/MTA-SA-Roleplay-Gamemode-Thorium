# Convenciones de código

Patrones que ya usa el gamemode. Copia el estilo del recurso más parecido antes de inventar uno nuevo.

## Recurso nuevo

1. Carpeta `resources/[roleplay]/rp_<sistema>/` con `server/`, `client/`, `shared/`, `html/` según haga falta.
2. `meta.xml`:
   ```xml
   <meta>
       <info author="Thorium" name="RP Algo" description="..." version="1.0.0" type="script" />
       <min_mta_version server="1.6.0" client="1.6.0" />
       <include resource="rp_database" />
       <include resource="rp_notify" />
       <include resource="rp_login" />
       <include resource="rp_characters" />
       <script src="shared/s_config.lua" type="shared" />
       <script src="server/s_algo.lua" type="server" />
       <script src="client/c_algo.lua" type="client" cache="false" />
       <file src="html/index.html" />
       <file src="html/style.css" />
       <file src="html/app.js" />
       <export function="algoUtil" type="server" />
   </meta>
   ```
   `cache="false"` en scripts de cliente para no dejar el código en el disco del jugador.
3. Línea en `mtaserver.conf` después de sus dependencias.
4. Fila en `RECURSOS.md` con qué hace, exports y comandos.
5. Cabecera en cada `.lua` con el recurso, el archivo y qué hace (ver los existentes).

## Base de datos

- Conexión: `local function db() return exports.rp_database:getConnection() end`.
- Lectura:
  ```lua
  dbQuery(function(qh)
      local rows = dbPoll(qh, 0)
      if not rows then return end
      -- ...
  end, db(), "SELECT * FROM characters WHERE id = ?", characterId)
  ```
- Escritura sin resultado: `dbExec(db(), "UPDATE ... WHERE id = ?", ...)`.
- Cobro: `dbPoll(qh, 0)` devuelve `result, affectedRows`; si `affectedRows == 0`, no había saldo.
- Al arrancar un recurso que lee la BD, espera a `exports.rp_database:isReady()` o al evento `rp:onDatabaseReady`.
- Datos del personaje van en `characters` o en tablas con `character_id` + `FOREIGN KEY ... ON DELETE CASCADE`.
- Tablas `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`.

### Migraciones (`rp_database/schema.lua`)

`SCHEMA` es una lista de sentencias que se ejecutan en orden en cada arranque. Por eso:

- Solo se **añade al final**, con un comentario de qué recurso la usa.
- Toda sentencia debe ser **idempotente**: `CREATE TABLE IF NOT EXISTS`,
  `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`, `ADD INDEX IF NOT EXISTS` (sintaxis de MariaDB).
- Nunca se edita una sentencia ya publicada en `main`; para cambiar una columna se añade otro `ALTER`.
- Si una falla, se registra en consola y se sigue con la siguiente: revisa la consola tras cambiarlo.

Tablas actuales: `accounts`, `login_log`, `characters`, `character_items`, `bank_transactions`, `atms`,
`phone_notes`, `phone_contacts`, `ride_drivers`, `rides`, `social_posts`, `social_likes`, `properties`,
`path_nodes`, `path_links`, `clothing_stores`, `character_toys`, `vehicles`, `shops`, `shop_items`,
`factions`, `faction_ranks`, `faction_members`, `faction_log`, `identity_cards`.

## Eventos y seguridad

- Nombres: `rp:<sistema>:<accion>` (servidor ↔ cliente) y `rp:<sistema>:ui:<accion>` (CEF → Lua cliente).
- Eventos remotos: `addEvent("rp:algo:hacer", true)`. Solo los que el cliente debe poder disparar.
- En el handler de servidor el jugador es `client`. Revalida todo:
  ```lua
  addEventHandler("rp:bank:deposit", root, function(amount)
      if not isNearATM(client) then return end
      deposit(client, tonumber(amount))
  end)
  ```
- Convierte y acota lo que llega (`tonumber`, `math.floor`, rangos, longitudes de texto).
- Identidad: `exports.rp_login:getPlayerAccountId(p)`, `exports.rp_characters:getPlayerCharacterId(p)`;
  si es `nil`, el jugador no tiene sesión o personaje y no se hace nada.
- Admin: `local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end`.
  Hoy solo hay nivel 1; si añades niveles, documéntalos en `RECURSOS.md`.

## Interfaces CEF

- Patrón de `rp_login`/`rp_shops`: `guiCreateBrowser(0, 0, screenW, screenH, true, true, false)`,
  cargar `http://mta/local/html/index.html` y, al terminar de cargar, enviar datos con
  `executeBrowserJavascript(browser, ("RP.render(%s[0])"):format(toJSON(data, true)))`.
- El JS llama a Lua con `mta.triggerEvent("rp:algo:ui:accion", ...)` y expone `window.RP` para recibir.
  Envuelve la llamada para que el HTML también abra en un navegador normal (vista previa).
- Interfaces que se abren a menudo: crea el navegador una vez y muéstralo/ocúltalo (ver `rp_inventory`).
- Misma paleta y estilo que `rp_shops` y `rp_inventory`. Esc cierra.
- Avisos al jugador con `exports.rp_notify:notify(player, texto, "success"|"error"|"warning"|"info")`.

## Estilo Lua

- Lua 5.1. `local` siempre; nada de globales salvo exports y tablas de config compartidas.
- Textos al jugador en español, sin depender de tildes en identificadores.
- Configuración (precios, coordenadas, tiempos) en `shared/s_config.lua`, no repartida por el código.
- Nada de `setTimer` por jugador sin limpiarlo en `onPlayerQuit` / `rp:onCharacterLogout`.
