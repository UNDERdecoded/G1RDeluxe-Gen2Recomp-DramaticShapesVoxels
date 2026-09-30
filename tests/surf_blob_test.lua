-- The surf blob, in the diorama: the thing the player sits on when SURF is up.
--
-- Reported from play: "still missing the surf blob beneath the player when
-- surfing, add that and make sure its working as well -- this is with voxels
-- on in any mode, first and third person or not".  With voxels on the player
-- is a billboard built by VoxelScene.drawEntity, so Player:draw -- the one
-- place that knew the blob existed -- never runs.
--
-- Two halves are pinned here: the ENGINE's published answer
-- (Player:surfBlobCard, which the flat path's own :drawSurfBlob is written in
-- terms of) and the VOXEL pass that asks it (VoxelScene.drawSurfBlob).
--
-- The engine tree this suite runs against.  Defaults to the current
-- directory, so the suite runs from a repository checkout on any machine;
-- override with ENGINE=... to point it somewhere else.
local ENGINE = os.getenv("ENGINE") or "."
package.path = ENGINE .. "/?.lua;" .. ENGINE .. "/?/init.lua;" .. package.path
-- The mod under test.  Defaults to the tree this suite ships in.
local MOD = os.getenv("MOD") or "mods/DRAMATIC_SHAPE"
if MOD:sub(-1) ~= "/" then MOD = MOD .. "/" end
_G.love = require("tests.love_stub")
-- love_stub leaves newMesh absent on purpose (headless takes the flat path),
-- so the card builders need one here -- the same stub sprite_card_test uses,
-- keeping the vertex list so the quad's UVs say which sheet row it cut.
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

-- the REAL Emerald record this tree ships: 32x32, three frames, one per
-- facing (south / north / west; east is west mirrored)
local constants = assert(loadfile(ENGINE .. "/data/generated/constants.lua"))()
local BLOB = assert(constants.gen3SurfBlob, "this dataset has no gen3SurfBlob")

local sheet = { getWidth = function() return BLOB.frameWidth end,
                getHeight = function() return BLOB.frameHeight * BLOB.frames end,
                getDimensions = function()
                  return BLOB.frameWidth, BLOB.frameHeight * BLOB.frames end }
package.loaded["src.render.Assets"] = {
  image = function() return sheet end,
  imageData = function() return nil end,
  register = function() end,
}

local Game = require("src.core.Game")
Game.data = { constants = constants }
Game.overworld = nil

-- ---------------------------------------------------------------- the engine

local Player = require("src.world.Player")

local function surfer(facing, underwater)
  return setmetatable({ surfing = true, facing = facing or "down",
                        isUnderwater = function() return underwater == true end },
                      Player)
end

io.write("the engine publishes the blob's card\n")

ok(type(Player.surfBlobCard) == "function",
   "Player:surfBlobCard exists -- the voxel pass has something to ask")

-- asked through a shim so a tree without the function FAILS these rather
-- than dying on the first one: the before/after counts have to be comparable
local function card(p, facing)
  if type(Player.surfBlobCard) ~= "function" then return nil end
  return p:surfBlobCard(facing)
end

-- the cartridge's own order, and east is west flipped
local WANT = { down = { 0, false }, up = { 1, false },
               left = { 2, false }, right = { 2, true } }
for _, facing in ipairs({ "down", "up", "left", "right" }) do
  local blob, frame, mirror = card(surfer(facing))
  ok(blob == BLOB, facing .. ": the card is the dataset's own record")
  eq(frame, WANT[facing][1], facing .. ": frame")
  eq(mirror, WANT[facing][2], facing .. ": mirror")
end

-- the POSE's facing beats the body's: spinner tiles whirl the drawn sprite
-- through all four while self.facing stays put (Player:pose)
do
  local _, frame = card(surfer("down"), "left")
  eq(frame, 2, "the pose's facing is what the blob turns with")
end

