-- THE FREE WALK MUST ASK THE ENGINE WHAT THE GROUND IS, NOT GUESS.
--
-- Reported from play: "when using first and third person into caves im
-- getting an issue where it makes me move on top of the cliff instead of
-- going into the cave entrance. shouldnt be able to climb on top of cliffs
-- either in first or third person".
--
-- FreeMove.blockedCell used to restate Collision's step test and got four of
-- its seven clauses -- bounds, passability, tile pairs, occupancy -- losing
-- the one-way side walls, the ELEVATION and the acro/rail tests.  In Hoenn
-- the sea is passable ground at elevation 1 and dry land is 3, and a cliff
-- top and its foot are two elevations with nothing solid between them, so
-- without that clause the free walk could climb any cliff and stroll onto the
-- open sea on foot.  Measured over the region before the fix: 12,919 of
-- 1,221,224 (cell, direction) probes disagreed with the grid walk, every one
-- of them the free walk being more permissive.
--
-- The repair is delegation, not another copy: Collision.mayEnter is canMove
-- asked about a cell you name rather than a direction you take, and
-- blockedCell now calls it.  This suite pins both halves -- the behaviour, and
-- the fact that it is asked rather than restated.
--
-- The cliffs and the sea are REAL extracted Emerald maps; the no-elevation
-- cartridges are a fixture, because no Gen 1 or Gen 2 cache exists to load.

