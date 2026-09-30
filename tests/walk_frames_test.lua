-- EMERALD'S SECOND WALK LEG, and the two sheet layouts that must both work.
--
-- Reported from play: "ensure the walking animation is using the proper
-- frames of emerald gen3 -- currently it looks like its not showing the full
-- walk sprite animation".
--
-- A Game Boy walker draws ONE step per direction and mirrors it for the other
-- leg; Emerald DRAWS both.  Its `GO_SOUTH` animation is step, hold, step,
-- hold -- four commands, two different step frames -- so its walker sheet is
-- nine rows, not six.  The import took the first step of each direction and
-- stopped, so the port walked a Game Boy cycle on Game Boy Advance art.
--
-- Three things are pinned here:
--   1. the READER: the other leg is the animation's THIRD command, and the
--      second command is the standing HOLD -- which is why animSecondFrame
--      would have extracted the stand frame twice;
--   2. the SELECTION, over both layouts: a six-row sheet (every Gen 1, Gen 2
--      and Prism sheet, and every Gen 3 cache imported before this change)
--      must behave byte-for-byte as it did, and a nine-row sheet gets the
--      drawn leg;
--   3. the SHARE: the flat path and the voxel billboard path must reach the
--      same answer through ONE function, not two copies of it.
--
-- BOUNDARY, stated plainly: there is no ROM and no assets/generated in this
-- tree, so no real nine-row sheet can be produced or measured here.  These
-- are synthesised against the cartridge's documented command order; they
-- prove the code handles both layouts, not that a real re-import is correct.
local ENGINE = os.getenv("ENGINE") or "."
package.path = ENGINE .. "/?.lua;" .. ENGINE .. "/?/init.lua;" .. package.path
local MOD = os.getenv("MOD") or "mods/DRAMATIC_SHAPE"
if MOD:sub(-1) ~= "/" then MOD = MOD .. "/" end
_G.love = require("tests.love_stub")
local meshVerts = setmetatable({}, { __mode = "k" })
love.graphics.newMesh = function(_, verts)
  local m = { release = function() end, setVertexMap = function() end }
  meshVerts[m] = verts
  return m
end

local pass, fail = 0, 0
local function eq(a, b, what)
  if type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 then
    pass = pass + 1
  elseif type(a) ~= "number" and a == b then pass = pass + 1
  else fail = fail + 1
    io.write("  FAIL  ", what, ": got ", tostring(a), ", want ", tostring(b), "\n") end
end
local function ok(c, what)
  if c then pass = pass + 1 else fail = fail + 1; io.write("  FAIL  ", what, "\n") end
end

-- ------------------------------------------------ 1. the reader

io.write("the other leg is the THIRD command, not the second\n")

local Rom = require("src.import.RomExtractorGen3")

-- An ANIMCMD_FRAME word: the frame index in the low halfword, the duration
-- above it, and bit 22 the horizontal flip (see animFirstFrame).
local function FRAME(index, duration) return index + (duration or 8) * 65536 end
local END = 0xFFFF

-- Emerald's own walk animation shape, laid out at synthetic addresses:
-- `GO_SOUTH` = step 3, hold 0, step 4, hold 0.  The hold is the STANDING
-- frame, which is exactly what makes it checkable against the facing slot.
local ANIMS, LIST = 0x1000, 0x2000
local words, ptrs = {}, {}
ptrs[ANIMS + 4 * 4] = LIST                        -- slot 4 == GO_SOUTH
words[LIST + 0], words[LIST + 4] = FRAME(3), FRAME(0)
words[LIST + 8], words[LIST + 12] = FRAME(4), FRAME(0)
local ex = setmetatable({ rom = {
  pointer = function(_, at) return ptrs[at] end,
  u32 = function(_, at) return words[at] or 0 end,
} }, Rom)

-- asked through a shim so a tree without the reader FAILS these rather than
-- dying on the first one: the before/after counts have to be comparable
local function third(anims, index)
  if type(Rom.animThirdFrame) ~= "function" then return nil end
  return ex:animThirdFrame(anims, index)
end
ok(type(Rom.animThirdFrame) == "function", "RomExtractorGen3:animThirdFrame exists")

