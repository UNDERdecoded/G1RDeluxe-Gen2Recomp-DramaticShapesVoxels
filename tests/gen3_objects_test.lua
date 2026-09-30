return function(game)
  local U = dofile("tests/drivers/util.lua")
  U.wait(10)
  U.freshSave(game)
  local namespace = assert(_G.__DRAMATIC_SHAPE_V, "Dramatic Shapes must be enabled")
  local Gen3 = namespace.require("Gen3")
  local Structures = namespace.require("Structures")
  local baselinePath = os.getenv("ROOF_BASELINE")
  local baselineStructures = baselinePath and assert(loadfile(baselinePath))(namespace)
  local Map = require("src.world.Map")
  local MapLoader = require("src.world.MapLoader")
  local version = require("src.core.GameVersion").get()
  local profiles = namespace.data("gen3_palings")
  local catalog = namespace.data("gen3_maps").maps
  local passed, failed = 0, 0
  local function check(condition, message)
    if condition then passed = passed + 1 else
      failed = failed + 1
      U.log("FAIL", message)
    end
  end
  local function key(tx, ty) return (ty + 64) * 4096 + tx + 64 end
  local function loadMap(mapId)
    local def = assert(game.data.maps[mapId], mapId)
    return Map.new(def, assert(MapLoader.tilesetFor(game.data, def)))
  end
  local function figuresFor(map)
    local byMeta = {}
    local primaryId = map.tileset.id:match("^TILESET_(%x+)_")
    local primary = (profiles.primaries or {})[primaryId]
    for _, figure in ipairs((primary and primary.figures) or {}) do
      if figure.meta < Gen3.inPrimary() and figure.under < Gen3.inPrimary() then
        byMeta[figure.meta] = figure
      end
    end
    local pair = (profiles.overhead or {})[map.tileset.id]
    for _, figure in ipairs((pair and pair.figures) or {}) do
      byMeta[figure.meta] = figure
    end
    return byMeta
  end
  local function walkability(map)
    local cells = {}
    for cy = 0, map.def.height - 1 do
      for cx = 0, map.def.width - 1 do
        cells[#cells + 1] = map:isWalkableCell(cx, cy) and "1" or "0"
      end
    end
    return table.concat(cells)
  end
  local function surfaceAt(scene, wx, wz)
    local height
    for _, quad in ipairs(scene.objectQuads) do
      if quad[1][2] == quad[2][2] and quad[1][2] == quad[3][2]
         and quad[1][2] == quad[4][2] then
        local x0 = math.min(quad[1][1], quad[2][1], quad[3][1], quad[4][1])
        local x1 = math.max(quad[1][1], quad[2][1], quad[3][1], quad[4][1])
        local z0 = math.min(quad[1][3], quad[2][3], quad[3][3], quad[4][3])
        local z1 = math.max(quad[1][3], quad[2][3], quad[3][3], quad[4][3])
        if wx > x0 and wx < x1 and wz > z0 and wz < z1 then
          height = math.max(height or -math.huge, quad[1][2])
        end
      end
    end
    return height
  end
  local selected = version == "firered"
        and { MAP_G04_N00 = true, MAP_G04_N03 = true, MAP_G05_N04 = true,
          MAP_G10_N00 = true, MAP_G01_N42 = true, MAP_G03_N00 = true,
          MAP_G03_N01 = true, MAP_G03_N06 = true }
        or { MAP_G11_N09 = true, MAP_G01_N00 = true, MAP_G02_N02 = true,
          MAP_G10_N03 = true, MAP_G00_N00 = true, MAP_G00_N03 = true,
          MAP_G00_N04 = true, MAP_G00_N05 = true, MAP_G00_N07 = true,
          MAP_G00_N10 = true }
  local mapIds = {}
  for mapId, entry in pairs(catalog) do
    if (entry.outdoor == false or selected[mapId]
        or (version == "emerald" and entry.primary == "gTileset_General"))
       and game.data.maps[mapId] then
      mapIds[#mapIds + 1] = mapId
    end
  end
  table.sort(mapIds)
  local combinations, crownMaps, crownCells = {}, 0, 0
  for _, mapId in ipairs(mapIds) do
    local map = loadMap(mapId)
    local entry = catalog[mapId]
    if version == "emerald" and entry.primary == "gTileset_General" then
      local plantings, borders = 0, 0
      for cy = 0, map.def.height - 1 do
        for cx = 0, map.def.width - 1 do
          local meta = map:blockAt(cx, cy)
          if meta == 7 then plantings = plantings + 1 end
          if meta == 581 and entry.secondary == "gTileset_Petalburg" then
            borders = borders + 1
          end
        end
      end
      if plantings + borders > 0 then
        selected[mapId] = true
        U.log("garden census", mapId, entry.name,
              "plantings=" .. plantings, "borders=" .. borders)
      end
    end
    local figures, found = figuresFor(map), false
    if next(figures) then
      for cy = 0, map.def.height - 1 do
        for cx = 0, map.def.width - 1 do
          local meta = map:blockAt(cx, cy)
          if figures[meta] then
            found, crownCells = true, crownCells + 1
            local combination = map.tileset.id .. ":" .. meta
            if not combinations[combination] then
              combinations[combination], selected[mapId] = true, true
            end
          end
        end
      end
    end
    if found then crownMaps = crownMaps + 1 end
  end
  U.log("crown census", version, "maps=" .. crownMaps, "cells=" .. crownCells)
  local testedMaps = 0
  for _, mapId in ipairs(mapIds) do
    if selected[mapId] then
      U.teleport(game, mapId, 5, 5, "down")
      local map = MapLoader.load(game.data, mapId)
      local before = walkability(map)
      local scene = Structures.forMap(map)
      check(scene ~= nil, mapId .. " builds geometry")
      check(walkability(map) == before, mapId .. " preserves collision")
      local baseline = baselineStructures and catalog[mapId].outdoor
               and baselineStructures.forMap(map)
      local roofRuns, roofSeen = 0, {}
      for tileKey, run in pairs(scene.runs) do
        if run.gen3WallArtFront and not roofSeen[run] then
          roofSeen[run] = true
          roofRuns = roofRuns + 1
          local roofEnd = run.roofArtTop + run.roofArtRows - 1
          local wallStart = run.gen3WallArtFront - (run.h - run.base) / 8 + 1
          check(roofEnd < wallStart, mapId .. " roof/wall source rows do not overlap")
          check(run.h > run.base and run.h + run.rise == run.peak,
                mapId .. " roof preserves peak above a positive facade: " .. tileKey
                .. " h=" .. run.h .. " rise=" .. run.rise .. " peak=" .. run.peak)
          if baseline then
            local previous = baseline.runs[tileKey]
            check(previous and previous.h + previous.rise == run.h + run.rise
                  and previous.base == run.base,
                  mapId .. " roof total height/base match released geometry: " .. tileKey
                  .. " old=" .. (previous and (previous.h + previous.rise) or -1)
                  .. " new=" .. (run.h + run.rise))
            check(previous and previous.front == run.front and previous.north == run.north,
                  mapId .. " roof footprint matches released geometry")
          end
        end
      end
      local roofColumns = 0
      local bands = Gen3.forMap(map).profile.roof_bands or {}
      if catalog[mapId].outdoor then
        for cy = 0, map.def.height - 1 do
          for cx = 0, map.def.width - 1 do
            local rows = bands[map:blockAt(cx, cy)]
            if rows then
              for dx = 0, 1 do
                roofColumns = roofColumns + 1
                local run = scene.runs[key(cx * 2 + dx, cy * 2 + rows)]
                check(run and run.gen3WallArtFront and run.roofArtTop == cy * 2
                      and run.roofArtRows == rows,
                      mapId .. " authored roof column " .. (cx * 2 + dx)
                      .. " at source row " .. (cy * 2) .. " is fully profiled")
              end
            end
          end
        end
      end
      if roofRuns > 0 then
        U.log("roof audit", mapId, "runs=" .. roofRuns, "columns=" .. roofColumns)
      end
      if version == "emerald" and (mapId == "MAP_G00_N00" or mapId == "MAP_G00_N04"
          or mapId == "MAP_G00_N10" or mapId == "MAP_G26_N14") then
        check(roofColumns == 8, mapId .. " checks every Center roof column")
      end
      if version == "firered" and (mapId == "MAP_G03_N01" or mapId == "MAP_G03_N06") then
        check(roofColumns == 8, mapId .. " checks every Center roof column")
      end
      if baseline then
        local unchanged = true
        for tileKey, run in pairs(scene.runs) do
          local previous = baseline.runs[tileKey]
          if not run.gen3WallArtFront and (not previous or run.h ~= previous.h
             or run.rise ~= previous.rise or run.base ~= previous.base
             or run.roofArtTop ~= previous.roofArtTop
             or run.roofArtRows ~= previous.roofArtRows) then
            unchanged = false
            break
          end
        end
        check(unchanged, mapId .. " unprofiled structures keep released geometry")
      end
      local info = Gen3.describe(map.tileset)
      local figures = figuresFor(map)
      for cy = 0, map.def.height - 1 do
        for cx = 0, map.def.width - 1 do
          local meta = map:blockAt(cx, cy)
          local entry = catalog[mapId]
          if version == "emerald" and entry.primary == "gTileset_General"
             and (meta == 7 or (meta == 581 and entry.secondary == "gTileset_Petalburg")) then
            for dy = 0, 1 do
              for dx = 0, 1 do
                local tileKey = key(cx * 2 + dx, cy * 2 + dy)
                check(scene.runs[tileKey] == nil and scene.skip[tileKey] == true,
                      mapId .. " planting relief at " .. cx .. "," .. cy)
              end
            end
          end
          local figure = figures[meta]
          if figure then
            local label = mapId .. " crown " .. figure.meta .. " at " .. cx .. "," .. cy
            for dy = 0, 1 do
              for dx = 0, 1 do
                local tileKey = key(cx * 2 + dx, cy * 2 + dy)
                local under = figure.under * 4 + dy * 2 + dx
                check(scene.tileAt[tileKey] == under, label .. " replaces original art")
                if scene.skip[tileKey] then
                  check(scene.ground[tileKey] == under, label .. " replaces claimed floor art")
                end
              end
            end
            local bodyTop
            for _, stamp in ipairs(scene.roundStamps or {}) do
              if stamp.mx > cx * 16 and stamp.mx < (cx + 1) * 16
                 and stamp.mz > (cy + figure.south) * 16
                 and stamp.mz < (cy + figure.south + 1) * 16 then
                for _, quad in ipairs(stamp.quads) do
                  for corner = 1, 4 do
                    bodyTop = math.max(bodyTop or -math.huge, quad[corner][2] + (stamp.my or 0))
                  end
                end
              end
            end
            local lowest, highest, count = math.huge, -math.huge, 0
            local depths = {}
            for _, quad in ipairs(scene.objectQuads) do
              if quad.u and quad.v then
                local tile = math.floor(quad.v * info.height / 8) * info.perRow
                             + math.floor(quad.u * info.width / 8)
                local centerX = (quad[1][1] + quad[2][1] + quad[3][1] + quad[4][1]) / 4
                local centerZ = (quad[1][3] + quad[2][3] + quad[3][3] + quad[4][3]) / 4
                if math.floor(tile / 4) == figure.meta
                   and centerX >= cx * 16 and centerX < (cx + 1) * 16
                   and centerZ > (cy + figure.south) * 16
                   and centerZ < (cy + figure.south + 1) * 16 then
                  count = count + 1
                  for corner = 1, 4 do
                    lowest = math.min(lowest, quad[corner][2])
                    highest = math.max(highest, quad[corner][2])
                    depths[string.format("%.3f", quad[corner][3])] = true
                  end
                end
              end
            end
            check(count > 0 and highest > lowest, label .. " is upright geometry")
            if bodyTop then
              check(math.abs(lowest - bodyTop) < 0.001, label .. " attaches to pot top")
            end
            if figure.round then
              local depthCount = 0
              for _ in pairs(depths) do depthCount = depthCount + 1 end
              check(depthCount > 2, label .. " has rounded depth")
            end
          end
        end
      end
      local function height(cx, cy, px, pz, expected, name)
        local actual = surfaceAt(scene, cx * 16 + px, cy * 16 + pz)
        check(actual and math.abs(actual - expected) < 0.001,
              mapId .. " " .. name .. ": got " .. tostring(actual) .. " expected " .. expected)
      end
      if version == "firered" and (mapId == "MAP_G04_N00" or mapId == "MAP_G05_N04") then
        for cy = 0, map.def.height - 1 do
          for cx = 0, map.def.width - 1 do
            local meta = map:blockAt(cx, cy)
            if meta == 75 or meta == 78 then
              height(cx, cy, 8.5, 6.5, 8, "dining chair seat")
              height(cx, cy, meta == 75 and 1.5 or 14.5, 8.5, 16, "dining chair back")
            elseif meta == 757 or meta == 765 then
              height(cx, cy, 8.5, 6.5, 8, "Center stool stays backless")
            end
          end
        end
      end
      if version == "firered" and mapId == "MAP_G10_N00" then
        local joinery = Gen3.forMap(map).profile.joinery
        check(joinery[75] and joinery[786], "secondary joinery preserves primary furniture")
        for _, cy in ipairs({ 9, 10 }) do
          height(0, cy, 1.5, 8.5, 16, "west bench back")
          height(12, cy, 14.5, 8.5, 16, "east bench back")
          height(0, cy, 8.5, 8.5, 8, "west bench cushion")
          height(12, cy, 8.5, 8.5, 8, "east bench cushion")
        end
      elseif version == "emerald" and mapId == "MAP_G11_N09" then
        for cx = 9, 11 do
          height(cx, 2, 8.5, 6.5, 8, "couch cushion")
          height(cx, 2, 8.5, 9.5, 8, "couch cushion has no carve hole")
          height(cx, 2, 8.5, 1.5, 16, "couch back")
        end
        height(9, 2, 1.5, 6.5, 12, "west couch arm")
        height(11, 2, 14.5, 6.5, 12, "east couch arm")
      elseif version == "emerald" and mapId == "MAP_G02_N02" then
        height(10, 6, 8.5, 6.5, 8, "Center stool stays backless")
      elseif version == "emerald" and mapId == "MAP_G00_N00" then
        for tx = 38, 45 do
          local center = scene.runs[key(tx, 30)]
          if center and center.roofArtTop and center.roofArtRows then
            local roofEnd = center.roofArtTop + center.roofArtRows - 1
            local wallStart = (center.gen3WallArtFront or center.front)
                              - math.floor((center.h - (center.base or 0)) / 8) + 1
            check(roofEnd < wallStart,
                  "Center roof/facade art separation at " .. tx .. ": roof ends "
                  .. roofEnd .. ", wall starts " .. wallStart)
            check(center.h + center.rise == center.peak,
              "Center preserves its total height at " .. tx)
            check(center.roofArtTop == 26 and roofEnd == 31,
              "Center preserves the complete roof emblem at " .. tx)
            check(center.h - (center.base or 0) == 16 and center.rise == 32,
              "Center corners share the facade/roof split at " .. tx)
          else
            check(false, "Center retains roof art at " .. tx)
          end
        end
        for cy = 21, 23 do
          for cx = 23, 24 do
            for dy = 0, 1 do
              for dx = 0, 1 do
                local tileKey = key(cx * 2 + dx, cy * 2 + dy)
                check(scene.runs[tileKey] == nil, "garden is not a building run")
                check(scene.skip[tileKey] == true, "garden builds its own relief")
              end
            end
          end
        end
        local gardenTop, gardenQuads = 0, 0
        for _, quad in ipairs(scene.objectQuads) do
          local centerX = (quad[1][1] + quad[2][1] + quad[3][1] + quad[4][1]) / 4
          local centerZ = (quad[1][3] + quad[2][3] + quad[3][3] + quad[4][3]) / 4
          if centerX > 23 * 16 and centerX < 25 * 16
             and centerZ > 21 * 16 and centerZ < 24 * 16 then
            gardenQuads = gardenQuads + 1
            for corner = 1, 4 do
              gardenTop = math.max(gardenTop, quad[corner][2])
            end
          end
        end
        check(gardenQuads > 0 and gardenTop <= 8,
              "garden emitted height stays low: " .. gardenTop)
        local house = scene.runs[key(20 * 2, 22 * 2)]
        check(house and house.h >= 32, "garden repair preserves neighboring house")
      end
      testedMaps = testedMaps + 1
      U.log("audited", mapId)
      Structures.invalidate(mapId)
      U.wait(1)
    end
  end
  U.log("object audit", version, "maps=" .. testedMaps, "passed=" .. passed, "failed=" .. failed)
  assert(failed == 0, "Gen 3 object geometry regressions: " .. failed)
end