"""Print a metatile's 16x16 drawing as text, so pixel numbers can be read off it.

Authoring a paling means naming the column a post starts at and the rows that
are its body.  Eyeballing a zoomed screenshot gets that wrong by a pixel and a
pixel is a whole world unit here, so print the grid instead.

Background is decided by the CORNER vote: the four corner pixels of a scenery
metatile are the ground it stands on, and anything unlike them is the object.

  python tools/gen3_metatile_pixels.py <atlas_dir> <MAP_ID> <id>[,<id>...]
"""
import sys
import os
from PIL import Image

CELL = 16
COLS_IN_SHEET = 16


def crop(sheet, mid):
    x = (mid % COLS_IN_SHEET) * CELL
    y = (mid // COLS_IN_SHEET) * CELL
    return sheet.crop((x, y, x + CELL, y + CELL))


def main():
    atlas_dir, map_id = sys.argv[1], sys.argv[2]
    ids = [int(v) for v in sys.argv[3].split(",")]
    bottom = Image.open(os.path.join(atlas_dir, f"{map_id}_bottom.png")).convert("RGBA")
    top_path = os.path.join(atlas_dir, f"{map_id}_top.png")
    top = Image.open(top_path).convert("RGBA") if os.path.exists(top_path) else None
    # A two-cell object draws its upper half on the ABOVE-PLAYER layer, so the
    # bottom sheet alone shows a plant's cell as bare floor.  Report both.
    layers = "--bottom-only" not in sys.argv

    for mid in ids:
        base = crop(bottom, mid)
        over = crop(top, mid) if top is not None else None
        img = base
        if layers and over is not None:
            img = Image.alpha_composite(base, over)
        px = img.convert("RGB").load()
        corners = [px[0, 0], px[15, 0], px[0, 15], px[15, 15]]
        bg = max(set(corners), key=corners.count)

        def near(c, d, tol=26):
            return all(abs(int(a) - int(b)) <= tol for a, b in zip(c, d))

        overdrawn = 0
        if over is not None:
            op = over.load()
            overdrawn = sum(1 for y in range(CELL) for x in range(CELL)
                            if op[x, y][3] > 0)
        print(f"\n=== metatile {mid} ===  background={bg}  "
              f"above-player px={overdrawn}")
        print("    " + "".join(f"{x%10}" for x in range(CELL)))
        for y in range(CELL):
            row = ""
            for x in range(CELL):
                row += "." if near(px[x, y], bg) else "#"
            print(f"{y:3} {row}")
        colspan = [x for x in range(CELL)
                   if any(not near(px[x, y], bg) for y in range(CELL))]
        rowspan = [y for y in range(CELL)
                   if any(not near(px[x, y], bg) for x in range(CELL))]
        print(f"    drawn columns {colspan}")
        print(f"    drawn rows    {rowspan}")


if __name__ == "__main__":
    main()
