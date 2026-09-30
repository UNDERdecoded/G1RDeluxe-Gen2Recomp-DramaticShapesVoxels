return function(game)
  local U = require("tests.drivers.util")
  local exported = assert(game.mods.exports.DRAMATIC_SHAPE, "Dramatic Shape did not load")
  local port = assert(exported.emerald, "the Emerald adapter did not load")
  local namespace = exported.lib
  local Renderer = require("src.render.Renderer")
  local Mesher = namespace.require("ChunkMesher")
  local function waitForRaisedMesh(id)
    for _ = 1, 1800 do
      local map = port.state and port.state.map
      local failure = Mesher.buildFailure(id)
      assert(not failure, tostring(failure))
      local mesh = map and map.id == id and (Mesher.peek(map, true) or Mesher.peek(map, false))
      if mesh then
        for vertex = 1, mesh:getVertexCount() do
          local _, height = mesh:getVertex(vertex)
          if height > 32 then return end
        end
        error(id .. " uploaded only flat geometry")
      end
      U.wait(1)
    end
    error(id .. " never uploaded a voxel mesh")
  end
  game.writeOptions = function() end
  game.saveGame = function() end
  game:_handleBootAction({ action = "new_game", name = "PORT",
    start = { map = "EM_OLDALE_TOWN", x = 8, y = 8, facing = "down" } })
  U.wait(120)
  assert(game.phase == "field", "did not reach the Emerald field")
  love.filesystem.createDirectory("emerald-port-shots")
  local captured = false
  local function shot(name)
    captured = false
    love.graphics.captureScreenshot(function(image)
      image:encode("png", "emerald-port-shots/" .. name .. ".png")
      captured = true
    end)
    for _ = 1, 120 do
      if captured then return end
      U.wait(1)
    end
    error("screenshot was not captured: " .. name)
  end
  shot("flat")
  local OptionMenu = require("src.ui.game3.screens").get("option", game.session)
  OptionMenu.show({ game = game, session = game.session })
  local cameraRow
  local optionPage = OptionMenu._st.pages[1]
  for index, row in ipairs(optionPage.rows) do
    if row.id == "DRAMATIC_SHAPE:camera" then
      cameraRow = row
      optionPage.index = index
      optionPage.scroll = math.max(0, index - OptionMenu.VISIBLE)
    end
  end
  assert(cameraRow, "native Options has no VOXEL setting")
  assert(cameraRow.value() == "OFF", "native Options does not show voxel OFF")
  cameraRow.step(OptionMenu._st.ctx, 1)
  assert(game.options.modOptions.DRAMATIC_SHAPE.camera == 1,
    "native Options did not persist voxel ON")
  cameraRow.step(OptionMenu._st.ctx, -1)
  assert(game.options.modOptions.DRAMATIC_SHAPE.camera == 0,
    "native Options did not persist voxel OFF")
  shot("native-voxel-option")
  OptionMenu.close()
  local ModManager = require("src.ui.game3.mod_manager")
  ModManager.show({ game = game })
  local manager = ModManager._mgr
  local schema = assert(manager:schemaFor({ id = "DRAMATIC_SHAPE" }),
    "mod manager has no Dramatic Shape settings")
  local cameraSchema
  for _, row in ipairs(schema) do if row.key == "camera" then cameraSchema = row end end
  assert(cameraSchema and #cameraSchema.choices == 8, "mod manager has no voxel camera choices")
  manager:openOptions({ id = "DRAMATIC_SHAPE" })
  assert(manager.screen == "options", "mod options page did not open")
  manager:setOption("DRAMATIC_SHAPE", "camera", 2)
  assert(game.options.modOptions.DRAMATIC_SHAPE.camera == 2,
    "mod manager did not persist the voxel camera")
  assert(cameraRow.value() == "15", "native Options did not reflect the mod setting")
  shot("mod-voxel-options")
  manager:setOption("DRAMATIC_SHAPE", "camera", 0)
  ModManager.close()
  U.wait(2)
  namespace.require("DayNight").setting:sync("day")
  require("src.render.Tilt").setLevel(2)
  game:keypressed("3")
  assert(require("src.render.Tilt").level == 2, "3 changed native Tilt instead of voxels")
  for _ = 1, 900 do
    if port.frames >= 20 then break end
    U.wait(1)
  end
  assert(port.frames >= 20, "Emerald voxel world never rendered")
  waitForRaisedMesh("EM_OLDALE_TOWN")
  assert(port.lastCanvas, "Emerald world canvas was not replaced")
  assert(#port.state.entities > 1, "native player and NPCs are missing")
  assert(port.state.player.sprite, "native player has no sprite view")
  assert(#port.state.neighbors > 0, "connected native maps are missing")
  assert(namespace.require("TerrainAtlas").forMap(port.state.map), "Emerald terrain has no texture")
  local context = namespace.require("Gen3").forMap(port.state.map)
  assert(context.primaryName == "gTileset_General", "Emerald terrain profile is missing")
  assert(context.secondaryName == "gTileset_Petalburg", "Emerald building profile is missing")
  assert(context.ownerPrimary == "P03DF704", "Emerald artwork role owner is missing")
  assert(context.metaRole(1), "Emerald ground artwork role is missing")
  assert(port.state.map.tiles.source, "original Emerald metatile layers were not loaded")
  local Map = require("src.core.game3.map")
  local Catalog = require("src.import.gba.map_catalog")
  for _, sample in ipairs({
    { "OldaleTown", "gTileset_Petalburg" },
    { "LittlerootTown", "gTileset_Petalburg" },
    { "RustboroCity", "gTileset_Rustboro" },
    { "FortreeCity", "gTileset_Fortree" },
    { "LittlerootTown_BrendansHouse_1F", "gTileset_BrendansMaysHouse" },
  }) do
    local id = Catalog.pretToEngine(sample[1])
    local def = assert(game.data.maps[id], "missing native sample " .. id)
    Map.ensureMidLayout(game, id, def)
    local view = assert(port.mapView(def))
    local profile = namespace.require("Gen3").forMap(view)
    assert(profile.mapName == sample[1], "wrong native map profile: " .. id)
    assert(profile.secondaryName == sample[2], "wrong native tileset profile: " .. id)
    assert(profile.ownerPrimary and profile.ownerSecondary, "missing artwork owners: " .. id)
    assert(view.tiles.source, "missing original artwork layers: " .. id)
    if sample[1] == "OldaleTown" or sample[1] == "LittlerootTown" then
      local structures = namespace.require("Structures").forMap(view)
      local buildings, raisedObjects = 0, 0
      local seen = {}
      for _, run in pairs(structures.runs) do
        if run.gen3Bld and not seen[run] then
          seen[run] = true
          if run.h > (run.base or 0) and (run.peak or run.h) > 16 then
            buildings = buildings + 1
          end
        end
      end
      for _, quad in ipairs(structures.objectQuads or {}) do
        if math.max(quad[1][2], quad[2][2], quad[3][2], quad[4][2]) > 16 then
          raisedObjects = raisedObjects + 1
        end
      end
      for _, stamp in ipairs(structures.roundStamps or {}) do
        for _, quad in ipairs(stamp.quads) do
          if math.max(quad[1][2], quad[2][2], quad[3][2], quad[4][2]) > 16 then
            raisedObjects = raisedObjects + 1
          end
        end
      end
      assert(buildings > 0, id .. " has no raised authored buildings")
      assert(raisedObjects > 0, id .. " has no raised object geometry")
      print("PASS Emerald geometry " .. id .. ": buildings=" .. buildings
        .. " raisedObjectQuads=" .. raisedObjects)
    end
  end
  local tiles = port.state.map.tiles
  for _, metatile in ipairs({ 468, 476 }) do
    local pixels = {}
    local function paint(x, y, red, green, blue) pixels[y * 16 + x] = { red, green, blue } end
    tiles:drawLayer(metatile, 1, 0, 0, paint)
    tiles:drawLayer(metatile, 2, 0, 0, paint)
    local slot = assert(tiles.atlas.midToSlot[metatile], "tree metatile is missing")
    for y = 0, 15 do
      for x = 0, 15 do
        local px, py = slot % tiles.atlas.cols * 16 + x, math.floor(slot / tiles.atlas.cols) * 16 + y
        local red, green, blue = tiles.atlas.imageData:getPixel(px, py)
        local topRed, topGreen, topBlue, alpha = tiles.atlas.overImageData:getPixel(px, py)
        if alpha > 0 then red, green, blue = topRed, topGreen, topBlue end
        local actual = assert(pixels[y * 16 + x])
        assert(math.abs(actual[1] - red * 255) <= 1
          and math.abs(actual[2] - green * 255) <= 1
          and math.abs(actual[3] - blue * 255) <= 1, "Emerald tree artwork differs from native atlas")
      end
    end
  end
  shot("voxel15")
  game:keypressed("3")
  U.wait(45)
  shot("voxel35")
  game:keypressed("3")
  game:keypressed("3")
  game:keypressed("3")
  U.wait(90)
  local firstPerson = namespace.require("FirstPerson")
  assert(firstPerson.blend == 1 and port.lastCanvas, "first-person camera did not engage")
  local before = firstPerson.yaw
  game:mousemoved(100, 100, 40, 0, false)
  assert(firstPerson.yaw ~= before, "mouse look did not reach the native camera")
  U.wait(20)
  shot("first-person")
  game:keypressed("3")
  U.wait(90)
  assert(namespace.require("VoxelState").isThirdPerson(), "third-person camera did not engage")
  assert(port.lastCanvas, "third-person world did not render")
  shot("third-person")
  local Message = require("src.ui.game3.message")
  Message.show("Native dialog check.")
  U.wait(30)
  assert(not firstPerson.driving(), "camera still owns input during a native dialog")
  assert(not love.mouse.getRelativeMode(), "native dialog did not release mouse capture")
  before = firstPerson.yaw
  game:mousemoved(100, 100, 40, 0, false)
  assert(firstPerson.yaw == before, "dialog input turned the camera")
  shot("native-dialog")
  Message.close()
  U.wait(30)
  Map.load(nil, game, "EM_LITTLEROOT_TOWN", { x = 8, y = 9, facing = "down" })
  game.mods.modOptions.DRAMATIC_SHAPE.camera = 2
  require("src.mods.Runtime").emit("mod.options_changed", { mod = "DRAMATIC_SHAPE" })
  waitForRaisedMesh("EM_LITTLEROOT_TOWN")
  U.wait(30)
  assert(port.lastCanvas, "Littleroot's raised mesh was not rendered")
  shot("littleroot-voxel")
  local previous = port.state.map
  local layout = previous.layout
  local original = layout:cellAt(8, 8)
  layout:setMetatiles({ { x = 8, y = 8, mid = original.mid,
                         coll = original.coll, elev = original.elev } })
  for _ = 1, 900 do
    if port.state.map ~= previous and port.lastCanvas then break end
    U.wait(1)
  end
  assert(port.state.map ~= previous and port.lastCanvas, "edited map did not rebuild")
  Map.load(nil, game, "EM_FORTREE_CITY", { x = 0, y = 0, facing = "down" })
  waitForRaisedMesh("EM_FORTREE_CITY")
  local Collision = require("src.core.game3.collision")
  local Steps = require("src.core.game3.step_callbacks_rse")
  local Player = require("src.core.game3.player")
  local bridge
  for bridgeY = 0, port.state.map.heightCells - 1 do
    for bridgeX = 0, port.state.map.widthCells - 2 do
      if Collision.isFortreeBridge(Collision.behavior(bridgeX, bridgeY))
          and Collision.isFortreeBridge(Collision.behavior(bridgeX + 1, bridgeY)) then
        bridge = { x = bridgeX, y = bridgeY }
        break
      end
    end
    if bridge then break end
  end
  assert(bridge, "Fortree has no adjacent bridge cells for the regression")
  local function bridgeMesh()
    return Mesher.peek(port.state.map, true) or Mesher.peek(port.state.map, false)
  end
  local beforeBridge = assert(bridgeMesh())
  local beforeHeightContext = assert(Mesher.heightContext(port.state.map),
    "completed mesh has no actor-height snapshot")
  local Scene = namespace.require("VoxelScene")
  local heightSamples = {}
  local function sampleHeight(cellX, cellY, elevation, label)
    heightSamples[#heightSamples + 1] = {
      x = cellX, y = cellY, elevation = elevation, label = label,
      height = Scene.groundAt(port.state.map, cellX, cellY, elevation,
        cellX * 16, cellY * 16),
    }
  end
  sampleHeight(bridge.x, bridge.y, 2, "player bridge west")
  sampleHeight(bridge.x + 1, bridge.y, 2, "player bridge east")
  local npcSamples = 0
  for _, entity in ipairs(port.state.entities) do
    if entity ~= port.state.player then
      sampleHeight(entity.cellX, entity.cellY, entity.elevation, "NPC")
      npcSamples = npcSamples + 1
    end
  end
  assert(npcSamples > 0, "Fortree height test has no NPC positions")
  local function checkActorHeights()
    for _, sample in ipairs(heightSamples) do
      local height = Scene.groundAt(port.state.map, sample.x, sample.y,
        sample.elevation, sample.x * 16, sample.y * 16)
      assert(math.abs(height - sample.height) < 0.001,
        string.format("%s height changed during bridge refresh: %.2f -> %.2f",
          sample.label, sample.height, height))
    end
  end
  local callbackState, bridgeEdits = {}, 0
  for step = 1, 6 do
    Player.cellX, Player.cellY = bridge.x + (step % 2), bridge.y
    Player.px, Player.py = Player.cellX * 16, Player.cellY * 16
    Player.elevation = 2
    game.session.x, game.session.y = Player.cellX, Player.cellY
    for frame = 1, 18 do
      local previousView, previousFrame = port.state.map, port.frames
      Steps.CALLBACKS.fortreeBridge(game, callbackState)
      U.wait(1)
      if port.state.map ~= previousView then bridgeEdits = bridgeEdits + 1 end
      assert(bridgeMesh(), "Fortree bridge step discarded the voxel mesh")
      assert(port.lastCanvas and port.frames > previousFrame,
        "Fortree bridge step fell back to native rendering")
      checkActorHeights()
    end
  end
  assert(bridgeEdits >= 6, "Fortree regression did not exercise repeated bridge edits")
  for _ = 1, 1800 do
    if bridgeMesh() ~= beforeBridge then break end
    assert(bridgeMesh() and port.lastCanvas, "Fortree refresh lost its completed mesh")
    checkActorHeights()
    U.wait(1)
  end
  assert(bridgeMesh() ~= beforeBridge, "Fortree bridge refresh never completed")
  assert(Mesher.heightContext(port.state.map) ~= beforeHeightContext,
    "replacement mesh did not publish fresh actor-height data")
  checkActorHeights()
  shot("fortree-bridge")
  print("PASS Fortree bridge: 6 steps, " .. bridgeEdits .. " layout refreshes without a missing mesh")
  print("PASS Fortree actor heights: 2 player cells and " .. npcSamples .. " NPC positions stayed stable")
  namespace.require("VoxelState").setLevel(0)
  game.mods.modOptions.DRAMATIC_SHAPE.camera = 0
  require("src.mods.Runtime").emit("mod.options_changed", { mod = "DRAMATIC_SHAPE" })
  U.wait(30)
  assert(not port.lastCanvas, "native field did not resume")
  shot("back-flat")
  game:keypressed("3")
  local scene = namespace.require("VoxelScene")
  local render = scene.render
  scene.render = function() error("intentional render-fallback probe") end
  U.wait(3)
  scene.render = render
  assert(port.renderError and not port.lastCanvas, "render failure did not fall back to native")
  assert(game.phase == "field", "render failure interrupted native gameplay")
  print("PASS emerald_port_shots: " .. port.frames .. " voxel frames; "
    .. love.filesystem.getSaveDirectory() .. "/emerald-port-shots")
end