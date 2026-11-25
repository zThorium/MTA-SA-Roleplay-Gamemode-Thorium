---
name: crear-recurso
description: Crear un recurso rp_* nuevo del gamemode Thorium (MTA:SA 1.6) o añadir un sistema grande a uno existente - diseño, integración con los sistemas de la GM (personaje, dinero, inventario, facciones, búsqueda, HUD, niveles), estructura, meta.xml, servidor, cliente, pruebas, registro en mtaserver.conf y documentación. Úsala SIEMPRE que haya que añadir un sistema, trabajo, actividad, tienda, minijuego o recurso nuevo al servidor.
---

# Crear un recurso nuevo en Thorium

Thorium es un roleplay **por personaje**: casi todo cuelga de `characters.id`, no de la cuenta ni del
jugador. Un recurso nuevo no es una isla: se engancha al ciclo de vida de la GM y **reutiliza** los
sistemas que ya existen (dinero, inventario, avisos, facciones, búsqueda, HUD...). Esta skill es el
mapa para hacerlo bien a la primera.

Archivos de apoyo (léelos cuando la fase lo pida, no todos de golpe):

| Archivo | Qué tiene |
|---|---|
| [`referencia/API.md`](referencia/API.md) | Exports reales de cada recurso con firma y retorno, y eventos del ciclo de vida |
| [`referencia/REGISTROS.md`](referencia/REGISTROS.md) | Lo que está "ocupado": dimensiones, teclas, elementData, blips, niveles de admin, orden de arranque |
| [`plantillas/`](plantillas/) | `meta.xml`, `s_config.lua`, `s_main.lua`, `c_main.lua` y prueba de `rp_test` listos para copiar |

Skills hermanas: **migracion-bd** (tablas), **interfaz-cef** (paneles HTML), **comando-admin**
(cualquier `/comando` y elementos que colocan los admins), **crear-mision** (todo lo de `rp_missions`).

---

## Fase 0 · ¿Hace falta un recurso nuevo?

1. Lee `RECURSOS.md` y `docs/PLAN_MVP.md`, y revisa los PR abiertos (`gh pr list`). Muchas ideas ya
   existen a medias o encajan como ampliación:
   - ¿Un trabajo civil? → va en `rp_jobs` (API en `docs/TRABAJOS.md`), no en un recurso nuevo.
   - ¿Una tienda que vende items? → `rp_shops` (o `addTempShop` para puestos temporales).
   - ¿Una misión o cinemática? → `rp_missions` con la skill **crear-mision**.
   - ¿Un evento del mundo (accidente, fiesta)? → `exports.rp_events:registerEvent`.
   - ¿Un item nuevo con efecto? → catálogo de `rp_inventory` + `rp:onItemUse`.
2. Crea recurso nuevo solo si es un **sistema** con estado y reglas propias (gimnasio, pool, carreras).
3. Si dudas entre ampliar y crear, pregunta a Fabián con la recomendación.

## Fase 1 · Diseño corto (antes de escribir código)

Escribe (en la conversación, o en `docs/<SISTEMA>.md` si es grande) estas respuestas. Son las que
luego deciden la estructura:

| Pregunta | Por qué importa |
|---|---|
| ¿Qué hace el jugador, paso a paso, y qué ve? | Define cliente, teclas y UI |
| ¿Qué persiste entre reinicios y qué es solo memoria? | Tablas (migracion-bd) vs. tablas Lua |
| ¿De quién es cada dato: personaje, propiedad, facción, global? | Columna `character_id` + `ON DELETE CASCADE` |
| ¿Cuesta o paga dinero? ¿Efectivo, banco o tarjeta? | Patrón de cobro (abajo) |
| ¿Da o quita items? ¿Cuáles nuevos hacen falta? | Catálogo de `rp_inventory` |
| ¿Quién puede usarlo: todos, una facción/permiso, admins? | `hasFactionPermission`, nivel admin |
| ¿Ocurre en un interior o instancia propia? | Dimensión libre (ver `REGISTROS.md`) |
| ¿Es ilegal? ¿Lo ve la policía? | `rp_wanted:reportCrime`, `rp_police:dispatchAlert` |
| ¿Qué pasa si el jugador sale, cambia de personaje, queda abatido o se reinicia el recurso a mitad? | Limpieza y rehidratación |
| ¿Qué teclas, comandos y blips usa? | Comprobar que no chocan (`REGISTROS.md`) |
| ¿Da XP o progreso? | `rp_levels:giveXP` |

