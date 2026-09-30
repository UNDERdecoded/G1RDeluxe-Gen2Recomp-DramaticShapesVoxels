-- GEN 3 TERRACE HEIGHTS -- the sculpted answer, one line per terrace.
--
-- WHY THIS FILE EXISTS.
--
-- Every height model tried before this one INFERS the relief from the art at
-- render time, and each inference has a map it cannot read.  The band raster
-- (`Structures.gen3BandLevels`) gets the terraces themselves right -- measured:
-- every walkable component in Sootopolis, Rustboro, Route 123 and Mt Chimney
-- lies inside a single band, so the modal vote that picks a component's level
-- is exact -- and then the relaxation that runs after it moves 33 of
-- Sootopolis' 80 terraces back off their band, and 23% of the map's tiles end
-- up drawn at a height the pass did not ask for.
--
-- Chasing that with more inference has been tried from four directions and the
-- rejected experiments are all recorded in HOENN_RELIEF/NOTES.md.  So the
-- terrace heights stop being inferred and become DATA: a number per terrace,
-- readable against the 2D map, which no later pass may overrule.
--
-- THIS IS NOT A `map.id` SPECIAL CASE.  There is no branch anywhere that names
-- a map; there is one uniform lookup, by the cartridge's own map name, into
-- this table.  A map absent from it keeps the inferred path exactly as before,
-- which is what keeps Gen 1, Gen 2 and Prism untouched.
--
-- THE FORMAT.
--
--   ["MapName"] = { { anchorX, anchorY, level }, ... }
--
-- A terrace is named by its ANCHOR: the first cell of its walkable component
-- in reading order (top row first, then left to right).  The loader re-floods
-- the component from that cell rather than storing every cell, so the file
-- stays hand-editable -- Sootopolis is eighty lines, not 3,600.
--
-- `level` is in COURSES above the water, the same unit the band map draws and
-- the same one a person counts off the 2D map: 0 is the sea, and each terrace
-- edge or stair tile you cross on the way up is one more.
--
-- SEEDED FROM THE BAND RASTER, because the raster is already right for most
-- terraces; the hand pass is corrections, not a blank page.  A line that has
-- been checked against the drawing carries `-- ok`; one that has been changed
-- carries the reason.
--
-- THE SEED RULE IS ONE COURSE PER RUN OF THE SAME EDGE METATILE -- what the
-- raster calls MODE=run.  One course per edge CELL was tried first, because
-- "each stair tile for cliff edge or cliff face should raise the height by 1"
-- reads that way and it is the rule that reaches thirteen in Sootopolis.  The
-- frame says no: every boundary in the town becomes a wall several courses
-- tall, the cliff drawing fills in between, and the city renders as a maze of
-- white rock with the houses sunk into it.
--
-- Thirteen is the DEPTH of the drop from rim to lake, not the number of places
-- to stand.  There are seven of those.  The rest of the height belongs to how
-- deep each cliff is drawn between two terraces, which is a question about the
-- wall, not about this table.
--
-- ...AND IT IS READ WITH THE PAVING DEMOTED.
--
-- Sootopolis' pale stone is metatile 729, drawn with a lit top edge and a
-- shadow -- the same way the tileset draws a terrace rim -- so the reader
-- called all 894 of its cells a step.  607 of them are walkable, and you
-- cannot stand on the front of a cliff.  `Gen3.isGroundMeta` demotes a
-- metatile that is walkable in most of the places it appears; see the census
-- on that function.  Seeded before that landed, this table was a rainbow.
--
-- ...AND THE DATUM IS THE CARTRIDGE'S WATER, NOT THE ART'S.
--
-- `Gen3.roleAt` called the Pokemon Mart's blue roof water, so the flood was
-- seeded at zero in the middle of the town and everything around it was
-- dragged down -- the sunken-behind-the-Mart report, traced to a cheapest path
-- that began inside the building.  The seed reads the behaviour byte instead.
-- With that and the shore step, the west column at x=12 reads 1, 2, 3 against
-- the art's 1, 2, 3 where it used to read 0, 0, 1.
--
-- THE SHORE IS THE DATUM.  The grass beside the lake is ground level and the
-- lake is dug out of it, so Sootopolis' eight walkable heights are 0 through 7
-- -- eight distinct levels, which is the eight counted off the 2D map.
--
-- ...AND THE HEIGHT IS WHAT THE STAIRCASES SAY.
--
-- In a town you cannot walk up a cliff, so a terrace is as high as the number
-- of FLIGHTS climbed to reach it from the shore.  Calibrated against the count
-- off the 2D map: Sootopolis is eight high in walkable terraces, and this rule
-- gives exactly eight.  One contiguous flight is one course however deep it is
-- drawn; stacked flights separated by a landing stack.  The constraint runs
-- both ways, so a flight coming DOWN from a terrace already fixed pulls the
-- ground south of it one lower.  See `Structures.gen3BandLevels`.
--
-- (superseded, kept for the record:)
-- ...AND THE WALK PAYS ONCE PER WALL WITH NO ROAD ALONG IT.
--
-- Charging per run of the same edge metatile made the rock network a free
-- highway: traced to (12,17), the flood paid one to enter the wall at (23,23)
-- and ran six cells along the inside of it for nothing, undoing two staircases
-- on the way.  The walk now carries a heading -- free to turn on ground, one
-- course to enter rock and the heading locks, straight on only inside it.  See
-- `Structures.gen3BandLevels`.
--
-- ONLY THE MAPS THE STAIRCASES CAN SPEAK ABOUT ARE IN HERE.
--
-- The rule derives height from the only way a player may climb, so a map with
-- no flight joining two terraces gets no entry and keeps the passes it had
-- before.  Towns draw staircases; routes and mountains draw CLIFFS, which is a
-- different statement.  Measured across the region, `banded` walkable art
-- outside a town tileset is almost absent -- Mt Pyre and Lavaridge have none
-- at all, Route 112 and Mt Chimney two cells each.
--
-- Answering anyway is what a first run did, and it flattened Hoenn: 80 maps at
-- one course with Sootopolis the only relief on the cartridge.
--
-- THE MERGE IS GONE.  It existed to smooth a raster that was noisy cell by
-- cell; the staircase model has no such noise -- a terrace takes one number
-- because a terrace is one piece of ground -- and the median it took differed
-- from the component's own reading on 3 of Sootopolis' 80 terraces, which is
-- 3 terraces of smoothing with nothing to smooth.
--
-- (superseded, kept for the record:)
-- ...AND THE SEED IS MERGED ACROSS EVERYTHING THAT IS NOT A WALL.
--
-- The raster is noisy cell by cell -- a wall is one metatile per course, and
-- which course a path is charged depends on the direction it comes from -- so
-- eighty scraps of Sootopolis floor, each voting its own band, come out a
-- course apart from their own neighbours.  A railing is not a terrace edge.
-- The seed therefore unions components through rails, planters, signposts,
-- trees and the ground under houses, cutting only at walls and staircases, and
-- gives each union the MEDIAN band of its cells, which the noise cannot move
-- the way it moves a mode.
return {
  version = 1,
  maps = {
    -- ROUTE 114 -- THE METEOR FALLS ENTRANCE, WHICH WAS NOT BEING BUILT AT ALL.
    --
    -- REPORTED from play: "at the entrance of meteor falls ... where the sign
    -- is is supposed to be 1 higher than it is, the stairs aren't raising the
    -- ground and are sunken/flat there; this should raise the meteor falls
    -- entrance and mountains behind it as well".
    --
    -- MEASURED: the terrace pass NEVER RAN on this map.  It is tiered, it
    -- states exactly ONE ledge, and that ledge comes out flat -- comp 24 and
    -- comp 9 both at 0 where the hop says 24 is a course above 9 -- so the
    -- tiered ledge check refused the whole map and Route 114 fell through to
    -- the flight graph.  The symptom is unmistakable in the height field: the
    -- shelf at the cave mouth, cols 7..10 rows 64..70, has NO synthZ at all,
    -- and both flights beside the sign at (12,69) have no landings to step
    -- between.
    --
    -- The ledge is a directed statement from the cartridge and the only one
    -- this map makes, so it is honoured: comp 24 is authored at 1, which
    -- satisfies it.  Every other row is the solver's own settled answer
    -- verbatim -- all thirty are listed because a sculpted map refuses the
    -- relaxation, so a partial list leaves the rest on their raw vote.
    ["Route114"] = {
      {  0,   0, 2 },  --   53 cell(s)
      { 10,   0, 1 },  --    6 cell(s)
      { 17,   0, 2 },  --    2 cell(s)
      { 21,   0, 1 },  --    7 cell(s)
      { 25,   0, 0 },  --   15 cell(s)
      { 16,   1, 0 },  --   13 cell(s)
      { 26,   2, 0 },  --  959 cell(s)
      { 19,   3, 4 },  --    1 cell(s)
      {  7,   4, 2 },  --   11 cell(s)
      {  5,   8, 1 },  --   40 cell(s)
      {  9,  10, 1 },  --   12 cell(s)
      {  2,  13, 1 },  --    3 cell(s)
      {  7,  15, 0 },  --    1 cell(s)
      {  1,  17, 0 },  --  355 cell(s)
      {  5,  17, 1 },  --    8 cell(s)
      { 37,  18, 0 },  --    2 cell(s)
      { 16,  20, 1 },  --    1 cell(s)
      {  6,  21, 0 },  --    2 cell(s)
      { 30,  22, 1 },  --    7 cell(s)
      { 35,  22, 0 },  --    2 cell(s)
      { 30,  24, 0 },  --    3 cell(s)
      { 33,  24, 0 },  --    2 cell(s)
      { 10,  25, 0 },  --   16 cell(s)
      { 11,  35, 1 },  --  188 cell(s)  the map's one ledge states this is a course above comp 9
      {  6,  45, 1 },  --  229 cell(s)
      { 29,  51, 0 },  --  320 cell(s)
      { 14,  62, 0 },  --  104 cell(s)
      {  7,  63, 0 },  --   69 cell(s)
      { 12,  68, 1 },  --  179 cell(s)
      { 26,  69, 1 },  --    8 cell(s)
    },

    -- ROUTE 115 -- THE SHELF ABOVE THE WATER BY THE METEOR FALLS ENTRANCE.
    --
    -- REPORTED from play: "the ground next to water and the staircase should
    -- be 0, the top of the stair next to the ground by the water should lead
    -- up to 1", and separately "the area leading to the route 115 meteor
    -- falls entrance is flat when its supposed to be raised".
    --
    -- The flight is at (16..17, 46), TWO CELLS WIDE AND ONE DEEP, with the
    -- bank and the water west of it.  The tread rule this revision fixes
    -- ("A FLIGHT IS AS TALL AS ITS TREADS, NOT AS WIDE AS IT IS") already
    -- gives it the right size -- `stairPair 17<->16` goes from w=2 to w=1, so
    -- the bank stays 0 and the shelf above becomes 1, exactly as reported.
    --
    -- SO EVERY ROW HERE IS THE SOLVER'S OWN ANSWER, VERBATIM.  Nothing is
    -- corrected; the map is listed only so that it is ACCEPTED.
    --
    -- Route 115 states three ledges.  With the shelf at 1 two of them hold and
    -- the third comes out FLAT: it says comp 16 is one course above comp 19,
    -- and comp 19 is itself one course above the beach (comp 18) by its own
    -- ledge, so the two statements want 16 at 2 -- which is the reading the
    -- owner says is wrong, and the one the drawn tread count disagrees with.
    -- The three cannot all hold; the tiered ledge check refuses the WHOLE MAP
    -- for it and Route 115 falls through to the flight graph, which is worse
    -- everywhere.  A flat ledge is a step the player does not see; a refused
    -- map is every terrace on it inferred by a builder that has already been
    -- measured as worse.  Taking the flat one is the cheaper of the two, and
    -- listing the map is how this file says so.
    --
    -- All twenty components are listed because a sculpted map refuses the
    -- relaxation, so a partial list leaves the rest on their raw vote and the
    -- tiered ledge check then refuses the whole map.
    ["Route115"] = {
      {  2,   0, 0 },  --  519 cell(s)
      { 28,   0, 1 },  --   73 cell(s)
      { 38,   0, 1 },  --  238 cell(s)
      { 18,   6, 1 },  --   62 cell(s)
      { 29,   6, 2 },  --  203 cell(s)
      { 20,  13, 1 },  --   91 cell(s)
      {  7,  19, 1 },  --    2 cell(s)
      { 19,  20, 1 },  --  432 cell(s)
      {  7,  31, 0 },  --    2 cell(s)
      { 10,  34, 0 },  --   16 cell(s)
      { 15,  36, 3 },  --   12 cell(s)
      -- 3, NOT 2 -- THE METEOR FALLS ENTRANCE.  REPORTED from play: "at the
      -- entrance of meteor falls ... where the sign is is supposed to be 1
      -- higher than it is, the stairs aren't raising the ground and are
      -- sunken/flat there; this should raise the meteor falls entrance and
      -- mountains behind it as well".  This is the pocket that holds warp 1
      -- at (27, 37) -- Meteor Falls 1F -- and the script sign at (25, 38).
      --
      -- MEASURED: at 2 the flight at (24..25, 42) came out FLAT, 32 -> 32,
      -- because this pocket and the shelf below it (comp anchored (16, 43))
      -- both landed at 32 -- the shelf is authored a level lower but its
      -- storey offset brings its elevation-3 ground back up to meet this.
      -- At 3 the pocket stands at 48, the flight steps 32 -> 48, and the rock
      -- mass behind the cave mouth follows the terrace it retains.  Route
      -- 115's flat flights go 2 -> 1.
      { 27,  37, 3 },  --   16 cell(s)  the Meteor Falls entrance pocket
      { 29,  38, 2 },  --    3 cell(s)
      { 17,  40, 2 },  --    4 cell(s)
      { 31,  40, 2 },  --   55 cell(s)
      { 16,  43, 1 },  --  240 cell(s)  the shelf the water-side flight climbs to
      { 14,  45, 0 },  --   44 cell(s)  the bank beside the water
      {  9,  60, 0 },  --   63 cell(s)  the beach, and the datum for the chain
      { 15,  61, 1 },  --  312 cell(s)  one ledge above the beach
      { 12,  76, 0 },  --    5 cell(s)
    },

    -- ROUTE 120 -- CARRYING FORTREE'S DATUM EAST.
    --
    -- REPORTED from play: "raise route 120 to the height of fortree city".
    --
    -- Two things were wrong here and the datum only fixes the second.
    --
    -- FIRST, this map's terrace pass NEVER RAN.  Probed, it is refused at the
    -- tiered-ledge gate -- one ledge that does not come out a single course --
    -- exactly like Route 114 and Route 115 were before they were listed here.
    -- Its west gate, cells (0..3, 5..10), had NO synthZ at all and fell to the
    -- floor, and all four of its staircases had no landings to step between.
    -- Listing the map makes it `sculpted`, which exempts it from that gate.
    --
    -- SECOND, the height it solves to is its own, starting from zero.  The
    -- component holding the west gate settles at level 2 -- 32px -- against
    -- Fortree's east gate at 80, so `datum = 3` carries the floor up to meet
    -- it.  MEASURED after: the west gate stands at 80, exactly level with
    -- Fortree, and the map's histogram is the same one shifted three courses
    -- (z0/16/32/48/64 = 94/1052/1624/115/110 becomes z48/64/80/96/112 with
    -- the same five counts).
    --
    -- THE EAST SEAM IMPROVES TOO, which was not the reason for the number but
    -- is worth recording: `east -> Route121, offset 80` puts this map's gate
    -- at rows 86..93 against Route 121's rows 6..13, which stand at 48.  This
    -- gate had no height at all and now stands at 64 -- one course over its
    -- neighbour instead of three under it.
    --
    -- All thirty-three levels are the solver's own, verbatim; a sculpted map
    -- refuses the relaxation, so a partial list would leave the rest on their
    -- raw vote.  Nothing inside Route 120 is corrected here.
    ["Route120"] = {
      datum = 3,       -- courses; Fortree's east gate stands at 80 = 5 x 16
      {  0,   0, 2 },  --  1052 cell(s)  the northern plain, and the WEST GATE onto Fortree
      { 17,  13, 0 },  --     6 cell(s)
      { 18,  21, 0 },  --    11 cell(s)
      { 29,  24, 1 },  --   661 cell(s)
      { 13,  30, 1 },  --     6 cell(s)
      { 10,  31, 1 },  --     1 cell(s)
      { 20,  31, 1 },  --     1 cell(s)
      { 26,  31, 1 },  --     2 cell(s)
      { 19,  32, 1 },  --     5 cell(s)
      { 20,  32, 1 },  --     2 cell(s)
      { 25,  32, 1 },  --     8 cell(s)
      { 14,  34, 1 },  --     3 cell(s)
      { 15,  35, 1 },  --     2 cell(s)
      { 16,  37, 1 },  --     2 cell(s)
      { 17,  38, 1 },  --     2 cell(s)
      {  6,  39, 1 },  --     2 cell(s)
      { 12,  39, 1 },  --     1 cell(s)
      {  8,  42, 4 },  --    22 cell(s)
      { 14,  42, 3 },  --     7 cell(s)
      { 12,  43, 2 },  --     2 cell(s)
      { 14,  45, 2 },  --    73 cell(s)
      {  9,  47, 2 },  --   286 cell(s)
      { 19,  61, 2 },  --   211 cell(s)
      { 24,  63, 0 },  --    14 cell(s)
      { 12,  67, 3 },  --   108 cell(s)
      { 18,  73, 1 },  --   354 cell(s)
      { 22,  77, 0 },  --    29 cell(s)
      { 30,  84, 0 },  --     1 cell(s)
      {  0,  86, 4 },  --    88 cell(s)  the EAST GATE onto Route 121
      {  4,  96, 0 },  --     1 cell(s)
      {  6,  96, 0 },  --    29 cell(s)
      {  2,  97, 0 },  --     2 cell(s)
      { 39,  99, 0 },  --     1 cell(s)
    },

    -- ROUTE 119'S STAIRCASE LADDER -- read off the 2D, because nothing in
    -- the cartridge orders it.
    --
    -- REPORTED from play: "the stairs up here are supposed to lead up to a
    -- raised terrace not lowering like it currently is ... theres another
    -- flight of stairs above that ... but its going downward dropping the
    -- height".
    --
    -- FOUR staircases join FIVE terraces here, and every cell of all five is
    -- elevation 3, so the grid states ONE level across the whole ladder.  A
    -- boundary weight caps how big a step may be and never says which side is
    -- up, and the two DIRECTED statements Gen 3 makes outright are ledges and
    -- muddy slopes -- ROUTE 119 STATES EXACTLY ONE LEDGE ON THE WHOLE MAP.
    -- So the solver orders the chain by distance from its seed and comes out
    -- 1, 2, 2, 1, 2 going north: up, flat, DOWN, up.
    --
    -- Four direction sources were measured and all rejected, which is why
    -- this is data and not a rule:
    --   * the elevation NUMBER -- of the 27 stair chains the mod already gets
    --     right, ArtisanCave_B1F, VictoryRoad_1F and VictoryRoad_B1F each
    --     carry BOTH `higher=e3 lower=e4` and the reverse;
    --   * the LEDGE GRAPH (regions as nodes, MB_JUMP_* as directed edges,
    --     transitive closure) -- silent on 43 of 43 stated steps region-wide,
    --     and on all 16 of the flat ones;
    --   * the drawn FACING (`Gen3.cliffFacing`) -- scored against the
    --     cartridge's own elevation ranks it agrees 476 times and DISAGREES
    --     200, 70.4%, and is systematically inverted on whole maps
    --     (Route123 16%, MossdeepCity 17%, SafariZone_Southeast 22%);
    --   * zeroing a boundary whose two sides share a stated elevation --
    --     collapses the solve below `g3c.levels` and the pass declines the
    --     map outright.
    --
    -- THE DIRECTION IS READ OFF THE DRAWING, which is what this file is for.
    -- Hoenn draws a cliff TOP as dark bumpy rock and its FACE as pink
    -- diagonal hatching.  Every band in the ladder -- rows 26..27, 31, 36 and
    -- 41 -- shows its dark top against the terrace to its NORTH and drops to
    -- the ground south of it, and each staircase is cut through the band with
    -- its landing on the north side.  The route climbs northward, the way the
    -- river beside it falls.
    --
    -- THE SIZES ARE THE ART'S.  The pass already counts each flight's drawn
    -- treads and they are 1, 1, 1 and 2 going north (`stairPair` w).
    --
    -- THE DATUM IS THE WATER.  REPORTED: "the ground near the water in the
    -- multiple staircase area is at 1 instead of level with the water".  The
    -- ladder's foot (comp 14, rows 42..45) edges the river, which stands at
    -- -4, so the foot is level 0 and the chain reads 0, 1, 3, 3, 5 -- the
    -- same four steps, started at the shore the way this file's own header
    -- asks ("THE SHORE IS THE DATUM").
    --
    -- EVERY component is listed, not just the five, because a listed map
    -- refuses the relaxation ("On a sculpted map every proposed move is
    -- refused") -- so a partial list leaves the rest on their raw vote and
    -- Route 119's one ledge stops being exactly one course, which the tiered
    -- ledge check then refuses the whole map for.  The other thirty carry the
    -- solver's own settled answer verbatim.
    ["Route119"] = {
      {  0,   0, 1 },  --  449 cell(s)
      { 23,   4, 5 },  --  577 cell(s)  +2 drawn treads  the north-east high ground
      {  0,  11, 1 },  --  393 cell(s)
      { 16,  21, 3 },  --   10 cell(s)
      { 11,  25, 1 },  --    1 cell(s)
      { 17,  25, 0 },  --   12 cell(s)
      -- 3, AND THE ALTERNATIVE WAS MEASURED.  This component is not one
      -- storey: it carries the elevation-3 shelf at cols 24..30 rows 32..35
      -- AND the elevation-4 ground north of it, and the storey offset splits
      -- them.  Authored at 3 the shelf stands at 32, the band above it at 48,
      -- and the flight at (24..25, 36) steps 16 -> 32.  Authored at 4 the
      -- whole component goes up a course and the flight at (25..26, 31) comes
      -- out FLAT (48 -> 48) -- three flat flights on the map instead of two.
      { 11,  28, 3 },  --  297 cell(s)  the mid-route shelf, +1 drawn tread
      { 24,  28, 3 },  --   21 cell(s)  +1 drawn tread   the pocket below the cave
      { 16,  29, 0 },  --    2 cell(s)
      { 20,  29, 0 },  --    2 cell(s)
      { 32,  30, 2 },  --    1 cell(s)
      { 30,  32, 2 },  --    3 cell(s)
      { 24,  37, 1 },  --   23 cell(s)  +1 drawn tread
      { 24,  42, 0 },  --   15 cell(s)  the foot, LEVEL WITH THE WATER it edges
      { 24,  47, 0 },  --   35 cell(s)
      { 35,  47, 0 },  --    2 cell(s)
      { 28,  48, 1 },  --  569 cell(s)
      { 34,  50, 0 },  --   12 cell(s)
      {  1,  52, 2 },  --    1 cell(s)
      { 36,  58, 0 },  --   35 cell(s)
      { 32,  62, 0 },  --  118 cell(s)
      { 27,  68, 0 },  --   13 cell(s)
      { 24,  73, 0 },  --   60 cell(s)
      { 19,  74, 0 },  --   18 cell(s)
      {  1,  78, 1 },  --   10 cell(s)
      { 31,  80, 3 },  --    2 cell(s)
      -- 1, not 0.  REPORTED: "lower in route 119 there's still areas where
      -- stairs aren't raising the ground north of them".  The flight at
      -- (5..6, 80) joins this to comp 18, and BOTH are mostly elevation 3 --
      -- so their ground is one storey and comp 18 stands at 1.  At 0 this
      -- one's elevation-3 ground sat a course below its neighbour's and the
      -- elevation-4 pocket at (3..6, 81..85) landed exactly level with comp
      -- 18, which is the flat flight.  At 1 the ground matches and the
      -- pocket the cartridge ranks above it stands a course up.
      {  3,  81, 1 },  --  399 cell(s)
      {  0,  86, 1 },  --    1 cell(s)
      {  2,  86, 0 },  --  484 cell(s)
      { 38,  87, 1 },  --    2 cell(s)
      { 33,  89, 1 },  --   44 cell(s)
      { 39,  90, 0 },  --   35 cell(s)
      {  4,  96, 1 },  --   67 cell(s)
      { 11, 104, 0 },  --    6 cell(s)
      { 26, 104, 1 },  --  972 cell(s)
    },

    -- FortreeCity  40x20  13 terrace(s), tallest band 1
        -- FORTREE CITY -- THE SEAM WITH ROUTE 119.
    --
    -- REPORTED from play: "ensure fortree cities ground height matches route
    -- 119s height where they meet".
    --
    -- MEASURED: Fortree's west gate is cells (0..3, 6..11) and Route 119's
    -- east gate is (36..39, 5..10); the connection is `west -> Route119,
    -- offset 0`, so the two rows line up one for one.  Route 119's gate
    -- stands at 80 -- the top of the drawn ladder authored under
    -- `["Route119"]` below -- and Fortree's stood at 0.  An 80px wall across
    -- the seam the player walks through.
    --
    -- The levels below are the fourteen the solver settles on, VERBATIM:
    -- nothing inside the city is corrected, because nothing inside it was
    -- reported wrong.  They are listed only so the map is fully authored and
    -- the datum has something to lift.  `datum` is the whole fix -- see
    -- `gen3TerraceDatum` in Structures.lua for why it cannot be done by
    -- writing 5 and 6 in the rows instead (it flattens the tree tier).
    --
    -- The cells named are real cells of each component, not necessarily its
    -- anchor; the loader asks which component holds the cell.
    ["FortreeCity"] = {
      datum = 5,       -- courses; Route 119's east gate stands at 80 = 5 x 16
      {  0,   0, 0 },  --  395 cell(s)  the city floor
      {  7,   0, 1 },  --  151 cell(s)  the north strip
      { 32,   2, 1 },  --    1 cell(s)
      { 17,   3, 1 },  --    1 cell(s)
      { 25,   3, 1 },  --    1 cell(s)
      { 12,   4, 0 },  --    4 cell(s)  a hut deck; its height is the tier's
      { 19,   4, 0 },  --    5 cell(s)  a hut deck
      { 27,   4, 0 },  --    4 cell(s)  a hut deck
      { 25,   5, 0 },  --   29 cell(s)
      { 32,   5, 0 },  --   89 cell(s)  the eastern ground, toward Route 120
      { 13,   8, 0 },  --    1 cell(s)
      { 29,   8, 0 },  --    1 cell(s)
      { 12,  12, 1 },  --   16 cell(s)
      { 37,  13, 1 },  --    1 cell(s)
    },
    -- SootopolisCity  60x60  80 terrace(s), tallest band 7
    -- ROUTE 112  40x60  31 terrace(s).  Mt Chimney's foothills: the ash
    -- plateau, the Cable Car Station on it, the two Fiery Path mouths in its
    -- west wall, and the grass at its foot.
    --
    -- ONE FLIGHT, SO TWO LEVELS.  The route draws exactly one staircase --
    -- the General tileset's 175/207, six cells at (20..21, 41..43), climbing
    -- NORTH off the grass and through the rock wall onto the plateau -- and
    -- there is no other way up, because everything else round the plateau is
    -- drawn as a face you cannot climb.  A terrace is as high as the number
    -- of flights climbed to reach it, so the plateau is 1 and the land at its
    -- foot is 0.  Nothing here is eyeballed off the picture.
    --
    -- AND THE CARTRIDGE SORTS THE THIRTY-ONE TERRACES ITSELF.  Emerald marks
    -- the plateau MB_MOUNTAIN_TOP (0x0C) and the low ground MB_NORMAL, and
    -- the split is total:
    --
    --   19 terraces, 173 cells   MOUNTAIN_TOP on every cell   -> 3
    --   12 terraces, 355 cells   MOUNTAIN_TOP on none of them -> 0
    --
    -- ...AND THE NUMBER IS THREE, NOT ONE, BECAUSE THE CLIFF IS DRAWN THREE
    -- DEEP.  One flight = one course is the rule for a TOWN, where a
    -- staircase is a step between two paved levels.  A route draws its drop
    -- instead: between the plateau's last walkable ash at row 40 and the
    -- grass at row 44 the art puts THREE rows of cliff -- 41, 42, 43 -- and
    -- the staircase through it is three stacked stair metatiles, 175/207 at
    -- each of those rows.  Reported from the frame: "the terrace with 3
    -- stacked cliffs and 3 stacked stairs is only 1 high".  It is three, and
    -- the flight ramps 48px over its three cells.
    --
    -- (terrace `m`, the plateau's 128-cell main floor, reads 125 of 128; the
    -- three are the Cable Car Station's own doorstep.)  So the numbers below
    -- are the behaviour byte, not a reading of the art -- the art was used
    -- only to check the answer, and it agrees: green grass at the bottom and
    -- along the east, ash above the rock wall.
    --
    -- The nineteen one-cell terraces are gaps in the tree lines and pockets
    -- in the lava ridges; they are cut out as their own components because a
    -- ledge or a tree separates them, and each takes the level of the ground
    -- it is drawn on.
    ["Route112"] = {
      { 26,  6, 0 },  -- 91 cell(s)   the north grass, below the plateau's north face
      { 23, 19, 3 },  -- 2 cell(s)
      { 21, 20, 3 },  -- 1 cell(s)
      { 20, 21, 3 },  -- 5 cell(s)
      { 22, 21, 3 },  -- 1 cell(s)
      { 24, 22, 3 },  -- 1 cell(s)
      { 30, 22, 3 },  -- 7 cell(s)
      { 22, 23, 3 },  -- 20 cell(s)
      { 34, 23, 3 },  -- 1 cell(s)
      { 33, 25, 3 },  -- 1 cell(s)
      { 11, 26, 3 },  -- 1 cell(s)   a pocket in the west lava mass
      { 21, 27, 3 },  -- 1 cell(s)
      { 28, 27, 3 },  -- 128 cell(s) the ash plateau's main floor
      { 22, 28, 3 },  -- 1 cell(s)
      { 19, 29, 3 },  -- 1 cell(s)
      { 34, 29, 3 },  -- 1 cell(s)
      { 16, 30, 3 },  -- 2 cell(s)
      { 35, 31, 3 },  -- 1 cell(s)
      { 34, 33, 3 },  -- 1 cell(s)
      { 15, 34, 3 },  -- 1 cell(s)
      { 35, 35, 0 },  -- 1 cell(s)   east grass strip, outside the plateau wall
      { 34, 36, 0 },  -- 1 cell(s)
      { 35, 41, 0 },  -- 1 cell(s)
      { 31, 42, 0 },  -- 1 cell(s)
      { 14, 43, 0 },  -- 10 cell(s)  a grass corridor between two lava ridges
      { 26, 43, 0 },  -- 164 cell(s) the south grass, the staircase's bottom
      { 36, 43, 0 },  -- 1 cell(s)
      { 16, 44, 0 },  -- 9 cell(s)
      {  6, 46, 0 },  -- 66 cell(s)  the south-west grass
      { 11, 46, 0 },  -- 14 cell(s)
      { 18, 54, 0 },  -- 6 cell(s)
    },

    ["SootopolisCity"] = {
      { 16, 0, 6 },  -- 1 cell(s)
      { 18, 0, 6 },  -- 10 cell(s)
      { 39, 0, 5 },  -- 5 cell(s)
      { 55, 0, 4 },  -- 7 cell(s)
      { 13, 2, 6 },  -- 3 cell(s)
      { 34, 2, 5 },  -- 5 cell(s)
      { 43, 2, 5 },  -- 20 cell(s)
      { 25, 3, 5 },  -- 45 cell(s)
      { 38, 3, 5 },  -- 4 cell(s)
      { 7, 5, 7 },  -- 3 cell(s)
      { 15, 5, 6 },  -- 25 cell(s)
      { 37, 5, 5 },  -- 6 cell(s)
      { 41, 5, 5 },  -- 6 cell(s)
      { 57, 5, 4 },  -- 7 cell(s)
      { 47, 6, 5 },  -- 1 cell(s)
      { 9, 7, 7 },  -- 1 cell(s)
      { 5, 8, 7 },  -- 2 cell(s)
      { 43, 8, 5 },  -- 4 cell(s)
      { 7, 9, 6 },  -- 2 cell(s)
      { 27, 9, 4 },  -- 9 cell(s)
      { 19, 10, 5 },  -- 2 cell(s)
      { 40, 11, 4 },  -- 1 cell(s)
      { 45, 11, 4 },  -- 31 cell(s)
      { 56, 11, 4 },  -- 4 cell(s)
      { 59, 11, 4 },  -- 1 cell(s)
      { 0, 12, 5 },  -- 2 cell(s)
      { 10, 12, 5 },  -- 9 cell(s)
      { 23, 12, 3 },  -- 1 cell(s)
      { 37, 12, 3 },  -- 1 cell(s)
      { 3, 13, 5 },  -- 7 cell(s)
      { 18, 13, 4 },  -- 1 cell(s)
      { 25, 13, 3 },  -- 13 cell(s)
      { 53, 13, 4 },  -- 12 cell(s)
      { 58, 13, 4 },  -- 2 cell(s)
      { 5, 14, 4 },  -- 10 cell(s)
      { 12, 14, 4 },  -- 32 cell(s)
      { 19, 15, 4 },  -- 2 cell(s)
      { 22, 15, 2 },  -- 3 cell(s)
      { 36, 15, 3 },  -- 2 cell(s)
      { 24, 16, 2 },  -- 10 cell(s)
      { 31, 16, 1 },  -- 50 cell(s)
      { 39, 16, 3 },  -- 1 cell(s)
      { 42, 16, 3 },  -- 26 cell(s)
      { 35, 17, 1 },  -- 9 cell(s)
      { 16, 18, 3 },  -- 16 cell(s)
      { 47, 18, 3 },  -- 1 cell(s)
      { 59, 18, 4 },  -- 3 cell(s)
      { 7, 21, 3 },  -- 1 cell(s)
      { 52, 21, 3 },  -- 3 cell(s)
      { 9, 22, 3 },  -- 6 cell(s)
      { 20, 22, 2 },  -- 6 cell(s)
      { 55, 22, 2 },  -- 24 cell(s)
      { 5, 23, 2 },  -- 9 cell(s)
      { 44, 23, 2 },  -- 41 cell(s)
      { 51, 23, 3 },  -- 8 cell(s)
      { 12, 24, 2 },  -- 14 cell(s)
      { 0, 25, 2 },  -- 3 cell(s)
      { 18, 25, 1 },  -- 2 cell(s)
      { 21, 25, 1 },  -- 29 cell(s)
      { 55, 26, 2 },  -- 9 cell(s)
      { 0, 29, 2 },  -- 4 cell(s)
      { 3, 30, 2 },  -- 11 cell(s)
      { 7, 30, 2 },  -- 8 cell(s)
      { 15, 30, 2 },  -- 41 cell(s)
      { 27, 32, 0 },  -- 36 cell(s)
      { 42, 32, 1 },  -- 32 cell(s)
      { 54, 32, 2 },  -- 3 cell(s)
      { 58, 32, 1 },  -- 4 cell(s)
      { 4, 34, 2 },  -- 1 cell(s)
      { 53, 34, 1 },  -- 3 cell(s)
      { 15, 35, 1 },  -- 3 cell(s)
      { 2, 36, 2 },  -- 2 cell(s)
      { 5, 36, 2 },  -- 2 cell(s)
      { 19, 36, 0 },  -- 8 cell(s)
      { 40, 37, 0 },  -- 48 cell(s)
      { 57, 37, 1 },  -- 1 cell(s)
      { 0, 38, 0 },  -- 1 cell(s)
      { 2, 38, 0 },  -- 9 cell(s)
      { 17, 38, 0 },  -- 62 cell(s)
      { 50, 48, 0 },  -- 4 cell(s)
    },
  },
}