-- MEASURED off this record: 32x32 on a 16px cell, so -floor((32-16)/2) = -8
-- east and -(32-16) + 8 = -8 north -- the cell grown 8px on every side,
-- centred on the very cell middle a billboard is anchored to (footAnchor = 8)
do
  local _, _, _, offX, offY = card(surfer("down"))
  eq(offX, -8, "offX centres the 32-wide sheet on the 16px cell")
  eq(offY, -8, "offY is the sheet's hang plus the cartridge's +8")
  eq((offX or 0) + BLOB.frameWidth / 2, 8, "so the blob's middle is the cell's middle")
  eq((offY or 0) + BLOB.frameHeight / 2, 8, "in both axes")
end

-- the three refusals, each of which is also what keeps Gen 1 / Gen 2 / Prism
-- drawing exactly nothing
do
  local p = surfer("down"); p.surfing = false
  ok(card(p) == nil, "not surfing: no card")
  ok(card(surfer("down", true)) == nil,
     "underwater: no card -- the cartridge destroys the blob on a dive")
  local saved = Game.data.constants
  Game.data = { constants = {} }
  ok(card(surfer("down")) == nil,
     "no gen3SurfBlob (Gen 1 / Gen 2 / Prism): no card")
  Game.data = { constants = saved }
end

-- ----------------------------------------------------------- the voxel pass

io.write("the voxel pass draws it, flat, on the player's own surface\n")

local V = {}
local modules = {}
function V.require(name)
  local hit = modules[name]; if hit ~= nil then return hit end
  local v = assert(loadfile(MOD .. "lib/" .. name .. ".lua"))(V)
  modules[name] = v
  return v
end
function V.data(name) return assert(loadfile(MOD .. "data/" .. name .. ".lua"))(V) end

local VoxelScene = V.require("VoxelScene")
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")
local FirstPerson = V.require("FirstPerson")

ok(type(VoxelScene.drawSurfBlob) == "function",
   "VoxelScene.drawSurfBlob exists")

