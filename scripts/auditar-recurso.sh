#!/usr/bin/env bash
# Audita un recurso contra docs/ESTANDAR_RECURSOS.md y devuelve 0 (sin fallas bloqueantes) o 1.
# Compatible con el bash 3.2 y el awk de macOS (sin arrays asociativos, sin grep -P).
#
#   scripts/auditar-recurso.sh rp_bikes          informe en consola
#   scripts/auditar-recurso.sh rp_bikes --md     informe en Markdown (para docs/auditorias/)
#   scripts/auditar-recurso.sh --todos           nota de todos los rp_* ordenada de peor a mejor
#
# Resultado de cada regla: OK | FALLA | AVISO | N/A. Nota = 100 - 15 por FALLA [B]
# - 5 por FALLA [I] - 2 por AVISO (mínimo 0). Excepciones justificadas en el código con
# un comentario "estandar:<etiqueta> <motivo>" en la línea (ver el estándar).
set -u

cd "$(dirname "$0")/.."
ROOT=$(pwd)
RECURSOS="$ROOT/RECURSOS.md"
CONF="$ROOT/mtaserver.conf"
CATALOG="$ROOT/resources/[roleplay]/rp_adminpanel/server/s_catalog.lua"
HELPCFG="$ROOT/resources/[roleplay]/rp_help/shared/s_config.lua"
TESTDIR="$ROOT/resources/[test]/rp_test"
DEV_ONLY=" rp_animlab rp_test "     # no van en mtaserver.conf

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

# ----------------------------------------------------------------- todos
if [ "${1:-}" = "--todos" ]; then
    printf '%-18s %5s %7s %7s %6s\n' RECURSO NOTA FALLA_B FALLA_I AVISOS
    for d in "$ROOT"/resources/\[roleplay\]/rp_*/; do
        n=$(basename "$d")
        out=$("$0" "$n" 2>/dev/null)
        nota=$(printf '%s\n' "$out" | sed -n 's/^NOTA: \([0-9]*\).*/\1/p')
        fb=$(printf '%s\n' "$out" | grep -c '^FALLA  \[B\]')
        fi=$(printf '%s\n' "$out" | grep -c '^FALLA  \[I\]')
        av=$(printf '%s\n' "$out" | grep -c '^AVISO')
        printf '%-18s %5s %7s %7s %6s\n' "$n" "$nota" "$fb" "$fi" "$av"
    done | sort -k2 -n
    exit 0
fi

NAME="${1:-}"; [ -n "$NAME" ] || usage
MD=0; [ "${2:-}" = "--md" ] && MD=1
DIR=""
for cand in "$ROOT"/resources/*/"$NAME"; do [ -d "$cand" ] && DIR="$cand"; done
[ -n "$DIR" ] || { echo "No existe el recurso $NAME en resources/*/" >&2; exit 2; }
META="$DIR/meta.xml"
RELDIR=${DIR#"$ROOT"/}
[ -f "$META" ] || { echo "$NAME no tiene meta.xml" >&2; exit 2; }

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t audit)
trap 'rm -rf "$TMP"' EXIT
RESULTS="$TMP/results"; : > "$RESULTS"

