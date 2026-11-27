# rp_wanted / tools/gen_sounds.ps1
# Genera los sonidos sintetizados propios de rp_wanted (PCM 16 bits mono 22050 Hz):
#   disparo_rifle.wav  disparo de rifle (M4 del tirador del helicoptero): chasquido, golpe grave y cola
# Se escriben en assets/propios/sonidos/ (biblioteca del repo) y en rp_wanted/sounds/.
# Uso (desde la raiz del repo): powershell -File "resources/[roleplay]/rp_wanted/tools/gen_sounds.ps1"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
$outs = @((Join-Path $root "assets\propios\sonidos"), (Join-Path $PSScriptRoot "..\sounds"))
$rate = 22050
$PI2 = 2 * [Math]::PI
function sine($f, $t) { [Math]::Sin($PI2 * $f * $t) }

function Wav($name, [double]$secs, [scriptblock]$f) {
  $n = [int]($rate * $secs); $data = New-Object byte[] ($n * 2)
  $rnd = New-Object System.Random 11
  $state = @{ lp = 0.0 }
  for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $v = & $f $t $rnd $state
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

# Disparo de rifle: chasquido de ruido blanco muy corto, cuerpo de ruido filtrado (paso bajo),
# golpe grave que cae de 120 a 50 Hz y una cola de eco suave
Wav "disparo_rifle" 0.5 {
  param($t, $r, $st)
  $noise = $r.NextDouble() * 2 - 1
  $st.lp = $st.lp + 0.18 * ($noise - $st.lp)
  $attack = [Math]::Min(1, $t * 4000)
  $crack = $noise * [Math]::Exp(-90 * $t)
  $body = $st.lp * 2.2 * [Math]::Exp(-22 * $t)
  $f = 50 + 70 * [Math]::Exp(-30 * $t)
  $thump = 0.8 * (sine $f $t) * [Math]::Exp(-18 * $t)
  $tail = $st.lp * 0.5 * [Math]::Exp(-7 * $t)
  $attack * (0.55 * $crack + 0.6 * $body + $thump + $tail)
}
"ok"
