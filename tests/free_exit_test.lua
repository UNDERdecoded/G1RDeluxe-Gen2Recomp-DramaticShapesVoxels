-- THE FREE WALK MUST BE ABLE TO LEAVE A BUILDING.
--
-- Reported from play: "first and third person not able to exit buildings in
-- gen2".  In 1ST and 3RD the walk is FreeMove's, not the grid's, and its
-- blocked-push block restated three of the engine's five blocked-step verbs.
-- The two it left out -- checkGen2CarpetExit and checkGen3ArrowWarp -- are
-- exactly the two a DIRECTIONAL EXIT MAT answers to, and on a mat nothing
-- else answers at all: Warp.onArrive refuses the carpet on purpose (that is
-- what stops a two-cell mat being a trapdoor), and checkEdgeExit and the
-- blocked-step Warp.onCollision are both gated on standingOnWarp, which
-- refreshStandingOnWarp clears for precisely these cells.  So the player
-- stood on the Center's mat pushing south and never went anywhere, while the
-- grid walk on the identical cell walked out on the first frame.
--
-- The buildings are built here rather than loaded, the way
-- tests/engine/gen3_arrow_warp.lua builds its Hoenn fixture, so the suite
-- needs no ROM and no dataset: a Johto Pokemon Center's bottom row (two
-- COLL_WARP_CARPET_DOWN cells with the map edge beneath them), the same row
-- in Hoenn (MB_SOUTH_ARROW_WARP), and Red's house (a door tile, which is the
-- case that always worked and must keep working).

-- The engine tree this suite runs against.  Defaults to the current
-- directory; override with ENGINE=... .
local ENGINE = os.getenv("ENGINE") or "."
package.path = ENGINE .. "/?.lua;" .. ENGINE .. "/?/init.lua;" .. package.path
-- The mod under test.  Defaults to the tree this suite ships in; override
-- with MOD=... .
local MOD = os.getenv("MOD") or "mods/DRAMATIC_SHAPE"
if MOD:sub(-1) ~= "/" then MOD = MOD .. "/" end
_G.love = require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local Map  = require("src.world.Map")
local OW   = require("src.world.OverworldController")

local pass, fail = 0, 0
local function ok(c, w)
  if c then pass = pass + 1 else fail = fail + 1; io.write("  FAIL  ", w, "\n") end
end
local function eq(a, b, w)
  if a == b then pass = pass + 1 else fail = fail + 1
    io.write("  FAIL  ", w, ": got ", tostring(a), " want ", tostring(b), "\n") end
end

-- ------------------------------------------------------------- the world
--
-- Enough of Game for the walk: the pad, the bike flag, and the three field
-- tables FreeMove reads.  OverworldController keeps its own `Game` as a
-- file-local it assigns only inside :enter, and this suite never enters a
-- map, so that upvalue is bound by hand.
local Game = require("src.core.Game")
Game.save = { onBike = false, options = {}, party = {} }
Game.data = { field = { warpCarpets = nil, forcedMovement = { slopeMaps = {} },
                        tilePairs = { land = {}, water = {} },
                        boot = { screens = {} } },
              maps = {}, constants = {}, tilesets = {} }
local held = {}
Game.input = { isDown = function(_, k) return held[k] == true end,
               wasPressed = function() return false end,
               state = held, pressQueue = {} }
_G.Game = Game
do
  local i = 1
  while true do
    local n = debug.getupvalue(OW.handleInput, i)
    if not n then error("OverworldState.handleInput has no Game upvalue") end
    if n == "Game" then debug.setupvalue(OW.handleInput, i, Game) break end
    i = i + 1
  end
end

-- ----------------------------------------------- the mod, stubbed to the walk
--
-- FreeMove asks FirstPerson for the camera bearing and Horde whether world
-- input is suppressed, and nothing else of the mod takes part in a step.
local bearing = { wx = 0, wz = 1 }
local V = {}
local stubs = {
  FirstPerson = {
    driving = function() return true end,
    releaseBody = function() end,
    moveVector = function() return 0, 1 end,
    moveWorld = function() return bearing.wx, bearing.wz end,
    -- the real one quantises a bearing to the four compass points
    pointBody = function(wx, wz)
      if (wx or 0) == 0 and (wz or 0) == 0 then return "down" end
      if math.abs(wx) > math.abs(wz) then return wx > 0 and "right" or "left" end
      return wz > 0 and "down" or "up"
    end,
  },
  Horde = { suppressWorldInput = function() return false end },
}
function V.require(n) return assert(stubs[n], "unstubbed mod module: " .. tostring(n)) end
local FreeMove = assert(loadfile(MOD .. "lib/FreeMove.lua"))(V)

