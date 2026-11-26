# scripts/leer-ipl-interior.ps1
# Lista los objetos del mapa original de GTA SA (IPL binarios dentro de un .img) en una caja de coordenadas:
# modelo, nombre, posicion, giro Z e interior. Sirve para colocar NPCs, sillas, estaciones o marcadores
# sobre el mobiliario real de un interior (ej.: la pizzeria esta en gta_int.img, gen_int5_stream2.ipl).
# Uso:
#   powershell -File scripts/leer-ipl-interior.ps1 -Img "<GTA SA>/models/gta_int.img" -IdeDir "<GTA SA>/data/maps" `
#       -MinX 355 -MaxX 392 -MinY -140 -MaxY -105 -MinZ 995 -MaxZ 1010
# Interiores: gta_int.img. Exterior: gta3.img. La ruta del juego esta en el registro de MTA (GTA:SA Path).
param([string]$Img, [string]$IdeDir, [double]$MinX = 355, [double]$MaxX = 392, [double]$MinY = -140, [double]$MaxY = -105, [double]$MinZ = 995, [double]$MaxZ = 1010)
$names = @{}
Get-ChildItem $IdeDir -Recurse -Filter *.ide | ForEach-Object {
  foreach ($l in [IO.File]::ReadAllLines($_.FullName)) { if ($l -match '^\s*(\d+)\s*,\s*([^,\s]+)') { $names[[int]$matches[1]] = $matches[2] } }
}
$fs = [IO.File]::OpenRead($Img); $br = New-Object IO.BinaryReader $fs
$null = $br.ReadBytes(4); $n = $br.ReadUInt32()
$entries = @()
for ($i=0; $i -lt $n; $i++) { $off=$br.ReadUInt32(); $s1=$br.ReadUInt16(); $s2=$br.ReadUInt16(); $nm=[Text.Encoding]::ASCII.GetString($br.ReadBytes(24)).Split([char]0)[0]
  if ($nm.ToLower().EndsWith('.ipl')) { $entries += ,@($off, [Math]::Max($s1,$s2), $nm) } }
$inv = [Globalization.CultureInfo]::InvariantCulture
foreach ($e in $entries) {
  $fs.Position = [int64]$e[0]*2048; $d = $br.ReadBytes([int]$e[1]*2048)
  if ([Text.Encoding]::ASCII.GetString($d,0,4) -ne 'bnry') { continue }
  $ni = [BitConverter]::ToUInt32($d,4); $io = [BitConverter]::ToUInt32($d,28)
  for ($k=0; $k -lt $ni; $k++) { $o = $io + $k*40
    $x=[BitConverter]::ToSingle($d,$o); $y=[BitConverter]::ToSingle($d,$o+4); $z=[BitConverter]::ToSingle($d,$o+8)
    if ($x -gt $MinX -and $x -lt $MaxX -and $y -gt $MinY -and $y -lt $MaxY -and $z -gt $MinZ -and $z -lt $MaxZ) {
      $qx=[BitConverter]::ToSingle($d,$o+12); $qy=[BitConverter]::ToSingle($d,$o+16); $qz=[BitConverter]::ToSingle($d,$o+20); $qw=[BitConverter]::ToSingle($d,$o+24)
      $id=[BitConverter]::ToInt32($d,$o+28); $int=[BitConverter]::ToInt32($d,$o+32)
      $rz = [Math]::Atan2(2*($qw*$qz+$qx*$qy), 1-2*($qy*$qy+$qz*$qz))*180/[Math]::PI
      "{0,-20} {1,6} {2,-22} {3,8:F3} {4,9:F3} {5,9:F3} rz={6,7:F1} int={7}" -f $e[2],$id,$names[$id],$x,$y,$z,$rz,$int
    } } }
$fs.Close()
