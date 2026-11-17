<#
.SYNOPSIS
    Sincroniza el servidor MTA local con `main` del repositorio (lo corre el Programador de tareas).

.DESCRIPTION
    Cada ejecucion hace `git fetch` en un clon de trabajo. Si `main` cambio:
      1. Hace respaldo de todo lo que va a tocar (backups\sync-AAAA-MM-DD_HHMMSS).
      2. Copia los archivos nuevos o cambiados a mods\deathmatch SIN pisar cambios locales:
         - si el archivo local es igual al anterior del repo -> se reemplaza;
         - si el local tiene cambios propios -> fusion de 3 vias; con conflicto se deja el
           archivo local y se guarda el del repo como <archivo>.main-nuevo;
         - los archivos borrados en el repo se mueven al respaldo (nunca se borran).
      3. Nunca toca: acl.xml, mtaserver.conf (solo agrega lineas), vehiclecolors.conf,
         rp_database\config.lua ni nada fuera de resources\, docs\, .claude\ y los .md de la raiz.
      4. Registra en mtaserver.conf los resources nuevos con startup="1", despues de sus
         dependencias (<include> del meta.xml) y respetando el orden del repo.
      5. Escribe un log legible con QUE REINICIAR: ultimo-sync.txt (y sync-local.log, historial).

    Si main no cambio, no hace nada ni escribe nada (salvo el log de errores si fallo el fetch).

.PARAMETER Init
    Prepara el clon de trabajo (git clone) y marca main como "ya aplicado" SIN copiar nada.
    Usalo una sola vez cuando el servidor ya esta al dia con main.

.PARAMETER DryRun
    Muestra lo que haria en el log, sin copiar ni modificar nada del servidor.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File sync-local.ps1 -Init
    powershell -NoProfile -ExecutionPolicy Bypass -File sync-local.ps1
#>
param(
    [string]$Root = (Join-Path $env:USERPROFILE "Documents\mta-rp-sync"),
    [string]$Server = "C:\Program Files (x86)\MTA San Andreas 1.6\server\mods\deathmatch",
    [string]$RepoUrl = "https://github.com/zThorium/MTA-SA-Roleplay-Gamemode-Thorium.git",
    [string]$Branch = "main",
    [switch]$Init,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Repo      = Join-Path $Root "repo"
$StateFile = Join-Path $Root "estado.txt"          # SHA de main ya aplicado al servidor
$LogFile   = Join-Path $Root "sync-local.log"      # historial
$LastFile  = Join-Path $Root "ultimo-sync.txt"     # resumen de la ultima sincronizacion
$LockFile  = Join-Path $Root "sync.lock"

# Rutas del repo que NUNCA se copian al servidor
$NeverCopy = @("acl.xml", "mtaserver.conf", "vehiclecolors.conf", ".gitignore")
$BinaryExt = @(".png", ".jpg", ".jpeg", ".wav", ".mp3", ".ogg", ".txd", ".dff", ".col", ".dll", ".exe", ".ttf", ".otf", ".woff", ".woff2")

$report = New-Object System.Collections.Generic.List[string]
function Say([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    $report.Add($msg)
}
function LogOnly([string]$msg) {
    Add-Content -LiteralPath $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) -Encoding UTF8
}

function Invoke-Git {
    $out = & git -C $Repo -c core.quotepath=false @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("git " + ($args -join " ") + " fallo: " + ($out -join " ")) }
    return $out
}

# Vuelca un archivo de una revision a disco, byte a byte
function GitShowToFile([string]$rev, [string]$path, [string]$dest) {
    $cmd = 'git -C "{0}" show "{1}:{2}" > "{3}"' -f $Repo, $rev, $path, $dest
    & cmd.exe /c $cmd 2>$null
    return ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $dest))
}

function Normalize([string]$src, [string]$dest) {
    $t = [IO.File]::ReadAllText($src)
    $t = $t.Replace("`r`n", "`n")
    [IO.File]::WriteAllText($dest, $t, (New-Object Text.UTF8Encoding($false)))
}

