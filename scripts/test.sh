#!/usr/bin/env bash
# Levanta el entorno Docker, espera a que la base este lista, ejecuta rp_test y
# devuelve 0 si todo pasa o 1 si algo falla. Compatible con el bash 3.2 de macOS.
#
#   scripts/test.sh            usa los contenedores (y datos) que ya hay
#   scripts/test.sh --fresh    borra la base antes (prueba de instalacion limpia)
#   scripts/test.sh --down     para los contenedores al terminar
#   scripts/test.sh --no-build no reconstruye la imagen del servidor
#
# Ademas de las pruebas de rp_test, falla si la consola del servidor tiene lineas
# "ERROR:" desde el arranque (recursos que no cargan, errores de script, SQL que falla).
set -euo pipefail

cd "$(dirname "$0")/.."
LOG=docker/logs/server.log
FRESH=0; DOWN=0; BUILD=--build
for arg in "$@"; do
    case "$arg" in
        --fresh) FRESH=1 ;;
        --down) DOWN=1 ;;
        --no-build) BUILD= ;;
        *) echo "Opcion desconocida: $arg" >&2; exit 2 ;;
    esac
done

[ -f .env ] || { echo "No existe .env. Crealo con: cp .env.example .env" >&2; exit 2; }
mkdir -p docker/logs

say() { printf '\n== %s\n' "$*"; }
lines() { [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }

# Espera hasta que aparezca un patron en el log a partir de la linea $2. $3 = segundos maximos
wait_for() {
    local pattern=$1 from=$2 timeout=$3 i=0
    while [ $i -lt "$timeout" ]; do
        if tail -n +"$from" "$LOG" 2>/dev/null | grep -q "$pattern"; then return 0; fi
        sleep 1; i=$((i + 1))
    done
    return 1
}

finish() {
    local code=$1
    if [ $DOWN -eq 1 ]; then say "Parando contenedores"; scripts/mta.sh down >/dev/null 2>&1 || true; fi
    if [ "$code" -eq 0 ]; then say "OK: todas las pruebas pasan"; else say "FALLO (codigo $code)"; fi
    exit "$code"
}

if [ $FRESH -eq 1 ]; then
    say "Borrando base de datos y contenedores (--fresh)"
    docker compose down -v
fi

# Se reinicia el servidor para medir errores desde un arranque limpio
say "Arrancando MariaDB + servidor MTA"
start_line=$(( $(lines) + 1 ))
docker compose up -d $BUILD db
docker compose up -d $BUILD --force-recreate mta

say "Esperando a la base de datos (rp_database)"
if ! wait_for "Base de datos lista" "$start_line" 120; then
    echo "rp_database no termino de aplicar el esquema en 120 s. Ultimas lineas del log:"
    tail -n 40 "$LOG" 2>/dev/null || docker compose logs --tail 40 mta
    finish 1
fi

# Margen para que terminen de arrancar el resto de recursos
sleep 3

say "Ejecutando rp_test"
test_line=$(( $(lines) + 1 ))
scripts/mta.sh cmd "refresh" >/dev/null
scripts/mta.sh cmd "start rp_test" >/dev/null
if ! wait_for "\[rp_test\] FIN" "$test_line" 120; then
    echo "rp_test no termino en 120 s. Ultimas lineas del log:"
    tail -n 40 "$LOG"
    scripts/mta.sh cmd "stop rp_test" >/dev/null || true
    finish 1
fi
scripts/mta.sh cmd "stop rp_test" >/dev/null || true

tail -n +"$test_line" "$LOG" | grep "\[rp_test\]" | sed 's/^.*\[rp_test\] /  /'

code=0
tail -n +"$test_line" "$LOG" | grep -q "\[rp_test\] FIN OK" || code=1

say "Errores en la consola del servidor desde el arranque"
errors=$(tail -n +"$start_line" "$LOG" | grep -E "ERROR:" || true)
if [ -n "$errors" ]; then
    echo "$errors"
    code=1
else
    echo "  ninguno"
fi

finish $code