rel() { case "$1" in "$SRC"/*) printf '%s' "$RELDIR/${1#"$SRC"/}" ;; *) printf '%s' "${1#"$ROOT"/}" ;; esac; }
# res ESTADO GRAVEDAD ID "titulo" "detalle"
res() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}" >> "$RESULTS"; }
# Limita el detalle a 6 evidencias
cap() { awk 'NR<=6' | tr '\n' ';' | sed 's/;$//; s/;/ ; /g'; }

# --------------------------------------------------------------- inventario
# Copia de cada .lua sin comentarios (mismas líneas) en $SRC: los greps no ven código comentado.
# Las líneas con "estandar:" se conservan enteras para poder leer las excepciones.
SRC="$TMP/src"
uncomment() {
    awk 'BEGIN { inb = 0 }
    { sub(/\r$/, ""); s = $0; out = ""
      while (length(s) > 0) {
          if (inb) { p = index(s, "]]"); if (p == 0) { s = ""; break } s = substr(s, p + 2); inb = 0; continue }
          p = index(s, "--")
          if (p == 0) { out = out s; break }
          out = out substr(s, 1, p - 1); rest = substr(s, p + 2)
          if (rest ~ /^\[=*\[/) { inb = 1; sub(/^\[=*\[/, "", rest); s = rest; continue }
          break
      }
      print (($0 ~ /estandar:/) ? $0 : out) }' "$1"
}
find "$DIR" -name '*.lua' -not -path '*/tools/*' -not -name '*.example.lua' | sort > "$TMP/lua"
while IFS= read -r f; do
    r=${f#"$DIR"/}; mkdir -p "$SRC/$(dirname "$r")"; uncomment "$f" > "$SRC/$r"
done < "$TMP/lua"
# Scripts declarados en meta.xml: "tipo<TAB>ruta"
grep -oE '<script[^>]*>' "$META" | while IFS= read -r tag; do
    src=$(printf '%s' "$tag" | sed -n 's/.*src="\([^"]*\)".*/\1/p')
    typ=$(printf '%s' "$tag" | sed -n 's/.*type="\([^"]*\)".*/\1/p')
    printf '%s\t%s\n' "${typ:-server}" "$src"
done > "$TMP/scripts"
awk -F'\t' '$1=="server"||$1=="shared"{print $2}' "$TMP/scripts" | while IFS= read -r f; do [ -f "$SRC/$f" ] && printf '%s\n' "$SRC/$f"; done > "$TMP/server"
awk -F'\t' '$1=="client"||$1=="shared"{print $2}' "$TMP/scripts" | while IFS= read -r f; do [ -f "$SRC/$f" ] && printf '%s\n' "$SRC/$f"; done > "$TMP/client"
find "$SRC" -name '*.lua' | sort > "$TMP/luas"
awk -F'\t' '{print $2}' "$TMP/scripts" | sed "s#^#$DIR/#" | sort -u > "$TMP/declared"

# grep sobre una lista de archivos (vacía => nada)
lgrep() { list="$1"; shift; [ -s "$list" ] || return 1; tr '\n' '\0' < "$list" | xargs -0 grep "$@" 2>/dev/null; }
hasany() { lgrep "$1" -qE "$2"; }
# Quita la ruta absoluta de la salida de grep -n
strip() { sed "s#^$SRC/#$RELDIR/#; s#^$ROOT/##"; }
# Filtra líneas con excepción justificada "estandar:<etiqueta>"
noexc() { grep -v "estandar:$1"; }

# ===================================================================== EST
if grep -q '<info' "$META" && grep -qE '<info[^>]*author=' "$META" && grep -qE '<info[^>]*description=' "$META" \
   && grep -qE '<info[^>]*version=' "$META" && grep -q '<min_mta_version' "$META"; then
    res OK B EST-01 "meta.xml con info y min_mta_version"
else
    res FALLA B EST-01 "meta.xml con info y min_mta_version" "falta <info author/description/version> o <min_mta_version>"
fi

bad=$(grep -nE '<script[^>]*type="client"' "$META" | grep -v 'cache="false"' | sed 's/^\([0-9]*\):.*src="\([^"]*\)".*/meta.xml:\1 \2/' | cap)
[ -z "$bad" ] && res OK I EST-02 'Scripts de cliente con cache="false"' || res FALLA I EST-02 'Scripts de cliente con cache="false"' "$bad"

# EST-03: dependencias. Una dependencia opcional (sin <include>) es válida si el código comprueba
# antes que el recurso está en marcha con getResourceFromName("rp_x") o lleva "estandar:dep-opcional".
lgrep "$TMP/luas" -ohE 'exports\.[A-Za-z0-9_]+|exports\["[A-Za-z0-9_]+"\]' | sed -E 's/exports\.//; s/exports\["//; s/"\]//' | sort -u > "$TMP/used"
grep -oE '<include resource="[^"]+"' "$META" | sed 's/.*"\(.*\)"/\1/' | sort -u > "$TMP/incl"
missing=$(grep -vxF -f "$TMP/incl" "$TMP/used" 2>/dev/null | grep -vx "$NAME" | while IFS= read -r dep; do
    lgrep "$TMP/luas" -qE "getResourceFromName\([[:space:]]*\"$dep\"|estandar:dep-opcional $dep" || echo "$dep"
done | cap)
[ -z "$missing" ] && res OK I EST-03 "Dependencias declaradas con <include> (u opcionales comprobadas)" \
                  || res FALLA I EST-03 "Dependencias declaradas con <include> (u opcionales comprobadas)" "sin include: $missing"

gone=""
for f in $(grep -oE '<(script|file|config)[^>]*src="[^"]+"' "$META" | sed 's/.*src="\([^"]*\)"/\1/' | grep -v '^:'); do
    [ -f "$DIR/$f" ] || gone="$gone $f"
done
orphan=$(grep -vxF -f "$TMP/declared" "$TMP/lua" 2>/dev/null | while IFS= read -r f; do rel "$f"; echo; done | cap)
if [ -n "$gone" ]; then res FALLA I EST-04 "meta.xml y archivos coinciden" "declarado y no existe:$gone"
elif [ -n "$orphan" ]; then res AVISO I EST-04 "meta.xml y archivos coinciden" "lua sin declarar: $orphan"
else res OK I EST-04 "meta.xml y archivos coinciden"; fi

badname=$(while IFS= read -r f; do
    r=${f#"$DIR"/}; b=$(basename "$f")
    case "$r" in
        server/*) case "$b" in s_*) ;; *) echo "$r";; esac ;;
        client/*) case "$b" in c_*) ;; *) echo "$r";; esac ;;
        shared/*) case "$b" in s_*|c_*) ;; *) echo "$r";; esac ;;
    esac
done < "$TMP/lua" | cap)
[ -z "$badname" ] && res OK I EST-05 "Prefijos s_/c_ según carpeta" || res AVISO I EST-05 "Prefijos s_/c_ según carpeta" "$badname"

nohead=$(while IFS= read -r f; do
    first=$(grep -m1 -vE '^[[:space:]]*$' "$f" | tr -d '\r')
    case "$first" in --*) ;; *) rel "$f"; echo;; esac
done < "$TMP/lua" | cap)
[ -z "$nohead" ] && res OK R EST-06 "Cabecera de comentario en cada .lua" || res AVISO R EST-06 "Cabecera de comentario en cada .lua" "$nohead"

case "$DEV_ONLY" in
    *" $NAME "*) res N/A B EST-07 "Registrado en mtaserver.conf tras sus dependencias" "recurso solo de desarrollo" ;;
    *)
    self=$(grep -n "resource src=\"$NAME\"" "$CONF" | head -1 | cut -d: -f1)
    if [ -z "$self" ]; then res FALLA B EST-07 "Registrado en mtaserver.conf tras sus dependencias" "no está en mtaserver.conf"
    else
        late=""
        while IFS= read -r dep; do
            l=$(grep -n "resource src=\"$dep\"" "$CONF" | head -1 | cut -d: -f1)
            if [ -z "$l" ]; then late="$late $dep(no está)"; elif [ "$l" -gt "$self" ]; then late="$late $dep(después)"; fi
        done < "$TMP/incl"
        [ -z "$late" ] && res OK B EST-07 "Registrado en mtaserver.conf tras sus dependencias" \
                       || res FALLA B EST-07 "Registrado en mtaserver.conf tras sus dependencias" "dependencias mal ordenadas:$late"
    fi ;;
esac

# ===================================================================== SEG
# SEG-01: cada handler de un evento remoto (addEvent(..., true)) usa `client`
lgrep "$TMP/server" -ohE 'addEvent\([[:space:]]*"[^"]+"[[:space:]]*,[[:space:]]*true' | sed 's/.*"\([^"]*\)".*/\1/' | sort -u > "$TMP/remote"
seg1=""
if [ -s "$TMP/remote" ] && [ -s "$TMP/server" ]; then
    seg1=$(tr '\n' '\0' < "$TMP/server" | xargs -0 awk -v evlist="$(tr '\n' ' ' < "$TMP/remote")" '
        function indent(s) { match(s, /^[ \t]*/); return RLENGTH }
        BEGIN { n = split(evlist, a, " "); for (i = 1; i <= n; i++) remote[a[i]] = 1 }
        { sub(/\r$/, ""); line[FILENAME, FNR] = $0; last[FILENAME] = FNR }
        FNR == 1 { files[++nf] = FILENAME }
        END {
            for (fi = 1; fi <= nf; fi++) { f = files[fi]
                for (i = 1; i <= last[f]; i++) { s = line[f, i]
                    if (s !~ /function[ \t]+[A-Za-z_][A-Za-z0-9_.:]*[ \t]*\(/) continue
                    nm = s; sub(/.*function[ \t]+/, "", nm); sub(/[ \t]*\(.*/, "", nm); sub(/.*[.:]/, "", nm)
                    fstart[nm] = f SUBSEP i
                }
            }
            for (fi = 1; fi <= nf; fi++) { f = files[fi]
                for (i = 1; i <= last[f]; i++) { s = line[f, i]
                    if (s !~ /addEventHandler[ \t]*\([ \t]*"/) continue
                    ev = s; sub(/^[^"]*"/, "", ev); sub(/".*/, "", ev)
                    if (!(ev in remote)) continue
                    if (s ~ /estandar:sin-client/) continue
                    body = ""; ok = 0
                    if (s ~ /function[ \t]*\(/) {
                        ind = indent(s)
                        for (j = i; j <= last[f] && j < i + 400; j++) {
                            body = body "\n" line[f, j]
                            if (j > i && indent(line[f, j]) == ind && line[f, j] ~ /^[ \t]*end\)/) break
                        }
                    } else {
                        nm = s; sub(/^[^"]*"[^"]*"[ \t]*,[^,]*,[ \t]*/, "", nm); sub(/[^A-Za-z0-9_.].*/, "", nm); sub(/.*[.:]/, "", nm)
                        if (!(nm in fstart)) continue
                        split(fstart[nm], p, SUBSEP); ff = p[1]; st = p[2] + 0; ind = indent(line[ff, st])
                        for (j = st; j <= last[ff] && j < st + 400; j++) {
                            body = body "\n" line[ff, j]
                            if (j > st && indent(line[ff, j]) == ind && line[ff, j] ~ /^[ \t]*end[ \t]*$/) break
                        }
                    }
                    if (body ~ /[^A-Za-z0-9_]client[^A-Za-z0-9_]/ || body ~ /estandar:sin-client/) ok = 1
                    if (!ok) print f ":" i " " ev
                }
            }
        }' | strip | cap)
fi
if [ ! -s "$TMP/remote" ]; then res N/A B SEG-01 "Handlers de eventos remotos usan client" "sin eventos remotos"
elif [ -z "$seg1" ]; then res OK B SEG-01 "Handlers de eventos remotos usan client"
else res FALLA B SEG-01 "Handlers de eventos remotos usan client" "$seg1"; fi

sec=$(find "$DIR" -type f \( -name '*.lua' -o -name '*.js' -o -name '*.html' -o -name '*.xml' -o -name '*.json' \) \
        -not -name 'config.lua' -not -name '*.example.*' -not -path '*/tools/*' -print0 \
      | xargs -0 grep -nIiE '(password|passwd|api[_-]?key|secret|token)[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"' ]{8,}["'"'"']|[^0-9](192\.168|10\.[0-9]+\.[0-9]+)\.[0-9]+[^0-9]|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(com|net|org|cl|es|io)([^A-Za-z]|$)' 2>/dev/null \
      | noexc secreto | strip | cut -c1-140 | cap)
[ -z "$sec" ] && res OK B SEG-05 "Sin secretos, IPs privadas ni emails" || res FALLA B SEG-05 "Sin secretos, IPs privadas ni emails" "$sec"

ls=$(lgrep "$TMP/luas" -nE '(^|[^A-Za-z0-9_])loadstring[[:space:]]*\(' | noexc loadstring | strip | cut -c1-120 | cap)
[ -z "$ls" ] && res OK B SEG-06 "Sin loadstring" || res FALLA B SEG-06 "Sin loadstring" "$ls"

# ====================================================================== BD
if [ "$NAME" = "rp_database" ]; then
    res N/A B BD-01 "Sin dbConnect propio" "es el dueño de la conexión"
else
    c=$(lgrep "$TMP/luas" -nE 'dbConnect[[:space:]]*\(' | strip | cap)
    [ -z "$c" ] && res OK B BD-01 "Sin dbConnect propio" || res FALLA B BD-01 "Sin dbConnect propio" "$c"
fi

sync=$( [ -s "$TMP/server" ] && tr '\n' '\0' < "$TMP/server" | xargs -0 awk '
    { sub(/\r$/, ""); l[FILENAME, FNR] = $0; last[FILENAME] = FNR } FNR == 1 { fs[++n] = FILENAME }
    END { for (k = 1; k <= n; k++) { f = fs[k]
        for (i = 1; i <= last[f]; i++) if (l[f, i] ~ /dbPoll[ \t]*\(/) {
            j = l[f, i] " " l[f, i+1] " " l[f, i+2]; pre = l[f, i-1]
            if (j ~ /,[ \t]*-1[ \t]*\)/ && j !~ /estandar:sincrono/ && pre !~ /estandar:sincrono/) print f ":" i
        } } }' | strip | cap)
[ -z "$sync" ] && res OK B BD-02 "Sin dbPoll(-1) sin justificar" || res FALLA B BD-02 "Sin dbPoll(-1) sin justificar" "$sync"

# Solo cuenta lo que se pega AL TEXTO SQL ("SELECT ..." .. x, x .. "WHERE ...", ("...%s"):format(x)).
# Unir dos textos fijos o concatenar dentro de un parámetro ("%" .. q .. "%") es seguro.
sqlc=$(lgrep "$TMP/server" -nE '(SELECT[[:space:]]|INSERT[[:space:]]+INTO|UPDATE[[:space:]]+[A-Za-z_]+[[:space:]]+SET|DELETE[[:space:]]+FROM)' \
       | awk '{ s = $0
           if (!match(s, /"[^"]*(SELECT[ \t]|INSERT[ \t]+INTO|UPDATE[ \t]+[A-Za-z_]+[ \t]+SET|DELETE[ \t]+FROM)[^"]*"/)) next
           before = substr(s, 1, RSTART - 1); after = substr(s, RSTART + RLENGTH)
           bad = 0
           if (after ~ /^[ \t]*\.\.[ \t]*[^" \t]/) bad = 1                       # "SQL" .. variable
           if (before ~ /[^"\] \t][ \t]*\.\.[ \t]*$/) bad = 1                    # variable .. "SQL"
           if (after ~ /^[ \t]*\)[ \t]*:[ \t]*format[ \t]*\(/ || before ~ /string\.format[ \t]*\([ \t]*$/) bad = 1
           if (bad) print }' \
       | noexc sql-seguro | strip | cut -c1-140 | cap)
[ -z "$sqlc" ] && res OK B BD-03 "SQL parametrizado (sin concatenar)" || res FALLA B BD-03 "SQL parametrizado (sin concatenar)" "$sqlc"

if [ "$NAME" = "rp_database" ]; then res N/A B BD-04 "Esquema solo en rp_database/schema.lua"
else
    ddl=$(lgrep "$TMP/luas" -niE '(CREATE[[:space:]]+TABLE|ALTER[[:space:]]+TABLE|DROP[[:space:]]+TABLE)' | strip | cut -c1-120 | cap)
    [ -z "$ddl" ] && res OK B BD-04 "Esquema solo en rp_database/schema.lua" || res FALLA B BD-04 "Esquema solo en rp_database/schema.lua" "$ddl"
fi

if hasany "$TMP/server" 'getConnection[[:space:]]*\(' && [ "$NAME" != "rp_database" ]; then
    if hasany "$TMP/server" 'isReady[[:space:]]*\(|rp:onDatabaseReady'; then res OK I BD-05 "Espera a la BD al arrancar"
    else res AVISO I BD-05 "Espera a la BD al arrancar" "usa getConnection sin isReady()/rp:onDatabaseReady (revisa si consulta antes de que la BD esté lista)"; fi
else res N/A I BD-05 "Espera a la BD al arrancar" "no usa la BD"; fi

# ===================================================================== CIC
perplayer=0
hasany "$TMP/server" '\[[[:space:]]*(player|p|plr|client|thePlayer|source)[[:space:]]*\][[:space:]]*=[^=]' && perplayer=1
if [ "$perplayer" = 1 ]; then
    hasany "$TMP/server" '"onPlayerQuit"' && res OK I CIC-01 "Estado por jugador se limpia en onPlayerQuit" \
        || res FALLA I CIC-01 "Estado por jugador se limpia en onPlayerQuit" "hay tablas [player] = ... sin handler de onPlayerQuit"
    if hasany "$TMP/server" 'getPlayerCharacterId'; then
        hasany "$TMP/server" 'rp:onCharacterLogout' && res OK I CIC-02 "Estado por personaje se limpia en rp:onCharacterLogout" \
            || res AVISO I CIC-02 "Estado por personaje se limpia en rp:onCharacterLogout" "estado por jugador ligado a personaje sin rp:onCharacterLogout"
    else res N/A I CIC-02 "Estado por personaje se limpia en rp:onCharacterLogout" "no usa personajes"; fi
else
    res N/A I CIC-01 "Estado por jugador se limpia en onPlayerQuit" "sin estado por jugador"
    res N/A I CIC-02 "Estado por personaje se limpia en rp:onCharacterLogout" "sin estado por jugador"
fi

if hasany "$TMP/luas" 'setTimer[[:space:]]*\('; then
    hasany "$TMP/luas" 'killTimer|isTimer' && res OK I CIC-04 "Los timers se pueden cancelar" \
        || res AVISO I CIC-04 "Los timers se pueden cancelar" "usa setTimer y nunca killTimer/isTimer"
else res N/A I CIC-04 "Los timers se pueden cancelar"; fi

if hasany "$TMP/client" 'setHudSuppressed|setRadioSuppressed|toggleAllControls[[:space:]]*\([[:space:]]*false|setCameraMatrix|showCursor[[:space:]]*\([[:space:]]*true|fadeCamera[[:space:]]*\([[:space:]]*false'; then
    hasany "$TMP/client" '"onClientResourceStop"' && res OK I CIC-05 "El cliente devuelve cámara/controles/HUD al parar" \
        || res FALLA I CIC-05 "El cliente devuelve cámara/controles/HUD al parar" "toca cámara/controles/cursor/HUD sin onClientResourceStop"
else res N/A I CIC-05 "El cliente devuelve cámara/controles/HUD al parar"; fi

# ===================================================================== INT
i1=""
[ "$NAME" != "rp_hud" ] && i1=$(lgrep "$TMP/luas" -nE 'setElementData\([^)]*"rp:hudHidden"' | strip | cap)
[ "$NAME" != "rp_radio" ] && i1="$i1$(lgrep "$TMP/luas" -nE 'setRadioChannel[[:space:]]*\(' | noexc radio | strip | cap)"
[ -z "$i1" ] && res OK B INT-01 "HUD y radio solo con setHudSuppressed/setRadioSuppressed" \
             || res FALLA B INT-01 "HUD y radio solo con setHudSuppressed/setRadioSuppressed" "$i1"

if [ "$NAME" != "rp_events" ]; then
    tw=$(lgrep "$TMP/luas" -nE '(^|[^A-Za-z_.:])(setTime|setWeather|setWeatherBlended|setMinuteDuration)[[:space:]]*\(' | noexc mundo | strip | cut -c1-120 | cap)
    [ -z "$tw" ] && res OK I INT-02 "Hora y clima solo desde rp_events" || res AVISO I INT-02 "Hora y clima solo desde rp_events" "$tw"
else res N/A I INT-02 "Hora y clima solo desde rp_events"; fi

ev=$(lgrep "$TMP/luas" -ohE 'addEvent\([[:space:]]*"[^"]+"' | sed 's/.*"\([^"]*\)"/\1/' | grep -vE '^rp:' | sort -u | cap)
[ -z "$ev" ] && res OK I INT-03 'Eventos propios con prefijo "rp:"' || res FALLA I INT-03 'Eventos propios con prefijo "rp:"' "$ev"

nchat=$(lgrep "$TMP/luas" -cE 'outputChatBox[[:space:]]*\(' | awk -F: '{s+=$NF} END{print s+0}')
if [ "$NAME" = "rp_chat" ] || [ "$nchat" -le 15 ]; then res OK R INT-04 "Avisos con rp_notify (no outputChatBox)" "$nchat outputChatBox"
else res AVISO R INT-04 "Avisos con rp_notify (no outputChatBox)" "$nchat outputChatBox: revisar si son avisos de acciones"; fi

# INT-05: bases de dimensión únicas entre recursos
mydims=$(lgrep "$TMP/luas" -ohE '(DIMENSION_BASE|DIM_BASE|DIMENSION)[[:space:]]*=[[:space:]]*[0-9]{3,}' | grep -oE '[0-9]+$' | sort -u)
clash=""
for v in $mydims; do
    others=$(grep -rlE "(DIMENSION_BASE|DIM_BASE|DIMENSION)[[:space:]]*=[[:space:]]*$v([^0-9]|$)" --include='*.lua' "$ROOT"/resources/\[roleplay\]/ 2>/dev/null \
             | sed "s#^$ROOT/resources/\[roleplay\]/##; s#/.*##" | sort -u | grep -vx "$NAME" | grep -vE '^(rp_properties|rp_furniture)$' | tr '\n' ' ')
    [ -n "$others" ] && clash="$clash $v comparte con: $others;"
done
if [ -z "$mydims" ]; then res N/A B INT-05 "Dimensiones propias sin choques"
elif [ -z "$clash" ]; then res OK B INT-05 "Dimensiones propias sin choques" "$(echo $mydims)"
else res FALLA B INT-05 "Dimensiones propias sin choques" "$clash"; fi

# INT-06: teclas globales que ya usa otro recurso (sin contar las contextuales)
mykeys=$(lgrep "$TMP/client" -ohE 'bindKey\([[:space:]]*"[^"]+"' | sed 's/.*"\([^"]*\)"/\1/' | tr 'A-Z' 'a-z' | sort -u \
         | grep -vE '^(e|y|n|enter|backspace|space|tab|escape|delete|lshift|rshift|lctrl|rctrl|lalt|ralt|mouse.*|arrow_.|[0-9wasd]|num_.*)$')
kc=""
for k in $mykeys; do
    o=$(grep -rliE "bindKey\([[:space:]]*\"$k\"" --include='*.lua' "$ROOT"/resources/\[roleplay\]/ 2>/dev/null \
        | sed "s#^$ROOT/resources/\[roleplay\]/##; s#/.*##" | sort -u | grep -vx "$NAME" | tr '\n' ' ')
    [ -n "$o" ] && kc="$kc $k: $o;"
done
[ -z "$kc" ] && res OK R INT-06 "Teclas sin choques con otros recursos" "$(echo $mykeys)" || res AVISO R INT-06 "Teclas sin choques con otros recursos" "$kc"

# ===================================================================== CLI
kb=$(while IFS= read -r f; do
    grep -qE 'bindKey[[:space:]]*\(' "$f" || continue
    grep -qE 'isChatBoxInputActive|isCursorShowing|isConsoleActive' "$f" || { rel "$f"; echo; }
done < "$TMP/client" | cap)
[ -z "$kb" ] && res OK I CLI-01 "Las teclas ignoran chat/consola/cursor" || res AVISO I CLI-01 "Las teclas ignoran chat/consola/cursor" "$kb"

rend=$(lgrep "$TMP/client" -nE 'onClientRender' >/dev/null && tr '\n' '\0' < "$TMP/client" | xargs -0 awk '
    function indent(s) { match(s, /^[ \t]*/); return RLENGTH }
    { sub(/\r$/, "") }
    /addEventHandler[ \t]*\([ \t]*"onClient(Pre)?Render"[ \t]*,[^,]*,[ \t]*function/ { inr = 1; ind = indent($0); st = FNR; next }
    inr && /getElementsByType|dbQuery|fileOpen|dxCreateTexture|dxCreateFont|engineLoad/ { print FILENAME ":" FNR }
    inr && indent($0) == ind && /^[ \t]*end\)/ { inr = 0 }' 2>/dev/null | strip | cap)
[ -z "$rend" ] && res OK R CLI-02 "onClientRender sin trabajo pesado por frame" || res AVISO R CLI-02 "onClientRender sin trabajo pesado por frame" "$rend"

# CLI-04: un script de cliente cache="false" puede ejecutarse ANTES que un script shared cacheado
# (sin cache="false"). Si al cargar copia una global de ese archivo (local C = CONFIG), queda nil.
grep -oE '<script[^>]*>' "$META" | grep -E 'type="shared"' | grep -v 'cache="false"' | sed -n 's/.*src="\([^"]*\)".*/\1/p' > "$TMP/sharedcached"
cli4=""
if [ -s "$TMP/sharedcached" ]; then
    while IFS= read -r s; do [ -f "$SRC/$s" ] && grep -ohE '^[A-Z][A-Z0-9_]+[[:space:]]*=' "$SRC/$s" | sed 's/[[:space:]]*=//'; done < "$TMP/sharedcached" | sort -u > "$TMP/cachedglobals"
    grep -oE '<script[^>]*>' "$META" | grep -E 'type="client"' | grep 'cache="false"' | sed -n 's/.*src="\([^"]*\)".*/\1/p' | while IFS= read -r c; do
        [ -f "$SRC/$c" ] || continue
        while IFS= read -r g; do
            grep -nE "^local[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*$g([^A-Za-z0-9_]|\$)" "$SRC/$c" | sed "s#^#$SRC/$c:#"
        done < "$TMP/cachedglobals"
    done | strip | cut -c1-120 > "$TMP/cli4"
    cli4=$(cap < "$TMP/cli4")
fi
[ -z "$cli4" ] && res OK I CLI-04 "El cliente no copia config compartida al cargar" \
               || res FALLA I CLI-04 "El cliente no copia config compartida al cargar" "$cli4 (léela en onClientResourceStart o marca el shared con cache=\"false\")"

# ===================================================================== DOC
grep -q "\`$NAME\`" "$RECURSOS" && res OK B DOC-01 "Fila en RECURSOS.md" || res FALLA B DOC-01 "Fila en RECURSOS.md" "no aparece \`$NAME\`"

exp=$(grep -oE '<export[^>]*function="[^"]+"' "$META" | sed 's/.*function="\([^"]*\)"/\1/' | sort -u | while IFS= read -r e; do
    grep -q "$e" "$RECURSOS" || echo "$e"; done | cap)
[ -z "$exp" ] && res OK I DOC-02 "Exports documentados en RECURSOS.md" || res AVISO I DOC-02 "Exports documentados en RECURSOS.md" "$exp"

cmds=$(lgrep "$TMP/luas" -ohE 'addCommandHandler\([[:space:]]*"[^"]+"' | sed 's/.*"\([^"]*\)"/\1/' | sort -u | while IFS= read -r c; do
    grep -qiE "/$c([^A-Za-z0-9_]|$)" "$RECURSOS" "$CATALOG" "$HELPCFG" 2>/dev/null || echo "/$c"; done | cap)
[ -z "$cmds" ] && res OK I DOC-03 "Comandos en RECURSOS.md, panel de admin o ayuda" || res AVISO I DOC-03 "Comandos en RECURSOS.md, panel de admin o ayuda" "$cmds"

[ -f "$ROOT/docs/auditorias/$NAME.md" ] && res OK R DOC-04 "Registro de auditoría en docs/auditorias/" \
    || res AVISO R DOC-04 "Registro de auditoría en docs/auditorias/" "falta docs/auditorias/$NAME.md"

# ===================================================================== PRU
if hasany "$TMP/server" 'getConnection[[:space:]]*\(' && [ "$NAME" != "rp_test" ]; then
    grep -rqE "$NAME|exports\.$NAME" "$TESTDIR" 2>/dev/null && res OK I PRU-01 "Pruebas en rp_test" \
        || res AVISO I PRU-01 "Pruebas en rp_test" "usa la BD y rp_test no lo menciona"
else res N/A I PRU-01 "Pruebas en rp_test" "no usa la BD"; fi

# ================================================================== informe
fb=$(grep -c "^FALLA	B" "$RESULTS"); fi_=$(grep -c "^FALLA	I" "$RESULTS"); fr=$(grep -c "^FALLA	R" "$RESULTS")
av=$(grep -c "^AVISO" "$RESULTS"); okc=$(grep -c "^OK" "$RESULTS")
nota=$((100 - 15 * fb - 5 * fi_ - 2 * fr - 2 * av)); [ "$nota" -lt 0 ] && nota=0
fecha=$(date '+%Y-%m-%d')
commit=$(git rev-parse --short HEAD 2>/dev/null || echo "?")

if [ "$MD" = 1 ]; then
    echo "### Auditoría automática ($fecha, commit $commit)"
    echo
    echo "**Nota: $nota/100** · OK $okc · FALLA B $fb · FALLA I $fi_ · AVISO $av"
    echo
    echo "| Estado | Grav. | Regla | Qué | Evidencia |"
    echo "|---|---|---|---|---|"
    for st in FALLA AVISO OK N/A; do
        awk -F'\t' -v st="$st" '$1 == st { for (k = 4; k <= 5; k++) { gsub(/\|/, "\\|", $k); gsub(/</, "\\&lt;", $k); gsub(/>/, "\\&gt;", $k) }
            printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5 }' "$RESULTS"
    done
else
    echo "== Auditoría de $NAME ($(rel "$DIR"))  $fecha  commit $commit"
    for st in FALLA AVISO OK N/A; do
        awk -F'\t' -v st="$st" '$1==st { printf "%-6s [%s] %-7s %s%s\n", $1, $2, $3, $4, ($5 != "" ? "\n         -> " $5 : "") }' "$RESULTS"
    done
    echo
    echo "Reglas manuales (docs/ESTANDAR_RECURSOS.md): B: SEG-02 SEG-04 BD-06 PRU-02 · I: EST-08 SEG-03 SEG-07 BD-07 CIC-03 CIC-06 INT-07 INT-08 CLI-03 DOC-05"
    echo "NOTA: $nota/100  (OK $okc, FALLA B $fb, FALLA I $fi_, AVISO $av)"
fi
[ "$fb" -eq 0 ]
