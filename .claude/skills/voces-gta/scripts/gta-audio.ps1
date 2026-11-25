<#
 gta-audio.ps1 - extrae sonidos de los bancos SFX de GTA San Andreas (PC) a WAV

 Formato (verificado): AUDIO/CONFIG/PakFiles.dat   = nombres de los archivos SFX (52 bytes por entrada, nombre al inicio)
                       AUDIO/CONFIG/BankLkup.dat   = 12 bytes por banco: u8 pak, 3 pad, u32 offset, u32 longitud de datos
                       cada banco en el pak: cabecera de 4804 bytes (u32 nSonidos + 400 x {u32 offset, i32 loop, u16 rate, u16 headroom})
                       seguida de los datos: PCM 16 bit mono sin cabecera; offset de cada sonido relativo al inicio de los datos.
 El doblaje latino reemplaza SCRIPT->ZAINES (dialogos de misiones), PAIN_A->MAGOTA, SPC_FA->HUGUIT, SPC_PA->FLOREN.

 Uso:
   gta-audio.ps1 indice  -Config <AUDIO\CONFIG> -Sfx <dir1>,<dir2> [-Pak ZAINES]          lista bancos (n sonidos, segundos)
   gta-audio.ps1 extraer -Config ... -Sfx ... -Banco 147 [-Sonidos 1,2,5] -Salida <carpeta>   escribe sonido_NNN.wav
   gta-audio.ps1 durs    -Config ... -Sfx ... -Banco 147                                    duracion y rate de cada sonido
#>
param(
    [Parameter(Position = 0)][string]$Comando = "indice",
    [string]$Config, [string[]]$Sfx, [string]$Pak, [int]$Banco = -1, [int[]]$Sonidos, [string]$Salida
)
$ErrorActionPreference = "Stop"
Add-Type -TypeDefinition @'
using System; using System.IO; using System.Collections.Generic; using System.Text;
public class GtaBank { public int Index, Pak; public long Offset, Length; public int Count; public uint[] Offs; public int[] Rates; }
public static class GtaAudio {
    public static string[] PakNames;
    public static List<long[]> Lookup = new List<long[]>();   // pak, offset, length
    public static List<string> SfxDirs = new List<string>();
    public static void Load(string config, string[] sfxDirs) {
        byte[] p = File.ReadAllBytes(Path.Combine(config, "PakFiles.dat"));
        int n = p.Length / 52; PakNames = new string[n];
        for (int i = 0; i < n; i++) { int e = 0; while (e < 14 && p[i * 52 + e] != 0 && p[i * 52 + e] != 0xCD) e++; PakNames[i] = Encoding.ASCII.GetString(p, i * 52, e); }
        byte[] b = File.ReadAllBytes(Path.Combine(config, "BankLkup.dat"));
        Lookup.Clear();
        for (int i = 0; i < b.Length / 12; i++) Lookup.Add(new long[] { b[i * 12], BitConverter.ToUInt32(b, i * 12 + 4), BitConverter.ToUInt32(b, i * 12 + 8) });
        SfxDirs.Clear(); SfxDirs.AddRange(sfxDirs);
    }
    public static string FindPak(string name) {
        foreach (string d in SfxDirs) { string f = Path.Combine(d, name); if (File.Exists(f)) return f; }
        return null;
    }
    public static GtaBank ReadBank(int index) {
        long[] l = Lookup[index];
        GtaBank bk = new GtaBank { Index = index, Pak = (int)l[0], Offset = l[1], Length = l[2] };
        string f = FindPak(PakNames[bk.Pak]);
        if (f == null) return null;
        using (FileStream fs = File.OpenRead(f)) {
            if (bk.Offset + 4804 > fs.Length) return null;
            byte[] h = new byte[4804]; fs.Position = bk.Offset; fs.Read(h, 0, 4804);
            int n = (int)BitConverter.ToUInt32(h, 0);
            if (n < 0 || n > 400) return null;
            bk.Count = n; bk.Offs = new uint[n]; bk.Rates = new int[n];
            for (int i = 0; i < n; i++) { bk.Offs[i] = BitConverter.ToUInt32(h, 4 + i * 12); bk.Rates[i] = BitConverter.ToUInt16(h, 4 + i * 12 + 8); }
        }
        return bk;
    }
    public static long SoundLength(GtaBank bk, int i) { long end = (i + 1 < bk.Count) ? bk.Offs[i + 1] : bk.Length; return end - bk.Offs[i]; }
    public static double Seconds(GtaBank bk, int i) { return SoundLength(bk, i) / 2.0 / Math.Max(1, bk.Rates[i]); }
    public static void WriteWav(GtaBank bk, int i, string path) {
        string f = FindPak(PakNames[bk.Pak]);
        long len = SoundLength(bk, i); byte[] pcm = new byte[len];
        using (FileStream fs = File.OpenRead(f)) { fs.Position = bk.Offset + 4804 + bk.Offs[i]; fs.Read(pcm, 0, (int)len); }
        using (BinaryWriter w = new BinaryWriter(File.Create(path))) {
            int rate = bk.Rates[i];
            w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write((int)(36 + len)); w.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
            w.Write(16); w.Write((short)1); w.Write((short)1); w.Write(rate); w.Write(rate * 2); w.Write((short)2); w.Write((short)16);
            w.Write(Encoding.ASCII.GetBytes("data")); w.Write((int)len); w.Write(pcm);
        }
    }
}
'@
if (-not $Config) { throw "Falta -Config (carpeta AUDIO\CONFIG)" }
if (-not $Sfx) { throw "Falta -Sfx (carpeta(s) con los archivos SFX)" }
[GtaAudio]::Load($Config, $Sfx)

switch ($Comando) {
    "indice" {
        for ($i = 0; $i -lt [GtaAudio]::Lookup.Count; $i++) {
            $pakName = [GtaAudio]::PakNames[[GtaAudio]::Lookup[$i][0]]
            if ($Pak -and $pakName -ne $Pak) { continue }
            $bk = [GtaAudio]::ReadBank($i)
            if (-not $bk) { continue }
            $tot = 0.0; for ($s = 0; $s -lt $bk.Count; $s++) { $tot += [GtaAudio]::Seconds($bk, $s) }
            "{0,4}  {1,-7} sonidos={2,3}  {3,7:N1}s" -f $i, $pakName, $bk.Count, $tot
        }
    }
    "durs" {
        $bk = [GtaAudio]::ReadBank($Banco)
        if (-not $bk) { throw "Banco $Banco no disponible (¿falta el archivo SFX?)" }
        for ($s = 0; $s -lt $bk.Count; $s++) { "{0,3}  {1,5:N2}s  {2}Hz" -f ($s + 1), [GtaAudio]::Seconds($bk, $s), $bk.Rates[$s] }
    }
    "extraer" {
        if ($Banco -lt 0 -or -not $Salida) { throw "Faltan -Banco y -Salida" }
        $bk = [GtaAudio]::ReadBank($Banco)
        if (-not $bk) { throw "Banco $Banco no disponible" }
        [void][IO.Directory]::CreateDirectory($Salida)
        $list = if ($Sonidos) { $Sonidos } else { 1..$bk.Count }
        foreach ($n in $list) {
            if ($n -lt 1 -or $n -gt $bk.Count) { continue }
            [GtaAudio]::WriteWav($bk, $n - 1, (Join-Path $Salida ("sonido_{0:000}.wav" -f $n)))
        }
        "{0} sonidos de {1} en {2}" -f @($list).Count, [GtaAudio]::PakNames[$bk.Pak], $Salida
    }
    default { throw "Comando desconocido '$Comando' (indice | durs | extraer)" }
}
