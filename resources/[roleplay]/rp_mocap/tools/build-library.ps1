<#
 build-library.ps1 - construye la biblioteca de mocap de personajes a partir de las escenas ANP3 de rp_animlab

   & build-library.ps1 -Escenas <carpeta con *_p.ifp> -Salida <carpeta rp_mocap> [-Gestos 14] [-Idles 6]

 Pasos: (1) mide por ventanas el movimiento de cada actor de cada escena; (2) clasifica GESTO (brazos activos, de pie, sin desplazarse, sin
 inclinar el cuerpo) e IDLE (casi quieto y que cierra bien el bucle); (3) elige por personaje los mejores tramos con diversidad entre escenas;
 (4) corta cada tramo como clip independiente normalizando la RAIZ (en el sitio: x,y = 0, z relativa; giro de escena -> orientacion base de ped);
 (5) escribe anims/mocap_<personaje>.ifp (ANP3, un clip por tramo: <personaje>_g01..., <personaje>_i01...), shared/mocap_catalog.lua y
 docs/MOCAP_CATALOGO.md. Los .ifp son material de Rockstar: no se suben al repo.
#>
param([string]$Escenas, [string]$Salida, [int]$Gestos = 14, [int]$Idles = 6)
$ErrorActionPreference = "Stop"
$inv = [Globalization.CultureInfo]::InvariantCulture
Add-Type -TypeDefinition @'
using System; using System.IO; using System.Text; using System.Linq; using System.Collections.Generic;

public class Bone { public int Id; public string Name; public int Type; public double[] T; public double[][] Q; public double[][] P; }
public class Actor { public string Scene, Name; public double Dur; public Dictionary<int, Bone> Bones = new Dictionary<int, Bone>(); }

public static class Mocap {
    static string S(byte[] b, int o, int n) { string s = Encoding.ASCII.GetString(b, o, n); int z = s.IndexOf('\0'); return z >= 0 ? s.Substring(0, z) : s; }
    public static List<Actor> Load(string path, string scene) {
        byte[] b = File.ReadAllBytes(path); var res = new List<Actor>();
        int n = BitConverter.ToInt32(b, 32); int p = 36;
        for (int a = 0; a < n; a++) {
            var act = new Actor { Scene = scene, Name = S(b, p, 24) }; int bones = BitConverter.ToInt32(b, p + 24); p += 36;
            for (int i = 0; i < bones; i++) {
                int t = BitConverter.ToInt32(b, p + 24), f = BitConverter.ToInt32(b, p + 28), id = BitConverter.ToInt32(b, p + 32);
                var bone = new Bone { Id = id, Name = S(b, p, 24), Type = t, T = new double[f], Q = new double[f][], P = t == 4 ? new double[f][] : null }; p += 36; int per = t == 4 ? 16 : 10;
                for (int k = 0; k < f; k++) { int o = p + k * per;
                    bone.Q[k] = new double[] { BitConverter.ToInt16(b,o)/4096.0, BitConverter.ToInt16(b,o+2)/4096.0, BitConverter.ToInt16(b,o+4)/4096.0, BitConverter.ToInt16(b,o+6)/4096.0 };
                    bone.T[k] = BitConverter.ToInt16(b,o+8)/60.0; if (bone.T[k] > act.Dur) act.Dur = bone.T[k];
                    if (t == 4) bone.P[k] = new double[] { BitConverter.ToInt16(b,o+10)/1024.0, BitConverter.ToInt16(b,o+12)/1024.0, BitConverter.ToInt16(b,o+14)/1024.0 }; }
                p += f * per; act.Bones[id] = bone;
            }
            res.Add(act);
        }
        return res;
    }
    public static int Idx(double[] t, double x) { int lo = 0, hi = t.Length - 1; while (lo < hi) { int m = (lo + hi + 1) / 2; if (t[m] <= x) lo = m; else hi = m - 1; } return lo; }
    public static double Ang(double[] a, double[] b) { double d = Math.Abs(a[0]*b[0]+a[1]*b[1]+a[2]*b[2]+a[3]*b[3]); if (d > 1) d = 1; return 2 * Math.Acos(d); }
    static readonly int[] ArmIds = { 22, 23, 24, 32, 33, 34 };
    static readonly int[] LegIds = { 41, 42, 51, 52 };
    static readonly int[] PoseIds = { 2, 3, 4, 5, 22, 23, 32, 33 };
    static readonly int[] TIds = { 22, 23, 32, 33 };
    // angulo medio (grados) de hombros y codos respecto a la rotacion identidad en el punto medio de la ventana: < ~25 = T-pose
    public static double TPoseAngle(Actor a, double t0, double w) {
        double sum = 0; int c = 0;
        foreach (int id in TIds) { if (!a.Bones.ContainsKey(id)) continue; var bn = a.Bones[id]; var q = bn.Q[Idx(bn.T, t0 + w / 2)];
            double d = Math.Abs(q[3]); if (d > 1) d = 1; sum += 2 * Math.Acos(d) * 180 / Math.PI; c++; }
        return c > 0 ? sum / c : 0;
    }

