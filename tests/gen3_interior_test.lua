-- Interiors: metatile pins, and the elevation that is not height.
-- Runs against the REAL Brendan's House layouts out of the extracted data.
-- The engine tree this suite runs against.  Defaults to the current
-- directory, so the suite runs from a repository checkout on any
-- machine; override with ENGINE=... to point it somewhere else.  It
-- used to name a scratch directory that exists only on one
-- contributor's box, which meant this suite loaded src/* from THAT
-- tree no matter what MOD said.
local ENGINE = os.getenv("ENGINE") or "."
package.path = ENGINE .. "/?.lua;" .. ENGINE .. "/?/init.lua;" .. package.path
-- The mod under test.  Defaults to the tree this suite ships in, so the
-- suite runs from a checkout on any machine; override with MOD=... to
-- point it somewhere else.  It used to name a scratch directory that
-- exists only on one contributor's box, so four of the six suites were
-- silently measuring a stale copy -- and reported green while the tree
-- they were meant to cover was failing.
local MOD = os.getenv("MOD") or "mods/DRAMATIC_SHAPE"
if MOD:sub(-1) ~= "/" then MOD = MOD .. "/" end
local GEN = "/mnt/user-data/uploads/Gen2Recomp/emerald/data/generated/"
_G.love = require("tests.love_stub")

-- REAL ImageData storage, the same stub gen3_scenery_test carries and for
-- the same reason: `Structures.buildGen3Joinery` reads the baked carve back
-- through getPixel, and a no-op setPixel is exactly the thing that would let
-- a hollow carve pass for a working one.
local function obj(t)
  return setmetatable(t or {}, { __index = function() return function() end end })
end
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
local mods, dats = {}, {}
function V.require(n)
  local h = mods[n]; if h ~= nil then return h end
  local v = assert(loadfile(MOD .. "lib/" .. n .. ".lua"))(V); mods[n] = v; return v
end
function V.data(n)
  local h = dats[n]; if h ~= nil then return h end
  local v = assert(loadfile(MOD .. "data/" .. n .. ".lua"))(V); dats[n] = v; return v
end

local tilesets = assert(loadfile(GEN .. "tilesets.lua"))()
local mapts    = assert(loadfile(GEN .. "map_tilesets.lua"))()
local consts   = assert(loadfile(GEN .. "constants.lua"))()
local layouts  = assert(loadfile(GEN .. "map_layouts.lua"))()
_G.Game = { data = { tilesets = tilesets, map_tilesets = mapts,
                     constants = consts, maps = {} } }

local pass, fail = 0, 0
local function eq(a, b, w)
  if a == b then pass = pass + 1 else fail = fail + 1
    io.write("  FAIL  ", w, ": got ", tostring(a), " want ", tostring(b), "\n") end
end
local function ok(c, w)
  if c then pass = pass + 1 else fail = fail + 1; io.write("  FAIL  ", w, "\n") end
end

local Map = require("src.world.Map")
local PAIR = "TILESET_03DF884_03DFAF4"
local function houseMap(layoutIndex, mapId)
  local lay = layouts[layoutIndex]
  local def = { id = mapId, width = lay.width, height = lay.height,
                blocks = lay.blocks, collisionCells = lay.collisionCells,
                elevationCells = lay.elevationCells, border = lay.border,
                borderBlock = 0, tileset = PAIR }
  local m = Map.new(def, tilesets[PAIR])
  m.id = mapId
  return m
end

local Gen3 = V.require("Gen3")
local TileShape = V.require("TileShape")

io.write("Brendan's House 1F -- the kitchen and the dining set\n")
local m1 = houseMap(54, "MAP_G01_N00")
local ctx1 = Gen3.forMap(m1)
ok(ctx1 ~= nil, "the 1F context builds")
eq(ctx1.mapName, "LittlerootTown_BrendansHouse_1F", "and names the map")
eq(ctx1.secondaryName, "gTileset_BrendansMaysHouse", "and its tileset")
ok(ctx1.pins ~= nil, "so the metatile pins resolve")

local shapes1 = TileShape.forMap(m1)
local function classAtCell(map, shapes, cx, cy)
  local tx, ty = cx * 2, cy * 2
  local s = TileShape.at(map, shapes, Gen3.tileAt(map, tx, ty), tx, ty)
  return s and s.class, s
end

