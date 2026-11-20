#!/usr/bin/env bash
# Atajos para el entorno Docker de Thorium (docs/DOCKER.md).
# Compatible con el bash 3.2 de macOS.
set -euo pipefail

cd "$(dirname "$0")/.."
LOG=docker/logs/server.log

usage() {
    cat <<'TXT'
Uso: scripts/mta.sh <comando> [args]

  up                 Construye y arranca MariaDB + servidor MTA (en segundo plano)
  down               Para el servidor (shutdown limpio) y los contenedores
  restart            Reinicia el contenedor del servidor MTA
  status             Estado de los contenedores
  logs [-f]          Muestra server.log (-f para seguirlo en vivo)
  cmd "<comando>"    Envia un comando a la consola del servidor y muestra la respuesta
                       ej: scripts/mta.sh cmd "restart rp_bank"
  start|stop|restart-res <recurso>
                     Atajo: refresh + start/stop/restart del recurso
  db                 Abre una consola mysql en la base del gamemode
  reset-db           Borra TODOS los datos de la base (pide confirmacion)
TXT
}

require_env() {
    if [ ! -f .env ]; then
        echo "No existe .env. Crealo con: cp .env.example .env (y cambia las contrasenas)" >&2
        exit 1
    fi
}

log_lines() { [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }

# Envia una linea a la FIFO que hace de consola del servidor
send() {
    printf '%s\n' "$*" | docker compose exec -T mta sh -c 'cat > /tmp/mta-console'
}

# Envia un comando y muestra lo que el servidor escribio en el log despues
cmd() {
    local before wait
    before=$(log_lines)
    wait=${WAIT:-2}
    send "$*"
    sleep "$wait"
    tail -n +"$((before + 1))" "$LOG" 2>/dev/null || true
}

case "${1:-}" in
    up)
        require_env
        mkdir -p docker/logs
        docker compose up -d --build
        echo "Arrancando... sigue el log con: scripts/mta.sh logs -f"
        ;;
    down)
        if docker compose ps --status running --services 2>/dev/null | grep -qx mta; then
            send "shutdown" || true
            sleep 3
        fi
        docker compose down
        ;;
    restart)
        docker compose restart mta
        ;;
    status)
        docker compose ps
        ;;
    logs)
        if [ "${2:-}" = "-f" ]; then tail -n 50 -F "$LOG"; else cat "$LOG"; fi
        ;;
    cmd)
        shift
        [ $# -gt 0 ] || { usage; exit 1; }
        cmd "$*"
        ;;
    start|stop|restart-res)
        [ -n "${2:-}" ] || { usage; exit 1; }
        action=$1; [ "$action" = "restart-res" ] && action=restart
        send "refresh"
        sleep 1
        cmd "$action $2"
        ;;
    db)
        require_env
        # shellcheck disable=SC1091
        . ./.env
        docker compose exec db mariadb -u"${DB_USER:-mtarp}" -p"${DB_PASSWORD}" "${DB_NAME:-mtarp}"
        ;;
    reset-db)
        printf 'Esto borra cuentas, personajes y todo lo guardado. Escribe "borrar" para seguir: '
        read -r answer
        [ "$answer" = "borrar" ] || { echo "Cancelado."; exit 1; }
        docker compose down -v
        echo "Base borrada. Arranca de nuevo con: scripts/mta.sh up"
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        echo "Comando desconocido: $1" >&2
        usage
        exit 1
        ;;
esac
