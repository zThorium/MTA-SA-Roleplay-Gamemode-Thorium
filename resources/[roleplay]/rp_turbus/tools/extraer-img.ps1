# rp_turbus/tools/extraer-img.ps1
# Saca archivos sueltos (DFF, TXD, COL) de un .img de GTA SA (formato VER2) a una carpeta local, para usarlos
# como molde en Blender (escala, altura de aceras, prelight y texturas de referencia).
# Lo extraído es material de Rockstar: va al scratchpad, NUNCA al repo.
# Uso:
#   powershell -File tools/extraer-img.ps1 -Img "<GTA SA>/models/gta3.img" -Out "<scratchpad>/ref" `
#       -Names unmainstat_LAS.dff,BTOLAND2_LAS.dff,union_las.txd
param([string]$Img, [string]$Out, [string[]]$Names)
$want = @{}; foreach ($n in $Names) { foreach ($p in ($n -split ',')) { if ($p.Trim()) { $want[$p.Trim().ToLower()] = $true } } }
New-Item -ItemType Directory -Force $Out | Out-Null
$fs = [IO.File]::OpenRead($Img); $br = New-Object IO.BinaryReader $fs
if ([Text.Encoding]::ASCII.GetString($br.ReadBytes(4)) -ne 'VER2') { throw "No es un IMG VER2: $Img" }
$n = $br.ReadUInt32(); $found = @()
for ($i = 0; $i -lt $n; $i++) {
  $off = $br.ReadUInt32(); $s1 = $br.ReadUInt16(); $s2 = $br.ReadUInt16()
  $nm = [Text.Encoding]::ASCII.GetString($br.ReadBytes(24)).Split([char]0)[0]
  if ($want.ContainsKey($nm.ToLower())) { $found += ,@($off, [Math]::Max($s1, $s2), $nm) }
}
foreach ($e in $found) {
  $fs.Position = [int64]$e[0] * 2048
  [IO.File]::WriteAllBytes((Join-Path $Out $e[2]), $br.ReadBytes([int]$e[1] * 2048))
  "extraido: $($e[2])"
}
$fs.Close()
foreach ($k in $want.Keys) { if (-not ($found | Where-Object { $_[2].ToLower() -eq $k })) { "NO ENCONTRADO: $k" } }
