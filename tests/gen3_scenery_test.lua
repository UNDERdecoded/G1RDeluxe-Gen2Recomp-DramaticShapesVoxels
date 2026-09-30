-- WHAT A GEN 3 METATILE IS A PICTURE OF.
--
-- The bug this exists for did not crash, log a warning, or fail any test that
-- existed: a real Littleroot resolved every one of its 900 cells to exactly
-- three classes -- wall, ground, water. Not one tree, roof, fence or flower,
-- because Emerald writes MB_NORMAL on all of them. Every object in Hoenn
-- meshed as the box its collision bit implied, which is the whole of the
-- "houses and trees are extremely boxy" report.
--
-- The three things that fixed it are the three things pinned here:
--
--   1. THE BACKGROUND SET. Emerald draws an object on layer 2 over the ground
--      on layer 1, so the layer-1 art under a FULL layer-2 object is ground by
--      construction -- and that is where the tileset's own ground colours are
--      read from. No colour constants, nothing to retune per tileset.
--   2. THE SHAPE SURFACE. The same sheet as the texture atlas, with those
--      ground colours cut to alpha 0. Every pixel pass in this mod finds
--      background by testing `a == 0`, and Emerald's composite has no
--      transparency at all -- so before the carve they all carved a hull out
--      of a solid rectangle and got the rectangle back.
--   3. THE 2x2 TREE MOTIF. Hoenn's forests are a four-metatile motif tiled
--      edge to edge, which reads cell by cell as a green wall. Read as a
--      tiling it is a stand of trees: one round crown per 2x2 block.
--
-- Run from the repository root:
--     luajit mods/DRAMATIC_SHAPE/tests/gen3_scenery_test.lua
local ENGINE = os.getenv("ENGINE") or "."
local MOD = os.getenv("MOD") or "mods/DRAMATIC_SHAPE"
if MOD:sub(-1) ~= "/" then MOD = MOD .. "/" end
package.path = ENGINE .. "/?.lua;" .. ENGINE .. "/?/init.lua;" .. package.path

_G.love = require("tests.love_stub")
local function obj(t)
  return setmetatable(t or {}, { __index = function() return function() end end })
end
-- REAL storage. A no-op setPixel is exactly the thing that would let a hollow
-- carve pass for a working one.
love.image = love.image or {}
love.image.newImageData = function(w, h)
  local px = {}
  return obj({
    _w = w, _h = h,
    getWidth = function() return w end,
    getHeight = function() return h end,
    getDimensions = function() return w, h end,
    setPixel = function(_, x, y, r, g, b, a) px[y * w + x] = { r, g, b, a } end,
    getPixel = function(_, x, y)
      local c = px[y * w + x]
      if not c then return 0, 0, 0, 0 end
      return c[1], c[2], c[3], c[4]
    end,
  })
end
love.graphics.newImage = function(d)
  return obj({ __data = d,
               getWidth = function() return d:getWidth() end,
               getHeight = function() return d:getHeight() end,
               getDimensions = function() return d:getDimensions() end })
end

local V = {}
local modules, dataFiles = {}, {}
function V.require(n)
  local h = modules[n]; if h ~= nil then return h end
  local v = assert(loadfile(MOD .. "lib/" .. n .. ".lua"))(V); modules[n] = v; return v
end
function V.data(n)
  local h = dataFiles[n]; if h ~= nil then return h end
  local v = assert(loadfile(MOD .. "data/" .. n .. ".lua"))(V); dataFiles[n] = v; return v
end

local pass, fail = 0, 0
local function ok(c, what)
  if c then pass = pass + 1 else fail = fail + 1; io.write("  FAIL  ", what, "\n") end
end
local function eq(a, b, what)
  if a == b then pass = pass + 1 else fail = fail + 1
    io.write("  FAIL  ", what, ": got ", tostring(a), " want ", tostring(b), "\n") end
end