    // metricas de una ventana: [arms, legs, move, tilt, zrange, loop]
    public static double[] Window(Actor a, double t0, double w) {
        double arms = 0, legs = 0, move = 0, tilt = 0, zr = 0, loop = 0; int lc = 0;
        foreach (var kv in a.Bones) {
            var bn = kv.Value; int i0 = Idx(bn.T, t0), i1 = Idx(bn.T, t0 + w); double sum = 0;
            for (int k = i0 + 1; k <= i1; k++) sum += Ang(bn.Q[k-1], bn.Q[k]);
            if (ArmIds.Contains(bn.Id)) arms += sum; else if (LegIds.Contains(bn.Id)) legs += sum;
            if (PoseIds.Contains(bn.Id)) { loop += Ang(bn.Q[i0], bn.Q[i1]); lc++; }
            if (bn.Id == 0 && bn.P != null) {
                double zmin = 1e9, zmax = -1e9;
                for (int k = i0; k <= i1; k++) {
                    double x = bn.Q[k][0], y = bn.Q[k][1]; double c = 1 - 2*(x*x + y*y); if (c > 1) c = 1; if (c < -1) c = -1;
                    double tl = Math.Acos(c) * 180 / Math.PI; if (tl > tilt) tilt = tl;
                    if (bn.P[k][2] < zmin) zmin = bn.P[k][2]; if (bn.P[k][2] > zmax) zmax = bn.P[k][2];
                }
                zr = zmax - zmin; double dx = bn.P[i1][0] - bn.P[i0][0], dy = bn.P[i1][1] - bn.P[i0][1]; move = Math.Sqrt(dx*dx + dy*dy);
            }
        }
        return new double[] { arms / w, legs / w, move, tilt, zr, lc > 0 ? loop / lc : 9 };
    }

    // ---------- corte de clips con raiz normalizada ----------
    static double[] QMul(double[] a, double[] b) { return new double[] { a[3]*b[0] + a[0]*b[3] + a[1]*b[2] - a[2]*b[1], a[3]*b[1] - a[0]*b[2] + a[1]*b[3] + a[2]*b[0], a[3]*b[2] + a[0]*b[1] - a[1]*b[0] + a[2]*b[3], a[3]*b[3] - a[0]*b[0] - a[1]*b[1] - a[2]*b[2] }; }
    static double Yaw(double[] q) { return Math.Atan2(2*(q[3]*q[2] + q[0]*q[1]), 1 - 2*(q[1]*q[1] + q[2]*q[2])); }
    static short Q16(double v, double s) { double r = Math.Round(v * s); if (r > 32767) r = 32767; if (r < -32768) r = -32768; return (short)r; }
    static void Name24(BinaryWriter w, string s) { byte[] b = new byte[24]; byte[] t = Encoding.ASCII.GetBytes(s); Array.Copy(t, b, Math.Min(23, t.Length)); w.Write(b); }
    const double PedYaw = Math.PI / 2;     // yaw de la raiz en idle_stance de ped.ifp (+90 grados)
    const double PedZ = 0.02;              // altura de la raiz en idle_stance

