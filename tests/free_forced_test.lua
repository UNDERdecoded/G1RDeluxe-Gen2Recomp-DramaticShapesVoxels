-- THE VERBS THAT ARE NOT REFUSALS.
--
-- The free walk hands the engine its blocked-step verbs out of pushSpecials,
-- which runs only when the body has been CLAMPED against something (see
-- free_exit_test.lua, which pins the doormat half of that).  Two of the grid
-- walk's verbs are not refusals at all, and neither can live there:
--
--   THE EDDY.  CollisionPermissionTable (3E:$74BE) gives COLL_WHIRLPOOL
--   ($24/$2C) the byte $11, whose low nibble GetTileCollision keeps, so a
--   whirlpool reads as PLAIN WATER: Collision.canMove says yes, blockedCell
--   returns nil, the body never clamps and pushSpecials never runs.  The free
--   walk swam into the current and sat in it -- which is the softlock the
--   eddy-as-a-bump exists to avoid -- while the grid walk on the identical
--   cell started the spin on the first frame.  The grid keeps this at the TOP
--   of its held-direction loop, ahead of the `facing == dir` guard, because
--   "the eddy pre-empts turning, stepping, ledges and warps alike"; the free
--   walk now asks it once per moving frame, before the slide covers ground.
--
--   THE ROTATING GATE.  Same shape, and NOT fixed -- see the last block of
--   this suite, which pins the facts that rule pushSpecials out as its home
--   so the reasoning is on the record rather than in a commit message.
--
-- The eddy pond is a fixture, because no gold/silver/crystal cache exists to
-- load (the same reason free_exit_test.lua builds its Pokemon Center).  The
-- gate half runs against the REAL extracted Fortree City Gym.

-- The engine tree this suite runs against.  Defaults to the current
-- directory; override with ENGINE=... .
local ENGINE = os.getenv("ENGINE") or "."
package.path = ENGINE .. "/?.lua;" .. ENGINE .. "/?/init.lua;" .. package.path
-- The mod under test.  Defaults to the tree this suite ships in; override
-- with MOD=... .
local MOD = os.getenv("MOD") or "mods/DRAMATIC_SHAPE"
if MOD:sub(-1) ~= "/" then MOD = MOD .. "/" end
_G.love = require("tests.love_stub")
package.loaded["src.core.Sound"] = { play = function() end,
                                     playMusic = function() end }

local GameVersion = require("src.core.GameVersion")
local Map       = require("src.world.Map")
local Collision = require("src.world.Collision")
local OW        = require("src.world.OverworldController")

local pass, fail = 0, 0
local function ok(c, w)
  if c then pass = pass + 1 else fail = fail + 1; io.write("  FAIL  ", w, "\n") end
end
local function eq(a, b, w)
  if a == b then pass = pass + 1 else fail = fail + 1
    io.write("  FAIL  ", w, ": got ", tostring(a), " want ", tostring(b), "\n") end
end

-- ------------------------------------------------------------- the world
local function loadGen3(name)
  local f = loadfile(ENGINE .. "/data/generated/" .. name .. ".lua")
  return f and f() or nil
end
local gen3maps      = loadGen3("maps")
local gen3tilesets  = loadGen3("tilesets")
local gen3constants = loadGen3("constants")

local Game = require("src.core.Game")
Game.save = { onBike = false, options = {}, party = {}, flags = {}, vars = {} }
Game.data = { field = { warpCarpets = nil,
                        forcedMovement = { slopeMaps = {} },
                        tilePairs = { land = {}, water = {} },
                        boot = { screens = {} } },
              maps = gen3maps or {}, constants = gen3constants or {},
              tilesets = gen3tilesets or {} }
local held = {}
Game.input = { isDown = function(_, k) return held[k] == true end,
               wasPressed = function() return false end,
               state = held, pressQueue = {} }
_G.Game = Game
-- OverworldController keeps `Game` as a file-local it assigns only inside
-- :enter; this suite never enters a map, so bind that upvalue by hand.
do
  local i = 1
  while true do
    local n = debug.getupvalue(OW.handleInput, i)
    if not n then error("OverworldState.handleInput has no Game upvalue") end
    if n == "Game" then debug.setupvalue(OW.handleInput, i, Game) break end
    i = i + 1
  end
end

-- FreeMove asks FirstPerson for the camera bearing and Horde whether world
-- input is suppressed; nothing else of the mod takes part in a step.
local bearing = { wx = 0, wz = 1 }
local V = {}
local stubs = {
  FirstPerson = {
    driving = function() return true end,
    releaseBody = function() end,
    moveVector = function() return 0, 1 end,
    moveWorld = function() return bearing.wx, bearing.wz end,
    pointBody = function(wx, wz)
      if (wx or 0) == 0 and (wz or 0) == 0 then return "down" end
      if math.abs(wx) > math.abs(wz) then return wx > 0 and "right" or "left" end
      return wz > 0 and "down" or "up"
    end,
  },
  Horde = { suppressWorldInput = function() return false end },
}
function V.require(n) return assert(stubs[n], "unstubbed: " .. tostring(n)) end
local FreeMove = assert(loadfile(MOD .. "lib/FreeMove.lua"))(V)

