#!/usr/bin/env bash
# Kanban del proyecto en local, para no gastar la cuota de GraphQL de GitHub (5.000 puntos por
# hora, compartida por todo lo que usa tu cuenta). Se descarga UNA vez al empezar, se trabaja con la
# copia y los cambios de columna/prioridad/tamaño se encolan y se envían juntos al terminar.
# Crear issues y PRs NO pasa por aquí: va por REST (otra cuota), con `gh api repos/...`.
# Solo necesita gh (usa su --jq) y awk. Compatible con el bash 3.2 de macOS.
#
#   scripts/kanban.sh pull                     descarga el kanban a .claude/kanban.tsv (1-2 puntos)
#   scripts/kanban.sh status                   resumen: In progress, Ready, P0 del Backlog y cola
#   scripts/kanban.sh ver [texto]              lista los ítems abiertos (filtra por texto si se da)
#   scripts/kanban.sh mover <N> <Estado>       encola el cambio de columna del issue/PR #N
#   scripts/kanban.sh campo <N> <Campo> <Val>  encola Priority (P0-P2) o Size (XS-XL)
#   scripts/kanban.sh nuevo <N> [Prio] [Size]  encola añadir el issue #N (ya creado) al proyecto, en Backlog
#   scripts/kanban.sh cola                     muestra lo que falta enviar
#   scripts/kanban.sh push                     envía la cola (1 petición por fase) y vuelve a descargar
#
# Si alguien cambió una tarjeta en la web después del pull, push no la pisa: la deja en la cola y avisa.
set -euo pipefail

cd "$(dirname "$0")/.."
OWNER=zThorium
PROJECT=4
REPO=zThorium/MTA-SA-Roleplay-Gamemode-Thorium
DIR=.claude
CACHE=$DIR/kanban.tsv          # tipo  N  estado(OPEN/CLOSED/MERGED)  Status  Priority  Size  itemId  título
FIELDS=$DIR/kanban-campos.tsv  # PROJECT  projectId  |  FIELD  Campo  fieldId  |  OPTION  Campo  Valor  optionId
QUEUE=$DIR/kanban-cola.tsv     # set  N  Campo  desde  hacia   |   add  N  -  -  -
mkdir -p "$DIR"
touch "$QUEUE"

die() { echo "kanban: $*" >&2; exit 1; }
need_cache() { [ -s "$CACHE" ] || die "no hay copia local; ejecuta: scripts/kanban.sh pull"; }

