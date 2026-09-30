# Dramatic Shape Voxel Mod

A mod for the [Pokémon Gen 1 Recompilation
Project](https://github.com/bryanthaboi/pokemon-gen1-recomp-project).

The overworld as a voxelized 3D diorama. Also supports experimental
first-person, third-person and VR.

## Native Emerald Port

Version 0.7.75 exposes **VOXEL** in Emerald's **Options** menu and in
**Mods > Dramatic Shape > Options**. Choose an angle or FULL to enable it;
choose OFF to restore the native world. Both menus and the `3` hotkey share
the same saved camera setting.

Fortree bridge step/bounce updates retain the completed voxel mesh while a
replacement builds, preventing the town from blinking back to the flat world.
Player and NPC floor heights use that mesh's completed structure data until
the replacement is published, so bridge updates do not sink actors into it.

An imported copy in the game's save folder takes precedence over the source
mod folder. If the import list still shows upstream version 1.5.5 or marks it
incompatible, replace that installed copy with this gen1recomp port and fully
restart the game. Look for version 0.7.75 and the `(gen1recomp)` name suffix.
The upstream update source is intentionally disabled for this port.

The native Emerald adapter resolves the mod's Emerald map and
tileset profiles and reads original metatile layers from your imported cache.
The native map adapter supplies the door lookup and border patch required by
the existing structure builder. A missing lookup previously aborted the build
before roofs and trees were created, and the error was swallowed, leaving a
partially built flat scene. Failed builds now report the error instead.
Native Tilt's split terrain/actor passes no longer bypass voxel rendering.
Restart the game after updating; the voxel cache revision rebuilds older native
meshes automatically. No engine files or ROM reimport are required for this fix.
Press `3` in the field to cycle voxel cameras. Native Tilt alone is not voxel mode.

The real-asset graphics check verifies raised building runs, tree-hull geometry,
and uploaded GPU meshes in Oldale and Littleroot with native Tilt enabled.
Profile and texture checks alone do not establish correct voxel geometry;
other Emerald maps and native FireRed rendering have not had this geometry audit.

This port is still experimental: first/third-person cameras are connected,
but movement remains native grid movement, and native Emerald staged battles
and VR are not yet ported. Older feature descriptions below describe the
upstream implementation, not complete native Emerald support.

The focused checks are `tests/emerald_port_test.lua` and
`tests/native_tiles_test.lua` inside this mod. The real-asset LÖVE driver is
`mods/DRAMATIC_SHAPE/tests/emerald_port_shots.lua`, run from the engine root
with `POKEPORT_VERSION=emerald` and `POKEPORT_DRIVER` set to that path. Use an
isolated `POKEPORT_IDENTITY` containing an imported Emerald cache; the driver
creates a temporary session and suppresses save/option writes.

## Emerald and FireRed Objects

Version 0.7.71 reconstructs selected furniture and plant families from the
games' own artwork. Emerald couches have 8px cushions, 16px backs and 12px
arms. FireRed department-store benches and dining chairs have raised backs;
Center stools remain backless. Registered plant crowns attach to the actual
pot mesh, gain rounded depth, and no longer leave duplicate foliage on the
floor. Petalburg's planting bed and grassy border stay below the house roof.

This is not an all-object fidelity guarantee. Some outdoor roof/facade bands
still overlap, existing tree and terrain shapes need further work, and the
Emerald couch's upper wall-band artwork remains in place. Hidden depth and
furniture heights are authored approximations, not measurements uniquely
recoverable from a single 2D view.

### Authoring

In `data/gen3_shapes.lua`, `tilesets[tilesetName].joinery` adds per-metatile
overrides to already-classified indoor furniture:

```lua
joinery = {
  [860] = {
    height = 8,
    layer2 = true,
    parts = { { 0, 0, 15, 2, 16 }, { 0, 3, 2, 11, 12 } },
  },
}
```

Each part is `{x0, z0, x1, z1, topHeight}` with inclusive local pixel
coordinates 0..15. Heights are relative to the floor. `layer2` uses the
source foreground alpha mask when available. Omitting `parts` preserves
automatic chair-back detection; `parts = false` disables it. Overrides merge
by metatile from primary to secondary to map, so secondary seating does not
discard shared primary furniture.

In the version-specific `gen3_palings.lua`, `overhead[pairId].figures` entries
use `{meta, under, south, round}`. `under` is clean replacement background art;
`south` locates the supporting object. `round = true` gives each silhouette
row circular depth centered on that support. The pass measures both direct
quads and translated round stamps after furniture placement.
`primaries[primaryHex].figures` shares entries across tileset pairs, provided
both IDs are below the cartridge's primary boundary (Emerald 512, FireRed
640). Pair-specific entries take precedence. Validate background candidates
with `tools/gen3_find_under.py`; its exact layer-1 match is stronger than an
outside-silhouette match alone. Bump `Structures.SHAPE_REV` after changing
geometry or profiles to invalidate persisted meshes.

