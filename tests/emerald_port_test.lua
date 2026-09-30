package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Pipelines = require("src.render.Pipelines")
local Runtime = require("src.mods.Runtime")
local Input = require("src.core.Input")
Input:applyBindings({})
require("src.core.GameVersion").set("emerald")
local sentinel = { label = "OTHER MOD", levels = { "OFF", "ON" } }
Pipelines.install({ render_pipelines = { unrelated = sentinel } })
Pipelines.setLevel("unrelated", 1)
local Rows = require("src.ui.game3.option_rows")
Rows.build = function() return { { id = "native-test" } } end
local run = T.sdk.loadMod("mods/DRAMATIC_SHAPE", { data = T.sdk.gen3Data(), generation = 3 })
T.eq(#run.errors, 0, "Emerald entry loads without unsupported APIs")
local exported = assert(run.loader.exports.DRAMATIC_SHAPE)
local port = assert(exported.emerald)
local namespace = exported.lib
local profiles = namespace.data("gen3_maps").maps
T.eq(profiles.EM_OLDALE_TOWN, profiles.MAP_G00_N10, "native Oldale uses its Emerald profile")
T.eq(profiles.EM_OLDALE_TOWN.primary, "gTileset_General", "resolves Emerald outdoor tiles")
T.eq(profiles.EM_OLDALE_TOWN.secondary, "gTileset_Petalburg", "resolves Emerald building tiles")
local NativeTileset = require("src.core.game3.tileset_native")
local getAtlas = NativeTileset.get
local atlas = { imageData = {}, midToSlot = { [1] = 0 } }
NativeTileset.get = function() return atlas end
local Layout = require("src.core.game3.layout_native")
local definition = { id = "EM_OLDALE_TOWN", pair = "general__petalburg",
  midLayout = Layout.fromDecoded({ width = 1, height = 1,
    cells = { { mid = 1, coll = 0, elev = 3 } } }, "EM_OLDALE_TOWN", "general__petalburg") }
local view = port.mapView(definition)
local Mesher = namespace.require("ChunkMesher")
local refresh, invalidate = Mesher.refresh, Mesher.invalidate
local refreshed, dropped = 0, 0
Mesher.refresh = function(id)
  T.eq(id, definition.id, "refresh targets the edited map")
  refreshed = refreshed + 1
end
Mesher.invalidate = function() dropped = dropped + 1 end
definition.midLayout:setMetatiles({ { x = 0, y = 0, mid = 1, elev = 4 } })
local replacement = port.mapView(definition)
T.check(replacement ~= view, "layout changes rebuild the native map view")
T.eq(replacement.def.elevationCells[1], 4, "refresh observes the edited elevation")
T.eq(refreshed, 1, "layout changes request a retained-mesh refresh")
T.eq(dropped, 0, "layout changes do not discard completed geometry")
T.eq(port.mapView(definition), replacement, "unchanged layouts reuse their refreshed view")
T.eq(refreshed, 1, "refresh is consumed once per layout change")
Mesher.refresh, Mesher.invalidate = refresh, invalidate
NativeTileset.get = getAtlas
T.eq(view.tileset.primaryKey, "TILESET_03DF704", "resolves Emerald terrain role owner")
local primary, secondary = view.tileset.id:match("TILESET_(%x+)_(%x+)")
local roles = namespace.data("gen3_metatiles").roles
T.check(roles["P" .. primary], "primary artwork roles are reachable")
T.check(roles["S" .. secondary], "secondary artwork roles are reachable")
T.eq(view.id, "EM_OLDALE_TOWN", "profile lookup preserves native gameplay identity")
T.eq(Pipelines.level("unrelated"), 1, "loading preserves other pipeline levels")
T.eq(namespace.engineRequire("src.world.Map"), namespace.require("NativeWorld"),
  "only the mod sees the native map adapter")
T.check(namespace.engineRequire("src.core.Game") ~= require("src.core.Game3"),
  "legacy game reads use a private view")
local forwarded = 0
local function forward() forwarded = forwarded + 1 end
local options = { shaderfx = "untouched", pipelines = { unrelated = 1 } }
local game = {
  mods = run.loader, options = options, phase = "boot", input = Input,
  update = forward, mousemoved = forward, mousepressed = forward,
  mousereleased = forward, gamepadaxis = forward, touchpressed = forward,
  touchmoved = forward, touchreleased = forward, writeOptions = forward,
}
Runtime.emit("game.ready", { game = game })
T.eq(port.game, game, "binds the live native instance")
T.eq(Pipelines.level("unrelated"), 1, "game.ready preserves other pipeline levels")
T.eq(game.options, options, "keeps the native options table")
T.eq(options.shaderfx, "untouched", "keeps ShaderFX selection")
game:update(1 / 60)
T.eq(forwarded, 1, "native update runs once")
game:mousemoved(0, 0, 1, 1, false)
game:mousepressed(0, 0, 1, false)
game:mousereleased(0, 0, 1, false)
game:touchpressed("finger", 0, 0)
game:touchmoved("finger", 1, 1)
game:touchreleased("finger", 1, 1)
game:gamepadaxis(nil, "rightx", 0)
T.eq(forwarded, 8, "inactive camera forwards native input")
T.check(not namespace.require("FirstPerson").captureAllowed(), "boot never captures the pointer")
T.eq(#run.errors, 0, "ready and update add no forbidden dependencies")
local context = { game = game, options = options }
local byId = {}
for _, row in ipairs(Rows.build(context)) do byId[row.id] = row end
T.check(byId["native-test"], "preserves native Options rows")
local camera = byId["DRAMATIC_SHAPE:camera"]
T.check(camera, "native Options exposes the voxel camera")
T.eq(camera:value(), "OFF", "voxel camera starts explicitly OFF")
T.check(camera.step(context, 1), "native Options enables voxel mode")
T.eq(options.modOptions.DRAMATIC_SHAPE.camera, 1, "native Options persists the camera")
T.eq(run.loader.modOptions.DRAMATIC_SHAPE.camera, 1, "mod settings share the native Options value")
local Tilt = require("src.render.Tilt")
Tilt.setLevel(2)
game.phase = "field"
require("src.core.Game3").keypressed(game, "3")
T.eq(options.modOptions.DRAMATIC_SHAPE.camera, 4, "3 advances from FULL to the next voxel angle")
T.eq(Tilt.level, 2, "the voxel hotkey does not change native Tilt")
run.loader.modOptions.DRAMATIC_SHAPE.camera = 0
Runtime.emit("mod.options_changed", { mod = "DRAMATIC_SHAPE" })
T.eq(camera:value(), "OFF", "native Options reflects camera changes from mod settings")
for _, row in ipairs(Rows.build({ options = {} })) do
  T.check(row.id ~= "DRAMATIC_SHAPE:camera", "voxel rows require the owning game")
end
local Structures = namespace.require("Structures")
local heightMap = { id = "DS_HEIGHT_SNAPSHOT_TEST" }
local snapshot = { synthZ = { [0] = 112 } }
T.eq(Structures.terraceAt(heightMap, 0, 0), nil, "height probe starts without cached geometry")
local height = Structures.withSnapshot(heightMap, snapshot, function(map)
  T.eq(Structures.terraceAt(map, 0, 0), 112, "height reads use the completed snapshot")
  local inner = Structures.withSnapshot(map, { synthZ = { [0] = 48 } },
    function(nested) return Structures.terraceAt(nested, 0, 0) end)
  T.eq(inner, 48, "nested height reads use their own snapshot")
  return Structures.terraceAt(map, 0, 0)
end)
T.eq(height, 112, "nested reads restore the outer snapshot")
T.eq(Structures.terraceAt(heightMap, 0, 0), nil, "height sampling restores the build cache")
local ok, problem = pcall(Structures.withSnapshot, heightMap, snapshot,
  function() error("height-read-probe") end)
T.check(not ok and tostring(problem):find("height-read-probe", 1, true),
  "height sampling propagates reader failures")
T.eq(Structures.terraceAt(heightMap, 0, 0), nil, "failed reads also restore the build cache")
T.finish()