local function newState(map, cx, cy, facing)
  local st = setmetatable({}, { __index = OW })
  st.map, st.entities, st.cast = map, {}, {}
  st.npcs, st.boulders, st.scriptMoves = {}, {}, {}
  st.bumpCooldown = 0
  st.player = { cellX = cx, cellY = cy, px = cx * 16, py = cy * 16,
                facing = facing or "down", moving = false,
                inputLocked = false, surfing = false, elevation = 0 }
  st.takeWarp = function() return true end
  st.onStepComplete = function(self) self:refreshStandingOnWarp() end
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

-- ============================================================= THE EDDY
--
-- A pond four blocks square: open water inside a shore wall, with one
-- COLL_WHIRLPOOL cell at (2,5).
local WATER, EDDY, LAND, WALL = 0x14, 0x24, 0x00, 0x01
local BLK = {
  [1] = { WATER, WATER, WATER, WATER },   -- open water
  [2] = { WALL,  WALL,  WALL,  WALL  },   -- shore
  [3] = { WATER, WATER, EDDY,  WATER },   -- the eddy is this block's SW cell
  [4] = { LAND,  LAND,  LAND,  LAND  },
}
local coll = {}
for b = 0, 4 do
  local q = BLK[b] or { WALL, WALL, WALL, WALL }
  for i = 1, 4 do coll[b * 4 + i] = q[i] end
end
local pondPair = { id = "TS_GEN2_WATER", blockTiles = 4, blockCells = 2,
                   metatileCount = 5, collision = coll, walkable = { LAND },
                   -- the eddy reads as plain water, which is the whole point
                   waterTiles = { WATER, EDDY }, shoreTiles = {},
                   doorTiles = {}, warpTiles = {} }
