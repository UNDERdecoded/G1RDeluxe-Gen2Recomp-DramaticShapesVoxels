-- Voxel world mode: free movement for the free-roam rungs.
--
-- The engine walks a grid: sixteen frames per cell, four directions,
-- input locked mid-step. Inside a camera that stands with the player that
-- gait reads as riding a rail, so while 1ST or 3RD drives, this module
-- replaces the WALK and nothing else: the player's position becomes
-- continuous, steered by the camera's own yaw -- push forward and you go
-- where you look, at any angle, sliding along whatever you graze.
--
-- Both rungs walk identically: the boom behind the shoulder (3RD) changes
-- where the eye stands, not which way it points, and the walk was always
-- rotated by the YAW. The one thing it does change is which way the body
-- POINTS while it moves -- see bodyFacing in the tick.
--
-- THE GRID IS STILL THE GAME. Every fact the world cares about is a fact
-- about cells -- what blocks, what warps, what rustles, what bites -- and
-- this module keeps the player's logical cell synced to wherever the free
-- walk stands, then reuses the engine's own machinery for every one of
-- those questions:
--
--   passability      Collision.mayEnter -- the grid walker's own verdict,
--                    whole, asked per cell the player's body overlaps:
--                    side walls, bounds, passability, ELEVATION, acro
--                    tiles and rails, tile pairs, occupancy. Asked, not
--                    restated; a copy of it here lost three of the seven.
--
--   the forced moves the eddy that spins you back out (Gen 2's
--                    whirlpool) is asked once per moving frame, before the
--                    slide covers ground, because it is not a refusal the
--                    body can clamp against -- an eddy reads as plain
--                    water. Once it fires the engine's spin owns the
--                    player and this module stands aside.
--
--   cell arrival     OverworldState:onStepComplete, the same landing
--                    pipeline a grid step runs -- warps, spinners, gates,
--                    forced currents, poison, repel, encounters, the
--                    step counters -- fired once per cell crossed, which
--                    is exactly the rate a grid walk fires it.
--
--   the special pushes   walking out of a door, off the map edge, into a
--                    ledge, or into a boulder hands the quantised
--                    direction straight to checkGen2CarpetExit /
--                    checkGen3ArrowWarp / checkEdgeExit / checkLedgeHop /
--                    checkBoulderPush, the engine's own handlers, which
--                    validate and stage everything themselves (the mat's
--                    own direction, connections, the hop arc, the
--                    two-push arm). While any of those animates a
--                    scripted grid move, this module stands aside and
--                    adopts the result.
--
-- Nothing here writes save state, rolls encounters, or decides what a
-- warp does -- it moves a point, keeps the cell honest, and lets the
-- engine be the engine. Stepping off the rung snaps the point to its
-- cell and hands the walk back to the grid, and with the rung off this
-- module costs one gate check per frame.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local FirstPerson = V.require("FirstPerson")

local FreeMove = {}

-- The body: a circle in the ground plane. Small enough to walk every
-- one-cell corridor the grid game has (half a cell is 8), big enough to
-- keep the eye's near plane out of wall faces when sliding along them.
FreeMove.RADIUS = 5.5

-- World pixels per fixed 60Hz frame -- the grid walker's own speeds (16
-- frames per 16px cell on foot, 8 on the bike), so distance covered per
-- second is unchanged and the encounter rate per tile crossed stays the
-- game's own.
FreeMove.WALK = 1.0
FreeMove.BIKE = 2.0