## Fase 2 · Nombre, dependencias y estructura

- Nombre `rp_<sistema>` en minúsculas, corto (`rp_gym`, `rp_pool`). Prefijo de eventos `rp:<sistema>:`
  y de elementData `rp:<algo>`.
- Dependencias: incluye **solo** los recursos cuyos exports llamas (casi siempre `rp_database`,
  `rp_notify`, `rp_login`, `rp_characters`; mira `API.md` para el resto). `<include>` garantiza que
  arrancan antes.

```
resources/[roleplay]/rp_<sistema>/
  meta.xml
  shared/s_config.lua        CONFIG en MAYÚSCULAS: precios, coords, tiempos, textos ajustables
  server/s_config.lua        config que el cliente NO debe ver (premios, probabilidades, posiciones de botín)
  server/s_<sistema>.lua     estado, validación, BD, exports
  server/s_admin.lua         comandos de admin (si los hay; skill comando-admin)
  client/c_<sistema>.lua     teclas, dx, efectos (solo si hace falta)
  html/                      solo si hay CEF (skill interfaz-cef)
```

Recursos pequeños y solo servidor pueden tener los `.lua` en la raíz. Si un archivo pasa de ~600
líneas, pártelo por responsabilidad (`s_machines.lua`, `s_trainers.lua` como en `rp_gym`).

Copia las plantillas de [`plantillas/`](plantillas/) y renombra `sistema`/`SISTEMA`.

## Fase 3 · Base de datos

Si algo persiste → skill **migracion-bd** (entrada nueva **al final** de `rp_database/schema.lua`,
idempotente, nunca editar las anteriores). Recuerda:

- Datos del personaje: tabla con `character_id INT NOT NULL` + `FOREIGN KEY ... REFERENCES characters(id) ON DELETE CASCADE`.
- Puntos que colocan los admins (`/crear...`): tabla con `x, y, z, rot, interior, dimension`.
- Carga al arrancar esperando a la BD; escribe en el momento de la acción (no solo al salir: el servidor puede caerse).
- `dbPoll(qh, -1)` está prohibido en flujo normal. Única excepción tolerada: un **export** que debe
  devolver un valor a otro recurso (los exports no aceptan callbacks), como `rp_bank:chargeAccount`.
  Si lo haces, documéntalo en el comentario del export.

## Fase 4 · Servidor

Parte de [`plantillas/s_main.lua`](plantillas/s_main.lua). Lo que **siempre** debe tener:

1. **Arranque**: espera a la BD (`isReady()` o `rp:onDatabaseReady`) y **rehidrata a los jugadores
   que ya están dentro** (reiniciar el recurso en caliente es lo normal en desarrollo).
2. **Ciclo de vida** (`API.md` › Eventos):
   - `rp:onCharacterSpawn` (source = jugador, args `characterId, name`) → cargar estado del personaje.
   - `rp:onCharacterLogout` (args `characterId`) **y** `onPlayerQuit` → guardar y limpiar.
   - `rp:onPlayerDowned` → cortar lo que el jugador esté haciendo si no tiene sentido estando abatido.
   - `onResourceStop` → destruir lo creado fuera de `resourceRoot`, devolver controles, cerrar sesiones.
3. **Identidad**: `exports.rp_characters:getPlayerCharacterId(p)`; si es `nil`, no hay personaje y no se hace nada.
4. **Eventos remotos**: `addEvent(nombre, true)` solo para lo que el cliente dispara. En el handler
   el jugador es **`client`**, nunca `source`. Revalidar: tipo, rango, cooldown, personaje,
   cercanía (posición + interior + dimensión), item, dinero, permiso, estado (abatido, esposado, en misión).
