using System;
using System.Collections.Generic;

public class PatchRefusal : Exception { public PatchRefusal(string m) : base(m) { } }

public class PeSection { public int HdrOff; public string Name; public uint VS, VA, RS, Raw; }

public class AbsRef { public long Va; public AbsRef(long v) { Va = v; } }
public class RelRef { public long Target; public RelRef(long t) { Target = t; } }

public static class SpellbookPatcher
{
    const long BASE = 0x400000;
    const int SEC_VS = 0x2000, CAVE_RAW = 0x200, BG_OFF = 0x200;
    const int BG_BYTES = 1440 * 4, FLAG_OFF = BG_OFF + BG_BYTES;
    const long ORIG_READ = 0x57b600;

    static uint U32(byte[] b, int o) { return (uint)(b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)); }
    static ushort U16(byte[] b, int o) { return (ushort)(b[o] | (b[o + 1] << 8)); }
    static void W32(byte[] b, int o, uint v) { b[o] = (byte)v; b[o + 1] = (byte)(v >> 8); b[o + 2] = (byte)(v >> 16); b[o + 3] = (byte)(v >> 24); }
    static void W16(byte[] b, int o, ushort v) { b[o] = (byte)v; b[o + 1] = (byte)(v >> 8); }

    static byte[] Hex(string s)
    {
        byte[] r = new byte[s.Length / 2];
        for (int i = 0; i < r.Length; i++) r[i] = Convert.ToByte(s.Substring(i * 2, 2), 16);
        return r;
    }
    static byte[] Rel32(long from, long to)
    {
        uint v = unchecked((uint)(to - from));
        return new byte[] { (byte)v, (byte)(v >> 8), (byte)(v >> 16), (byte)(v >> 24) };
    }
    static bool SameAt(byte[] buf, int off, byte[] want)
    {
        if (off < 0 || off + want.Length > buf.Length) return false;
        for (int i = 0; i < want.Length; i++) if (buf[off + i] != want[i]) return false;
        return true;
    }

    class Pe
    {
        public int Peo, NSec, OptSz, Opt, SecTab;
        public List<PeSection> Sec = new List<PeSection>();
        public PeSection Text, Reloc;
    }

    static Pe Parse(byte[] buf)
    {
        if (buf.Length < 0x400 || buf[0] != 'M' || buf[1] != 'Z') throw new PatchRefusal("This is not a Windows program file.");
        Pe p = new Pe();
        p.Peo = (int)U32(buf, 0x3c);
        if (p.Peo < 0 || p.Peo + 24 > buf.Length || buf[p.Peo] != 'P' || buf[p.Peo + 1] != 'E') throw new PatchRefusal("This is not a Windows program file.");
        p.NSec = U16(buf, p.Peo + 6);
        p.OptSz = U16(buf, p.Peo + 20);
        p.Opt = p.Peo + 24;
        p.SecTab = p.Opt + p.OptSz;
        for (int i = 0; i < p.NSec; i++)
        {
            int o = p.SecTab + i * 40;
            PeSection s = new PeSection();
            s.HdrOff = o;
            s.Name = System.Text.Encoding.ASCII.GetString(buf, o, 8).Replace("\0", "");
            s.VS = U32(buf, o + 8); s.VA = U32(buf, o + 12); s.RS = U32(buf, o + 16); s.Raw = U32(buf, o + 20);
            p.Sec.Add(s);
            if (s.Name == ".text") p.Text = s;
            if (s.Name == ".reloc") p.Reloc = s;
        }
        if (p.Text == null || p.Reloc == null) throw new PatchRefusal("This does not look like the RoF2 eqgame.exe (missing code sections).");
        return p;
    }

    public static bool HasLaa(byte[] buf) { Pe p = Parse(buf); return (U16(buf, p.Peo + 22) & 0x20) != 0; }
    public static bool HasSpellbookSection(byte[] buf)
    {
        Pe p = Parse(buf);
        foreach (PeSection s in p.Sec) if (s.Name == ".sbook") return true;
        return false;
    }

    class Cave
    {
        public byte[] Data = new byte[CAVE_RAW];
        public List<int> Relocs = new List<int>();
        public long NewRva;
        public Cave(long rva) { NewRva = rva; for (int i = 0; i < Data.Length; i++) Data[i] = 0xCC; }
        long Abs(int off) { return BASE + NewRva + off; }
        public int Emit(int off, object[] parts)
        {
            int p = off;
            foreach (object x in parts)
            {
                if (x is string) { byte[] b = Hex((string)x); Array.Copy(b, 0, Data, p, b.Length); p += b.Length; }
                else if (x is AbsRef)
                {
                    uint v = unchecked((uint)((AbsRef)x).Va);
                    W32(Data, p, v); Relocs.Add(p); p += 4;
                }
                else
                {
                    byte[] b = Rel32(Abs(p) + 4, ((RelRef)x).Target);
                    Array.Copy(b, 0, Data, p, 4); p += 4;
                }
            }
            return p;
        }
    }

    // vas/expects/replaces: the patch table. Returns the patched file bytes. Throws PatchRefusal if anything is off.
    public static byte[] Build(byte[] buf, string[] vas, string[] expects, string[] replaces, bool setLaa)
    {
        Pe pe = Parse(buf);
        if (HasSpellbookSection(buf)) throw new PatchRefusal("This exe already has the spellbook patch (it has a .sbook section).");

        Func<long, int> va2off = delegate (long va)
        {
            long r = va - BASE;
            if (r < pe.Text.VA || r >= (long)pe.Text.VA + pe.Text.RS) throw new PatchRefusal("Internal error: address outside the code section.");
            return (int)(r - pe.Text.VA + pe.Text.Raw);
        };

        byte[] outb = (byte[])buf.Clone();

        // ---- 1. check EVERYTHING first, then change
        int bad = 0; string firstBad = "";
        for (int i = 0; i < vas.Length; i++)
        {
            long va = Convert.ToInt64(vas[i], 16);
            if (!SameAt(buf, va2off(va), Hex(expects[i]))) { bad++; if (firstBad == "") firstBad = vas[i]; }
        }
        if (bad > 0)
            throw new PatchRefusal(bad + " of " + vas.Length + " spots (first at " + firstBad + ") do not hold what this patch expects. This is not the RoF2 eqgame.exe the patch was made for, or it has other changes in the same places.");

        long site1 = 0x57cbd1, site2 = 0x578fd6;
        byte[] exp1 = Hex("68d0020000" + "8d97bc1a0000" + "52" + "8bce" + "e8");
        byte[] tail1 = Rel32(0x57cbe4, ORIG_READ);
        byte[] exp1all = new byte[exp1.Length + 4];
        Array.Copy(exp1, exp1all, exp1.Length); Array.Copy(tail1, 0, exp1all, exp1.Length, 4);
        if (!SameAt(buf, va2off(site1), exp1all)) throw new PatchRefusal("The profile-reading code is not what this patch expects (hook 1).");
        if (!SameAt(buf, va2off(site2), Hex("8bbcb3bc1a0000"))) throw new PatchRefusal("The spellbook copy code is not what this patch expects (hook 2).");

        for (int i = 0; i < vas.Length; i++)
        {
            long va = Convert.ToInt64(vas[i], 16);
            byte[] r = Hex(replaces[i]);
            if (r.Length != Hex(expects[i]).Length) throw new PatchRefusal("Internal error: patch table length mismatch at " + vas[i]);
            Array.Copy(r, 0, outb, va2off(va), r.Length);
        }

        // ---- 2. the new .sbook section (code caves + staging array)
        uint sizeOfImage = U32(buf, pe.Opt + 56);
        long newRva = sizeOfImage;
        Cave cave = new Cave(newRva);
        Func<int, long> abs = delegate (int off) { return BASE + newRva + off; };
        long BG = abs(BG_OFF), FLAG = abs(FLAG_OFF);
        string H1440 = "a0050000";

        cave.Emit(0x00, new object[] {
            "50", "51", "57",
            "bf", new AbsRef(BG),
            "b9" + H1440,
            "83c8ff", "fc", "f3ab",
            "5f", "59", "58",
            "68" + H1440,
            "68", new AbsRef(BG),
            "8bce", "e8", new RelRef(ORIG_READ),
            "c705", new AbsRef(FLAG), "01000000",
            "56", "57",
            "be", new AbsRef(BG),
            "8dbfbc1a0000",
            "b9d0020000", "fc", "f3a5",
            "5f", "5e", "c3"
        });
        const long COPY_BACK = 0x578fdd;
        cave.Emit(0x80, new object[] {
            "81fed0020000",
            "730c",
            "8bbcb3bc1a0000",
            "e9", new RelRef(COPY_BACK),
            "833d", new AbsRef(FLAG), "00",
            "bfffffffff",
            "7407",
            "8b3cb5", new AbsRef(BG),
            "e9", new RelRef(COPY_BACK)
        });

        // hooks in .text
        {
            byte[] b = new byte[19]; for (int i = 0; i < b.Length; i++) b[i] = 0x90;
            b[0] = 0xe8; Array.Copy(Rel32(site1 + 5, abs(0x00)), 0, b, 1, 4);
            Array.Copy(b, 0, outb, va2off(site1), b.Length);
        }
        {
            byte[] b = new byte[7]; for (int i = 0; i < b.Length; i++) b[i] = 0x90;
            b[0] = 0xe9; Array.Copy(Rel32(site2 + 5, abs(0x80)), 0, b, 1, 4);
            Array.Copy(b, 0, outb, va2off(site2), b.Length);
        }

        // ---- 3. PE edits
        int hdrEnd = pe.SecTab + pe.NSec * 40;
        uint firstRaw = uint.MaxValue;
        foreach (PeSection s in pe.Sec) if (s.Raw < firstRaw) firstRaw = s.Raw;
        if (hdrEnd + 40 > firstRaw) throw new PatchRefusal("No room in the file header for another section.");
        for (int i = 0; i < 40; i++) if (buf[hdrEnd + i] != 0) throw new PatchRefusal("The section header slot is not empty.");

        foreach (int r in cave.Relocs) if (r >= 0x1000) throw new PatchRefusal("Internal error: fixup beyond first page.");
        List<ushort> entries = new List<ushort>();
        foreach (int r in cave.Relocs) entries.Add((ushort)(0x3000 | r));
        if (entries.Count % 2 == 1) entries.Add(0);
        byte[] blk = new byte[8 + entries.Count * 2];
        W32(blk, 0, (uint)newRva); W32(blk, 4, (uint)blk.Length);
        for (int i = 0; i < entries.Count; i++) W16(blk, 8 + i * 2, entries[i]);
        int dd5 = pe.Opt + 96 + 5 * 8;
        if (U32(buf, dd5) != pe.Reloc.VA) throw new PatchRefusal("The relocation directory is not where this patch expects.");
        uint dirSize = U32(buf, dd5 + 4);
        if (pe.Reloc.RS - dirSize < blk.Length) throw new PatchRefusal("Not enough room at the end of the relocation section.");
        Array.Copy(blk, 0, outb, (int)(pe.Reloc.Raw + dirSize), blk.Length);
        W32(outb, dd5 + 4, dirSize + (uint)blk.Length);
        if (pe.Reloc.VS < dirSize + blk.Length) W32(outb, pe.Reloc.HdrOff + 8, dirSize + (uint)blk.Length);

        byte[] raw = new byte[outb.Length + cave.Data.Length];
        Array.Copy(outb, raw, outb.Length);
        Array.Copy(cave.Data, 0, raw, outb.Length, cave.Data.Length);
        byte[] nm = System.Text.Encoding.ASCII.GetBytes(".sbook\0\0");
        Array.Copy(nm, 0, raw, hdrEnd, 8);
        W32(raw, hdrEnd + 8, SEC_VS);
        W32(raw, hdrEnd + 12, (uint)newRva);
        W32(raw, hdrEnd + 16, CAVE_RAW);
        W32(raw, hdrEnd + 20, (uint)outb.Length);
        W32(raw, hdrEnd + 36, 0xE0000060u);
        W16(raw, pe.Peo + 6, (ushort)(pe.NSec + 1));
        W32(raw, pe.Opt + 56, sizeOfImage + SEC_VS);

        if (setLaa) W16(raw, pe.Peo + 22, (ushort)(U16(raw, pe.Peo + 22) | 0x20));

        W32(raw, pe.Opt + 64, 0);
        long sum = 0; int n = raw.Length;
        for (int i = 0; i < n; i += 2)
        {
            sum += (i + 1 < n) ? (long)U16(raw, i) : (long)raw[i];
            sum = (sum & 0xffff) + (sum >> 16);
        }
        sum = (sum & 0xffff) + (sum >> 16);
        W32(raw, pe.Opt + 64, (uint)((sum & 0xffff) + n));
        return raw;
    }
}
