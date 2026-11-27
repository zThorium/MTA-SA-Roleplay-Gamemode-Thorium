# rp_worldobjects/tools/generar-objetos.ps1
# Mapea los objetos del mapa original de GTA SA con los que se puede interactuar (bancas, sillas, sofas...)
# y escribe shared/s_data.lua con su posicion. Los modelos que se buscan salen de WO.MODELS en
# shared/s_config.lua (las claves [id]); para anadir uno: ponlo alli y vuelve a ejecutar este script.
# Lee:
#   - los IPL de texto que carga data/gta.dat (seccion inst)
#   - los IPL binarios dentro de models/gta3.img (exterior) y models/gta_int.img (interiores)
# Uso: powershell -ExecutionPolicy Bypass -File tools/generar-objetos.ps1 [-Gta "<carpeta del juego>"]
param([string]$Gta = "")
$ErrorActionPreference = "Stop"
$res = Split-Path -Parent $PSScriptRoot
if (-not $Gta) {
    $Gta = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Multi Theft Auto: San Andreas All\Common" -ErrorAction SilentlyContinue)."GTA:SA Path"
}
if (-not $Gta -or -not (Test-Path -LiteralPath (Join-Path $Gta "models\gta3.img"))) { throw "No encuentro GTA SA. Pasa -Gta <carpeta del juego>." }

# Modelos buscados (claves de WO.MODELS)
$cfg = [IO.File]::ReadAllText((Join-Path $res "shared\s_config.lua"))
$want = @{}
foreach ($m in [regex]::Matches($cfg, '\[(\d+)\]\s*=\s*\{\s*kind')) { $want[[int]$m.Groups[1].Value] = $true }
if ($want.Count -eq 0) { throw "No hay modelos en WO.MODELS (shared/s_config.lua)." }

$inv = [Globalization.CultureInfo]::InvariantCulture
$found = @{}   # [model] = lista de "x,y,z,rz,int"
$seen = @{}    # quitar duplicados exactos
$skipped = 0

function Add-Obj([int]$id, [double]$x, [double]$y, [double]$z, [double]$qx, [double]$qy, [double]$qz, [double]$qw, [int]$int) {
    if (-not $want.ContainsKey($id)) { return }
    # Inclinacion: un asiento torcido mas de ~15 grados no sirve para sentarse
    $up = 1 - 2 * ($qx * $qx + $qy * $qy)
    if ($up -lt 0.966) { $script:skipped++; return }
    # Los IPL guardan el cuaternion invertido: el giro en MTA es el opuesto
    $rz = -[Math]::Atan2(2 * ($qw * $qz + $qx * $qy), 1 - 2 * ($qy * $qy + $qz * $qz)) * 180 / [Math]::PI
    if ($rz -lt 0) { $rz += 360 }
    $line = [string]::Format($inv, "{0:0.00},{1:0.00},{2:0.00},{3:0},{4}", $x, $y, $z, $rz, $int)
    $key = "$id|$line"
    if ($script:seen.ContainsKey($key)) { return }
    $script:seen[$key] = $true
    if (-not $script:found.ContainsKey($id)) { $script:found[$id] = New-Object Collections.Generic.List[string] }
    $script:found[$id].Add($line)
}