-- ----------------------------------------------------------- the buildings
--
-- Five blocks by four -- 10 x 8 collision cells -- with the exit mat at (3,7)
-- and (4,7) on the bottom row and the map edge beneath it, which is what a
-- doormat backs onto.  Gen 1 and Gen 2 read four collision classes per block
-- (NW, NE, SW, SE); block 0 always reads as wall, so the ids start at 1.
local function fourCellMap(id, matClass, floor, wall, doorTiles, warpTiles)
  local B = {
    [1] = { floor, floor, floor, floor },      -- floor
    [2] = { wall,  wall,  wall,  wall  },      -- wall
    [3] = { floor, floor, floor, matClass },   -- (3,7) is this block's SE cell
    [4] = { floor, floor, matClass, floor },   -- (4,7) is this block's SW cell
  }
  local coll = {}
  for b = 0, 4 do
    local q = B[b] or { wall, wall, wall, wall }
    for i = 1, 4 do coll[b * 4 + i] = q[i] end
  end
  local pair = { id = "TS_" .. id, blockTiles = 4, blockCells = 2,
                 metatileCount = 5, collision = coll,
                 walkable = { floor, matClass },
                 doorTiles = doorTiles or {}, warpTiles = warpTiles or {} }
  local GRID = { { 2, 2, 2, 2, 2 }, { 2, 1, 1, 1, 2 },
                 { 2, 1, 1, 1, 2 }, { 2, 3, 4, 1, 2 } }
  local packed = {}
  for by = 1, 4 do
    for bx = 1, 5 do
      packed[#packed + 1] = string.char(GRID[by][bx] % 256, 0)
    end
  end
  return Map.new({ id = id, width = 5, height = 4,
                   blocks = table.concat(packed), borderBlock = 2,
                   tileset = "TS_" .. id, environment = 3,
                   warps = { { x = 3, y = 7, destMap = "LAST_MAP", destWarp = 1 },
                             { x = 4, y = 7, destMap = "LAST_MAP", destWarp = 1 } } },
                 pair)
end

-- A Gen 3 pair says what it is: one metatile IS one collision cell, one
-- behaviour byte each, and warpsAreEvents makes the warp event the whole warp.
local function gen3Map(id)
  local pair = { id = "TS_" .. id, blockTiles = 2, blockCells = 1,
                 metatileCount = 3, warpsAreEvents = true, behaviourBytes = true,
                 doorTiles = { 0x60, 0x69, 0x6C },
                 collision = { 0x00, 0x65, 0x01 },   -- normal, south arrow, wall
                 walkable = (function()
                   local a = {}
                   for b = 0, 254 do a[b + 1] = b end
                   return a
                 end)() }
  local W, H = 10, 8
  local meta, cells, packed = {}, {}, {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local i = y * W + x + 1
      local isWall = (x == 0 or x == W - 1 or y == 0)
      meta[i], cells[i] = isWall and 3 or 1, isWall and 1 or 0
      if y == H - 1 and (x == 3 or x == 4) then meta[i], cells[i] = 2, 0 end
    end
  end
  for i = 1, W * H do packed[i] = string.char((meta[i] - 1) % 256, 0) end
  return Map.new({ id = id, width = W, height = H,
                   blocks = table.concat(packed), collisionCells = cells,
                   borderBlock = 0, tileset = "TS_" .. id,
                   warps = { { x = 3, y = 7, destMap = "LAST_MAP", destWarp = 1 },
                             { x = 4, y = 7, destMap = "LAST_MAP", destWarp = 1 } } },
                 pair)
end

-- --------------------------------------------------------------- the drive
local taken
local function newState(map, cx, cy)
  local st = setmetatable({}, { __index = OW })
  st.map, st.entities, st.cast = map, {}, {}
  st.npcs, st.boulders, st.scriptMoves = {}, {}, {}
  st.bumpCooldown = 0
  st.player = { cellX = cx, cellY = cy, px = cx * 16, py = cy * 16,
                facing = "down", moving = false, inputLocked = false,
                surfing = false }
  st.takeWarp = function(_, d) taken = d; return true end
  -- onStepComplete's tail is the only part of it this question turns on (the
  -- refreshStandingOnWarp at OverworldController.lua:9886); the whole of it
  -- wants a booted save and data tree.
  st.onStepComplete = function(self) self:refreshStandingOnWarp() end
  local Collision = require("src.world.Collision")
  st.player.tryMove = function(pl, dir, m, ents)
    pl.facing = dir
    local moved, why = Collision.canMove(m, ents, pl, dir)
    if not moved then return "blocked", why end
    local tx, ty = Collision.target(pl.cellX, pl.cellY, dir)
    pl.cellX, pl.cellY, pl.px, pl.py = tx, ty, tx * 16, ty * 16
    return "moved"
  end
  return st
end

-- Hold south on the free walk for as many frames as it takes to cross a cell
-- and be clamped against whatever refuses; returns the warp taken, or nil.
local function freeWalkSouth(map, cx, cy)
  taken, bearing.wx, bearing.wz = nil, 0, 1
  local st = newState(map, cx, cy)
  st:refreshStandingOnWarp()
  FreeMove.drop()
  for _ = 1, 40 do
    FreeMove.tick(st)
    if taken then break end
  end
  return taken, st
end

-- ...and the same thing on the grid, which is the reference behaviour.
local function gridWalkSouth(map, cx, cy)
  taken = nil
  local st = newState(map, cx, cy)
  st:refreshStandingOnWarp()
  for k in pairs(held) do held[k] = nil end
  held.down = true
  for _ = 1, 8 do
    pcall(function() st:handleInput() end)
    if taken then break end
  end
  for k in pairs(held) do held[k] = nil end
  return taken, st
end

-- ======================================================= GEN 2, the report
io.write("gen2: a Johto exit mat answers the free walk\n")
GameVersion.set("gold")
do
  local map = fourCellMap("CHERRYGROVE_POKECENTER_1F", 0x70, 0x00, 0x01)

  -- the fixture is the cell the cartridge describes
  eq(map:cellTile(3, 7), 0x70, "the mat's west cell is COLL_WARP_CARPET_DOWN")
  eq(map:cellTile(4, 7), 0x70, "and so is its east cell")
  ok(Map.gen2IsDirectionalCarpet(map:cellTile(3, 7)),
     "which gen2IsDirectionalCarpet calls a carpet")
  ok(map:speaksGen2Collision(), "on a tileset that speaks collision classes")
  ok(not map:inBounds(3, 8), "and south of the mat is off the map")

  -- ...and the three shut doors that make this the only way out
  local st = newState(map, 3, 7)
  st:refreshStandingOnWarp()
  eq(st.standingOnWarp, false,
     "a fresh refreshStandingOnWarp clears the flag on a carpet")
  eq(st:canCollisionWarp(), false,
     "so canCollisionWarp -- checkEdgeExit's gate and the blocked-step "
     .. "Warp.onCollision's -- is false on the mat")
  eq(require("src.world.Warp").onArrive(map, 3, 7, "down"), nil,
     "and Warp.onArrive still refuses the carpet (the mat is not a trapdoor)")

  -- THE REPORT, both walks
  local grid = gridWalkSouth(map, 3, 7)
  ok(grid ~= nil and grid.destMap == "LAST_MAP",
     "the GRID walk leaves the Center holding DOWN on the mat")
  local free = freeWalkSouth(map, 3, 7)
  ok(free ~= nil and free.destMap == "LAST_MAP",
     "and so does the FREE walk -- the reported bug")

  -- walking in from the floor above and straight on out
  local free2 = freeWalkSouth(map, 3, 6)
  ok(free2 ~= nil and free2.destMap == "LAST_MAP",
     "walking south from the floor above crosses the mat and leaves")

  -- ...but only in the carpet's OWN direction.  Walking east along a
  -- two-cell mat is the step that must never fire (it is the other half of
  -- Warp.onArrive's refusal), and the free walk must not restore it.
  taken, bearing.wx, bearing.wz = nil, 1, 0
  local st2 = newState(map, 3, 7)
  st2:refreshStandingOnWarp()
  FreeMove.drop()
  for _ = 1, 40 do FreeMove.tick(st2); if taken then break end end
  eq(taken, nil, "walking EAST along the mat does not leave the building")
  ok(st2.player.cellX > 3 and st2.player.cellY == 7,
     "it just walks east along the bottom row, mat cell and all")
end

-- =================================================== PRISM, which is a Gen 2
io.write("prism walks out of the same door\n")
do
  GameVersion.set("prism")
  ok(GameVersion.isGen2(), "prism is generation 2")
  local map = fourCellMap("PRISM_POKECENTER_1F", 0x70, 0x00, 0x01)
  local free = freeWalkSouth(map, 3, 7)
  ok(free ~= nil and free.destMap == "LAST_MAP",
     "so the free walk leaves a Prism building too")
end

-- ================================================= GEN 3, the same hole
--
-- Hoenn's mat is an arrow, and its own half of this is checkGen3ArrowWarp.
-- The step DOWN onto the mat always warped (Warp.onArrive qualifies it by the
-- arrow's direction), so the case that was stuck is the one every player is
-- in the moment they walk into a Center: already STANDING on the mat.
io.write("gen3's arrow mat answers it too\n")
do
  GameVersion.set("emerald")
  local map = gen3Map("MAP_G01_N00")
  eq(map:arrowWarpDirAt(3, 7), "down", "the mat is a south arrow warp")
  local grid = gridWalkSouth(map, 3, 7)
  ok(grid ~= nil and grid.destMap == "LAST_MAP",
     "the grid walk leaves from a standing start on the mat")
  local free = freeWalkSouth(map, 3, 7)
  ok(free ~= nil and free.destMap == "LAST_MAP",
     "and so does the free walk")
end

-- ============================================ GEN 1 WAS NEVER AFFECTED
--
-- Red's mat is a DOOR tile, which is a warp tile AND a door tile, so
-- refreshStandingOnWarp KEEPS standingOnWarp set (#378) and checkEdgeExit
-- already answered for it.  This pins that it still does.
io.write("gen1 is unchanged\n")
do
  GameVersion.set("red")
  local map = fourCellMap("REDS_HOUSE_1F", 0x1B, 0x00, 0x01, { 0x1B }, { 0x1B })
  local st = newState(map, 3, 7)
  st:refreshStandingOnWarp()
  eq(st.standingOnWarp, true, "a Gen 1 door mat keeps BIT_STANDING_ON_WARP")
  local grid = gridWalkSouth(map, 3, 7)
  ok(grid ~= nil and grid.destMap == "LAST_MAP", "the grid walk leaves")
  local free = freeWalkSouth(map, 3, 7)
  ok(free ~= nil and free.destMap == "LAST_MAP",
     "and the free walk leaves, through checkEdgeExit as it always did")
end

-- ========================================= the order the engine asked for
--
-- checkGen2CarpetExit and checkGen3ArrowWarp go AHEAD of checkEdgeExit, which
-- is the grid walk's own order (OverworldController.lua:3718-3726) and
-- deliberate: the edge path would otherwise answer for every mat whose front
-- is off the map, and it is gated on a flag that is clear on all of them.
io.write("the push order matches the grid walk\n")
do
  local src = assert(io.open(MOD .. "lib/FreeMove.lua")):read("*a")
  local push = src:match("local function pushSpecials%(state, dir, why%)(.-)\nend")
  ok(push ~= nil, "pushSpecials is still where the walk keeps its verbs")
  if push then
    local carpet = push:find("checkGen2CarpetExit", 1, true)
    local arrow  = push:find("checkGen3ArrowWarp", 1, true)
    local edge   = push:find("checkEdgeExit", 1, true)
    local ledge  = push:find("checkLedgeHop", 1, true)
    local bould  = push:find("checkBoulderPush", 1, true)
    ok(carpet and arrow and edge and ledge and bould,
       "and it hands the engine all five blocked-step verbs")
    ok(carpet and arrow and carpet < arrow, "the carpet is asked before the arrow")
    ok(arrow and edge and arrow < edge, "and both before the map edge")
    ok(edge and ledge and ledge < bould and edge < ledge,
       "with the ledge and the boulder after, as before")
  end
end

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
