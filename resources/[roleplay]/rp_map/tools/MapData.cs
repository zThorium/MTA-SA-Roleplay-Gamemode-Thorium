using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.Collections.Generic;

// Extrae de la instalacion local de GTA SA los datos que usa rp_map:
//   - red de calles (data/Paths/NODES*.DAT) con sentido de circulacion -> GPS y dibujo de calles
//   - edificios (IDE + IPL de texto y binarios de gta3.img + cajas de colision .col) -> modo 3D
//   - mascara de tierra/agua y relieve a partir del radar y de los nodos
// Lo llama tools/generar-datos.ps1. Ver docs/MAPA.md.
public static class MapData
{
    static readonly CultureInfo IC = CultureInfo.InvariantCulture;
    public const int CELL = 50;              // metros por celda de exploracion
    public const int CELLS = 6000 / CELL;    // 120 x 120

    // ------------------------------------------------------------------ IMG
    public class ImgEntry { public uint Offset; public uint Size; public string Name; }

    public static List<ImgEntry> ReadImg(BinaryReader br)
    {
        var list = new List<ImgEntry>();
        br.BaseStream.Position = 0;
        br.ReadBytes(4);
        uint n = br.ReadUInt32();
        for (int i = 0; i < n; i++)
        {
            uint off = br.ReadUInt32();
            ushort s1 = br.ReadUInt16(), s2 = br.ReadUInt16();
            string name = Encoding.ASCII.GetString(br.ReadBytes(24)).Split('\0')[0];
            list.Add(new ImgEntry { Offset = off, Size = Math.Max(s1, s2), Name = name });
        }
        return list;
    }

    static byte[] ReadEntry(BinaryReader br, ImgEntry e)
    {
        br.BaseStream.Position = (long)e.Offset * 2048;
        return br.ReadBytes((int)e.Size * 2048);
    }

    static string F1(double v) { return Math.Round(v, 1).ToString(IC); }

