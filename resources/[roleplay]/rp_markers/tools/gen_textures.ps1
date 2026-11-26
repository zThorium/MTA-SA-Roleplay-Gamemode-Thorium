# rp_markers / tools / gen_textures.ps1
# Genera las texturas del marcador (anillos, haz, brillo, insignia) y los iconos
# (blancos, trazo redondeado) en ../images. Todo es dibujo propio: sin material de terceros.
# Uso: powershell -ExecutionPolicy Bypass -File gen_textures.ps1
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$img = Join-Path $root "images"
$icons = Join-Path $img "icons"
New-Item -ItemType Directory -Force $icons | Out-Null

function Save-Bmp($bmp, $path) { $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose() }
function Clamp01($v) { if ($v -lt 0) { 0 } elseif ($v -gt 1) { 1 } else { $v } }

# Textura procedural: $fn recibe (u, v) en [-1,1] y devuelve alfa 0..1 (color blanco)
function New-Procedural($w, $h, $path, [scriptblock]$fn) {
    $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $bmp.PixelFormat)
    $bytes = New-Object byte[] ($w * $h * 4)
    for ($y = 0; $y -lt $h; $y++) {
        $v = ($y + 0.5) / $h * 2 - 1
        for ($x = 0; $x -lt $w; $x++) {
            $u = ($x + 0.5) / $w * 2 - 1
            $a = [int](255 * (Clamp01 (& $fn $u $v)))
            $i = ($y * $w + $x) * 4
            $bytes[$i] = 255; $bytes[$i + 1] = 255; $bytes[$i + 2] = 255; $bytes[$i + 3] = $a
        }
    }
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    $bmp.UnlockBits($data)
    Save-Bmp $bmp $path
}

# Anillo de suelo: aro fino brillante + halo + relleno que crece hacia el borde
New-Procedural 256 256 (Join-Path $img "ring.png") {
    param($u, $v)
    $r = [math]::Sqrt($u * $u + $v * $v)
    $ring = [math]::Exp(-[math]::Pow(($r - 0.9) / 0.022, 2))
    $halo = 0.45 * [math]::Exp(-[math]::Pow(($r - 0.9) / 0.09, 2))
    $fill = if ($r -lt 0.9) { 0.06 + 0.3 * [math]::Pow($r / 0.9, 3) } else { 0 }
    $ring + $halo + $fill
}

# Aro segmentado (gira): 3 arcos largos + marcas cortas
New-Procedural 256 256 (Join-Path $img "dash.png") {
    param($u, $v)
    $r = [math]::Sqrt($u * $u + $v * $v)
    $ang = ([math]::Atan2($v, $u) + [math]::PI) / (2 * [math]::PI)   # 0..1
    $band = [math]::Exp(-[math]::Pow(($r - 0.78) / 0.03, 2))
    $seg = ($ang * 3) % 1
    $on = if ($seg -lt 0.72) { 1 } else { 0 }
    $edge = [math]::Min($seg / 0.04, (0.72 - $seg) / 0.04)
    $arc = $band * $on * (Clamp01 $edge)
    $tick = 0
    $t = ($ang * 24) % 1
    if ($t -lt 0.12 -and [math]::Abs($r - 0.66) -lt 0.035) { $tick = 0.7 }
    $arc + $tick
}

# Haz vertical: centro brillante, se desvanece hacia arriba
New-Procedural 64 256 (Join-Path $img "beam.png") {
    param($u, $v)
    $hor = [math]::Exp(-[math]::Pow($u / 0.42, 2))
    $vert = [math]::Pow((Clamp01 (($v + 1) / 2)), 1.8)  # fila 0 = arriba (0) .. abajo (1)
    $hor * $vert
}

# Brillo suave (partículas y halo del icono)
New-Procedural 64 64 (Join-Path $img "glow.png") {
    param($u, $v)
    $r = [math]::Sqrt($u * $u + $v * $v)
    [math]::Exp(-[math]::Pow($r / 0.45, 2))
}

# Aro de la insignia (se tiñe con el color del marcador)
New-Procedural 128 128 (Join-Path $img "badge_ring.png") {
    param($u, $v)
    $r = [math]::Sqrt($u * $u + $v * $v)
    [math]::Exp(-[math]::Pow(($r - 0.86) / 0.04, 2)) + 0.35 * [math]::Exp(-[math]::Pow(($r - 0.86) / 0.12, 2))
}

# Fondo de la insignia: disco oscuro con degradado (no se tiñe)
$bmp = New-Object System.Drawing.Bitmap 128, 128
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = "AntiAlias"
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddEllipse(10, 10, 108, 108)
$pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush $path
$pgb.CenterColor = [System.Drawing.Color]::FromArgb(225, 34, 38, 52)
$pgb.SurroundColors = @([System.Drawing.Color]::FromArgb(235, 12, 14, 20))
$g.FillPath($pgb, $path)
$g.Dispose(); Save-Bmp $bmp (Join-Path $img "badge_bg.png")

