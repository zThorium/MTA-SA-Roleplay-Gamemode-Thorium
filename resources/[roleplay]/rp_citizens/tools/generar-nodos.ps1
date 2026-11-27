# rp_citizens/tools/generar-nodos.ps1
# Genera la red de caminos de los ciudadanos (todo San Andreas) desde TU instalacion de GTA SA:
#   c_nodes_veh.lua   nodos viales: VEH_NODES/LINKS/LANES/OFFSET/LIGHT
#   c_nodes_ped.lua   nodos peatonales: PED_NODES/LINKS
#   c_nodes_boat.lua  rutas de barcos: BOAT_NODES/LINKS (c_boats.lua)
# Los nodos que ya estaban en esos archivos conservan su indice:
# el editor /nodos guarda en SQL por indice. Si cambian los totales, actualiza BASE en s_paths.lua.
# Uso: powershell -ExecutionPolicy Bypass -File tools/generar-nodos.ps1 [-Gta "E:\GTA san andreas"]
param([string]$Gta = "")
$ErrorActionPreference = "Stop"
$res = Split-Path -Parent $PSScriptRoot
if (-not $Gta) {
    $Gta = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Multi Theft Auto: San Andreas All\Common" -ErrorAction SilentlyContinue)."GTA:SA Path"
}
$paths = Join-Path $Gta "data\Paths"
if (-not $Gta -or -not (Test-Path -LiteralPath (Join-Path $paths "NODES0.DAT"))) { throw "No encuentro GTA SA. Pasa -Gta <carpeta del juego>." }
$mapData = Join-Path (Split-Path -Parent $res) "rp_map\tools\MapData.cs"
Add-Type -Path $mapData -ReferencedAssemblies System.Drawing
$prev = @("c_nodes_veh.lua", "c_nodes_ped.lua", "c_nodes_boat.lua") | ForEach-Object { Join-Path $res $_ }
Write-Host ([MapData]::CitizenNodes($paths, [string[]]$prev, $res))
Write-Host "Listo."
