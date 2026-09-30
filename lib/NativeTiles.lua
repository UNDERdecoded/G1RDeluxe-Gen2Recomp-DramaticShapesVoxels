local NativeTiles = {}
NativeTiles.__index = NativeTiles
local Tileset = require("src.import.gba.tileset")
local Metatile = require("src.import.gba.metatile")

function NativeTiles.loadSource(cache, primaryOffset, secondaryOffset)
  local cacheRoot = require("src.import.gba.extract_island1").CACHE_ROOT
  local function bank(offset)
    local root = cacheRoot .. string.format("/map_tree/tilesets/ts_%08x/", 0x08000000 + offset)
    local pixels = cache:read(root .. "tiles.4bpp")
    local metatiles = cache:read(root .. "metatiles.bin")
    local attributes = cache:read(root .. "attributes.bin")
    local palettes = cache:read(root .. "palettes.bin")
    if not pixels or not metatiles or not attributes or not palettes then return nil end
    local reader = { u16 = function(_, position)
      local low, high = palettes:byte(position + 1, position + 2)
      return (low or 0) + (high or 0) * 256
    end }
    return {
      tiles = { raw = pixels, count = math.floor(#pixels / 32) },
      metatiles = { data = metatiles, count = math.floor(#metatiles / 16) },
      attributes = { data = attributes, count = math.floor(#attributes / 2) },
      palettes = Tileset.loadPalettes(reader, 0, math.floor(#palettes / 32)),
    }
  end
  local primary, secondary = bank(primaryOffset), bank(secondaryOffset)
  if not primary or not secondary then return nil end
  return {
    primaryTiles = primary.tiles, secondaryTiles = secondary.tiles,
    primaryMt = primary.metatiles, secondaryMt = secondary.metatiles,
    primaryAttr = primary.attributes, secondaryAttr = secondary.attributes,
    mapPals = Tileset.mergeMapPalettes(primary.palettes, secondary.palettes),
  }
end

function NativeTiles.new(atlas, attributes, source)
  assert(atlas and atlas.imageData and atlas.midToSlot, "native tileset pixels are unavailable")
  local count = 0
  for metatile in pairs(atlas.midToSlot) do
    count = math.max(count, metatile + 1)
  end
  return setmetatable({ atlas = atlas, attrs = attributes or {}, count = count,
                        source = source, layers = { {}, {} } }, NativeTiles)
end

function NativeTiles:metatileCount()
  return self.count
end

function NativeTiles:sheetLayout()
  local rows = math.max(1, math.ceil(self.count / 16))
  return 16, rows, 256, rows * 16
end

function NativeTiles:attributes(metatile)
  if self.source then
    return Tileset.behaviorOf(self.source, metatile), Metatile.layerType(self.source, metatile)
  end
  local value = self.attrs[metatile]
  if type(value) == "table" then return value.behavior or 0, value.layerType or 0 end
  value = tonumber(value) or 0
  return value % 256, math.floor(value / 4096) % 16
end

function NativeTiles:topIsAbovePlayer(metatile)
  local _, layer = self:attributes(metatile)
  return layer ~= 1
end

function NativeTiles:drawLayer(metatile, layer, originX, originY, plot)
  local slot = self.atlas.midToSlot[metatile]
  if slot == nil then return end
  if self.source then
    local pixels = self.layers[layer][metatile]
    if not pixels then
      local composite = layer == 1 and Metatile.compositeIndexedBottom or Metatile.compositeIndexedTop
      pixels = composite(self.source, metatile)
      self.layers[layer][metatile] = pixels
    end
    for pixelY = 0, 15 do
      for pixelX = 0, 15 do
        local index = pixels[pixelY * 16 + pixelX + 1]
        if layer == 1 or index ~= 0 then
          local palette = self.source.mapPals[math.floor(index / 16)]
          local _, _, _, red, green, blue = Tileset.bgr555(palette[index % 16])
          plot(originX + pixelX, originY + pixelY,
            math.floor(red + 0.5), math.floor(green + 0.5), math.floor(blue + 0.5))
        end
      end
    end
    return
  end
  local pixels = layer == 1 and self.atlas.imageData or self.atlas.overImageData
  if not pixels then return end
  local sourceX = (slot % self.atlas.cols) * 16
  local sourceY = math.floor(slot / self.atlas.cols) * 16
  for pixelY = 0, 15 do
    for pixelX = 0, 15 do
      local red, green, blue, alpha = pixels:getPixel(sourceX + pixelX, sourceY + pixelY)
      if alpha > 0 then
        plot(originX + pixelX, originY + pixelY,
             math.floor(red * 255 + 0.5), math.floor(green * 255 + 0.5),
             math.floor(blue * 255 + 0.5))
      end
    end
  end
end

function NativeTiles:bakeLayer(layer, plot)
  for metatile = 0, self.count - 1 do
    if self.atlas.midToSlot[metatile] ~= nil then
      self:drawLayer(metatile, layer, (metatile % 16) * 16,
                     math.floor(metatile / 16) * 16, plot)
    end
  end
end

return NativeTiles