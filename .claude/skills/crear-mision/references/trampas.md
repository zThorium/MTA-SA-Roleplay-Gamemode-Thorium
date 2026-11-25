# Trampas de MTA y del proyecto (aprendidas a golpes)

## MTA / Lua
- **`scriptdebugloglevel 0`** (valor por defecto del servidor de Fabián): los errores y avisos de Lua no aparecen en ningún log. En el cliente usar `/debugscript 3`. Un `setPedAnimation` que devuelve `false` sin error suele ser un argumento mal.
- **`setTimer` copia las tablas** que le pasas: pasa el jugador/clave y busca el estado; cierra sobre variables locales en vez de pasar tablas.
- **Los exports no pueden recibir funciones** (sí tablas simples y elementos). `exports.recurso:funcion()` dentro de un `pcall` si el recurso es opcional.
- `dbPoll(qh, -1)` congela el servidor: siempre `dbQuery` con callback y parámetros `?`.
- **`goto`** es palabra reservada en Lua 5.2+ pero **no en 5.1** (MTA): `st.goto` y `goto = {…}` son válidos.
- Un `setElementData` en un blip/ped se sincroniza a los clientes (útil para banderas como `rp:radarEdge`, `rp:mEnemy`, `rp:mNpc`).
- `toggleAllControls(false)` impide iniciar animaciones nuevas; para congelar a un actor usar `setElementFrozen`.
- `setPedAnimationSpeed` **crashea** el cliente: no usarlo. Las animaciones personalizadas (IFP) solo existen en el cliente que las carga: hay que avisar a cada cliente.
- **Reiniciar un recurso con IFP cargado cierra MTA** (`client.dll+0xC2155`). `destroyElement(ifp)` previo es seguro.
- `getElementsByType("marker", resourceRoot, true)` recorre recursivamente; los elementos creados por el servidor cuelgan del recurso.
- Orden de eventos de entrada/salida: `rp_characters` autoguarda cada 5 min con el jugador donde esté; en misiones hay que parchear la BD (ver `mundo.md`).
- El servidor no tiene **colisiones**: para validar posiciones (enemigos) hay que usar `processLineOfSight`/`isLineOfSightClear` en el cliente.
- `Invoke-WebRequest -OutFile` interpreta `[corchetes]` como comodines; `Get-ChildItem -Filter` con rutas `[roleplay]` también (usar `-LiteralPath`).
- `rotation 0` = norte; `rz` crece en sentido antihorario: dirección "adelante" = `(-sin rz, cos rz)`, "derecha" = `(cos rz, sin rz)`. Perpendicular a la mirada para formaciones lado a lado.

## Windows / PowerShell 5.1 (el shell por defecto)
- **Nunca** `Add-Content`/`Set-Content` sin `-Encoding` sobre archivos con acentos (escribe ANSI y rompe UTF-8). Usar heredoc de bash o `[IO.File]::AppendAllText(path, texto, (New-Object Text.UTF8Encoding $false))`.
- **Nunca** normalizar codificación en masa sobre carpetas de recursos: `-Include` junto con `-LiteralPath` y `-Recurse` no filtra como se espera y **corrompe binarios** (wav/mp3/ifp). Incidente real del 2026-11-24: se recuperó deshaciendo la conversión (verificado por tamaños conocidos y cabeceras) y regenerando lo determinista.
- Pasar arrays a scripts: invocar con `&` (`& .\script.ps1 -Lista @("a","b")`); con `powershell -File` el array llega como **una sola cadena**.
- `-f` formatea con la cultura local (coma decimal): para Lua usar `.ToString("0.0", [Globalization.CultureInfo]::InvariantCulture)`.
- `Remove-Item` con comodín sobre rutas de recursos está bloqueado: borrar archivo a archivo con `-LiteralPath`.
- No hay Python, Node, ffmpeg ni luac en el equipo: usar C# vía `Add-Type` (compilador de .NET Framework incluido) para analizar binarios.
- Los `.ps1` heredoc con `'@` de PowerShell dentro de heredocs de bash dan errores de comillas: crear el archivo con la herramienta Write.

## Proyecto
- **`CLAUDE.md` NO está versionado** (commit "Deja de versionar CLAUDE.md"); el conocimiento compartido va en `.claude/skills/` y `docs/`.
- `schema.lua` del servidor local tiene tablas locales que no están en el repo (`rp_backpacks`, `rp_pool`…): nunca sobrescribir con la copia del repo ni commitear el archivo entero; insertar al final solo lo propio.
- La carpeta local es un clon de git en `main` con cambios ajenos sin commitear; no hacer `git add -A`. Para subir: clon limpio + parches propios.
- MariaDB local se corrompe con apagados sucios (`mysql.proxies_priv`): `REPAIR TABLE mysql.proxies_priv`.
- Material de Rockstar (mocap `.ifp`, `muestras/`, `map.png`) y la API key de Fish **nunca** al repo; el doblaje latino exige crédito a ZainEsc, Magotakon y colaboradores.
- `rp_citizens` y `rp_driving` pueden mostrar errores de arranque propios (`DRIVING` nil) que no son de las misiones.
