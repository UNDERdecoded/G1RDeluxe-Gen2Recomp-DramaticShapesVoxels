local V = ...
local hostRequire = V.engineRequire
local NativeWorld = V.require("NativeWorld")
local NativeTiles = V.require("NativeTiles")
local NativeTileset = hostRequire("src.core.game3.tileset_native")
local Map = hostRequire("src.core.game3.map")
local Behaviors = hostRequire("src.core.game3.scripting.interaction_scripts")
local FieldView = hostRequire("src.core.game3.field_view")
local Renderer = hostRequire("src.render.Renderer")
local Emerald = { game = nil, state = nil, frames = 0 }
local maps = setmetatable({}, { __mode = "k" })
local changedLayouts = setmetatable({}, { __mode = "k" })
local gameView = {}
local tileRenderer = setmetatable({}, { __index = hostRequire("src.render.TileRenderer") })
local overworldView = {}

local MapCatalog = hostRequire("src.import.gba.map_catalog")
local Family = hostRequire("src.import.gba.family").active()
local symbols = Family:syms()
local mapProfiles = V.data("gen3_maps").maps
local nativeProfiles = {}
local tilesetProfiles = {}
for legacyId, profile in pairs(mapProfiles) do
  local group, number = legacyId:match("^MAP_G(%d+)_N(%d+)$")
  if group then
    local nativeId = MapCatalog.mapIdFor(tonumber(group), tonumber(number))
    if nativeId then nativeProfiles[nativeId] = profile end
  end
  if profile.primary and profile.secondary
      and symbols.has(profile.primary) and symbols.has(profile.secondary) then
    local primary = symbols.off(profile.primary)
    local secondary = symbols.off(profile.secondary)
    local nativePair = Family:tilesetName(primary) .. "__" .. Family:tilesetName(secondary)
    tilesetProfiles[nativePair] = {
      id = string.format("TILESET_%07X_%07X", primary, secondary),
      primaryKey = string.format("TILESET_%07X", primary),
      secondaryKey = string.format("TILESET_%07X", secondary),
      primaryOffset = primary, secondaryOffset = secondary,
    }
  end
end
for nativeId, profile in pairs(nativeProfiles) do mapProfiles[nativeId] = profile end

function tileRenderer.gen3SheetsFor(tileset)
  return tileset.nativeWorld and tileset.nativeWorld:world()
end

function V.engineRequire(name)
  if name == "src.core.Game" then return gameView end
  if name == "src.world.Map" then return NativeWorld end
  if name == "src.world.OverworldController" then return overworldView end
  if name == "src.render.TileRenderer" then return tileRenderer end
  return hostRequire(name)
end

local Voxel = V.require("VoxelState")
local Scene = V.require("VoxelScene")
local Mesher = V.require("ChunkMesher")
Mesher.setCacheRulesTag("emerald-native-geometry-2")
local Voxel3D = V.require("Voxel3D")
local TiltShift = V.require("TiltShift")
local DayNight = V.require("DayNight")
local Grid = V.require("VoxelGrid")
local Curve = V.require("WorldCurve")
local Water = V.require("Water")
local AntiAlias = V.require("AntiAlias")
local NativeActors = V.require("NativeActors")
local NativeCamera = V.require("NativeCamera")
local CameraSetting = V.require("ModSetting").new("camera", "VOXEL",
  { 0, 1, 2, 3, 4, 5, 6, 7 }, Voxel.ANGLE_LABELS)
local BlurSetting = V.require("ModSetting").new("tiltshift", "T-SHIFT",
  { 0, 1, 2, 3 }, TiltShift.LABELS)
local settings = { CameraSetting, BlurSetting, Grid.setting, Curve.setting,
                   Water.setting, AntiAlias.setting, DayNight.setting }

local function owns(game)
  local exports = game and game.mods and game.mods.exports
  return exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib == V
end