-- the kitchen front row, y=2: fridge, sink, worktop, cabinet, cabinet
do
  local want = { [0] = "appliance", [1] = "sink", [2] = "worktop",
                 [3] = "cabinet", [4] = "cabinet" }
  for x, w in pairs(want) do
    local c, s = classAtCell(m1, shapes1, x, 2)
    eq(c, w, ("kitchen cell (%d,2) is a %s"):format(x, w))
    ok(s and s.authored == true,
       ("...and is AUTHORED so it leaves the wall flood (%d,2)"):format(x))
  end
end
-- the wall band above it must NOT be pinned -- it has to stay in the flood
do
  local c, s = classAtCell(m1, shapes1, 0, 1)
  eq(c, "wall", "the unit's upper door stays part of the wall")
  eq(s.authored, false, "and UNAUTHORED, so the wall still measures as one run")
end
-- the dining set
do
  eq(classAtCell(m1, shapes1, 3, 6), "tabletop", "the table cloth is a table")
  eq(classAtCell(m1, shapes1, 2, 6), "chair", "with a chair beside it")
  eq(classAtCell(m1, shapes1, 5, 6), "chair", "and one on the other side")
  local _, s = classAtCell(m1, shapes1, 2, 6)
  ok(s.art == "top", "a chair's art rides its top face -- it is drawn from above")
  ok(s.h > 0 and s.h <= 10, "at seat height (" .. tostring(s.h) .. ")")
  ok(m1:isWalkableCell(2, 6), "and the chair cell is PASSABLE, as Emerald leaves it")
end
-- the fridge is taller than the worktop, and both are uprights
do
  local _, fridge = classAtCell(m1, shapes1, 0, 2)
  local _, top    = classAtCell(m1, shapes1, 2, 2)
  ok(fridge.h > top.h, "the fridge stands taller than the counter (" ..
     fridge.h .. " > " .. top.h .. ")")
  eq(fridge.art, "upright", "and folds its face-on art up its south side")
end

-- ---- AND THE GEOMETRY THAT FOLD ACTUALLY BUILDS (g3-upright).
--
-- The report: "many of the interior objects aren't properly rotated in 3d to
-- stand up", naming Pallet Town's house and Oak's Lab -- and the same defect
-- is in this kitchen.  `Structures.buildGen3Joinery` read every one of its
-- classes as a PLAN: the fridge's two doors and their handles were laid FLAT
-- on the lid of a 32px box, facing the sky.  Measured here before the fix:
-- the fridge cell carried 32 horizontal quads (one run per drawn row of
-- metatile 568) and 12 upright ones.
--
-- `JOINERY_ELEVATION` now splits the vocabulary in two.  An elevation stands
-- its drawing up the front and puts ONE texel row on the cap; a plan is
-- untouched and still rides the lid.  Both halves are asserted, because the
-- thing that could go wrong is either one moving alone.
io.write("Brendan's House 1F -- elevations stand, plans stay on the lid\n")
do
  local Structures = V.require("Structures")
  Structures.invalidate()
  local okS, S = pcall(Structures.forMap, m1)
  ok(okS and S ~= nil, "Structures builds the kitchen" ..
     (okS and "" or (": " .. tostring(S))))
  local cell = {}
  for _, q in ipairs((okS and S and S.objectQuads) or {}) do
    local x0, z0, z1 = math.huge, math.huge, -math.huge
    local ymin, ymax = math.huge, -math.huge
    for i = 1, 4 do
      local v = q[i]
      if v[1] < x0 then x0 = v[1] end
      if v[3] < z0 then z0 = v[3] end
      if v[3] > z1 then z1 = v[3] end
      if v[2] < ymin then ymin = v[2] end
      if v[2] > ymax then ymax = v[2] end
    end
    local k = math.floor(z0 / 16) * 64 + math.floor(x0 / 16)
    local c = cell[k]
    if not c then
      c = { flat = 0, up = 0, deepCap = 0, ymin = math.huge, ymax = -math.huge }
      cell[k] = c
    end
    if ymin == ymax then
      c.flat = c.flat + 1
      -- a cap laid ACROSS the depth, not a pixel run of the drawing
      if z1 - z0 > 8 then c.deepCap = c.deepCap + 1 end
    else
      c.up = c.up + 1
    end
    if ymin < c.ymin then c.ymin = ymin end
    if ymax > c.ymax then c.ymax = ymax end
  end
  local function at(cx, cy) return cell[cy * 64 + cx] end

  -- the FRIDGE at (0, 2): metatile 568 over 560, class `appliance`
  local f = at(0, 2)
  ok(f ~= nil, "the fridge cell builds quads")
  if f then
    ok(f.up > 100, "and they are UPRIGHT -- the drawing stands (" ..
       f.up .. " upright)")
    eq(f.flat, 2, "with a cap of two quads and no picture on the lid")
    eq(f.deepCap, 2, "each laid across the whole depth of the cell")
    eq(f.ymin, 0, "the fridge stands on the floor")
    eq(f.ymax, 32, "and reaches the height its class states")
  end

  -- the GLASS DRESSER at (3..4, 2): 571/572 over 563/564, class `cabinet`
  for _, cx in ipairs({ 3, 4 }) do
    local c = at(cx, 2)
    ok(c ~= nil and c.up > 100,
       ("the dresser cell (%d,2) stands its drawing up"):format(cx))
    ok(c ~= nil and c.flat <= 4,
       ("...and wears a cap, not the picture (%d,2)"):format(cx))
  end

  -- THE PLANS DID NOT MOVE.  569 draws a basin seen from above and 570 a hob
  -- with a pot on it; both stay on the lid, which is what the earlier report
  -- ("the sink should be like a counter height") asked for.
  for _, w in ipairs({ { 1, "sink" }, { 2, "worktop" } }) do
    local c = at(w[1], 2)
    ok(c ~= nil and c.flat > 10,
       ("the %s still rides its lid (%d flat)"):format(w[2],
        c and c.flat or -1))
    eq(c and c.ymax, 16, ("...at counter height (%s)"):format(w[2]))
  end
