--[[
    rp_database / schema.lua

    Tablas del gamemode. Se crean con CREATE TABLE IF NOT EXISTS al iniciar el
    recurso, asi una base de datos vacia queda lista sin pasos manuales.
    Para cambios futuros de columnas agrega nuevas entradas al final (ALTER ...)
    en lugar de modificar las existentes.
]]

SCHEMA = {
    [[
    CREATE TABLE IF NOT EXISTS accounts (
        id            INT UNSIGNED      NOT NULL AUTO_INCREMENT,
        username      VARCHAR(24)       NOT NULL,
        password_hash VARCHAR(255)      NOT NULL,
        serial        CHAR(32)          NULL,
        ip            VARCHAR(45)       NULL,
        admin_level   TINYINT UNSIGNED  NOT NULL DEFAULT 0,
        skin          SMALLINT UNSIGNED NOT NULL DEFAULT 26,
        money         INT               NOT NULL DEFAULT 500,
        health        FLOAT             NOT NULL DEFAULT 100,
        armor         FLOAT             NOT NULL DEFAULT 0,
        pos_x         FLOAT             NULL,
        pos_y         FLOAT             NULL,
        pos_z         FLOAT             NULL,
        rotation      FLOAT             NOT NULL DEFAULT 0,
        interior      TINYINT UNSIGNED  NOT NULL DEFAULT 0,
        dimension     SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        created_at    DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_login    DATETIME          NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uq_accounts_username (username),
        KEY idx_accounts_serial (serial)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS login_log (
        id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
        account_id INT UNSIGNED NULL,
        username   VARCHAR(24)  NOT NULL,
        serial     CHAR(32)     NULL,
        ip         VARCHAR(45)  NULL,
        success    TINYINT(1)   NOT NULL,
        created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_login_log_account (account_id),
        CONSTRAINT fk_login_log_account FOREIGN KEY (account_id)
            REFERENCES accounts (id) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS characters (
        id          INT UNSIGNED      NOT NULL AUTO_INCREMENT,
        account_id  INT UNSIGNED      NOT NULL,
        name        VARCHAR(32)       NOT NULL,
        gender      TINYINT UNSIGNED  NOT NULL DEFAULT 0,
        age         TINYINT UNSIGNED  NOT NULL,
        weight      SMALLINT UNSIGNED NOT NULL,
        height      SMALLINT UNSIGNED NOT NULL,
        origin      VARCHAR(48)       NOT NULL,
        story       TEXT              NOT NULL,
        skin        SMALLINT UNSIGNED NOT NULL,
        money       INT               NOT NULL DEFAULT 500,
        health      FLOAT             NOT NULL DEFAULT 100,
        armor       FLOAT             NOT NULL DEFAULT 0,
        pos_x       FLOAT             NULL,
        pos_y       FLOAT             NULL,
        pos_z       FLOAT             NULL,
        rotation    FLOAT             NOT NULL DEFAULT 0,
        interior    TINYINT UNSIGNED  NOT NULL DEFAULT 0,
        dimension   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        created_at  DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_played DATETIME          NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uq_characters_name (name),
        KEY idx_characters_account (account_id),
        CONSTRAINT fk_characters_account FOREIGN KEY (account_id)
            REFERENCES accounts (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Hito 3: apariencia personalizada (cabeza + ropa de CJ) para hombres
    [[
    ALTER TABLE characters
        ADD COLUMN IF NOT EXISTS race          TINYINT UNSIGNED  NULL AFTER skin,
        ADD COLUMN IF NOT EXISTS head          SMALLINT UNSIGNED NULL AFTER race,
        ADD COLUMN IF NOT EXISTS clothes_torso SMALLINT UNSIGNED NULL AFTER head,
        ADD COLUMN IF NOT EXISTS clothes_legs  SMALLINT UNSIGNED NULL AFTER clothes_torso,
        ADD COLUMN IF NOT EXISTS clothes_shoes SMALLINT UNSIGNED NULL AFTER clothes_legs
    ]],
    -- Hito 4: inventario por personaje (el catalogo de items vive en rp_inventory/shared/s_items.lua)
    [[
    CREATE TABLE IF NOT EXISTS character_items (
        character_id INT UNSIGNED NOT NULL,
        item_id      VARCHAR(32)  NOT NULL,
        amount       INT UNSIGNED NOT NULL,
        updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id, item_id),
        CONSTRAINT fk_items_character FOREIGN KEY (character_id)
            REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Hito 5: necesidades del personaje (0-100)
    [[
    ALTER TABLE characters
        ADD COLUMN IF NOT EXISTS hunger TINYINT UNSIGNED NOT NULL DEFAULT 100 AFTER armor,
        ADD COLUMN IF NOT EXISTS thirst TINYINT UNSIGNED NOT NULL DEFAULT 100 AFTER hunger,
        ADD COLUMN IF NOT EXISTS energy TINYINT UNSIGNED NOT NULL DEFAULT 100 AFTER thirst
    ]],
    -- Hito 5: banco y telefono
    [[
    ALTER TABLE characters
        ADD COLUMN IF NOT EXISTS bank_money   INT          NOT NULL DEFAULT 0 AFTER money,
        ADD COLUMN IF NOT EXISTS phone_number INT UNSIGNED NULL AFTER bank_money,
        ADD UNIQUE INDEX IF NOT EXISTS uq_characters_phone (phone_number)
    ]],
    [[
    CREATE TABLE IF NOT EXISTS bank_transactions (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED NOT NULL,
        type         VARCHAR(16)  NOT NULL,
        amount       INT          NOT NULL,
        other_name   VARCHAR(32)  NULL,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_bank_tx_character (character_id, id),
        CONSTRAINT fk_bank_tx_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS atms (
        id        INT UNSIGNED      NOT NULL AUTO_INCREMENT,
        x         FLOAT             NOT NULL,
        y         FLOAT             NOT NULL,
        z         FLOAT             NOT NULL,
        rotation  FLOAT             NOT NULL DEFAULT 0,
        interior  TINYINT UNSIGNED  NOT NULL DEFAULT 0,
        dimension SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS phone_notes (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED NOT NULL,
        title        VARCHAR(64)  NOT NULL,
        body         TEXT         NOT NULL,
        updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_notes_character (character_id),
        CONSTRAINT fk_notes_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS phone_contacts (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED NOT NULL,
        name         VARCHAR(32)  NOT NULL,
        number       INT UNSIGNED NOT NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uq_contacts (character_id, number),
        CONSTRAINT fk_contacts_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- App de viajes (rp_rides): conductores con su calificacion y viajes realizados
    [[
    CREATE TABLE IF NOT EXISTS ride_drivers (
        character_id INT UNSIGNED NOT NULL,
        rating_sum   INT UNSIGNED NOT NULL DEFAULT 0,
        rating_count INT UNSIGNED NOT NULL DEFAULT 0,
        rides        INT UNSIGNED NOT NULL DEFAULT 0,
        earnings     INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (character_id),
        CONSTRAINT fk_ride_drivers_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- driver_id NULL = conductor IA
    [[
    CREATE TABLE IF NOT EXISTS rides (
        id           INT UNSIGNED     NOT NULL AUTO_INCREMENT,
        passenger_id INT UNSIGNED     NOT NULL,
        driver_id    INT UNSIGNED     NULL,
        fare         INT UNSIGNED     NOT NULL,
        tip          INT UNSIGNED     NOT NULL DEFAULT 0,
        rating       TINYINT UNSIGNED NULL,
        distance     INT UNSIGNED     NOT NULL DEFAULT 0,
        created_at   DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_rides_passenger (passenger_id),
        KEY idx_rides_driver (driver_id),
        CONSTRAINT fk_rides_passenger FOREIGN KEY (passenger_id) REFERENCES characters (id) ON DELETE CASCADE,
        CONSTRAINT fk_rides_driver FOREIGN KEY (driver_id) REFERENCES characters (id) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS social_posts (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED NOT NULL,
        caption      VARCHAR(280) NOT NULL,
        image        MEDIUMTEXT   NOT NULL,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        CONSTRAINT fk_posts_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS social_likes (
        post_id      INT UNSIGNED NOT NULL,
        character_id INT UNSIGNED NOT NULL,
        PRIMARY KEY (post_id, character_id),
        CONSTRAINT fk_likes_post FOREIGN KEY (post_id) REFERENCES social_posts (id) ON DELETE CASCADE,
        CONSTRAINT fk_likes_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Hito 5: propiedades (interiores comprables)
    [[
    CREATE TABLE IF NOT EXISTS properties (
        id            INT UNSIGNED     NOT NULL AUTO_INCREMENT,
        name          VARCHAR(48)      NOT NULL,
        type          VARCHAR(24)      NOT NULL,
        price         INT UNSIGNED     NOT NULL,
        x             FLOAT            NOT NULL,
        y             FLOAT            NOT NULL,
        z             FLOAT            NOT NULL,
        owner_id      INT UNSIGNED     NULL,
        locked        TINYINT(1)       NOT NULL DEFAULT 1,
        created_at    DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_properties_owner (owner_id),
        CONSTRAINT fk_properties_owner FOREIGN KEY (owner_id) REFERENCES characters (id) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Hito 6: interior propio por propiedad (casas originales de GTA) y origen del dato
    [[
    ALTER TABLE properties
        ADD COLUMN IF NOT EXISTS int_id TINYINT UNSIGNED NULL AFTER z,
        ADD COLUMN IF NOT EXISTS ix     FLOAT NULL AFTER int_id,
        ADD COLUMN IF NOT EXISTS iy     FLOAT NULL AFTER ix,
        ADD COLUMN IF NOT EXISTS iz     FLOAT NULL AFTER iy,
        ADD COLUMN IF NOT EXISTS irot   FLOAT NULL AFTER iz,
        ADD COLUMN IF NOT EXISTS source VARCHAR(8) NOT NULL DEFAULT 'admin' AFTER irot
    ]],
    -- Editor de rutas de ciudadanos: cambios sobre la red de caminos original de GTA SA
    -- type: 'p' peatones, 'v' vehiculos. idx: indice del nodo en c_nodes_ls.lua (o nuevo)
    [[
    CREATE TABLE IF NOT EXISTS path_nodes (
        type       CHAR(1)      NOT NULL,
        idx        INT UNSIGNED NOT NULL,
        x          FLOAT        NOT NULL,
        y          FLOAT        NOT NULL,
        z          FLOAT        NOT NULL,
        deleted    TINYINT(1)   NOT NULL DEFAULT 0,
        updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (type, idx)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS path_links (
        type    CHAR(1)      NOT NULL,
        a       INT UNSIGNED NOT NULL,
        b       INT UNSIGNED NOT NULL,
        removed TINYINT(1)   NOT NULL DEFAULT 0,
        PRIMARY KEY (type, a, b)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Tiendas de ropa con interior propio (rp_clothing). ix..irot: interior corregido en juego (NULL = el del tipo)
    [[
    CREATE TABLE IF NOT EXISTS clothing_stores (
        id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
        name       VARCHAR(48)  NOT NULL,
        type       VARCHAR(16)  NOT NULL,
        x          FLOAT        NOT NULL,
        y          FLOAT        NOT NULL,
        z          FLOAT        NOT NULL,
        ix         FLOAT        NULL,
        iy         FLOAT        NULL,
        iz         FLOAT        NULL,
        irot       FLOAT        NULL,
        created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Accesorios (toys) del personaje: hueso, posicion, rotacion y escala por eje
    [[
    CREATE TABLE IF NOT EXISTS character_toys (
        id           INT UNSIGNED     NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED     NOT NULL,
        toy          VARCHAR(32)      NOT NULL,
        bone         TINYINT UNSIGNED NOT NULL,
        x            FLOAT            NOT NULL DEFAULT 0,
        y            FLOAT            NOT NULL DEFAULT 0,
        z            FLOAT            NOT NULL DEFAULT 0,
        rx           FLOAT            NOT NULL DEFAULT 0,
        ry           FLOAT            NOT NULL DEFAULT 0,
        rz           FLOAT            NOT NULL DEFAULT 0,
        sx           FLOAT            NOT NULL DEFAULT 1,
        sy           FLOAT            NOT NULL DEFAULT 1,
        sz           FLOAT            NOT NULL DEFAULT 1,
        worn         TINYINT(1)       NOT NULL DEFAULT 0,
        created_at   DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_toys_character (character_id),
        CONSTRAINT fk_toys_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Hito 5: vehiculos de los personajes
    [[
    CREATE TABLE IF NOT EXISTS vehicles (
        id         INT UNSIGNED      NOT NULL AUTO_INCREMENT,
        owner_id   INT UNSIGNED      NOT NULL,
        model      SMALLINT UNSIGNED NOT NULL,
        plate      VARCHAR(8)        NOT NULL,
        color      VARCHAR(64)       NOT NULL,
        x          FLOAT             NOT NULL,
        y          FLOAT             NOT NULL,
        z          FLOAT             NOT NULL,
        rx         FLOAT             NOT NULL DEFAULT 0,
        ry         FLOAT             NOT NULL DEFAULT 0,
        rz         FLOAT             NOT NULL DEFAULT 0,
        interior   TINYINT UNSIGNED  NOT NULL DEFAULT 0,
        dimension  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        health     FLOAT             NOT NULL DEFAULT 1000,
        locked     TINYINT(1)        NOT NULL DEFAULT 1,
        created_at DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_vehicles_owner (owner_id),
        CONSTRAINT fk_vehicles_owner FOREIGN KEY (owner_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Hito 4: tiendas con NPC y su catalogo de venta
    [[
    CREATE TABLE IF NOT EXISTS shops (
        id         INT UNSIGNED      NOT NULL AUTO_INCREMENT,
        name       VARCHAR(48)       NOT NULL,
        ped_skin   SMALLINT UNSIGNED NOT NULL DEFAULT 211,
        x          FLOAT             NOT NULL,
        y          FLOAT             NOT NULL,
        z          FLOAT             NOT NULL,
        rotation   FLOAT             NOT NULL DEFAULT 0,
        interior   TINYINT UNSIGNED  NOT NULL DEFAULT 0,
        dimension  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        created_at DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS shop_items (
        shop_id INT UNSIGNED NOT NULL,
        item_id VARCHAR(32)  NOT NULL,
        price   INT UNSIGNED NOT NULL,
        PRIMARY KEY (shop_id, item_id),
        CONSTRAINT fk_shop_items_shop FOREIGN KEY (shop_id)
            REFERENCES shops (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Facciones: roles definidos por el lider con permisos (bitmask, ver rp_factions/shared/s_config.lua) y sueldo
    [[
    CREATE TABLE IF NOT EXISTS factions (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        name         VARCHAR(48)  NOT NULL,
        tag          VARCHAR(8)   NOT NULL,
        type         VARCHAR(16)  NOT NULL DEFAULT 'otra',
        color        CHAR(7)      NOT NULL DEFAULT '#f5a524',
        state_funded TINYINT(1)   NOT NULL DEFAULT 0,
        bank         INT          NOT NULL DEFAULT 0,
        motd         VARCHAR(255) NOT NULL DEFAULT '',
        leader_id    INT UNSIGNED NULL,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_factions_name (name),
        CONSTRAINT fk_factions_leader FOREIGN KEY (leader_id) REFERENCES characters (id) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS faction_ranks (
        id          INT UNSIGNED     NOT NULL AUTO_INCREMENT,
        faction_id  INT UNSIGNED     NOT NULL,
        name        VARCHAR(32)      NOT NULL,
        level       TINYINT UNSIGNED NOT NULL DEFAULT 1,
        salary      INT UNSIGNED     NOT NULL DEFAULT 0,
        permissions INT UNSIGNED     NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        UNIQUE KEY uq_faction_ranks_name (faction_id, name),
        CONSTRAINT fk_faction_ranks_faction FOREIGN KEY (faction_id) REFERENCES factions (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS faction_members (
        character_id INT UNSIGNED NOT NULL,
        faction_id   INT UNSIGNED NOT NULL,
        rank_id      INT UNSIGNED NULL,
        joined_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id),
        KEY idx_faction_members_faction (faction_id),
        CONSTRAINT fk_faction_members_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE,
        CONSTRAINT fk_faction_members_faction FOREIGN KEY (faction_id) REFERENCES factions (id) ON DELETE CASCADE,
        CONSTRAINT fk_faction_members_rank FOREIGN KEY (rank_id) REFERENCES faction_ranks (id) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS faction_log (
        id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
        faction_id INT UNSIGNED NOT NULL,
        text       VARCHAR(255) NOT NULL,
        created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_faction_log (faction_id, id),
        CONSTRAINT fk_faction_log_faction FOREIGN KEY (faction_id) REFERENCES factions (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Payday: minutos jugados desde el ultimo sueldo (se conservan entre sesiones)
    [[
    ALTER TABLE characters
        ADD COLUMN IF NOT EXISTS payday_minutes SMALLINT UNSIGNED NOT NULL DEFAULT 0 AFTER energy
    ]],
    -- Vehiculos personales: llaves, freno de mano, cepo policial, tuning y ultimo conductor
    [[
    ALTER TABLE vehicles
        ADD COLUMN IF NOT EXISTS key_given        TINYINT(1)   NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS handbrake        TINYINT(1)   NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS clamped          TINYINT(1)   NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS tuning           TEXT         NULL,
        ADD COLUMN IF NOT EXISTS last_driver_id   INT UNSIGNED NULL,
        ADD COLUMN IF NOT EXISTS last_driver_name VARCHAR(32)  NULL,
        ADD COLUMN IF NOT EXISTS last_driver_at   DATETIME     NULL
    ]],
    -- Maletero: items guardados en cada vehiculo
    [[
    CREATE TABLE IF NOT EXISTS vehicle_items (
        vehicle_id INT UNSIGNED NOT NULL,
        item_id    VARCHAR(32)  NOT NULL,
        amount     INT UNSIGNED NOT NULL,
        PRIMARY KEY (vehicle_id, item_id),
        CONSTRAINT fk_vehicle_items_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Golpes recibidos (se conservan 1 dia, rp_vehicles borra los viejos cada hora)
    [[
    CREATE TABLE IF NOT EXISTS vehicle_hits (
        id             INT UNSIGNED      NOT NULL AUTO_INCREMENT,
        vehicle_id     INT UNSIGNED      NOT NULL,
        character_id   INT UNSIGNED      NULL,
        character_name VARCHAR(32)       NOT NULL,
        weapon         SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        loss           FLOAT             NOT NULL DEFAULT 0,
        hits           SMALLINT UNSIGNED NOT NULL DEFAULT 1,
        created_at     DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_vehicle_hits_vehicle (vehicle_id, id),
        KEY idx_vehicle_hits_created (created_at),
        CONSTRAINT fk_vehicle_hits_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Quien se subio a cada vehiculo y en que asiento (se conserva 1 dia)
    [[
    CREATE TABLE IF NOT EXISTS vehicle_entries (
        id             INT UNSIGNED     NOT NULL AUTO_INCREMENT,
        vehicle_id     INT UNSIGNED     NOT NULL,
        character_id   INT UNSIGNED     NULL,
        character_name VARCHAR(32)      NOT NULL,
        seat           TINYINT UNSIGNED NOT NULL DEFAULT 0,
        created_at     DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_vehicle_entries_vehicle (vehicle_id, id),
        KEY idx_vehicle_entries_created (created_at),
        CONSTRAINT fk_vehicle_entries_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Policia: multas a vehiculos y registro de acciones (cepo, multas, pagos)
    [[
    CREATE TABLE IF NOT EXISTS vehicle_fines (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        vehicle_id   INT UNSIGNED NOT NULL,
        officer_id   INT UNSIGNED NULL,
        officer_name VARCHAR(32)  NOT NULL,
        amount       INT UNSIGNED NOT NULL,
        reason       VARCHAR(128) NOT NULL,
        paid         TINYINT(1)   NOT NULL DEFAULT 0,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        paid_at      DATETIME     NULL,
        PRIMARY KEY (id),
        KEY idx_vehicle_fines_vehicle (vehicle_id, paid),
        CONSTRAINT fk_vehicle_fines_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS vehicle_police_log (
        id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
        vehicle_id INT UNSIGNED NOT NULL,
        actor_name VARCHAR(32)  NOT NULL,
        text       VARCHAR(255) NOT NULL,
        created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_vehicle_police_log (vehicle_id, id),
        CONSTRAINT fk_vehicle_police_log_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Faccion 1 reservada para la Policia (necesita las tablas de rp_factions;
    -- si aun no existen, estas dos sentencias fallan sin bloquear el resto y se
    -- reintentan en el siguiente arranque).
    [[
    INSERT IGNORE INTO factions (id, name, tag, type, color, state_funded)
    VALUES (1, 'Policia de Los Santos', 'LSPD', 'policia', '#3b6fe0', 1)
    ]],
    [[
    INSERT IGNORE INTO faction_ranks (faction_id, name, level, salary, permissions)
    SELECT 1, r.name, r.level, r.salary, r.permissions FROM (
        SELECT 'Comisario' AS name, 10 AS level, 2000 AS salary, 1023 AS permissions
        UNION ALL SELECT 'Oficial', 1, 800, 1
    ) r
    WHERE EXISTS (SELECT 1 FROM factions WHERE id = 1 AND type = 'policia')
      AND NOT EXISTS (SELECT 1 FROM faction_ranks WHERE faction_id = 1)
    ]],
    -- Bencina de los vehiculos (NULL = tanque lleno) y tarjetas de debito
    [[
    ALTER TABLE vehicles
        ADD COLUMN IF NOT EXISTS fuel FLOAT NULL
    ]],
    [[
    CREATE TABLE IF NOT EXISTS bank_cards (
        character_id INT UNSIGNED NOT NULL,
        number       CHAR(16)     NOT NULL,
        pin          CHAR(4)      NOT NULL,
        holder       VARCHAR(32)  NOT NULL,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id),
        UNIQUE KEY uq_bank_cards_number (number),
        CONSTRAINT fk_bank_cards_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_injury: ms que le quedan abatido (0 = no esta abatido). Se retoma al volver a entrar
    [[
    ALTER TABLE characters
        ADD COLUMN IF NOT EXISTS downed_ms INT UNSIGNED NOT NULL DEFAULT 0 AFTER payday_minutes
    ]],
    -- Vehiculos personales: llaves, freno de mano, cepo policial, tuning y ultimo conductor
    [[
    ALTER TABLE vehicles
        ADD COLUMN IF NOT EXISTS key_given        TINYINT(1)   NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS handbrake        TINYINT(1)   NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS clamped          TINYINT(1)   NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS tuning           TEXT         NULL,
        ADD COLUMN IF NOT EXISTS last_driver_id   INT UNSIGNED NULL,
        ADD COLUMN IF NOT EXISTS last_driver_name VARCHAR(32)  NULL,
        ADD COLUMN IF NOT EXISTS last_driver_at   DATETIME     NULL
    ]],
    -- Maletero: items guardados en cada vehiculo
    [[
    CREATE TABLE IF NOT EXISTS vehicle_items (
        vehicle_id INT UNSIGNED NOT NULL,
        item_id    VARCHAR(32)  NOT NULL,
        amount     INT UNSIGNED NOT NULL,
        PRIMARY KEY (vehicle_id, item_id),
        CONSTRAINT fk_vehicle_items_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Golpes recibidos (se conservan 1 dia, rp_vehicles borra los viejos cada hora)
    [[
    CREATE TABLE IF NOT EXISTS vehicle_hits (
        id             INT UNSIGNED      NOT NULL AUTO_INCREMENT,
        vehicle_id     INT UNSIGNED      NOT NULL,
        character_id   INT UNSIGNED      NULL,
        character_name VARCHAR(32)       NOT NULL,
        weapon         SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        loss           FLOAT             NOT NULL DEFAULT 0,
        hits           SMALLINT UNSIGNED NOT NULL DEFAULT 1,
        created_at     DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_vehicle_hits_vehicle (vehicle_id, id),
        KEY idx_vehicle_hits_created (created_at),
        CONSTRAINT fk_vehicle_hits_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Quien se subio a cada vehiculo y en que asiento (se conserva 1 dia)
    [[
    CREATE TABLE IF NOT EXISTS vehicle_entries (
        id             INT UNSIGNED     NOT NULL AUTO_INCREMENT,
        vehicle_id     INT UNSIGNED     NOT NULL,
        character_id   INT UNSIGNED     NULL,
        character_name VARCHAR(32)      NOT NULL,
        seat           TINYINT UNSIGNED NOT NULL DEFAULT 0,
        created_at     DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_vehicle_entries_vehicle (vehicle_id, id),
        KEY idx_vehicle_entries_created (created_at),
        CONSTRAINT fk_vehicle_entries_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Policia: multas a vehiculos y registro de acciones (cepo, multas, pagos)
    [[
    CREATE TABLE IF NOT EXISTS vehicle_fines (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        vehicle_id   INT UNSIGNED NOT NULL,
        officer_id   INT UNSIGNED NULL,
        officer_name VARCHAR(32)  NOT NULL,
        amount       INT UNSIGNED NOT NULL,
        reason       VARCHAR(128) NOT NULL,
        paid         TINYINT(1)   NOT NULL DEFAULT 0,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        paid_at      DATETIME     NULL,
        PRIMARY KEY (id),
        KEY idx_vehicle_fines_vehicle (vehicle_id, paid),
        CONSTRAINT fk_vehicle_fines_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS vehicle_police_log (
        id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
        vehicle_id INT UNSIGNED NOT NULL,
        actor_name VARCHAR(32)  NOT NULL,
        text       VARCHAR(255) NOT NULL,
        created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_vehicle_police_log (vehicle_id, id),
        CONSTRAINT fk_vehicle_police_log_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Faccion 1 reservada para la Policia (necesita las tablas de rp_factions;
    -- si aun no existen, estas dos sentencias fallan sin bloquear el resto y se
    -- reintentan en el siguiente arranque).
    [[
    INSERT IGNORE INTO factions (id, name, tag, type, color, state_funded)
    VALUES (1, 'Policia de Los Santos', 'LSPD', 'policia', '#3b6fe0', 1)
    ]],
    [[
    INSERT IGNORE INTO faction_ranks (faction_id, name, level, salary, permissions)
    SELECT 1, r.name, r.level, r.salary, r.permissions FROM (
        SELECT 'Comisario' AS name, 10 AS level, 2000 AS salary, 1023 AS permissions
        UNION ALL SELECT 'Oficial', 1, 800, 1
    ) r
    WHERE EXISTS (SELECT 1 FROM factions WHERE id = 1 AND type = 'policia')
      AND NOT EXISTS (SELECT 1 FROM faction_ranks WHERE faction_id = 1)
    ]],
    -- Bencina de los vehiculos (NULL = tanque lleno) y tarjetas de debito
    [[
    ALTER TABLE vehicles
        ADD COLUMN IF NOT EXISTS fuel FLOAT NULL
    ]],
    [[
    CREATE TABLE IF NOT EXISTS bank_cards (
        character_id INT UNSIGNED NOT NULL,
        number       CHAR(16)     NOT NULL,
        pin          CHAR(4)      NOT NULL,
        holder       VARCHAR(32)  NOT NULL,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id),
        UNIQUE KEY uq_bank_cards_number (number),
        CONSTRAINT fk_bank_cards_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_robbery: tiendas 24/7 robables (puerta por fuera; points = JSON con cajero, caja, salida y clientes corregidos en juego)
    [[
    CREATE TABLE IF NOT EXISTS robbery_stores (
        id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
        name       VARCHAR(48)  NOT NULL,
        type       VARCHAR(16)  NOT NULL,
        x          FLOAT        NOT NULL,
        y          FLOAT        NOT NULL,
        z          FLOAT        NOT NULL,
        rot        FLOAT        NOT NULL DEFAULT 0,
        points     TEXT         NULL,
        created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_phone (Fotogram): filtro aplicado a la foto (solo informativo, la imagen ya llega editada)
    [[
    ALTER TABLE social_posts
        ADD COLUMN IF NOT EXISTS filter VARCHAR(16) NOT NULL DEFAULT '' AFTER caption
    ]],
    -- rp_phone (Fotogram): publicaciones de un personaje en orden (perfil y feed de seguidos)
    [[
    ALTER TABLE social_posts
        ADD INDEX IF NOT EXISTS idx_posts_character_id (character_id, id)
    ]],
    -- rp_phone (Fotogram): perfil publico de cada personaje (usuario @, biografia y foto de perfil)
    [[
    CREATE TABLE IF NOT EXISTS social_profiles (
        character_id   INT UNSIGNED NOT NULL,
        username       VARCHAR(24)  NOT NULL,
        bio            VARCHAR(150) NOT NULL DEFAULT '',
        avatar_post_id INT UNSIGNED NULL,
        created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id),
        UNIQUE KEY uq_social_profiles_username (username),
        CONSTRAINT fk_social_profiles_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE,
        CONSTRAINT fk_social_profiles_avatar FOREIGN KEY (avatar_post_id) REFERENCES social_posts (id) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_phone (Fotogram): quien sigue a quien
    [[
    CREATE TABLE IF NOT EXISTS social_follows (
        follower_id INT UNSIGNED NOT NULL,
        followed_id INT UNSIGNED NOT NULL,
        created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (follower_id, followed_id),
        KEY idx_social_follows_followed (followed_id),
        CONSTRAINT fk_social_follows_follower FOREIGN KEY (follower_id) REFERENCES characters (id) ON DELETE CASCADE,
        CONSTRAINT fk_social_follows_followed FOREIGN KEY (followed_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_phone (Fotogram): comentarios de las fotos
    [[
    CREATE TABLE IF NOT EXISTS social_comments (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        post_id      INT UNSIGNED NOT NULL,
        character_id INT UNSIGNED NOT NULL,
        body         VARCHAR(200) NOT NULL,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_social_comments_post (post_id, id),
        CONSTRAINT fk_social_comments_post FOREIGN KEY (post_id) REFERENCES social_posts (id) ON DELETE CASCADE,
        CONSTRAINT fk_social_comments_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_phone (Fotogram): notificaciones (like, comment, follow, mention). character_id = quien la recibe
    [[
    CREATE TABLE IF NOT EXISTS social_notifications (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED NOT NULL,
        actor_id     INT UNSIGNED NOT NULL,
        type         VARCHAR(12)  NOT NULL,
        post_id      INT UNSIGNED NULL,
        text         VARCHAR(100) NOT NULL DEFAULT '',
        is_read      TINYINT(1)   NOT NULL DEFAULT 0,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_social_notifications_character (character_id, id),
        KEY idx_social_notifications_created (created_at),
        CONSTRAINT fk_social_notifications_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE,
        CONSTRAINT fk_social_notifications_actor FOREIGN KEY (actor_id) REFERENCES characters (id) ON DELETE CASCADE,
        CONSTRAINT fk_social_notifications_post FOREIGN KEY (post_id) REFERENCES social_posts (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_phone (Tinder, parte 1): perfil de citas del personaje. Edad y genero salen de characters
    [[
    CREATE TABLE IF NOT EXISTS tinder_profiles (
        character_id INT UNSIGNED NOT NULL,
        bio          VARCHAR(200) NOT NULL DEFAULT '',
        interested   CHAR(1)      NOT NULL DEFAULT 'a',
        photo        MEDIUMTEXT   NULL,
        active       TINYINT(1)   NOT NULL DEFAULT 1,
        updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id),
        CONSTRAINT fk_tinder_profiles_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_characters: complexion (0-100, stats FAT y BODY_MUSCLE de CJ) y tono de piel
    -- (indice de BODY.TONES en rp_characters/shared/s_body.lua; 0 = piel original de CJ)
    [[
    ALTER TABLE characters
        ADD COLUMN IF NOT EXISTS body_fat    TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER clothes_shoes,
        ADD COLUMN IF NOT EXISTS body_muscle TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER body_fat,
        ADD COLUMN IF NOT EXISTS skin_tone   TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER body_muscle
    ]],
    -- rp_agency: DNI de cada personaje (el item "id_card" es solo el papel; si se pierde se reimprime)
    [[
    CREATE TABLE IF NOT EXISTS identity_cards (
        character_id INT UNSIGNED      NOT NULL,
        number       VARCHAR(12)       NOT NULL,
        signature    TEXT              NULL,
        copies       SMALLINT UNSIGNED NOT NULL DEFAULT 1,
        issued_at    DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id),
        UNIQUE KEY uq_identity_cards_number (number),
        CONSTRAINT fk_identity_cards_character FOREIGN KEY (character_id)
            REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_jobs: trabajo actual de cada personaje (lo asigna la agencia o la sede del trabajo)
    [[
    CREATE TABLE IF NOT EXISTS character_jobs (
        character_id INT UNSIGNED NOT NULL,
        job_id       VARCHAR(24)  NOT NULL,
        hired_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id),
        CONSTRAINT fk_character_jobs_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_jobs: experiencia y estadisticas por personaje y trabajo (se conservan al cambiar de trabajo)
    [[
    CREATE TABLE IF NOT EXISTS job_stats (
        character_id INT UNSIGNED NOT NULL,
        job_id       VARCHAR(24)  NOT NULL,
        xp           INT UNSIGNED NOT NULL DEFAULT 0,
        tasks        INT UNSIGNED NOT NULL DEFAULT 0,
        earned       INT UNSIGNED NOT NULL DEFAULT 0,
        best_shift   INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (character_id, job_id),
        CONSTRAINT fk_job_stats_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_driving: autoescuelas (instructor en el mundo) y su pista de pruebas (arena_* NULL = la de config)
    [[
    CREATE TABLE IF NOT EXISTS driving_schools (
        id         INT UNSIGNED      NOT NULL AUTO_INCREMENT,
        x          FLOAT             NOT NULL,
        y          FLOAT             NOT NULL,
        z          FLOAT             NOT NULL,
        rotation   FLOAT             NOT NULL DEFAULT 0,
        interior   TINYINT UNSIGNED  NOT NULL DEFAULT 0,
        dimension  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        arena_x    FLOAT             NULL,
        arena_y    FLOAT             NULL,
        arena_z    FLOAT             NULL,
        arena_rot  FLOAT             NULL,
        created_at DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_driving: mejor resultado de cada personaje en cada prueba (tabla de puntajes)
    [[
    CREATE TABLE IF NOT EXISTS driving_scores (
        character_id INT UNSIGNED     NOT NULL,
        test_id      VARCHAR(24)      NOT NULL,
        best_score   TINYINT UNSIGNED NOT NULL DEFAULT 0,
        best_time_ms INT UNSIGNED     NOT NULL DEFAULT 0,
        medal        TINYINT UNSIGNED NOT NULL DEFAULT 0,
        attempts     INT UNSIGNED     NOT NULL DEFAULT 0,
        updated_at   DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id, test_id),
        KEY idx_driving_scores_rank (test_id, best_score, best_time_ms),
        CONSTRAINT fk_driving_scores_character FOREIGN KEY (character_id)
            REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_driving: licencia de conducir del personaje (el item driver_license es solo el papel)
    [[
    CREATE TABLE IF NOT EXISTS driving_licenses (
        character_id   INT UNSIGNED NOT NULL,
        number         VARCHAR(16)  NOT NULL,
        status         VARCHAR(12)  NOT NULL DEFAULT 'valid',
        revoked_reason VARCHAR(120) NULL,
        revoked_by     VARCHAR(32)  NULL,
        revoked_at     DATETIME     NULL,
        issued_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id),
        UNIQUE KEY uq_driving_licenses_number (number),
        CONSTRAINT fk_driving_licenses_character FOREIGN KEY (character_id)
            REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_phone: catálogo reproducible de música (propio, SoundCloud o cualquier proveedor externo directo)
    [[
    CREATE TABLE IF NOT EXISTS music_tracks (
        id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
        track_key      VARCHAR(96)  NOT NULL,
        provider       VARCHAR(24)  NOT NULL DEFAULT 'local',
        provider_id    VARCHAR(96)  NULL,
        title          VARCHAR(160) NOT NULL,
        artist         VARCHAR(160) NOT NULL,
        artwork_url    VARCHAR(512) NULL,
        stream_url     VARCHAR(512) NOT NULL,
        duration_ms    INT UNSIGNED NOT NULL DEFAULT 0,
        active         TINYINT(1)   NOT NULL DEFAULT 1,
        created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_music_tracks_key (track_key),
        KEY idx_music_tracks_search (provider, active, title),
        KEY idx_music_tracks_artist (artist)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_phone: canciones favoritas por personaje
    [[
    CREATE TABLE IF NOT EXISTS music_favorites (
        character_id INT UNSIGNED NOT NULL,
        track_key    VARCHAR(96)  NOT NULL,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id, track_key),
        KEY idx_music_favorites_character (character_id, created_at),
        CONSTRAINT fk_music_favorites_character FOREIGN KEY (character_id)
            REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_phone: historial reciente de reproducciones por personaje
    [[
    CREATE TABLE IF NOT EXISTS music_history (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED NOT NULL,
        track_key    VARCHAR(96)  NOT NULL,
        played_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_music_history_character (character_id, played_at),
        CONSTRAINT fk_music_history_character FOREIGN KEY (character_id)
            REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_phone: cache persistente de búsquedas externas (no guarda archivos de audio)
    [[
    CREATE TABLE IF NOT EXISTS music_search_cache (
        provider  VARCHAR(24)  NOT NULL,
        query_key VARCHAR(96)  NOT NULL,
        payload   MEDIUMTEXT   NOT NULL,
        expires_at DATETIME    NOT NULL,
        created_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (provider, query_key),
        KEY idx_music_search_cache_expiry (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Rendimiento del tuning: piezas y desgaste (JSON) y kilometraje del vehiculo
    [[
    ALTER TABLE vehicles
        ADD COLUMN IF NOT EXISTS perf     TEXT  NULL,
        ADD COLUMN IF NOT EXISTS odometer FLOAT NOT NULL DEFAULT 0
    ]],
    -- rp_phone (Tinder, parte 2): likes y dislikes. Un match es un like mutuo (parte 3 los lista)
    [[
    CREATE TABLE IF NOT EXISTS tinder_swipes (
        swiper_id  INT UNSIGNED NOT NULL,
        target_id  INT UNSIGNED NOT NULL,
        liked      TINYINT(1)   NOT NULL,
        created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (swiper_id, target_id),
        KEY idx_tinder_swipes_target (target_id, liked),
        CONSTRAINT fk_tinder_swipes_swiper FOREIGN KEY (swiper_id) REFERENCES characters (id) ON DELETE CASCADE,
        CONSTRAINT fk_tinder_swipes_target FOREIGN KEY (target_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_levels: experiencia (RP) total por personaje; el nivel se calcula con la curva del recurso
    [[
    CREATE TABLE IF NOT EXISTS character_levels (
        character_id INT UNSIGNED NOT NULL,
        xp           INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (character_id),
        CONSTRAINT fk_character_levels_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_phone: galeria del telefono (fotos tomadas con la camara, JPEG en base64) por personaje
    [[
    CREATE TABLE IF NOT EXISTS phone_gallery (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED NOT NULL,
        image        MEDIUMTEXT   NOT NULL,
        created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_phone_gallery_character (character_id, id),
        CONSTRAINT fk_phone_gallery_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_chat: historial de PMs (OOC) para que los admins revisen MG. Sin FK: se conserva aunque se borre el personaje
    [[
    CREATE TABLE IF NOT EXISTS chat_pm_log (
        id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
        sender_char INT UNSIGNED NOT NULL,
        sender_name VARCHAR(64)  NOT NULL,
        target_char INT UNSIGNED NOT NULL,
        target_name VARCHAR(64)  NOT NULL,
        message     VARCHAR(255) NOT NULL,
        created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_chat_pm_sender (sender_name, id),
        KEY idx_chat_pm_target (target_name, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_dealers: traficantes (peds con skin 28/29/30) que venden drogas
    [[
    CREATE TABLE IF NOT EXISTS dealers (
        id        INT UNSIGNED NOT NULL AUTO_INCREMENT,
        ped_skin  SMALLINT UNSIGNED NOT NULL,
        x         FLOAT NOT NULL,
        y         FLOAT NOT NULL,
        z         FLOAT NOT NULL,
        rotation  FLOAT NOT NULL DEFAULT 0,
        interior  TINYINT UNSIGNED NOT NULL DEFAULT 0,
        dimension INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_needs: cordura del personaje (0-100); baja al matar civiles
    [[
    ALTER TABLE characters
        ADD COLUMN IF NOT EXISTS sanity TINYINT UNSIGNED NOT NULL DEFAULT 100
    ]],
    -- rp_backpacks: mochila equipada por personaje y su contenido (se pierde al tirarla)
    [[
    CREATE TABLE IF NOT EXISTS character_backpack (
        character_id INT UNSIGNED NOT NULL,
        backpack_id  VARCHAR(32)  NOT NULL,
        PRIMARY KEY (character_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS backpack_items (
        character_id INT UNSIGNED NOT NULL,
        item_id      VARCHAR(32)  NOT NULL,
        amount       INT UNSIGNED NOT NULL,
        PRIMARY KEY (character_id, item_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_pool: mesas de pool colocadas (las de Ten Green Bottles se siembran al arrancar)
    [[
    CREATE TABLE IF NOT EXISTS pool_tables (
        id        INT UNSIGNED NOT NULL AUTO_INCREMENT,
        x         FLOAT NOT NULL,
        y         FLOAT NOT NULL,
        z         FLOAT NOT NULL,
        rotation  FLOAT NOT NULL DEFAULT 0,
        interior  TINYINT UNSIGNED NOT NULL DEFAULT 0,
        dimension INT UNSIGNED NOT NULL DEFAULT 0,
        native    TINYINT(1) NOT NULL DEFAULT 0,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_pool: estadisticas globales por personaje (ranking de victorias y de dinero ganado)
    [[
    CREATE TABLE IF NOT EXISTS pool_stats (
        character_id INT UNSIGNED NOT NULL,
        name         VARCHAR(64)  NOT NULL,
        games        INT UNSIGNED NOT NULL DEFAULT 0,
        wins         INT UNSIGNED NOT NULL DEFAULT 0,
        losses       INT UNSIGNED NOT NULL DEFAULT 0,
        money_won    BIGINT UNSIGNED NOT NULL DEFAULT 0,
        money_lost   BIGINT UNSIGNED NOT NULL DEFAULT 0,
        best_win     INT UNSIGNED NOT NULL DEFAULT 0,
        updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id),
        KEY idx_pool_stats_wins (wins),
        KEY idx_pool_stats_money (money_won)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_pool: historial de partidas
    [[
    CREATE TABLE IF NOT EXISTS pool_matches (
        id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
        winner_id   INT UNSIGNED NOT NULL,
        loser_id    INT UNSIGNED NOT NULL,
        winner_name VARCHAR(64)  NOT NULL,
        loser_name  VARCHAR(64)  NOT NULL,
        bet         INT UNSIGNED NOT NULL DEFAULT 0,
        reason      VARCHAR(24)  NOT NULL DEFAULT 'normal',
        created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_pool_matches_winner (winner_id),
        KEY idx_pool_matches_loser (loser_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_pool: apuestas en custodia (se devuelven si el servidor cae a mitad de partida)
    [[
    CREATE TABLE IF NOT EXISTS pool_escrow (
        character_id INT UNSIGNED NOT NULL,
        amount       INT UNSIGNED NOT NULL,
        table_id     INT UNSIGNED NOT NULL,
        created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_npcrel: vinculos del personaje con personas del barrio (amistad, romance, numero de telefono)
    [[
    CREATE TABLE IF NOT EXISTS npc_contacts (
        id               INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id     INT UNSIGNED NOT NULL,
        name             VARCHAR(48)  NOT NULL,
        gender           TINYINT UNSIGNED NOT NULL DEFAULT 0,
        skin             SMALLINT UNSIGNED NOT NULL,
        traits           VARCHAR(64)  NOT NULL DEFAULT '',
        likes            CHAR(1)      NOT NULL DEFAULT 'a',
        phone_number     INT UNSIGNED NULL,
        friendship       SMALLINT     NOT NULL DEFAULT 0,
        romance          SMALLINT     NOT NULL DEFAULT 0,
        dating           TINYINT UNSIGNED NOT NULL DEFAULT 0,
        number_shared    TINYINT UNSIGNED NOT NULL DEFAULT 0,
        interactions     INT UNSIGNED NOT NULL DEFAULT 0,
        last_interaction DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_npc_contacts_phone (phone_number),
        KEY idx_npc_contacts_character (character_id),
        CONSTRAINT fk_npc_contacts_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_characters / rp_gym: stats de cuerpo con escala 0-1000 (la del juego). NULL = sin entrenar:
    -- se usa body_fat / body_muscle (0-100) y la resistencia queda como esta
    [[
    ALTER TABLE characters
        ADD COLUMN IF NOT EXISTS stat_fat     FLOAT NULL,
        ADD COLUMN IF NOT EXISTS stat_muscle  FLOAT NULL,
        ADD COLUMN IF NOT EXISTS stat_stamina FLOAT NULL
    ]],
    -- rp_gym: maquinas y entrenadores colocados por admins
    [[
    CREATE TABLE IF NOT EXISTS gym_machines (
        id        INT UNSIGNED NOT NULL AUTO_INCREMENT,
        kind      VARCHAR(16)  NOT NULL,
        gym       VARCHAR(24)  NOT NULL DEFAULT 'gym',
        x         FLOAT NOT NULL,
        y         FLOAT NOT NULL,
        z         FLOAT NOT NULL,
        rotation  FLOAT NOT NULL DEFAULT 0,
        interior  TINYINT UNSIGNED NOT NULL DEFAULT 0,
        dimension INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS gym_trainers (
        id        INT UNSIGNED NOT NULL AUTO_INCREMENT,
        style     VARCHAR(16)  NOT NULL,
        x         FLOAT NOT NULL,
        y         FLOAT NOT NULL,
        z         FLOAT NOT NULL,
        rotation  FLOAT NOT NULL DEFAULT 0,
        interior  TINYINT UNSIGNED NOT NULL DEFAULT 0,
        dimension INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_gym: estilos de combate, estilo actual, progreso del dia, bloqueo de 12 h y ultimo entrenamiento
    [[
    CREATE TABLE IF NOT EXISTS character_gym (
        character_id  INT UNSIGNED NOT NULL,
        boxing        TINYINT UNSIGNED NOT NULL DEFAULT 0,
        kungfu        TINYINT UNSIGNED NOT NULL DEFAULT 0,
        kickboxing    TINYINT UNSIGNED NOT NULL DEFAULT 0,
        style         TINYINT UNSIGNED NULL,
        day_start     INT UNSIGNED NOT NULL DEFAULT 0,
        day_fat       FLOAT NOT NULL DEFAULT 0,
        day_stamina   FLOAT NOT NULL DEFAULT 0,
        day_muscle    FLOAT NOT NULL DEFAULT 0,
        locked_until  INT UNSIGNED NOT NULL DEFAULT 0,
        last_trained  INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (character_id),
        CONSTRAINT fk_gym_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_furniture: muebles colocados en cada propiedad (clave de catalogo, posicion, giro, escala, color, material y estado)
    [[
    CREATE TABLE IF NOT EXISTS property_furniture (
        id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
        property_id INT UNSIGNED NOT NULL,
        item_key    VARCHAR(48)  NOT NULL,
        x           FLOAT NOT NULL,
        y           FLOAT NOT NULL,
        z           FLOAT NOT NULL,
        rx          FLOAT NOT NULL DEFAULT 0,
        ry          FLOAT NOT NULL DEFAULT 0,
        rz          FLOAT NOT NULL DEFAULT 0,
        sx          FLOAT NOT NULL DEFAULT 1,
        sy          FLOAT NOT NULL DEFAULT 1,
        sz          FLOAT NOT NULL DEFAULT 1,
        color       INT UNSIGNED NULL,
        material    VARCHAR(16)  NULL,
        state       VARCHAR(255) NULL,
        placed_by   INT UNSIGNED NULL,
        placed_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_furniture_property (property_id),
        CONSTRAINT fk_furniture_property FOREIGN KEY (property_id) REFERENCES properties (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_furniture: estilo de la propiedad (objetos originales del interior ocultados, JSON)
    [[
    CREATE TABLE IF NOT EXISTS property_style (
        property_id   INT UNSIGNED NOT NULL,
        removed_props TEXT NULL,
        updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (property_id),
        CONSTRAINT fk_style_property FOREIGN KEY (property_id) REFERENCES properties (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_furniture: residentes que pueden construir en una propiedad ajena
    [[
    CREATE TABLE IF NOT EXISTS property_members (
        property_id  INT UNSIGNED NOT NULL,
        character_id INT UNSIGNED NOT NULL,
        role         VARCHAR(12)  NOT NULL DEFAULT 'builder',
        added_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (property_id, character_id),
        KEY idx_members_character (character_id),
        CONSTRAINT fk_members_property FOREIGN KEY (property_id) REFERENCES properties (id) ON DELETE CASCADE,
        CONSTRAINT fk_members_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_furniture: bodega personal de muebles (se llevan de una casa a otra)
    [[
    CREATE TABLE IF NOT EXISTS character_furniture_stock (
        character_id INT UNSIGNED NOT NULL,
        item_key     VARCHAR(48)  NOT NULL,
        qty          INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (character_id, item_key),
        CONSTRAINT fk_fstock_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_furniture: contenido de neveras, armarios y cajas fuertes
    [[
    CREATE TABLE IF NOT EXISTS furniture_storage (
        furniture_id INT UNSIGNED NOT NULL,
        item_id      VARCHAR(48)  NOT NULL,
        amount       INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (furniture_id, item_id),
        CONSTRAINT fk_fstorage_furniture FOREIGN KEY (furniture_id) REFERENCES property_furniture (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_furniture: registro de compras, ventas y cambios (para resolver disputas)
    [[
    CREATE TABLE IF NOT EXISTS furniture_log (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        property_id  INT UNSIGNED NOT NULL,
        character_id INT UNSIGNED NULL,
        action       VARCHAR(16)  NOT NULL,
        item_key     VARCHAR(48)  NULL,
        amount       INT NOT NULL DEFAULT 0,
        created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_flog_property (property_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_furniture: planos (diseños guardados por personaje; posiciones relativas a la salida de la casa)
    [[
    CREATE TABLE IF NOT EXISTS property_blueprints (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED NOT NULL,
        name         VARCHAR(40)  NOT NULL,
        interior     TINYINT UNSIGNED NOT NULL DEFAULT 0,
        data         MEDIUMTEXT   NOT NULL,
        created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_blueprints_character (character_id),
        CONSTRAINT fk_blueprints_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_police: antecedentes (arrestos, multas a personas, notas)
    [[
    CREATE TABLE IF NOT EXISTS police_records (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED NOT NULL,
        kind         VARCHAR(8)   NOT NULL,
        text         VARCHAR(255) NOT NULL,
        amount       INT NOT NULL DEFAULT 0,
        minutes      INT NOT NULL DEFAULT 0,
        paid         TINYINT(1)   NOT NULL DEFAULT 1,
        officer_name VARCHAR(40)  NOT NULL,
        created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_police_records_char (character_id, id),
        CONSTRAINT fk_police_records_char FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_police: BOLO (vehiculos o personas) y ordenes de captura (kind person con character_id)
    [[
    CREATE TABLE IF NOT EXISTS police_bolos (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        kind         VARCHAR(8)   NOT NULL,
        subject      VARCHAR(48)  NOT NULL,
        character_id INT UNSIGNED NULL,
        plate        VARCHAR(8)   NULL,
        description  VARCHAR(255) NOT NULL,
        reward       INT NOT NULL DEFAULT 0,
        active       TINYINT(1)   NOT NULL DEFAULT 1,
        officer_name VARCHAR(40)  NOT NULL,
        closed_by    VARCHAR(40)  NULL,
        created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_police_bolos_active (active, id),
        KEY idx_police_bolos_char (character_id),
        KEY idx_police_bolos_plate (plate)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_police: evidencia recolectada y su analisis en el laboratorio
    [[
    CREATE TABLE IF NOT EXISTS police_evidence (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        kind         VARCHAR(8)   NOT NULL,
        detail       VARCHAR(160) NOT NULL,
        source_char  INT UNSIGNED NULL,
        serial       VARCHAR(20)  NULL,
        location     VARCHAR(64)  NOT NULL,
        collected_by VARCHAR(40)  NOT NULL,
        analyzed     TINYINT(1)   NOT NULL DEFAULT 0,
        result       VARCHAR(255) NULL,
        created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_police_evidence_analyzed (analyzed, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_police: items decomisados en un cacheo
    [[
    CREATE TABLE IF NOT EXISTS police_seized (
        id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id INT UNSIGNED NOT NULL,
        item         VARCHAR(48)  NOT NULL,
        amount       INT NOT NULL,
        officer_name VARCHAR(40)  NOT NULL,
        created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_police_seized_char (character_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_police: puntos movidos por admins (vestuario, armeria, garaje, laboratorio, calabozos, spawn de patrullas)
    [[
    CREATE TABLE IF NOT EXISTS police_points (
        kind VARCHAR(16) NOT NULL,
        x    FLOAT NOT NULL,
        y    FLOAT NOT NULL,
        z    FLOAT NOT NULL,
        rot  FLOAT NOT NULL DEFAULT 0,
        PRIMARY KEY (kind)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- rp_missions: respeto por contacto, progreso por mision y puntos de inicio movidos por admins
    [[
    CREATE TABLE IF NOT EXISTS character_respect (
        character_id INT UNSIGNED NOT NULL,
        contact      VARCHAR(16)  NOT NULL,
        respect      INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (character_id, contact),
        CONSTRAINT fk_character_respect_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS mission_progress (
        character_id INT UNSIGNED NOT NULL,
        mission_key  VARCHAR(32)  NOT NULL,
        completions  INT UNSIGNED NOT NULL DEFAULT 0,
        best_ms      INT UNSIGNED NULL,
        PRIMARY KEY (character_id, mission_key),
        CONSTRAINT fk_mission_progress_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS mission_points (
        contact VARCHAR(16) NOT NULL,
        x FLOAT NOT NULL,
        y FLOAT NOT NULL,
        z FLOAT NOT NULL,
        PRIMARY KEY (contact)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
}
