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
}