5. **Dinero** (elige uno, nunca inventes otro):
   - Efectivo: `if getPlayerMoney(p) < n then ... end; takePlayerMoney(p, n); exports.rp_characters:saveCharacter(p)`.
     Pagar: `givePlayerMoney` + `saveCharacter`.
   - Banco: `UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?`
     y entregar solo si `affectedRows > 0` (o `exports.rp_bank:chargeAccount(charId, n, "Concepto")`).
   - Tarjeta de débito con PIN (datafono): `exports.rp_bank:payWithCard(p, ownerId, pin, n, concepto)`.
   - Ingreso al banco: `exports.rp_bank:deposit` no sirve (exige efectivo); haz `UPDATE ... + ?` y
     registra en `bank_transactions` como hace `rp_payday`.
   - **Orden**: primero cobrar (y comprobar), después entregar. Si la entrega falla, devolver el dinero.
6. **Items**: `local ok, why = exports.rp_inventory:canCarry(p, id, n)` antes de cobrar; luego
   `giveItem`/`takeItem` (devuelven `true` o `false, motivo`). Items nuevos van en
   `rp_inventory/shared/s_items.lua`; con `use = { event = true }` se gestionan en tu recurso con `rp:onItemUse`.
7. **Avisos**: `exports.rp_notify:notify(p, texto, "success"|"error"|"warning"|"info")`, `popup` para
   avisos importantes, `bubble` para globos sobre un ped. Nada de `outputChatBox` para feedback de acciones.
8. **Logs**: `outputDebugString("[rp_sistema] ...")` (nivel 1 error, 2 aviso, 3 info). Acciones de
   admin y movimientos grandes de dinero: también a la BD si hay que auditarlos.

## Fase 5 · Cliente

Parte de [`plantillas/c_main.lua`](plantillas/c_main.lua).

- Teclas con `bindKey` en `onClientResourceStart`; ignorar si
  `isCursorShowing() or isChatBoxInputActive() or isConsoleActive()`, si el jugador está abatido
  (`exports.rp_injury:isLocalPlayerDowned()`) o con el HUD suprimido (cinemática).
- **E** es la tecla universal de interacción y la usan 15 recursos: solo actúa si estás junto a
  **tu** punto, y nunca consumas la tecla fuera de él. Antes de usar otra tecla, mira `REGISTROS.md`.
- Aviso "Pulsa E para..." con dx, como `rp_shops/client/c_shops.lua`, solo en la dimensión/interior correcta.
- Ocultar HUD / silenciar radio: **solo** `exports.rp_hud:setHudSuppressed("rp_sistema", true/false)` y
  `exports.rp_radio:setRadioSuppressed("rp_sistema", true/false)`. Nunca toques `rp:hudHidden` ni la
  radio nativa. Libera siempre la supresión en `onClientResourceStop`.
- Blips: `rp_hud` solo dibuja los iconos de su lista `KNOWN_BLIP_ICON_IDS`. Usa uno existente
  (`REGISTROS.md`) o añade el icono y su PNG en `rp_hud/images/blips/` en el mismo PR.
- `onClientRender` lo más barato posible: precalcula, cachea texturas y fuentes, y no recorras
  `getElementsByType` cada frame si puedes mantener una lista.
- Panel HTML → skill **interfaz-cef**.

## Fase 6 · Integración con el resto de la GM

Repasa esta lista; cada "sí" es una línea de código que falta:

- [ ] ¿Es delito? → `exports.rp_wanted:reportCrime(p, clave, victima, dontCare, witnessed)` o `setWantedLevel`.
- [ ] ¿Debe enterarse la policía? → `exports.rp_police:dispatchAlert(clave, x, y, z, extra, jugador)`
      (claves de `POLICE_CODES` en `rp_police`; si necesitas una nueva, añádela allí).