# 1) IPL de texto de gta.dat
foreach ($l in [IO.File]::ReadAllLines((Join-Path $Gta "data\gta.dat"))) {
    if ($l -notmatch '^\s*IPL\s+(\S+)') { continue }
    $path = Join-Path $Gta ($matches[1] -replace '^DATA\\', 'data\')
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $inInst = $false
    foreach ($row in [IO.File]::ReadAllLines($path)) {
        $t = $row.Trim()
        if ($t -eq 'inst') { $inInst = $true; continue }
        if ($t -eq 'end') { $inInst = $false; continue }
        if (-not $inInst -or $t -eq '' -or $t.StartsWith('#')) { continue }
        $p = $t.Split(',') | ForEach-Object { $_.Trim() }
        if ($p.Count -lt 10) { continue }
        Add-Obj ([int]$p[0]) ([double]::Parse($p[3], $inv)) ([double]::Parse($p[4], $inv)) ([double]::Parse($p[5], $inv)) `
            ([double]::Parse($p[6], $inv)) ([double]::Parse($p[7], $inv)) ([double]::Parse($p[8], $inv)) ([double]::Parse($p[9], $inv)) ([int]$p[2])
    }
}

# 2) IPL binarios de los .img (mismo formato que scripts/leer-ipl-interior.ps1)
foreach ($imgName in @("gta3.img", "gta_int.img")) {
    $fs = [IO.File]::OpenRead((Join-Path $Gta "models\$imgName")); $br = New-Object IO.BinaryReader $fs
    $null = $br.ReadBytes(4); $n = $br.ReadUInt32()
    $entries = @()
    for ($i = 0; $i -lt $n; $i++) {
        $off = $br.ReadUInt32(); $s1 = $br.ReadUInt16(); $s2 = $br.ReadUInt16()
        $nm = [Text.Encoding]::ASCII.GetString($br.ReadBytes(24)).Split([char]0)[0]
        if ($nm.ToLower().EndsWith('.ipl')) { $entries += , @($off, [Math]::Max($s1, $s2)) }
    }
    foreach ($e in $entries) {
        $fs.Position = [int64]$e[0] * 2048; $d = $br.ReadBytes([int]$e[1] * 2048)
        if ([Text.Encoding]::ASCII.GetString($d, 0, 4) -ne 'bnry') { continue }
        $ni = [BitConverter]::ToUInt32($d, 4); $io = [BitConverter]::ToUInt32($d, 28)
        for ($k = 0; $k -lt $ni; $k++) {
            $o = $io + $k * 40
            $id = [BitConverter]::ToInt32($d, $o + 28)
            if (-not $want.ContainsKey($id)) { continue }
            Add-Obj $id ([BitConverter]::ToSingle($d, $o)) ([BitConverter]::ToSingle($d, $o + 4)) ([BitConverter]::ToSingle($d, $o + 8)) `
                ([BitConverter]::ToSingle($d, $o + 12)) ([BitConverter]::ToSingle($d, $o + 16)) ([BitConverter]::ToSingle($d, $o + 20)) ([BitConverter]::ToSingle($d, $o + 24)) `
                ([BitConverter]::ToInt32($d, $o + 32))
        }
    }
    $fs.Close()
}

# 3) Caja de colision de cada modelo (archivos .col de gta3.img y gta_int.img): para repartir las plazas
$names = @{}
Get-ChildItem (Join-Path $Gta "data") -Recurse -Filter *.ide | ForEach-Object {
    foreach ($l in [IO.File]::ReadAllLines($_.FullName)) {
        if ($l -match '^\s*(\d+)\s*,\s*([^,\s]+)') { $id = [int]$matches[1]; if ($want.ContainsKey($id)) { $names[$matches[2].ToLower()] = $id } }
    }
}
$boxes = @{}
foreach ($imgName in @("gta3.img", "gta_int.img")) {
    $fs = [IO.File]::OpenRead((Join-Path $Gta "models\$imgName")); $br = New-Object IO.BinaryReader $fs
    $null = $br.ReadBytes(4); $n = $br.ReadUInt32()
    $entries = @()
    for ($i = 0; $i -lt $n; $i++) {
        $off = $br.ReadUInt32(); $s1 = $br.ReadUInt16(); $s2 = $br.ReadUInt16()
        $nm = [Text.Encoding]::ASCII.GetString($br.ReadBytes(24)).Split([char]0)[0]
        if ($nm.ToLower().EndsWith('.col')) { $entries += , @($off, [Math]::Max($s1, $s2)) }
    }
    foreach ($e in $entries) {
        $fs.Position = [int64]$e[0] * 2048; $d = $br.ReadBytes([int]$e[1] * 2048)
        $p = 0
        while ($p + 32 -lt $d.Length) {
            $fcc = [Text.Encoding]::ASCII.GetString($d, $p, 4)
            if ($fcc -ne 'COLL' -and $fcc -ne 'COL2' -and $fcc -ne 'COL3' -and $fcc -ne 'COL4') { break }
            $size = [BitConverter]::ToUInt32($d, $p + 4)
            $nm = [Text.Encoding]::ASCII.GetString($d, $p + 8, 22).Split([char]0)[0].ToLower()
            $b = $p + 32
            if ($names.ContainsKey($nm) -and -not $boxes.ContainsKey($names[$nm])) {
                $mn = if ($fcc -eq 'COLL') { $b + 16 } else { $b }   # COL1: radio, centro, min, max; COL2+: min, max, centro, radio
                $v = 0..5 | ForEach-Object { [BitConverter]::ToSingle($d, $mn + 4 * $_) }
                $boxes[$names[$nm]] = [string]::Format($inv, "{0:0.000},{1:0.000},{2:0.000},{3:0.000},{4:0.000},{5:0.000}", $v[0], $v[1], $v[2], $v[3], $v[4], $v[5])
            }
            $p += 8 + $size
        }
    }
    $fs.Close()
}

# 4) Escribir shared/s_data.lua
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine("-- rp_worldobjects/shared/s_data.lua")
[void]$sb.AppendLine("-- GENERADO por tools/generar-objetos.ps1: no editar a mano.")
[void]$sb.AppendLine("-- Objetos del mapa original de GTA SA: [modelo] = { x, y, z, rz, interior, x, y, z, rz, interior, ... }")
[void]$sb.AppendLine("WO_DATA = {")
$total = 0
foreach ($id in ($found.Keys | Sort-Object)) {
    [void]$sb.AppendLine("  [$id] = {")
    foreach ($ln in $found[$id]) { [void]$sb.AppendLine("    $ln,"); $total++ }
    [void]$sb.AppendLine("  },")
}
[void]$sb.AppendLine("}")
[void]$sb.AppendLine("-- Caja de colision local de cada modelo: [modelo] = { minX, minY, minZ, maxX, maxY, maxZ }")
[void]$sb.AppendLine("WO_BOX = {")
foreach ($id in ($found.Keys | Sort-Object)) {
    if ($boxes.ContainsKey($id)) { [void]$sb.AppendLine("  [$id] = { $($boxes[$id]) },") } else { Write-Host "  (sin colision: $id)" }
}
[void]$sb.AppendLine("}")
[IO.File]::WriteAllText((Join-Path $res "shared\s_data.lua"), $sb.ToString(), (New-Object Text.UTF8Encoding $false))
foreach ($id in ($found.Keys | Sort-Object)) { Write-Host ("  {0,6}: {1}" -f $id, $found[$id].Count) }
Write-Host "Objetos: $total en $($found.Count) modelos (descartados por inclinados: $skipped)."
