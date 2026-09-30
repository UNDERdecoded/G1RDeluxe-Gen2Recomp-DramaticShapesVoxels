"""Contact sheet of the metatiles a Gen 3 map places, labelled with their ids.

Authoring a paling or a furniture pin means reading pixel numbers off the
drawing, and the drawing only exists once the engine has composited a
metatile's two layers with its own palettes.  tests/drivers/g3_atlas_dump.lua
dumps that bake; this lays the pieces out big enough to read and writes the
id under each one.

  python tools/gen3_atlas_sheet.py <atlas_dir> <MAP_ID> [--scale 4] [--only 1,2,3]
"""
import sys
import os
from PIL import Image, ImageDraw

CELL = 16
COLS_IN_SHEET = 16


def load_index(atlas_dir, map_id):
    path = os.path.join(atlas_dir, f"{map_id}_index.txt")
    placed = []
    with open(path, "r", encoding="utf-8") as fh:
        seen_header = False
        for line in fh:
            line = line.strip()
            if line.startswith("placed metatiles"):
                seen_header = True
                continue
            if seen_header and line:
                mid = line.split()[0]
                count = line.split("x")[-1]
                placed.append((int(mid), int(count)))
    return placed


def crop(sheet, mid):
    x = (mid % COLS_IN_SHEET) * CELL
    y = (mid // COLS_IN_SHEET) * CELL
    if y + CELL > sheet.height:
        return None
    return sheet.crop((x, y, x + CELL, y + CELL))


def main():
    atlas_dir, map_id = sys.argv[1], sys.argv[2]
    scale = 4
    only = None
    if "--scale" in sys.argv:
        scale = int(sys.argv[sys.argv.index("--scale") + 1])
    if "--only" in sys.argv:
        only = {int(v) for v in sys.argv[sys.argv.index("--only") + 1].split(",")}

    bottom = Image.open(os.path.join(atlas_dir, f"{map_id}_bottom.png")).convert("RGBA")
    top_path = os.path.join(atlas_dir, f"{map_id}_top.png")
    top = Image.open(top_path).convert("RGBA") if os.path.exists(top_path) else None

    placed = load_index(atlas_dir, map_id)
    if only is not None:
        placed = [(m, c) for m, c in placed if m in only]

    tile = CELL * scale
    pad = 18
    cols = 12
    rows = (len(placed) + cols - 1) // cols
    out = Image.new("RGBA", (cols * (tile + 6), rows * (tile + pad)), (32, 32, 40, 255))
    draw = ImageDraw.Draw(out)

    for i, (mid, count) in enumerate(placed):
        cx = (i % cols) * (tile + 6)
        cy = (i // cols) * (tile + pad)
        piece = crop(bottom, mid)
        if piece is None:
            continue
        # the above-player layer belongs to the same metatile; show it composited
        if top is not None:
            over = crop(top, mid)
            if over is not None:
                piece = Image.alpha_composite(piece, over)
        out.paste(piece.resize((tile, tile), Image.NEAREST), (cx, cy))
        draw.text((cx + 1, cy + tile + 2), f"{mid} x{count}", fill=(230, 230, 140, 255))

    dest = os.path.join(atlas_dir, f"{map_id}_sheet.png")
    out.save(dest)
    print(f"{dest}  {len(placed)} metatiles  {out.width}x{out.height}")


if __name__ == "__main__":
    main()
