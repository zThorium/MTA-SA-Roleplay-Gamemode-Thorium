<#
    rp_metaldetector / tools/gen_assets.ps1

    Genera los sonidos sintetizados y las texturas propias del detector (CC0, hechos para Thorium).
    Escribe en assets/propios/{sonidos,texturas}/detector/ y copia al recurso (sounds/ e images/fx/).
    Uso (desde la raíz de mods/deathmatch):  powershell -ExecutionPolicy Bypass -File "resources/[roleplay]/rp_metaldetector/tools/gen_assets.ps1"
#>
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$res = Join-Path $root "resources\[roleplay]\rp_metaldetector"
$sndOut = Join-Path $root "assets\propios\sonidos\detector"
$texOut = Join-Path $root "assets\propios\texturas\detector"
New-Item -ItemType Directory -Force $sndOut, $texOut, (Join-Path $res "sounds"), (Join-Path $res "images\fx") | Out-Null

$RATE = 22050
$rnd = New-Object System.Random 7

function Write-Wav([string]$name, [double[]]$s) {
    $peak = 0.0
    foreach ($v in $s) { if ([math]::Abs($v) -gt $peak) { $peak = [math]::Abs($v) } }
    $gain = if ($peak -gt 0) { 0.89 / $peak } else { 1 }
    $ms = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter $ms
    $n = $s.Length
    $w.Write([Text.Encoding]::ASCII.GetBytes("RIFF")); $w.Write([int](36 + $n * 2))
    $w.Write([Text.Encoding]::ASCII.GetBytes("WAVEfmt ")); $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1)
    $w.Write([int]$RATE); $w.Write([int]($RATE * 2)); $w.Write([int16]2); $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes("data")); $w.Write([int]($n * 2))
    foreach ($v in $s) { $w.Write([int16][math]::Round([math]::Max(-1, [math]::Min(1, $v * $gain)) * 32767)) }
    $w.Flush()
    $file = Join-Path $sndOut "$name.wav"
    [IO.File]::WriteAllBytes($file, $ms.ToArray())
    Copy-Item $file (Join-Path $res "sounds\$name.wav") -Force
    "  sonido $name.wav ($([math]::Round($n / $RATE, 2)) s)"
}

function New-Buf([double]$sec) { return New-Object double[] ([int]($sec * $RATE)) }

# Campana: parciales inarmónicos con caída exponencial
function Add-Bell([double[]]$buf, [double]$start, [double]$freq, [double]$amp, [double]$decay) {
    $partials = @(@(1.0, 1.0), @(2.0, 0.45), @(2.76, 0.3), @(5.4, 0.12))
    $i0 = [int]($start * $RATE)
    for ($i = $i0; $i -lt $buf.Length; $i++) {
        $t = ($i - $i0) / $RATE
        $env = [math]::Exp(-$t / $decay) * [math]::Min(1, $t * 400)
        if ($env -lt 0.0005) { break }
        $v = 0.0
        foreach ($p in $partials) { $v += $p[1] * [math]::Sin(2 * [math]::PI * $freq * $p[0] * $t * (1 + 0.0004 * $p[0])) }
        $buf[$i] += $amp * $env * $v
    }
}

# Envolvente suave (seno elevado): sube en $att s, baja en $rel s; sin bordes que hagan «clic»
function Get-Env([double]$t, [double]$len, [double]$att, [double]$rel) {
    if ($t -lt $att) { return 0.5 - 0.5 * [math]::Cos([math]::PI * $t / $att) }
    if ($t -gt $len - $rel) { $k = ($len - $t) / $rel; return 0.5 - 0.5 * [math]::Cos([math]::PI * [math]::Max(0, $k)) }
    return 1.0
}