local POND = { { 2, 2, 2, 2 }, { 2, 1, 1, 2 }, { 2, 3, 1, 2 }, { 2, 2, 2, 2 } }
local packed = {}
for by = 1, 4 do
  for bx = 1, 4 do packed[#packed + 1] = string.char(POND[by][bx] % 256, 0) end
end
local pond = Map.new({ id = "WHIRL_ISLANDS_B1F", width = 4, height = 4,
                       blocks = table.concat(packed), borderBlock = 2,
                       tileset = "TS_GEN2_WATER", environment = 3, warps = {} },
                     pondPair)
local EX, EY = 2, 5      -- the eddy

local function surfer(cx, cy, facing)
  local st = newState(pond, cx, cy, facing)
  st.player.surfing = true
  return st
end

-- hold a bearing on the free walk; returns the frame the spin started, or nil
local function freeSurf(st, wx, wz, frames)
  bearing.wx, bearing.wz = wx, wz
  FreeMove.drop()
  local fired
  for f = 1, frames or 30 do
    FreeMove.tick(st)
    if st.whirlSpin and not fired then fired = f end
  end
  return fired
end

local function gridSurf(st, dir, frames)
  for k in pairs(held) do held[k] = nil end
  held[dir] = true
  local fired
  for f = 1, frames or 6 do
    pcall(function() st:handleInput() end)
    if st.whirlSpin and not fired then fired = f end
  end
  for k in pairs(held) do held[k] = nil end
  return fired
end

io.write("gen2: an eddy answers the free walk\n")
GameVersion.set("gold")
do
  eq(pond:cellTile(EX, EY), 0x24, "the eddy cell is COLL_WHIRLPOOL")
  ok(pond:isWaterCell(EX, EY), "and it is water")
  local st = surfer(EX, EY - 1, "down")
  ok(st:gen2IsWhirlpool(EX, EY), "which gen2IsWhirlpool recognises")
  -- THE REASON pushSpecials CANNOT HOST IT: the map does not refuse the step,
  -- so the body never clamps and the blocked-push block never runs.
  ok(Collision.canMove(pond, {}, st.player, "down"),
     "the map ALLOWS swimming into the eddy -- it is not a wall")
  eq(FreeMove._blockedCell(st, st.player, EX, EY), nil,
     "so blockedCell refuses nothing there, and there is no clamp to push on")

  -- the reference behaviour
  eq(gridSurf(surfer(EX, EY - 1, "down"), "down"), 1,
     "the GRID walk starts the whirl on the first frame")
  -- ...and the free walk, which is the fix
  local fst = surfer(EX, EY - 1, "down")
  eq(freeSurf(fst, 0, 1), 1, "and so does the FREE walk")
  ok(fst.player.cellX == EX and fst.player.cellY == EY - 1,
     "without ever entering the eddy cell")
  ok(fst.player.spinning == true and fst.player.inputLocked == true,
     "the engine's spin and input lock are set, so the free walk stands aside")
  eq(fst.whirlSpin and fst.whirlSpin.frames, 32,
     "for the two step_dig 16 beats the ROM script plays")

  -- from the other side, so it is the direction of TRAVEL that is tested
  eq(freeSurf(surfer(EX + 1, EY, "left"), -1, 0), 1,
     "swimming WEST into it answers too")
end

io.write("an eddy you swim PAST is not an eddy you swim into\n")
do
  eq(freeSurf(surfer(EX + 1, EY - 1, "down"), 0, 1), nil,
     "surfing south in the lane beside it does not spin")
  eq(freeSurf(surfer(EX, EY - 1, "right"), 1, 0), nil,
     "nor does surfing east across the top of it")
  eq(freeSurf(surfer(EX + 1, EY, "up"), 0, -1), nil,
     "nor north beside it")
end

io.write("prism is a gen 2, gen 1 and gen 3 are not\n")
do
  GameVersion.set("prism")
  ok(GameVersion.isGen2(), "prism is generation 2")
  eq(freeSurf(surfer(EX, EY - 1, "down"), 0, 1), 1, "so its eddies spin too")
  for _, v in ipairs({ "red", "emerald" }) do
    GameVersion.set(v)
    eq(freeSurf(surfer(EX, EY - 1, "down"), 0, 1), nil,
       v .. " has no Gen 2 whirlpool class, and nothing fires")
  end
  GameVersion.set("gold")
end

-- ================================================ WHERE THE VERB LIVES
--
-- On the movement path, before the slide -- not in pushSpecials, which only
-- ever runs on a clamp.  Read off the source so the placement cannot drift
-- back without this saying so.
io.write("the eddy is asked on the movement path, not the blocked push\n")
do
  local src = assert(io.open(MOD .. "lib/FreeMove.lua")):read("*a")
  local push = src:match("local function pushSpecials%(state, dir, why%)(.-)\nend")
  local tick = src:match("function FreeMove%.tick%(state%)(.-)\nend")
  ok(push and tick, "pushSpecials and FreeMove.tick are both still there")
  if push and tick then
    eq(push:find("checkGen2Whirlpool", 1, true), nil,
       "checkGen2Whirlpool is NOT in pushSpecials (it would never run)")
    local whirl = tick:find("checkGen2Whirlpool", 1, true)
    local slide = tick:find("slideX(state", 1, true)
    ok(whirl ~= nil, "it IS in the tick")
    ok(whirl and slide and whirl < slide,
       "and ahead of the slide, so no ground is covered into the current")
    -- the doormat verbs must not have moved
    ok(push and push:find("checkGen2CarpetExit", 1, true)
       and push:find("checkGen3ArrowWarp", 1, true)
       and push:find("checkEdgeExit", 1, true),
       "and the doormat verbs are still in the blocked push where they belong")
  end
end

-- ================================== THE ROTATING GATE, AND WHY IT IS NOT HERE
--
-- Fortree City Gym (MAP_G12_N01) and Route 110's Trick House Puzzle 6
-- (MAP_G29_N08) are the two rooms in Hoenn with rotating gates.  A gate's
-- pivot is a CORNER and its arms lie on the LINES between cells, so there is
-- nothing solid to stand on -- only a fence to cross.  These assertions are
-- the facts that rule pushSpecials out as its home; the fix itself is
-- deliberately not attempted (see the report accompanying this change).
io.write("the rotating gate: why the blocked push cannot host it\n")
do
  GameVersion.set("emerald")
  local Gates = require("src.world.Gen3Gates")
  local def = (gen3maps or {})["MAP_G12_N01"]
  if not def then
    io.write("  (no emerald cache in this tree -- gate facts not checked)\n")
  else
    local map = Map.new(def, gen3tilesets[def.tileset])
    map.id = "MAP_G12_N01"
    local st = newState(map, 1, 1)
    ok(st:startGen3Gates("MAP_G12_N01"), "Fortree Gym loads a gate puzzle")
    local puzzle = st.gen3Gates and st.gen3Gates.puzzle
    eq(puzzle and #puzzle.gates, 8, "with eight gates")

    -- gate 8's arm lies on the line between rows 2 and 3 at x=4
    st.player.cellX, st.player.cellY, st.player.facing = 4, 2, "down"
    ok(map:isWalkableCell(4, 2) and map:isWalkableCell(4, 3),
       "both cells either side of gate 8's arm are walkable")
    ok(Collision.canMove(map, {}, st.player, "down"),
       "and Collision.canMove ALLOWS the step across it -- the arm is no wall")
    eq(FreeMove._blockedCell(st, st.player, 4, 3), nil,
       "so blockedCell refuses nothing, the body never clamps, and "
       .. "pushSpecials is never reached on a gate at all")
    -- ...and yet the gate itself refuses it
    local function passable(cx, cy)
      return map:inBounds(cx, cy) and map:isWalkableCell(cx, cy)
    end
    Gates.reset(Game.save, st.gen3Gates.record, puzzle)
    local what = Gates.step(st.gen3Gates.record, Game.save, puzzle,
                            "down", 4, 3, passable)
    eq(what, "blocked", "the GATE refuses the crossing, though the map does not")
    eq(st:checkGen3Gate("down"), true,
       "which is what checkGen3Gate answers on the grid walk")
  end
  GameVersion.set("gold")
end

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
