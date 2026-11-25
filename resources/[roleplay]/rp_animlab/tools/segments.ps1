<#
 segments.ps1 - busca tramos aprovechables en el mocap ANP3 (<escena>_p.ifp): gestos de pie, caminar, idle

   segments.ps1 -Ifp anims\sweet1b_p.ifp [-Ventana 3] [-Paso 1] [-Top 8]

 Por actor y ventana de tiempo mide: actividad de brazos (giro de hombro/codo/mano), de piernas, de columna y desplazamiento
 horizontal de la raiz. Clasifica: GESTO (brazos activos, de pie), CAMINAR (desplaza la raiz), IDLE (casi quieto).
 Escribe el ranking de GESTO por actor. Prueba cada candidato en juego con /animlab segmento.
#>
param([string]$Ifp, [double]$Ventana = 3, [double]$Paso = 1, [int]$Top = 8)
Add-Type -TypeDefinition @'
using System; using System.IO; using System.Text; using System.Collections.Generic;
public class Seg { public string Actor, Kind; public double T0, Dur, Arms, Legs, Spine, Move, Total; }
public static class SegTool {
    class Track { public int Id; public double[] Time; public double[][] Q; public double[][] P; }
    static double Ang(double[] a, double[] b) { double d = Math.Abs(a[0]*b[0]+a[1]*b[1]+a[2]*b[2]+a[3]*b[3]); if (d > 1) d = 1; return 2 * Math.Acos(d); }
    public static List<Seg> Analyze(string path, double win, double step) {
        byte[] b = File.ReadAllBytes(path); var res = new List<Seg>();
        int n = BitConverter.ToInt32(b, 32); int p = 36;
        for (int a = 0; a < n; a++) {
            string nm = Encoding.ASCII.GetString(b, p, 24).TrimEnd('\0'); int bones = BitConverter.ToInt32(b, p + 24); p += 36;
            var tracks = new List<Track>(); double dur = 0;
            for (int i = 0; i < bones; i++) {
                int t = BitConverter.ToInt32(b, p + 24), f = BitConverter.ToInt32(b, p + 28), id = BitConverter.ToInt32(b, p + 32); p += 36; int per = t == 4 ? 16 : 10;
                var tr = new Track { Id = id, Time = new double[f], Q = new double[f][], P = t == 4 ? new double[f][] : null };
                for (int k = 0; k < f; k++) { int o = p + k * per;
                    tr.Q[k] = new double[] { BitConverter.ToInt16(b,o)/4096.0, BitConverter.ToInt16(b,o+2)/4096.0, BitConverter.ToInt16(b,o+4)/4096.0, BitConverter.ToInt16(b,o+6)/4096.0 };
                    tr.Time[k] = BitConverter.ToInt16(b,o+8)/60.0; if (tr.Time[k] > dur) dur = tr.Time[k];
                    if (t == 4) tr.P[k] = new double[] { BitConverter.ToInt16(b,o+10)/1024.0, BitConverter.ToInt16(b,o+12)/1024.0, BitConverter.ToInt16(b,o+14)/1024.0 }; }
                p += f * per; tracks.Add(tr);
            }
            if (dur < win) continue;
            for (double t0 = 0; t0 + win <= dur + 0.001; t0 += step) {
                double arms = 0, legs = 0, spine = 0, move = 0; double[] ps = null, pe = null;
                foreach (var tr in tracks) {
                    int i0 = Idx(tr.Time, t0), i1 = Idx(tr.Time, t0 + win);
                    double sum = 0; for (int k = i0 + 1; k <= i1; k++) sum += Ang(tr.Q[k - 1], tr.Q[k]);
                    if (tr.Id == 22 || tr.Id == 23 || tr.Id == 24 || tr.Id == 32 || tr.Id == 33 || tr.Id == 34) arms += sum;
                    else if (tr.Id == 41 || tr.Id == 42 || tr.Id == 51 || tr.Id == 52) legs += sum;
                    else if (tr.Id == 2 || tr.Id == 3 || tr.Id == 4) spine += sum;
                    if (tr.Id == 0 && tr.P != null) { ps = tr.P[i0]; pe = tr.P[i1]; }
                }
                if (ps != null) move = Math.Sqrt((pe[0]-ps[0])*(pe[0]-ps[0]) + (pe[1]-ps[1])*(pe[1]-ps[1]));
                res.Add(new Seg { Actor = nm, Total = dur, T0 = t0, Dur = win, Arms = arms / win, Legs = legs / win, Spine = spine / win, Move = move });
            }
        }
        return res;
    }
    static int Idx(double[] times, double t) { int lo = 0, hi = times.Length - 1; while (lo < hi) { int m = (lo + hi + 1) / 2; if (times[m] <= t) lo = m; else hi = m - 1; } return lo; }
}
'@
$all = [SegTool]::Analyze($Ifp, $Ventana, $Paso)
$actors = $all | Group-Object Actor
foreach ($g in $actors) {
    $segs = $g.Group
    $meanArms = ($segs | Measure-Object Arms -Average).Average
    foreach ($s in $segs) {
        $s.Kind = if ($s.Move -gt 0.8 -or $s.Legs -gt 1.2) { "CAMINAR" } elseif ($s.Arms -gt $meanArms * 1.25 -and $s.Move -lt 0.35) { "GESTO" } elseif ($s.Arms -lt $meanArms * 0.5) { "IDLE" } else { "OTRO" }
    }
    "== {0}  (dur {5:N1}s, actividad media de brazos {1:N2} rad/s)  GESTO={2} CAMINAR={3} IDLE={4}" -f $g.Name, $meanArms, ($segs | ? Kind -eq GESTO).Count, ($segs | ? Kind -eq CAMINAR).Count, ($segs | ? Kind -eq IDLE).Count, $segs[0].Total
    # candidatos GESTO: mayor actividad de brazos, sin solapar entre si
    $picked = @()
    foreach ($s in ($segs | ? Kind -eq GESTO | Sort-Object Arms -Descending)) {
        if ($picked.Count -ge $Top) { break }
        if (-not ($picked | ? { [math]::Abs($_.T0 - $s.T0) -lt $Ventana })) { $picked += $s }
    }
    foreach ($s in ($picked | Sort-Object T0)) { "   GESTO  inicio {0,5:N1}s  dur {1}s  brazos {2:N2}  columna {3:N2}  desplaz {4:N2} m" -f $s.T0, $s.Dur, $s.Arms, $s.Spine, $s.Move }
    $idle = $segs | ? Kind -eq IDLE | Sort-Object Arms | Select-Object -First 2
    foreach ($s in ($idle | Sort-Object T0)) { "   IDLE   inicio {0,5:N1}s  dur {1}s  brazos {2:N2}" -f $s.T0, $s.Dur, $s.Arms }
}
