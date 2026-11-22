import struct

def BMHSearch(Data: bytes, Pattern: bytes) -> list[int]:
    m, n = len(Pattern), len(Data)
    SkipTable = [m] * 256
    for i in range(m - 1):
        SkipTable[Pattern[i]] = m - 1 - i
    Matches, i = [], 0
    while i <= n - m:
        j = m - 1
        while j >= 0 and Pattern[j] == Data[i + j]:
            j -= 1
        if j < 0:
            Matches.append(i)
            i += 1
        else:
            i += SkipTable[Data[i + m - 1]]
    return Matches

with open("doom_ram.bin", "rb") as f:
    ram = f.read()

Targets = {
    "Thing 295 (-1328, -1968)": struct.pack("<ii", -1328 << 16, -1968 << 16),
    "Thing 296 (-1328, -2128)": struct.pack("<ii", -1328 << 16, -2128 << 16),
}

for Name, Sig in Targets.items():
    for OffsetX in BMHSearch(ram, Sig):
        MobjStart = OffsetX - 0x0C
        MobjAngle, = struct.unpack_from("<I", ram, MobjStart + 0x20)
        MobjType, = struct.unpack_from("<I", ram, MobjStart + 0x58)
        MobjFlagsAddr = MobjStart + 0x68
        MobjFlags, = struct.unpack_from("<I", ram, MobjFlagsAddr)
        print(f"=== {Name} ===")
        print(f"  mobj_t base : 0x{MobjStart:08X}")
        print(f"  Angle       : 0x{MobjAngle:08X} (atteso: 0x40000000)")
        print(f"  type        : 0x{MobjType:08X} (atteso: 0x0000005D)")
        print(f"  Flags addr  : 0x{MobjFlagsAddr:08X} -> valore attuale: 0x{MobjFlags:08X}")

OrgX, OrgY, Width, Height = -2248, -2632, 38, 35
BmapHeader = struct.pack("<hhhh", OrgX, OrgY, Width, Height)

for off in BMHSearch(ram, BmapHeader):
    NumBlocks = Width * Height
    # Leggi la tabella degli offset (short unSigned a 16-bit)
    Offsets = struct.unpack_from(f"<{NumBlocks}H", ram, off + 8)
    
    # Verifica che il primo offset punti subito dopo la tabella (4 header + NumBlocks)
    ExpectedFirstOffset = 4 + NumBlocks
    if Offsets[0] == ExpectedFirstOffset:
        print(f"=== BLOCKMAP LUMP TROVATA ===")
        print(f"  Indirizzo base (blockmaplump) : 0x{off:08X}")
        print(f"  Tabella offset (blockmap)     : 0x{off + 8:08X} ({NumBlocks} elementi)")
        