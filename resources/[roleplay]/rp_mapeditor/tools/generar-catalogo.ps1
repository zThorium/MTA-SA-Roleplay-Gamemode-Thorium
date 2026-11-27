# rp_mapeditor / tools / generar-catalogo.ps1
# Genera shared/s_models.lua: catalogo de todos los objetos de GTA SA (id, nombre, grupo) leyendo
# los IDE de data/default.dat (armas) y data/gta.dat (mapa, props, piezas de auto). Los LOD ("lod...") se omiten.
#
#   powershell -File "resources/[roleplay]/rp_mapeditor/tools/generar-catalogo.ps1" [-Gta "<ruta GTA SA>"]
#
# Sin -Gta, la ruta sale del registro de MTA (GTA:SA Path). Solo se guardan ids y nombres de modelo,
# no archivos del juego.
param([string]$Gta)

$ErrorActionPreference = "Stop"
if (-not $Gta) {
    foreach ($k in @("HKLM:\SOFTWARE\WOW6432Node\Multi Theft Auto: San Andreas All\Common",
                     "HKLM:\SOFTWARE\Multi Theft Auto: San Andreas All\Common")) {
        try { $Gta = (Get-ItemProperty -Path $k -Name "GTA:SA Path" -ErrorAction Stop)."GTA:SA Path"; break } catch {}
    }
}
if (-not $Gta -or -not (Test-Path (Join-Path $Gta "data\gta.dat"))) { throw "No encuentro GTA SA; pasa -Gta <ruta>" }

$FOLDERS = @{ "generic" = "Genericos"; "la" = "Los Santos"; "sf" = "San Fierro"; "vegas" = "Las Venturas";
              "country" = "Campo"; "interior" = "Interiores"; "leveldes" = "Varios" }
$SKIP = @("txdcut", "vehicles", "peds")

$groups = New-Object System.Collections.ArrayList
$seen = @{}
$models = New-Object System.Collections.ArrayList

$ideLines = @(Get-Content (Join-Path $Gta "data\default.dat")) + @(Get-Content (Join-Path $Gta "data\gta.dat"))
foreach ($line in $ideLines) {
    if ($line -notmatch '^\s*IDE\s+(.+)$') { continue }
    $rel = $Matches[1].Trim()
    $file = Join-Path $Gta $rel
    if (-not (Test-Path $file)) { continue }
    $base = [IO.Path]::GetFileNameWithoutExtension($rel).ToLower()
    if ($SKIP -contains $base) { continue }
    $parts = $rel -split '[\\/]'
    $folder = if ($parts.Length -ge 3) { $parts[$parts.Length - 2].ToLower() } else { "generic" }
    $fname = $FOLDERS[$folder]; if (-not $fname) { $fname = $folder }
    $gname = "$fname / $([IO.Path]::GetFileNameWithoutExtension($rel))"
    [void]$groups.Add($gname)
    $gi = $groups.Count

    $section = ""
    foreach ($l in Get-Content $file) {
        $t = ($l -replace '#.*$', '').Trim()
        if ($t -eq "") { continue }
        if ($t -match '^[a-zA-Z]+$') { $section = if ($t -eq "end") { "" } else { $t.ToLower() }; continue }
        if ($section -ne "objs" -and $section -ne "tobj" -and $section -ne "anim" -and $section -ne "weap") { continue }
        $f = $t -split '\s*,\s*'
        if ($f.Length -lt 2) { continue }
        $id = 0
        if (-not [int]::TryParse($f[0], [ref]$id)) { continue }
        $name = $f[1]
        if ($name -match '^lod' -or $seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        [void]$models.Add(@($id, ($name -replace '[^A-Za-z0-9_\-]', ''), $gi))
    }
}

$sorted = $models | Sort-Object { $_[0] }
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("--[[")
[void]$sb.AppendLine("    rp_mapeditor / s_models.lua  (servidor, GENERADO por tools/generar-catalogo.ps1: no editar a mano)")
[void]$sb.AppendLine("    Catalogo de objetos de GTA SA: MAPEDIT_MODELS = { {id, nombre, grupo}, ... } y MAPEDIT_GROUPS.")
[void]$sb.AppendLine("    $($sorted.Count) modelos (sin LOD).")
[void]$sb.AppendLine("]]")
[void]$sb.AppendLine("MAPEDIT_GROUPS = {")
foreach ($g in $groups) { [void]$sb.AppendLine("    `"$g`",") }
[void]$sb.AppendLine("}")
[void]$sb.AppendLine("MAPEDIT_MODELS = {")
$row = New-Object System.Text.StringBuilder
$n = 0
foreach ($m in $sorted) {
    [void]$row.Append("{$($m[0]),`"$($m[1])`",$($m[2])},")
    $n++
    if ($n % 6 -eq 0) { [void]$sb.AppendLine($row.ToString()); [void]$row.Clear() }
}
if ($row.Length -gt 0) { [void]$sb.AppendLine($row.ToString()) }
[void]$sb.AppendLine("}")

$utf8 = New-Object System.Text.UTF8Encoding($false)
$out = Join-Path $PSScriptRoot "..\server\s_models.lua"
[IO.File]::WriteAllText($out, $sb.ToString(), $utf8)

# El mismo catalogo para el panel CEF (asi no viaja por executeBrowserJavascript)
$js = New-Object System.Text.StringBuilder
[void]$js.AppendLine("/* rp_mapeditor: catalogo GENERADO por tools/generar-catalogo.ps1 (no editar a mano) */")
[void]$js.Append("window.ME_GROUPS=[")
[void]$js.Append((($groups | ForEach-Object { "`"$_`"" }) -join ","))
[void]$js.AppendLine("];")
[void]$js.Append("window.ME_MODELS=[")
[void]$js.Append((($sorted | ForEach-Object { "[$($_[0]),`"$($_[1])`",$($_[2])]" }) -join ","))
[void]$js.AppendLine("];")
$outJs = Join-Path $PSScriptRoot "..\html\models.js"
[IO.File]::WriteAllText($outJs, $js.ToString(), $utf8)
Write-Host "OK: $($sorted.Count) modelos en $($groups.Count) grupos -> $out y $outJs"
