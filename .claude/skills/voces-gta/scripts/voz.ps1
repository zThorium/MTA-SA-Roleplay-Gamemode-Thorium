<#
 voz.ps1 - voces de personajes de GTA SA con Fish Audio (clonacion de voz)

   voz.ps1 voces
   voz.ps1 registrar -Voz sweet -Muestras <carpeta|archivo,archivo>      (clonacion sobre la marcha, sin crear modelo)
   voz.ps1 crear     -Voz sweet -Titulo "GTA SA - Sweet" -Muestras <carpeta>  (modelo persistente; exige credito en Fish)
   voz.ps1 hablar    -Voz sweet -Texto "[shouting] Grove Street!" -Salida out.mp3 [-Velocidad 1.0] [-Formato mp3|wav]
   voz.ps1 lote      -Voz sweet -Archivo lineas.txt -Carpeta salida [-Formato mp3]
        lineas.txt: una por linea "nombre|texto" (se ignoran vacias y las que empiezan con #)

 API key: $env:FISH_API_KEY o ~/.fish-audio-key (nunca va al repo).
 Voces registradas (IDs o rutas de muestras, sin secretos): voces.json junto a la skill.
 Transcripcion opcional de cada muestra: <muestra>.txt al lado (mejora el parecido).
#>
param(
    [Parameter(Position = 0)][string]$Comando = "voces",
    [string]$Voz, [string]$Titulo, [string[]]$Muestras, [string]$Texto, [string]$Salida,
    [string]$Archivo, [string]$Carpeta, [double]$Velocidad = 1.0, [string]$Formato = "mp3",
    [double]$Temperatura = 0.3, [string]$Idioma = "es"
)
$ErrorActionPreference = "Stop"
$skillDir = Split-Path -Parent $PSScriptRoot
$voicesFile = Join-Path $skillDir "voces.json"
$modelHeader = if ($env:FISH_MODEL) { $env:FISH_MODEL } else { "s2.1-pro-free" }
$utf8 = New-Object Text.UTF8Encoding $false

function Get-Key {
    if ($env:FISH_API_KEY) { return $env:FISH_API_KEY.Trim() }
    $f = Join-Path $HOME ".fish-audio-key"
    if (Test-Path $f) { return ([IO.File]::ReadAllText($f)).Trim() }
    throw "Falta la API key: define FISH_API_KEY o guardala en $f"
}

function Read-Voices {
    $h = @{}
    if (Test-Path $voicesFile) {
        $o = [IO.File]::ReadAllText($voicesFile) | ConvertFrom-Json
        $o.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
    }
    return $h
}

function Save-Voices($v) { [IO.File]::WriteAllText($voicesFile, ($v | ConvertTo-Json -Depth 4), $utf8) }

function Expand-Samples($list) {
    $files = @()
    foreach ($m in $list) {
        if (Test-Path $m -PathType Container) {
            $files += Get-ChildItem $m -File | Where-Object { $_.Extension -match '^\.(mp3|wav|flac)$' } | ForEach-Object { $_.FullName }
        } else { $files += (Resolve-Path $m).Path }
    }
    return $files
}

# ---- MessagePack minimo (la API solo acepta `references` en msgpack) ----
function Add-Be($b, [uint64]$n, [int]$bytes) { for ($i = $bytes - 1; $i -ge 0; $i--) { $b.Add([byte](($n -shr (8 * $i)) -band 0xFF)) } }
function Pack-Str($b, [string]$s) {
    $u = $utf8.GetBytes($s)
    if ($u.Length -lt 32) { $b.Add([byte](0xA0 -bor $u.Length)) }
    elseif ($u.Length -lt 65536) { $b.Add(0xDA); Add-Be $b $u.Length 2 }
    else { $b.Add(0xDB); Add-Be $b $u.Length 4 }
    $b.AddRange([byte[]]$u)
}
function Pack-Bin($b, [byte[]]$d) { $b.Add(0xC6); Add-Be $b $d.Length 4; $b.AddRange($d) }
function Pack-Float($b, [double]$n) { $raw = [BitConverter]::GetBytes($n); [Array]::Reverse($raw); $b.Add(0xCB); $b.AddRange([byte[]]$raw) }
function Pack-Map($b, [int]$count) { $b.Add(0xDE); Add-Be $b $count 2 }
function Pack-Arr($b, [int]$count) { $b.Add(0xDC); Add-Be $b $count 2 }

function Send-Tts([byte[]]$body, [string]$contentType, [string]$out) {
    $dir = Split-Path -Parent $out
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { [void][IO.Directory]::CreateDirectory($dir) }
    $headers = @{ Authorization = "Bearer $(Get-Key)"; model = $modelHeader }
    # Se descarga a un temporal y se mueve con -LiteralPath: -OutFile interpreta [corchetes] (p. ej. resources/[roleplay]) como comodines
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("voz_" + [guid]::NewGuid().ToString("N") + ".bin")
    try {
        Invoke-WebRequest -Uri "https://api.fish.audio/v1/tts" -Method Post -Headers $headers -ContentType $contentType -Body $body -OutFile $tmp -UseBasicParsing | Out-Null
    } catch {
        $msg = $_.Exception.Message
        if ($_.Exception.Response) { try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $msg += " | " + $sr.ReadToEnd() } catch {} }
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        throw "Fish Audio TTS fallo: $msg"
    }
    $len = (Get-Item -LiteralPath $tmp).Length
    if ($len -lt 1000) { Remove-Item -LiteralPath $tmp -Force; throw "Audio sospechosamente pequeno ($len bytes) para: $out" }
    Move-Item -LiteralPath $tmp -Destination $out -Force
    "{0}  ({1:N0} KB)" -f $out, ($len / 1KB)
}

