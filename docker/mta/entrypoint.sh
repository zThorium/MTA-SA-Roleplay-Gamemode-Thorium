#!/bin/bash
# Arranque del servidor MTA dentro del contenedor.
#  1. Copia mtaserver.conf, acl.xml y vehiclecolors.conf del repo (montados en /config).
#  2. Genera rp_database/config.lua con las credenciales del .env (si no hay uno propio).
#  3. Abre una FIFO como consola: lo que se escriba en /tmp/mta-console llega al servidor
#     como si se tecleara en su consola (scripts/mta.sh cmd "restart rp_bank").
set -euo pipefail

DM=/opt/mta/mods/deathmatch
CONSOLE=/tmp/mta-console

for f in mtaserver.conf acl.xml vehiclecolors.conf; do
    [ -f "/config/$f" ] && cp "/config/$f" "$DM/$f"
done

# El chequeo de version de cliente no aporta nada en local
sed -i 's|<minclientversion_auto_update>1</minclientversion_auto_update>|<minclientversion_auto_update>0</minclientversion_auto_update>|' "$DM/mtaserver.conf"

CFG="$DM/resources/[roleplay]/rp_database/config.lua"
MARK="GENERADO POR DOCKER"
if [ ! -f "$CFG" ] || grep -q "$MARK" "$CFG"; then
    cat > "$CFG" <<LUA
-- $MARK (docker/mta/entrypoint.sh). Se reescribe en cada arranque del contenedor
-- con los valores de .env. Esta en .gitignore: no lo subas.
DB_CONFIG = {
    host     = [==[${DB_HOST:-db}]==],
    port     = ${DB_PORT:-3306},
    dbname   = [==[${DB_NAME:-mtarp}]==],
    user     = [==[${DB_USER:-mtarp}]==],
    password = [==[${DB_PASSWORD:-}]==],
    charset  = "utf8mb4",
}
LUA
    echo "[docker] rp_database/config.lua generado (host ${DB_HOST:-db})"
else
    echo "[docker] AVISO: rp_database/config.lua ya existe y no es de Docker; se usa tal cual."
    echo "[docker]        Para que lo genere el contenedor, borralo o renombralo."
fi

# rp_hud necesita images/map.png, que no esta en el repo (material de Rockstar, ver
# docs/ENTORNO_LOCAL.md). Sin el, rp_hud no arranca. En Docker se pone un PNG gris de
# relleno (ignorado por git) para que el recurso cargue; el minimapa sale vacio.
MAP="$DM/resources/[roleplay]/rp_hud/images/map.png"
if [ -d "$DM/resources/[roleplay]/rp_hud" ] && [ ! -f "$MAP" ]; then
    mkdir -p "$(dirname "$MAP")"
    echo "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAUElEQVR42u3PMQ0AAAgDsMnh4MS/NiRwkzSpgaZ6XouAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAwGUBdNWAebPgQKoAAAAASUVORK5CYII=" \
        | base64 -d > "$MAP"
    echo "[docker] rp_hud/images/map.png no existia: creado uno de relleno (minimapa vacio)"
fi

rm -f "$CONSOLE"
mkfifo "$CONSOLE"
# Abrir la FIFO en lectura+escritura evita que el servidor reciba EOF cuando
# termina cada "echo comando > fifo".
exec 3<>"$CONSOLE"

cd /opt/mta
exec ./mta-server -t -n -u <&3
