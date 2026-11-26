# scripts/escalar-png.ps1
# Escala un PNG pequeño (p. ej. los emotes de Kenney, 32x38) con suavizado de alta calidad.
# Uso: powershell -File scripts/escalar-png.ps1 -Src origen.png -Dst destino.png [-Scale 4]
# Ver docs/EXPERIENCIA_JUEGO.md > Assets.
param([string]$Src, [string]$Dst, [int]$Scale = 4)
Add-Type -AssemblyName System.Drawing
$i = [System.Drawing.Image]::FromFile($Src)
$b = New-Object System.Drawing.Bitmap ($i.Width * $Scale), ($i.Height * $Scale)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.SmoothingMode = 'AntiAlias'
$g.DrawImage($i, 0, 0, $b.Width, $b.Height)
$b.Save($Dst, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $b.Dispose(); $i.Dispose()