-- THE RUN, ASKED OF THE ENGINE RATHER THAN RESTATED HERE.
--
-- Reported from play: "add the ability to sprint in first and third person
-- currently it doesnt work".  It did not: the speed below picked between WALK
-- and BIKE on Game.save.onBike alone, so holding B on Route 119 with the
-- SHOES on covered exactly as much ground as strolling -- measured, 60px over
-- 60 frames either way, while the grid walk beside it covered 120.
--
-- This is the fourth round of one disease in this module, so it is fixed the
-- way the other three were: by ASKING.  Every gate already exists in
-- OverworldState:runFrames (src/world/OverworldController.lua:4359) -- the
-- dataset's runStepFrames, Hoenn's SHOES flag, the map header's may-run bit
-- (228 of the region's 519 maps), the seven ground behaviours the shoes do
-- not work on, Prism's no-gates-at-all, and the B button itself.  Not one of
-- them is restated here; a copy would only lose some, which is precisely how
-- the doormat, the whirlpool and blockedCell each went wrong.  If runFrames
-- says nil, the free walk does not sprint, whatever the reason was.
--
-- RIDING AND SURFING ANSWER FIRST, as the engine's own comment at the call
-- site says (src/world/Player.lua:451): a bicycle already has its own speed
-- and the sprint does not stack on it, and runFrames refuses a surfer itself.
--
-- THE SPEED IS DERIVED, NOT A HARDCODED MULTIPLIER.  The grid measures a step
-- in FRAMES and the free walk measures it in PIXELS PER FRAME, so the honest
-- conversion between them is the ratio of the two step lengths: a walk step is
-- `stepFrames` and a run step is `runFrames`, so a free sprint at
-- WALK * stepFrames / runFrames covers ground at exactly the rate the grid
-- sprint does.  On the shipped Emerald cache that is 1.0 * 16 / 8 = 2.0 px a
-- frame, the same 120px per 60 frames the grid walk was measured covering --
-- but it is read off the dataset, so a cache with different figures gets its
-- own answer rather than this one.
--
-- runningBlockedAt is a PER-CELL verdict, so this is asked every moving frame
-- rather than once: a continuous walk crosses into long grass mid-stride, and
-- the sprint has to end on the cell it enters, not at the next grid step.
-- runFrames reads state.player.cellX/cellY, which the tick below keeps synced
-- to wherever the body stands.
--
-- Returns the sprint speed in world px per frame, or nil to leave WALK alone.
function FreeMove.runSpeed(state)
  local Game = require("src.core.Game")
  -- riding wins outright; surfing runFrames refuses for itself, but a free
  -- walk that never reaches it (no overworld to ask) must refuse it too
  if Game.save and Game.save.onBike then return nil end
  local p = state and state.player
  if p and p.surfing then return nil end
  if not (state and state.runFrames) then return nil end
  local run = state:runFrames()
  if type(run) ~= "number" or run <= 0 then return nil end
  local walk = require("src.world.FieldDefaults").world(Game.data, "stepFrames")
  if type(walk) ~= "number" or walk <= 0 then return nil end
  if run >= walk then return nil end   -- a "run" no faster than the walk is none
  return FreeMove.WALK * walk / run
end

local EPS = 0.01

-- the free position (player centre, world px) and the px/py we last wrote
-- -- if they differ from the player's, something else (a warp, a script)
-- moved them, and the free walk adopts rather than fights
local pos = nil
local lastPx, lastPy = nil, nil

local function adopt(p)
  pos = { x = p.px + 8, z = p.py + 8 }
  lastPx, lastPy = p.px, p.py
end

function FreeMove.drop()
  pos = nil
  -- and the body with it: while something else is walking the player --
  -- a scripted move, a ledge hop, the grid walk off the rung -- the
  -- engine's own four-direction facing is the whole truth about which way
  -- they point, so the card must stop reading our finer one
  FirstPerson.releaseBody()
end

-- named for the suite: the module's live position, nil while dropped
function FreeMove._pos()
  return pos
end

-- ------- the per-cell verdict
--
-- The same questions Collision.canMove asks for a grid step, asked of one
-- cell from the player's current standing. The player's OWN cell never
-- blocks -- the body must always be free to leave wherever it stands
-- (a warp mat, the water it is surfing, a cell an NPC just stepped
-- against).

-- ASK THE ENGINE. DO NOT RESTATE IT.
--
-- MOTIVATED BY THE CLIFF BESIDE ROUTE 114'S METEOR FALLS MOUTH (the seam
-- between (14,52) at elevation 3 and (14,53) at elevation 4), which the free
-- walk strolled up.  Reported from play: "when using first and third person
-- into caves im getting an issue where it makes me move on top of the cliff
-- instead of going into the cave entrance. shouldnt be able to climb on top
-- of cliffs either in first or third person".
--
-- This function used to spell the step test out again, and it got FOUR of the
-- engine's SEVEN clauses.  Collision's own `verdict` applies, in order: the
-- one-way side walls, the bounds, the passability (with the surfing
-- exception), the ELEVATION (with the coming-ashore exception), the acro
-- tiles and the rail under the rider, the tile pairs, and the occupancy.  The
-- copy here had bounds, passability, tile pairs and occupancy -- and no side
-- walls, no elevation and no acro.
--
-- Elevation is the one that showed.  In Hoenn the sea is passable ground at
-- elevation 1 and dry land is 3; a cliff top and its foot are two elevations
-- with nothing solid between them, which is the whole of "you cannot walk
-- onto water", "you cannot step off a cliff" and "the bridge and the river
-- beneath it are different places".  Measured over the region: 4,376 cliff
-- steps and 3,704 water steps across 107 maps that the grid walk refuses with
-- reason "elevation" and this function waved through -- including walking off
-- a beach onto the open sea, on foot, without surfing.
--
-- So it no longer has an opinion.  Collision.mayEnter is canMove asked about
-- a cell you name instead of a direction you take, and it runs the same
-- verdict through the same movement.collision hook -- which the restatement
-- also skipped, so a mod that overrode collision was obeyed on the grid and
-- ignored in first person.  Anything added to that verdict later is now the
-- free walk's too, which is the actual repair: this is the third bug in a row
-- from restating the engine rather than calling it.
--
-- `dir` is the AXIS being crossed, handed down by slideX/slideZ, because the
-- cell asked about can be DIAGONAL from the player -- a body with a radius
-- overlaps two cells per axis while it slides along anything. East is east
-- through that boundary whichever row the cell is in, which is the reading
-- the two direction-keyed clauses (the side walls, the rail) want.
--
-- The player's OWN cell still never blocks, and that exemption matters more
-- now than it did: with elevation live, a body standing on a cell whose
-- elevation disagrees with p.elevation -- a script placed them, a warp landed
-- them -- must still be free to walk off it rather than be frozen where it
-- stands.  (p.elevation itself is kept current by the engine: setMap writes
-- it on entry and onStepComplete re-derives it on every cell crossed, which
-- this module calls on every cell it crosses.  A nil elevation blocks
-- nothing, so a mover that somehow has none walks exactly as before.)
--
-- Returns the engine's own reason -- "bounds" | "tile" | "entity" |
-- "elevation" -- or nil when the body may enter.  The extra name is passed
-- through rather than folded into "tile" because it is the engine's word for
-- it, and the blocked-push block below already treats it the way the grid
-- walk does: not an entity, so the door and ledge verbs are still offered it.
local function blockedCell(state, p, cx, cy, dir)
  if cx == p.cellX and cy == p.cellY then return nil end
  local Collision = require("src.world.Collision")
  local allowed, why
  if Collision.mayEnter then
    allowed, why = Collision.mayEnter(state.map, state.entities, p, cx, cy, dir)
  else
    dir = dir or (cx ~= p.cellX and (cx > p.cellX and "right" or "left")
                               or (cy > p.cellY and "down" or "up"))
    local delta = Collision.DELTA[dir]
    local fromX, fromY = cx - delta[1], cy - delta[2]
    local mover = p
    if fromX ~= p.cellX or fromY ~= p.cellY then
      mover = setmetatable({ cellX = fromX, cellY = fromY }, { __index = p })
    end
    allowed, why = Collision.canMove(state.map, state.entities, mover, dir)
  end
  if allowed then return nil end
  return why or "tile"