    // ------------------------------------------------------------------ Radar
    // Une los tiles del radar (RadarExtract de rp_hud) y los guarda en JPG a 'size' px.
    public static string Radar(string png, string jpg, int size)
    {
        using (var src = new Bitmap(png))
        using (var big = new Bitmap(size, size, PixelFormat.Format24bppRgb))
        using (var g = Graphics.FromImage(big))
        {
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
            g.DrawImage(src, 0, 0, size, size);
            var codec = ImageCodecInfo.GetImageEncoders().First(c => c.MimeType == "image/jpeg");
            var ps = new EncoderParameters(1);
            ps.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 88L);
            big.Save(jpg, codec, ps);
        }
        return "radar " + size + "px -> " + jpg;
    }

    // Mascara de tierra: celda de 50 m con al menos un 12 % de pixeles que no son agua.
    // El agua del radar es un azul casi uniforme; se toma de la esquina sureste (mar abierto).
    public static bool[] LandMask(string png, out string report)
    {
        var land = new bool[CELLS * CELLS];
        using (var bmp = new Bitmap(png))
        {
            Color water = bmp.GetPixel(bmp.Width - 4, bmp.Height - 4);
            double px = bmp.Width / (double)CELLS;
            int count = 0;
            for (int cy = 0; cy < CELLS; cy++)
                for (int cx = 0; cx < CELLS; cx++)
                {
                    int total = 0, dry = 0;
                    for (int y = (int)(cy * px); y < (int)((cy + 1) * px); y++)
                        for (int x = (int)(cx * px); x < (int)((cx + 1) * px); x++)
                        {
                            Color c = bmp.GetPixel(x, y);
                            int d = Math.Abs(c.R - water.R) + Math.Abs(c.G - water.G) + Math.Abs(c.B - water.B);
                            total++;
                            if (d > 40) dry++;
                        }
                    // fila 0 = norte (y = +3000)
                    bool isLand = total > 0 && dry >= total * 0.12;
                    land[cy * CELLS + cx] = isLand;
                    if (isLand) count++;
                }
            report = string.Format("agua RGB({0},{1},{2}); celdas de tierra {3}/{4}", water.R, water.G, water.B, count, CELLS * CELLS);
        }
        return land;
    }

    // ------------------------------------------------------------------ Calles
    class PNode { public float X, Y, Z; public uint Flags; public int LinkStart; public int Global = -1; public bool Veh; }
    class Navi { public float DirX, DirY; public uint Flags; }
    class Area
    {
        public PNode[] Nodes; public Navi[] Navis; public int[] LinkArea; public int[] LinkNode; public ushort[] NaviLink;
        public int NumVeh;
    }

    static Area[] LoadAreas(string pathsDir)
    {
        var areas = new Area[64];
        for (int a = 0; a < 64; a++)
        {
            string f = Path.Combine(pathsDir, "NODES" + a + ".DAT");
            if (!File.Exists(f)) continue;
            using (var br = new BinaryReader(File.OpenRead(f)))
            {
                int numNodes = br.ReadInt32(), numVeh = br.ReadInt32(); br.ReadInt32();
                int numNavi = br.ReadInt32(), numLinks = br.ReadInt32();
                var ar = new Area { NumVeh = numVeh, Nodes = new PNode[numNodes], Navis = new Navi[numNavi],
                    LinkArea = new int[numLinks], LinkNode = new int[numLinks], NaviLink = new ushort[numLinks] };
                for (int i = 0; i < numNodes; i++)
                {
                    br.ReadUInt32(); br.ReadUInt32();
                    var n = new PNode();
                    n.X = br.ReadInt16() / 8f; n.Y = br.ReadInt16() / 8f; n.Z = br.ReadInt16() / 8f;
                    br.ReadInt16();
                    n.LinkStart = br.ReadUInt16();
                    br.ReadUInt16(); br.ReadUInt16(); br.ReadByte(); br.ReadByte();
                    n.Flags = br.ReadUInt32();
                    n.Veh = i < numVeh;
                    ar.Nodes[i] = n;
                }
                for (int i = 0; i < numNavi; i++)
                {
                    br.ReadInt16(); br.ReadInt16(); br.ReadUInt16(); br.ReadUInt16();
                    var nv = new Navi();
                    nv.DirX = br.ReadSByte() / 100f; nv.DirY = br.ReadSByte() / 100f;
                    nv.Flags = br.ReadUInt32();
                    ar.Navis[i] = nv;
                }
                for (int i = 0; i < numLinks; i++) { ar.LinkArea[i] = br.ReadUInt16(); ar.LinkNode[i] = br.ReadUInt16(); }
                br.ReadBytes(768);
                for (int i = 0; i < numLinks; i++) ar.NaviLink[i] = br.ReadUInt16();
                areas[a] = ar;
            }
        }
        return areas;
    }

    // Sentido: el navi node de un tramo trae direccion y carriles a izquierda/derecha.
    // flip invierte la convencion; se elige sola comprobando que se circula por la derecha.
    static void Lanes(Area[] areas, Area ar, int link, PNode a, PNode b, bool flip, out int fwd, out int back)
    {
        fwd = back = 1;
        int nl = ar.NaviLink[link];
        int na = nl >> 10, ni = nl & 0x3FF;
        if (na >= 64 || areas[na] == null || ni >= areas[na].Navis.Length) return;
        var nv = areas[na].Navis[ni];
        int left = (int)((nv.Flags >> 8) & 7), right = (int)((nv.Flags >> 11) & 7);
        if (left == 0 && right == 0) return;
        double dot = (b.X - a.X) * nv.DirX + (b.Y - a.Y) * nv.DirY;
        bool along = dot >= 0;
        if (flip) along = !along;
        fwd = along ? right : left;
        back = along ? left : right;
    }

    public static string Roads(string pathsDir, string luaOut, string jsOut, out List<float[]> allNodes)
    {
        var log = new StringBuilder();
        var areas = LoadAreas(pathsDir);
        allNodes = new List<float[]>();
        var veh = new List<PNode>();
        foreach (var ar in areas)
        {
            if (ar == null) continue;
            foreach (var n in ar.Nodes)
            {
                allNodes.Add(new[] { n.X, n.Y, n.Z });
                if (n.Veh && (n.Flags & 0x80) == 0) { n.Global = veh.Count; veh.Add(n); }   // bit 7 = barcos
            }
        }

        // Elegir la convencion de sentido: en las autopistas de doble calzada la calzada contraria
        // queda a la izquierda (se circula por la derecha).
        bool flip = false;
        for (int pass = 0; pass < 2; pass++)
        {
            var oneWay = new List<double[]>(); // mx, my, dx, dy
            ForEachEdge(areas, pass == 1, (ar, link, a, b, fwd, back) =>
            {
                if ((fwd > 0) == (back > 0)) return;
                double dx = b.X - a.X, dy = b.Y - a.Y, len = Math.Sqrt(dx * dx + dy * dy);
                if (len < 1) return;
                if (back > 0) { dx = -dx; dy = -dy; }
                oneWay.Add(new[] { (a.X + b.X) / 2.0, (a.Y + b.Y) / 2.0, dx / len, dy / len });
            });
            var grid = new Dictionary<long, List<int>>();
            for (int i = 0; i < oneWay.Count; i++)
            {
                long k = Key(oneWay[i][0], oneWay[i][1], 40);
                List<int> l; if (!grid.TryGetValue(k, out l)) grid[k] = l = new List<int>(); l.Add(i);
            }
            int leftCount = 0, rightCount = 0;
            for (int i = 0; i < oneWay.Count; i++)
            {
                var e = oneWay[i];
                double best = 40; int bj = -1;
                for (int gx = -1; gx <= 1; gx++) for (int gy = -1; gy <= 1; gy++)
                {
                    List<int> l; if (!grid.TryGetValue(Key(e[0] + gx * 40, e[1] + gy * 40, 40), out l)) continue;
                    foreach (int j in l)
                    {
                        var o = oneWay[j];
                        if (e[2] * o[2] + e[3] * o[3] > -0.8) continue;
                        double d = Math.Sqrt((o[0] - e[0]) * (o[0] - e[0]) + (o[1] - e[1]) * (o[1] - e[1]));
                        if (d > 4 && d < best) { best = d; bj = j; }
                    }
                }
                if (bj < 0) continue;
                var p = oneWay[bj];
                double cross = e[2] * (p[1] - e[1]) - e[3] * (p[0] - e[0]);
                if (cross > 0) leftCount++; else rightCount++;
            }
            log.AppendLine(string.Format("convencion {0}: calzada contraria a la izquierda {1}, a la derecha {2}", pass, leftCount, rightCount));
            if (pass == 0) flip = rightCount > leftCount;
            if (pass == 0 && !flip) break;
        }
        log.AppendLine("sentido invertido: " + flip);

        // Aristas dirigidas permitidas para coches + aristas unicas para dibujar
        var outs = new List<int>[veh.Count];
        for (int i = 0; i < veh.Count; i++) outs[i] = new List<int>();
        var drawn = new HashSet<long>();
        var segs = new List<int>();
        int oneWays = 0;
        ForEachEdge(areas, flip, (ar, link, a, b, fwd, back) =>
        {
            if (a.Global < 0 || b.Global < 0) return;
            if (fwd > 0 && !outs[a.Global].Contains(b.Global)) outs[a.Global].Add(b.Global);
            long key = a.Global < b.Global ? ((long)a.Global << 20) | (uint)b.Global : ((long)b.Global << 20) | (uint)a.Global;
            if (drawn.Add(key))
            {
                // tipo: 1 autopista (bit 13 de las banderas del nodo; el 12 es "no autopista"), 0 calle; +2 si es de un solo sentido
                int t = ((a.Flags >> 13) & 1) == 1 && ((b.Flags >> 13) & 1) == 1 ? 1 : 0;
                if ((fwd > 0) != (back > 0)) { t += 2; oneWays++; }
                segs.Add(a.Global); segs.Add(b.Global); segs.Add(t);
            }
        });
        log.AppendLine(string.Format("nodos de calle {0}, tramos {1} ({2} de un sentido)", veh.Count, segs.Count / 3, oneWays));

        var lua = new StringBuilder();
        lua.AppendLine("--[[ rp_map / client/c_roads.lua (GENERADO por tools/generar-datos.ps1 desde data/Paths/NODES*.DAT; no editar)");
        lua.AppendLine("    ROAD_XYZ: x, y, z del nodo i en 3i-2..3i. ROAD_OUT[i]: nodos a los que un coche puede ir desde i (respeta el sentido). ]]");
        lua.Append("ROAD_XYZ = {");
        for (int i = 0; i < veh.Count; i++)
        {
            if (i > 0) lua.Append(i % 40 == 0 ? ",\n" : ",");
            lua.Append(F1(veh[i].X)).Append(',').Append(F1(veh[i].Y)).Append(',').Append(F1(veh[i].Z));
        }
        lua.AppendLine("}");
        lua.Append("ROAD_OUT = {");
        for (int i = 0; i < veh.Count; i++)
        {
            if (i > 0) lua.Append(i % 60 == 0 ? ",\n" : ",");
            lua.Append('{').Append(string.Join(",", outs[i].Select(j => (j + 1).ToString(IC)))).Append('}');
        }
        lua.AppendLine("}");
        File.WriteAllText(luaOut, lua.ToString(), new UTF8Encoding(false));

        var js = new StringBuilder();
        js.AppendLine("/* rp_map: red de calles de GTA SA (GENERADO por tools/generar-datos.ps1; no editar). n = x,y por nodo; s = a,b,tipo por tramo (1 autopista, +2 un sentido) */");
        js.Append("window.MAP_ROADS={n:[");
        for (int i = 0; i < veh.Count; i++) { if (i > 0) js.Append(','); js.Append(F1(veh[i].X)).Append(',').Append(F1(veh[i].Y)); }
        js.Append("],s:[").Append(string.Join(",", segs.Select(v => v.ToString(IC)))).AppendLine("]};");
        File.WriteAllText(jsOut, js.ToString(), new UTF8Encoding(false));
        return log.ToString();
    }

    // ------------------------------------------------------------------ Red de rp_citizens
    // Genera rp_citizens/c_nodes_veh.lua y c_nodes_ped.lua con TODO San Andreas. Los nodos que ya existian
    // (archivos "prev": la red anterior) conservan su indice, porque el editor /nodos guarda cambios en SQL
    // por indice; el resto se anade detras. Convenciones (reproducen exactamente la red de LS original):
    //   - viales: sin barcos (bit 7) ni solo emergencias (bit 8); peatonales: todos
    //   - barcos (c_nodes_boat.lua): solo los viales con el bit 7, sin carriles ni semaforos
    //   - enlaces ordenados de menor a mayor; solo hacia nodos incluidos
    //   - carriles i->k: derechos del navi node si el tramo va en su direccion, izquierdos si no
    //   - offset (CCarPathLink de gta-reversed, carril de 5 m, carril mas a la derecha): sin carriles 2.5
    //     (0 si el tramo no tiene ninguno); sentido unico 2.5*(n-1); doble sentido 2.5 + ancho/16 + 5*(n-1)
    //   - semaforo: bits 16-17 de las banderas del navi node
    static string R1(double v) { return Math.Round(v, 1, MidpointRounding.AwayFromZero).ToString(IC); }

    static float[] LuaFlat(string src, string name)
    {
        int i = src.IndexOf("\n" + name + " = {", StringComparison.Ordinal);
        if (i < 0) return null;
        i = src.IndexOf('{', i) + 1;
        int j = src.IndexOf('}', i);
        return src.Substring(i, j - i).Split(new[] { ',', '\n', '\r', ' ' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(s => float.Parse(s, IC)).ToArray();
    }

    public static string CitizenNodes(string pathsDir, string[] prevFiles, string outDir)
    {
        var log = new StringBuilder();
        var areas = LoadAreas(pathsDir);
        string prevSrc = "\n" + string.Join("\n", prevFiles.Where(File.Exists).Select(f => File.ReadAllText(f).Replace("\r\n", "\n")));
        var sets = new[] { new { Name = "VEH", Veh = true, Boat = false }, new { Name = "PED", Veh = false, Boat = false },
            new { Name = "BOAT", Veh = true, Boat = true } };
        foreach (var set in sets)
        {
            // Nodos incluidos: (area, nodo) -> indice Lua
            var order = new List<int[]>();
            var idx = new Dictionary<long, int>();
            Func<int, int, long> key = (a, n) => ((long)a << 16) | (uint)n;
            Func<PNode, bool> included = n => n.Veh == set.Veh &&
                (set.Boat ? (n.Flags & 0x80) != 0 : (!set.Veh || (n.Flags & 0x180) == 0));

            var prev = LuaFlat(prevSrc, set.Name + "_NODES");
            if (prev != null)
            {
                var grid = new Dictionary<long, List<int[]>>();
                for (int a = 0; a < 64; a++)
                {
                    if (areas[a] == null) continue;
                    for (int n = 0; n < areas[a].Nodes.Length; n++)
                    {
                        var p = areas[a].Nodes[n];
                        if (!included(p)) continue;
                        long k = Key(p.X, p.Y, 2);
                        List<int[]> l; if (!grid.TryGetValue(k, out l)) grid[k] = l = new List<int[]>(); l.Add(new[] { a, n });
                    }
                }
                for (int i = 0; i < prev.Length / 3; i++)
                {
                    float x = prev[i * 3], y = prev[i * 3 + 1], z = prev[i * 3 + 2];
                    int[] best = null; double bd = 0.31;
                    for (int gx = -1; gx <= 1; gx++) for (int gy = -1; gy <= 1; gy++)
                    {
                        List<int[]> l; if (!grid.TryGetValue(Key(x + gx * 2, y + gy * 2, 2), out l)) continue;
                        foreach (var c in l)
                        {
                            var p = areas[c[0]].Nodes[c[1]];
                            double d = Math.Abs(p.X - x) + Math.Abs(p.Y - y) + Math.Abs(p.Z - z);
                            if (d < bd && !idx.ContainsKey(key(c[0], c[1]))) { bd = d; best = c; }
                        }
                    }
                    if (best == null) throw new Exception(string.Format("{0}: el nodo {1} de la red anterior no esta en los .DAT; no se regenera para no romper los indices de path_nodes", set.Name, i + 1));
                    idx[key(best[0], best[1])] = order.Count + 1;
                    order.Add(best);
                }
            }
            int prevCount = order.Count;
            for (int a = 0; a < 64; a++)
            {
                if (areas[a] == null) continue;
                for (int n = 0; n < areas[a].Nodes.Length; n++)
                {
                    if (!included(areas[a].Nodes[n]) || idx.ContainsKey(key(a, n))) continue;
                    idx[key(a, n)] = order.Count + 1;
                    order.Add(new[] { a, n });
                }
            }

            var nodes = new StringBuilder(); var links = new StringBuilder();
            var lanes = new StringBuilder(); var offs = new StringBuilder(); var lights = new StringBuilder();
            int edges = 0;
            for (int i = 0; i < order.Count; i++)
            {
                var ar = areas[order[i][0]]; var p = ar.Nodes[order[i][1]];
                string sep = i == 0 ? "" : (i % 40 == 0 ? ",\n" : ",");
                nodes.Append(sep).Append(R1(p.X)).Append(',').Append(R1(p.Y)).Append(',').Append(R1(p.Z));
                var outs = new List<int[]>();   // destino, carriles, offset*10, semaforo
                for (int k = 0; k < (int)(p.Flags & 0xF); k++)
                {
                    int link = p.LinkStart + k;
                    if (link >= ar.LinkArea.Length) break;
                    int ba = ar.LinkArea[link], bn = ar.LinkNode[link], t;
                    if (ba >= 64 || areas[ba] == null || !idx.TryGetValue(key(ba, bn), out t)) continue;
                    int ln = 1, off = 25, light = 0;   // sin navi node: doble sentido de 1 carril
                    if (set.Veh && !set.Boat)
                    {
                        var b = areas[ba].Nodes[bn];
                        int nl = ar.NaviLink[link], na = nl >> 10, ni = nl & 0x3FF;
                        if (na < 64 && areas[na] != null && ni < areas[na].Navis.Length)
                        {
                            var nv = areas[na].Navis[ni];
                            int left = (int)((nv.Flags >> 8) & 7), right = (int)((nv.Flags >> 11) & 7), width = (int)(nv.Flags & 0xFF);
                            bool along = (b.X - p.X) * nv.DirX + (b.Y - p.Y) * nv.DirY >= 0;
                            ln = along ? right : left;
                            int other = along ? left : right;
                            double o = ln == 0 ? (left + right == 0 ? 0 : 2.5) : other == 0 ? 2.5 * (ln - 1) : 2.5 + width / 16.0 + 5 * (ln - 1);
                            off = (int)Math.Round(o * 10, MidpointRounding.AwayFromZero);
                            light = (int)((nv.Flags >> 16) & 3);
                        }
                    }
                    if (!outs.Any(o => o[0] == t)) outs.Add(new[] { t, ln, off, light });   // el .DAT repite algun enlace
                }
                outs.Sort((u, v) => u[0].CompareTo(v[0]));
                edges += outs.Count;
                sep = i == 0 ? "" : (i % 60 == 0 ? ",\n" : ",");
                links.Append(sep).Append('{').Append(string.Join(",", outs.Select(o => o[0].ToString(IC)))).Append('}');
                lanes.Append(sep).Append('{').Append(string.Join(",", outs.Select(o => o[1].ToString(IC)))).Append('}');
                offs.Append(sep).Append('{').Append(string.Join(",", outs.Select(o => (o[2] / 10.0).ToString(IC)))).Append('}');
                lights.Append(sep).Append('{').Append(string.Join(",", outs.Select(o => o[3].ToString(IC)))).Append('}');
            }

            var lua = new StringBuilder();
            string file = set.Boat ? "c_nodes_boat.lua" : set.Veh ? "c_nodes_veh.lua" : "c_nodes_ped.lua";
            lua.AppendLine("--[[ rp_citizens / " + file + " (GENERADO por tools/generar-nodos.ps1 desde data/Paths/NODES*.DAT de GTA SA,");
            if (set.Boat)
            {
                lua.AppendLine("    todo San Andreas; no editar a mano: se regenera con el script)");
                lua.AppendLine("    BOAT_NODES: x, y, z planos (nodo i -> indices 3i-2..3i). BOAT_LINKS[i]: vecinos del nodo i.");
                lua.AppendLine("    Rutas de los barcos ambientales (bit 7 de los nodos viales del juego), ver c_boats.lua. ]]");
                lua.Append("BOAT_NODES = {").Append(nodes).AppendLine("}");
                lua.Append("BOAT_LINKS = {").Append(links).AppendLine("}");
            }
            else if (set.Veh)
            {
                lua.AppendLine("    todo San Andreas; no editar a mano: usa el editor /nodos, que guarda los cambios en SQL)");
                lua.AppendLine("    VEH_NODES: x, y, z planos (nodo i -> indices 3i-2..3i). VEH_LINKS[i]: vecinos del nodo i.");
                lua.AppendLine("    VEH_LANES[i][k]: carriles en sentido i -> VEH_LINKS[i][k] (0 = prohibido, sentido unico).");
                lua.AppendLine("    VEH_OFFSET[i][k]: metros a la derecha de la linea central para ese sentido.");
                lua.AppendLine("    VEH_LIGHT[i][k]: 1/2 si el tramo i -> k termina en un semaforo (0 = sin semaforo). ]]");
                lua.Append("VEH_NODES = {").Append(nodes).AppendLine("}");
                lua.Append("VEH_LINKS = {").Append(links).AppendLine("}");
                lua.Append("VEH_LANES = {").Append(lanes).AppendLine("}");
                lua.Append("VEH_OFFSET = {").Append(offs).AppendLine("}");
                lua.Append("VEH_LIGHT = {").Append(lights).AppendLine("}");
            }
            else
            {
                lua.AppendLine("    todo San Andreas; no editar a mano: usa el editor /nodos, que guarda los cambios en SQL)");
                lua.AppendLine("    PED_NODES: x, y, z planos (nodo i -> indices 3i-2..3i). PED_LINKS[i]: vecinos del nodo i. ]]");
                lua.Append("PED_NODES = {").Append(nodes).AppendLine("}");
                lua.Append("PED_LINKS = {").Append(links).AppendLine("}");
            }
            File.WriteAllText(Path.Combine(outDir, file), lua.ToString(), new UTF8Encoding(false));
            log.AppendLine(string.Format("{0}: {1} nodos ({2} de la red anterior, {3} nuevos), {4} enlaces dirigidos -> {5}",
                set.Name, order.Count, prevCount, order.Count - prevCount, edges, file));
        }
        return log.ToString();
    }

    delegate void EdgeFn(Area ar, int link, PNode a, PNode b, int fwd, int back);

    static void ForEachEdge(Area[] areas, bool flip, EdgeFn fn)
    {
        foreach (var ar in areas)
        {
            if (ar == null) continue;
            for (int i = 0; i < ar.NumVeh; i++)
            {
                var a = ar.Nodes[i];
                if ((a.Flags & 0x80) != 0) continue;
                int count = (int)(a.Flags & 0xF);
                for (int k = 0; k < count; k++)
                {
                    int link = a.LinkStart + k;
                    if (link >= ar.LinkArea.Length) break;
                    int ba = ar.LinkArea[link], bn = ar.LinkNode[link];
                    if (ba >= 64 || areas[ba] == null || bn >= areas[ba].NumVeh) continue;
                    var b = areas[ba].Nodes[bn];
                    if ((b.Flags & 0x80) != 0) continue;
                    int fwd, back;
                    Lanes(areas, ar, link, a, b, flip, out fwd, out back);
                    fn(ar, link, a, b, fwd, back);
                }
            }
        }
    }

    static long Key(double x, double y, double size)
    {
        return ((long)Math.Floor(x / size) + 1000) * 100000 + ((long)Math.Floor(y / size) + 1000);
    }

    // ------------------------------------------------------------------ Edificios
    class Inst { public int Id; public string Name; public float X, Y, Z, QX, QY, QZ, QW; public int Interior; }

    static readonly string[] SKIP = {
        "lod", "road", "land", "grass", "beach", "hill", "rock", "cliff", "sea", "water", "bridge", "tunnel",
        "fence", "wall", "tree", "veg", "bush", "plant", "pier", "jetty", "dock", "rail", "track", "trck",
        "path", "pave", "kerb", "curb", "ground", "grnd", "field", "dirt", "sand", "mount", "mntn", "desert",
        "dam", "barrier", "sign", "lamp", "light", "pylon", "pole", "wire", "cable", "fwy", "freeway", "hiway",
        "slip", "junct", "jnct", "xing", "crossing", "drain", "canal", "river", "lake", "gras", "grss", "terrain",
        "carpark", "cpark", "park", "golf", "pool", "court", "pitch", "runway", "tarmac", "apron", "taxiway",
        "sidewalk", "stair", "steps", "ramp", "_dirt", "scrub",
    };

    static bool Skipped(string name)
    {
        string n = name.ToLowerInvariant();
        foreach (var s in SKIP) if (n.Contains(s)) return true;
        return false;
    }

    public static string Buildings(string gta, string jsOut, string terrainOut, List<float[]> allNodes, bool[] land)
    {
        var log = new StringBuilder();
        string dat = Path.Combine(gta, "data", "gta.dat");
        var ideFiles = new List<string>(); var iplFiles = new List<string>();
        foreach (var raw in File.ReadAllLines(dat))
        {
            string l = raw.Trim();
            if (l.StartsWith("IDE ", StringComparison.OrdinalIgnoreCase)) ideFiles.Add(Path.Combine(gta, l.Substring(4).Trim()));
            else if (l.StartsWith("IPL ", StringComparison.OrdinalIgnoreCase) && !l.ToUpperInvariant().EndsWith(".ZON")) iplFiles.Add(Path.Combine(gta, l.Substring(4).Trim()));
        }

        // IDE: id -> nombre del modelo
        var names = new Dictionary<int, string>();
        foreach (var f in ideFiles)
        {
            if (!File.Exists(f)) continue;
            string section = "";
            foreach (var raw in File.ReadAllLines(f))
            {
                string l = raw.Trim();
                if (l.Length == 0 || l.StartsWith("#")) continue;
                if (l == "end") { section = ""; continue; }
                if (!char.IsDigit(l[0])) { section = l.ToLowerInvariant(); continue; }
                if (section != "objs" && section != "tobj" && section != "anim") continue;
                var p = l.Split(',');
                int id; if (p.Length > 1 && int.TryParse(p[0].Trim(), out id)) names[id] = p[1].Trim();
            }
        }

        string imgPath = Path.Combine(gta, "models", "gta3.img");
        var bounds = new Dictionary<string, float[]>(StringComparer.OrdinalIgnoreCase);
        var insts = new List<Inst>();
        using (var br = new BinaryReader(File.OpenRead(imgPath)))
        {
            var entries = ReadImg(br);
            foreach (var e in entries)
            {
                string lower = e.Name.ToLowerInvariant();
                if (lower.EndsWith(".col")) ReadCol(ReadEntry(br, e), bounds);
                else if (lower.EndsWith(".ipl"))
                {
                    var d = ReadEntry(br, e);
                    if (Encoding.ASCII.GetString(d, 0, 4) != "bnry") continue;
                    uint ni = BitConverter.ToUInt32(d, 4), io = BitConverter.ToUInt32(d, 28);
                    for (int k = 0; k < ni; k++)
                    {
                        int o = (int)io + k * 40;
                        var it = new Inst
                        {
                            X = BitConverter.ToSingle(d, o), Y = BitConverter.ToSingle(d, o + 4), Z = BitConverter.ToSingle(d, o + 8),
                            QX = BitConverter.ToSingle(d, o + 12), QY = BitConverter.ToSingle(d, o + 16), QZ = BitConverter.ToSingle(d, o + 20), QW = BitConverter.ToSingle(d, o + 24),
                            Id = BitConverter.ToInt32(d, o + 28), Interior = BitConverter.ToInt32(d, o + 32),
                        };
                        insts.Add(it);
                    }
                }
            }
        }
        foreach (var f in iplFiles)
        {
            if (!File.Exists(f)) continue;
            string section = "";
            foreach (var raw in File.ReadAllLines(f))
            {
                string l = raw.Trim();
                if (l.Length == 0 || l.StartsWith("#")) continue;
                if (l == "end") { section = ""; continue; }
                if (!char.IsDigit(l[0]) && !l.StartsWith("-")) { section = l.ToLowerInvariant(); continue; }
                if (section != "inst") continue;
                var p = l.Split(',');
                if (p.Length < 10) continue;
                insts.Add(new Inst
                {
                    Id = int.Parse(p[0].Trim(), IC), Name = p[1].Trim(), Interior = int.Parse(p[2].Trim(), IC),
                    X = float.Parse(p[3], IC), Y = float.Parse(p[4], IC), Z = float.Parse(p[5], IC),
                    QX = float.Parse(p[6], IC), QY = float.Parse(p[7], IC), QZ = float.Parse(p[8], IC), QW = float.Parse(p[9], IC),
                });
            }
        }
        log.AppendLine(string.Format("modelos IDE {0}, colisiones {1}, instancias {2}", names.Count, bounds.Count, insts.Count));

        // Relieve: altura media de los nodos (calles y aceras) por celda, rellenando huecos.
        int G = CELLS + 1;
        var hsum = new double[G * G]; var hcnt = new int[G * G];
        foreach (var n in allNodes)
        {
            int gx = (int)Math.Round((n[0] + 3000) / CELL), gy = (int)Math.Round((3000 - n[1]) / CELL);
            if (gx < 0 || gy < 0 || gx >= G || gy >= G) continue;
            hsum[gy * G + gx] += n[2]; hcnt[gy * G + gx]++;
        }

        var outB = new List<string>();
        var modelNames = new List<string>(); var modelIdx = new Dictionary<string, int>();
        int kept = 0, noCol = 0;
        foreach (var it in insts)
        {
            if (it.Interior != 0 && it.Interior != 13) continue;
            string name = it.Name;
            if (name == null && !names.TryGetValue(it.Id, out name)) continue;
            if (Skipped(name)) continue;
            float[] b;
            if (!bounds.TryGetValue(name, out b)) { noCol++; continue; }
            float sx = b[3] - b[0], sy = b[4] - b[1], sz = b[5] - b[2];
            if (sz < 4 || sx < 4 || sy < 4 || sx * sy < 30 || sx > 260 || sy > 260) continue;
            if (sx * sy > 25000) continue;
            if (Math.Abs(it.QX) > 0.05 || Math.Abs(it.QY) > 0.05) continue;   // inclinados: piezas de terreno
            double yaw = Math.Atan2(2 * (it.QW * it.QZ + it.QX * it.QY), 1 - 2 * (it.QY * it.QY + it.QZ * it.QZ));
            double lcx = (b[0] + b[3]) / 2, lcy = (b[1] + b[4]) / 2;
            double c = Math.Cos(yaw), s = Math.Sin(yaw);
            double cx = it.X + lcx * c - lcy * s, cy = it.Y + lcx * s + lcy * c;
            double baseZ = it.Z + b[2], topZ = it.Z + b[5];
            if (topZ < -5 || baseZ > 400) continue;
            int mi;
            string clean = name.ToLowerInvariant();
            if (!modelIdx.TryGetValue(clean, out mi)) { mi = modelNames.Count; modelIdx[clean] = mi; modelNames.Add(clean); }
            outB.Add(string.Format(IC, "{0},{1},{2},{3},{4},{5},{6},{7}", F1(cx), F1(cy), F1(sx / 2), F1(sy / 2),
                Math.Round(yaw, 3).ToString(IC), F1(baseZ), F1(topZ), mi));
            kept++;
            int ggx = (int)Math.Round((cx + 3000) / CELL), ggy = (int)Math.Round((3000 - cy) / CELL);
            if (ggx >= 0 && ggy >= 0 && ggx < G && ggy < G && baseZ > -20) { hsum[ggy * G + ggx] += Math.Max(baseZ, 0) ; hcnt[ggy * G + ggx]++; }
        }
        log.AppendLine(string.Format("edificios {0} (sin colision {1}), modelos {2}", kept, noCol, modelNames.Count));

        var js = new StringBuilder();
        js.AppendLine("/* rp_map: edificios de GTA SA (GENERADO por tools/generar-datos.ps1 desde IPL + COL; no editar).");
        js.AppendLine("   b = cx, cy, medio ancho X, medio ancho Y, giro (rad), z base, z techo, indice de modelo */");
        js.Append("window.MAP_BUILDINGS={m:[").Append(string.Join(",", modelNames.Select(n => "\"" + n + "\""))).Append("],b:[");
        js.Append(string.Join(",", outB)).AppendLine("]};");
        File.WriteAllText(jsOut, js.ToString(), new UTF8Encoding(false));

        // Relieve: celdas sin datos toman la media de sus vecinas con datos (varias pasadas); agua = 0
        var h = new double[G * G]; var known = new bool[G * G];
        for (int i = 0; i < G * G; i++) if (hcnt[i] > 0) { h[i] = hsum[i] / hcnt[i]; known[i] = true; }
        for (int pass = 0; pass < 40; pass++)
        {
            var nh = (double[])h.Clone(); var nk = (bool[])known.Clone();
            for (int y = 0; y < G; y++) for (int x = 0; x < G; x++)
            {
                int i = y * G + x; if (known[i]) continue;
                double sum = 0; int cnt = 0;
                for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++)
                {
                    int xx = x + dx, yy = y + dy; if (xx < 0 || yy < 0 || xx >= G || yy >= G) continue;
                    int j = yy * G + xx; if (known[j]) { sum += h[j]; cnt++; }
                }
                if (cnt > 0) { nh[i] = sum / cnt; nk[i] = true; }
            }
            h = nh; known = nk;
        }
        var th = new StringBuilder();
        th.AppendLine("/* rp_map: relieve aproximado (GENERADO; altura media de calles y edificios por vertice de 50 m, 121x121, fila 0 = norte). a = tierra por celda 120x120 */");
        th.Append("window.MAP_TERRAIN={size:" + G + ",h:[");
        for (int y = 0; y < G; y++) for (int x = 0; x < G; x++)
        {
            // vertice en agua si las 4 celdas que toca son agua
            bool wet = true;
            for (int dy = -1; dy <= 0; dy++) for (int dx = -1; dx <= 0; dx++)
            {
                int cx = x + dx, cy = y + dy;
                if (cx >= 0 && cy >= 0 && cx < CELLS && cy < CELLS && land[cy * CELLS + cx]) wet = false;
            }
            double v = wet ? -2 : Math.Max(0, h[y * G + x]);
            if (y + x > 0) th.Append(',');
            th.Append(((int)Math.Round(v)).ToString(IC));
        }
        th.Append("],a:\"");
        for (int i = 0; i < CELLS * CELLS; i++) th.Append(land[i] ? '1' : '0');
        th.AppendLine("\"};");
        File.WriteAllText(terrainOut, th.ToString(), new UTF8Encoding(false));
        return log.ToString();
    }

    // Archivo .col: varias entradas COLL/COL2/COL3/COL4 seguidas; de cada una se toma la caja (min, max).
    static void ReadCol(byte[] d, Dictionary<string, float[]> bounds)
    {
        int p = 0;
        while (p + 32 <= d.Length)
        {
            string four = Encoding.ASCII.GetString(d, p, 4);
            if (!four.StartsWith("COL")) break;
            uint size = BitConverter.ToUInt32(d, p + 4);
            string name = Encoding.ASCII.GetString(d, p + 8, 22).Split('\0')[0];
            int b = p + 32;
            if (b + 40 > d.Length) break;
            float[] box = new float[6];
            if (four == "COLL")
            {   // radio, centro(3), min(3), max(3)
                for (int i = 0; i < 6; i++) box[i] = BitConverter.ToSingle(d, b + 16 + i * 4);
            }
            else
            {   // min(3), max(3), centro(3), radio
                for (int i = 0; i < 6; i++) box[i] = BitConverter.ToSingle(d, b + i * 4);
            }
            if (name.Length > 0 && !bounds.ContainsKey(name)) bounds[name] = box;
            p += 8 + (int)size;
        }
    }

    public static string WriteLandLua(bool[] land, string luaOut)
    {
        var sb = new StringBuilder();
        sb.AppendLine("--[[ rp_map / shared/s_land.lua (GENERADO por tools/generar-datos.ps1 desde el radar; no editar)");
        sb.AppendLine("    MAP_LAND: una letra por celda de 50 m (120x120, fila 0 = norte): 1 tierra, 0 agua. ]]");
        sb.Append("MAP_LAND = \"");
        for (int i = 0; i < land.Length; i++) sb.Append(land[i] ? '1' : '0');
        sb.AppendLine("\"");
        File.WriteAllText(luaOut, sb.ToString(), new UTF8Encoding(false));
        return "mascara -> " + luaOut;
    }
}