function Speak-Once([string]$name, [string]$text, [string]$out) {
    $v = Read-Voices
    if (-not $name -or -not $v.ContainsKey($name)) { throw "Voz '$name' desconocida. Usa 'voces' para ver las registradas." }
    $e = $v[$name]
    if ($e.id) {
        $body = @{ text = $text; reference_id = $e.id; format = $Formato; temperature = $Temperatura; normalize = $true; language = $Idioma; prosody = @{ speed = $Velocidad; volume = 0 } }
        if ($Formato -eq "mp3") { $body.mp3_bitrate = 128 }
        return Send-Tts ($utf8.GetBytes(($body | ConvertTo-Json -Depth 5 -Compress))) "application/json; charset=utf-8" $out
    }
    $clips = @($e.muestras | ForEach-Object { if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $skillDir $_ } } | Where-Object { Test-Path $_ })
    if ($clips.Count -eq 0) { throw "No encuentro las muestras de '$name' en disco; registralas de nuevo con 'registrar'." }
    $b = New-Object 'System.Collections.Generic.List[byte]'
    Pack-Map $b 8
    Pack-Str $b "text"; Pack-Str $b $text
    Pack-Str $b "references"; Pack-Arr $b $clips.Count
    foreach ($c in $clips) {
        $t = [IO.Path]::ChangeExtension($c, ".txt")
        $tx = if (Test-Path $t) { ([IO.File]::ReadAllText($t, $utf8)).Trim() } else { "" }
        Pack-Map $b 2
        Pack-Str $b "audio"; Pack-Bin $b ([IO.File]::ReadAllBytes($c))
        Pack-Str $b "text"; Pack-Str $b $tx
    }
    Pack-Str $b "language"; Pack-Str $b $Idioma
    Pack-Str $b "format"; Pack-Str $b $Formato
    Pack-Str $b "temperature"; Pack-Float $b $Temperatura
    Pack-Str $b "normalize"; $b.Add(0xC3)
    Pack-Str $b "mp3_bitrate"; $b.Add(0xCC); $b.Add(128)
    Pack-Str $b "prosody"; Pack-Map $b 2; Pack-Str $b "speed"; Pack-Float $b $Velocidad; Pack-Str $b "volume"; Pack-Float $b 0.0
    return Send-Tts $b.ToArray() "application/msgpack" $out
}


