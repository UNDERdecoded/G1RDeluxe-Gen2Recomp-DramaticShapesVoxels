-- data/firered/gen3_palings.lua -- THE KANTO PALING PROFILE.
--
-- FireRed's counterpart of data/gen3_palings.lua, same schema and same rules.
-- It is a separate file because `gen3_palings` is version-keyed in main.lua
-- (EMERALD_KEYED): a Gen 3 game that is not Emerald reads
-- `data/<version>/gen3_palings.lua` and, where it has none, reads NOTHING.
-- FireRed had none, so Kanto built no palings at all -- measured over 33
-- outdoor maps, Hoenn logs "stood 147 paling post(s)" on Route 110 and "38"
-- on Route 104 while Kanto logs not one. Its fences stayed in whatever
-- generic class they resolved to, and `fence` is a BOX: a run of them comes
-- out as one continuous kerb wearing fence texture, which is the flat grey
-- rail lying across Viridian City like a length of railway track.
--
-- Hand-authored by this mod and read only from here. Nothing below is
-- extracted, derived or copied from the ROM; nothing here reaches gameplay,
-- collision, warps, scripts or encounters. An entry can only ever change how
-- a cell LOOKS.
--
-- ---------------------------------------------------------------------------
-- KANTO DRAWS ITS FENCE IN ONE VIEW, WHERE HOENN DRAWS TWO
-- ---------------------------------------------------------------------------
--
-- This is the one place the schema does not fit Kanto the way it fits Hoenn,
-- and it is worth stating plainly rather than papering over.
--
-- Hoenn's fences are drawn TWICE -- metatile 329 is the ELEVATION (rows are
-- height) and 320 is the PLAN (rows are depth) -- and the Hoenn file reads
-- the post's width off one, its depth off the other, and checks that the two
-- agree. That cross-check is most of why those numbers can be called read
-- rather than chosen.
--
-- Kanto has no plan drawing. Every piece of this fence is the SAME elevation;
-- a line running north or south is stated by the post continuing up or down
-- out of the cell in that same face view (252/253 continue north, 236/237
-- south). Read off the engine's own bake of metatile 231:
--
--         0123456789012345
--       0 ................
--       1 ................
--       2 ..####....####..     <- the two post heads, cols 2..5 and 10..13
--       3 .######..######.
--       4 .######..######.
--       5 .######..######.
--       6 ################     <- the RAIL, full width, rows 6..9:
--       7 ################        post colour across the posts and rail
--       8 ################        colour between them, so the posts
--       9 ################        OCCLUDE it and it is centred, not proud
--      10 .######..######.
--      11 .######..######.
--      12 .######..######.     <- the post feet
--      13 .#######.#######     \
--      14 ...#####...#####      > the CAST SHADOW, stepping south-east.
--      15 .....###.....###     /  Not the post, and not taken.
--
-- so the post is six columns wide (1..6 and 9..14) at a pitch of eight, and
-- eleven rows tall (2..12). Those three are read.
--
-- TWO NUMBERS ARE CHOSEN, and they are named here so nobody has to guess
-- which:
--   * the post's DEPTH is set equal to its width, because a square post is
--     what the drawing shows and because Hoenn's, where both views exist,
--     measured w == d as well;
--   * the RAIL's depth is 2, the same as the Hoenn rail whose depth its own
--     plan drawing did state.
-- Neither can be read off Kanto's art because Kanto never draws this fence
-- from above.
--
-- `top` is metatile 231's own post HEAD (x = 1, z = 2). A square post's lid
-- is the same lit grey its head is drawn in, so this is the drawing's own
-- answer rather than a borrowed one -- but it is the post's head seen
-- face-on, not a plan, and that is the honest description of it.
--
-- ---------------------------------------------------------------------------
-- WHERE THESE IDS ARE VALID
-- ---------------------------------------------------------------------------
--
-- 231 and its family are all below 512, so they belong to the PRIMARY
-- tileset -- the same drawing in every pair built on it. Kanto's outdoor
-- primary is `02D4A94` (frlg_gTileset_General, the primary of all 76 outdoor
-- FireRed maps), so this is keyed there rather than per pair, exactly as the
-- Hoenn white rail fence is keyed on `03DF704`.
return {
  version = 1,

  primaries = {
    ["02D4BB4"] = {
      figures = {
        { name = "house plant crown (grey floor)",
          meta = 71, under = 1, south = 1, round = true },
        { name = "house plant crown (wood floor)",
          meta = 87, under = 9, south = 1, round = true },
      },
    },
    ["02D4A94"] = {
      palings = {
        {
          name = "kanto white rail fence",

          -- w = 6   drawn columns 1..6 of 231
          -- d = 6   chosen: square post, see the header
          -- h = 11  drawn rows 2..12 of 231
          post = { w = 6, d = 6, h = 11 },
          face = { meta = 231, x = 1, y0 = 2, y1 = 12 },
          top  = { meta = 231, x = 1, z = 2 },

          -- one rail, drawn rows 6..9 of 231, full width of the cell.
          rails = {
            { face = { 6, 9 }, depth = 2 },
          },

          -- WHERE THE POSTS STAND.
          --
          -- Across the cell the two posts are at x = 1 and x = 9, which is
          -- where 231 draws them. Through the cell the fence hugs the SOUTH
          -- edge: the post feet are row 12 and the shadow falls on 13..15, so
          -- a six-deep post seated at z = 10 closes on the cell's south edge
          -- and a corner meets without a gap.
          --
          -- A line running north or south is a RAIL leaving the cell in that
          -- direction at the continuing post's own lane -- the posts
          -- themselves are already stated by the east-west pair, so a
          -- junction adds a rail and never a third post.
          pieces = {
            -- east-west, running through the cell
            [231] = { posts = { { 1, 10 }, { 9, 10 } },
                      rails = { { "x", 10, 0, 16 } } },

            -- ...and turning NORTH out of the cell: 252 on the west post
            -- (its rows 0..1 carry that post's body at columns 2..5), 253 on
            -- the east (rows 0..1 at columns 10..13).
            [252] = { posts = { { 1, 10 }, { 9, 10 } },
                      rails = { { "x", 10, 0, 16 }, { "z", 1, 0, 10 } } },
            [253] = { posts = { { 1, 10 }, { 9, 10 } },
                      rails = { { "x", 10, 0, 16 }, { "z", 9, 0, 10 } } },

            -- ...and turning SOUTH: 236 on the west post, 237 on the east.
            -- Their rows 13..15 carry a straight four-column body where 231
            -- has only its stepped shadow, which is how the two are told
            -- apart.
            [236] = { posts = { { 1, 10 }, { 9, 10 } },
                      rails = { { "x", 10, 0, 16 }, { "z", 1, 10, 16 } } },
            [237] = { posts = { { 1, 10 }, { 9, 10 } },
                      rails = { { "x", 10, 0, 16 }, { "z", 9, 10, 16 } } },
          },
        },
      },
    },
  },

  -- ---------------------------------------------------------------------
  -- OVERHEAD FIGURES: a crown that belongs to the pot in front of it.
  -- ---------------------------------------------------------------------
  --
  -- Gen 3 draws anything taller than one cell across TWO cells: the body in
  -- the cell you stand next to, and the part that rises past the top of it
  -- on the ABOVE-PLAYER layer of the cell BEHIND.  The mod stands the body --
  -- that is what the `cylinder` pins on the pots do -- but the crown stays
  -- painted flat on whatever it was drawn over, which is the report: the
  -- pot stands up and its leaves lie on the floor beside it.
  --
  -- Hoenn answers this with the same block (g3-crown-278, the Game Corner's
  -- three plants).  Kanto needs its own because the ids are its own.
  --
  -- `under` is what the crown's cell wears once the crown is lifted off it,
  -- and it MUST be that cell's own layer 1 -- `Structures.overheadFor`
  -- checks it at runtime and DROPS a figure whose `under` does not match,
  -- rather than half-apply one and paint a hole in the floor.  Both ids
  -- below were found by that same test, run offline over every metatile in
  -- the pair (tools/gen3_find_under.py), and each came back with exactly ONE
  -- candidate.
  overhead = {
    -- CELADON DEPARTMENT STORE: the planters flanking the shop floor.  702
    -- and 703 each carry 138 px of above-player frond over the two floor
    -- shades, and 710/711 (pinned `cylinder` in gen3_shapes.lua) are the
    -- tubs one cell south of them.
    ["TILESET_02D4BB4_02D4E6C"] = {
      figures = {
        { name = "dept store planter crown (orange floor)",
          meta = 702, under = 705, south = 1, round = true },
        { name = "dept store planter crown (tan floor)",
          meta = 703, under = 704, south = 1, round = true },
      },
    },

    -- OAK'S LAB, whose corner plants are the pots pinned 667/668.
    ["TILESET_02D4BB4_02D4C8C"] = {
      figures = {
        { name = "lab plant crown (pale floor)",
          meta = 659, under = 648, south = 1, round = true },
        { name = "lab plant crown (main floor)",
          meta = 660, under = 649, south = 1, round = true },
      },
    },

    -- SILPH CO AND THE ROCKET HIDEOUT, pots 776/777.
    ["TILESET_02D4BB4_02D4ECC"] = {
      figures = {
        { name = "office planter crown (light floor)",
          meta = 768, under = 641, south = 1, round = true },
        { name = "office planter crown (dark floor)",
          meta = 769, under = 642, south = 1, round = true },
      },
    },
  },
}
