---
name: comando-admin
description: Añadir comandos de jugador o de administración a un recurso del gamemode Thorium, incluidos los que crean o borran elementos persistentes en el mundo (tiendas, cajeros, casas, puntos). Úsala al crear cualquier /comando.
---

# Comandos de jugador y de admin

Referencias: `rp_shops` (`/crearshop`, `/borrarshop`), `rp_bank` (`/crearatm`, `/dardinero`),
`rp_payday` (`/forzarpayday`), `rp_factions` (`/crearfaccion`, `/setlider`).

## Reglas

- Comandos **de jugador en español**, minúsculas, sin tildes ni guiones: `/vendercasa`, `/cerrarcasa`.
- Comandos **de admin con la sintaxis de OwlGaming** (en inglés), que es la que conoce el staff que viene de Owl/Valhalla:
  - Elementos que colocan los admins: **no escribas los comandos a mano**. Expón en el recurso los exports
    `adminElements(kind)` (lista `{ id, x, y, z, interior, dimension, label }`) y `adminDelete(id, kind)` (`true` o `false, motivo`)
    y añade una fila a `WORLD_TYPES` en `rp_admin/s_world.lua`. Con eso salen solos `/nearby<tipos>`, `/goto<tipo>`,
    `/del<tipo>`, `/delthis<tipo>`, `/delnearby<tipos>` y el tipo aparece en `/nearby`. Ejemplo: `rp_bank` (`atm`).
  - Crear: `/make<cosa>` o `/add<cosa>`. Cambiar un valor de un jugador: `/set<valor> <jugador> <valor>` (`/setint`, `/setdim`).
    Dar/quitar: `/give<cosa>`, `/take<cosa>`. Buscar: `/find<cosa>`. Prefijos de sanción: `p` jugador (`/pkick`),
    `s` sin aviso global (`/sban`), `o` cuenta desconectada (`/oban`).
  - Los comandos de admin antiguos en español (`/crearatm`, `/borrarcasa`) se mantienen como alias; no los borres.
- Niveles (`accounts.admin_level`): 1 admin, 2 admin senior (datos sensibles: serial, IP, multicuentas), 3 super admin (baneos, borrados masivos).
  En `rp_admin` usa `guard(player, nivel)`.
- Todo comando se registra en el servidor con `addCommandHandler`; el cliente nunca decide permisos.
- Admin: `accounts.admin_level >= 1`. Si un comando necesita otro nivel,
  usa una constante en el config del recurso y documéntala en `RECURSOS.md`.
- Respuestas con `rp_notify`. `outputChatBox` solo para listados largos o chats (`/facciones`, `/f`, `/id`):
  - sin permiso → `"No tienes permiso para usar este comando.", "error"`
  - uso incorrecto → `"Uso: /comando <arg> (aclaración)", "warning"`
  - éxito → mensaje con el id/nombre afectado, `"success"`
- Jugadores objetivo con `exports.rp_ids:findPlayer(query)` (acepta ID o parte del nombre).
- Comandos de jugador que requieren personaje: si `getPlayerCharacterId` es `nil`, no hacer nada.

## Plantilla

```lua
local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

addCommandHandler("darcosa", function(player, _, query, amount)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local target = query and exports.rp_ids:findPlayer(query)
    amount = tonumber(amount)
    if not target or not amount or amount < 1 or amount ~= math.floor(amount) then
        return notify(player, "Uso: /darcosa <id o nombre> <cantidad>", "warning")
    end
    if not exports.rp_characters:getPlayerCharacterId(target) then
        return notify(player, "Ese jugador no tiene un personaje en juego.", "warning")
    end
    -- acción
    notify(player, ("Diste %d a %s."):format(amount, (getPlayerName(target):gsub("_", " "))), "success")
end)

-- Argumento de texto libre (nombres con espacios)
addCommandHandler("crearcosa", function(player, _, ...)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local name = table.concat({ ... }, " ")
    if #name < 3 or #name > 48 then return notify(player, "Uso: /crearcosa <nombre>", "warning") end
    -- ...
end)
```

## Elementos persistentes colocados por admins

Patrón de `rp_shops`: la fila en SQL es la verdad, el mundo se reconstruye desde ella.

1. Tabla con `x, y, z, rotation, interior, dimension` (skill **migracion-bd**).
2. `spawnX(row)` crea ped/objeto/colshape/blip y los guarda en `cosas[id] = { row, ped, col, blip }`.
   `destroyX(id)` destruye todo y borra la entrada.
3. Al arrancar (tras `rp:onDatabaseReady`) se cargan todas las filas y se llama a `spawnX`.
4. `/crearX`: toma `getElementPosition`, `getElementRotation`, `getElementInterior`, `getElementDimension`
   del admin, hace `INSERT` con `dbQuery` y, con el `insertId`, llama a `spawnX`. Aparta al admin si
   quedaría dentro del ped.
5. `/borrarX <id>`: valida que exista en la tabla en memoria, `DELETE` y `destroyX(id)`.
6. Si la BD está vacía y el sistema necesita un mínimo, crea un elemento por defecto al cargar.
7. Interacción con `createColSphere` + `onColShapeHit`/`onColShapeLeave` (comprobando `sameDim`) y avisando
   al cliente con `triggerClientEvent(el, "rp:x:near", resourceRoot, id)`; el servidor vuelve a comprobar la
   distancia al ejecutar la acción.

## Al terminar

- Añade el comando de admin al catálogo del panel: `resources/[roleplay]/rp_adminpanel/server/s_catalog.lua`.
- Añade los comandos a la fila del recurso en `RECURSOS.md` (separando los de admin con "Admin:").
- Pruébalos con una cuenta sin `admin_level` (debe rechazar) y con una de nivel 1.
