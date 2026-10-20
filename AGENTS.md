# AGENTS.md

This is a Godot 4.7.2 project: a 2D top-down, open-world, real-time RPG set in the real city of Santa Maria (Rio Grande do Sul, Brazil). World geometry (roads, buildings, vegetation areas, water) comes from OpenStreetMap (OSM) data processed offline. Everything else (interiors, objects, items, entities, art) is authored by the human developer.

Inspiration: GTA (1997) for free-roaming top-down play, and Rome: Pathway to Power (1992) for a living world where every entity has its own beliefs, desires, and intentions (agenda) that adapt to time of day, weekday, and surrounding events. Underlying world rules follow D&D 5.5e (abilities: Strength, Dexterity, Constitution, Intelligence, Wisdom, Charisma).

Deep simulation (fire spread, terrain charring, regrowth, weather effects on terrain) is a **future** goal. Do not implement it unless a phase prompt asks for it, but do not make choices that would block it (see Architecture Contracts).

## Requirements

- Godot 4.7.2.
- GDScript.
- Statically typed (every function signature fully annotated; no untyped vars in new code; typed arrays and typed lambdas/Callables where practical).
- Fluid layout for all UI, must look good in desktop, mobile, and web.
- Keyboard, game controller, mouse, and touch support.
- Use snake case and screaming snake case for constants.
- All assets (images, musics, fonts, textures, and so on) will be provided by the human developer. Never fetch or generate binary assets. Code must work with missing art (fall back to flat colors / placeholder shapes).
- User-facing strings are plain English literals for now. Do not add i18n infrastructure.
- No secrets in the repo (no committed keys, tokens, or credentials).
- No commented-out dead code (git keeps history).

## Folder Structure

Folders relative to the project root. Sub-folders are indicated by the tab level. The string after the dash is the folder name (all lowercase). What comes after the equals sign is the explanation of what the folder contains.

- addons = third-party addons and plugins
- scenes = scene files (per-area subfolders, e.g. `world/`, `entities/`, `objects/`, `interiors/`, `ui/`)
- scripts = script files with the exception of the globals auto-loaded ones (per-area subfolders mirroring `scenes`)
- assets = different assets
	- fonts = TrueType Font files
	- images = all images
		- actors = sprites, sprite sheets, and any other image file for the actors
		- items = game items images (inventory, in-game, etc)
		- backgrounds = game backgrounds
		- tiles = individual tiles images
		- tilesets = tile sheets
		- textures = tileable ground/roof/road textures and images to be used with shaders or other nodes that expect textures
		- ui = application icon and all UI images (interface menus and in-game)
	- sounds = all sounds and musics
		- sfx = sound effects
		- bgm = background musics
	- videos = all video files
- shaders = 2D shaders files
- resources = Godot resource files `.tres` and their associated scripts, if any (map styles, entity data, item data, and so on)
- autoloaders = all globals auto-loaded `.gd` scripts (file `world.gd` ↔ autoload `World`; do not rename without updating uids and references)
- data = game data files read at runtime
	- `map.json` = GENERATED map data (never hand-edit)
	- overlays = developer-authored data layered on the map, keyed by OSM ID
- tools = offline tooling outside the game runtime (the OSM Python pipeline). Contains a `.gdignore` so Godot does not import it.

## Architecture Contracts

### Units and coordinates