    // devuelve los bytes del clip (cabeceras de hueso + fotogramas) y rellena nBones / frameBytes
    public static byte[] CutClip(Actor a, double t0, double w, out int nBones, out int frameBytes) {
        var ms = new MemoryStream(); var bw = new BinaryWriter(ms); nBones = 0; frameBytes = 0;
        if (!a.Bones.ContainsKey(0)) return new byte[0];
        var root = a.Bones[0]; int r0 = Idx(root.T, t0);
        double yaw0 = Yaw(root.Q[r0]); double h = (PedYaw - yaw0) / 2; double[] fix = { 0, 0, Math.Sin(h), Math.Cos(h) }; double z0 = root.P[r0][2];
        foreach (var kv in a.Bones.OrderBy(k => k.Key)) {
            var bn = kv.Value; int i0 = Idx(bn.T, t0); int i1 = Math.Min(bn.T.Length - 1, Idx(bn.T, t0 + w) + 1);
            var times = new List<double>(); var qs = new List<double[]>(); var ps = new List<double[]>();
            for (int k = i0; k <= i1; k++) {
                double tt = Math.Max(0, Math.Min(w, bn.T[k] - t0)); if (times.Count == 0) tt = 0;
                double[] q = bn.Q[k]; double[] p = bn.P != null ? bn.P[k] : null;
                if (bn.Id == 0) {
                    q = QMul(fix, q); double nn = Math.Sqrt(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3]); q = new double[] { q[0]/nn, q[1]/nn, q[2]/nn, q[3]/nn };
                    p = new double[] { 0, 0, p[2] - z0 + PedZ };      // en el sitio
                }
                if (times.Count > 0 && tt <= times[times.Count - 1]) { if (tt < times[times.Count - 1]) continue; tt = times[times.Count - 1] + 0.001; if (tt > w + 0.01) continue; }
                times.Add(tt); qs.Add(q); ps.Add(p);
            }
            if (times.Count == 1) { times.Add(w); qs.Add(qs[0]); ps.Add(ps[0]); }
            if (times[times.Count - 1] < w - 0.02) { times.Add(w); qs.Add(qs[qs.Count - 1]); ps.Add(ps[ps.Count - 1]); }
            bool isRoot = bn.Id == 0; int per = isRoot ? 16 : 10;
            Name24(bw, bn.Name); bw.Write(isRoot ? 4 : 3); bw.Write(times.Count); bw.Write(bn.Id);
            for (int k = 0; k < times.Count; k++) {
                bw.Write(Q16(qs[k][0], 4096)); bw.Write(Q16(qs[k][1], 4096)); bw.Write(Q16(qs[k][2], 4096)); bw.Write(Q16(qs[k][3], 4096)); bw.Write(Q16(times[k], 60));
                if (isRoot) { bw.Write(Q16(ps[k][0], 1024)); bw.Write(Q16(ps[k][1], 1024)); bw.Write(Q16(ps[k][2], 1024)); }
            }
            nBones++; frameBytes += times.Count * per;
        }
        return ms.ToArray();
    }
    public static byte[] WriteIfp(string libName, List<string> names, List<byte[]> clips, List<int> bones, List<int> fbytes) {
        var res = new MemoryStream(); var w = new BinaryWriter(res);
        w.Write(Encoding.ASCII.GetBytes("ANP3")); w.Write(0); Name24(w, libName); w.Write(clips.Count);
        for (int i = 0; i < clips.Count; i++) { Name24(w, names[i]); w.Write(bones[i]); w.Write(fbytes[i]); w.Write(1); w.Write(clips[i]); }
        byte[] o = res.ToArray(); Array.Copy(BitConverter.GetBytes(o.Length - 8), 0, o, 4, 4); return o;
    }
}
'@

