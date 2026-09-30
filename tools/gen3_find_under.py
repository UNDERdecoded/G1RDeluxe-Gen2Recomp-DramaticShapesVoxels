"""Find the `under` metatile for an overhead figure in data/*/gen3_palings.lua.

A Gen 3 object taller than one cell draws its top half on the ABOVE-PLAYER
layer of the cell BEHIND it, which leaves the crown painted flat on the floor
or wall it was drawn over. `overhead.figures` lifts it back onto the object,
and each entry needs `under`: what the crown's cell wears once the crown is
taken off it -- which must be that cell's own layer 1.

Structures.overheadFor believes that only if BOTH hold, so this tests both:
  * `under` draws nothing on the above-player layer of its own;
  * outside `meta`'s above-player silhouette the two composited metatiles
    agree pixel for pixel.

    python tools/gen3_find_under.py <atlas_dir> <MAP_ID> <meta>[,<meta>...] [--same-art]
"""
import sys
import os
from PIL import Image

CELL = 16
COLS = 16


def crop(sheet, mid):
    x, y = (mid % COLS) * CELL, (mid // COLS) * CELL
    if y + CELL > sheet.height:
        return None
    return sheet.crop((x, y, x + CELL, y + CELL))


def main():
    atlas_dir, map_id = sys.argv[1], sys.argv[2]
    metas = [int(v) for v in sys.argv[3].split(",")]
    bottom = Image.open(os.path.join(atlas_dir, f"{map_id}_bottom.png")).convert("RGBA")
    top = Image.open(os.path.join(atlas_dir, f"{map_id}_top.png")).convert("RGBA")

    total = (bottom.height // CELL) * COLS
    if "--same-art" in sys.argv:
        drawings = {crop(top, meta).tobytes() for meta in metas}
        metas = [meta for meta in range(total)
                 if crop(top, meta).tobytes() in drawings]

    def composite(mid):
        b, t = crop(bottom, mid), crop(top, mid)
        if b is None:
            return None
        return Image.alpha_composite(b, t) if t is not None else b

    def overhead_px(mid):
        t = crop(top, mid)
        if t is None:
            return 0
        return sum(alpha > 0 for alpha in t.getchannel("A").tobytes())

    for meta in metas:
        mt = crop(top, meta)
        mask = [alpha > 0 for alpha in mt.getchannel("A").tobytes()]
        n = sum(mask)
        mc = composite(meta).convert("RGB").load()
        print(f"\n=== meta {meta} (above-player px={n}) ===")
        if n == 0:
            print("    no above-player art -- not an overhead figure")
            continue
        found = []
        for u in range(total):
            if u == meta or overhead_px(u) != 0:
                continue
            cu = composite(u)
            if cu is None:
                continue
            up = cu.convert("RGB").load()
            ok = True
            for i in range(CELL * CELL):
                if mask[i]:
                    continue
                x, y = i % CELL, i // CELL
                if mc[x, y] != up[x, y]:
                    ok = False
                    break
            if ok:
                found.append(u)
        print(f"    under candidates: {found if found else 'NONE'}")
        base = crop(bottom, meta).convert("RGB").tobytes()
        exact = [under for under in found
             if composite(under).convert("RGB").tobytes() == base]
        print(f"    exact layer-1 matches: {exact if exact else 'NONE'}")


if __name__ == "__main__":
    main()