eq(ex:animFirstFrame(ANIMS, 4), 3, "the first command is the first leg")
eq(ex:animSecondFrame(ANIMS, 4), 0,
   "the second command is the standing HOLD -- reading it for the other leg "
   .. "would have extracted the stand frame a second time")
eq(third(ANIMS, 4), 4, "the third command is the OTHER LEG")
ok(third(ANIMS, 4) ~= nil and third(ANIMS, 4) ~= ex:animFirstFrame(ANIMS, 4),
   "and it is a different frame from the first")

-- the reader refuses what is not a frame, so a cartridge laid out some other
-- way comes back with nothing rather than with a terminator read as art
words[LIST + 8] = END
ok(third(ANIMS, 4) == nil, "a terminator is not a frame")
words[LIST + 8] = FRAME(4) + 0x01000000
ok(third(ANIMS, 4) == nil, "nor is a word with a top byte set")
words[LIST + 8] = FRAME(4)
ok(third(ANIMS, 9) == nil, "an empty animation slot answers nil")

-- ------------------------------------------------ 2. the selection

io.write("six rows behave as they always did; nine rows draw the other leg\n")

package.loaded["src.render.Assets"] = {
  image = function() return { getDimensions = function() return 16, 288 end } end,
  imageData = function() return nil end,
  register = function() end,
}
local SR = require("src.render.SpriteRenderer")

local SIX  = { id = "SPRITE_G3_000", image = "p.png", frames = 6, walker = true,
               frameWidth = 16, frameHeight = 32, trueColor = true }
local NINE = { id = "SPRITE_G3_000", image = "p.png", frames = 9, walker = true,
               frameWidth = 16, frameHeight = 32, trueColor = true }
-- a Gen 1 / Gen 2 / Prism sheet states no frame box, whatever its row count
local G12  = { id = "SPRITE_RED", image = "g1.png", frames = 6, walker = true }
local G12B = { id = "SPRITE_RED", image = "g1.png", frames = 9, walker = true }

ok(type(SR.poseFrame) == "function", "SpriteRenderer.poseFrame exists")
ok(type(SR.WALK_B) == "table", "and the second-leg table is published")
if type(SR.WALK_B) == "table" then
  -- the cartridge's own order: south, north, west, east-is-west-flipped
  eq(SR.WALK_B.down, 6, "WALK_B south is row 6")
  eq(SR.WALK_B.up, 7, "WALK_B north is row 7")
  eq(SR.WALK_B.left, 8, "WALK_B west is row 8")
  eq(SR.WALK_B.right, SR.WALK_B.left, "and east is the same row, mirrored")
end

local function poseOf(def, facing, phase, flip)
  if type(SR.poseFrame) ~= "function" then return nil, nil end
  return SR.poseFrame(def, facing, phase, flip)
end

-- THE SIX-ROW GOLDEN TABLE.  This is what the engine drew before any of this
-- existed, measured off the shipped build (_scratch/frameprobe.lua, 0
-- disagreements over 2656 combinations across 166 real Emerald walker defs).
-- Every row of it must still hold, or an existing imported cache animates
-- differently after an update that is supposed to leave it alone.
local GOLDEN = {
  { "down",  0, false, 0, false }, { "down",  0, true,  0, false },
  { "down",  1, false, 3, false }, { "down",  1, true,  3, true  },
  { "up",    0, false, 1, false }, { "up",    0, true,  1, false },
  { "up",    1, false, 4, false }, { "up",    1, true,  4, true  },
  { "left",  0, false, 2, false }, { "left",  0, true,  2, false },
  { "left",  1, false, 5, false }, { "left",  1, true,  5, false },
  { "right", 0, false, 2, true  }, { "right", 0, true,  2, true  },
  { "right", 1, false, 5, true  }, { "right", 1, true,  5, true  },
}
for _, g in ipairs(GOLDEN) do
  local facing, phase, flip, wantF, wantM = g[1], g[2], g[3], g[4], g[5]
  local tag = ("6-row %s ph=%d flip=%s"):format(facing, phase, tostring(flip))
  local f, m = poseOf(SIX, facing, phase, flip)
  eq(f, wantF, tag .. ": frame")
  eq(not not m, wantM, tag .. ": mirror")
  -- ...and a Gen 1 / Gen 2 / Prism sheet answers the very same thing
  local gf, gm = poseOf(G12, facing, phase, flip)
  eq(gf, wantF, tag .. ": gen1/gen2 frame")
  eq(not not gm, wantM, tag .. ": gen1/gen2 mirror")
  -- EVEN AT NINE ROWS, because it states no frame box: the second-leg branch
  -- is gated on `frameWidth`, which only the Gen 3 importer ever writes
  local bf, bm = poseOf(G12B, facing, phase, flip)
  eq(bf, wantF, tag .. ": gen1/gen2 shape at 9 rows is still unchanged")
  eq(not not bm, wantM, tag .. ": ...and still mirrors rather than drawing")