function Char-Of([string]$actor) {
    $a = $actor.ToLower()
    switch ($a) { "csplay" { return "cj" } "csbigbearthin" { return "bigbear" } "csogloc" { return "ogloc" } default { return ($a -replace '^cs', '') } }
}
function F1($x) { return ([double]$x).ToString("0.0", $inv) }

$files = Get-ChildItem -LiteralPath $Escenas -Filter "*_p.ifp" | Sort-Object Name
$actors = New-Object System.Collections.Generic.List[Actor]
foreach ($f in $files) { foreach ($a in [Mocap]::Load($f.FullName, ($f.BaseName -replace '_p$', ''))) { $actors.Add($a) } }
"{0} actores en {1} escenas" -f $actors.Count, $files.Count

# candidatos por personaje
$cands = @{}
foreach ($a in $actors) {
    if ($a.Dur -lt 4) { continue }
    $ch = Char-Of $a.Name
    $wins = @()
    for ($t = 0.0; $t + 3.0 -le $a.Dur; $t += 0.5) { $m = [Mocap]::Window($a, $t, 3.0); $wins += [pscustomobject]@{ t = $t; arms = $m[0]; legs = $m[1]; move = $m[2]; tilt = $m[3]; zr = $m[4]; loop = $m[5]; tp = [Mocap]::TPoseAngle($a, $t, 3.0) } }
    if ($wins.Count -eq 0) { continue }
    $mean = ($wins | Measure-Object arms -Average).Average
    if (-not $cands.ContainsKey($ch)) { $cands[$ch] = @{ g = @(); i = @() } }
    foreach ($w in $wins) {
        if ($w.arms -ge [Math]::Max(2.5, $mean * 1.25) -and $w.move -lt 0.35 -and $w.tilt -lt 12 -and $w.zr -lt 0.25 -and $w.legs -lt 1.5 -and $w.tp -gt 25) {
            $cands[$ch].g += [pscustomobject]@{ actor = $a; t0 = $w.t; w = 3.0; arms = $w.arms; loop = $w.loop }
        }
        if ($w.arms -lt [Math]::Max(1.2, $mean * 0.6) -and $w.move -lt 0.2 -and $w.tilt -lt 12 -and $w.zr -lt 0.15 -and $w.loop -lt 0.35 -and $w.tp -gt 25) {
            $cands[$ch].i += [pscustomobject]@{ actor = $a; t0 = $w.t; w = 3.0; arms = $w.arms; loop = $w.loop }
        }
    }
}

function Pick($list, $n, $perScene) {
    $picked = @(); $count = @{}
    foreach ($c in $list) {
        if ($picked.Count -ge $n) { break }
        $sk = $c.actor.Scene + "/" + $c.actor.Name
        if ([int]$count[$sk] -ge $perScene) { continue }
        $dup = $picked | Where-Object { $_.actor.Scene -eq $c.actor.Scene -and $_.actor.Name -eq $c.actor.Name -and [Math]::Abs($_.t0 - $c.t0) -lt 3.0 }
        if ($dup) { continue }
        $picked += $c; $count[$sk] = 1 + [int]$count[$sk]
    }
    return $picked
}

