<#
 check-library.ps1 - comprueba la biblioteca de mocap: detecta clips en T-pose (brazos casi en rotacion identidad)

   & check-library.ps1 -Anims <rp_mocap\anims> -Ped "<juego>\anim\ped.ifp"

 Por clip muestra el angulo medio de hombros y codos respecto a la identidad ("T") y respecto al reposo de un ped (idle_stance).
 Un clip con "T" < 25 grados es una T-pose y no debe estar en la biblioteca (build-library.ps1 ya los descarta).
#>
param([string]$Anims, [string]$Ped)
Add-Type -TypeDefinition @'
using System; using System.IO; using System.Text; using System.Collections.Generic;
public static class TPoseCheck {
    static double Ang(double[] a, double[] b) { double d = Math.Abs(a[0]*b[0]+a[1]*b[1]+a[2]*b[2]+a[3]*b[3]); if (d > 1) d = 1; return 2 * Math.Acos(d) * 180 / Math.PI; }
    public static Dictionary<int, double[]> Rest(string pedIfp, string anim) {
        byte[] b = File.ReadAllBytes(pedIfp); byte[] key = Encoding.ASCII.GetBytes(anim); var res = new Dictionary<int, double[]>();
        for (int i = 36; i + key.Length + 36 < b.Length; i++) {
            bool m = true; for (int k = 0; k < key.Length; k++) if ((b[i+k] | 0x20) != (key[k] | 0x20)) { m = false; break; }
            if (!m || b[i + key.Length] != 0) continue; int bones = BitConverter.ToInt32(b, i + 24); if (bones < 1 || bones > 64) continue; int p = i + 36;
            for (int bn = 0; bn < bones; bn++) { int t = BitConverter.ToInt32(b, p+24), f = BitConverter.ToInt32(b, p+28), id = BitConverter.ToInt32(b, p+32); p += 36; int per = t == 4 ? 16 : 10;
                res[id] = new double[] { BitConverter.ToInt16(b,p)/4096.0, BitConverter.ToInt16(b,p+2)/4096.0, BitConverter.ToInt16(b,p+4)/4096.0, BitConverter.ToInt16(b,p+6)/4096.0 }; p += f * per; }
            return res;
        }
        return res;
    }
    public static List<string> Run(string lib, Dictionary<int, double[]> rest) {
        byte[] b = File.ReadAllBytes(lib); var res = new List<string>(); int n = BitConverter.ToInt32(b, 32); int p = 36;
        int[] arm = { 22, 23, 32, 33 }; double[] ident = { 0, 0, 0, 1 };
        for (int a = 0; a < n; a++) {
            string nm = Encoding.ASCII.GetString(b, p, 24).TrimEnd('\0'); int bones = BitConverter.ToInt32(b, p + 24); p += 36; double dRest = 0, dId = 0; int c = 0;
            for (int i = 0; i < bones; i++) { int t = BitConverter.ToInt32(b, p+24), f = BitConverter.ToInt32(b, p+28), id = BitConverter.ToInt32(b, p+32); p += 36; int sz = t == 4 ? 16 : 10;
                if (Array.IndexOf(arm, id) >= 0) { double[] q = { BitConverter.ToInt16(b,p)/4096.0, BitConverter.ToInt16(b,p+2)/4096.0, BitConverter.ToInt16(b,p+4)/4096.0, BitConverter.ToInt16(b,p+6)/4096.0 };
                    dId += Ang(q, ident); if (rest.ContainsKey(id)) dRest += Ang(q, rest[id]); c++; }
                p += f * sz; }
            res.Add(string.Format("{0}|{1:F0}|{2:F0}", nm, dId / Math.Max(1, c), dRest / Math.Max(1, c)));
        }
        return res;
    }
}
'@
$rest = [TPoseCheck]::Rest($Ped, "idle_stance")
$bad = 0; $total = 0
foreach ($f in (Get-ChildItem -LiteralPath $Anims -Filter "mocap_*.ifp" | Sort-Object Name)) {
    foreach ($r in [TPoseCheck]::Run($f.FullName, $rest)) {
        $c = $r.Split("|"); $total++
        $flag = if ([double]$c[1] -lt 25) { $bad++; "  <-- T-POSE" } else { "" }
        "{0,-12} T={1,3} reposo={2,3}{3}" -f $c[0], $c[1], $c[2], $flag
    }
}
"{0} clips, {1} en T-pose" -f $total, $bad
