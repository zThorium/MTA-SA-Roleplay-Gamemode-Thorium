# rp_mapeditor / tools / generar-categorias.ps1
# Genera html/categories.js con el árbol de categorías del navegador de objetos del editor de MTA
# (objects.xml de multitheftauto/mtasa-resources, licencia MIT), traducido al español y cruzado con
# nuestro catálogo (server/s_models.lua): los modelos que no están en él se descartan, porque el
# servidor no los aceptaría.
#
#   powershell -File "resources/[roleplay]/rp_mapeditor/tools/generar-categorias.ps1" [-Xml <objects.xml>]
#
# Sin -Xml se descarga de GitHub. Ejecutar después de generar-catalogo.ps1.
param([string]$Xml)

$ErrorActionPreference = "Stop"
$URL = "https://raw.githubusercontent.com/multitheftauto/mtasa-resources/master/%5Beditor%5D/editor_gui/client/browser/objects.xml"

if (-not $Xml) {
    $Xml = Join-Path ([IO.Path]::GetTempPath()) "rp_mapeditor_objects.xml"
    Invoke-WebRequest -UseBasicParsing -Uri $URL -OutFile $Xml
}
[xml]$doc = [IO.File]::ReadAllText($Xml)

# Modelos válidos (los del catálogo generado desde los IDE del juego)
$valid = @{}
$lua = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\server\s_models.lua"))
foreach ($m in [regex]::Matches($lua, '\{(\d+),"')) { $valid[[int]$m.Groups[1].Value] = $true }

$ES = @{
    "Alpha Channels and Non Collidable" = "Transparentes y sin colisión"
    "Nighttime Objects" = "Objetos nocturnos (luces)"
    "Beach and Sea" = "Playa y mar"
    "Ships, Docks, and Piers" = "Barcos, muelles y embarcaderos"
    "General" = "General"
    "buildings" = "Edificios"
    "Factories and Warehouses" = "Fábricas y almacenes"
    "Stores and Shops" = "Tiendas y comercios"
    "Graveyard" = "Cementerio"
    "Houses and Apartments" = "Casas y departamentos"
    "Offices and Skyscrapers" = "Oficinas y rascacielos"
    "Other Buildings" = "Otros edificios"
    "Restaurants and Hotels" = "Restaurantes y hoteles"
    "Sports and Stadium Objects" = "Deportes y estadios"
    "Bars, Clubs, and Casinos" = "Bares, discotecas y casinos"
    "Car parts" = "Piezas de auto"
    "Weapon Models" = "Armas"
    "industrial" = "Industrial"
    "Construction" = "Construcción"
    "Cranes" = "Grúas"
    "Crates, Drums, and Racks" = "Cajas, barriles y estanterías"
    "interior objects" = "Interiores"
    "Bar Items" = "Objetos de bar"
    "Shop Items" = "Objetos de tienda"
    "Household Items" = "Objetos de casa"
    "Furniture" = "Muebles"
    "Doors and Windows" = "Puertas y ventanas"
    "Clothes" = "Ropa"
    "Tables and Chairs" = "Mesas y sillas"
    "Casino Items" = "Objetos de casino"
    "More Interiors" = "Más interiores"
    "land masses" = "Terreno"
    "Concrete and Rock" = "Hormigón y roca"
    "Grass and Dirt" = "Pasto y tierra"
    "miscellaneous" = "Varios"
    "Street and Road Items" = "Calle y carretera"
    "Food and Drinks" = "Comida y bebida"
    "Special" = "Especiales"
    "Military" = "Militar"
    "Pickups and Icons" = "Pickups e iconos"
    "Ladders, Stairs, and Scaffolding" = "Escaleras y andamios"
    "Trash" = "Basura"
    "nature" = "Naturaleza"
    "Rocks" = "Rocas"
    "Trees" = "Árboles"
    "Plants" = "Plantas"
    "structures" = "Estructuras"
    "Airport and Aircraft Objects" = "Aeropuerto y aviones"
    "Car Parks" = "Estacionamientos"
    "Farm Objects" = "Granja"
    "Fences, Walls, Gates, and Barriers" = "Rejas, muros, portones y barreras"
    "Garages and Petrol Stations" = "Talleres y gasolineras"
    "Ramps" = "Rampas"
    "Signs, Billboards, and Statues" = "Letreros, carteles y estatuas"
    "transportation" = "Transporte"
    "Railroads" = "Vías de tren"
    "Roads, Bridges, and Tunnels" = "Calles, puentes y túneles"
    "Wires and Cables" = "Cables y tendido"
}

function Esc([string]$s) { return ($s -replace '\\', '\\' -replace '"', '\"') }
function Name([string]$n) { if ($ES.ContainsKey($n)) { return $ES[$n] } else { return $n } }

$kw = @{}
$kept = 0; $dropped = 0

function GroupJs($g) {
    $ids = New-Object System.Collections.ArrayList
    foreach ($o in $g.SelectNodes("object")) {
        $id = [int]$o.model
        if (-not $valid.ContainsKey($id)) { $script:dropped++; continue }
        $script:kept++
        [void]$ids.Add($id)
        if ($o.keywords) { $script:kw[$id] = $o.keywords }
    }
    $kids = New-Object System.Collections.ArrayList
    foreach ($sub in $g.SelectNodes("group")) { $j = GroupJs $sub; if ($j) { [void]$kids.Add($j) } }
    if ($ids.Count -eq 0 -and $kids.Count -eq 0) { return $null }
    $s = "{n:`"$(Esc (Name $g.name))`""
    if ($ids.Count -gt 0) { $s += ",m:[" + ($ids -join ",") + "]" }
    if ($kids.Count -gt 0) { $s += ",c:[" + ($kids -join ",") + "]" }
    return $s + "}"
}

$top = New-Object System.Collections.ArrayList
foreach ($g in $doc.catalog.SelectNodes("group")) { $j = GroupJs $g; if ($j) { [void]$top.Add($j) } }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("/* rp_mapeditor: categorías del navegador de objetos, GENERADO por tools/generar-categorias.ps1 (no editar a mano).")
[void]$sb.AppendLine("   Árbol y palabras clave: objects.xml de multitheftauto/mtasa-resources (MIT), traducido al español. */")
[void]$sb.AppendLine("window.ME_CATS=[" + ($top -join ",") + "];")
$kwParts = foreach ($k in $kw.Keys) { "$k`:`"$(Esc $kw[$k])`"" }
[void]$sb.AppendLine("window.ME_KW={" + ($kwParts -join ",") + "};")

$out = Join-Path $PSScriptRoot "..\html\categories.js"
[IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK: $kept modelos en categorías ($dropped descartados: no están en el catálogo) -> $out"