end

-- THE NINE-ROW CYCLE: the alternate step is DRAWN, so it stops being mirrored
local NINE_WANT = {
  { "down",  1, false, 3, false }, { "down",  1, true,  6, false },
  { "up",    1, false, 4, false }, { "up",    1, true,  7, false },
  { "left",  1, false, 5, false }, { "left",  1, true,  8, false },
  -- east keeps its mirror: that half is the cartridge's own doing and holds
  -- for all nine rows
  { "right", 1, false, 5, true  }, { "right", 1, true,  8, true  },
  -- standing is untouched by any of it
  { "down",  0, false, 0, false }, { "down",  0, true,  0, false },
  { "up",    0, true,  1, false }, { "left",  0, true,  2, false },
  { "right", 0, true,  2, true  },
}
for _, g in ipairs(NINE_WANT) do
  local facing, phase, flip, wantF, wantM = g[1], g[2], g[3], g[4], g[5]
  local tag = ("9-row %s ph=%d flip=%s"):format(facing, phase, tostring(flip))
  local f, m = poseOf(NINE, facing, phase, flip)
  eq(f, wantF, tag .. ": frame")
  eq(not not m, wantM, tag .. ": mirror")
end

-- THE WHOLE CYCLE, DRIVEN BY THE ENGINE'S OWN CLOCK.
--
-- Player:walkPhase is `(animClock % 16) >= 4 and < 12`, and the alternate
-- step is `floor(animClock / 16) % 2 == 1` (Player:pose) -- so one full walk
-- cycle is 32 ticks and shows the standing pose, one leg, the standing pose
-- and the OTHER leg.  On six rows that is two drawn rows, one of them shown
-- mirrored; on nine it is three drawn rows and no mirroring at all.
local function cycle(def, facing)
  local seenFrames, seenMirrored, order = {}, 0, {}
  for clock = 0, 31 do
    local phase = ((clock % 16) >= 4 and (clock % 16) < 12) and 1 or 0
    local stepFlip = math.floor(clock / 16) % 2 == 1
    local f, m = poseOf(def, facing, phase, stepFlip)
    -- a tree with no poseFrame answers nil; count it as its own "frame" so
    -- the cycle checks FAIL rather than dying on a nil table index
    if f == nil then f = "none" end
    seenFrames[f] = true
    if m then seenMirrored = seenMirrored + 1 end
    if order[#order] ~= f then order[#order + 1] = f end
  end
  local n = 0
  for _ in pairs(seenFrames) do n = n + 1 end
  return n, seenMirrored, order
end

for _, facing in ipairs({ "down", "up" }) do
  local n6 = cycle(SIX, facing)
  local n9, mir9, order9 = cycle(NINE, facing)
  eq(n6, 2, facing .. ": a six-row cycle draws TWO rows (one of them mirrored)")
  eq(n9, 3, facing .. ": a nine-row cycle draws THREE -- stand, leg, other leg")
  eq(mir9, 0, facing .. ": and mirrors nothing, because both legs are drawn")
  -- stand, leg, stand, other leg -- the cartridge's own order.  Five runs
  -- rather than four over clock 0..31: the last four ticks are the standing
  -- pose the NEXT cycle opens on, so the fifth run is the first one coming
  -- round again (MEASURED: ticks 0-3 stand, 4-11 leg, 12-19 stand across the
  -- 16-tick boundary, 20-27 other leg, 28-31 stand).
  eq(#order9, 5, facing .. ": the cycle is stand, step, stand, step, (stand)")
  eq(order9[1], SR.STAND and SR.STAND[facing], facing .. ": it opens standing")
  eq(order9[2], SR.WALK and SR.WALK[facing], facing .. ": then the first leg")
  eq(order9[3], SR.STAND and SR.STAND[facing], facing .. ": then standing again")
  eq(order9[4], SR.WALK_B and SR.WALK_B[facing], facing .. ": then the other leg")
  eq(order9[5], order9[1], facing .. ": and comes round to the standing pose")
end
do
  -- west and east never alternated at all on six rows: the Game Boy had no
  -- second side-on frame to alternate to
  local n6 = cycle(SIX, "left")
  local n9 = cycle(NINE, "left")
  eq(n6, 2, "left: six rows show a stand and one step, forever")
  eq(n9, 3, "left: nine rows finally give it a second step")
  local _, mir6 = cycle(SIX, "right")
  local _, mir9r = cycle(NINE, "right")
  eq(mir6, 32, "right: every frame is mirrored on six rows...")
  eq(mir9r, 32, "...and on nine too -- east is west flipped either way")
end

-- ------------------------------------------------ 3. the share

io.write("both draw paths ask one function\n")

-- the REAL frameFor, by source slice, so this measures the shipped text
local vsrc = io.open(MOD .. "lib/VoxelScene.lua"):read("a")
local body = vsrc:match("(local function frameFor%(def, facing, phase, flip, stated%).-\nend\n)")
ok(body ~= nil, "frameFor is still where the slice expects it")
ok(body and not body:match("SR%.WALK%["),
   "and no longer indexes the facing tables itself -- one statement, not two")
ok(body and body:match("SR%.poseFrame"), "it asks SpriteRenderer.poseFrame")

if body then
  local frameFor = assert(loadstring(body .. "\nreturn frameFor"))()
  local disagree = 0
  for _, def in ipairs({ SIX, NINE, G12, G12B }) do
    for _, facing in ipairs({ "down", "up", "left", "right" }) do
      for phase = 0, 1 do
        for _, flip in ipairs({ false, true }) do
          local f2, m2 = poseOf(def, facing, phase, flip)
          local f3, m3 = frameFor(def, facing, phase, flip, nil)
          if f2 ~= f3 or (not not m2) ~= (not not m3) then
            disagree = disagree + 1
          end
        end
      end
    end
  end
  eq(disagree, 0, "the voxel path agrees with the flat path on every "
     .. "(layout, facing, phase, flip) -- 64 combinations")
end

-- ...and the mod's card builder can actually cut the new rows
local SBV = {}
local sbmods = {}
function SBV.require(name)
  local hit = sbmods[name]; if hit ~= nil then return hit end
  local v = assert(loadfile(MOD .. "lib/" .. name .. ".lua"))(SBV)
  sbmods[name] = v
  return v
end
do
  local sheets = {}
  package.loaded["src.render.Assets"] = {
    image = function(p) return sheets[p] end, register = function() end,
  }
  sheets["p9.png"] = { getDimensions = function() return 16, 288 end }
  sheets["p6.png"] = { getDimensions = function() return 16, 192 end }
  local SB = SBV.require("SpriteBillboards")
  local nine9 = { id = "SPRITE_G3_000", image = "p9.png", frames = 9,
                  frameWidth = 16, frameHeight = 32, walker = true }
  SB.invalidate()
  local m = SB.mesh(nine9, 8)
  local v = m and meshVerts[m]
  ok(v ~= nil, "a nine-row card builds")
  if v then
    eq(v[4][5] * 288, 8 * 32 + 0.05, "row 8 is cut at y=256, the last row")
    eq(v[1][5] * 288, 9 * 32 - 0.05, "and ends at y=288, the sheet's bottom")
  end
  -- a six-row sheet asked for row 8 clamps to 0 rather than reading past the
  -- bottom: the layouts cannot be mixed even by accident
  local six6 = { id = "SPRITE_G3_000", image = "p6.png", frames = 6,
                 frameWidth = 16, frameHeight = 32, walker = true }
  SB.invalidate()
  local m6 = SB.mesh(six6, 8)
  local v6 = m6 and meshVerts[m6]
  ok(v6 ~= nil, "a six-row card still builds when asked for a row it lacks")
  if v6 then eq(v6[4][5] * 192, 0.05, "and clamps to row 0 rather than past the end") end
end

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
