# rp_hud / tools/gen_sounds.ps1
# Genera los sonidos sintetizados propios del HUD (PCM 16 bits mono 22050 Hz):
#   heartbeat.wav  latido "lub-dub" para la vida baja
#   coins.wav      monedas al ganar dinero
# Se escriben en assets/propios/sonidos/ (biblioteca del repo) y en rp_hud/sounds/.
# Uso (desde la raiz del repo): powershell -File "resources/[roleplay]/rp_hud/tools/gen_sounds.ps1"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
$outs = @((Join-Path $root "assets\propios\sonidos"), (Join-Path $PSScriptRoot "..\sounds"))
$rate = 22050
$PI2 = 2 * [Math]::PI
function sine($f, $t) { [Math]::Sin($PI2 * $f * $t) }

function Wav($name, [double]$secs, [scriptblock]$f) {
  $n = [int]($rate * $secs); $data = New-Object byte[] ($n * 2)
  $rnd = New-Object System.Random 7
  for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $v = & $f $t $rnd
    $v = [Math]::Max(-1, [Math]::Min(1, $v))
    $s = [int16]($v * 30000)
    $data[$i * 2] = [byte]($s -band 0xFF); $data[$i * 2 + 1] = [byte](($s -shr 8) -band 0xFF)
  }
  $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
  $w.Write([Text.Encoding]::ASCII.GetBytes("RIFF")); $w.Write([int](36 + $data.Length)); $w.Write([Text.Encoding]::ASCII.GetBytes("WAVEfmt "))
  $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16)
  $w.Write([Text.Encoding]::ASCII.GetBytes("data")); $w.Write([int]$data.Length); $w.Write($data)
  foreach ($o in $outs) {
    New-Item -ItemType Directory -Force $o | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $o "$name.wav"), $ms.ToArray())
  }
}

# Latido: dos golpes graves (el segundo mas suave), con un poco de "cuerpo" de ruido filtrado
function thump($t, $amp) {
  if ($t -lt 0) { return 0 }
  $f = 58 - 18 * [Math]::Min(1, $t * 8)
  return $amp * ((sine $f $t) + 0.35 * (sine (2 * $f) $t)) * [Math]::Exp(-14 * $t) * [Math]::Min(1, $t * 300)
}
Wav "heartbeat" 0.7 { param($t) (thump $t 0.95) + (thump ($t - 0.26) 0.65) }

# Monedas: tres tintineos brillantes escalonados
function ting($t, $f, $amp) {
  if ($t -lt 0) { return 0 }
  return $amp * (0.6 * (sine $f $t) + 0.3 * (sine ($f * 2.76) $t) + 0.15 * (sine ($f * 5.4) $t)) * [Math]::Exp(-9 * $t)
}
Wav "coins" 0.7 { param($t, $r) (ting $t 2093 0.45) + (ting ($t - 0.07) 2637 0.4) + (ting ($t - 0.15) 3136 0.35) + ($r.NextDouble() * 2 - 1) * 0.08 * [Math]::Exp(-40 * $t) }
"ok"