- Map data is in **meters**, origin at the center of the imported area, +X east, +Y south (Y is already flipped for Godot's coordinate system).
- The single source of truth for scale is `Units.PX_PER_METER` in `scripts/units.gd` (`class_name Units`). Never hard-code a scale anywhere else. Convert with `Units.m_to_px()` / `Units.px_to_m()`.
- Gameplay values (speeds, ranges, sizes) are expressed in meters and m/s and converted to pixels at the edge.

### Map data pipeline

- OSM `.geojson` export → `tools/osm_to_godot.py` (Python, shapely + pyproj, projection EPSG:31982) → `res://data/map.json`. The file is generated: regenerate it instead of editing it.
- `map.json` schema: top level keys `landuse`, `waterways`, `roads`, `buildings`, `meta`. Every feature has `id` (string, e.g. `"way/123"` or `"relation/456"`), `name` (string, may be empty), `tags` (Dictionary of kept OSM tags), `kind` (string), and `polys`: an Array of polygons, each polygon an Array of rings (`[outer, hole1, ...]`), each ring an Array of `[x, y]` points in meters (rings are not closed). Roads additionally have `width` (m), `oneway` (bool, the `line` already points in the travel direction), `layer` (int), `bridge`, `tunnel` (bool), and `line` (the centerline, Array of `[x, y]`). Waterways additionally have `line`. Buildings additionally have `levels`. `meta` has `crs`, `origin_utm`, `size_m`, `attribution`, `counts`.
- Developer-authored data (interiors, entrances, spawn points, building properties) lives in `res://data/overlays/` **keyed by OSM ID**, never by array index or node path, so the map can be re-imported without losing work.
- Attribution "© OpenStreetMap contributors (ODbL)" must be shown in the credits before any release.

### Rendering layers (draw order, bottom to top)

`Landuse` → `Waterways` → `Roads` → `Buildings` (footprints draw as roofs) → `Decals` → `TerrainState` (reserved for future dynamic overlays) → `Objects` (y-sorted: entities, vehicles, items, vegetation) → `Canopy` (tree tops, roof fade-outs).

- Base ground/road/building polygons are **static art**: never modify them at runtime. Anything dynamic (burn marks, wetness, regrowth, puddles) goes in an overlay layer above.
- Terrain appearance is data-driven through the `MapStyle` resource (kind → color/texture/scale). No colors or textures hard-coded in loader logic.

### Data versus nodes

- Entity data is a `Resource` (`EntityData`: abilities, full name, birth date, sex, likes, dislikes, ...) referenced by an `Entity` node; the node is only the on-screen presentation. Entities far from the player must be representable as data only (no node).
- Relationships between entities are stored as edges between entity IDs in a central registry (kinship terms: consanguinity, affinity, adoption; plus social states such as stranger, acquaintance, friend, enemy, couple). Resources never hold direct references to each other (avoids cyclic references).
- The player is an `Entity` driven by a `PlayerController`; NPCs are the same `Entity` driven by an AI controller. Same body, different controller.
- Interactive world objects (doors, windows, vehicles, containers, vegetation) use composition: an `Interactable` component exposing `interact(actor)`; behavior-specific components are added as needed.
- Items: `ItemData` (static definition, Resource) versus an item instance (runtime state: stack count, durability, owner/location). A dropped item is a node carrying an instance.
- Buildings block entities (static collision). They are entered only through entrances (door objects) that switch to an interior scene.
- "What terrain is at this point?" is answered by one function (`TerrainQuery.kind_at(position)`), so the implementation can later move from polygon tests to a raster grid without touching callers.
- Procedural placement (e.g. vegetation scatter) must be deterministic: seed from the OSM ID. Persist only the differences from the generated state, keyed by OSM ID plus index.

### Physics layers (named in project settings)

1 `world` (buildings, water, static obstacles) · 2 `entities` · 3 `vehicles` · 4 `items` · 5 `interactables`.

### Input actions

Canonical actions, persisted in `project.godot`, one keyboard key + one pad button each, left stick implicitly bound to movement: `move_up` (Up, W / D-pad up) · `move_down` (Down, S / D-pad down) · `move_left` (Left, A / D-pad left) · `move_right` (Right, D / D-pad right) · `run` (Shift / pad button west) · `interact` (E / pad button south) · `zoom_in` (= / pad right shoulder) · `zoom_out` (- / pad left shoulder) · `menu` (Esc / pad start). Add actions here when a phase introduces them. Gameplay code only reads actions, never raw keys.

### Performance

- Target 60 fps on the laptop and a stable frame rate on the low-end phone (see Testing). Keep node counts low: prefer one node per feature at most, and plan for chunked streaming of the map when the imported area grows. Do not build per-frame work that scales with the total number of map features.

## Testing

All testing will be done manually by human after every iteration, so don't run the game.
The testing devices are:

1. Samsung Odyssey laptop running Omarchy Quattro in 1920 x 1080 @ 60 Hz.
2. Samsung Galaxy A03 phone running Android in 360 x 800 (portrait mode).

Agents must still rely on script parse-validation diagnostics (never ship a script with errors). Each phase prompt lists its own manual checklist.

Before shipping a build: remove any `_mcp_game_helper` dev autoload and its editor plugin entry if present.

## Agent Workflow Notes (learned the hard way — keep current)

- While the agent writes files, keep those files **closed** in the Godot script editor: an open buffer can silently revert external writes on focus/undo/save.
- After every script write, **read the file back from disk** — never trust the write receipt alone.
- `node_set_property` cannot coerce strings to bool/int — set non-string properties in GDScript instead.
- `input_map` calls must be **sequential** (parallel bursts wedge the backend lock); `project_manage settings_set` accepts invalid keys without complaint (verify setting names against engine docs).
- Godot 4 API differs from Godot 3 memory (e.g. `ScrollContainer.horizontal_scroll_mode`). When unsure about a property or method, check the Godot 4.7 docs instead of guessing.
- Editor-log ghosts: the log buffer re-emits stale diagnostics on scans — confirm errors against current file contents (grep) before treating them as live.

## Commit Convention

When there are changes to commit, AI agents should suggest an one-line commit message at the end of their response following conventional commit format: `type(scope): description`. Use types like `feat`, `fix`, `refactor`, `docs`, `chore` and keep descriptions concise but descriptive — focus on the "why" rather than the "what". This message must be in own line to facilitate copying.