-- ---- a synthetic cartridge with three kinds of art -----------------------
--
-- Palette entry 5 is the ground: a bright yellow-green with a strong blue
-- component, which is what Hoenn's lawn actually is. Entry 6 is canopy: the
-- same hue with the blue taken out. Entry 7 is a roof. The foliage test has
-- to separate 5 from 6, and those two are as close as the real ones.
local GROUND = { 117, 196, 166 }
local CANOPY = { 99, 171, 84 }
local ROOF   = { 199, 120, 110 }

local palettes = {}
for p = 1, 16 do
  local row = {}
  for c = 1, 16 do row[c] = { 8 * c, 8 * c, 8 * c } end
  row[6] = GROUND          -- 4bpp index 5 -> Lua index 6
  row[7] = CANOPY
  row[8] = ROOF
  palettes[p] = row
end

-- tile 0 blank, tile 1 solid index 5, tile 2 index 6, tile 3 index 7
local function solid(i) return string.rep(string.char(i * 17), 32) end
local tilePixels = string.rep("\0", 32) .. solid(5) .. solid(6) .. solid(7)
                   .. string.rep("\0", 32 * 508)

-- metatile 0 ground; 1 ground under a FULL roof; 2 and 3 solid canopy
local META = {
  [0] = { bottom = 1, top = 0 },
  [1] = { bottom = 1, top = 3 },
  [2] = { bottom = 2, top = 0 },
  [3] = { bottom = 2, top = 0 },
}
local N = 4
local meta, attrs = {}, {}
for m = 0, N - 1 do
  local spec = META[m]
  for t = 0, 7 do
    local tile = (t <= 3) and spec.bottom or spec.top
    local word = tile + 1 * 4096            -- palette 1
    meta[#meta + 1] = string.char(word % 256, math.floor(word / 256) % 256)
  end
  -- MB_NORMAL on every one of them, layer type 0 -- which is the point: the
  -- behaviour byte says nothing at all and the art has to carry it
  attrs[#attrs + 1] = string.char(0, 0)
end

local primary = {
  id = "TS", tiles = tilePixels, metatiles = table.concat(meta),
  attributes = table.concat(attrs), palettes = palettes,
  tileCount = 512, metatileCount = N,
}
_G.Game = { data = { map_tilesets = { TS = primary }, maps = {},
                     constants = { gen3Layout = { tilesInPrimary = 512,
                       metatilesInPrimary = N, palettesInPrimary = 6,
                       metatileLayers = 2 } } } }

--   . = ground   T = canopy art   R = roof     # = blocked
--      T T . T          # # . #
--      T T . .          # # . .
--      . . . .          . . . .
--      R . . .          # . . .
local W, H = 4, 4
local grid = { 2, 3, 0, 2,
               3, 2, 0, 0,
               0, 0, 0, 0,
               1, 0, 0, 0 }
local coll = { 1, 1, 0, 1,
               1, 1, 0, 0,
               0, 0, 0, 0,
               1, 0, 0, 0 }
local blocks = {}
for i = 1, W * H do
  local word = grid[i] + coll[i] * 1024
  blocks[i] = string.char(word % 256, math.floor(word / 256) % 256)
end
local tsDef = { id = "TS_PAIR", primaryKey = "TS", blockTiles = 2,
                blockCells = 1, metatileCount = N, collision = {}, walkable = {} }
local function newMap(id, outdoor)
  local def = { id = id, width = W, height = H, blocks = table.concat(blocks),
                collisionCells = coll, borderBlock = 0, tileset = "TS_PAIR",
                outdoor = outdoor }
  local m = require("src.world.Map").new(def, tsDef)
  m.id = id
  return m
end

local Gen3 = V.require("Gen3")
local TileShape = V.require("TileShape")

-- ---- 1. the background set -----------------------------------------------
io.write("the ground colours identify themselves\n")

local art = Gen3.analyse(tsDef)
ok(art ~= nil, "the pair analyses")
if art then
  local function key(c) return c[1] * 65536 + c[2] * 256 + c[3] end
  ok(art.background[key(GROUND)] == true,
     "the lawn under the roof is background")
  ok(art.background[key(CANOPY)] ~= true,
     "the canopy is NOT background (nothing full-topped is drawn on it)")
  ok(art.background[key(ROOF)] ~= true, "and neither is the roof")
  eq(art.stats[0].leafy, false, "plain ground is not leafy")
  eq(art.stats[2].leafy, true, "canopy art is leafy")
  eq(art.stats[1].leafy, false, "a roof is not leafy, however green the lawn "
     .. "under it")
  eq(art.stats[1].overhead, true, "a full top layer reads as overhead")
  eq(art.stats[0].overhead, false, "an empty one does not")
  -- the number that matters: how much of the cell is NOT ground
  eq(art.stats[0].solid, 0, "a ground cell is 0% object")
  eq(art.stats[2].solid, 1, "a canopy cell is 100% object")
  eq(art.stats[1].solid, 1, "so is a roofed one -- the roof covers the lawn")
end

-- ---- 2. the shape surface ------------------------------------------------
io.write("\nthe shape surface cuts the ground out\n")

local shape = Gen3.shapeDataForTileset(tsDef)
local atlas = Gen3.atlasDataForTileset(tsDef)
ok(shape ~= nil, "a shape surface is carved")
ok(atlas ~= nil, "and the texture atlas still bakes")
ok(shape ~= atlas, "they are two different surfaces")

if shape and atlas then
  local info = Gen3.atlasInfoFor(tsDef)
  local function alphaIn(surface, m)
    local n = 0
    for q = 0, 3 do
      local t = m * 4 + q
      local ox = (t % info.perRow) * 8
      local oy = math.floor(t / info.perRow) * 8
      for y = oy, oy + 7 do
        for x = ox, ox + 7 do
          local _, _, _, a = surface:getPixel(x, y)
          if a and a > 0 then n = n + 1 end
        end
      end
    end
    return n
  end
  eq(alphaIn(shape, 0), 0, "ground carves away to nothing")
  eq(alphaIn(shape, 2), 256, "canopy art survives whole")
  eq(alphaIn(shape, 1), 256, "a roof survives whole, over its cut-out lawn")
  -- THE TEXTURE MUST NOT BE CARVED. A hole in it is a hole in the world.
  eq(alphaIn(atlas, 0), 256, "the TEXTURE keeps its ground -- opaque")
  eq(alphaIn(atlas, 2), 256, "and its canopy")
end

-- ---- 3. the tree motif ---------------------------------------------------
io.write("\na 2x2 of foliage is one tree, not four walls\n")

local outdoor = newMap("MAP_G00_N09", true)
local shapes = TileShape.forMap(outdoor)
local function classAt(map, sh, cx, cy)
  local s = TileShape.at(map, sh, Gen3.tileAt(map, cx * 2, cy * 2), cx * 2, cy * 2)
  return s and s.class or nil
end

eq(classAt(outdoor, shapes, 0, 0), "canopy", "the block's top-left anchors it")
eq(classAt(outdoor, shapes, 1, 0), "cylinder", "its partners are hull cells")
eq(classAt(outdoor, shapes, 0, 1), "cylinder", "(south-west)")
eq(classAt(outdoor, shapes, 1, 1), "cylinder", "(south-east)")
eq(classAt(outdoor, shapes, 3, 0), "cylinder",
   "a LONE foliage cell is a single hull, not an anchor with no partners")
eq(classAt(outdoor, shapes, 2, 0), "ground", "the gap between them is ground")
eq(classAt(outdoor, shapes, 2, 2), "ground", "and so is the open field")

local g3 = Gen3.forMap(outdoor)
ok(g3 ~= nil, "the map builds a context")
if g3 then
  eq(g3.roofAt(0, 3), true, "the roofed cell is a roof")
  eq(g3.roofAt(0, 0), false, "a tree is not a roof, whatever its layer type")
  eq(g3.roofAt(2, 2), false, "and open ground is not a roof")
end

-- INDOORS, above-player art is the top of a wall or a shelf -- priority, not
-- a pitched roof over a facade. A gable on the kitchen units is worse than
-- no gable at all.
Gen3.invalidate()
local inside = newMap("MAP_G01_N00", false)
local g3in = Gen3.forMap(inside)
ok(g3in ~= nil, "an interior builds a context too")
if g3in then
  eq(g3in.roofAt(0, 3), false, "and pitches no roofs indoors")
end

-- ---- 4. Structures actually sees it --------------------------------------
io.write("\nand Structures builds from it\n")

local Structures = V.require("Structures")
local S = Structures.forMap(outdoor)
ok(S ~= nil, "a Gen 3 outdoor map builds")
if S then
  eq(S.outdoor, true, "which knows it is outdoors (the MAP_TYPE, not the "
     .. "tileset name)")
  ok(S.gen3Roof ~= nil, "and collected the stated roof rows")
  ok(#S.roundStamps > 0,
     "the tree becomes a round hull (" .. #S.roundStamps .. " stamp(s))")
end

-- ---- 5. THE SHEET GEOMETRY IS NOT NEGOTIABLE -----------------------------
--
-- The rainbow-striped world, and the black interiors that came with it. Every
-- consumer of the atlas geometry in this mod reads `tileset.imageWidth or
-- 128` / `imageHeight or 48`, and on a Gen 3 pair those fallbacks are not a
-- smaller sheet -- they are a DIFFERENT sheet. An 8px quad stretched over 48
-- rows of a 2336-row atlas walks forty-eight unrelated tile rows across one
-- face: outdoors that is the banding, indoors, where those rows are
-- unpainted, it is a black room.
--
-- It was reachable because the geometry was being asked of the map CONTEXT,
-- which can legitimately not exist yet -- a mesh is queued before the engine
-- publishes the map's world record -- and the miss was cached forever. So the
-- rule this pins is: the sheet's geometry is a property of the PAIR, needs no
-- map, no context and no graphics, and is stated on the record before anyone
-- can read a fallback.
io.write("\nthe sheet states its own geometry, with no context and no bake\n")

do
  local fresh = { id = "TS_PAIR_FRESH", primaryKey = "TS", blockTiles = 2,
                  blockCells = 1, metatileCount = N,
                  collision = {}, walkable = {} }
  eq(fresh.imageWidth, nil, "a fresh pair record states nothing")
  local info = Gen3.describe(fresh)
  ok(info ~= nil, "describe answers without a map or a bake")
  eq(fresh.tilesPerRow, info.perRow, "and writes the stride onto the record")
  eq(fresh.imageWidth, info.width, "and the width")
  eq(fresh.imageHeight, info.height, "and the height")
  ok(fresh.imageHeight ~= 48,
     "which is emphatically not Gen 1's 48 (" .. tostring(fresh.imageHeight) .. ")")
  ok(fresh.imageWidth == info.perRow * 8,
     "width and stride agree, so `(t % perRow) * 8` stays in bounds")
end

-- and a map whose context cannot be built must not poison itself: the first
-- ask routinely lands before the world record exists, and caching that as a
-- permanent failure is what sent the UVs down the fallback in the first place
do
  Gen3.invalidate()
  local orphan = { id = "MAP_ORPHAN", width = W, height = H,
                   blocks = table.concat(blocks), collisionCells = coll,
                   borderBlock = 0, tileset = "TS_PAIR", outdoor = true }
  local m = require("src.world.Map").new(orphan, tsDef)
  m.id = "MAP_ORPHAN"
  local saved = _G.Game
  _G.Game = { data = { map_tilesets = {}, maps = {}, constants = {} } }
  local first = Gen3.forMap(m)
  eq(first, nil, "with nothing to build from, there is no context")
  _G.Game = saved
  local second = Gen3.forMap(m)
  ok(second ~= nil,
     "and the very next ask, once the data is there, SUCCEEDS -- the miss "
     .. "was not cached as permanent")
end

-- ---- 5b. a hull that stands on a roof ------------------------------------
--
-- The `my` field is what lets a round stamp leave the floor. It is read in
-- ChunkMesher and written only by buildRoofProps, so the contract worth
-- pinning here is the one every other hull depends on NOT changing: a stamp
-- that names no base is still placed at zero.
io.write("\nrooftop props\n")
do
  local Structures = V.require("Structures")
  local TileShape = V.require("TileShape")
  ok(TileShape.CLASS_INFO.chimney ~= nil,
     "`chimney` is a published class, so the map editor can offer it")
  eq(TileShape.CLASS_INFO.chimney.art, "chimney",
     "and it takes no fold: it is carved, not boxed")
  ok(type(Structures.buildRoofProps) == "function",
     "and Structures publishes the pass that carves it")
end

-- ---- 5c. FIRERED'S OWN BEHAVIOUR BYTES ------------------------------------
--
-- data/gen3_shapes.lua is EMERALD's table, and FireRed ships 37 behaviour
-- bytes it has no row for -- 6,625 placed cells over the cartridge's 425
-- maps, every one of them falling to the structural answer.  2,824 of those
-- are SEAFOAM ISLANDS' and the SEVII PORTS' fast current, blocked, standing
-- up as solid boxes where the sea should be.
--
-- lib/Gen3.lua's `spec()` merges an overlay over Emerald's table when, and
-- only when, the cartridge's own `constants.gen3FRLGBehaviours` is there.
-- What is pinned here is the whole contract:
--
--   * Emerald, which has no such key, gets THE SAME TABLE OBJECT as before;
--   * the bytes come from the cache and nothing is pinned to a number;
--   * a byte Emerald already names keeps Emerald's answer;
--   * and where both cartridges name a byte, the two agree -- which is the
--     evidence that the overlay is reading the script names the way Emerald's
--     author read the MB_ names.
io.write("\nfirered behaviour overlay\n")
do
  local shapes = V.data("gen3_shapes")
  local saved = _G.Game

  -- (a) NO FIRERED CONSTANTS -> NO OVERLAY, AND NO COPY EITHER.
  _G.Game = { data = { map_tilesets = {}, maps = {},
                       constants = { gen3Layout = { metatilesInPrimary = 512 } } } }
  local em = Gen3.spec()
  ok(rawequal(em, shapes),
     "on a cartridge with no gen3FRLGBehaviours the spec IS the data file")
  ok(rawequal(em.behaviour, shapes.behaviour),
     "and so is its behaviour table -- Emerald cannot tell the merge exists")
  eq(em.behaviour[0x5B], nil,
     "0x5B is a byte Emerald never defines, and stays undefined")
  eq(next(Gen3.frlgBehaviourOverlay(nil)), nil,
     "and the overlay of no constants at all is empty")
  eq(next(Gen3.frlgBehaviourOverlay({})), nil,
     "as is the overlay of an empty one")

  -- (b) THE CARTRIDGE'S OWN TABLE, shaped as src/import/RomExtractorGen3.lua
  -- writes it (pokefirered metatile_behaviors.h / GetInteractedMetatileScript).
  local frlg = {
    fastWater = 0x5B, pullDown = 0x59, pullDownGrass = 0x5A,
    stopSpinning = 0x58, runningDisallowed = 0x0A,
    spin = { [0x54] = "right", [0x55] = "left",
             [0x56] = "up", [0x57] = "down" },
    scripts = {
      [0x5B] = { name = "EventScript_CurrentTooFast", water = true },
      [0x83] = { name = "EventScript_PC" },
      [0x85] = { name = "EventScript_WallTownMap", north = true },
      [0x86] = { name = "EventScript_PlayerFacingTVScreen", north = true },
      [0xA4] = { name = "EventScript_Bookshelf" },
      [0xA8] = { name = "EventScript_Cabinet" },
      [0xA9] = { name = "EventScript_Kitchen" },
      [0xCA] = { name = "EventScript_Painting" },
      [0xD7] = { name = "EventScript_TrashBin" },
    },
  }
  _G.Game = { data = { map_tilesets = {}, maps = {},
                       constants = { gen3FRLGBehaviours = frlg } } }
  local fr = Gen3.spec()
  ok(not rawequal(fr, shapes), "FireRed gets a merged spec of its own")
  ok(not rawequal(fr.behaviour, shapes.behaviour),
     "with a behaviour table of its own, so the data file is never mutated")
  eq(fr.classes, shapes.classes,
     "and every other key is the file's own object, carried through")

  -- THE SEA.  The report this exists for.
  eq(fr.behaviour[0x5B], "water",
     "MB_FAST_WATER classes as water -- Seafoam's current stops being a wall")
  -- THE FURNITURE the cartridge names.
  eq(fr.behaviour[0xA4], "bookcase",
     "EventScript_Bookshelf is a bookcase, like Emerald's MB_BOOKSHELF")
  eq(fr.behaviour[0xA8], "cabinet", "EventScript_Cabinet is a cabinet")
  eq(fr.behaviour[0xA9], "worktop", "EventScript_Kitchen is counter height")
  eq(fr.behaviour[0xD7], "can",
     "EventScript_TrashBin is a can, like Emerald's MB_TRASH_CAN")
  eq(fr.behaviour[0x5A], "grass",
     "and Route 17's pull-down GRASS is grass, which the cache states by name")

  -- WHAT IS DELIBERATELY LEFT ALONE, because the structural fallback is
  -- already right and a row would be churn.
  eq(fr.behaviour[0x59], nil,
     "the cycling road itself is passable road: no row, so `ground`")
  eq(fr.behaviour[0x54], nil, "a spin tile is passable floor: no row")
  eq(fr.behaviour[0x58], nil, "and so is the tile that stops the spin")
  eq(fr.behaviour[0xCA], nil,
     "a painting is part of the wall it hangs on: no row, so `wall`")

  -- EMERALD'S ROW WINS, AND THE TWO AGREE.
  eq(fr.behaviour[0x83], shapes.behaviour[0x83],
     "0x83 is MB_PC on both cartridges and Emerald's row stands")
  local ov = Gen3.frlgBehaviourOverlay(frlg)
  local overlaps, disagree = 0, {}
  for b, cls in pairs(ov) do
    local e = shapes.behaviour[b]
    if e ~= nil then
      overlaps = overlaps + 1
      if e ~= cls then disagree[#disagree + 1] = ("0x%02X"):format(b) end
    end
  end
  ok(overlaps >= 3, "the two tables name at least three bytes in common")
  eq(table.concat(disagree, ","), "",
     "and they do not disagree on any of them")

  -- THE BYTES ARE THE CACHE'S.  Move them and the classes move with them:
  -- nothing in lib/Gen3.lua is pinned to a Kanto number.
  local moved = Gen3.frlgBehaviourOverlay({
    fastWater = 0x77, pullDownGrass = 0x76,
    scripts = { [0x78] = { name = "EventScript_Bookshelf" } },
  })
  eq(moved[0x77], "water", "a fastWater that moved takes `water` with it")
  eq(moved[0x76], "grass", "and so does a pullDownGrass")
  eq(moved[0x78], "bookcase", "and a script that moved takes its class")
  eq(moved[0x5B], nil, "leaving nothing behind at the number it used to have")

  -- AND THE MEMO IS KEYED ON THE CARTRIDGE, so switching back inside one
  -- session answers Emerald again rather than serving Kanto's rows to Hoenn.
  _G.Game = saved
  ok(rawequal(Gen3.spec(), shapes),
     "and switching cartridge back rebuilds: Hoenn is never served Kanto")
end

-- ---- 5b. a roof painted green is still a roof ----------------------------
--
-- VIRIDIAN CITY's house, door (25,11), and its Trainer School, door (25,18)
-- -- MAP_G05_N00 and MAP_G05_N02, the cartridge's own warp destinations.
-- Kanto paints a town's roofs one colour per town and Viridian's are GREEN,
-- so `Gen3.analyse` calls metatiles 649 and 657 leafy and `ctx.metaRole`
-- calls them green: every clause of `foliageCell`.  Each door column is those
-- two rows and nothing else, so the foliage guard in `ctx.buildings` refused
-- the DOOR column and neither building was ever founded -- their roofs then
-- lathed into tree crowns and their wall row read `cliff`.
--
-- What separates a roof from a wood is what `ctx.roofAt` is built on: a roof
-- is drawn ABOVE THE PLAYER, and a building's art is bespoke where the
-- landscape it backs onto tiles.  Both directions are pinned here.
io.write("\na roof drawn green is still a roof\n")
do
  local saved = _G.Game
  local realData = V.data

  local RGROUND, RLEAF = { 117, 196, 166 }, { 99, 171, 84 }
  local RWALL = { 199, 120, 110 }
  local rpal = {}
  for pi = 1, 16 do
    local row = {}
    for c = 1, 16 do row[c] = { 8 * c, 8 * c, 8 * c } end
    row[6] = RGROUND; row[7] = RLEAF; row[8] = RWALL
    rpal[pi] = row
  end
  local function rsolid(i) return string.rep(string.char(i * 17), 32) end
  local rtiles = string.rep("\0", 32) .. rsolid(5) .. rsolid(6) .. rsolid(7)
                 .. string.rep("\0", 32 * 508)
  -- 0 ground; 1 GREEN ROOF (leaf art on the ABOVE-PLAYER layer); 2 WOOD (the
  -- same leaf art, bottom layer only); 3 the wall course with the door in it
  local RMETA = { [0] = { 1, 0 }, [1] = { 2, 2 }, [2] = { 2, 0 }, [3] = { 3, 0 } }
  local RN = 4
  local rmeta, rattr = {}, {}
  for m = 0, RN - 1 do
    local spec = RMETA[m]
    for t = 0, 7 do
      local word = ((t <= 3) and spec[1] or spec[2]) + 1 * 4096
      rmeta[#rmeta + 1] = string.char(word % 256, math.floor(word / 256) % 256)
    end
    rattr[#rattr + 1] = string.char(0, 0)   -- MB_NORMAL: the art carries it
  end
  local rprim = { id = "RTS", tiles = rtiles, metatiles = table.concat(rmeta),
                  attributes = table.concat(rattr), palettes = rpal,
                  tileCount = 512, metatileCount = RN }
  _G.Game = { data = { map_tilesets = { RTS = rprim }, maps = {},
                       constants = { gen3Layout = { tilesInPrimary = 512,
                         metatilesInPrimary = RN, palettesInPrimary = 6,
                         metatileLayers = 2 } } } }

  --   row 0  . . . . . . . .   street
  --   row 1  W W R R W W W W   wood, ROOF, wood
  --   row 2  W W R R W W W W
  --   row 3  . . D D . . D .   two doors: one in the roof, one in the wood
  --   row 4  . . . . . . . .
  local RW, RH = 8, 5
  local rgrid = { 0,0,0,0,0,0,0,0,
                  2,2,1,1,2,2,2,2,
                  2,2,1,1,2,2,2,2,
                  0,0,3,3,0,0,3,0,
                  0,0,0,0,0,0,0,0 }
  local rcoll = { 0,0,0,0,0,0,0,0,
                  1,1,1,1,1,1,1,1,
                  1,1,1,1,1,1,1,1,
                  0,0,0,0,0,0,0,0,
                  0,0,0,0,0,0,0,0 }
  local rblocks = {}
  for i = 1, RW * RH do
    local word = rgrid[i] + rcoll[i] * 1024
    rblocks[i] = string.char(word % 256, math.floor(word / 256) % 256)
  end
  local rts = { id = "TILESET_0ABCDEF_0FEDCBA", primaryKey = "RTS",
                blockTiles = 2, blockCells = 1, metatileCount = RN,
                collision = {}, walkable = {} }
  -- The role table is what `foliageCell` reads `green` from, so the synthetic
  -- pair needs its own rows -- the same shape the generator emits.
  local ROLES = { version = 1, roles = { ["P0ABCDEF"] = {
    [0] = { "surface", "green",   16, 0, "", false, "", "", false },
    [1] = { "surface", "green",   16, 0, "", true,  "", "", false },
    [2] = { "surface", "green",   16, 0, "", true,  "", "", false },
    [3] = { "brow",    "manmade",  0, 2, "", false, "", "", false },
  } } }
  V.data = function(n)
    if n == "gen3_metatiles" then return ROLES end
    return realData(n)
  end

  local art2 = Gen3.analyse(rts)
  ok(art2 ~= nil, "the synthetic town analyses")
  if art2 then
    eq(art2.stats[1].leafy, true,
       "a green roof reads LEAFY -- which is the whole of the trouble")
    eq(art2.stats[2].leafy, true, "and so does the wood behind it")
    eq(art2.stats[1].overhead, true,
       "but the roof is drawn ABOVE THE PLAYER: you walk behind a house")
    eq(art2.stats[2].overhead, false, "and the wood is not")
  end

  local def = { id = "RMAP", width = RW, height = RH,
                blocks = table.concat(rblocks), collisionCells = rcoll,
                borderBlock = 0, tileset = "TILESET_0ABCDEF_0FEDCBA",
                outdoor = true,
                warps = { { x = 2, y = 3, destMap = "HOUSE", destWarp = 1 },
                          { x = 6, y = 3, destMap = "WOOD",  destWarp = 1 } } }
  local rmap = require("src.world.Map").new(def, rts)
  rmap.id = "RMAP"
  local ctx = Gen3.forMap(rmap)
  ok(ctx ~= nil, "and builds a context")
  if ctx then
    local b = ctx.buildings()
    local function claimed(cx, cy) return b.cell[cy * 8192 + cx] ~= nil end
    -- the green-roofed house IS a building: its art is bespoke (4 cells on
    -- the map, under RARE_BUILD) and drawn above the player
    ok(claimed(2, 1), "the green roof's west column is claimed")
    ok(claimed(3, 1), "and its east column")
    ok(claimed(2, 2), "and the course under the ridge")
    ok(claimed(3, 2), "on both columns")
    -- ...and the other direction, which is what the guard exists for: a door
    -- cut into a WOOD claims nothing.  Same leaf art, same green material --
    -- it is drawn on the bottom layer and it tiles.
    ok(not claimed(6, 1), "a door cut into the wood claims no tree above it")
    ok(not claimed(6, 2), "nor the tree under that")
    ok(not claimed(0, 1), "and the wood beside the house is not the house")
    ok(not claimed(5, 2), "nor the wood on its other side")
    eq(#b.list, 1, "one building on the map, not two and not none")
  end

  V.data = realData
  _G.Game = saved
end

-- ---- 6. no regression ----------------------------------------------------
io.write("\ngen1/gen2 untouched\n")
local g1 = { id = "G1", tilesPerRow = 16, imageWidth = 128, imageHeight = 48,
             blocks = string.rep("\0", 16), collision = {}, walkable = {} }
eq(Gen3.isGen3(g1), false, "a Gen 1 tileset is not Gen 3")
eq(Gen3.shapeDataForTileset(g1), nil, "and is carved by nothing")
eq(Gen3.analyse(g1), nil, "and analysed by nothing")
eq(g1.tilesPerRow, 16, "its stride is untouched")
eq(g1.imageWidth, 128, "and so are its dimensions")

io.write(("\n%d passed, %d failed\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
