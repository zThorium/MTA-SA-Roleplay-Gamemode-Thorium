using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Drawing.Imaging;
using System.Collections.Generic;

// Extrae radar00..radar143.txd de gta3.img (GTA SA PC) y los une en un mapa.
public static class RadarExtract
{
    class Entry { public uint Offset; public uint Size; }

    public static string Run(string imgPath, string outPath, int tile)
    {
        var entries = new Dictionary<string, Entry>(StringComparer.OrdinalIgnoreCase);
        var log = new StringBuilder();
        using (var fs = File.OpenRead(imgPath))
        using (var br = new BinaryReader(fs))
        {
            br.ReadBytes(4);
            uint n = br.ReadUInt32();
            for (int i = 0; i < n; i++)
            {
                uint off = br.ReadUInt32();
                ushort s1 = br.ReadUInt16();
                ushort s2 = br.ReadUInt16();
                string name = Encoding.ASCII.GetString(br.ReadBytes(24)).Split('\0')[0];
                entries[name] = new Entry { Offset = off, Size = Math.Max(s1, s2) };
            }

            using (var map = new Bitmap(tile * 12, tile * 12, PixelFormat.Format32bppArgb))
            using (var g = Graphics.FromImage(map))
            {
                g.Clear(Color.FromArgb(255, 120, 150, 170));
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                for (int t = 0; t < 144; t++)
                {
                    string name = "radar" + t.ToString("00") + ".txd";
                    Entry e;
                    if (!entries.TryGetValue(name, out e)) { log.AppendLine("falta " + name); continue; }
                    fs.Position = (long)e.Offset * 2048;
                    byte[] data = br.ReadBytes((int)e.Size * 2048);
                    try
                    {
                        using (Bitmap bmp = DecodeFirstTexture(data))
                        {
                            if (bmp == null) { log.AppendLine("sin textura " + name); continue; }
                            g.DrawImage(bmp, (t % 12) * tile, (t / 12) * tile, tile, tile);
                        }
                    }
                    catch (Exception ex) { log.AppendLine(name + ": " + ex.Message); }
                }
                map.Save(outPath, ImageFormat.Png);
            }
        }
        return log.ToString();
    }

    // Recorre los chunks RenderWare hasta el primer Texture Native (0x15)
    static Bitmap DecodeFirstTexture(byte[] d)
    {
        int p = 0;
        // Texture Dictionary
        uint type = BitConverter.ToUInt32(d, p); p += 12;
        if (type != 0x16) return null;
        // Struct
        uint structSize = BitConverter.ToUInt32(d, p + 4); p += 12 + (int)structSize;
        // Texture Native
        type = BitConverter.ToUInt32(d, p); p += 12;
        if (type != 0x15) return null;
        // Struct de la textura
        p += 12;
        uint platform = BitConverter.ToUInt32(d, p); p += 4;
        p += 4;           // filtro + direccionamiento
        p += 32 + 32;     // nombre + mascara
        uint rasterFormat = BitConverter.ToUInt32(d, p); p += 4;
        uint d3dFormat = BitConverter.ToUInt32(d, p); p += 4;
        int w = BitConverter.ToUInt16(d, p); p += 2;
        int h = BitConverter.ToUInt16(d, p); p += 2;
        int depth = d[p]; p += 1;
        p += 1;           // niveles
        p += 1;           // raster type
        p += 1;           // flags
        if (platform != 9) throw new Exception("plataforma " + platform);

        uint[] palette = null;
        if ((rasterFormat & 0x2000) != 0 || (rasterFormat & 0x4000) != 0)
        {
            int count = (rasterFormat & 0x2000) != 0 ? 256 : 16;
            palette = new uint[count];
            for (int i = 0; i < count; i++) { palette[i] = BitConverter.ToUInt32(d, p); p += 4; }
        }
        int size = BitConverter.ToInt32(d, p); p += 4;

        var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        string fourcc = Encoding.ASCII.GetString(BitConverter.GetBytes(d3dFormat));
        if (fourcc == "DXT1") DecodeDxt1(d, p, w, h, bmp);
        else if (fourcc == "DXT3") DecodeDxt3(d, p, w, h, bmp);
        else if (palette != null)
        {
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
            {
                uint c = palette[d[p + y * w + x]]; // RGBA
                bmp.SetPixel(x, y, Color.FromArgb(255, (int)(c & 0xFF), (int)((c >> 8) & 0xFF), (int)((c >> 16) & 0xFF)));
            }
        }
        else if (depth == 32)
        {
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
            {
                int o = p + (y * w + x) * 4; // BGRA
                bmp.SetPixel(x, y, Color.FromArgb(255, d[o + 2], d[o + 1], d[o]));
            }
        }
        else if (depth == 16)
        {
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
                bmp.SetPixel(x, y, C565(BitConverter.ToUInt16(d, p + (y * w + x) * 2)));
        }
        else throw new Exception("formato no soportado " + fourcc + " depth " + depth);
        return bmp;
    }

    static Color C565(ushort c)
    {
        int r = (c >> 11) & 31, g = (c >> 5) & 63, b = c & 31;
        return Color.FromArgb(255, r * 255 / 31, g * 255 / 63, b * 255 / 31);
    }

    static void DecodeBlockColors(byte[] d, int o, Color[] pal, bool dxt1)
    {
        ushort c0 = BitConverter.ToUInt16(d, o), c1 = BitConverter.ToUInt16(d, o + 2);
        pal[0] = C565(c0); pal[1] = C565(c1);
        if (!dxt1 || c0 > c1)
        {
            pal[2] = Color.FromArgb(255, (2 * pal[0].R + pal[1].R) / 3, (2 * pal[0].G + pal[1].G) / 3, (2 * pal[0].B + pal[1].B) / 3);
            pal[3] = Color.FromArgb(255, (pal[0].R + 2 * pal[1].R) / 3, (pal[0].G + 2 * pal[1].G) / 3, (pal[0].B + 2 * pal[1].B) / 3);
        }
        else
        {
            pal[2] = Color.FromArgb(255, (pal[0].R + pal[1].R) / 2, (pal[0].G + pal[1].G) / 2, (pal[0].B + pal[1].B) / 2);
            pal[3] = Color.FromArgb(255, 0, 0, 0);
        }
    }

    static void DecodeDxt1(byte[] d, int p, int w, int h, Bitmap bmp)
    {
        var pal = new Color[4];
        for (int by = 0; by < h; by += 4) for (int bx = 0; bx < w; bx += 4)
        {
            DecodeBlockColors(d, p, pal, true);
            uint bits = BitConverter.ToUInt32(d, p + 4);
            for (int i = 0; i < 16; i++)
            {
                int x = bx + i % 4, y = by + i / 4;
                if (x < w && y < h) bmp.SetPixel(x, y, pal[(bits >> (2 * i)) & 3]);
            }
            p += 8;
        }
    }

    static void DecodeDxt3(byte[] d, int p, int w, int h, Bitmap bmp)
    {
        var pal = new Color[4];
        for (int by = 0; by < h; by += 4) for (int bx = 0; bx < w; bx += 4)
        {
            DecodeBlockColors(d, p + 8, pal, false);
            uint bits = BitConverter.ToUInt32(d, p + 12);
            for (int i = 0; i < 16; i++)
            {
                int x = bx + i % 4, y = by + i / 4;
                if (x < w && y < h) bmp.SetPixel(x, y, pal[(bits >> (2 * i)) & 3]);
            }
            p += 16;
        }
    }
}