# ---------------------------------------------------------------- iconos
$W = [System.Drawing.Color]::White
function New-Icon($name, [scriptblock]$draw) {
    $bmp = New-Object System.Drawing.Bitmap 256, 256
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"; $g.TextRenderingHint = "AntiAliasGridFit"
    $pen = New-Object System.Drawing.Pen $W, 18
    $pen.StartCap = "Round"; $pen.EndCap = "Round"; $pen.LineJoin = "Round"
    $br = New-Object System.Drawing.SolidBrush $W
    & $draw $g $pen $br
    $g.Dispose(); Save-Bmp $bmp (Join-Path $icons "$name.png")
}
function P($x, $y) { New-Object System.Drawing.PointF $x, $y }
function Pts([float[]]$c) { $l = @(); for ($i = 0; $i -lt $c.Length; $i += 2) { $l += (P $c[$i] $c[$i + 1]) }; [System.Drawing.PointF[]]$l }
function Dot($g, $br, $x, $y, $r) { $g.FillEllipse($br, $x - $r, $y - $r, 2 * $r, 2 * $r) }
function Circ($g, $pen, $x, $y, $r) { $g.DrawEllipse($pen, $x - $r, $y - $r, 2 * $r, 2 * $r) }

New-Icon "info"     { param($g, $p, $b) Dot $g $b 128 64 16; $g.DrawLine($p, 128, 112, 128, 200) }
New-Icon "enter"    { param($g, $p, $b) $g.DrawLines($p, (Pts 116,40, 196,40, 196,216, 116,216)); $g.DrawLine($p, 44, 128, 150, 128); $g.DrawLines($p, (Pts 112,90, 150,128, 112,166)) }
New-Icon "exit"     { param($g, $p, $b) $g.DrawLines($p, (Pts 140,40, 60,40, 60,216, 140,216)); $g.DrawLine($p, 104, 128, 210, 128); $g.DrawLines($p, (Pts 172,90, 210,128, 172,166)) }
New-Icon "door"     { param($g, $p, $b) $g.DrawRectangle($p, 76, 36, 104, 184); Dot $g $b 152 132 11 }
New-Icon "shop"     { param($g, $p, $b) $g.DrawPolygon($p, (Pts 56,94, 200,94, 188,216, 68,216)); $g.DrawArc($p, 92, 40, 72, 100, 180, 180) }
New-Icon "money"    { param($g, $p, $b)
    $f = New-Object System.Drawing.Font "Arial", 210, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = "Center"; $sf.LineAlignment = "Center"
    $g.DrawString('$', $f, $b, (New-Object System.Drawing.RectangleF 0, 10, 256, 256), $sf) }
New-Icon "car"      { param($g, $p, $b) $g.DrawPolygon($p, (Pts 36,168, 36,130, 70,120, 98,78, 162,78, 190,120, 220,130, 220,168)); Dot $g $b 82 172 24; Dot $g $b 174 172 24 }
New-Icon "gun"      { param($g, $p, $b) $g.FillPolygon($b, (Pts 30,78, 220,78, 220,126, 30,126)); $g.FillPolygon($b, (Pts 148,120, 200,120, 214,212, 160,212)); $g.DrawArc($p, 100, 100, 60, 70, 0, 180) }
New-Icon "job"      { param($g, $p, $b) $g.DrawRectangle($p, 36, 88, 184, 124); $g.DrawLines($p, (Pts 96,88, 96,56, 160,56, 160,88)); $g.DrawLine($p, 36, 144, 220, 144) }
New-Icon "wrench"   { param($g, $p, $b) $p.Width = 30; $g.DrawLine($p, 60, 196, 146, 110); $p.Width = 22; $g.DrawArc($p, 134, 38, 84, 84, -10, 290) }
New-Icon "fuel"     { param($g, $p, $b) $g.DrawRectangle($p, 56, 44, 100, 172); $g.FillRectangle($b, 78, 70, 56, 42); $g.DrawLine($p, 36, 216, 176, 216); $g.DrawLines($p, (Pts 156,96, 196,120, 196,186, 214,196)) }
New-Icon "medical"  { param($g, $p, $b) $g.FillRectangle($b, 102, 36, 52, 184); $g.FillRectangle($b, 36, 102, 184, 52) }
New-Icon "bike"     { param($g, $p, $b) $p.Width = 14; Circ $g $p 66 168 40; Circ $g $p 190 168 40; $g.DrawLines($p, (Pts 66,168, 108,104, 172,104, 190,168)); $g.DrawLines($p, (Pts 108,104, 134,168, 66,168)); $g.DrawLine($p, 94, 82, 126, 82); $g.DrawLines($p, (Pts 172,104, 160,74, 186,74)) }
New-Icon "house"    { param($g, $p, $b) $g.DrawLines($p, (Pts 32,126, 128,44, 224,126)); $g.DrawLines($p, (Pts 64,106, 64,214, 192,214, 192,106)); $g.FillRectangle($b, 108, 150, 40, 64) }
New-Icon "key"      { param($g, $p, $b) Circ $g $p 82 128 40; $g.DrawLine($p, 122, 128, 222, 128); $g.DrawLine($p, 196, 128, 196, 166); $g.DrawLine($p, 166, 128, 166, 156) }
New-Icon "star"     { param($g, $p, $b)
    $pts = @(); for ($i = 0; $i -lt 10; $i++) { $a = -[math]::PI / 2 + $i * [math]::PI / 5; $r = if ($i % 2) { 44 } else { 100 }; $pts += (P (128 + $r * [math]::Cos($a)) (136 + $r * [math]::Sin($a))) }
    $g.FillPolygon($b, [System.Drawing.PointF[]]$pts) }