# Fish a veces "desbarra" (audio mucho mas largo que el texto, incoherente). Se detecta por tamano y se reintenta.
function Speak([string]$name, [string]$text, [string]$out) {
    $clean = ($text -replace '\[[^\]]*\]', '').Trim()
    $limit = [Math]::Max(60000, 2300 * $clean.Length)   # demasiado largo = desbarro
    $floor = 700 * $clean.Length                          # demasiado corto = frase comida o recortada
    for ($try = 1; $try -le 4; $try++) {
        $r = Speak-Once $name $text $out
        $len = (Get-Item -LiteralPath $out).Length
        if ($Formato -ne "mp3" -or ($len -le $limit -and $len -ge $floor)) { return $r }
        Write-Warning ("Intento {0}: audio sospechoso ({1:N0} KB para {2} caracteres), reintento..." -f $try, ($len / 1KB), $clean.Length)
    }
    throw "No se obtuvo un audio coherente tras 4 intentos para: $text"
}
switch ($Comando) {
    "voces" {
        $v = Read-Voices
        if ($v.Count -eq 0) { "No hay voces registradas. Usa: voz.ps1 registrar -Voz sweet -Muestras <carpeta>" }
        foreach ($k in $v.Keys) {
            $e = $v[$k]
            $how = if ($e.id) { "modelo " + $e.id } else { "zero-shot, " + @($e.muestras).Count + " muestras" }
            "{0}  ->  {1}  ({2})" -f $k, $e.titulo, $how
        }
    }
    "registrar" {
        if (-not $Voz -or -not $Muestras) { throw "Faltan -Voz y -Muestras" }
        $files = Expand-Samples $Muestras
        $v = Read-Voices
        $rel = @($files | ForEach-Object { if ($_.StartsWith($skillDir)) { $_.Substring($skillDir.Length).TrimStart([char]92).Replace([string][char]92, "/") } else { $_ } })
        $v[$Voz] = @{ modo = "zero-shot"; titulo = $(if ($Titulo) { $Titulo } else { "GTA SA - $Voz" }); muestras = $rel }
        Save-Voices $v
        "Voz '$Voz' registrada con $($files.Count) muestras (zero-shot)"
    }
    "crear" {
        if (-not $Voz -or -not $Muestras) { throw "Faltan -Voz y -Muestras" }
        $files = Expand-Samples $Muestras
        if ($files.Count -lt 1 -or $files.Count -gt 20) { throw "Se necesitan entre 1 y 20 muestras (hay $($files.Count))" }
        if (-not $Titulo) { $Titulo = "GTA SA - $Voz" }
        $a = @("-sS", "-X", "POST", "https://api.fish.audio/model", "-H", "Authorization: Bearer $(Get-Key)",
            "--form-string", "type=tts", "--form-string", "title=$Titulo", "--form-string", "train_mode=fast",
            "--form-string", "visibility=private", "--form-string", "enhance_audio_quality=true")
        foreach ($f in $files) {
            $a += @("--form", "voices=@$f")
            $t = [IO.Path]::ChangeExtension($f, ".txt")
            if (Test-Path $t) { $a += @("--form-string", "texts=$(([IO.File]::ReadAllText($t, $utf8)).Trim())") }
        }
        $raw = & curl.exe @a
        $res = $raw | ConvertFrom-Json
        if (-not $res._id) { throw "Fish Audio no creo el modelo: $raw" }
        $v = Read-Voices
        $v[$Voz] = @{ id = $res._id; titulo = $Titulo; muestras = $files.Count }
        Save-Voices $v
        "Modelo creado: $($res._id) (estado: $($res.state)) -> guardado como '$Voz'"
    }
    "hablar" {
        if (-not $Texto -or -not $Salida) { throw "Faltan -Texto y -Salida" }
        Speak $Voz $Texto $Salida
    }
    "lote" {
        if (-not $Archivo -or -not $Carpeta) { throw "Faltan -Archivo y -Carpeta" }
        foreach ($line in [IO.File]::ReadAllLines($Archivo, $utf8)) {
            if (-not $line.Trim() -or $line.TrimStart().StartsWith("#")) { continue }
            $p = $line.Split("|", 2)
            if ($p.Count -lt 2) { Write-Warning "Linea sin '|': $line"; continue }
            Speak $Voz $p[1].Trim() (Join-Path $Carpeta ($p[0].Trim() + "." + $Formato))
        }
    }
    default { throw "Comando desconocido '$Comando' (voces | registrar | crear | hablar | lote)" }
}