# 1) Respuesta a un objetivo no ferroso, como un detector real: «bup» redondo de ~560 Hz que sube un poco
#    de tono al pasar la bobina por encima (el juego lo afina más agudo o más grave según la lectura).
$len = 0.20
$b = New-Buf $len
$ph = 0.0
for ($i = 0; $i -lt $b.Length; $i++) { $t = $i / $RATE
    $f = 520 + 80 * ($t / $len) + 4 * [math]::Sin(2 * [math]::PI * 18 * $t)
    $ph += 2 * [math]::PI * $f / $RATE
    $b[$i] = (Get-Env $t $len 0.025 0.09) * ([math]::Sin($ph) + 0.12 * [math]::Sin(2 * $ph)) }
Write-Wav "beep_hi" $b

# 2) Hierro: gruñido grave y suave (~185 Hz que cae un poco), sin saturar
$len = 0.22
$b = New-Buf $len
$ph = 0.0
for ($i = 0; $i -lt $b.Length; $i++) { $t = $i / $RATE
    $f = 190 - 25 * ($t / $len)
    $ph += 2 * [math]::PI * $f / $RATE
    $b[$i] = (Get-Env $t $len 0.03 0.1) * ([math]::Sin($ph) + 0.3 * [math]::Sin(2 * $ph) + 0.08 * [math]::Sin(3 * $ph)) }
Write-Wav "beep_lo" $b

# 3) Tono continuo en bucle (pinpoint): 560 Hz con un 2º armónico muy leve; 1 s exacto = bucle sin corte
$b = New-Buf 1.0
for ($i = 0; $i -lt $b.Length; $i++) { $t = $i / $RATE
    $b[$i] = [math]::Sin(2 * [math]::PI * 560 * $t) + 0.1 * [math]::Sin(2 * [math]::PI * 1120 * $t) }
Write-Wav "tone_loop" $b

# 4) Zumbido de fondo del detector encendido (umbral): muy suave y limpio, 180 Hz con un leve vaivén
$b = New-Buf 1.0
for ($i = 0; $i -lt $b.Length; $i++) { $t = $i / $RATE
    $b[$i] = (0.85 + 0.15 * [math]::Sin(2 * [math]::PI * 2 * $t)) * ([math]::Sin(2 * [math]::PI * 180 * $t) + 0.15 * [math]::Sin(2 * [math]::PI * 360 * $t)) }
Write-Wav "hum_loop" $b

# 5) Encendido: barrido ascendente corto
$b = New-Buf 0.35
$ph = 0.0
for ($i = 0; $i -lt $b.Length; $i++) { $t = $i / $RATE; $f = 300 + 1500 * ($t / 0.35); $ph += 2 * [math]::PI * $f / $RATE
    $b[$i] = [math]::Min(1, $t * 80) * [math]::Min(1, (0.35 - $t) * 20) * [math]::Sin($ph) }
Write-Wav "power_on" $b

# 6) Hallazgos por rareza
$b = New-Buf 0.9;  Add-Bell $b 0 1318.5 1 0.25; Add-Bell $b 0.09 1975.5 0.8 0.3
Write-Wav "reveal_common" $b

$b = New-Buf 1.5
$notes = 1046.5, 1318.5, 1568.0, 2093.0
for ($k = 0; $k -lt 4; $k++) { Add-Bell $b ($k * 0.08) $notes[$k] 0.8 0.45 }
Write-Wav "reveal_rare" $b

$b = New-Buf 3.2
$notes = 523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0, 2093.0
for ($k = 0; $k -lt $notes.Length; $k++) { Add-Bell $b ($k * 0.07) $notes[$k] 0.7 0.6 }
foreach ($f in 1046.5, 1318.5, 1568.0) { Add-Bell $b 0.55 $f 0.9 1.2 }
for ($i = 0; $i -lt $b.Length; $i++) { $t = $i / $RATE; if ($t -gt 0.55) { $b[$i] *= 0.85 + 0.15 * [math]::Sin(2 * [math]::PI * 6 * $t) } }
Write-Wav "reveal_legendary" $b

