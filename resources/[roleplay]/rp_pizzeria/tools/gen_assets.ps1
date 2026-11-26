# rp_pizzeria / tools/gen_assets.ps1
# Genera los sonidos sintetizados (html/sounds/*.wav) del trabajo de pizzero.
# Hoy solo se usa sizzle.wav; los demas efectos y los globos de animo (images/) son de Kenney (CC0).
# Uso: powershell -File tools/gen_assets.ps1 -Out "<ruta a rp_pizzeria>"
param([string]$Out)
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force "$Out\images","$Out\html\sounds" | Out-Null

# ---------- Sonidos (PCM 16 bits mono 22050 Hz) ----------
$rate = 22050
function Wav($name, [double]$secs, [scriptblock]$f) {
  $n = [int]($rate * $secs); $data = New-Object byte[] ($n*2)
  $rnd = New-Object System.Random 7
  for ($i=0; $i -lt $n; $i++) {
    $t = $i / $rate
    $v = & $f $t $rnd
    $v = [Math]::Max(-1, [Math]::Min(1, $v))
    $s = [int16]($v * 30000)
    $data[$i*2] = [byte]($s -band 0xFF); $data[$i*2+1] = [byte](($s -shr 8) -band 0xFF)
  }
  $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
  $w.Write([Text.Encoding]::ASCII.GetBytes("RIFF")); $w.Write([int](36 + $data.Length)); $w.Write([Text.Encoding]::ASCII.GetBytes("WAVEfmt "))
  $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]($rate*2)); $w.Write([int16]2); $w.Write([int16]16)
  $w.Write([Text.Encoding]::ASCII.GetBytes("data")); $w.Write([int]$data.Length); $w.Write($data)
  [IO.File]::WriteAllBytes("$Out\html\sounds\$name.wav", $ms.ToArray())
}
$PI2 = 2*[Math]::PI
function sine($f,$t) { [Math]::Sin($PI2*$f*$t) }

Wav "bell" 1.2 { param($t) $e=[Math]::Exp(-3*$t); (0.5*(sine 1318 $t) + 0.3*(sine 2637 $t) + 0.2*(sine 1975 $t))*$e*0.8 }
Wav "ding" 0.9 { param($t) $e=[Math]::Exp(-4*$t); (0.6*(sine 1568 $t) + 0.3*(sine 3136 $t))*$e*0.8 }
Wav "alarm" 0.9 { param($t) $on = ([int]($t*8) % 2) -eq 0; if ($on) { 0.45*[Math]::Sign((sine 880 $t)) } else { 0 } }
Wav "print" 0.6 { param($t,$r) $env=0.5*(1+[Math]::Sin($PI2*28*$t)); ($r.NextDouble()*2-1)*0.25*$env*[Math]::Exp(-1.5*$t) }
Wav "oven" 0.5 { param($t,$r) ($r.NextDouble()*2-1)*0.25*[Math]::Exp(-9*$t) + 0.3*(sine (180-120*$t) $t)*[Math]::Exp(-6*$t) }
Wav "sizzle" 1.2 { param($t,$r) $x=($r.NextDouble()*2-1); $x*0.22*[Math]::Min(1,$t*8)*[Math]::Exp(-1.2*$t)*(0.6+0.4*[Math]::Sin($PI2*13*$t)) }
Wav "box" 0.35 { param($t,$r) ($r.NextDouble()*2-1)*0.4*[Math]::Exp(-25*$t) + 0.35*(sine 140 $t)*[Math]::Exp(-14*$t) }
Wav "cash" 1.0 { param($t,$r) $a = ($r.NextDouble()*2-1)*0.3*[Math]::Exp(-30*$t); $b = if ($t -gt 0.08) { (0.4*(sine 2093 ($t-0.08)) + 0.3*(sine 2637 ($t-0.08)))*[Math]::Exp(-4*($t-0.08)) } else { 0 }; $a+$b }
Wav "angry" 0.7 { param($t) $f = 160 - 50*$t; 0.35*[Math]::Sign((sine $f $t))*(1-$t/0.7) }
Wav "pop" 0.12 { param($t) 0.5*(sine (900-4000*$t) $t)*[Math]::Exp(-30*$t) }
Wav "chop" 0.25 { param($t,$r) ($r.NextDouble()*2-1)*0.5*[Math]::Exp(-30*$t) + 0.3*(sine 320 $t)*[Math]::Exp(-20*$t) }
"ok"
