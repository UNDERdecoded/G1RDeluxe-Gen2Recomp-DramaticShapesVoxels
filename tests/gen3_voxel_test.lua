-- Headless coverage for the mod's GEN 3 arm.
--
-- Runs with nothing but a Lua interpreter -- no ROM, no LOVE, no host -- by
-- building a synthetic Gen 3 cartridge in memory: eight metatiles with chosen
-- attributes words, and a 4x4-cell map whose blockdata is packed the way the
-- hardware packs it (metatile 0-9, collision 10-11, elevation 12-15).
--
-- What it pins:
--   * the synthetic tile id, both directions, and where it lands on the sheet
--   * behaviour byte  -> class, for every family
--   * layer type      -> "is this cover", including the COVERED exception
--   * collision bit   -> a passable cell is never something you stand inside
--   * elevation       -> ranked heights, the transition rule, the bridge lift
--   * that Structures and ChunkMesher both survive a Gen 3 map end to end
--   * and that Gen 1 resolution is completely unchanged
--
-- Run from the repository root:
--     luajit mods/DRAMATIC_SHAPE/tests/gen3_voxel_test.lua
-- or point it somewhere else:
--     ENGINE=/path/to/engine MOD=/path/to/mod luajit .../gen3_voxel_test.lua

local ENGINE = os.getenv("ENGINE") or "."
local MOD = os.getenv("MOD") or "mods/DRAMATIC_SHAPE"
if MOD:sub(-1) ~= "/" then MOD = MOD .. "/" end
package.path = ENGINE .. "/?.lua;" .. ENGINE .. "/?/init.lua;" .. package.path