local ENGINE = os.getenv("ENGINE") or "."
package.path = ENGINE .. "/?.lua;" .. ENGINE .. "/?/init.lua;" .. package.path
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
local V = {}
local stubs = {
  FirstPerson = {
    driving = function() return true end, releaseBody = function() end,
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
                inputLocked = false, surfing = false,
                elevation = map:elevationAfter(nil, cx, cy) }
  st.takeWarp = function() return true end
  -- a map-edge crossing needs a camera and a whole boot; the body clamping at
  -- the edge is what this suite measures
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
    local moved, why = Collision.canMove(m, ents, pl, dir)
    if not moved then return "blocked", why end
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

-- hold a bearing on the free walk; returns the cell it ends on
local function freeWalk(st, wx, wz, frames)
  bearing.wx, bearing.wz = wx, wz
  FreeMove.drop()
  for _ = 1, frames or 24 do FreeMove.tick(st) end
  return st.player.cellX, st.player.cellY
end

-- ============================================== THE DELEGATION ITSELF
io.write("the engine publishes the verdict for an explicit cell\n")
local HAVE_MAYENTER = type(Collision.mayEnter) == "function"
ok(HAVE_MAYENTER, "Collision.mayEnter exists (the cell-addressed verdict)")

GameVersion.set("emerald")

-- ================================================== THE CLIFF, REAL DATA
--
-- Route114 (MAP_G00_N29) carries the Meteor Falls mouth at (8,63).  The seam
-- at (14,52)/(14,53) is two land terraces, elevation 3 and 4, both walkable,
-- with nothing solid between them -- a cliff.
io.write("gen3: a real cliff refuses the free walk\n")
local r114 = realMap("MAP_G00_N29")
if not r114 then
  io.write("  (no emerald cache in this tree -- the real-map blocks are skipped)\n")
else
  eq(r114:cellElevation(14, 52), 3, "Route114 (14,52) is elevation 3")
  eq(r114:cellElevation(14, 53), 4, "and (14,53) is elevation 4")
  ok(r114:isWalkableCell(14, 52) and r114:isWalkableCell(14, 53),
     "both cells are walkable, so passability alone does not fence them")
  local st = newState(r114, 14, 52, "down")
  local moved, why = Collision.canMove(r114, {}, st.player, "down")
  eq(moved, false, "the GRID walk refuses the step")
  eq(why, "elevation", "with the reason 'elevation'")
  eq(FreeMove._blockedCell(st, st.player, 14, 53, "down"), "elevation",
     "and the FREE walk refuses it too, with the engine's own reason")
  local fx, fy = freeWalk(newState(r114, 14, 52, "down"), 0, 1)
  ok(fx == 14 and fy == 52,
     "so pushing south for 24 frames does not climb the cliff")
end

-- ============================================== THE SEA, ON FOOT, REAL DATA
io.write("gen3: dry land to open water on foot is refused\n")
local r106 = realMap("MAP_G00_N21")
if r106 then
  -- Route106 carries the Granite Cave mouth at (48,16); the shelf above the
  -- beach runs the width of the map at y=10 (elevation 1) / y=11 (elevation 3)
  eq(r106:cellElevation(48, 10), 1, "Route106 (48,10) is elevation 1")
  eq(r106:cellElevation(48, 11), 3, "and (48,11) is elevation 3")
  local st = newState(r106, 48, 10, "down")
  st.player.surfing = false
  local moved, why = Collision.canMove(r106, {}, st.player, "down")
  eq(moved, false, "the GRID walk refuses that seam")
  eq(why, "elevation", "for elevation")
  eq(FreeMove._blockedCell(st, st.player, 48, 11, "down"), "elevation",
     "and so does the FREE walk")

  -- ...and the same clause the other way round: walking off land into the sea
  local sx, sy, sdir, sdx, sdz, tx, ty
  for cy = 0, r106.heightCells - 1 do
    for cx = 0, r106.widthCells - 1 do
      if r106:isWalkableCell(cx, cy) and not r106:isWaterCell(cx, cy)
         and (r106:cellElevation(cx, cy) or 0) >= 3 then
        for _, d in ipairs({ { "up", 0, -1 }, { "down", 0, 1 },
                             { "left", -1, 0 }, { "right", 1, 0 } }) do
          local ax, ay = cx + d[2], cy + d[3]
          if r106:inBounds(ax, ay) and r106:isWaterCell(ax, ay)
             and r106:isWalkableCell(ax, ay) then
            sx, sy, sdir, sdx, sdz, tx, ty = cx, cy, d[1], d[2], d[3], ax, ay
            break
          end
        end
      end
      if sx then break end
    end
    if sx then break end
  end
  ok(sx ~= nil, "Route106 has a shoreline where land meets walkable water")
  if sx then
    local wst = newState(r106, sx, sy, sdir)
    wst.player.surfing = false
    eq((Collision.canMove(r106, {}, wst.player, sdir)), false,
       "the GRID walk will not walk onto the sea")
    eq(FreeMove._blockedCell(wst, wst.player, tx, ty, sdir), "elevation",
       "and neither will the FREE walk any more")
    local ex, ey = freeWalk(newState(r106, sx, sy, sdir), sdx, sdz)
    ok(ex == sx and ey == sy, "pushing at the water for 24 frames goes nowhere")
  end

  -- ...but COMING ASHORE must still work: the cartridge turns exactly this
  -- mismatch into COLLISION_STOP_SURFING when the cell ahead is standable
  -- land, which is how you land anywhere along a coast.
  io.write("...but a surfer still comes ashore\n")
  local wx2, wy2, wdir, wtx, wty
  for cy = 0, r106.heightCells - 1 do
    for cx = 0, r106.widthCells - 1 do
      if r106:isWaterCell(cx, cy) then
        for _, d in ipairs({ { "up", 0, -1 }, { "down", 0, 1 },
                             { "left", -1, 0 }, { "right", 1, 0 } }) do
          local ax, ay = cx + d[2], cy + d[3]
          if r106:inBounds(ax, ay) and r106:isWalkableCell(ax, ay)
             and not r106:isWaterCell(ax, ay) then
            wx2, wy2, wdir, wtx, wty = cx, cy, d[1], ax, ay
            break
          end
        end
      end
      if wx2 then break end
    end
    if wx2 then break end
  end
  ok(wx2 ~= nil, "Route106 has water with standable land beside it")
  if wx2 then
    local ast = newState(r106, wx2, wy2, wdir)
    ast.player.surfing = true
    ok(r106:elevationBlocks(ast.player.elevation, wtx, wty),
       "the raw elevations mismatch at the shoreline")
    eq((Collision.canMove(r106, {}, ast.player, wdir)), true,
       "and the GRID walk allows it anyway -- the landing exception")
    eq(FreeMove._blockedCell(ast, ast.player, wtx, wty, wdir), nil,
       "and the FREE walk gets that exception too, because it asks rather "
       .. "than restates")
  end
end

-- ==================================== NEVER STRICTER THAN THE GRID WALK
--
-- The free walk refusing something the grid allows is how a player gets
-- walled into a corner, so it is worth a sweep rather than a sample.
io.write("the free walk is never stricter than the grid walk\n")
if r106 then
  local stricter, leaks, probes = 0, 0, 0
  for _, surf in ipairs({ false, true }) do
    local st = newState(r106, 0, 0)
    st.player.surfing = surf
    for cy = 0, r106.heightCells - 1 do
      for cx = 0, r106.widthCells - 1 do
        if r106:isWalkableCell(cx, cy) or (surf and r106:isWaterCell(cx, cy)) then
          for _, d in ipairs({ { "up", 0, -1 }, { "down", 0, 1 },
                               { "left", -1, 0 }, { "right", 1, 0 } }) do
            local tx, ty = cx + d[2], cy + d[3]
            st.player.cellX, st.player.cellY = cx, cy
            st.player.elevation = r106:elevationAfter(nil, cx, cy)
            local allowed = Collision.canMove(r106, {}, st.player, d[1])
            local blocked = FreeMove._blockedCell(st, st.player, tx, ty, d[1])
            probes = probes + 1
            if allowed and blocked then stricter = stricter + 1 end
            if (not allowed) and not blocked then leaks = leaks + 1 end
          end
        end
      end
    end
  end
  ok(probes > 5000, "swept the whole of Route106 on foot and surfing")
  eq(stricter, 0, "the free walk never refuses a step the grid walk allows")
  eq(leaks, 0, "and never allows one the grid walk refuses")
end

-- ================================================ AND IT STILL WALKS
io.write("and the body still covers ground everywhere the grid can step\n")
local gym = realMap("MAP_G12_N01")
if gym then
  local tried, movedN = 0, 0
  for cy = 0, gym.heightCells - 1 do
    for cx = 0, gym.widthCells - 1 do
      if gym:isWalkableCell(cx, cy) then
        for _, d in ipairs({ { "up", 0, -1 }, { "down", 0, 1 },
                             { "left", -1, 0 }, { "right", 1, 0 } }) do
          local st = newState(gym, cx, cy, d[1])
          if Collision.canMove(gym, {}, st.player, d[1]) then
            tried = tried + 1
            bearing.wx, bearing.wz = d[2], d[3]
            FreeMove.drop()
            local before
            for f = 1, 20 do
              local pp = FreeMove._pos()
              if f == 1 and pp then before = { x = pp.x, z = pp.z } end
              FreeMove.tick(st)
            end
            local after = FreeMove._pos()
            local slid = after and before
              and (math.abs(after.x - before.x) + math.abs(after.z - before.z)) > 4
            if (st.player.cellX ~= cx or st.player.cellY ~= cy) or slid then
              movedN = movedN + 1
            end
          end
        end
      end
    end
  end
  ok(tried > 300, "Fortree Gym offers the grid walk hundreds of legal steps")
  eq(movedN, tried, "and the free walk covers ground on every one of them")
end

-- ======================= THE OWN CELL NEVER BLOCKS, EVEN AT A WRONG ELEVATION
--
-- With elevation live this exemption stops being a nicety: a body standing on
-- a cell whose elevation disagrees with the one it is carrying -- a script
-- placed it, a warp landed it -- has to be free to walk off rather than be
-- frozen where it stands.
io.write("the player's own cell still never blocks\n")
if r114 then
  local st = newState(r114, 14, 53, "up")
  st.player.elevation = 3          -- deliberately not (14,53)'s own elevation
  eq(FreeMove._blockedCell(st, st.player, 14, 53, "up"), nil,
     "the cell under the body answers nil even at a mismatched elevation")
  ok(FreeMove._blockedCell(st, st.player, 14, 52, "up") == nil,
     "and it can walk back off to the elevation it is carrying")
end

-- ========================================= THE DIRECTION IS THE AXIS CROSSED
io.write("the probe takes the axis being crossed, and works without one\n")
if r114 then
  local st = newState(r114, 14, 52, "down")
  -- a DIAGONAL cell: slideX/slideZ ask about the leading edge, which can be
  -- one row or column off the body's own cell
  local diag = FreeMove._blockedCell(st, st.player, 15, 53, "down")
  ok(diag == nil or type(diag) == "string",
     "a diagonal cell answers without raising")
  local noDir = FreeMove._blockedCell(st, st.player, 14, 53)
  eq(noDir, "elevation",
     "and with no axis named the five direction-free clauses still answer")
end

-- ============================ GEN 1, GEN 2 AND PRISM CARRY NO ELEVATION
--
-- elevationBlocks answers false the moment the cell has no elevation, so
-- nothing about those cartridges changes.  A flat Gen 2 room, walked.
io.write("gen1, gen2 and prism are unchanged\n")
do
  local FLOOR, WALL = 0x00, 0x01
  local coll = {}
  for b = 0, 2 do
    local q = (b == 1) and { FLOOR, FLOOR, FLOOR, FLOOR }
              or { WALL, WALL, WALL, WALL }
    for i = 1, 4 do coll[b * 4 + i] = q[i] end
  end
  local pair = { id = "TS_FLAT", blockTiles = 4, blockCells = 2,
                 metatileCount = 3, collision = coll, walkable = { FLOOR },
                 doorTiles = {}, warpTiles = {} }
  local packed = {}
  for _ = 1, 9 do packed[#packed + 1] = string.char(1, 0) end
  local flat = Map.new({ id = "GEN2_ROOM", width = 3, height = 3,
                         blocks = table.concat(packed), borderBlock = 2,
                         tileset = "TS_FLAT", environment = 3, warps = {} },
                       pair)
  eq(flat.def.elevationCells, nil, "a Gen 2 map ships no elevation array")
  eq(flat:cellElevation(2, 2), nil, "so a cell has no elevation")
  eq(flat:elevationBlocks(3, 2, 3), false, "and elevationBlocks answers false")
  for _, v in ipairs({ "red", "gold", "crystal", "prism" }) do
    GameVersion.set(v)
    local st = newState(flat, 2, 2, "down")
    eq(FreeMove._blockedCell(st, st.player, 2, 3, "down"), nil,
       v .. ": the free walk crosses a flat room exactly as before")
    local fx, fy = freeWalk(newState(flat, 2, 2, "down"), 0, 1, 20)
    ok(fy > 2, v .. ": and the body actually covers the ground")
  end
  GameVersion.set("emerald")
end

-- ================================== ASKED, NOT RESTATED -- read off the source
--
-- This is the clause that stops the bug coming back.  Three rounds of this
-- family of bugs have all been FreeMove restating an engine rule and losing a
-- piece of it; blockedCell must delegate, not re-implement.
io.write("blockedCell asks the engine rather than restating it\n")
do
  local src = assert(io.open(MOD .. "lib/FreeMove.lua")):read("*a")
  local body = src:match(
    "local function blockedCell%(state, p, cx, cy, dir%)(.-)\nend")
  ok(body ~= nil, "blockedCell takes the axis as its fifth argument")
  if body then
    ok(body:find("Collision.mayEnter", 1, true) ~= nil,
       "and calls Collision.mayEnter")
    eq(body:find("isWalkableCell", 1, true), nil,
       "it no longer restates the passability test")
    eq(body:find("inBounds", 1, true), nil,
       "nor the bounds test")
    eq(body:find("Collision.occupied", 1, true), nil,
       "nor the occupancy test")
    ok(body:find("cx == p.cellX and cy == p.cellY", 1, true) ~= nil,
       "but it keeps the own-cell exemption, which is the free walk's own")
  end
  -- and the slide hands the axis down
  local sx = src:match("local function slideX%(state, p, dx%)(.-)\nend")
  local sz = src:match("local function slideZ%(state, p, dz%)(.-)\nend")
  ok(sx and sx:find('blockedCell(state, p, edge, zc, dir)', 1, true),
     "slideX probes with the axis it is sliding along")
  ok(sz and sz:find('blockedCell(state, p, xc, edge, dir)', 1, true),
     "and so does slideZ")
end

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