### Validation

Run `tests/gen3_objects_test.lua` as a LÖVE driver from the engine root with
the mod enabled, imported game data configured, `POKEPORT_VERSION` and
`POKEPORT_UNLOCK` set to `emerald` or `firered`, and `POKEPORT_DRIVER` set to
`mods/DRAMATIC_SHAPE/tests/gen3_objects_test.lua`. It checks real generated
assets, crown attachment/source cleanup, seating heights and unchanged
walkability. Current results: Emerald 289 checks on 12 maps; FireRed 145 on
6 maps. The crown census covers 80 cells on 33 Emerald maps and 47 cells on
17 FireRed maps; geometry is sampled per tileset/metatile combination, not
every crown placement. All 16 newly pinned planting cells on three Emerald
maps and Petalburg's two border cells are checked. The separate synthetic
`tests/gen3_voxel_test.lua` suite passes 83 checks, including Gen 1/2 parity.

The engine's `tests/drivers/g3_shots.lua` takes paired 2D/3D LÖVE captures;
set `SHOT_MODE=both`, `SHOT_DAY=1`, `SHOT_DIR` and a `SHOT_ONLY` location list.
The release pass compared houses, labs, Centers, benches, couches, plants,
towns, a cave, fences and terrain in both games. These are representative
visual checks, not a complete map-by-map audit.

## Controls

Every key is free-roam only, and each one is also a row on the OPTIONS
menu.

| control | does |
| --- | --- |
| `3`, or the **VOXEL** options row | OFF → 15 → 35 → 50 → 75 → 1ST → 3RD → OFF (camera pitch) |
| `SELECT` (pad / touch) | the same step as `3` — for the machines with no number row |
| `5`, or the **V-GRID** options row | OFF / ON — a one-pixel wireframe on every voxel |
| `6`, or the **T-SHIFT** options row | OFF → 1 → 2 → 3 → OFF (miniature blur) |
| `7`, or the **V-CURVE** options row | OFF → 1 → 2 → 3 — bend the world over the horizon |
| `8`, or the **3D-BTL** options row | ON / OFF — fight on the map instead of on a white field |
| `9`, or the **WATER** options row | FULL / SKY / OFF — waves and reflections on water. **SKY** gives the surface its pixel-tall wave columns and puts the sky, the sun, the moon and the cast in them; **FULL** adds a screen-space ray march that also reflects the shoreline, the trees and the buildings standing behind it |
| the **BACK SPRITES** options row | OFF / ON — keep your own Pokémon on the battle menu, seen from behind in its classic slot, instead of standing it on the map; the foe is still out there. Only on the menu while **3D-BTL** is on, because it decides nothing without it |
| the **AA** options row | OFF / 2X / 4X — smooth the stair-stepped edges of the 3D world by rendering the diorama larger than the window and folding it back down. The ladder is samples per display pixel: 2X is a canvas root-two wider and taller, 4X one exactly twice the size. Every edge in the projected picture softens with the silhouettes — the tileset's own texels are quads in a perspective view and cross the pixel grid at the same arbitrary angles — so the diorama reads smoother rather than sharper. The most expensive row in the mod, so it is OFF by default and **FULL** leaves it alone |
| the **DAYTIME** options row | SYNC / DAY / NIGHT / DUSK / DAWN / CYCLE — what time it is outdoors, on the diorama *and* on the flat 2D world; held at SYNC (and off the menu) while VOXEL is FULL |

## Free-roam cameras (1ST / 3RD)

The last two rungs of the **VOXEL** ladder are experimental, and they are
the same camera: **1ST** stands it in the player's own eyes, **3RD** pulls
it back onto a boom behind their shoulder. Both steer, and on both the grid
walk is replaced by continuous camera-relative movement — push in any
direction and you go there, at any angle, not just along the four compass
lines. Collision, warps, ledges, encounters and scripts all still run
through the engine's own machinery.