function FileHash([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}

function SameText([string]$a, [string]$b) {
    if (-not (Test-Path -LiteralPath $a) -or -not (Test-Path -LiteralPath $b)) { return $false }
    $ta = [IO.File]::ReadAllText($a).Replace("`r`n", "`n")
    $tb = [IO.File]::ReadAllText($b).Replace("`r`n", "`n")
    return ($ta -eq $tb)
}

# Ruta del repo -> ruta en el servidor (o $null si no se copia)
function MapToServer([string]$rel) {
    if ($NeverCopy -contains $rel) { return $null }
    if ($rel -like "tools/*") { return $null }
    if ($rel -match '(^|/)config\.lua$') { return $null }
    if ($rel -like "resources/*" -or $rel -like "docs/*" -or $rel -like ".claude/*") { return Join-Path $Server ($rel -replace '/', '\') }
    if ($rel -notmatch '/' -and $rel -match '\.md$') { return Join-Path $Server $rel }   # README.md, RECURSOS.md, CLAUDE.md
    return $null
}

function ResourceOf([string]$rel) {
    if ($rel -match '^resources/\[[^\]]+\]/([^/]+)/') { return $Matches[1] }
    return $null
}

function ConfNames([string]$confPath) {
    $names = @()
    foreach ($l in [IO.File]::ReadAllLines($confPath)) {
        if ($l -match '<resource\s+src="([^"]+)"') { $names += $Matches[1] }
    }
    return $names
}

function MetaIncludes([string]$metaPath) {
    $deps = @()
    if (Test-Path -LiteralPath $metaPath) {
        foreach ($l in [IO.File]::ReadAllLines($metaPath)) {
            if ($l -match '<include\s+resource="([^"]+)"') { $deps += $Matches[1] }
        }
    }
    return $deps
}

# ---------------------------------------------------------------- inicio
New-Item -ItemType Directory -Force -Path $Root | Out-Null
if (-not (Test-Path -LiteralPath $LogFile)) { New-Item -ItemType File -Path $LogFile | Out-Null }

# Un solo sync a la vez
if (Test-Path -LiteralPath $LockFile) {
    $age = (Get-Date) - (Get-Item -LiteralPath $LockFile).LastWriteTime
    if ($age.TotalMinutes -lt 15) { exit 0 }
}
$exitCode = 0
Set-Content -LiteralPath $LockFile -Value $PID
try {

    if ($Init) {
        if (-not (Test-Path -LiteralPath (Join-Path $Repo ".git"))) {
            & git clone --quiet $RepoUrl $Repo
            if ($LASTEXITCODE -ne 0) { throw "git clone fallo" }
        }
        & git -C $Repo config core.autocrlf false
        Invoke-Git fetch --quiet origin $Branch | Out-Null
        Invoke-Git checkout --quiet -B $Branch "origin/$Branch" | Out-Null
        $sha = (Invoke-Git rev-parse HEAD) | Select-Object -First 1
        Set-Content -LiteralPath $StateFile -Value $sha
        Say "Init: clon listo en $Repo; main ($($sha.Substring(0,7))) marcado como ya aplicado. No se copio nada."
        throw "__NOOP__"
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Repo ".git")) -or -not (Test-Path -LiteralPath $StateFile)) {
        throw "Falta el clon o estado.txt: ejecuta primero con -Init."
    }

    # --- fetch
    try { Invoke-Git fetch --quiet origin $Branch | Out-Null }
    catch { LogOnly ("ERROR fetch (sin red o sin acceso): " + $_.Exception.Message); throw "__NOOP__" }

    $old = (Get-Content -LiteralPath $StateFile -Raw).Trim()
    $new = (Invoke-Git rev-parse "origin/$Branch") | Select-Object -First 1
    if ($old -eq $new) { throw "__NOOP__" }     # main no cambio: silencio

    $report.Clear()
    $stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    Say ("main cambio: {0} -> {1}{2}" -f $old.Substring(0,7), $new.Substring(0,7), $(if ($DryRun) { "  (SIMULACRO: no se copia nada)" } else { "" }))
    foreach ($l in (Invoke-Git log --format="  - %s" "$old..$new" | Select-Object -First 15)) { $report.Add($l) }

    # --- actualizar clon de trabajo (es solo del script: se puede resetear)
    Invoke-Git checkout --quiet -B $Branch "origin/$Branch" | Out-Null
    Invoke-Git reset --quiet --hard "origin/$Branch" | Out-Null

    $backup = Join-Path $Server ("backups\sync-" + $stamp)
    $changes = @(Invoke-Git diff --name-status --no-renames $old $new)
    $copied = 0; $merged = 0; $conflicts = @(); $removed = 0; $skippedSame = 0
    $touchedRes = New-Object System.Collections.Generic.SortedSet[string]
    $newRes = New-Object System.Collections.Generic.SortedSet[string]
    $schemaChanged = $false
    $tmp = Join-Path $Root "tmp"; New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    foreach ($c in $changes) {
        $parts = $c -split "`t", 2
        if ($parts.Count -lt 2) { continue }
        $st = $parts[0].Substring(0,1); $rel = $parts[1]
        $dest = MapToServer $rel
        if (-not $dest) { continue }
        $res = ResourceOf $rel
        if ($rel -like "*rp_database/schema.lua") { $schemaChanged = $true }
        $src = Join-Path $Repo ($rel -replace '/', '\')
        $ext = [IO.Path]::GetExtension($rel).ToLower()
        $isBin = $BinaryExt -contains $ext

        if ($st -eq "D") {
            if (Test-Path -LiteralPath $dest) {
                $removed++
                if ($res) { [void]$touchedRes.Add($res) }
                if (-not $DryRun) {
                    $bk = Join-Path $backup ($rel -replace '/', '\')
                    New-Item -ItemType Directory -Force -Path (Split-Path $bk) | Out-Null
                    Move-Item -LiteralPath $dest -Destination ($bk + ".borrado-en-main") -Force
                }
                LogOnly "  borrado en main -> al respaldo: $rel"
            }
            continue
        }

        if ($res) { [void]$touchedRes.Add($res) }
        if ($st -eq "A" -and $rel -match '^resources/\[[^\]]+\]/[^/]+/meta\.xml$' -and $res) { [void]$newRes.Add($res) }
        $destExists = Test-Path -LiteralPath $dest
        if (-not $destExists) {
            $copied++
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
                Copy-Item -LiteralPath $src -Destination $dest -Force
            }
            continue
        }

        # ya existe en el servidor
        if ($isBin) { $same = ((FileHash $src) -eq (FileHash $dest)) } else { $same = (SameText $src $dest) }
        if ($same) { $skippedSame++; continue }

        $baseFile = Join-Path $tmp "base.tmp"
        $hasBase = ($st -ne "A") -and (GitShowToFile $old $rel $baseFile)
        $localIsOld = $false
        if ($hasBase) { if ($isBin) { $localIsOld = ((FileHash $baseFile) -eq (FileHash $dest)) } else { $localIsOld = (SameText $baseFile $dest) } }

        if ($localIsOld) {
            $copied++
            if (-not $DryRun) {
                $bk = Join-Path $backup ($rel -replace '/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $bk) | Out-Null
                Copy-Item -LiteralPath $dest -Destination $bk -Force
                Copy-Item -LiteralPath $src -Destination $dest -Force
            }
            continue
        }

        # archivo NUEVO en main que ya existia en el servidor con otro contenido (p. ej. copiado a mano desde un PR):
        # se toma la version de main y la tuya queda en el respaldo
        if ($st -eq "A") {
            $copied++
            if (-not $DryRun) {
                $bk = Join-Path $backup ($rel -replace '/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $bk) | Out-Null
                Copy-Item -LiteralPath $dest -Destination $bk -Force
                Copy-Item -LiteralPath $src -Destination $dest -Force
            }
            LogOnly "  nuevo en main, reemplaza copia local distinta (tu version en el respaldo): $rel"
            continue
        }

        # el local tiene cambios propios
        if ($isBin -or -not $hasBase) {
            $conflicts += $rel
            if (-not $DryRun) { Copy-Item -LiteralPath $src -Destination ($dest + ".main-nuevo") -Force }
            continue
        }
        $cur = Join-Path $tmp "cur.tmp"; $baseN = Join-Path $tmp "baseN.tmp"; $theirsN = Join-Path $tmp "theirsN.tmp"
        Normalize $dest $cur; Normalize $baseFile $baseN; Normalize $src $theirsN
        & git merge-file -L local -L base -L main $cur $baseN $theirsN 2>$null
        $rc = $LASTEXITCODE
        if ($rc -eq 0) {
            $merged++
            if (-not $DryRun) {
                $bk = Join-Path $backup ($rel -replace '/', '\'); New-Item -ItemType Directory -Force -Path (Split-Path $bk) | Out-Null
                Copy-Item -LiteralPath $dest -Destination $bk -Force
                Copy-Item -LiteralPath $cur -Destination $dest -Force
            }
            LogOnly "  fusionado con cambios locales: $rel"
        } else {
            $conflicts += $rel
            if (-not $DryRun) { Copy-Item -LiteralPath $src -Destination ($dest + ".main-nuevo") -Force }
        }
    }

    # --- registrar en mtaserver.conf
    $resRoot = Join-Path $Repo "resources"
    $confPath = Join-Path $Server "mtaserver.conf"
    $repoConf = Join-Path $Repo "mtaserver.conf"
    $confAdded = @()
    $repoOrder = ConfNames $repoConf
    $localNames = ConfNames $confPath
    $toAdd = @()
    foreach ($name in $repoOrder) { if ($localNames -notcontains $name) { $toAdd += $name } }

    if ($toAdd.Count -gt 0) {
        # solo se registran los que existen como carpeta en el repo (los nuevos de main)
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.AddRange([string[]][IO.File]::ReadAllLines($confPath))
        foreach ($name in $toAdd) {
            $metaRepo = Get-ChildItem -LiteralPath $resRoot -Recurse -Filter meta.xml -ErrorAction SilentlyContinue | Where-Object { $_.Directory.Name -eq $name } | Select-Object -First 1
            if (-not $metaRepo) { continue }
            $deps = MetaIncludes $metaRepo.FullName
            # posicion: despues de su predecesor en el orden del repo y de todas sus dependencias
            $minIdx = -1
            $iRepo = [array]::IndexOf($repoOrder, $name)
            for ($k = $iRepo - 1; $k -ge 0; $k--) {
                $idx = -1
                for ($j = 0; $j -lt $lines.Count; $j++) { if ($lines[$j] -match ('<resource\s+src="' + [regex]::Escape($repoOrder[$k]) + '"')) { $idx = $j; break } }
                if ($idx -ge 0) { $minIdx = $idx; break }
            }
            foreach ($d in $deps) {
                for ($j = 0; $j -lt $lines.Count; $j++) { if ($lines[$j] -match ('<resource\s+src="' + [regex]::Escape($d) + '"') -and $j -gt $minIdx) { $minIdx = $j } }
            }
            if ($minIdx -lt 0) {
                for ($j = $lines.Count - 1; $j -ge 0; $j--) { if ($lines[$j] -match '<resource\s+src=') { $minIdx = $j; break } }
            }
            $lines.Insert($minIdx + 1, ('    <resource src="{0}" startup="1" protected="0" />' -f $name))
            $confAdded += $name
            [void]$newRes.Add($name)
        }
        if ($confAdded.Count -gt 0 -and -not $DryRun) {
            New-Item -ItemType Directory -Force -Path $backup | Out-Null
            Copy-Item -LiteralPath $confPath -Destination (Join-Path $backup "mtaserver.conf") -Force
            [IO.File]::WriteAllLines($confPath, $lines.ToArray(), (New-Object Text.UTF8Encoding($false)))
        }
    }

    if (-not $DryRun) { Set-Content -LiteralPath $StateFile -Value $new }

    # --- informe
    $report.Add("")
    $report.Add(("Resultado: {0} copiados, {1} fusionados con tus cambios, {2} borrados (al respaldo), {3} ya iguales." -f $copied, $merged, $removed, $skippedSame))
    if ($confAdded.Count -gt 0) { $report.Add("Registrados en mtaserver.conf (startup=1): " + ($confAdded -join ", ")) }
    if (-not $DryRun -and (Test-Path -LiteralPath $backup)) { $report.Add("Respaldo: $backup") }
    if ($conflicts.Count -gt 0) {
        $report.Add("")
        $report.Add("ATENCION: estos archivos tienen cambios locales que chocan con main. Se dejo TU version y la de main quedo como <archivo>.main-nuevo para que la revises:")
        foreach ($c in $conflicts) { $report.Add("  - $c") }
    }
    $report.Add("")
    $report.Add("QUE REINICIAR:")
    if ($newRes.Count -gt 0) { $report.Add("Recursos nuevos: " + ($newRes -join ", ")) }
    if ($schemaChanged -or $confAdded.Count -gt 0 -or $newRes.Count -gt 0) {
        $report.Add("  -> Reinicia el SERVIDOR COMPLETO (cambio el esquema de la base de datos o se registraron recursos nuevos).")
    } elseif ($touchedRes.Count -gt 0) {
        $report.Add("  -> En la consola del servidor escribe: refresh")
        foreach ($r in $touchedRes) { $report.Add("     restart $r") }
    } else {
        $report.Add("  -> Nada: solo cambiaron documentos.")
    }
    if ($schemaChanged) { $report.Add("  (schema.lua cambio: hay migraciones de base de datos nuevas, se aplican solas al arrancar)") }

    $header = "Sincronizacion del " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Set-Content -LiteralPath $LastFile -Value (@($header, ("=" * $header.Length)) + $report) -Encoding UTF8
    foreach ($l in $report) { if ($l) { LogOnly $l } }

} catch {
    if ($_.Exception.Message -ne "__NOOP__") {
        LogOnly ("ERROR: " + $_.Exception.Message)
        Set-Content -LiteralPath $LastFile -Value ("Fallo la sincronizacion (" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "): " + $_.Exception.Message) -Encoding UTF8
        $exitCode = 1
    }
} finally {
    Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue
}
exit $exitCode
