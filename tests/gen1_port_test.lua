package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Pipelines = require("src.render.Pipelines")
local Runtime = require("src.mods.Runtime")
local Game = require("src.core.Game")
require("src.core.Input"):applyBindings({})
local Tilt = require("src.render.Tilt")
local Targets = require("src.mods.ModTargets")
local data = T.fixtures.load()
local run = T.sdk.loadMod(os.getenv("DS_MOD_PATH") or "mods/DRAMATIC_SHAPE",
                          { data = data })

T.eq(#run.errors, 0, "loads through the Gen 1 loader")
assert(run.loader.exports.DRAMATIC_SHAPE, table.concat(run.errors, "; "))
local namespace = run.loader.exports.DRAMATIC_SHAPE.lib
local manifest = run.loader.mods.DRAMATIC_SHAPE.manifest
for _, version in ipairs({ "red", "blue", "yellow" }) do
  T.check(Targets.supports(manifest, version), "targets " .. version)
end
T.check(not Targets.supports(manifest, "gold"), "does not claim untested Gen 2 support")
T.check(Targets.supports(manifest, "emerald"), "allows the requested Emerald game")
T.eq(manifest.github, nil, "upstream updates cannot overwrite the port")

Pipelines.install(data)
T.eq(data.render_pipelines._owners.voxel, "DRAMATIC_SHAPE", "owns the world pipeline")
T.eq(type(data.render_pipelines.voxel.drawWorld), "function", "registers world rendering")
T.eq(type(data.render_pipelines.tiltshift.worldPresent), "function", "registers tilt shift")
T.eq(Pipelines.level("voxel"), 0, "starts with voxel mode off")
Pipelines.setLevel("voxel", 2)
T.eq(Pipelines.worldPipeline(), nil, "keeps 2D rendering without GPU support")

local overworld = { transitioning = false }
local writes = 0
local game = {
  data = data,
  overworld = overworld,
  stack = { top = function() return overworld end },
  save = { options = { tilt = 3, gbcfx = 2, pipelines = {}, modOptions = {},
                      shaderfx = "preset-one", shaderfx2 = "preset-two" } },
  mods = { modOptions = {} },
  writeOptions = function() writes = writes + 1 end,
}

local function optionRows()
  local rows = Runtime.call("ui.options.rows", function(_, value) return value end,
    game, { { id = "tilt" }, { id = "gbcfx" }, { id = "shaderfx" },
            { id = "shaderfx2" }, { id = "pipeline:voxel" },
            { id = "pipeline:tiltshift" }, { id = "battleLayout" } })
  local byId = {}
  for _, row in ipairs(rows) do byId[row.id] = row end
  return byId
end

Tilt.setLevel(3)
local rows = optionRows()
T.check(rows["DRAMATIC_SHAPE:grid"], "offers voxel settings")
T.check(rows["DRAMATIC_SHAPE:battles"], "offers staged battles")
T.check(rows["DRAMATIC_SHAPE:aa"], "offers antialiasing")
T.check(not rows.tilt and not rows.gbcfx, "removes conflicting legacy rows")
T.eq(Tilt.level, 0, "disables live tilt")
T.eq(game.save.options.tilt, 0, "disables saved tilt")
T.eq(game.save.options.gbcfx, 0, "clears obsolete GBCFX options without requiring the module")
T.check(rows.shaderfx and rows.shaderfx2, "keeps both ShaderFX controls")
T.eq(game.save.options.shaderfx, "preset-one", "preserves the first ShaderFX preset")
T.eq(game.save.options.shaderfx2, "preset-two", "preserves the second ShaderFX preset")

local voxel = namespace.require("VoxelState")
Pipelines.setLevel("voxel", voxel.FULL_LEVEL)
rows = optionRows()
T.check(rows["pipeline:voxel"], "FULL keeps its own row")
T.check(not rows["pipeline:tiltshift"], "FULL hides its preset-controlled blur")
T.check(rows["DRAMATIC_SHAPE:aa"], "FULL leaves performance controls available")
T.check(rows.shaderfx and rows.shaderfx2, "FULL also preserves ShaderFX controls")

Pipelines.setLevel("voxel", 0)
for _, expected in ipairs({ 2, 3, 4, 5, voxel.FP_LEVEL, voxel.TP_LEVEL, 0 }) do
  Game.keypressed(game, "3")
  T.eq(Pipelines.level("voxel"), expected, "hotkey cycles camera rungs")
  T.eq(game.save.options.pipelines.voxel, expected, "hotkey persists the rung")
end
T.check(writes >= 7, "camera changes write options")
T.eq(game.save.options.shaderfx, "preset-one", "camera hotkeys preserve ShaderFX")

local grid = namespace.require("VoxelGrid").setting
grid:sync(false)
Game.keypressed(game, "5")
T.eq(grid:get(), true, "wireframe hotkey works")
T.eq(game.save.options.modOptions.DRAMATIC_SHAPE.grid, true, "settings use the port namespace")
overworld.transitioning = true
Game.keypressed(game, "5")
T.eq(grid:get(), true, "refuses setting changes during a warp")
overworld.transitioning = false

local typed = {}
local menu = { onKeyPressed = function(_, key) typed[#typed + 1] = key end }
game.stack.top = function() return menu end
for _, key in ipairs({ "3", "5", "6", "7", "8", "9" }) do
  Game.keypressed(game, key)
end
T.eq(#typed, 6, "text input receives all claimed keys")
T.eq(Pipelines.level("voxel"), 0, "typing does not change the camera")
T.eq(grid:get(), true, "typing does not change wireframe")

Pipelines.setLevel("voxel", 3)
Pipelines.setLevel("tiltshift", 2)
Pipelines.syncOptions(game.save.options)
Pipelines.reset()
Pipelines.applyOptions(game.save.options)
T.eq(Pipelines.level("voxel"), 3, "restores the saved camera")
T.eq(Pipelines.level("tiltshift"), 2, "restores the saved blur")
T.eq(Pipelines.worldPipeline(), nil, "restoring options still respects GPU availability")

local Collision = require("src.world.Collision")
local freeMove = namespace.require("FreeMove")
local player = { cellX = 1, cellY = 1, surfing = false }
local state = {
  player = player,
  entities = { player, { cellX = 2, cellY = 2 } },
  map = {
    def = { tileset = "PORT_TEST" },
    inBounds = function(_, cx, cy) return cx >= 0 and cy >= 0 and cx < 3 and cy < 3 end,
    isWalkableCell = function(_, cx, cy)
      return not (cx == 2 and cy == 1 or cx == 1 and cy == 2)
    end,
    isWaterCell = function(_, cx, cy) return cx == 1 and cy == 2 end,
    cellTile = function(_, cx) return cx == 0 and 3 or 1 end,
  },
}
Collision.load({ field = { tilePairs = {
  land = { { tileset = "PORT_TEST", a = 1, b = 3 } }, water = {},
} } })
for _, surfing in ipairs({ false, true }) do
  player.surfing = surfing
  for direction, delta in pairs(Collision.DELTA) do
    local allowed, reason = Collision.canMove(state.map, state.entities, player, direction)
    local blocked = freeMove._blockedCell(state, player,
      player.cellX + delta[1], player.cellY + delta[2], direction)
    T.eq(blocked == nil, allowed, "free movement matches the grid for " .. direction)
    if not allowed then T.eq(blocked, reason, "preserves the collision reason") end
  end
end
T.eq(freeMove._blockedCell(state, player, 2, 2, "right"), "entity", "diagonal probes check occupancy")
T.eq(freeMove._blockedCell(state, player, 3, 1, "right"), "bounds", "probes respect map edges")
T.eq(freeMove._blockedCell(state, player, 1, 1), nil, "the player's own cell never blocks")
T.eq(player.cellX, 1, "collision probes do not move the player horizontally")
T.eq(player.cellY, 1, "collision probes do not move the player vertically")

namespace.mod.hooks:wrap("movement.collision", function(next, allowed, context)
  allowed = next(allowed, context)
  if context.toX == 1 and context.toY == 0 then
    context.reason = "port-test-hook"
    return false
  end
  return allowed
end)
T.eq(freeMove._blockedCell(state, player, 1, 0, "up"), "port-test-hook",
  "free movement honors the engine collision hook")
Collision.load(data)
T.eq(#run.errors, 0, "callbacks complete without loader or hook errors")
run.release()
T.finish("dramatic_shape_gen1_port")