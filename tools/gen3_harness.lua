-- ============================================================================
-- THE SHARED HARNESS for the Gen 3 data generators -- census, roles, rolemap.
--
-- These three tools were written against one scratch session and hardcoded
-- its addresses: an absolute GEN directory under /mnt/user-data/uploads, a
-- `dofile("/tmp/idx/layoutnames.lua")`, a `dofile("/tmp/t/census_owned.lua")`
-- and an `io.lines("/tmp/t/outdoor.txt")`.  Three of those four files no
-- longer exist anywhere, so the tools could not be run at all, and none of
-- them could name a cartridge other than Emerald.
--
-- FireRed is the reason that now matters.  It is a Gen 3 version in this
-- engine and the mod ships it one of the four EMERALD_KEYED tables, so this
-- had to become a thing you point at a version rather than a thing that only
-- ever meant Hoenn.  Everything below is derived from the extracted cache and
-- the mod's own data, so there is nothing left to go missing.
--
--   VERSION   emerald (default) | firered.  Chooses the cache directory, the
--             gen3_maps table, and -- through the cache's own constants --
--             where the secondary's metatile ids begin (512 on Emerald, 640
--             on FireRed: stated, src/core/GameVersion.lua and
--             lib/Gen3.lua inPrimary()).
--   ENGINE    engine tree root (default /tmp/fr).
--   SHAPEMOD  mod tree (default $ENGINE/mods/DRAMATIC_SHAPE/).
--   GEN       cache dir override; default $ENGINE/<prefix>data/generated/,
--             where <prefix> is "" for Emerald and "firered/" for FireRed --
--             the layout this checkout actually has.
--
-- THE THREE RECONSTRUCTED INPUTS.
--
--   layoutnames  was {[layoutIndex] = {name = "LAYOUT_..."}}.  maps.lua gives
--                every map a `layoutId` (its index into map_layouts.lua) and
--                gen3_maps.lua gives the same map a `layout` NAME, and the
--                two are keyed alike by MAP_G<g>_N<n>.  Joining them is a
--                bijection on both cartridges -- measured: Emerald 406 layout
--                indices, 406 distinct names, 0 index-to-name conflicts and 0
--                duplicate names; FireRed 309 and 309, 0 and 0 -- so the
--                reconstruction is forced, not chosen.
--   outdoor      was a list of outdoor map names.  gen3_maps.lua carries
--                `outdoor` per map, so it is a one-line derivation.  NOTE it
--                is dead weight in the role generator, which scores maps from
--                maps.lua's own `outdoor` field and never reads this set; it
--                is rebuilt anyway so the tool has no unexplained input.
--   census       is gen3_census.lua's output.  Run that first.
-- ============================================================================
local H = {}

H.VERSION  = os.getenv("VERSION") or "emerald"
H.ENGINE   = (os.getenv("ENGINE") or "/tmp/fr"):gsub("/*$", "/")
H.MOD      = (os.getenv("SHAPEMOD") or (H.ENGINE .. "mods/DRAMATIC_SHAPE")):gsub("/*$", "/")
H.PREFIX   = (H.VERSION == "emerald") and "" or (H.VERSION .. "/")
H.GEN      = (os.getenv("GEN") or (H.ENGINE .. H.PREFIX .. "data/generated")):gsub("/*$", "/")
-- data/<version>/ for anything but Emerald, exactly as main.lua's
-- EMERALD_KEYED resolves it.
H.DATASUB  = (H.VERSION == "emerald") and "" or (H.VERSION .. "/")

package.path = H.ENGINE .. "?.lua;" .. H.ENGINE .. "?/init.lua;" .. package.path

-- The version has to be set before anything requires src.world.Map, which
-- branches on GameVersion.get() in its collision reader.
local okGV, GameVersion = pcall(require, "src.core.GameVersion")
if okGV and GameVersion.set then GameVersion.set(H.VERSION) end
H.GameVersion = okGV and GameVersion or nil

-- ---- the LOVE stub: headless ImageData that remembers its pixels ----------
-- Gen3.atlasDataForTileset bakes the atlas by writing through setPixel and
-- the profiler reads it back with getPixel, so the art needs no PNG and no
-- window.  Identical to the stub the three tools each carried inline.
_G.love = require("tests.love_stub")
local function obj(t) return setmetatable(t or {}, { __index = function() return function() end end }) end
love.image = love.image or {}
love.image.newImageData = function(w, h)
  local px = {}
  return obj({ _w = w, _h = h,
    getWidth = function() return w end, getHeight = function() return h end,
    getDimensions = function() return w, h end,
    setPixel = function(_, x, y, r, g, b, a) px[y * w + x] = { r, g, b, a } end,
    getPixel = function(_, x, y)
      local c = px[y * w + x]
      if not c then return 0, 0, 0, 0 end
      return c[1], c[2], c[3], c[4]
    end })
