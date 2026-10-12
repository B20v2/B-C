"""
Shared colour palette for every Forge & Frontline model.

All meshes use ONE 256x256 palette texture (8x8 cells). Each face's UVs are
collapsed onto the centre of one cell, so a whole building is a single
material + single texture: cheap to render on Roblox and every model shares
the same look. Change a colour here and regenerate the kit to restyle
everything at once.
"""

CELLS = 8
CELL_PX = 32
SIZE = CELLS * CELL_PX

# 8 rows x 8 colours (sRGB 0-255)
ROWS = [
    # neutrals
    [("white", (242, 240, 234)), ("offwhite", (226, 222, 212)), ("concrete_l", (204, 201, 192)), ("concrete", (172, 170, 162)),
     ("grey", (130, 131, 128)), ("grey_d", (90, 92, 95)), ("charcoal", (54, 56, 60)), ("black", (28, 29, 32))],
    # warm
    [("cream", (240, 228, 200)), ("beige", (222, 202, 164)), ("sand", (208, 184, 138)), ("tan", (178, 148, 106)),
     ("terracotta", (198, 106, 74)), ("brick", (164, 84, 64)), ("brick_d", (118, 60, 50)), ("wood", (132, 94, 64))],
    # glass / cool
    [("glass_l", (156, 200, 218)), ("glass", (92, 142, 170)), ("glass_d", (46, 74, 98)), ("teal", (48, 170, 160)),
     ("teal_d", (30, 112, 110)), ("steelblue", (72, 106, 142)), ("navy", (36, 52, 84)), ("slate", (86, 98, 114))],
    # greens
    [("grass_l", (138, 180, 94)), ("grass", (100, 144, 72)), ("leaf", (78, 128, 60)), ("leaf_d", (54, 92, 48)),
     ("olive_l", (144, 150, 98)), ("olive", (104, 112, 72)), ("olive_d", (72, 80, 52)), ("camo", (88, 94, 64))],
    # accents
    [("orange", (246, 138, 40)), ("amber", (255, 186, 58)), ("yellow", (244, 208, 74)), ("red", (214, 64, 54)),
     ("red_d", (152, 42, 38)), ("hazard", (32, 32, 32)), ("cyan", (84, 222, 242)), ("glow", (255, 216, 144))],
    # metals
    [("alu", (198, 202, 206)), ("steel", (142, 150, 158)), ("rust", (152, 84, 48)), ("copper", (186, 114, 72)),
     ("brass", (202, 162, 82)), ("gunmetal", (72, 78, 84)), ("tire", (38, 38, 40)), ("chrome", (224, 230, 234))],
    # misc
    [("pblue", (152, 188, 226)), ("pgreen", (162, 208, 172)), ("ppink", (232, 172, 172)), ("purple", (132, 98, 182)),
     ("dirt", (134, 102, 72)), ("water", (72, 142, 192)), ("asphalt", (66, 68, 72)), ("line", (238, 234, 222))],
    # faction + roofs
    [("east", (80, 100, 66)), ("east_d", (58, 72, 48)), ("euro", (186, 170, 130)), ("euro_d", (142, 126, 92)),
     ("roof_r", (172, 72, 60)), ("roof_s", (82, 90, 106)), ("roof_g", (92, 122, 92)), ("roof_b", (72, 98, 142))],
]

INDEX = {}
COLORS = []
for r, row in enumerate(ROWS):
    for c, (name, rgb) in enumerate(row):
        INDEX[name] = len(COLORS)
        COLORS.append((name, rgb, r, c))


def index(name: str) -> int:
    if name not in INDEX:
        raise KeyError(f"unknown palette colour '{name}'")
    return INDEX[name]


def uv(i: int):
    """UV coordinate at the centre of palette cell i (V flipped for images)."""
    _, _, r, c = COLORS[i]
    return ((c + 0.5) / CELLS, 1.0 - (r + 0.5) / CELLS)


def write_png(path: str):
    """Write the palette texture (pure Python, no PIL needed)."""
    import struct
    import zlib

    rows = []
    for y in range(SIZE):
        r = y // CELL_PX
        row = bytearray([0])
        for x in range(SIZE):
            c = x // CELL_PX
            rgb = ROWS[r][c][1]
            row += bytes(rgb)
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
