# rp_cartheft / tools/gen_sounds.ps1
# Genera los sonidos sintetizados propios de rp_cartheft (PCM 16 bits mono 22050 Hz):
#   alarma_auto.wav  alarma de auto en bucle (2 s): sirena que sube y baja y dos pitidos rapidos
#   alarma_chirp.wav doble pitido corto al apagar la alarma con la bocina
# Se escriben en assets/propios/sonidos/ (biblioteca del repo) y en rp_cartheft/sounds/.
# Uso (desde la raiz del repo): powershell -File "resources/[roleplay]/rp_cartheft/tools/gen_sounds.ps1"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
$outs = @((Join-Path $root "assets\propios\sonidos"), (Join-Path $PSScriptRoot "..\sounds"))
$rate = 22050
$PI2 = 2 * [Math]::PI

function Wav($name, [double]$secs, [scriptblock]$f) {
  $n = [int]($rate * $secs); $data = New-Object byte[] ($n * 2)
  $state = @{ ph = 0.0 }
  for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate
    $v = & $f $t $state
    $v = [Math]::Max(-1, [Math]::Min(1, $v))
    $s = [int16]($v * 26000)
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

# Onda cuadrada suavizada (suena a bocina electronica sin ser tan aspera)
function buzz($ph) { [Math]::Tanh(4 * [Math]::Sin($ph)) }

# Alarma: 1,2 s de sirena (900 -> 1600 -> 900 Hz, 3 vueltas) y 0,8 s de pitidos a 1300 Hz (4 x 0,1 s).
# La fase se acumula para que el barrido no chasquee; dura 2 s exactos para repetirse en bucle.
Wav "alarma_auto" 2.0 {
  param($t, $st)
  if ($t -lt 1.2) {
    $u = ($t % 0.4) / 0.4
    $f = 900 + 700 * (1 - [Math]::Abs(2 * $u - 1))
    $on = 1
  } else {
    $f = 1300
    $k = ($t - 1.2) / 0.1
    $on = if ([int][Math]::Floor($k) % 2 -eq 0) { 1 } else { 0 }
  }
  $st.ph += $PI2 * $f / $rate
  0.55 * $on * (buzz $st.ph)
}

# Pitido doble al desactivar (como el mando a distancia)
Wav "alarma_chirp" 0.45 {
  param($t, $st)
  $on = if (($t -lt 0.12) -or ($t -ge 0.22 -and $t -lt 0.34)) { 1 } else { 0 }
  $st.ph += $PI2 * 2000 / $rate
  0.5 * $on * (buzz $st.ph)
}
"ok"