New-Icon "food"     { param($g, $p, $b) $p.Width = 14; $g.DrawLine($p, 90, 40, 90, 216); $g.DrawLines($p, (Pts 62,40, 62,96, 90,116, 118,96, 118,40)); $g.DrawLine($p, 176, 130, 176, 216); $g.FillPolygon($b, (Pts 168,36, 202,70, 202,136, 168,136)) }
New-Icon "drink"    { param($g, $p, $b) $g.DrawPolygon($p, (Pts 66,74, 190,74, 174,216, 82,216)); $g.DrawLine($p, 140, 74, 168, 26); $g.DrawLine($p, 76, 120, 180, 120) }
New-Icon "target"   { param($g, $p, $b) $p.Width = 14; Circ $g $p 128 128 78; Circ $g $p 128 128 38; Dot $g $b 128 128 11; $g.DrawLine($p, 128, 18, 128, 64); $g.DrawLine($p, 128, 192, 128, 238); $g.DrawLine($p, 18, 128, 64, 128); $g.DrawLine($p, 192, 128, 238, 128) }
New-Icon "flag"     { param($g, $p, $b) $g.DrawLine($p, 62, 30, 62, 228); $g.FillPolygon($b, (Pts 62,38, 206,38, 174,88, 206,138, 62,138)) }
New-Icon "person"   { param($g, $p, $b) Dot $g $b 128 82 38; $g.FillPie($b, 56, 134, 144, 176, 180, 180) }
New-Icon "phone"    { param($g, $p, $b) $g.DrawRectangle($p, 78, 30, 100, 196); Dot $g $b 128 196 10 }
New-Icon "arrow"    { param($g, $p, $b) $p.Width = 24; $g.DrawLines($p, (Pts 64,72, 128,136, 192,72)); $g.DrawLines($p, (Pts 64,140, 128,204, 192,140)) }
New-Icon "bank"     { param($g, $p, $b) $g.FillPolygon($b, (Pts 32,96, 128,36, 224,96)); $g.FillRectangle($b, 32, 196, 192, 24); foreach ($x in 66, 106, 150, 190) { $g.DrawLine($p, $x, 116, $x, 180) } }
New-Icon "police"   { param($g, $p, $b) $g.DrawPolygon($p, (Pts 128,30, 210,62, 202,148, 128,226, 54,148, 46,62))
    $pts = @(); for ($i = 0; $i -lt 10; $i++) { $a = -[math]::PI / 2 + $i * [math]::PI / 5; $r = if ($i % 2) { 18 } else { 42 }; $pts += (P (128 + $r * [math]::Cos($a)) (122 + $r * [math]::Sin($a))) }
    $g.FillPolygon($b, [System.Drawing.PointF[]]$pts) }
New-Icon "gym"      { param($g, $p, $b) $g.DrawLine($p, 70, 128, 186, 128); $g.FillRectangle($b, 50, 84, 30, 88); $g.FillRectangle($b, 176, 84, 30, 88); $g.FillRectangle($b, 26, 104, 26, 48); $g.FillRectangle($b, 204, 104, 26, 48) }
New-Icon "clothes"  { param($g, $p, $b) $g.FillPolygon($b, (Pts 92,44, 128,70, 164,44, 204,62, 230,112, 196,130, 186,112, 186,218, 70,218, 70,112, 60,130, 26,112, 52,62)) }
New-Icon "license"  { param($g, $p, $b) $g.DrawRectangle($p, 30, 62, 196, 132); Dot $g $b 84 114 20; $g.FillPie($b, 56, 138, 56, 50, 180, 180); $g.DrawLine($p, 136, 106, 196, 106); $g.DrawLine($p, 136, 148, 180, 148) }

Write-Host "Texturas generadas en $img"