end

FreeMove._blockedCell = blockedCell   -- named for the suite

-- ------- the slide
--
-- One axis at a time, clamped at the first refusing cell's face: the
-- classic axis-separated walk, which is where wall-sliding comes from --
-- the blocked axis stops and the free one keeps going. Returns the
-- refusal ("bounds"/"tile"/"entity") when this axis was clamped.

local function slideX(state, p, dx)
  if dx == 0 then return nil end
  local r = FreeMove.RADIUS
  local nx = pos.x + dx
  local z0 = math.floor((pos.z - r + EPS) / 16)
  local z1 = math.floor((pos.z + r - EPS) / 16)
  local hit = nil
  local dir = dx > 0 and "right" or "left"
  local edge = dx > 0 and math.floor((nx + r) / 16)
               or math.floor((nx - r) / 16)
  for zc = z0, z1 do
    hit = blockedCell(state, p, edge, zc, dir)
    if hit then break end
  end
  if hit then
    if dx > 0 then nx = math.min(nx, edge * 16 - r - EPS)
    else nx = math.max(nx, (edge + 1) * 16 + r + EPS) end
  end
  pos.x = nx
  return hit
end

local function slideZ(state, p, dz)
  if dz == 0 then return nil end
  local r = FreeMove.RADIUS
  local nz = pos.z + dz
  local x0 = math.floor((pos.x - r + EPS) / 16)
  local x1 = math.floor((pos.x + r - EPS) / 16)
  local hit = nil
  local dir = dz > 0 and "down" or "up"
  local edge = dz > 0 and math.floor((nz + r) / 16)
               or math.floor((nz - r) / 16)
  for xc = x0, x1 do
    hit = blockedCell(state, p, xc, edge, dir)
    if hit then break end
  end
  if hit then
    if dz > 0 then nz = math.min(nz, edge * 16 - r - EPS)
    else nz = math.max(nz, (edge + 1) * 16 + r + EPS) end
  end
  pos.z = nz
  return hit
