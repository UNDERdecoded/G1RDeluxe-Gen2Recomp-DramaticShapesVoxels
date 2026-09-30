local Sprites = require("src.core.game3.ow_sprites")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Space = require("src.core.game3.scripting.space")
local NativeActors = {}
local views = setmetatable({}, { __mode = "k" })

local function actorView(native, graphicsId, isPlayer)
  local sheet = Sprites.getDraw(graphicsId)
  if not sheet then return nil end
  local view = views[native]
  if not view or view.sheet ~= sheet then
    view = setmetatable({ source = native, sheet = sheet }, { __index = native })
    local sprite = { def = {
      image = "native:" .. tostring(sheet), nativeImage = sheet.image,
      frameWidth = sheet.width, frameHeight = sheet.height,
      frames = sheet.frameCount, trueColor = true,
    } }
    function sprite:resolveImage() return sheet.image end
    function sprite.def.nativeFrame(facing, phase, flip)
      return Sprites.pose(sheet, facing, phase, flip, view.poseOptions)
    end
    view.sprite = sprite
    function view:pose()
      return self.sprite, self.drawX, self.drawY, self.facing, self.phase, self.stepFlip
    end
    views[native] = view
  end
  view.px = native.px or (native.cellX or 0) * 16
  view.py = native.py or (native.cellY or 0) * 16
  view.facing = native.facing or "down"
  view.hidden = false
  view.phase = isPlayer and Player.walkPhase() or Objects.walkPhase(native)
  view.stepFlip = isPlayer and Player.drawFlip() or native.stepFlip
  view.poseOptions = {}
  if isPlayer then
    local options = view.poseOptions
    options.running = Player.runPose and Player.runPose() or nil
    options.frame = Player.acroFrame and Player.acroFrame() or nil
    options.fieldMove = (Player.fieldMoveAnim or 0) > 0
    if options.fieldMove then
      options.fieldMoveFrame = Sprites.fieldMoveFrame(
        (Player.fieldMoveTotal or Player.fieldMoveAnim) - Player.fieldMoveAnim,
        Player.fieldMoveKind)
    end
    local fishFrame, fishX, fishY
    if not options.fieldMove and Field.fishingPose then
      fishFrame, fishX, fishY = Field.fishingPose()
    end
    options.fishing, options.fishFrame = fishFrame ~= nil, fishFrame
    local jumpY = native.spriteYOffset or 0
    if jumpY == 0 and Player.jumpSpriteY then jumpY = Player.jumpSpriteY() or 0 end
    view.drawX = view.px + (native.spriteXOffset or 0) + (fishX or 0)
    view.drawY = view.py + jumpY + (fishY or 0)
  else
    view.poseOptions.frame = native.customFrame
    view.poseOptions.bow = (native.bowFrames and native.bowFrames > 8
      and native.bowFrames <= 40) or native.raiseHand == true
    view.drawX = view.px + (native.raiseX or 0)
    view.drawY = view.py + (native.raiseY or 0)
  end
  return view
end

function NativeActors.collect(game, state)
  local entities = state.entities
  for index = #entities, 1, -1 do entities[index] = nil end
  for _, native in ipairs(Objects.forDraw()) do
    local graphicsId = native.graphicsId or (native.def and native.def.graphicsId)
    if native.def and Space.resolveObjectGraphicsId then
      graphicsId = Space.resolveObjectGraphicsId(native.def) or graphicsId
    end
    local view = actorView(native, graphicsId, false)
    if view then entities[#entities + 1] = view end
  end
  local player = actorView(Player, Sprites.playerGraphicsId(game), true)
  state.player = player or Player
  if player and (not Player.isVisible or Player.isVisible()) then
    entities[#entities + 1] = player
  end
end

return NativeActors