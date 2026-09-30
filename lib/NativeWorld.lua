local V = ...
local Permissions = require("src.core.CollPermissions")
local NativeTiles = V.require("NativeTiles")
local NativeWorld = {}
local MapView = {}
MapView.__index = MapView

function NativeWorld.isOutdoor(def)
  if def.outdoor ~= nil then return def.outdoor end
  local kind = def.kind or def.mapType
  return kind == 1 or kind == 2 or kind == 3
      or kind == "town" or kind == "city" or kind == "route"
end

function NativeWorld.new(def, atlas, behaviors, source)
  local layout = assert(def.midLayout, "native map layout is unavailable")
  local view = setmetatable({
    id = def.id or layout.mapId,
    source = def,
    layout = layout,
    widthCells = layout.trueWidth or layout.width,
    heightCells = layout.trueHeight or layout.height,
    renderer = { image = atlas.image, trueColor = true },
    doorTiles = {},
  }, MapView)
  view.tiles = NativeTiles.new(atlas, behaviors, source)
  view.tileset = {
    id = def.pair or layout.pair, blockTiles = 2, blockCells = 1,
    behaviourBytes = true, trueColor = true,
    metatileCount = view.tiles:metatileCount(),
  }
  view.tileset.nativeWorld = view
  view.def = setmetatable({
    id = view.id, width = view.widthCells, height = view.heightCells,
    blockPx = 16, outdoor = NativeWorld.isOutdoor(def),
    tileset = view.tileset.id, collisionCells = {}, elevationCells = {}, blocks = {},
  }, { __index = def })
  local border = {}
  for borderY = 0, 1 do
    for borderX = 0, 1 do
      local index = (borderY % (layout.borderHeight or 1))
          * (layout.borderWidth or 1) + borderX % (layout.borderWidth or 1) + 1
      local metatile = (layout.borderMids and layout.borderMids[index]) or 0
      border[#border + 1] = string.char(metatile % 256, math.floor(metatile / 256) % 256)
    end
  end
  view.def.border = table.concat(border)
  local function cells(read)
    return setmetatable({}, { __index = function(_, index)
      if type(index) ~= "number" then return nil end
      return read(view, (index - 1) % view.widthCells,
                  math.floor((index - 1) / view.widthCells))
    end })
  end
  view.def.blocks = cells(MapView.blockAt)
  view.def.collisionCells = cells(function(map, cx, cy)
    return map:isWalkableCell(cx, cy) and 0 or 1
  end)
  for cy = 0, view.heightCells - 1 do
    for cx = 0, view.widthCells - 1 do
      view.def.elevationCells[cy * view.widthCells + cx + 1] = layout:elevAt(cx, cy)
    end
  end
  return view
end

function MapView:inBounds(cx, cy)
  return cx >= 0 and cy >= 0 and cx < self.widthCells and cy < self.heightCells
end

function MapView:blockAt(cx, cy)
  return self.layout:midAt(cx, cy)
end

function MapView:tileAt(tx, ty)
  return self:blockAt(math.floor(tx / 2), math.floor(ty / 2)) * 4
      + (ty % 2) * 2 + tx % 2
end

function MapView:cellTile(cx, cy)
  return self:tileAt(cx * 2, cy * 2 + 1)
end

function MapView:cellBehaviour(cx, cy)
  return self.tiles:attributes(self:blockAt(cx, cy))
end

function MapView:cellElevation(cx, cy)
  return self.layout:elevAt(cx, cy)
end

function MapView:isWalkableCell(cx, cy)
  if not self:inBounds(cx, cy) then return false end
  local collision = self.layout:collAt(cx, cy)
  return not Permissions.isLedge(collision) and Permissions.isWalkable(collision)
end

function MapView:isWaterCell(cx, cy)
  return self:inBounds(cx, cy) and Permissions.isWater(self.layout:collAt(cx, cy))
end

function MapView:isGrassCell(cx, cy)
  local behavior = self:cellBehaviour(cx, cy)
  return behavior == 2 or behavior == 3
end

function MapView:world()
  local cols, _, width, height = self.tiles:sheetLayout()
  return {
    generation = 3, tileset = self.tileset, pair = self.tileset,
    bottom = self.renderer.image, top = self.tiles.atlas.overImage,
    width = width, height = height, cols = cols, cell = 16,
    metatiles = self.tiles:metatileCount(), tiles = self.tiles,
    attributes = function(metatile) return self.tiles:attributes(metatile) end,
    topIsAbovePlayer = function(metatile) return self.tiles:topIsAbovePlayer(metatile) end,
  }
end

return NativeWorld