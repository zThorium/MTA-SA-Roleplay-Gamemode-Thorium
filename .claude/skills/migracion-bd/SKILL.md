---
name: migracion-bd
description: Añadir o cambiar tablas, columnas o índices de la base de datos MySQL/MariaDB del gamemode Thorium mediante rp_database/schema.lua. Úsala siempre que un cambio necesite persistir datos nuevos.
---

# Migraciones de base de datos

No hay archivos `.sql` ni herramienta de migraciones. `resources/[roleplay]/rp_database/schema.lua`
define `SCHEMA`, una lista de sentencias que `s_database.lua` ejecuta **en orden en cada arranque**.
Si una falla se registra en consola y sigue con la siguiente. Luego dispara `rp:onDatabaseReady`.

## Reglas

1. **Solo se añade al final de `SCHEMA`.** Nunca edites, borres ni reordenes una entrada que ya está en `main`:
   ya se aplicó en las bases de los demás y no se volvería a ejecutar con otro contenido.
2. **Toda sentencia es idempotente** (se ejecuta en cada arranque):
   - `CREATE TABLE IF NOT EXISTS`
   - `ALTER TABLE x ADD COLUMN IF NOT EXISTS ...`
   - `ADD INDEX IF NOT EXISTS` / `ADD UNIQUE INDEX IF NOT EXISTS`
   - `MODIFY COLUMN` (re-aplicarlo es inocuo)
   - Datos semilla: `INSERT IGNORE` con clave única.
   Prohibido `DROP` de tablas o columnas con datos; si algo deja de usarse, se deja.
3. Cada entrada lleva encima un comentario `-- <recurso>: para qué es`.
4. Para cambiar una columna existente, **otra entrada nueva** al final con su `ALTER`.
5. Si una tabla nueva referencia otra, debe ir después de ella en la lista.

## Plantilla de tabla

```lua
    -- rp_sistema: qué guarda
    [[
    CREATE TABLE IF NOT EXISTS sistema_cosas (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED NOT NULL,
        nombre       VARCHAR(48)  NOT NULL,
        x            FLOAT        NOT NULL,
        y            FLOAT        NOT NULL,
        z            FLOAT        NOT NULL,
        interior     TINYINT UNSIGNED  NOT NULL DEFAULT 0,
        dimension    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_sistema_cosas_character (character_id),
        CONSTRAINT fk_sistema_cosas_character FOREIGN KEY (character_id)
            REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
```

Convenciones:
- Tablas en plural, `snake_case`, prefijadas por el sistema si no son genéricas (`faction_ranks`, `phone_notes`).
- `id INT UNSIGNED AUTO_INCREMENT`; claves foráneas `<tabla>_id` con `fk_<tabla>_<ref>` e índices `idx_...`/`uq_...`.
- Datos de jugador **por personaje** (`character_id` → `characters`, `ON DELETE CASCADE`), no por cuenta,
  salvo cosas de cuenta (`accounts`, `login_log`).
- Dinero en `INT` (sin decimales). Posiciones `FLOAT` + `interior` + `dimension`.
- Permisos como bitmask en `INT UNSIGNED` con las constantes en `shared/s_config.lua` (ver `rp_factions`).

## Plantilla de columna nueva

```lua
    -- rp_sistema: minutos acumulados de X
    [[
    ALTER TABLE characters
        ADD COLUMN IF NOT EXISTS sistema_minutos SMALLINT UNSIGNED NOT NULL DEFAULT 0 AFTER energy
    ]],
```

Siempre con `DEFAULT` (o `NULL`) para que las filas existentes sigan siendo válidas.

## Usar las tablas desde un recurso

```lua
local function db() return exports.rp_database:getConnection() end

-- lectura
dbQuery(function(qh)
    local rows = dbPoll(qh, 0) or {}
end, db(), "SELECT * FROM sistema_cosas WHERE character_id = ?", characterId)

-- insert con id
dbQuery(function(qh)
    local result, _, insertId = dbPoll(qh, 0)
    if not result then return outputDebugString("[rp_sistema] Error al insertar", 1) end
end, db(), "INSERT INTO sistema_cosas (character_id, nombre, x, y, z) VALUES (?, ?, ?, ?, ?)", characterId, nombre, x, y, z)

-- escritura sin respuesta
dbExec(db(), "UPDATE sistema_cosas SET nombre = ? WHERE id = ?", nombre, id)

-- cobro atómico
dbQuery(function(qh)
    local _, affected = dbPoll(qh, 0)
    if not (affected and affected > 0) then return notify(player, "Saldo insuficiente.", "error") end
    -- entregar
end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", precio, characterId, precio)
```

- Siempre `?`. Nunca `..` para meter valores en SQL.
- Siempre asíncrono con callback y `dbPoll(qh, 0)`. Nunca `dbPoll(qh, -1)`.
- Dentro del callback comprueba `isElement(player)` y que siga con el mismo personaje antes de tocarlo.
- Si el recurso lee al arrancar, espera a `exports.rp_database:isReady()` o `rp:onDatabaseReady`.

## Después del cambio

1. Sincroniza y reinicia `rp_database` (o el servidor). En consola: `Esquema verificado (N sentencias)` sin errores.
2. Comprueba la tabla en phpMyAdmin.
3. Añade la tabla a la lista de `RECURSOS.md` (sección Base de datos) y de `docs/CONVENCIONES.md`.
