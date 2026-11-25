<#
 extract-cuts.ps1 - extrae el mocap de una cinematica de GTA SA (anim\cuts.img) y lo prepara para MTA

   extract-cuts.ps1 -Img "<juego>\anim\cuts.img" -Escenas sweet1b,sweet1a -Salida ..\anims [-Listar]

 Por escena escribe en -Salida:
   <escena>.ifp        copia con los huesos renombrados al esqueleto de peds (root->Normal, Spine 1->Spine, ...)
   <escena>_orig.ifp   copia sin tocar
 y muestra las pistas de cada actor ("cssweet", "csryder"...). Los .ifp son material de Rockstar: NO se suben al repo
 (ver .gitignore).
#>
param([string]$Img, [string[]]$Escenas, [string]$Salida, [switch]$Listar, [string[]]$Actores = @(), [switch]$SoloP)
$ErrorActionPreference = "Stop"
Add-Type -TypeDefinition @'
using System; using System.IO; using System.Text; using System.Collections.Generic;
public static class CutsTool {
    public class Entry { public string Name; public long Offset; public int Sectors; }
    public static List<Entry> ReadImg(string path) {
        var list = new List<Entry>();
        using (var fs = File.OpenRead(path)) using (var br = new BinaryReader(fs)) {
            br.ReadBytes(4); uint n = br.ReadUInt32();
            for (uint i = 0; i < n; i++) {
                uint off = br.ReadUInt32(); ushort stm = br.ReadUInt16(); ushort size = br.ReadUInt16(); string nm = Encoding.ASCII.GetString(br.ReadBytes(24));
                int z = nm.IndexOf('\0'); if (z >= 0) nm = nm.Substring(0, z);
                list.Add(new Entry { Name = nm, Offset = off, Sectors = Math.Max(stm, size) });
            }
        }
        return list;
    }
    public static byte[] Read(string path, Entry e) {
        using (var fs = File.OpenRead(path)) { fs.Position = e.Offset * 2048L; byte[] b = new byte[e.Sectors * 2048L]; fs.Read(b, 0, b.Length); return b; }
    }
    // cut (Max biped) -> esqueleto de peds de GTA SA
    static readonly Dictionary<string, string> Map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) {
        {"root","Normal"}, {"Spine 1","Spine"}, {"Spine 2","Spine1"}, {"jaw1","Jaw"}, {"lbrow1","L Brow"}, {"rbrow1","R Brow"},
    };
    public static string Rename(string name) { string t = name.Trim(); string r; return Map.TryGetValue(t, out r) ? r : t; }
    // Renombra in situ (campo de 28 bytes) las pistas de hueso: bloques "ANIM" de 44 bytes
    public static int PatchBones(byte[] b, List<string> log) {
        int changed = 0;
        for (int i = 0; i + 8 < b.Length; i++) {
            if (b[i]=='A'&&b[i+1]=='N'&&b[i+2]=='I'&&b[i+3]=='M' && BitConverter.ToInt32(b, i+4) == 44) {
                string nm = Encoding.ASCII.GetString(b, i+8, 28); int z = nm.IndexOf('\0'); if (z >= 0) nm = nm.Substring(0, z);
                string nn = Rename(nm);
                if (nn != nm) {
                    byte[] nb = Encoding.ASCII.GetBytes(nn); for (int k = 0; k < 28; k++) b[i+8+k] = (byte)(k < nb.Length ? nb[k] : 0);
                    changed++; if (log != null && log.Count < 8) log.Add("'" + nm + "' -> '" + nn + "'");
                }
            }
        }
        return changed;
    }
    // ---- ANPK (cinematica, floats) -> ANP3 (ped estandar, enteros), solo huesos del esqueleto de peds ----
    // Cuantizacion identica a la que aplica MTA al leer ANPK: xyz de la rotacion negados * 4096, w * 4096, traslacion * 1024, tiempo * 60
    class BoneDef { public string Name; public int Id; public BoneDef(string n, int id) { Name = n; Id = id; } }
    static readonly Dictionary<string, BoneDef> PedBones = new Dictionary<string, BoneDef>(StringComparer.OrdinalIgnoreCase) {
        {"root", new BoneDef("Normal", 0)}, {"pelvis", new BoneDef("Pelvis", 1)}, {"spine1", new BoneDef("Spine", 2)}, {"spine2", new BoneDef("Spine1", 3)},
        {"neck", new BoneDef("Neck", 4)}, {"head", new BoneDef("Head", 5)},
        {"bip01lclavicle", new BoneDef("Bip01 L Clavicle", 31)}, {"lupperarm", new BoneDef("L UpperArm", 32)}, {"lforearm", new BoneDef("L ForeArm", 33)},
        {"lhand", new BoneDef("L Hand", 34)}, {"lfinger", new BoneDef("L Finger", 35)}, {"lfinger01", new BoneDef("L Finger01", 36)},
        {"bip01rclavicle", new BoneDef("Bip01 R Clavicle", 21)}, {"rupperarm", new BoneDef("R UpperArm", 22)}, {"rforearm", new BoneDef("R ForeArm", 23)},
        {"rhand", new BoneDef("R Hand", 24)}, {"rfinger", new BoneDef("R Finger", 25)}, {"rfinger01", new BoneDef("R Finger01", 26)},
        {"lthigh", new BoneDef("L Thigh", 41)}, {"lcalf", new BoneDef("L Calf", 42)}, {"lfoot", new BoneDef("L Foot", 43)}, {"ltoe0", new BoneDef("L Toe0", 44)},
        {"rthigh", new BoneDef("R Thigh", 51)}, {"rcalf", new BoneDef("R Calf", 52)}, {"rfoot", new BoneDef("R Foot", 53)}, {"rtoe0", new BoneDef("R Toe0", 54)},
    };
    static short Q(double v, double scale) { double r = Math.Round(v * scale); if (r > 32767) r = 32767; if (r < -32768) r = -32768; return (short)r; }
    static string Key(string n) { return n.Trim().Replace(" ", "").ToLowerInvariant(); }
    static void PutName(BinaryWriter w, string s) { byte[] b = new byte[24]; byte[] t = Encoding.ASCII.GetBytes(s); Array.Copy(t, b, Math.Min(23, t.Length)); w.Write(b); }

    // actors: nombres de pista a exportar (p.ej. cssweet, csryder); devuelve el ANP3 y rellena el log
    public static byte[] ToAnp3(byte[] b, string scene, string[] actors, List<string> log) {
        int p = 8; int isz = BitConverter.ToInt32(b, p + 4); int entries = BitConverter.ToInt32(b, p + 8); p += 8 + ((isz + 3) & ~3);
        var outAnims = new List<byte[]>();
        for (int a = 0; a < entries; a++) {
            int nsz = BitConverter.ToInt32(b, p + 4); string name = Encoding.ASCII.GetString(b, p + 8, nsz).TrimEnd('\0'); p += 8 + ((nsz + 3) & ~3);
            p += 8; int jsz = BitConverter.ToInt32(b, p + 4); int bones = BitConverter.ToInt32(b, p + 8); p += 8 + ((jsz + 3) & ~3);
            bool want = (actors == null || actors.Length == 0) ? bones >= 40 : Array.Exists(actors, x => x.Equals(name, StringComparison.OrdinalIgnoreCase));
            var ms = new MemoryStream(); var w = new BinaryWriter(ms); int kept = 0; int frameBytes = 0;
            var tracks = new List<byte[]>();
            for (int j = 0; j < bones; j++) {
                p += 8; int asz = BitConverter.ToInt32(b, p + 4); string bn = Encoding.ASCII.GetString(b, p + 8, 28); int z = bn.IndexOf('\0'); if (z >= 0) bn = bn.Substring(0, z);
                int frames = BitConverter.ToInt32(b, p + 8 + 28); p += 8 + ((asz + 3) & ~3);
                if (frames == 0) continue;
                string ft = Encoding.ASCII.GetString(b, p, 4); int fsz = BitConverter.ToInt32(b, p + 4); int q = p + 8; p += 8 + ((fsz + 3) & ~3);
                if (!want) continue;
                BoneDef def; if (!PedBones.TryGetValue(Key(bn), out def)) continue;
                bool hasT = ft != "KR00"; int per = ft == "KR00" ? 20 : ft == "KRT0" ? 32 : 44;
                bool root = def.Id == 0;                       // la raiz lleva traslacion (tipo 4); el resto solo rotacion (tipo 3)
                var tm = new MemoryStream(); var tw = new BinaryWriter(tm);
                PutName(tw, def.Name); tw.Write(root ? 4 : 3); tw.Write(frames); tw.Write(def.Id);
                for (int f = 0; f < frames; f++) {
                    int o = q + f * per;
                    double rx = BitConverter.ToSingle(b, o), ry = BitConverter.ToSingle(b, o + 4), rz = BitConverter.ToSingle(b, o + 8), rw = BitConverter.ToSingle(b, o + 12);
                    double tx = 0, ty = 0, tz = 0, time;
                    if (hasT) { tx = BitConverter.ToSingle(b, o + 16); ty = BitConverter.ToSingle(b, o + 20); tz = BitConverter.ToSingle(b, o + 24); time = BitConverter.ToSingle(b, o + 28); }
                    else time = BitConverter.ToSingle(b, o + 16);
                    tw.Write(Q(-rx, 4096)); tw.Write(Q(-ry, 4096)); tw.Write(Q(-rz, 4096)); tw.Write(Q(rw, 4096));
                    tw.Write(Q(time, 60));
                    if (root) { tw.Write(Q(tx, 1024)); tw.Write(Q(ty, 1024)); tw.Write(Q(tz, 1024)); }
                }
                byte[] tb = tm.ToArray(); tracks.Add(tb); frameBytes += tb.Length - 36; kept++;
            }
            if (!want) continue;
            if (log != null) log.Add(name + ": " + kept + " huesos de ped exportados");
            PutName(w, name); w.Write(kept); w.Write(frameBytes); w.Write(1);
            foreach (var t in tracks) w.Write(t);
            outAnims.Add(ms.ToArray());
        }
        var res = new MemoryStream(); var rw2 = new BinaryWriter(res);
        rw2.Write(Encoding.ASCII.GetBytes("ANP3")); rw2.Write(0); PutName(rw2, scene.ToUpperInvariant()); rw2.Write(outAnims.Count);
        foreach (var a in outAnims) rw2.Write(a);
        byte[] outb = res.ToArray(); Array.Copy(BitConverter.GetBytes(outb.Length - 8), 0, outb, 4, 4);
        return outb;
    }

    public static string Tracks(byte[] b) {
        var sb = new StringBuilder(); string cur = null; int bones = 0;
        for (int i = 0; i + 8 < b.Length; i++) {
            if (b[i]=='N'&&b[i+1]=='A'&&b[i+2]=='M'&&b[i+3]=='E') { int len = BitConverter.ToInt32(b, i+4); if (len > 0 && len < 64 && i+8+len <= b.Length) { if (cur != null) sb.Append(cur + "(" + bones + " huesos) "); cur = Encoding.ASCII.GetString(b, i+8, len).TrimEnd('\0'); bones = 0; } }
            else if (b[i]=='A'&&b[i+1]=='N'&&b[i+2]=='I'&&b[i+3]=='M' && BitConverter.ToInt32(b, i+4) == 44) bones++;
        }
        if (cur != null) sb.Append(cur + "(" + bones + " huesos)");
        return sb.ToString();
    }
}
'@
if (-not (Test-Path -LiteralPath $Img)) { throw "No encuentro cuts.img: $Img" }
$entries = [CutsTool]::ReadImg($Img)
if ($Listar) { ($entries | Where-Object { $_.Name -like '*.cut' } | ForEach-Object { $_.Name -replace '\.cut$','' }) -join " "; return }
if (-not $Escenas -or -not $Salida) { throw "Faltan -Escenas y -Salida (o usa -Listar)" }
[void][IO.Directory]::CreateDirectory($Salida)
foreach ($s in $Escenas) {
    $e = $entries | Where-Object { $_.Name -ieq "$s.ifp" } | Select-Object -First 1
    if (-not $e) { Write-Warning "Escena '$s' no existe en cuts.img"; continue }
    $b = [CutsTool]::Read($Img, $e)
    # recorta al tamano real del IFP (campo de tamano tras la firma ANPK)
    $real = [BitConverter]::ToInt32($b, 4) + 8
    if ($real -gt 0 -and $real -le $b.Length) { $b = $b[0..($real - 1)] }
    if (-not $SoloP) { [IO.File]::WriteAllBytes((Join-Path $Salida "${s}_orig.ifp"), $b) }
    $log3 = New-Object System.Collections.Generic.List[string]
    $anp3 = [CutsTool]::ToAnp3($b.Clone(), $s, $Actores, $log3)
    [IO.File]::WriteAllBytes((Join-Path $Salida "${s}_p.ifp"), $anp3)
    "   ANP3 ${s}_p.ifp: {0:N0} KB -> {1}" -f ($anp3.Length / 1KB), ($log3 -join "; ")
    $log = New-Object 'System.Collections.Generic.List[string]'
    $changed = [CutsTool]::PatchBones($b, $log)
    if (-not $SoloP) { [IO.File]::WriteAllBytes((Join-Path $Salida "$s.ifp"), $b) }
    "{0}: {1:N0} KB, {2} huesos renombrados ({3})" -f $s, ($b.Length / 1KB), $changed, ($log -join "; ")
    "   actores: " + [CutsTool]::Tracks($b)
    $c = $entries | Where-Object { $_.Name -ieq "$s.cut" } | Select-Object -First 1
    if ($c) { [IO.File]::WriteAllText((Join-Path $Salida "$s.cut.txt"), ([Text.Encoding]::ASCII.GetString([CutsTool]::Read($Img, $c)).Split([char]0)[0])) }
}