- [ ] ¿Requiere licencia/DNI? → `rp_driving:hasDriverLicense`, `rp_agency:hasPlayerDNI`.
- [ ] ¿Solo para una facción o rol? → `rp_factions:getPlayerFaction` / `hasFactionPermission(p, "clave")`.
- [ ] ¿Afecta a hambre/sed/energía? → `rp_needs:addNeed(p, "hunger"|"thirst"|"energy", n)`.
- [ ] ¿Da progreso? → `rp_levels:giveXP(p, n, "motivo")`.
- [ ] ¿Usa un vehículo? → los personales son de `rp_vehicles` (llaves, combustible); los temporales
      los creas tú, con dueño en una tabla Lua, y los destruyes al terminar/salir.
- [ ] ¿Choca con estar abatido, esposado (`rp_police:isCuffed`), en misión (`rp_missions:getPlayerMission`),
      en carrera (`rp_races:getPlayerRace`) o en un robo (`rp_robbery:isPlayerRobbing`)? → bloquéalo.
- [ ] ¿Tiene comandos de admin? → skill **comando-admin** + entrada en `rp_adminpanel/server/s_catalog.lua`.
- [ ] ¿Tiene teclas o comandos de jugador? → añádelos al panel de ayuda (`rp_help/shared/s_config.lua`).

## Fase 7 · Pruebas

- Servidor: añade pruebas en `resources/[test]/rp_test/server/` (ver
  [`plantillas/s_tests_sistema.lua`](plantillas/s_tests_sistema.lua)) que reproduzcan las consultas
  del recurso contra la BD real, sobre todo cobros, tablas nuevas y exports. Ejecuta `scripts/test.sh`
  (Docker) o `start rp_test` / `rptest` en la consola; debe terminar en `FIN OK`.
- Arranque limpio: `refresh` → `restart rp_sistema` sin errores en consola.
- Reinicio en caliente con un personaje dentro: el estado se rehidrata y no quedan elementos huérfanos.
- Cliente: **no hay tests**. Di explícitamente a Fabián qué probar en juego (flujo feliz + errores:
  sin dinero, lejos, sin permiso, abatido, salir a mitad) con `/debugscript 3` limpio.

## Fase 8 · Registrar y documentar (mismo PR)

1. `mtaserver.conf`: `<resource src="rp_sistema" startup="1" protected="0" />` **después** de todas
   sus dependencias (orden actual en `REGISTROS.md`).
2. `RECURSOS.md`: fila con qué hace, teclas, exports, eventos, tablas, comandos de jugador y de admin.
3. `CLAUDE.md` › "Recursos actuales": añadir el recurso en su categoría.
4. `README.md` si es visible para jugadores; `docs/PLAN_MVP.md` si cierra un punto; `docs/<SISTEMA>.md`
   si tiene reglas de diseño que no caben en una fila.
5. Si ocupas dimensión, tecla, elementData o blip nuevos, **actualiza `referencia/REGISTROS.md`** de esta skill.
6. Si exportas algo, añádelo a `referencia/API.md`.

## Checklist final antes del PR

- [ ] Rama `feat/rp-sistema` desde `main` actualizado; commits y PR en español contando qué cambia en el juego.
- [ ] Ningún `dbConnect`, ningún SQL concatenado, ningún `dbPoll(qh, -1)` fuera de un export justificado.
- [ ] Todo evento remoto usa `client`, convierte y acota argumentos, tiene cooldown y revalida cercanía/estado.
- [ ] Cobro antes de entregar, atómico en banco, `saveCharacter` tras tocar efectivo.
- [ ] Sin globales sueltas (solo la config compartida y las funciones exportadas).
- [ ] Timers, colshapes, peds, vehículos, binds y supresiones de HUD/radio se limpian al salir, al
      cambiar de personaje, al quedar abatido y en `onResourceStop`.
- [ ] Dimensión, teclas y blips sin choques (`REGISTROS.md`).
- [ ] `scripts/test.sh` en `FIN OK`; consola limpia en `restart`.
- [ ] Docs actualizadas (fase 8) y aviso a Fabián de lo que debe probar en el cliente.
- [ ] Sin secretos, IPs, emails ni material de Rockstar en el repo.

Si al crear un recurso descubres una forma mejor de hacer algo, **actualiza esta skill en el mismo PR**.