end
love.graphics.newImage = function(d)
  return obj({ __data = d, getWidth = function() return d:getWidth() end,
    getHeight = function() return d:getHeight() end,
    getDimensions = function() return d:getDimensions() end })
end
love.graphics.newMesh = function(f, v)
  return obj({ getVertexCount = function() return type(v) == "table" and #v or 0 end })
end

-- ---- the mod's own loader, now version-aware ------------------------------
-- V.data has to resolve data/<version>/<name>.lua the way main.lua's
-- EMERALD_KEYED does, or a FireRed run reads Emerald's map table and mis-owns
-- every metatile it sees.
-- ...and where the version has no copy of its own it must read NOTHING, not
-- Emerald's answers -- the same rule and the same fallback values main.lua
-- applies.  A tool that quietly fell back to data/gen3_metatiles.lua would
-- measure a FireRed map through Hoenn's metatile ids.
local EMERALD_KEYED = {
  gen3_maps      = { version = 1, maps = {} },
  gen3_metatiles = { version = 1, roles = {} },
  gen3_terraces  = { version = 1, maps = {} },
  gen3_palings   = { version = 1 },
}
local V = {}
local modules, dataFiles = {}, {}
function V.require(n)
  local h = modules[n]; if h ~= nil then return h end
  local v = assert(loadfile(H.MOD .. "lib/" .. n .. ".lua"))(V)
  modules[n] = v; return v
end
function V.data(n)
  local h = dataFiles[n]; if h ~= nil then return h end
  local v
  if EMERALD_KEYED[n] and H.DATASUB ~= "" then
    local try = H.MOD .. "data/" .. H.DATASUB .. n .. ".lua"
    local fh = io.open(try, "r")
    if fh then fh:close(); v = assert(loadfile(try))(V) else v = EMERALD_KEYED[n] end
  else
    v = assert(loadfile(H.MOD .. "data/" .. n .. ".lua"))(V)
  end
  dataFiles[n] = v; return v
end
function V.optional(n) local ok, v = pcall(V.require, n); return ok and v or nil end
H.V = V

-- ---- the extracted cache --------------------------------------------------
local function load_(f) return assert(loadfile(H.GEN .. f))() end
H.load = load_
H.tilesets  = load_("tilesets.lua")
H.constants = load_("constants.lua")
H.mapts     = load_("map_tilesets.lua")
H.layouts   = load_("map_layouts.lua")
H.mapRec    = load_("maps.lua")
_G.Game = { data = { tilesets = H.tilesets, map_tilesets = H.mapts,
                     constants = H.constants, maps = {} } }

H.g3maps = V.data("gen3_maps")

-- ---- layoutnames, rebuilt -------------------------------------------------
-- {[layoutIndex] = {name = "LAYOUT_..."}}, joined through the map key.
H.layoutNames = {}
do
  local seen = {}
  for key, ent in pairs(H.g3maps.maps or {}) do
    local r = H.mapRec[key]
    if r and r.layoutId and ent.layout then
      local prev = seen[r.layoutId]
      assert(prev == nil or prev == ent.layout,
        ("layout index %d names both %s and %s"):format(r.layoutId, tostring(prev), ent.layout))
      seen[r.layoutId] = ent.layout
      H.layoutNames[r.layoutId] = { name = ent.layout }
    end
  end
end
H.layIdxByName = {}
for i, ln in pairs(H.layoutNames) do
  assert(H.layIdxByName[ln.name] == nil,
    ("layout name %s is at two indices"):format(ln.name))
  H.layIdxByName[ln.name] = i
end

-- ---- outdoor, rebuilt (and, in the role generator, unused) -----------------
H.outdoor = {}
for _, ent in pairs(H.g3maps.maps or {}) do
  if ent.outdoor then H.outdoor[ent.name] = true end
end

H.Map  = require("src.world.Map")
H.Gen3 = V.require("Gen3")

-- where the secondary's ids begin, asked of the cartridge's own constants:
-- 512 on Emerald, 640 on FireRed.  Derived, not assumed.
H.inPrimary = H.Gen3.inPrimary()

return H
