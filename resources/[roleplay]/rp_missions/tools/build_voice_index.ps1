# Reconstruye shared/s_voice.lua (duraciones y extension de cada voz) y las lineas <file src="audio/..."> del meta.xml
# a partir de lo que haya en audio/ (wav = TTS de Windows, mp3 = voces clonadas con la skill voces-gta).
# Si existen ambos para una linea, gana el mp3. mp3: se asume 128 kbps CBR (bytes*8/128 = ms).
param([string]$Res = (Split-Path -Parent $PSScriptRoot))
$utf8 = New-Object Text.UTF8Encoding $false
$files = @{}
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $Res "audio") -File | Where-Object { $_.Extension -in ".wav", ".mp3" } | Sort-Object Name)) {
    $n = $f.BaseName
    if ($files.ContainsKey($n) -and $f.Extension -eq ".wav") { continue }
    $files[$n] = $f
}
$lens = @(); $exts = @(); $metaFiles = @()
foreach ($n in ($files.Keys | Sort-Object)) {
    $f = $files[$n]
    $ms = if ($f.Extension -eq ".mp3") { [int]($f.Length / 16) } else { [int](($f.Length - 44) / 32) }   # wav: 16 kHz mono 16 bit
    $lens += ('    ["{0}"] = {1},' -f $n, $ms)
    if ($f.Extension -eq ".mp3") { $exts += ('    ["{0}"] = "mp3",' -f $n) }
    $metaFiles += ('    <file src="audio/{0}" />' -f $f.Name)
}
$lua = @("-- Generado por tools/build_voice_index.ps1: duracion en ms y extension de cada linea con voz", "VOICE_LEN = {") + $lens + @("}", "", "VOICE_EXT = {") + $exts + @("}", "",
'for _, def in ipairs(MISSION_DEFS) do',
'    for si, st in ipairs(def.stages) do',
'        for i, l in ipairs((st.cutscene and st.cutscene.lines) or {}) do',
'            local n = ("%s_%d%s%d"):format(def.key, si, "c", i)',
'            if VOICE_LEN[n] then l.voice, l.vlen = "audio/" .. n .. "." .. (VOICE_EXT[n] or "wav"), VOICE_LEN[n] end',
'        end',
'        for i, l in ipairs(st.radio or {}) do',
'            local n = ("%s_%d%s%d"):format(def.key, si, "r", i)',
'            if VOICE_LEN[n] then l.voice, l.vlen = "audio/" .. n .. "." .. (VOICE_EXT[n] or "wav"), VOICE_LEN[n] end',
'        end',
'    end',
'end')
[IO.File]::WriteAllText((Join-Path $Res "shared\s_voice.lua"), ($lua -join "`n") + "`n", $utf8)
$meta = [IO.File]::ReadAllLines((Join-Path $Res "meta.xml"), $utf8) | Where-Object { $_ -notmatch '<file src="audio/' }
$out = New-Object System.Collections.Generic.List[string]
foreach ($l in $meta) { $out.Add($l); if ($l -match '<file src="html/app\.js" />') { $metaFiles | ForEach-Object { $out.Add($_) } } }
[IO.File]::WriteAllText((Join-Path $Res "meta.xml"), ($out -join "`n") + "`n", $utf8)
"{0} voces indexadas ({1} mp3)" -f $files.Count, $exts.Count