local function mapView(def)
  if not def or not def.midLayout then return nil end
  local pair = def.pair or def.midLayout.pair
  local atlas = NativeTileset.get(pair)
  if not atlas then return nil end
  local cached = maps[def]
  if changedLayouts[def.midLayout] then
    changedLayouts[def.midLayout] = nil
    Mesher.refresh(def.id or def.midLayout.mapId)
    cached = nil
  end
  if cached and cached.layout == def.midLayout and cached.tiles.atlas == atlas then
    return cached
  end
  local profile = tilesetProfiles[pair]
  if profile and profile.source == nil then
    profile.source = NativeTiles.loadSource(hostRequire("src.core.game3.dataset").cache(),
      profile.primaryOffset, profile.secondaryOffset) or false
  end
  local view = NativeWorld.new(def, atlas, Behaviors.behaviors[pair], profile and profile.source)
  if profile then
    view.tileset.id = profile.id
    view.tileset.primaryKey = profile.primaryKey
    view.tileset.secondaryKey = profile.secondaryKey
    view.def.tileset = profile.id
  end
  maps[def] = view
  return view
end
Emerald.mapView = mapView

function overworldView.gen3WorldFor(_, _, map)
  return map and map:world()
end

function overworldView.computeNeighbors(_, mapId, hops, reachW, reachH)
  local game = Emerald.game
  if not game then return {} end
  local entries = Map.computeWorld(game.data.maps, mapId, hops,
    (reachW or 0) / 16, (reachH or 0) / 16,
    function(id, def) Map.ensureMidLayout(game, id, def) end)
  local out = {}
  for _, entry in ipairs(entries) do
    out[#out + 1] = { id = entry.id, ox = entry.ox * 16, oy = entry.oy * 16 }
  end
  return out
end

local function refresh(game, vw, vh)
  local def = Map.currentDef()
  local map = mapView(def)
  if not map then return nil end
  local player = hostRequire("src.core.game3.player")
  local state = Emerald.state
  if not state or state.map ~= map then
    state = setmetatable({ map = map, camera = {}, entities = {}, neighbors = {},
                 game = gameView }, { __index = overworldView })
    Emerald.state = state
  end
  NativeActors.collect(game, state)
  for index = #state.neighbors, 1, -1 do state.neighbors[index] = nil end
  for _, entry in ipairs(Map.world or {}) do
    local neighbor = mapView(entry.def)
    if neighbor then
      state.neighbors[#state.neighbors + 1] = {
        map = neighbor, ox = entry.ox * 16, oy = entry.oy * 16,
      }
    end
  end
  state.camera.x = (player.px or 0) + 8 - vw / 2 + (FieldView.cameraPanX or 0)
  state.camera.y = (player.py or 0) + 8 - vh / 2 + (FieldView.cameraPanY or 0)
  gameView.overworld = state
  if not gameView.data then
    gameView.data = setmetatable({ maps = setmetatable({}, { __index = function(_, id)
      local native = game.data.maps[id]
      if not native then return nil end
      Map.ensureMidLayout(game, id, native)
      local view = mapView(native)
      return view and view.def
    end }) }, { __index = game.data })
  end
  gameView.input = game.input
  gameView.mods = game.mods
  gameView.save = setmetatable({ options = game.options }, { __index = game.session })
  gameView.writeOptions = function() game:writeOptions() end
  return state
end

local function canToggle(game)
  if not owns(game) or game.phase ~= "field" then return false end
  local runtime = hostRequire("src.core.game3.runtime")
  local field = hostRequire("src.core.game3.field")
  local transition = hostRequire("src.core.game3.battle_transition")
  return not runtime.uiBusy() and not field.locked and not transition.isActive()
end

function Emerald.install()
  local Layout = hostRequire("src.core.game3.layout_native")
  for _, name in ipairs({ "applyOverride", "stamp", "setMetatiles", "clearOverrides" }) do
    local original = Layout[name]
    Layout[name] = function(layout, ...)
      local result = original(layout, ...)
      changedLayouts[layout] = true
      return result
    end
  end
  local schema = {}
  for _, setting in ipairs(settings) do schema[#schema + 1] = setting:schema() end
  V.mod.options:define(schema)
  local OptionRows = hostRequire("src.ui.game3.option_rows")
  local buildRows = OptionRows.build
  OptionRows.build = function(context)
    local rows = buildRows(context)
    if not owns(context.game) then return rows end
    for _, setting in ipairs(settings) do
      local row = setting:row()
      row.step = function(current, direction)
        setting:cycle({ save = { options = current.options }, mods = current.game.mods,
          writeOptions = function() current.game:writeOptions() end }, direction)
        return true
      end
      rows[#rows + 1] = row
    end
    return rows
  end
  V.mod.exports.lib = V
  V.mod.exports.emerald = Emerald
  V.mod.exports.version = "0.7.75"

  V.mod.events:on("game.ready", function(event)
    local game = event and event.game
    if not owns(game) then return end
    Emerald.game = game
    gameView.stack = { top = function()
      return canToggle(game) and Emerald.state or nil
    end }
    NativeCamera.install(game, function() return canToggle(game) and not Emerald.renderError end)
    local update = game.update
    game.update = function(self, dt)
      update(self, dt)
      if not owns(self) then return end
      local level = CameraSetting:get()
      Voxel.update(dt, level)
      NativeCamera.update(dt)
      TiltShift.update(dt, BlurSetting:get())
      DayNight.update(dt)
      if level > 0 and self.phase == "field" then Mesher.pump(false) end
    end
  end)

  V.mod.events:on("mod.options_changed", function(event)
    if not event or event.mod ~= V.mod.id then return end
    for _, setting in ipairs(settings) do
      setting:sync(V.mod.options:get(setting.key))
    end
  end)

  V.mod.hooks:wrap("input.key", function(next, game, event)
    if event.phase == "pressed" and canToggle(game) then
      local key = event.key
      local setting = ({ ["5"] = Grid.setting, ["6"] = BlurSetting,
                         ["7"] = Curve.setting, ["9"] = Water.setting })[key]
      if key == "3" then
        local level = Voxel.nextHotkeyLevel(CameraSetting:get())
        CameraSetting:setIndex(level + 1, { save = { options = game.options },
          mods = game.mods, writeOptions = function() game:writeOptions() end })
        return true
      elseif setting then
        setting:cycle({ save = { options = game.options }, mods = game.mods,
          writeOptions = function() game:writeOptions() end })
        return true
      end
    end
    return next(game, event)
  end)

  local draw = FieldView.draw
  FieldView.draw = function(game, vw, vh, opts)
    if not (opts and opts.actorsOnly) then Emerald.lastCanvas = nil end
    local result = draw(game, vw, vh, opts)
    if not owns(game) or game.phase ~= "field" or (opts and not opts.skipActors)
      or CameraSetting:get() == 0
        or Emerald.renderError then
      return result
    end
    love.graphics.push("all")
    local ok, canvas = pcall(function()
      if not Voxel3D.available() then return nil end
      local state = refresh(game, vw, vh)
      if not state then return nil end
      local width, height = love.graphics.getPixelDimensions()
      local renderWidth, renderHeight = AntiAlias.expand(width, height)
      local image = Scene.render(state, renderWidth, renderHeight, vw, vh)
      if not image then return nil end
      image = AntiAlias.resolve(image, width, height, "world")
      return TiltShift.apply(image)
    end)
    love.graphics.pop()
    if not ok then
      Emerald.renderError = tostring(canvas)
      V.mod.log:error("Emerald voxel rendering disabled: " .. Emerald.renderError)
    elseif canvas then
      Renderer:setWorldOverride(canvas)
      Emerald.lastCanvas = canvas
      Emerald.frames = Emerald.frames + 1
    end
    return result
  end
end

return Emerald