-- THE FREE WALK MUST ASK THE ENGINE WHETHER IT MAY RUN, NOT DECIDE.
--
-- Reported from play: "add the ability to sprint in first and third person
-- currently it doesnt work".
--
-- It did not.  FreeMove picked its speed from Game.save.onBike alone --
-- FreeMove.BIKE or FreeMove.WALK, nothing else -- so holding B on a map that
-- allows running, with the SHOES flag set, covered exactly as much ground as
-- strolling.  Measured on Route 119 before the fix: 60px over 60 frames with
-- B held and 60px without, while the grid walk on the same cell with the same
-- input covered 120.
--
-- This is the fourth round of one disease in this module -- FreeMove
-- restating an engine behaviour instead of delegating to it -- so it is
-- repaired the way the doormat, the whirlpool and blockedCell each were: by
-- ASKING.  OverworldState:runFrames already holds every gate (the dataset's
-- runStepFrames, Hoenn's SHOES flag, the map header's may-run bit -- 228 of
-- the region's 519 maps -- the seven ground behaviours the shoes refuse,
-- Prism's no-gates-at-all, and the B button itself), and FreeMove.runSpeed
-- now calls it rather than copying any of it.
--
-- The speed is DERIVED: the grid measures a step in frames and the free walk
-- in pixels per frame, so the conversion is the ratio of the two step
-- lengths, WALK * stepFrames / runFrames.  Nothing here asserts "2.0"
-- without also computing it from the dataset.
--
-- The maps are REAL extracted Emerald maps.  The Gen 1 / Gen 2 / Prism
-- version gate is checked on a FIXTURE map, because no Gen 1, Gen 2 or Prism
-- cache exists in this tree to load.

local ENGINE = os.getenv("ENGINE") or "."
package.path = ENGINE .. "/?.lua;" .. ENGINE .. "/?/init.lua;" .. package.path
local MOD = os.getenv("MOD") or "mods/DRAMATIC_SHAPE"
if MOD:sub(-1) ~= "/" then MOD = MOD .. "/" end
_G.love = require("tests.love_stub")
package.loaded["src.core.Sound"] = { play = function() end,
                                     playMusic = function() end }

local GameVersion   = require("src.core.GameVersion")
local Map           = require("src.world.Map")
local Collision     = require("src.world.Collision")
local OW            = require("src.world.OverworldController")
local FieldDefaults = require("src.world.FieldDefaults")

local pass, fail = 0, 0
local function ok(c, w)
  if c then pass = pass + 1 else fail = fail + 1; io.write("  FAIL  ", w, "\n") end
end
local function eq(a, b, w)
  if a == b then pass = pass + 1 else fail = fail + 1
    io.write("  FAIL  ", w, ": got ", tostring(a), " want ", tostring(b), "\n") end
end
local function near(a, b, w)
  if type(a) == "number" and math.abs(a - b) < 1e-6 then pass = pass + 1
  else fail = fail + 1
    io.write("  FAIL  ", w, ": got ", tostring(a), " want ", tostring(b), "\n") end
end

local function loadGen3(n)
  local f = loadfile(ENGINE .. "/data/generated/" .. n .. ".lua")
  return f and f() or nil
end
local gmaps, gtiles, gconst =
  loadGen3("maps"), loadGen3("tilesets"), loadGen3("constants")

local Game = require("src.core.Game")
Game.save = { onBike = false, options = {}, party = {}, flags = {}, vars = {} }
Game.data = { field = { warpCarpets = nil,
                        forcedMovement = { slopeMaps = {} },
                        tilePairs = { land = {}, water = {} },
                        boot = { screens = {} } },
              maps = gmaps or {}, constants = gconst or {}, tilesets = gtiles or {} }
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

local bearing = { wx = 0, wz = 1 }
-- the pad itself: `moving` in FreeMove.tick comes from moveVector, not from
-- the world bearing, so releasing the stick means zeroing THIS
local pad = { mx = 0, mz = 1 }
local V = {}
local stubs = {
  FirstPerson = {
    driving = function() return true end, releaseBody = function() end,
    moveVector = function() return pad.mx, pad.mz end,
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
                inputLocked = false, surfing = false,
                elevation = map.elevationAfter and map:elevationAfter(nil, cx, cy) or 0 }
  st.takeWarp = function() return true end
  st.checkEdgeExit = function() return false end
  st.onStepComplete = function(self)
    self:refreshStandingOnWarp()
    if self.map.elevationAfter then
      self.player.elevation =
        self.map:elevationAfter(self.player.elevation, self.player.cellX,
                                self.player.cellY)
    end
  end
  st.player.tryMove = function(pl, dir, m, ents)
    pl.facing = dir
    local moved = Collision.canMove(m, ents, pl, dir)
    if not moved then return "blocked" end
    local tx, ty = Collision.target(pl.cellX, pl.cellY, dir)
    pl.cellX, pl.cellY, pl.px, pl.py = tx, ty, tx * 16, ty * 16
    return "moved"
  end
  return st
end

local function realMap(id)
  local d = (gmaps or {})[id]
  if not d then return nil end
  local m = Map.new(d, gtiles[d.tileset])
  m.id = id
  return m
end

-- hold a bearing for `frames` and report the world px covered per frame
local function pxPerFrame(st, wx, wz, frames)
  frames = frames or 60
  bearing.wx, bearing.wz = wx, wz
  FreeMove.drop()
  local x0, y0 = st.player.px, st.player.py
  for _ = 1, frames do FreeMove.tick(st) end
  local dx, dy = st.player.px - x0, st.player.py - y0
  return math.sqrt(dx * dx + dy * dy) / frames
end

local function reset(st)
  Game.save.flags = {}
  Game.save.onBike = false
  for k in pairs(held) do held[k] = nil end
  st.player.surfing = false
  st.runGateSaid = nil
end

-- ------- the dataset's own figures, which every expectation below is
-- ------- computed from rather than spelled out
local WALK_FRAMES = FieldDefaults.world(Game.data, "stepFrames")
local RUN_FRAMES  = FieldDefaults.world(Game.data, "runStepFrames")
local EXPECT_RUN  = FreeMove.WALK * WALK_FRAMES / RUN_FRAMES

io.write("-- the derived conversion\n")
ok(type(WALK_FRAMES) == "number" and WALK_FRAMES > 0,
   "the dataset defines a walk step length")
ok(type(RUN_FRAMES) == "number" and RUN_FRAMES > 0,
   "the dataset defines a run step length")
ok(RUN_FRAMES < WALK_FRAMES, "and the run step is the shorter of the two")

-- ROUTE 119: allowRunning is set in its header, and its long grass is 765
-- cells of MetatileBehavior_IsRunningDisallowed ground.
local RUN_MAP  = "MAP_G00_N34"            -- Route119
local PC_MAP   = "MAP_G03_N01"            -- DewfordTown_PokemonCenter_1F
local OPEN_X, OPEN_Y = 23, 7              -- twelve clear cells eastward
local GRASS_X, GRASS_Y = 11, 56           -- long grass; (7..10,56) are clear

if gmaps and gmaps[RUN_MAP] and gtiles then
  GameVersion.set("emerald")
  local m  = realMap(RUN_MAP)
  local pc = realMap(PC_MAP)
  local FLAG = string.format("FLAG_G3_%04X", (gconst or {}).gen3RunningShoesFlag or 0)

  io.write("-- the maps this suite stands on are the real extracted ones\n")
  ok(m.def.allowRunning == true, RUN_MAP .. " (Route119) allows running")
  ok(pc and pc.def.allowRunning ~= true,
     PC_MAP .. " (a Pokemon Centre) does not")
  ok(m:runningBlockedAt(GRASS_X, GRASS_Y) == true,
     "Route119 (11,56) is ground the shoes refuse")
  ok(m:runningBlockedAt(OPEN_X, OPEN_Y) == false,
     "Route119 (23,7) is not")

  io.write("-- the grid walk, which is the reference\n")
  local gst = newState(m, OPEN_X, OPEN_Y, "right")
  Game.overworld = gst
  reset(gst)
  Game.save.flags[FLAG] = true
  held.b = true
  eq(gst:runFrames(), RUN_FRAMES, "the grid runs here with the shoes and B")
  reset(gst)
  Game.save.flags[FLAG] = true
  eq(gst:runFrames(), nil, "and does not with B released")

  io.write("-- the free walk now covers the same ground at the same rate\n")
  local st = newState(m, OPEN_X, OPEN_Y, "right")
  Game.overworld = st

  reset(st); Game.save.flags[FLAG] = true
  near(pxPerFrame(st, 1, 0), FreeMove.WALK, "walking with B released is the walk")

  st = newState(m, OPEN_X, OPEN_Y, "right"); Game.overworld = st
  reset(st); Game.save.flags[FLAG] = true; held.b = true
  near(pxPerFrame(st, 1, 0), EXPECT_RUN,
       "holding B with the shoes on sprints at WALK*stepFrames/runFrames")

  io.write("-- and refuses exactly where the grid refuses\n")
  st = newState(m, OPEN_X, OPEN_Y, "right"); Game.overworld = st
  reset(st); held.b = true                            -- no shoes flag
  near(pxPerFrame(st, 1, 0), FreeMove.WALK,
       "no SHOES flag: the free walk does not sprint")

  st = newState(m, GRASS_X, GRASS_Y, "right"); Game.overworld = st
  reset(st); Game.save.flags[FLAG] = true; held.b = true
  near(pxPerFrame(st, 1, 0), FreeMove.WALK,
       "standing on ground the shoes refuse: no sprint")

  st = newState(pc, 6, 5, "right"); Game.overworld = st
  reset(st); Game.save.flags[FLAG] = true; held.b = true
  near(pxPerFrame(st, 1, 0, 6), FreeMove.WALK,
       "a map header that forbids running: no sprint")

  io.write("-- riding and surfing answer first\n")
  st = newState(m, OPEN_X, OPEN_Y, "right"); Game.overworld = st
  reset(st); Game.save.onBike = true
  near(pxPerFrame(st, 1, 0), FreeMove.BIKE, "the bike is the bike")

  st = newState(m, OPEN_X, OPEN_Y, "right"); Game.overworld = st
  reset(st); Game.save.flags[FLAG] = true
  Game.save.onBike = true; held.b = true
  near(pxPerFrame(st, 1, 0), FreeMove.BIKE,
       "and B on the bike does not stack a sprint on top of it")

  st = newState(m, OPEN_X, OPEN_Y, "right"); Game.overworld = st
  reset(st); Game.save.flags[FLAG] = true
  st.player.surfing = true; held.b = true
  near(pxPerFrame(st, 1, 0), FreeMove.WALK, "a surfer does not sprint")

  io.write("-- the ground gate is per CELL, so it is re-asked as the body moves\n")
  -- sprint east out of (7,56); the long grass begins at x = 11
  st = newState(m, 7, 56, "right"); Game.overworld = st
  reset(st); Game.save.flags[FLAG] = true; held.b = true
  bearing.wx, bearing.wz = 1, 0
  FreeMove.drop()
  local fastBefore, slowAfter, prev = 0, 0, st.player.px
  for _ = 1, 40 do
    FreeMove.tick(st)
    local d = st.player.px - prev
    prev = st.player.px
    if st.player.cellX < GRASS_X then
      if d > FreeMove.WALK + 1e-6 then fastBefore = fastBefore + 1 end
    elseif d <= FreeMove.WALK + 1e-6 and d > 0 then
      slowAfter = slowAfter + 1
    end
  end
  ok(fastBefore > 0, "it sprinted across the clear cells")
  ok(slowAfter > 0, "and dropped to the walk once the grass was underfoot")
  ok(st.player.cellX >= GRASS_X, "having actually reached the grass")

  io.write("-- A RUN IS A SHEET: the run cycle follows the chosen speed\n")
  -- Player:pose picks self.runSprite on self.running, and running is set only
  -- inside the grid step's speed branch -- the branch this module replaces --
  -- so the free walk sprinted at a run and animated at a walk.  Reported from
  -- play: "make sure your using the players sprint animation currently its
  -- not using it at all".
  local function runFlag(shoes, b, cx, cy)
    local s2 = newState(m, cx, cy, "right")
    Game.overworld = s2
    reset(s2)
    if shoes then Game.save.flags[FLAG] = true end
    held.b = b or nil
    s2.player.running = nil
    bearing.wx, bearing.wz = 1, 0
    FreeMove.drop()
    for _ = 1, 4 do FreeMove.tick(s2) end
    return s2.player.running, s2
  end
  eq((runFlag(true, true, OPEN_X, OPEN_Y)), true,
     "sprinting with the shoes and B sets running")
  eq((runFlag(true, false, OPEN_X, OPEN_Y)), false,
     "walking with B released does not")
  eq((runFlag(false, true, OPEN_X, OPEN_Y)), false,
     "and neither does B with no shoes")
  eq((runFlag(true, true, GRASS_X, GRASS_Y)), false,
     "nor on ground the shoes refuse")
  do
    local _, s3 = runFlag(true, true, OPEN_X, OPEN_Y)
    eq(s3.player.running, true, "running while the pad is held")
    pad.mx, pad.mz = 0, 0            -- the stick, actually released
    FreeMove.tick(s3)
    eq(s3.player.running, false, "and false the frame the pad is released")
    pad.mx, pad.mz = 0, 1            -- put it back for anything after this
  end

end

io.write("-- Gen 1 and Gen 2 have no running at all; Prism has it ungated\n")
do
  -- FIXTURE: no Gen 1, Gen 2 or Prism cache exists in this tree, so the MAP
  -- is hand-built.  The version gate under test is the engine's own.
  local fx = { def = { allowRunning = false }, widthCells = 24, heightCells = 24,
               tileset = { behaviourBytes = false } }
  function fx:runningBlockedAt() return false end
  local st = newState(fx, 5, 5, "right")
  Game.overworld = st
  local function gate(v)
    GameVersion.set(v)
    reset(st)
    held.b = true
    -- guarded so a tree without runSpeed still REPORTS rather than crashing
    return st:runFrames(), FreeMove.runSpeed and FreeMove.runSpeed(st) or nil
  end
  for _, v in ipairs({ "red", "blue", "yellow" }) do
    local rf, sp = gate(v)
    eq(rf, nil, "Gen 1 (" .. v .. ") has no run to ask for")
    eq(sp, nil, "so the free walk on " .. v .. " does not sprint")
  end
  for _, v in ipairs({ "gold", "silver", "crystal" }) do
    local rf, sp = gate(v)
    eq(rf, nil, "Gen 2 (" .. v .. ") has none to port")
    eq(sp, nil, "so the free walk on " .. v .. " does not sprint")
  end
  local rf, sp = gate("prism")
  eq(rf, RUN_FRAMES, "Prism runs on B alone, with no shoes and no flag")
  near(sp, EXPECT_RUN, "and the free walk on Prism sprints at the same rate")
  GameVersion.set("emerald")
end

io.write("-- asked, not restated\n")
do
  local f = assert(io.open(MOD .. "lib/FreeMove.lua", "r"))
  local src = f:read("*a"); f:close()
  local body = src:match("function FreeMove%.runSpeed%(state%)(.-)\nend")
  ok(body ~= nil, "FreeMove.runSpeed exists")
  if body then
    ok(body:find("state:runFrames()", 1, true) ~= nil,
       "and asks OverworldState:runFrames for the gate")
    eq(body:find("allowRunning", 1, true), nil,
       "it does not restate the map header's may-run bit")
    eq(body:find("runningBlockedAt", 1, true), nil,
       "nor the ground test")
    eq(body:find("gen3RunningShoesFlag", 1, true), nil,
       "nor the SHOES flag")
    eq(body:find('isDown("b")', 1, true), nil,
       "nor the B button, which runFrames reads for it")
    ok(body:find("onBike", 1, true) ~= nil,
       "but riding answers first, as the engine's call site does")
    ok(body:find("surfing", 1, true) ~= nil, "and so does surfing")
    ok(body:find("stepFrames", 1, true) ~= nil,
       "and the speed is derived from the dataset's step lengths")
  end
  -- and the speed pick actually uses it
  -- Matched from the sprint local rather than the `local speed =` line alone:
  -- the answer is held in a local now so the RUN SHEET can be set from the
  -- same decision, and an assertion pinned to one line's shape failed on that
  -- refactor while the thing it protects -- runSpeed feeding the speed -- was
  -- intact.
  local pick = src:match("local sprint = (.-)\n  local dx, dz")
  ok(pick and pick:find("FreeMove.runSpeed(state)", 1, true) ~= nil,
     "the per-frame speed pick is fed by runSpeed")
  ok(src:find("p.running = sprint ~= nil", 1, true) ~= nil,
     "and the run sheet is set from that same answer")
  ok(src:find("p.running = false", 1, true) ~= nil,
     "and cleared when the pad is released")
  ok(pick and pick:find("FreeMove.BIKE", 1, true) ~= nil,
     "with the bike still ahead of it")
end

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
