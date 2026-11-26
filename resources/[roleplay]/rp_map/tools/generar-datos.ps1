# rp_map/tools/generar-datos.ps1
# Genera los datos del mapa desde TU instalacion de GTA SA (no se suben al repo los de Rockstar):
#   html/data/map.jpg        radar unido (material de Rockstar: .gitignore)
#   html/data/roads.js       red de calles para dibujar
#   html/data/buildings.js   cajas de edificios para el modo 3D
#   html/data/terrain.js     relieve aproximado y mascara de tierra
#   client/c_roads.lua       grafo dirigido para el GPS
#   shared/s_land.lua        mascara de tierra (para el % explorado)
# Uso: powershell -ExecutionPolicy Bypass -File tools/generar-datos.ps1 [-Gta "E:\GTA san andreas"]
param([string]$Gta = "")
$ErrorActionPreference = "Stop"
$res = Split-Path -Parent $PSScriptRoot
if (-not $Gta) {
    $Gta = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Multi Theft Auto: San Andreas All\Common" -ErrorAction SilentlyContinue)."GTA:SA Path"
}
if (-not $Gta -or -not (Test-Path -LiteralPath (Join-Path $Gta "models\gta3.img"))) { throw "No encuentro GTA SA. Pasa -Gta <carpeta del juego>." }
$radarCs = Join-Path (Split-Path -Parent $res) "rp_hud\tools\RadarExtract.cs"
Add-Type -Path @($radarCs, (Join-Path $PSScriptRoot "MapData.cs")) -ReferencedAssemblies System.Drawing
$data = Join-Path $res "html\data"
New-Item -ItemType Directory -Force -Path $data | Out-Null
$tmpPng = Join-Path $env:TEMP "rp_map_radar.png"
Write-Host ([RadarExtract]::Run((Join-Path $Gta "models\gta3.img"), $tmpPng, 128))
Write-Host ([MapData]::Radar($tmpPng, (Join-Path $data "map.jpg"), 3072))
$rep = ""
$land = [MapData]::LandMask($tmpPng, [ref]$rep); Write-Host $rep
Write-Host ([MapData]::WriteLandLua($land, (Join-Path $res "shared\s_land.lua")))
$nodes = $null
Write-Host ([MapData]::Roads((Join-Path $Gta "data\Paths"), (Join-Path $res "client\c_roads.lua"), (Join-Path $data "roads.js"), [ref]$nodes))
Write-Host ([MapData]::Buildings($Gta, (Join-Path $data "buildings.js"), (Join-Path $data "terrain.js"), $nodes, $land))
Remove-Item $tmpPng -ErrorAction SilentlyContinue
Write-Host "Listo."