| control | does |
| --- | --- |
| mouse | look (the cursor is captured; left click is A, right click is B) |
| right stick | look |
| a touch drag off the overlay's controls | look |
| left stick / touch d-pad / arrow keys | walk, relative to where the camera looks |
| wheel, `Q` / `E`, pinch, or a stick click | **3RD only** — let the boom out and pull it in (`Q` and left stick click out, `E` and right stick click in) |

On an **orbit rung** the same wheel, `Q`/`E` and pinch drive the engine's own
survey zoom. On **1ST** they do nothing at all: the eye is in your head, and
there is no distance to change.

On **3RD** the boom shortens against whatever is behind you, so backing into
a wall walks the camera in to your shoulders rather than through it — squeeze
it all the way in and the view is 1ST until you step clear. The character
turns to face where they are walking, and every sprite in the world — yours,
the NPCs', the figures drawn into the furniture — turns to face the camera
and shows the frame it would look like from where the camera actually
stands, so walking behind someone shows you their back.

## The battle camera

A fight staged on the map (**3D-BTL**, on by default) is shot with a solved
over-the-shoulder rig — and you can steer it.

| control | does |
| --- | --- |
| right stick, a touch drag, or the mouse | swing the shot around the arena (→) and raise the seat (↑) |
| wheel, `Q` / `E`, pinch, or a stick click | the lens (`Q` / left stick click out, `E` / right stick click in) |

Both axes stop where the composition does. Left stops at the shot the rig was
solved for — there is nothing to the left of it. Right ends **side-on**: the
eye square to the arena's axis, both Pokémon at the same distance instead of
one behind the other. Down stops at the rig's own low stance; up is 45° above
it. The lens opens as you swing or climb, by exactly the amount the two
Pokémon spread apart, so they stay framed at every angle. Move animations
follow the pair's position *and* its separation, so a beam still lands on the
Pokémon it was aimed at.

Where you leave the camera is where the next battle opens.

**BACK SPRITES locks it.** That setting pins your own Pokémon to the GB's slot
on the menu while the foe stands out on the map, and no angle holds a
composition that is half frame and half world — so with it on, the shot holds
the one the rig was solved for.

## VR

The **VR** options row (OFF / ON, off by default) drives a PCVR headset
through OpenXR on Windows — SteamVR, Oculus or WMR.

Both free-roam rungs put the headset in the player's *head*: a boom that
seats its wearer three cells behind their own body is a reliable way to make
people ill, so **3RD** in VR is **1ST** in VR. The rung still changes the
walk and the sprites the same way.

### VR controls

Suggested onto Touch, Index and WMR controllers (rebindable in the
runtime's own binding UI); pad, keyboard and mouse all keep working
alongside.

| control | does |
| --- | --- |
| left stick | move — grid-walks the diorama, free-walks 1ST |
| A / B (X / Y on the left hand) | A / B |
| either trigger | START |
| left stick click | step the VOXEL angle ladder (same as the "3" key) |
| right stick up / down | *diorama only* — zoom the model |
| right stick left / right | *1ST only* — snap-turn 45°, or turn smoothly with **SMOOTH TURN** on |
| grip squeeze + raise / lower that hand | *diorama only* — drag the table's height |
| head | *1ST and battles* — look; FreeMove walks where you look |
| left hand | *1ST and battles* — the Pokédex: menus, dialogs and the 2D battle screen on its screen |

## Licenses

This mod is released under the **MIT License** — see [`LICENSE`](LICENSE).

It redistributes one third-party binary:

- **`assets/vr/openxr_loader.dll`** — the Khronos OpenXR loader
  (version 1.0.10.2, x64, unmodified), © The Khronos Group Inc.,
  licensed under the **Apache License 2.0**. The full license text ships
  alongside the DLL at
  [`assets/vr/LICENSE-openxr_loader.txt`](assets/vr/LICENSE-openxr_loader.txt),
  as the license requires; keep the two files together if you
  redistribute this mod. Source:
  [KhronosGroup/OpenXR-SDK](https://github.com/KhronosGroup/OpenXR-SDK).

Everything else in this mod is original to it, except that the voxel
geometry and shape profiles are derived from the tile and sprite data of
the original game, as documented by the
[pret/pokered](https://github.com/pret/pokered) disassembly. No ROM
data, artwork or audio is included; the mod reads the assets the host
game already has.