end

-- ------- the blocked push
--
-- The grid game's blocked step is where half its verbs live: the map-edge
-- crossing, the ledge hop, the boulder shove, and the route-gate warp
-- fired by collision. Hand the engine the quantised direction and let its
-- own handlers decide -- each one validates itself (checkLedgeHop matches
-- the tile pair, checkEdgeExit checks the bounds), so calling them on
-- every firm push is safe. Returns true when one of them took the frame
-- over.
--
-- The one verb NOT restated here is the bonk. On the grid a blocked step
-- is a discrete event -- you pressed a direction, the game refused, and
-- the bump answers you once. A free walk has no such moment: the body
-- SLIDES along whatever it grazes, so a player walking a fence line or
-- rounding a doorframe is blocked on one axis continuously, and the same
-- sound comes out as a rattle for as long as they keep walking. It is
-- feedback for a refusal that is not happening. The grid walk keeps its
-- own bump (the engine's, in OverworldController) untouched.
local function pushSpecials(state, dir, why)
  local p = state.player
  p.facing = dir      -- the handlers read the push off the facing

  -- A DOORMAT IS A VERB, AND IT WAS THE ONE VERB THIS LIST LEFT OUT.
  --
  -- MOTIVATED BY CHERRYGROVE CITY'S POKEMON CENTER -- AND EVERY OTHER
  -- CENTER, MART, GYM AND HOUSE IN JOHTO -- WHOSE EXIT MAT THE FREE WALK
  -- COULD STAND ON FOREVER.  Reported from play: "first and third person not
  -- able to exit buildings in gen2".
  --
  -- The list below restates the grid walk's blocked-step verbs, and it
  -- restated three of the five.  On the grid (OverworldController:handleInput,
  -- the held-direction loop) the order is:
  --
  --     checkGen2CarpetExit -> checkGen3ArrowWarp -> checkEdgeExit
  --     -> checkLedgeHop -> checkBoulderPush
  --
  -- and the first two are exactly the ones a DIRECTIONAL EXIT MAT answers to.
  -- Nothing else will: on a Gen 2 carpet ($70/$76/$78/$7E) and a Gen 3 arrow
  -- warp ($62..$65, $6D) all three of the other ways out are shut, by design
  -- and not by accident --
  --
  --   * Warp.onArrive REFUSES the mat.  That is CheckDirectionalWarp, and it
  --     is what stops a two-cell mat from being a trapdoor you fall through
  --     by taking one step ALONG it (Warp.lua:45-50).  It must stay refused.
  --   * checkEdgeExit and the blocked-step Warp.onCollision below are both
  --     gated on canCollisionWarp, and refreshStandingOnWarp clears
  --     standingOnWarp for precisely these cells -- a mat is a warp tile and
  --     is not a door tile -- so the gate is FALSE on every mat in the game
  --     (OverworldController.lua:3208-3211 says so in as many words).
  --   * there is no completed step to qualify either, because the cell the
  --     mat points at is the doorway: off the map, or a wall.
  --
  -- So the free walk pushed south on the mat, was clamped flush against the
  -- map edge, ran this function every frame, and got false from all three --
  -- while the grid walk on the identical cell, with standingOnWarp equally
  -- false, walked out on the first frame through the two calls that were
  -- missing here.  Gen 1 was never affected: its mat is a DOOR tile, which
  -- keeps standingOnWarp set, so checkEdgeExit already answered for it.
  --
  -- Both of these self-gate -- checkGen2CarpetExit returns false off Gen 2,
  -- checkGen3ArrowWarp returns false on a map with no arrow warps -- so they
  -- are safe to ask on every firm push, which is the same contract the three
  -- below already keep.  They go FIRST, in the grid walk's own order: the
  -- engine puts checkGen3ArrowWarp ahead of checkEdgeExit deliberately
  -- (OverworldController.lua:3719-3724), and a mat whose front is off the map
  -- would otherwise be answered by the edge path instead of the door.
  if state.checkGen2CarpetExit and state:checkGen2CarpetExit(dir) then return true end
  if state.checkGen3ArrowWarp and state:checkGen3ArrowWarp(dir) then return true end

  if why == "bounds" and state:checkEdgeExit(dir) then return true end
  if state:checkLedgeHop(dir) then return true end
  if state:checkBoulderPush(dir) then return true end
  if why ~= "entity" and state:canCollisionWarp() then
    local Game = require("src.core.Game")
    local Warp = require("src.world.Warp")
    local w = Warp.onCollision(state.map, Game.data.field.warpCarpets,
                               p.cellX, p.cellY, dir)
    if w then
      state:takeWarp(w.def)
      return true
    end
  end
  -- and NO bonk. The grid walk's collision sound marks a discrete event:
  -- you pressed a direction, the step was refused, nothing happened. A
  -- free walk has no such moment -- the body slides along every wall it
  -- grazes, continuously, and a corridor taken at a slight angle is a
  -- steady graze from end to end. Rate-limited or not, that came out as a
  -- machine-gun of bonks for walking normally down a hallway. The wall
  -- stopping you is the feedback; the sound only ever said so twice a
  -- second whether or not anything had changed.
  return false
end

-- ------- the tick
--
-- Runs in place of OverworldState:handleInput while first person drives
-- (see install below), which means it inherits every gate the grid walk
-- has: never during scripted moves, transitions, or with anything above
-- the overworld on the stack.

function FreeMove.tick(state)
  local p = state.player

  -- a grid move is animating -- a ledge hop, a spinner slide, a scripted
  -- walk -- or a cutscene owns the player: stand aside, adopt the result
  if p.moving or p.inputLocked then
    FreeMove.drop()
    return
  end
  if not pos or p.px ~= lastPx or p.py ~= lastPy then adopt(p) end

  local Game = require("src.core.Game")
  local input = Game.input

  -- the head is the facing: what A talks to, what the sun's card shows,
  -- which way a bonk points. (A body that is WALKING may turn along its
  -- travel instead -- see below, once there is a travel to turn along; a
  -- standing one always faces where the camera looks, which is what makes
  -- A predictable.) pointBody rather than compassFacing, so the card also
  -- gets the CONTINUOUS bearing behind that compass point.
  p.facing = FirstPerson.pointBody(0, 0)

  -- HORDE MODE takes both of these away for as long as it runs: there is
  -- no pausing (START), and nobody stops to read a sign with the horde
  -- coming (A, which is also the button the mode's own GAME OVER card
  -- wants left unspent). Everything below -- the walk, the wall slide and
  -- the blocked-push verbs, warps included -- keeps working, because the
  -- crowd has to be able to follow the player through a door.
  local suppressed = V.require("Horde").suppressWorldInput()

  if not suppressed and input:wasPressed("a") then
    state:interact()
    return
  end
  if not suppressed and input:wasPressed("start") then
    require("src.core.Sound").play(Game.data, "Start_Menu")
    require("src.ui.Screens").push(Game, "StartMenu")
    return
  end

  local mx, mz = FirstPerson.moveVector()
  local wx, wz = FirstPerson.moveWorld(mx, mz)

  -- Cycling Road's downhill pull, the free-walk restatement of the grid
  -- path's simulated PAD_DOWN: south drift with nothing held, braked by
  -- holding A or B exactly as the Route 17 sign promises
  local moving = (mx ~= 0 or mz ~= 0)
  if not moving and Game.save and Game.save.onBike then
    local fm = Game.data.field.forcedMovement
    local braking = input:isDown("a") or input:isDown("b")
    if fm and not braking then
      for _, m in ipairs(fm.slopeMaps or {}) do
        if m == state.map.id then
          wx, wz, moving = 0, 1, true
          break
        end
      end
    end
  end

  if not moving then
    -- standing still is never a run: the sheet has to come back off the run
    -- cycle the moment the pad is released, exactly as the grid walk's own
    -- `self.running = false` does at the top of its speed branch.
    p.running = false
    return
  end

  -- and once there IS a direction of travel, the body may point along it
  -- rather than along the head: on the boom (3RD) you can see yourself, so
  -- a strafe has to look like walking sideways. In the head it is the head
  -- either way -- bodyBearing says so.
  p.facing = FirstPerson.pointBody(wx, wz)

  -- the engine's own bonk clock, kept draining while the free walk has the
  -- wheel: nothing here rings it (see pushSpecials), but stepping back onto
  -- the grid must not inherit a cooldown frozen at whatever it held when
  -- the rung was picked
  state.bumpCooldown = math.max(0, (state.bumpCooldown or 0) - 1)

  -- the bike's own speed, else the engine's sprint (derived, see runSpeed
  -- above -- asked fresh this frame because the ground gate is per cell),
  -- else the walk
  local sprint = FreeMove.runSpeed(state)
  local speed = ((Game.save and Game.save.onBike) and FreeMove.BIKE)
                or sprint
                or FreeMove.WALK
  local dx, dz = wx * speed, wz * speed

  -- A RUN IS A SHEET, AND THE FREE WALK WAS MOVING AT ONE WITHOUT WEARING IT.
  --
  -- MOTIVATED BY SPRINTING ANYWHERE IN HOENN IN 1ST/3RD.  Reported from play:
  -- "for the first person and third person sprint make sure your using the
  -- players sprint animation currently its not using it at all".
  --
  -- `Player:pose` picks `self.runSprite` on `self.running` (Player.lua's
  -- "running is the walk's own sheet only for a character with no run cycle
  -- of its own"), and `running` is set ONLY inside the grid step's speed
  -- branch -- the branch this module replaces wholesale.  So the free walk
  -- moved at the run speed and animated on the walk sheet.
  --
  -- Set from the SPEED that was actually chosen rather than from the button,
  -- which is the same rule the engine settled on for its own second clause
  -- ("a step on foot that takes fewer frames than a walk IS a run, whoever
  -- decided it"): `runSpeed` has already refused the bike, the surf and every
  -- gate, so a non-nil answer here IS the run.  DERIVED: no cadence change
  -- belongs with it -- `animClock` ticks once per real frame while moving in
  -- both paths, and Player.lua states that the leg cadence stays constant
  -- when the speed changes.  Only the sheet moves.
  --
  -- Harmless where a character has no run cycle: `runSprite` is nil for those
  -- and `pose` falls straight through to `self.sprite`, which is what plays
  -- today.
  p.running = sprint ~= nil

  -- AN EDDY IS NOT A WALL, WHICH IS WHY THE BLOCKED-PUSH LIST COULD NOT HOLD
  -- IT.
  --
  -- MOTIVATED BY THE WHIRLPOOLS ON THE WAY INTO WHIRL ISLANDS AND UNION
  -- CAVE'S LOWER FLOOR, which the free walk swam straight into and sat in.
  --
  -- The doormat verbs below live in pushSpecials because a doormat is a
  -- REFUSED step: the mat's front is a wall or off the map, the body clamps,
  -- and the push is the event.  An eddy is the opposite.  CollisionPermission-
  -- Table (3E:$74BE) gives COLL_WHIRLPOOL ($24/$2C) the byte $11, whose low
  -- nibble GetTileCollision keeps -- so the eddy reads as PLAIN WATER, .TrySurf
  -- does not refuse it, Collision.canMove says yes, and blockedCell therefore
  -- returns nil.  There is no clamp, no `hit`, and pushSpecials never runs at
  -- all.  Measured on a Gen 2 pond: the free walk crossed into the eddy cell
  -- on frame 8 and was still sitting in it on frame 22, with checkGen2Whirl-
  -- pool never once asked, while the grid walk on the identical cell started
  -- the spin on frame 1.
  --
  -- So it belongs HERE, on the allowed-movement path, before the slide covers
  -- any ground.  That is also where the grid walk keeps it: handleInput asks
  -- it at the TOP of the held-direction loop, outside and ahead of the
  -- `not p.moving and p.facing == dir` guard, because ".Normal and .Surf both
  -- `call .CheckTile` straight after .GetAction and `ret c`, so the eddy
  -- pre-empts turning, stepping, ledges and warps alike".  Asking it after the
  -- slide would let the body enter the current before being spun out of it,
  -- and standing IN an eddy is the softlock the eddy-as-a-bump exists to
  -- avoid.
  --
  -- The direction is the quantised TRAVEL bearing -- the same dominant-axis
  -- rule the blocked push below uses -- because what the cartridge tests is
  -- the cell you are heading INTO.  (checkGen2Whirlpool also answers for an
  -- eddy underfoot, which is how a save left standing on one gets spun back
  -- out; a free walker who reached one before this existed is rescued by the
  -- same line.)
  --
  -- Once it fires, the engine owns the player: it sets p.spinning and
  -- p.inputLocked, so the very next tick takes the branch at the top of this
  -- function and the free walk stands aside for the whole 32-frame whirl and
  -- the 20-frame turn-around after it.  Dropping here is what hands the body
  -- card back, so the turn-around is drawn with the engine's own four-way
  -- facing rather than a bearing this module froze.
  --
  -- It costs one call per moving frame off Gen 2, where checkGen2Whirlpool
  -- answers false on its third line.
  local travel = math.abs(dx) >= math.abs(dz)
                 and (dx > 0 and "right" or "left")
                 or (dz > 0 and "down" or "up")
  if state.checkGen2Whirlpool and state:checkGen2Whirlpool(travel) then
    FreeMove.drop()
    return
  end

  local hitX = slideX(state, p, dx)
  local hitZ = slideZ(state, p, dz)

  -- the walk cycle: the wall-bonk clock animates the legs of a player the
  -- grid thinks is standing still, refreshed while the free walk covers
  -- ground (Player:update ticks animClock off it; walkPhase reads it)
  p.bumpFrames = 2

  p.px, p.py = pos.x - 8, pos.z - 8
  lastPx, lastPy = p.px, p.py

  -- the cell the body stands in; crossing into a new one IS a step
  local ncx = math.floor(pos.x / 16)
  local ncy = math.floor(pos.z / 16)
  if ncx ~= p.cellX or ncy ~= p.cellY then
    p.cellX, p.cellY = ncx, ncy
    state:onStepComplete()
    -- a warp or a battle may have moved the world out from under the
    -- walk; the adopt check on the next tick picks the pieces up
    return
  end

  -- a firm push into something that refused: the engine's own blocked-step
  -- verbs, aimed the way the push leans
  local hit, dir
  if hitX and (not hitZ or math.abs(dx) >= math.abs(dz)) then
    hit, dir = hitX, (dx > 0 and "right" or "left")
  elseif hitZ then
    hit, dir = hitZ, (dz > 0 and "down" or "up")
  end
  if hit and math.max(math.abs(dx), math.abs(dz)) > 0.4 * speed then
    if pushSpecials(state, dir, hit) then
      FreeMove.drop()
      return
    end
    -- the push handlers may have turned the facing; the walk still rules
    p.facing = FirstPerson.pointBody(wx, wz)
  end
end

-- ------- the seam
--
-- OverworldState:handleInput is the one choke point where the grid walk
-- reads the pad -- the same seam the engine's own Cycling Road pull and
-- collision warps live behind -- so replacing the walk means wrapping it
-- and nothing else. Every gate ABOVE the call (scripted moves, trainer
-- engagement, transitions, anything on the stack) still applies to the
-- free walk, because the wrap sits below them all.
function FreeMove.install()
  local OverworldState = require("src.world.OverworldController")
  if OverworldState.dramaticShapeFreeMoveHook then return end
  local inner = OverworldState.handleInput

  function OverworldState:handleInput()
    if not FirstPerson.driving() then
      if pos then
        -- stepping off the rung: back onto the grid, on the cell the
        -- free walk stood in
        local p = self.player
        p.px, p.py = p.cellX * 16, p.cellY * 16
        FreeMove.drop()
      end
      return inner(self)
    end
    return FreeMove.tick(self)
  end

  OverworldState.dramaticShapeFreeMoveHook = true
end

return FreeMove
