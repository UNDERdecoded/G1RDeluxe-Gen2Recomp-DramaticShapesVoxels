package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local NativeTiles = assert(loadfile("mods/DRAMATIC_SHAPE/lib/NativeTiles.lua"))()
local atlas = {
  cols = 2,
  midToSlot = { [4] = 1, [17] = 0 },
  imageData = { getPixel = function(_, pixelX, pixelY)
    return pixelX / 255, pixelY / 255, 128 / 255, 1
  end },
  overImageData = { getPixel = function(_, pixelX, pixelY)
    return 1, 0, 0, pixelX == 16 and pixelY == 0 and 1 or 0
  end },
}
local tiles = NativeTiles.new(atlas, { [4] = 0x2015, [17] = { behavior = 2, layerType = 1 } })
T.eq(tiles:metatileCount(), 18, "sparse native slots preserve the metatile ID space")
local cols, rows, width, height = tiles:sheetLayout()
T.eq(cols, 16, "exports the mod's metatile column count")
T.eq(rows, 2, "allocates the sparse ID range")
T.eq(width, 256, "uses 16px metatiles")
T.eq(height, 32, "uses the required sheet height")
local behavior, layer = tiles:attributes(4)
T.eq(behavior, 0x15, "preserves behavior bits")
T.eq(layer, 2, "preserves layer type bits")
T.check(tiles:topIsAbovePlayer(4), "split layers cover the player")
T.check(not tiles:topIsAbovePlayer(17), "covered layers stay below the player")

local bottom, top = {}, {}
tiles:bakeLayer(1, function(pixelX, pixelY, red, green, blue)
  bottom[pixelY * 256 + pixelX] = { red, green, blue }
end)
tiles:bakeLayer(2, function(pixelX, pixelY, red, green, blue)
  top[#top + 1] = { pixelX, pixelY, red, green, blue }
end)
T.same(bottom[64], { 16, 0, 128 }, "metatile 4 reads native slot 1")
T.same(bottom[16 * 256 + 16], { 0, 0, 128 }, "metatile 17 reads native slot 0")
T.eq(bottom[0], nil, "missing metatiles do not borrow unrelated artwork")
T.eq(#top, 1, "transparent overlay pixels are not painted")
T.same(top[1], { 64, 0, 255, 0, 0 }, "the overlay preserves metatile placement and RGB")
T.eq(atlas.midToSlot[4], 1, "does not rewrite the engine's slot mapping")

local count = 0
tiles:drawLayer(999, 1, 0, 0, function() count = count + 1 end)
T.eq(count, 0, "unknown metatiles draw nothing")
atlas.overImageData = nil
tiles:bakeLayer(2, function() count = count + 1 end)
T.eq(count, 0, "unlayered native atlases have no overlay")
local NativeWorld = assert(loadfile("mods/DRAMATIC_SHAPE/lib/NativeWorld.lua"))({
  require = function(name) assert(name == "NativeTiles"); return NativeTiles end,
})
local Layout = require("src.core.game3.layout_native")
local layout = Layout.fromDecoded({
  width = 2, height = 2, borderWidth = 2, borderHeight = 1, borderMids = { 4, 17 },
  cells = {
    { mid = 4, coll = 0, elev = 3 }, { mid = 17, coll = 7, elev = 4 },
    { mid = 4, coll = 0x29, elev = 1 }, { mid = 17, coll = 0, elev = 3 },
  },
}, "EM_TEST", "TEST_PAIR")
local def = { id = "EM_TEST", kind = 1, midLayout = layout }
local map = NativeWorld.new(def, atlas, { [4] = 0x15, [17] = 2 })
T.eq(map.def.width, 2, "native metatiles are one cell wide")
T.eq(map.def.blockPx, 16, "native map blocks stay 16px")
T.check(map.def.outdoor, "native town metadata is outdoors")
T.eq(map:blockAt(-1, 0), 17, "borders use the native repeated patch")
T.eq(map.def.border, string.char(4, 0, 17, 0, 4, 0, 17, 0),
  "structure borders retain the native metatiles and repeat short patches")
T.eq(type(map.doorTiles), "table", "native maps provide the structure builder's door lookup")
T.eq(map:tileAt(2, 1), 70, "native metatiles become synthetic 8px tiles")
T.check(map:isWalkableCell(0, 0), "land is walkable")
T.check(not map:isWalkableCell(1, 0), "walls are blocked")
T.check(map:isWaterCell(0, 1), "water stays water")
T.check(not map:isWalkableCell(0, 1), "water is not walkable land")
T.eq(map:cellElevation(1, 0), 4, "preserves native elevation")
T.eq(map.def.collisionCells[2], 1, "mesher reads blocked cells")
layout:applyOverride(1, 0, 4, 0, 3)
T.eq(map:blockAt(1, 0), 4, "script metatile changes remain live")
T.eq(map.def.collisionCells[2], 0, "script collision changes remain live")
T.eq(map:cellElevation(1, 0), 3, "script elevation changes remain live")
T.eq(def.width, nil, "does not overwrite native map metadata")
T.eq(layout.cells[2].mid, 17, "does not overwrite imported layout cells")
T.eq(map:world().tiles, map.tiles, "exports the adapted tiles to the voxel mesher")
require("src.core.GameVersion").set("emerald")
local function word(value) return string.char(value % 256, math.floor(value / 256)) end
local blobs = {
  ["tiles.4bpp"] = string.rep(string.char(0x11), 32) .. string.rep(string.char(0x22), 32),
  ["metatiles.bin"] = string.rep(word(0), 4) .. string.rep(word(1), 4),
  ["attributes.bin"] = word(0x1002),
  ["palettes.bin"] = word(0) .. word(31) .. word(31 * 32) .. string.rep(word(0), 13),
}
local source = NativeTiles.loadSource({ read = function(_, path)
  return blobs[path:match("([^/]+)$")]
end }, 0x3df704, 0x3df71c)
local rawTiles = NativeTiles.new({ imageData = {}, midToSlot = { [0] = 0 } }, {}, source)
local rawBottom, rawTop
rawTiles:drawLayer(0, 1, 0, 0, function(_, _, red, green, blue) rawBottom = { red, green, blue } end)
rawTiles:drawLayer(0, 2, 0, 0, function(_, _, red, green, blue) rawTop = { red, green, blue } end)
T.same(rawBottom, { 255, 0, 0 }, "covered metatiles keep original bottom artwork")
T.same(rawTop, { 0, 255, 0 }, "covered metatiles retain their original top artwork")
local rawBehavior, rawLayer = rawTiles:attributes(0)
T.eq(rawBehavior, 2, "raw metatile behavior is preserved")
T.eq(rawLayer, 1, "raw layer type is preserved")
T.check(not rawTiles:topIsAbovePlayer(0), "covered artwork stays below native actors")
T.finish("dramatic_shape_native_tiles")