-- capture the pass: what was drawn, and whether it went down as a DECAL
local drawn, decalDepth
local realDraw = Voxel3D.draw
local inDecal = false
Voxel3D.beginDecal = function() inDecal = true end
Voxel3D.endDecal = function() inDecal = false end
Voxel3D.draw = function(mesh, tex, model)
  drawn[#drawn + 1] = { mesh = mesh, tex = tex, model = model }
  decalDepth = inDecal
end

-- row-major, translation in the fourth column (Mat4's own header)
local function apply(m, x, y, z)
  return m[1] * x + m[2] * y + m[3] * z + m[4],
         m[5] * x + m[6] * y + m[7] * z + m[8],
         m[9] * x + m[10] * y + m[11] * z + m[12]
end

local PX, PY, GH, LIFT = 320, 480, 12, -1
local function poseOf(facing)
  return { px = PX, py = PY, gh = GH, lift = LIFT, facing = facing or "down",
           isPlayer = true }
end

-- the same shim on this side, and for the same reason
local function callDraw(state, me)
  if type(VoxelScene.drawSurfBlob) ~= "function" then return end
  pcall(VoxelScene.drawSurfBlob, state, me)
end

local function run(facing, player)
  drawn, decalDepth = {}, nil
  callDraw({ player = player or surfer(facing) }, poseOf(facing))
  return drawn
end

-- a quad's model matrix, or a matrix of NaNs so a tree that drew nothing
-- fails the geometry checks rather than dying indexing an empty list
local NOWHERE = {}
for i = 1, 16 do NOWHERE[i] = 0 / 0 end
local function modelOf(d) return (d[1] and d[1].model) or NOWHERE end

do
  local d = run("down")
  eq(#d, 1, "one quad is drawn for a surfing player")
  ok(decalDepth == true, "and it goes down inside the decal pass "
     .. "(depth tested, depth never written -- the card covers it after)")
  ok(d[1] and d[1].tex == sheet, "textured from the blob sheet itself")
end

-- the quad's world rectangle and its height
do
  local d = run("down")
  local m = modelOf(d)
  local fw, fh = BLOB.frameWidth, BLOB.frameHeight
  -- local (0,0) is the quad's SOUTH-WEST corner, (fw,fh) its NORTH-EAST
  local x0, y0, z0 = apply(m, 0, 0, 0)
  local x1, y1, z1 = apply(m, fw, fh, 0)
  eq(x0, PX - 8, "west edge is the cell's west edge less 8")
  eq(x1, PX - 8 + fw, "east edge is fw further on")
  eq(z0, PY - 8 + fh, "south edge")
  eq(z1, PY - 8, "north edge -- the sheet's top points north")
  -- THE HEIGHT IS THE PLAYER'S OWN, so the blob can never float away from
  -- him: gh + lift is the number drawEntity stands his card on, and `lift`
  -- is where the surf bob rides in (Player:pose, bobTimer % 32)
  eq(y0, GH + LIFT + Voxel3D.SHADOW_EPS, "south edge sits on the player's "
     .. "own surface, a shadow-epsilon clear of it")
  eq(y1, GH + LIFT + Voxel3D.SHADOW_EPS, "and so does the north edge -- flat")
end

-- the three frames are FACINGS, not a film strip: the quad's V range says
-- which 32px row of the 96px sheet it cut (MEASURED off the real record)
do
  local rows = { down = 0, up = 1, left = 2, right = 2 }
  local ih = BLOB.frameHeight * BLOB.frames
  for _, facing in ipairs({ "down", "up", "left", "right" }) do
    local d = run(facing)
    local v = d[1] and meshVerts[d[1].mesh]
    if not v then v = { [4] = { 0, 0, 0, 0, 0 / 0, 0 } } end
    -- verts are {x,y,z,u,v,shade}; [4] is the top-left corner of the quad
    eq(v[4][5] * ih, rows[facing] * BLOB.frameHeight + 0.05,
       facing .. ": the quad cuts sheet row " .. rows[facing])
  end
end

-- east is west mirrored, and the mirrored quad still covers the same box
do
  local dl = run("left")
  local dr = run("right")
  local fw = BLOB.frameWidth
  local lx0 = select(1, apply(modelOf(dl), 0, 0, 0))
  local rx0 = select(1, apply(modelOf(dr), 0, 0, 0))
  local rx1 = select(1, apply(modelOf(dr), fw, 0, 0))
  eq(lx0, PX - 8, "facing left, local x=0 is the west edge")
  eq(rx0, PX - 8 + fw, "facing right the quad is flipped in its own box...")
  eq(rx1, PX - 8, "...so it still covers exactly the same world rectangle")
end

-- the bob: one world pixel of lift moves the blob with the player
do
  drawn = {}
  local me = poseOf("down"); me.lift = 0
  callDraw({ player = surfer("down") }, me)
  local y = select(2, apply(modelOf(drawn), 0, 0, 0))
  eq(y, GH + Voxel3D.SHADOW_EPS, "bob up: the blob rises with him")
end

-- IN FIRST PERSON THE PLAYER'S OWN CARD IS LEFT OUT (drawCast's `hideMe`)
-- and the blob must NOT be: it is the only thing under you there is to see.
-- This pass is drawn outside that test, so it keeps drawing.
do
  local realHide = FirstPerson.hidePlayer
  FirstPerson.hidePlayer = function() return true end
  local d = run("down")
  eq(#d, 1, "1ST person (hidePlayer true): the blob is still drawn")
  FirstPerson.hidePlayer = realHide
end

-- ...and it is not turned to face the eye the way a CARD is. The blob really
-- lies in the world, so it wears the pose's frame whatever the camera does.
do
  local realFacing = FirstPerson.playerFacing
  FirstPerson.playerFacing = function() return "up" end
  local dA = run("down")
  FirstPerson.playerFacing = realFacing
  local dB = run("down")
  eq(dA[1] and dA[1].mesh, dB[1] and dB[1].mesh, "the eye's bearing does not swap the blob's frame")
end

-- the refusals reach the pass too
do
  local p = surfer("down"); p.surfing = false
  eq(#run("down", p), 0, "not surfing: nothing is drawn")
  eq(#run("down", surfer("down", true)), 0, "underwater: nothing is drawn")
  drawn = {}
  callDraw({ player = surfer("down") }, nil)
  eq(#drawn, 0, "no player pose in the list: nothing is drawn")
  drawn = {}
  callDraw({}, poseOf("down"))
  eq(#drawn, 0, "no player on the state: nothing is drawn")
end

Voxel3D.draw = realDraw

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