-- ---------- the mod namespace ---------------------------------------------
local V = {}
local modules, dataFiles = {}, {}
function V.require(name)
  local hit = modules[name]
  if hit ~= nil then return hit end
  local chunk = assert(loadfile(MOD .. "lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end
function V.data(name)
  local hit = dataFiles[name]
  if hit ~= nil then return hit end
  local chunk = assert(loadfile(MOD .. "data/" .. name .. ".lua"))
  local value = chunk(V)
  if name == "gen3_shapes" then value.metatiles = {} end
  dataFiles[name] = value
  return value
end

-- ---------- minimal host stubs --------------------------------------------
package.loaded["src.core.Logger"] = {
  info = function() end, warn = function() end, error = function() end,
}
package.loaded["src.render.Assets"] = {
  image = function() return nil end, imageData = function() return nil end,
  register = function() end,
}
package.loaded["src.render.PaletteFX"] = {
  usesGbcPack = function() return false end,
  hasWorldTileset = function() return false end,
}
package.loaded["src.render.TileRenderer"] = {
  defaultAnimatedTiles = function() return {} end,
  borderBlockFor = function() return nil end,
  voidFill = "trees",
  animFrame = function() return 0 end,
}

local pass, fail = 0, 0
local function ok(cond, what)
  if cond then pass = pass + 1
  else fail = fail + 1; io.write("  FAIL  ", what, "\n") end
end
local function eq(a, b, what)
  if a == b then pass = pass + 1
  else fail = fail + 1
    io.write("  FAIL  ", what, ": got ", tostring(a), ", want ", tostring(b), "\n")
  end
end

-- ---------- a synthetic Gen 3 cartridge -----------------------------------
--
-- Eight metatiles.  Attributes word = behaviour | layerType << 12.
--   0  MB_NORMAL,     layer 0 (NORMAL)  -- plain ground / a wall when blocked
--   1  MB_TALL_GRASS, layer 2 (SPLIT)   -- grass you stand in
--   2  MB_OCEAN_WATER,layer 0
--   3  MB_NORMAL,     layer 0           -- cover when blocked (a tree)
--   4  MB_JUMP_SOUTH, layer 0
--   5  MB_BRIDGE_OVER_OCEAN, layer 0
--   6  MB_NORMAL,     layer 1 (COVERED) -- a carpet: top half is ground
--   7  MB_BOOKSHELF,  layer 0
local MB = { NORMAL = 0x00, TALL_GRASS = 0x02, OCEAN_WATER = 0x15,
             JUMP_SOUTH = 0x3B, BRIDGE_OVER_OCEAN = 0x70, BOOKSHELF = 0xE1 }
local attrOf = {
  [0] = MB.NORMAL + 0 * 4096,
  [1] = MB.TALL_GRASS + 2 * 4096,
  [2] = MB.OCEAN_WATER + 0 * 4096,
  [3] = MB.NORMAL + 0 * 4096,
  [4] = MB.JUMP_SOUTH + 0 * 4096,
  [5] = MB.BRIDGE_OVER_OCEAN + 0 * 4096,
  [6] = MB.NORMAL + 1 * 4096,
  [7] = MB.BOOKSHELF + 0 * 4096,
}
local N = 8
local metabytes, attrbytes = {}, {}
for m = 0, N - 1 do
  for t = 0, 7 do
    -- every entry names tile 1 with palette 0; the pixels do not matter here
    metabytes[#metabytes + 1] = string.char(1, 0)
  end
  local a = attrOf[m]
  attrbytes[#attrbytes + 1] = string.char(a % 256, math.floor(a / 256) % 256)
end
local palettes = {}
for p = 1, 16 do
  local row = {}
  for c = 1, 16 do row[c] = { 8 * c, 4 * c, 2 * c } end
  palettes[p] = row
end
local primary = {
  id = "TILESET_TEST", tiles = string.rep("\0", 512 * 32),
  metatiles = table.concat(metabytes), attributes = table.concat(attrbytes),
  palettes = palettes, tileCount = 512, metatileCount = N,
}
_G.Game = { data = { map_tilesets = { TILESET_TEST = primary },
                     constants = { gen3Layout = { tilesInPrimary = 512,
                                                  metatilesInPrimary = N,
                                                  palettesInPrimary = 6,
                                                  metatileLayers = 2 } } } }

-- ---------- a 4x4-cell map ------------------------------------------------
--
--   row 0:  0 0 0 0     elevation 3 (datum), passable
--   row 1:  1 3 2 4     grass, TREE(blocked), water, ledge
--   row 2:  0 0 5 0     bridge at elevation 15 over the water beside it
--   row 3:  6 7 0 0     carpet(COVERED), bookshelf(blocked)
local W, H = 4, 4
local grid = { 0,0,0,0,  1,3,2,4,  0,0,5,0,  6,7,0,0 }
local collision = { 0,0,0,0,  0,1,0,0,  0,0,0,0,  0,1,0,0 }
local elevation = { 3,3,3,3,  3,3,1,3,  3,3,15,3,  5,5,3,3 }
local blocks = {}
for i = 1, W * H do
  local w = grid[i] + collision[i] * 1024 + elevation[i] * 4096
  blocks[i] = string.char(w % 256, math.floor(w / 256) % 256)
end

local tilesetDef = {
  id = "TILESET_TEST_PAIR", primaryKey = "TILESET_TEST", secondaryKey = nil,
  blockTiles = 2, blockCells = 1, metatileCount = N,
  collision = (function() local t = {} for i = 1, 255 do t[i] = i - 1 end return t end)(),
  walkable = (function() local t = {} for i = 1, 255 do t[i] = i - 1 end return t end)(),
}
local def = {
  id = "MAP_G00_N09", width = W, height = H,
  blocks = table.concat(blocks),
  collisionCells = collision, elevationCells = elevation,
  border = string.char(0, 0, 0, 0, 0, 0, 0, 0), borderBlock = 0,
  tileset = "TILESET_TEST_PAIR",
}

local Map = require("src.world.Map")
local map = Map.new(def, tilesetDef)
map.id = "MAP_G00_N09"

-- ==========================================================================
io.write("gen3 voxel\n")

local Gen3 = V.require("Gen3")

eq(Gen3.isGen3(tilesetDef), true, "a pair record identifies itself as Gen 3")
eq(Gen3.isGen3({ blockTiles = 4, blockCells = 2 }), false,
   "a Gen 1/Gen 2 tileset does not")

-- --- the synthetic tile id ------------------------------------------------
eq(Gen3.tileId(7, 0, 0), 28, "metatile 7 quadrant NW")
eq(Gen3.tileId(7, 1, 0), 29, "metatile 7 quadrant NE")
eq(Gen3.tileId(7, 0, 1), 30, "metatile 7 quadrant SW")
eq(Gen3.tileId(7, 1, 1), 31, "metatile 7 quadrant SE")
eq(Gen3.metatileOf(31), 7, "and it unfolds again")
do
  local ax, ay = Gen3.tileOrigin(Gen3.tileId(17, 1, 1), 16)
  -- metatile 17 = row 1, col 1 -> (16, 16) in cells -> SE quadrant +8,+8
  eq(ax, 16 + 8, "tile origin x")
  eq(ay, 16 + 8, "tile origin y")
end
eq(Gen3.tileCount(N), N * 4, "the tile-id space is four ids per metatile")

-- --- the per-map context --------------------------------------------------
local ctx = Gen3.forMap(map)
ok(ctx ~= nil, "Gen3.forMap builds a context")
eq(ctx.metatiles, N, "metatile count")
eq(ctx.mapName, "LittlerootTown", "the map id resolves to a pokeemerald name")
eq(ctx.primaryName, "gTileset_General", "and to its tilesets")

-- --- attributes -----------------------------------------------------------
do
  local b, l = ctx.attributes(1)
  eq(b, MB.TALL_GRASS, "behaviour byte out of the attributes word")
  eq(l, 2, "layer type out of the attributes word")
end
eq(ctx.coverAt(3), true, "layer type 0 draws its top half above the player")
eq(ctx.coverAt(6), false, "layer type 1 (COVERED) does not -- it is ground")

-- --- collision ------------------------------------------------------------
eq(ctx.blockedAt(1, 1), true, "the tree cell is blocked")
eq(ctx.blockedAt(0, 0), false, "the plain cell is not")

-- --- classes --------------------------------------------------------------
eq(ctx.classAt(0, 1), "grass", "MB_TALL_GRASS -> grass")
eq(ctx.classAt(2, 1), "water", "MB_OCEAN_WATER -> water")
eq(ctx.classAt(3, 1), "ledge", "MB_JUMP_SOUTH -> ledge")
eq(ctx.classAt(2, 2), "bridge", "MB_BRIDGE_OVER_OCEAN -> bridge")
eq(ctx.classAt(1, 3), "bookcase", "MB_BOOKSHELF -> bookcase")
eq(ctx.classAt(0, 0), "ground", "MB_NORMAL, passable -> ground")
eq(ctx.classAt(1, 1), "wall",
   "MB_NORMAL, blocked, cover above the player -> it stands up")

-- a passable cell must never resolve to something you would be standing
-- inside, whatever the behaviour row says
do
  local spec = Gen3.spec()
  ok(spec.standing.wall and spec.standing.cliff,
     "the standing set names the classes you cannot walk into")
  ok(not spec.standing.ground and not spec.standing.water
     and not spec.standing.grass and not spec.standing.ledge
     and not spec.standing.bridge and not spec.standing.log,
     "and does not name the ones you can")
  ok(spec.doors[0x69] and spec.doors[0x60],
     "doors are the exception: they rise with the facade though walkable")
  -- cell (1,3) is a bookshelf and BLOCKED; cell (0,3) is passable ground
  eq(ctx.classAt(1, 3), "bookcase", "a blocked bookshelf stays furniture")
  eq(ctx.classAt(0, 3), "ground", "and a passable cell beside it stays ground")
end

-- --- elevation ------------------------------------------------------------
-- levels present (excluding 0/1/15): 3 and 5.  Ranked, 3 is the datum.
eq(ctx.groundHeight(0, 0), 0, "elevation 3 is the datum")
eq(ctx.groundHeight(0, 3), Gen3.COURSE, "elevation 5 is one course above it")
ok(ctx.groundHeight(2, 1) < 0, "the surf level sits below the datum")
-- MB_BRIDGE_OVER_OCEAN lifts TWO courses: the bridge behaviours are an
-- ordered height index, not a flag (MetatileBehavior_GetBridgeType).
eq(ctx.groundHeight(2, 2), Gen3.COURSE * 2,
   "an ocean bridge deck stands two courses over what it spans")
ok(ctx.groundHeight(2, 2) > ctx.groundHeight(2, 1),
   "and well clear of the water beside it")

-- the lift is read off the BEHAVIOUR, so the three pond bridges differ
do
  local spec = Gen3.spec()
  ok(spec.bridge_lift[0x71] < spec.bridge_lift[0x72], "LOW lifts less than MED")
  ok(spec.bridge_lift[0x72] < spec.bridge_lift[0x73], "MED lifts less than HIGH")
  eq(spec.bridge_lift[0x7C], spec.bridge_lift[0x73],
     "a HIGH bridge's edge piece lifts with the bridge it belongs to")
end

-- ==========================================================================
io.write("gen3 x TileShape\n")

local TileShape = V.require("TileShape")
local shapes = TileShape.forMap(map)
ok(shapes ~= nil, "TileShape.forMap survives a Gen 3 pair")
eq(shapes.count, N * 4, "and sizes the tile-id space from the metatiles")
ok(shapes.coll == nil,
   "the Gen 2 collision-class table is NOT built from Gen 3 behaviour bytes")
ok(shapes.gen3 ~= nil, "the Gen 3 context rides on the shape table")

local function shapeAtCell(cx, cy)
  local tx, ty = cx * 2, cy * 2
  return TileShape.at(map, shapes, Gen3.tileAt(map, tx, ty), tx, ty)
end

do
  local s = shapeAtCell(0, 0)
  eq(s.class, "ground", "plain ground resolves")
  eq(s.h, 0, "at the datum")
  eq(s.art, "flat", "and lies flat")
end
do
  local s = shapeAtCell(0, 3)
  eq(s.class, "ground", "the raised cell is still ground")
  eq(s.h, Gen3.COURSE, "standing one course up")
end
do
  local s = shapeAtCell(1, 1)
  eq(s.class, "wall", "the blocked cover cell stands up")
  eq(s.art, "upright", "as an upright box")
  eq(s.authored, false,
     "and UNAUTHORED, so Structures may flood it and measure its real height")
end
do
  local s = shapeAtCell(2, 1)
  eq(s.class, "water", "water resolves")
  ok(s.h < 0, "and recesses")
end
do
  local s = shapeAtCell(2, 2)
  eq(s.class, "bridge", "the bridge deck resolves")
  eq(s.h, Gen3.COURSE * 2 + 4, "at its lift plus the deck's own thickness")
end
do
  local s = shapeAtCell(1, 3)
  eq(s.class, "bookcase", "a bookshelf is furniture, not wall")
end

-- every one of the four tiles of a cell must agree: the meaning is the
-- cell's, not the tile's
do
  local seen = {}
  for dy = 0, 1 do for dx = 0, 1 do
    local tx, ty = 2 + dx, 2 + dy      -- cell (1,1), the tree
    seen[TileShape.at(map, shapes, Gen3.tileAt(map, tx, ty), tx, ty).class] = true
  end end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  eq(n, 1, "all four tiles of a cell resolve to one class")
end

-- ==========================================================================
io.write("gen1/gen2 parity\n")

-- The same module set, asked about a Gen 1-shaped tileset, must behave
-- exactly as it did: no Gen 3 context, the per-tile pins built, `wall` as the
-- default for an unpinned tile.
do
  local g1tileset = {
    id = "OVERWORLD", blocks = { { 1, 1, 1, 1, 1, 1, 1, 1,
                                   1, 1, 1, 1, 1, 1, 1, 1 } },
    tilesPerRow = 16, imageWidth = 128, imageHeight = 48,
    walkable = { 0 }, waterTiles = {}, grassTile = 3,
  }
  local g1def = { id = "PALLET_TOWN", width = 1, height = 1,
                  blocks = { 0 }, borderBlock = 0, tileset = "OVERWORLD" }
  local g1map = Map.new(g1def, g1tileset)
  g1map.id = "PALLET_TOWN"
  local g1shapes = TileShape.forMap(g1map)
  eq(g1shapes.count, 96, "a Gen 1 atlas still sizes 128/8 * 48/8")
  ok(g1shapes.gen3 == nil, "and carries no Gen 3 context")
  eq(g1shapes[3].class, "grass", "the derived grass pin still fires")
  eq(g1shapes[0].class, "ground", "the Gen 1 walkable-tile pin still fires")
  local walls = 0
  for t = 0, 95 do
    if g1shapes[t] and g1shapes[t].class == "wall" then walls = walls + 1 end
  end
  ok(walls > 0, "and unpinned Gen 1 tiles still default to wall (" .. walls .. ")")
end

-- ==========================================================================
io.write("gen3 x Structures\n")

-- The pass that actually crashed first on Gen 3: it reads `tileset.blocks`
-- for the border ring, `tileset.image` for pixels, and `map:tileAt` for every
-- cell of the body and a twelve-tile apron -- and a Gen 3 pair has none of
-- the first two.
do
  local okS, S = pcall(function()
    return V.require("Structures").forMap(map)
  end)
  ok(okS, "Structures.forMap survives a Gen 3 map" ..
     (okS and "" or (": " .. tostring(S))))
  if okS and S then
    ok(S.shapeAt ~= nil and S.tileAt ~= nil, "and resolves the grid")
    local n = 0
    for _ in pairs(S.shapeAt) do n = n + 1 end
    ok(n >= W * 2 * H * 2, "covering at least the body (" .. n .. " tiles)")
    -- the blocked cover cells are the ones the volume builder must have
    -- measured: cell (1,1) is a tree, cell (1,3) a bookshelf
    local keyOf = function(tx, ty) return (ty + 64) * 4096 + (tx + 64) end
    local treeShape = S.shapeAt[keyOf(2, 2)]
    ok(treeShape ~= nil and treeShape.class == "wall",
       "the tree cell is upright in the resolved grid")
    ok(S.runs ~= nil, "and a run table exists")
  end
end

-- ==========================================================================
io.write("gen3 x ChunkMesher\n")

-- The geometry pass, headless.  This is what proves the UVs land on the right
-- part of the sheet: on Gen 3 the atlas is 16x16 metatiles and every `v`
-- coordinate is divided by the SHEET height, so a mesher that still thinks
-- the sheet is 48px tall puts every quad in the world off the top of it.
do
  local CM = V.require("ChunkMesher")
  local okG, verts, idx, n = pcall(CM.geometry, map, true, nil, false)
  ok(okG, "ChunkMesher.geometry survives a Gen 3 map" ..
     (okG and "" or (": " .. tostring(verts))))
  if okG and verts then
    ok(n and n > 0, "and emits geometry (" .. tostring(n) .. " vertices)")
    -- FORMAT is {x,y,z, u,v, shade}: every u and v must be inside the sheet
    local worstU, worstV = 0, 0
    for i = 1, #verts do
      local vtx = verts[i]
      local u, v = vtx[4], vtx[5]
      if u and u > worstU then worstU = u end
      if v and v > worstV then worstV = v end
    end
    ok(worstU <= 1.0001, "no u runs off the sheet (max " ..
       string.format("%.3f", worstU) .. ")")
    ok(worstV <= 1.0001, "no v runs off the sheet (max " ..
       string.format("%.3f", worstV) .. ")")
    -- and the sheet is really the metatile sheet, not the 128x48 fallback:
    -- 8 metatiles at 16 per row is one row -> 128 x 16.  A quad on metatile 7
    -- must reach past v = 0.5 of a 16px-tall sheet.
    ok(worstV > 0.4, "and the v range spans the real sheet height")
  end
end

-- ==========================================================================
io.write("gen3 with NO context (the degraded path)\n")

-- THE REGRESSION THIS SECTION EXISTS FOR.
--
-- `Gen3.forMap` can return nil for reasons that have nothing to do with the
-- shape of the world -- in the field it was a lookup bug (`_G.Game` is nil in
-- a real session; the engine's Game is a module). When it did, every branch
-- that had been gated on the CONTEXT rather than on "is this tileset Gen 3"
-- fell through into the Gen 1/Gen 2 arm and indexed `tileset.blocks`, which
-- no pair record has:
--
--     Structures.lua:310: attempt to index field 'blocks' (a nil value)
--
-- ...which failed the mesh build, cached `false`, and left the map flat
-- forever. A missing context must degrade, never fault.
do
  local Gen3b = V.require("Gen3")
  local savedGame = _G.Game
  _G.Game = { data = {} }                 -- no map_tilesets: context cannot build
  Gen3b.invalidate()
  V.require("TileShape").invalidate()
  V.require("Structures").invalidate()

  local ctx2 = Gen3b.forMap(map)
  ok(ctx2 == nil, "with no tileset store the context does not build")
  ok(Gen3b.isGen3(tilesetDef),
     "but the tileset still identifies itself as Gen 3 -- a pure record test")

  local okShapes, shapes2 = pcall(V.require("TileShape").forMap, map)
  ok(okShapes, "TileShape.forMap survives a Gen 3 map with no context" ..
     (okShapes and "" or (": " .. tostring(shapes2))))
  if okShapes then
    ok(shapes2.count > 96,
       "and still sizes the id space for METATILES, not Gen 1's 96 tiles (" ..
       tostring(shapes2.count) .. ")")
    ok(shapes2.coll == nil,
       "and still refuses to read behaviour bytes through Gen 2's table")
    local s2 = TileShape.at(map, shapes2, Gen3.tileAt(map, 0, 0), 0, 0)
    ok(s2 ~= nil and (s2.class == "ground" or s2.class == "wall"),
       "a cell degrades to ground/wall from passability rather than inventing")
  end

  local okStruct, S2 = pcall(V.require("Structures").forMap, map)
  ok(okStruct, "Structures.forMap survives it too -- this is the crash" ..
     (okStruct and "" or (": " .. tostring(S2))))

  local okMesh, verts = pcall(V.require("ChunkMesher").geometry, map, true, nil, false)
  ok(okMesh, "and the geometry pass survives it" ..
     (okMesh and "" or (": " .. tostring(verts))))

  -- AND THE UVs MUST STILL LAND ON THE SHEET.  This is the check that pins
  -- the reported artefact: with the atlas size taken from the Gen 1 defaults
  -- (16 tiles per row, 128x48) over a sheet that is really 256 wide and up to
  -- 656 tall, v runs to about 13.6 -- so every ground quad sampled the whole
  -- sheet thirteen times over and the world came out in fine horizontal
  -- stripes, with the cells past the id space simply black.
  if okMesh and verts then
    local worstU, worstV = 0, 0
    for i = 1, #verts do
      local u, v2 = verts[i][4], verts[i][5]
      if u and u > worstU then worstU = u end
      if v2 and v2 > worstV then worstV = v2 end
    end
    ok(worstU <= 1.0001, "u stays on the sheet with no context (max " ..
       string.format("%.2f", worstU) .. ")")
    ok(worstV <= 1.0001, "v stays on the sheet with no context (max " ..
       string.format("%.2f", worstV) .. ") -- >1 is the striping")
  end

  _G.Game = savedGame
  Gen3b.invalidate()
  V.require("TileShape").invalidate()
  V.require("Structures").invalidate()
end

-- ==========================================================================
io.write("gen3 roof art band\n")

-- HOW MANY ROWS OF THE DRAWING A STATED ROOF WEARS.
--
-- `gen3RoofRows` is the above-player layer read down a COLUMN, and on a great
-- many Gen 3 houses that layer runs a course or two into the facade, so the
-- roof surface came out wearing the top of the wall.  `gen3PlanRows` is the
-- same count taken off the ROW, which a mixed facade row refuses.  The rule
-- CAPS the first with the second; it never swaps them, because neither signal
-- is the drawn roof depth on its own.
--
-- The numbers below are MEASURED off the cartridge art, column by column --
-- see the doc comment on `Structures.gen3RoofArtRows` for where each one was
-- read.  They are the three buildings the rule was derived from.
do
  local Structures = V.require("Structures")
  local band = Structures.gen3RoofArtRows

  -- PalletTown, Oak's Lab, building 3 (13..19, 10..13), column tx = 34.
  -- Drawing rows 20..27: 20..23 grey shingle, 24..26 pale yellow wall
  -- (246,238,197), 27 the base course.  Four rows of roof; the layer states
  -- six, and six is what the band used to be.
  local rows, capped = band(6, 4, 0, 2)
  eq(rows, 4, "Oak's Lab: the layer's six roof rows cap to the plan's four")
  ok(capped, "and the run records that the cap fired")

  -- ViridianCity, Pokemon Centre, building 1 (24..28, 23..26), column tx = 52.
  -- Drawing rows 46..53: 46..49 red vault, 50..51 the white band, 52..53 blue.
  -- Four rows of roof again -- but here the PLAN reads two, so a rule that
  -- swapped the signals would halve it.  The cap cannot lengthen a band, and
  -- the Centre's own roof depth holds the floor.
  eq((band(6, 2, 0, 4)), 4,
     "the Pokemon Centre keeps four: the cap never goes below the roof's "
     .. "own built depth")

  -- LilycoveCity, Department Store, building 1 (23..31, 0..6), column tx = 54.
  -- Fourteen tile rows of drawing and NOT ONE of them is roof: three rows of
  -- windows, the Poke Ball emblem, the awnings and the door, all face-on.
  -- The layer states twelve, and the whole shopfront was laid flat on the
  -- roof deck.
  local storeRows, storeCapped = band(12, 2, 0, 2)
  eq(storeRows, 2, "the Department Store's twelve rows of shopfront cap to two")
  ok(storeCapped,
     "and a band the cap shortened all the way to the roof's depth is still "
     .. "recorded, so the run never loses its art entirely")

  -- ViridianCity, building 2 (24..28, 9..11) states `planRows = 0`.  A
  -- plan-based cap that fired there would leave the building with no roof art
  -- at all -- the failure the run builder's `statedFloor` guard is written
  -- against, which this rule must not reopen.
  local noPlanRows, noPlanCapped = band(4, 0, 0, 2)
  eq(noPlanRows, 4, "a building whose plan states nothing keeps the layer's count")
  ok(not noPlanCapped, "and is not recorded as capped")

  -- a folded walkable roof course belongs to both counts, so it cancels out
  -- of the comparison and is added back once.
  eq((band(6, 4, 2, 2)), 6, "a folded course is carried by both readings")

  -- the cap only ever SHORTENS: a plan deeper than the layer changes nothing.
  eq((band(4, 8, 0, 2)), 4, "a plan deeper than the layer never lengthens the band")

  -- and nil inputs (a run with no stated roof at all) do not throw
  eq((band(nil, nil, nil, nil)), 0, "an unstated roof reads zero rows")
end

-- ==========================================================================
io.write("gen3 roof plan: a footprint that is not the top of its drawing\n")

-- A ROOF IS AT THE TOP OF A BUILDING'S DRAWING.
--
-- `gen3RoofPlanAt` asks whether a footprint row is drawn above the player
-- right across itself, and a tall glass curtain wall answers yes exactly as a
-- rooftop does -- nothing in the art separates them (Lilycove's Contest Hall
-- rooftop and the Battle Tower's curtain wall carry the SAME role row,
-- `surface / cap 0 / face 0`).  Where the footprint sits in the drawing does.
--
-- The numbers below are MEASURED, over all 344 warp-named buildings on the
-- outdoor maps of both cartridges: the shallowest column's continuation above
-- the footprint is 0 rows for 341 of them, 1 row for one, and 5 or 6 for the
-- two glass towers.  See the doc comment on `gen3RoofPlanAt`.
do
  local Structures = V.require("Structures")
  local overtop = Structures.gen3PlanOvertop

  -- SaffronCity's SILPH CO, building 1 (29..37, 22..30), nine columns.  The
  -- tower's slatted upper storeys and its dome carry on for five more cell
  -- rows above y = 22, so the footprint holds no roof and all nine of its
  -- rows are wall.
  ok(overtop({ 5, 5, 5, 5, 5, 5, 5, 5, 5 }),
     "Silph Co: every column of the footprint has five more rows above it")

  -- BattleFrontier_OutsideEast's BATTLE TOWER, building 1 (11..21, 6..14),
  -- eleven columns, six rows of drawing above the footprint -- the Hoenn
  -- control, and the only Hoenn building this rule moves.
  ok(overtop({ 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6 }),
     "the Battle Tower: eleven columns, six rows above each")

  -- VIRIDIAN FOREST's south gate, building 1 (3..7, 1..9), is the near miss:
  -- its corrugated roof really is its own top and is simply CUT by the map
  -- edge at y = 0, one row above the footprint.  It keeps every roof row.
  ok(not overtop({ 1, 1, 1, 1, 1 }),
     "Viridian Forest's gate is clipped by the map edge, not overbuilt")

  -- Lilycove's CONTEST HALL (20..26, 19..24) and every other building in
  -- Hoenn: nothing of the building is drawn above its own footprint.
  ok(not overtop({ 0, 0, 0, 0, 0, 0, 0 }),
     "a footprint that is the top of its drawing keeps its roof plan")

  -- ONE column that stops is enough: the rule refuses unless the whole
  -- footprint is overbuilt, so a building banked against a cliff or a tree
  -- line on one flank is not read as a tower.
  ok(not overtop({ 5, 5, 0, 5 }),
     "one column whose drawing stops at the footprint answers no")

  ok(not overtop({}), "an empty footprint answers no")
  ok(not overtop(nil), "and so does no footprint at all")
end

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