# ------------------------------------------------------------------ descarga
# Escribe la copia en los archivos dados ($1 = ítems, $2 = campos)
fetch() {
    local items=$1 fields=$2
    gh api graphql -f query='query($o:String!,$n:Int!){user(login:$o){projectV2(number:$n){id
        fields(first:30){nodes{...on ProjectV2SingleSelectField{id name options{id name}}}}}}}' \
        -F o="$OWNER" -F n="$PROJECT" --jq '
        .data.user.projectV2 as $p
        | (["PROJECT", $p.id] | @tsv),
          ($p.fields.nodes[] | select(.name != null) as $f
            | (["FIELD", $f.name, $f.id] | @tsv),
              ($f.options[] | ["OPTION", $f.name, .name, .id] | @tsv))' > "$fields.tmp"

    gh api graphql --paginate -f query='query($o:String!,$n:Int!,$endCursor:String){user(login:$o){projectV2(number:$n){
        items(first:100, after:$endCursor){pageInfo{hasNextPage endCursor} nodes{id
            content{__typename ...on Issue{number title state} ...on PullRequest{number title state}}
            fieldValues(first:12){nodes{...on ProjectV2ItemFieldSingleSelectValue{name field{...on ProjectV2SingleSelectField{name}}}}}}}}}}' \
        -F o="$OWNER" -F n="$PROJECT" --jq '
        .data.user.projectV2.items.nodes[] | select(.content.number != null)
        | ([.fieldValues.nodes[] | select(.field.name != null) | {(.field.name): .name}] | add // {}) as $v
        | [(if .content.__typename == "PullRequest" then "PR" else "issue" end), .content.number, .content.state,
           ($v.Status // "-"), ($v.Priority // "-"), ($v.Size // "-"), .id, (.content.title | gsub("\t"; " "))] | @tsv' \
        | sort -t "$(printf '\t')" -k2,2n > "$items.tmp"

    mv "$fields.tmp" "$fields"
    mv "$items.tmp" "$items"
}

# ------------------------------------------------------------------ consultas sobre la copia
# valor de un campo del ítem #N en un archivo de ítems ($1 archivo, $2 N, $3 Campo)
value_of() {
    awk -F '\t' -v n="$2" -v c="$3" '$2 == n { col = (c == "Status") ? 4 : (c == "Priority") ? 5 : (c == "Size") ? 6 : 0
        if (col) print $col; exit }' "$1"
}
item_of() { awk -F '\t' -v n="$2" '$2 == n { print $7; exit }' "$1"; }
field_id() { awk -F '\t' -v c="$1" '$1 == "FIELD" && $2 == c { print $3; exit }' "$FIELDS"; }
option_id() { awk -F '\t' -v c="$1" -v v="$2" '$1 == "OPTION" && $2 == c && tolower($3) == tolower(v) { print $4; exit }' "$FIELDS"; }
option_name() { awk -F '\t' -v c="$1" -v v="$2" '$1 == "OPTION" && $2 == c && tolower($3) == tolower(v) { print $3; exit }' "$FIELDS"; }
options_of() { awk -F '\t' -v c="$1" '$1 == "OPTION" && $2 == c { printf "%s%s", sep, $3; sep = ", " } END { print "" }' "$FIELDS"; }
has_add() { awk -F '\t' -v n="$1" '$1 == "add" && $2 == n { f = 1 } END { exit !f }' "$QUEUE"; }
project_id() { awk -F '\t' '$1 == "PROJECT" { print $2; exit }' "$FIELDS"; }

# encola set N Campo hacia (sustituye un cambio anterior del mismo campo)
enqueue_set() {
    local n=$1 campo=$2 valor=$3 desde nombre
    need_cache
    nombre=$(option_name "$campo" "$valor")
    [ -n "$nombre" ] || die "'$valor' no es un valor de $campo ($(options_of "$campo"))"
    if has_add "$n"; then desde="-"
    else
        desde=$(value_of "$CACHE" "$n" "$campo")
        [ -n "$desde" ] || die "#$n no está en el kanban (si es nuevo: scripts/kanban.sh nuevo $n)"
    fi
    awk -F '\t' -v n="$n" -v c="$campo" '!($1 == "set" && $2 == n && $3 == c)' "$QUEUE" > "$QUEUE.tmp"
    mv "$QUEUE.tmp" "$QUEUE"
    if [ "$desde" = "$nombre" ]; then echo "#$n ya está en $campo = $nombre"; return; fi
    printf 'set\t%s\t%s\t%s\t%s\n' "$n" "$campo" "$desde" "$nombre" >> "$QUEUE"
    echo "encolado: #$n $campo $desde -> $nombre"
}

show_queue() {
    if [ ! -s "$QUEUE" ]; then echo "Cola vacía."; return; fi
    echo "Pendiente de enviar ($(wc -l < "$QUEUE" | tr -d ' ')):"
    awk -F '\t' '$1 == "add" { printf "  + añadir #%s al proyecto\n", $2 }
                 $1 == "set" { printf "  #%s %s: %s -> %s\n", $2, $3, $4, $5 }' "$QUEUE"
}

# ------------------------------------------------------------------ envío
# Ejecuta un documento GraphQL de mutaciones; $1 = cuerpo (alias: mutación ...)
run_mutations() {
    gh api graphql -f query="mutation{ $1 }" --jq '.data | keys | length' >/dev/null
}

push() {
    need_cache
    [ -s "$QUEUE" ] || { echo "Cola vacía: nada que enviar."; return; }
    local fresh=$DIR/kanban-remoto.tsv pid body n campo desde hacia actual item fid oid keep=0 sent=0
    echo "Comprobando el kanban en GitHub..."
    fetch "$fresh" "$FIELDS"
    pid=$(project_id)

    # Fase 1: añadir al proyecto los issues nuevos que aún no están
    body=""
    while IFS="$(printf '\t')" read -r op n _; do
        [ "$op" = add ] || continue
        [ -n "$(item_of "$fresh" "$n")" ] && continue
        local node
        node=$(gh api "repos/$REPO/issues/$n" --jq .node_id) || die "no existe el issue #$n"
        body="$body a$n: addProjectV2ItemById(input:{projectId:\"$pid\", contentId:\"$node\"}){item{id}}"
    done < "$QUEUE"
    if [ -n "$body" ]; then
        run_mutations "$body"
        fetch "$fresh" "$FIELDS"   # para tener el id de los ítems recién añadidos
    fi

    # Fase 2: cambios de campos, sin pisar lo que se cambió en la web
    body=""; : > "$QUEUE.keep"
    while IFS="$(printf '\t')" read -r op n campo desde hacia; do
        [ "$op" = set ] || continue
        item=$(item_of "$fresh" "$n")
        actual=$(value_of "$fresh" "$n" "$campo")
        if [ -z "$item" ]; then
            echo "  ! #$n no está en el proyecto; se queda en la cola"; printf 'set\t%s\t%s\t%s\t%s\n' "$n" "$campo" "$desde" "$hacia" >> "$QUEUE.keep"; keep=$((keep + 1)); continue
        fi
        if [ "$actual" = "$hacia" ]; then continue; fi
        if [ "$desde" != "-" ] && [ "$actual" != "$desde" ]; then
            echo "  ! #$n $campo cambió en la web ($desde -> $actual); no se pisa con $hacia. Se queda en la cola."
            printf 'set\t%s\t%s\t%s\t%s\n' "$n" "$campo" "$desde" "$hacia" >> "$QUEUE.keep"; keep=$((keep + 1)); continue
        fi
        fid=$(field_id "$campo"); oid=$(option_id "$campo" "$hacia")
        [ -n "$fid" ] && [ -n "$oid" ] || die "campo u opción desconocidos: $campo = $hacia"
        body="$body s${n}_$campo: updateProjectV2ItemFieldValue(input:{projectId:\"$pid\", itemId:\"$item\", fieldId:\"$fid\", value:{singleSelectOptionId:\"$oid\"}}){clientMutationId}"
        sent=$((sent + 1))
    done < "$QUEUE"
    [ -z "$body" ] || run_mutations "$body"

    mv "$QUEUE.keep" "$QUEUE"
    fetch "$CACHE" "$FIELDS"
    rm -f "$fresh"
    echo "Enviados $sent cambios.$([ $keep -gt 0 ] && echo " Quedan $keep en la cola (ver arriba).")"
}

# ------------------------------------------------------------------ resumen
status() {
    need_cache
    echo "Kanban (copia del $(date -r "$CACHE" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')):"
    awk -F '\t' '$3 == "OPEN" && $4 == "In progress" { printf "  [In progress] #%s %s (%s, %s)\n", $2, $8, $5, $6 }' "$CACHE"
    awk -F '\t' '$3 == "OPEN" && $4 == "In review"   { printf "  [In review]   #%s %s\n", $2, $8 }' "$CACHE"
    awk -F '\t' '$3 == "OPEN" && $4 == "Ready"       { printf "  [Ready]       #%s %s (%s, %s)\n", $2, $8, $5, $6 }' "$CACHE"
    awk -F '\t' '$3 == "OPEN" && $4 == "Backlog" && $5 == "P0" { printf "  [P0 Backlog]  #%s %s (%s)\n", $2, $8, $6 }' "$CACHE"
    awk -F '\t' '$3 == "OPEN" { n[$4]++ } END { printf "  Abiertos por columna:"; for (k in n) printf " %s=%d", k, n[k]; print "" }' "$CACHE"
    show_queue
}

case "${1:-}" in
    pull)   fetch "$CACHE" "$FIELDS"; echo "Kanban descargado: $(awk -F '\t' '$3 == "OPEN"' "$CACHE" | wc -l | tr -d ' ') abiertos en $CACHE" ;;
    status) status ;;
    ver)    need_cache; awk -F '\t' -v q="${2:-}" '$3 == "OPEN" && (q == "" || index(tolower($0), tolower(q))) {
                printf "#%-4s %-12s %-3s %-3s %s\n", $2, $4, $5, $6, $8 }' "$CACHE" ;;
    mover)  [ $# -ge 3 ] || die "uso: mover <N> <Estado>"; n=$2; shift 2; enqueue_set "$n" Status "$*" ;;
    campo)  [ $# -eq 4 ] || die "uso: campo <N> <Priority|Size> <Valor>"; enqueue_set "$2" "$3" "$4" ;;
    nuevo)  [ $# -ge 2 ] || die "uso: nuevo <N> [Priority] [Size]"; need_cache
            has_add "$2" || printf 'add\t%s\t-\t-\t-\n' "$2" >> "$QUEUE"
            enqueue_set "$2" Status Backlog
            [ -z "${3:-}" ] || enqueue_set "$2" Priority "$3"
            [ -z "${4:-}" ] || enqueue_set "$2" Size "$4" ;;
    cola)   show_queue ;;
    push)   push ;;
    *)      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