# 7) Destellos: campanitas agudas al azar
$b = New-Buf 1.4
for ($k = 0; $k -lt 14; $k++) { Add-Bell $b ($rnd.NextDouble() * 1.0) (2500 + $rnd.NextDouble() * 2500) (0.2 + $rnd.NextDouble() * 0.3) 0.12 }
Write-Wav "sparkle" $b

# 8) ¡Nuevo en tu colección!: dos notas
$b = New-Buf 0.8; Add-Bell $b 0 1567.98 0.9 0.2; Add-Bell $b 0.12 2093.0 1 0.35
Write-Wav "new_entry" $b

# ---------------------------------------------------------------- texturas
Add-Type -AssemblyName System.Drawing
function Save-Png([System.Drawing.Bitmap]$bmp, [string]$name) {
    $file = Join-Path $texOut "$name.png"
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Copy-Item $file (Join-Path $res "images\fx\$name.png") -Force
    "  textura $name.png"
}
function New-Radial([int]$size, [scriptblock]$pixel) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $c = ($size - 1) / 2
    for ($y = 0; $y -lt $size; $y++) { for ($x = 0; $x -lt $size; $x++) {
        $d = [math]::Sqrt(($x - $c) * ($x - $c) + ($y - $c) * ($y - $c)) / $c
        $a = [math]::Atan2($y - $c, $x - $c)
        $col = & $pixel $d $a
        $bmp.SetPixel($x, $y, $col)
    } }
    return $bmp
}
function Clamp255([double]$v) { return [int][math]::Max(0, [math]::Min(255, $v)) }

# Brillo radial blanco (se tiñe con el color de la rareza)
Save-Png (New-Radial 128 { param($d, $a) $v = [math]::Max(0, 1 - $d); [System.Drawing.Color]::FromArgb((Clamp255 (255 * $v * $v)), 255, 255, 255) }) "glow"

# Aro suave (onda expansiva en el suelo)
Save-Png (New-Radial 128 { param($d, $a) $v = [math]::Exp(-[math]::Pow(($d - 0.82) / 0.07, 2)); [System.Drawing.Color]::FromArgb((Clamp255 (255 * $v)), 255, 255, 255) }) "ring"

# Destello de 4 puntas
Save-Png (New-Radial 128 { param($d, $a)
    $star = [math]::Pow([math]::Abs([math]::Cos(2 * $a)), 18) * [math]::Max(0, 1 - $d)
    $core = [math]::Max(0, 1 - $d * 3.2)
    $v = [math]::Min(1, $star * 1.4 + $core)
    [System.Drawing.Color]::FromArgb((Clamp255 (255 * $v)), 255, 255, 255) }) "sparkle"

# Hoyo en la arena: centro oscuro, borde de arena removida más clara, irregular
Save-Png (New-Radial 128 { param($d, $a)
    $edge = 0.78 + 0.06 * [math]::Sin(5 * $a) + 0.04 * [math]::Sin(11 * $a + 1.3)
    if ($d -gt 1) { return [System.Drawing.Color]::FromArgb(0, 0, 0, 0) }
    if ($d -lt $edge) {
        $k = $d / $edge
        $alpha = 235
        return [System.Drawing.Color]::FromArgb($alpha, (Clamp255 (60 + 70 * $k)), (Clamp255 (45 + 55 * $k)), (Clamp255 (25 + 35 * $k)))
    }
    $k = ($d - $edge) / (1 - $edge)
    [System.Drawing.Color]::FromArgb((Clamp255 (200 * (1 - $k))), 196, 170, 120) }) "hole"

# Viñeta (bordes blancos, centro transparente) para el destello en pantalla
Save-Png (New-Radial 128 { param($d, $a) $v = [math]::Min(1, [math]::Max(0, ($d - 0.45) / 0.55)); [System.Drawing.Color]::FromArgb((Clamp255 (255 * $v * $v)), 255, 255, 255) }) "vignette"

"Listo."