end

io.write("Brendan's House 2F -- the bed, the TV, and the step that isn't there\n")
local m2 = houseMap(55, "MAP_G01_N01")
local ctx2 = Gen3.forMap(m2)
eq(ctx2.mapName, "LittlerootTown_BrendansHouse_2F", "the 2F map is named")
eq(ctx2.outdoor, false, "and known to be indoors")

-- THE REGRESSION: two cells of this bedroom carry elevation 4, which ranked
-- into a 16px slab standing in the middle of the carpet.
do
  local raised = 0
  for cy = 0, m2.def.height - 1 do
    for cx = 0, m2.def.width - 1 do
      if ctx2.groundHeight(cx, cy) ~= 0 then raised = raised + 1 end
    end
  end
  eq(raised, 0, "no cell indoors is raised -- elevation is sprite priority here")
  ok(ctx2.elevationAt(0, 5) == 4,
     "even though the map really does carry elevation 4 there")
end

local shapes2 = TileShape.forMap(m2)
do
  eq(classAtCell(m2, shapes2, 1, 4), "bed", "the bed is a bed")
  local _, s = classAtCell(m2, shapes2, 1, 4)
  ok(s.art == "top", "drawn from above")
  ok(s.h > 0 and s.h < 12, "and low (" .. tostring(s.h) .. ")")
  -- (3,2) IS THE GAME SYSTEM, metatile 614 -- not the television.  The
-- label below said "television" from before the two were told apart:
-- the real set is metatile 2 of gTileset_Building (MB_TELEVISION),
-- and class `tv` is the white box beside it.  Reported from play,
-- "make the gamesystem a 2d sprite", so 614/615 are pinned `cutout`
-- and build one world pixel thick.  The assertion follows the pin.
  eq(classAtCell(m2, shapes2, 3, 2), "cutout", "the game system is a flat sprite")
  local _, t = classAtCell(m2, shapes2, 3, 2)
  ok(t.authored == true, "authored, so it does not drag the wall forward")
  eq(classAtCell(m2, shapes2, 0, 2), "chair", "and the stool is a stool")
end
-- the rug must stay flat
do
  local c, s = classAtCell(m2, shapes2, 5, 4)
  eq(c, "ground", "the carpet is still flat ground")
  eq(s.h, 0, "at the datum")
end

io.write("gen1/gen2 untouched\n")
do
  local g1ts = { id = "OVERWORLD", blocks = { { 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1 } },
                 tilesPerRow = 16, imageWidth = 128, imageHeight = 48,
                 walkable = { 0 }, waterTiles = {}, grassTile = 3 }
  local g1 = Map.new({ id = "PALLET_TOWN", width = 1, height = 1, blocks = { 0 },
                       borderBlock = 0, tileset = "OVERWORLD" }, g1ts)
  g1.id = "PALLET_TOWN"
  local sh = TileShape.forMap(g1)
  ok(sh.gen3 == nil, "a Gen 1 map has no Gen 3 context")
  eq(sh.count, 96, "and its tile-id space is unchanged")
  eq(sh[3].class, "grass", "and its derived pins still fire")
end

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