[void][IO.Directory]::CreateDirectory("$Salida\anims"); [void][IO.Directory]::CreateDirectory("$Salida\shared")
$lua = New-Object System.Collections.Generic.List[string]
$lua.Add("-- Generado por tools/build-library.ps1 (no editar a mano). Catalogo de clips de mocap por personaje.")
$lua.Add("-- kind: gesture (un disparo, ~3 s) | idle (se reproduce en bucle). dur en segundos. scene/actor/t0 = origen en cuts.img.")
$lua.Add("MOCAP = {")
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Catalogo de mocap (generado)"); $md.Add("")
$md.Add("Origen: ``anim/cuts.img`` (cinematicas de GTA SA), convertido con ``rp_mocap/tools/build-library.ps1``. **Gesto** = un disparo de ~3 s con los brazos activos, de pie y sin desplazarse. **Idle** = postura casi quieta que cierra bien el bucle. Raiz normalizada (en el sitio, orientacion base de ped).")
$md.Add(""); $md.Add("| Personaje | Gestos | Idles | Archivo |"); $md.Add("|---|---|---|---|")
$detail = New-Object System.Collections.Generic.List[string]
$summary = @()
foreach ($ch in ($cands.Keys | Sort-Object)) {
    $g = @(Pick ($cands[$ch].g | Sort-Object arms -Descending) $Gestos 3)
    $i = @(Pick ($cands[$ch].i | Sort-Object loop) $Idles 2)
    if ($g.Count -lt 2) { continue }
    $names = New-Object 'System.Collections.Generic.List[string]'; $datas = New-Object 'System.Collections.Generic.List[byte[]]'
    $bones = New-Object 'System.Collections.Generic.List[int]'; $fb = New-Object 'System.Collections.Generic.List[int]'
    $entries = @()
    foreach ($set in @(@("g", "gesture", $g), @("i", "idle", $i))) {
        $n = 0
        foreach ($c in $set[2]) {
            $n++; $name = "{0}_{1}{2:00}" -f $ch, $set[0], $n
            $bc = 0; $fbytes = 0; $data = [Mocap]::CutClip($c.actor, $c.t0, $c.w, [ref]$bc, [ref]$fbytes)
            $names.Add($name); $datas.Add($data); $bones.Add($bc); $fb.Add($fbytes)
            $entries += [pscustomobject]@{ name = $name; kind = $set[1]; dur = $c.w; scene = $c.actor.Scene; actor = $c.actor.Name; t0 = $c.t0; arms = $c.arms }
        }
    }
    $ifp = [Mocap]::WriteIfp("MOCAP_" + $ch.ToUpper(), $names, $datas, $bones, $fb)
    [IO.File]::WriteAllBytes("$Salida\anims\mocap_$ch.ifp", $ifp)
    $lua.Add("    $ch = { block = `"mocap_$ch`", file = `"anims/mocap_$ch.ifp`", clips = {")
    foreach ($e in $entries) { $lua.Add(('        {{ name = "{0}", kind = "{1}", dur = {2}, scene = "{3}", actor = "{4}", t0 = {5} }},' -f $e.name, $e.kind, (F1 $e.dur), $e.scene, $e.actor, (F1 $e.t0))) }
    $lua.Add("    } },")
    $md.Add(("| {0} | {1} | {2} | ``anims/mocap_{0}.ifp`` ({3} KB) |" -f $ch, $g.Count, $i.Count, [int]($ifp.Length / 1KB)))
    $detail.Add(""); $detail.Add("### $ch"); $detail.Add(""); $detail.Add("| Clip | Tipo | Duracion | Escena | Actor | Inicio |"); $detail.Add("|---|---|---|---|---|---|")
    foreach ($e in $entries) { $detail.Add(("| {0} | {1} | {2} s | {3} | {4} | {5} s |" -f $e.name, $e.kind, (F1 $e.dur), $e.scene, $e.actor, (F1 $e.t0))) }
    $summary += ("{0}: {1} gestos, {2} idles, {3} KB" -f $ch, $g.Count, $i.Count, [int]($ifp.Length / 1KB))
}
$lua.Add("}")
$md.Add(""); $md.Add("## Clips por personaje"); foreach ($d in $detail) { $md.Add($d) }
$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText("$Salida\shared\mocap_catalog.lua", ($lua -join "`n") + "`n", $utf8)
[IO.File]::WriteAllText("$Salida\MOCAP_CATALOGO.md", ($md -join "`n") + "`n", $utf8)
$summary
