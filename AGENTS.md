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
	- objects = reusable interactive objects and components
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
	- textures = tileable ground/roof/road textures and images to be used with shaders or other nodes that expect textures
	- ui = application icon and all UI images (interface menus and in-game)
- sounds = all sounds and musics
	- sfx = sound effects
	- bgm = background musics
- videos = all video files
- shaders = 2D shaders files
- resources = Godot resource files `.tres` and their associated scripts, if any (map styles, entity data, item data, and so on)
	- world = world-level authored data resources
- autoloaders = all globals auto-loaded `.gd` scripts (file `entity_registry.gd` ↔ autoload `EntityRegistry`, `game_clock.gd` ↔ `GameClock`, `game_weather.gd` ↔ `GameWeather`; do not rename without updating uids and references)
- data = game data files read at runtime
	- `map.json` = GENERATED map data (never hand-edit)
	- overlays = developer-authored data layered on the map, keyed by OSM ID
- tools = offline tooling outside the game runtime (the OSM Python pipeline). Contains a `.gdignore` so Godot does not import it.

## Architecture Contracts

### Units and coordinates

- Map data is in **meters**, relative to a pinned UTM origin (`meta.origin_utm`, projection EPSG:31982), +X east, +Y south (Y is already flipped for Godot's coordinate system). The origin never moves when the imported area changes, so authored positions stay valid across re-imports.
- `meta.size_m` is the imported extent; `meta.bounds_m` is `[min_x, min_y, max_x, max_y]` of every written coordinate. Frame using `bounds_m`; derive bounds from polygons only for old data that has no `bounds_m`.
- The single source of truth for scale is `Units.PX_PER_METER` in `scripts/units.gd` (`class_name Units`). Never hard-code a scale anywhere else. Convert with `Units.m_to_px()` / `Units.px_to_m()`.
- Gameplay values (speeds, ranges, sizes) are expressed in meters and m/s and converted to pixels at the edge.

### Map data pipeline

- OSM `.geojson` export → `tools/osm_to_godot.py` (Python, shapely + pyproj, projection EPSG:31982) → `res://data/map.json`. The file is generated: regenerate it instead of editing it.
- The converter's pinned origin is `DEFAULT_ORIGIN_UTM = (228400.0, 6712900.0)` and is written to `meta.origin_utm`. `--origin-utm X Y` exists for a deliberate re-origin only; changing it invalidates every authored position and overlay.
- `map.json` schema: top level keys `landuse`, `waterways`, `roads`, `buildings`, `meta`. Every feature has `id` (string, e.g. `"way/123"` or `"relation/456"`), `name` (string, may be empty), `tags` (Dictionary of kept OSM tags), `kind` (string), and `polys`: an Array of polygons, each polygon an Array of rings (`[outer, hole1, ...]`), each ring an Array of `[x, y]` points in meters (rings are not closed). Roads additionally have `width` (m), `oneway` (bool, the `line` already points in the travel direction), `layer` (int), `bridge`, `tunnel` (bool), and `line` (the centerline, Array of `[x, y]`). Waterways additionally have `line`. Buildings additionally have `levels`. `meta` has `crs`, `origin_utm`, `size_m`, `bounds_m`, `attribution`, `counts`.
- Developer-authored data (interiors, entrances, spawn points, building properties) lives in `res://data/overlays/` **keyed by OSM ID**, never by array index or node path, so the map can be re-imported without losing work.
- Map styling is data-driven through `MapStyle` / `TerrainStyle` (`id`, `kind`, `surface`, color/texture/scale). Resolution order is: exact style-id override → kind + surface → kind → category default. Surface keys are normalized to lowercase and stripped before `;` and `:` (for example `concrete:lanes` becomes `concrete`). No colors or textures are hard-coded in loader logic.
- `res://data/overlays/style_overrides.json` maps OSM ID to style ID, for example `{"version": 1, "overrides": {"way/123": "residential_asphalt"}}`. Unknown OSM IDs and unknown style IDs fall back safely and produce one aggregated warning per rebuild, not one per feature.
- Attribution "© OpenStreetMap contributors (ODbL)" must be shown in the credits before any release.

### Rendering layers (draw order, bottom to top)

`Landuse` → `Waterways` → `Roads` → `Buildings` (footprints draw as roofs) → `Decals` → `TerrainState` (reserved for future dynamic overlays) → `Objects` (y-sorted: entities, vehicles, items, vegetation) → `Canopy` (tree tops, roof fade-outs).

- Base ground/road/building polygons are **static art**: never modify them at runtime. Anything dynamic (burn marks, wetness, regrowth, puddles) goes in an overlay layer above.
- Terrain appearance is data-driven through `MapStyle` / `TerrainStyle` (style id + kind + surface → color/texture/scale). No colors or textures hard-coded in loader logic. A new `MapStyle` resource can be seeded from the inspector with its “Reset to defaults” button.
- `scripts/world/map_loader.gd` is the only `@tool` **node** script. The resource scripts it uses in the editor (`resources/map_style.gd`, `resources/terrain_style.gd`) are also `@tool`, because Godot loads non-tool resource scripts as placeholder instances whose methods cannot be called from the preview. `MapLoader` previews the generated layers in the editor, has a “Rebuild map” inspector button, and auto-frames the 2D editor view once when the map bounds are completely off-screen. Generated layer/polygon nodes deliberately have no `owner`, so they are never saved into a scene. Other node scripts (including `world.gd`) stay non-tool and connect `map_loaded` in `_ready()`.
- `scripts/world/map_picker.gd` is a non-tool debug node. The `debug_pick` action picks the top-most polygon under the mouse (or the screen center for the pad), draws a closed white `Line2D` outline, copies the OSM ID to the clipboard, and sends the feature report (category, kind, surface, style, up to eight tags) to the HUD.

### Data versus nodes

- Entity data is a `Resource` (`EntityData`: abilities, full name, birth date, sex, likes, dislikes, ...) referenced by an `Entity` node; the node is only the on-screen presentation. Entities far from the player must be representable as data only (no node).
- Relationships between entities are stored as edges between entity IDs in a central registry (kinship terms: consanguinity, affinity, adoption; plus social states such as stranger, acquaintance, friend, enemy, couple). Resources never hold direct references to each other (avoids cyclic references).
- The player is an `Entity` driven by a `PlayerController`; NPCs are the same `Entity` driven by an AI controller. Same body, different controller.
- Interactive world objects (doors, windows, vehicles, containers, vegetation) use composition: an `Interactable` component exposing `interact(actor)`; behavior-specific components are added as needed.
- Items: `ItemData` (static definition, Resource) versus an item instance (runtime state: stack count, durability, owner/location). A dropped item is a node carrying an instance.
- Buildings block entities (static collision). They are entered only through entrances (door objects) that switch to an interior scene.
- "What terrain is at this point?" is answered by `TerrainQuery` (`TerrainQuery.active.sample(position_m)` → a `TerrainSample` with category, kind, surface, style id, and OSM id; `TerrainSample.default_sample()` when nothing matches; coordinates in **meters**). The index is a 32 m uniform grid built once per map load, at runtime only (`active` is `null` before `map_loaded`), outer rings only (holes ignored, exactly like drawing and collisions), priority buildings → roads → waterways → landuse with later features winning — the same top-most polygon `MapPicker` shows. `TerrainRules` maps a sample's surface, then kind, to a walking-speed factor that `Entity` re-samples at most every 0.25 s or per 1 m moved. Callers go through one method, so the implementation can later move from polygon tests to a raster grid without touching them.
- Procedural placement (e.g. vegetation scatter) must be deterministic: seed from the OSM ID. Persist only the differences from the generated state, keyed by OSM ID plus index.

### World state

- `GameClock` (autoload) is the single source of truth for in-game time: `total_seconds` (float seconds since 1970-01-01 00:00) is the only time state; year/month/day/hour/minute, weekday, sunrise/sunset, and the `Period` are all derived through `GameCalendar` (proleptic Gregorian, weekday 0 = Monday; the sunrise/sunset model is for Santa Maria, UTC−3, no DST). The six `Period`s (NIGHT, DAWN, MORNING, AFTERNOON, DUSK, EVENING) are relative to today's sunrise/sunset (±1 h twilight windows) and always partition the whole day.
- `GameWeather` (autoload) is a pure function of `weather_seed` and clock time: `GameWeather.compute(seed, total_seconds)` holds no accumulated state, so clock jumps and future save/load reproduce identical weather. It recomputes on `GameClock.minute_changed` and emits `weather_changed` only when the condition changes or the temperature moves at least 0.5 °C.
- Day/night is the `DayNight` `CanvasModulate` in `world.tscn`: `smoothstep`-blended night → twilight → day around sunrise/sunset, plus an overcast blend weighted by daylight from `cloud_cover`/`rain_intensity`. It tints the world only; the HUD is a `CanvasLayer` and stays untinted. This is the only weather visual for now — no rain particles, no wetness.
- Systems react to clock and weather **signals** (`minute_changed`, `hour_changed`, `day_changed`, `period_changed`, `time_scale_changed`, `paused_changed`, `weather_changed`) instead of polling every frame. `GameClock` and `GameWeather` each expose `get_state()` / `load_state()` as the future save hooks: validation happens up front, and unknown or invalid input warns and changes nothing. No file I/O exists yet.
- The HUD's debug time panel (pause, time scale, +1 h) exists **only in debug builds** (`OS.is_debug_build()`) and its buttons are mouse/touch only (`FOCUS_NONE`) — the one deliberate exception to full gamepad support.

### Entities

- `EntityData` is a `Resource` holding identity and D&D 5.5e ability scores; the `Entity` node is only presentation. The player and debug NPCs share the same `Entity` body and swap behavior through an `EntityController` (`PlayerController` or `WanderController`).
- `EntityRegistry` is the `autoloaders/entity_registry.gd` autoload. It assigns IDs of the form `e_000001`, stores `EntityData` by ID, and stores relationship edges as directed ID pairs. Relationship resources never hold references to other resources.
- Entities collide with `PhysicsLayers.WORLD` only for now. They do not block each other. Buildings and `water` landuse polygons block entities; waterways (streams) do not block. Collision bodies are generated at runtime only, never saved into the editor scene.

### Physics layers (named in project settings)

1 `world` (buildings, water, static obstacles) · 2 `entities` · 3 `vehicles` · 4 `items` · 5 `interactables`. The bit masks are `PhysicsLayers.WORLD = 1`, `ENTITIES = 2`, `VEHICLES = 4`, `ITEMS = 8`, `INTERACTABLES = 16`; collision layer/mask assignment uses those constants.

### Input actions

Canonical actions, persisted in `project.godot`, one keyboard key + one pad button each, left stick implicitly bound to movement: `move_up` (Up, W / D-pad up) · `move_down` (Down, S / D-pad down) · `move_left` (Left, A / D-pad left) · `move_right` (Right, D / D-pad right) · `run` (Shift / pad button west) · `interact` (E / pad button south) · `zoom_in` (= / pad right shoulder) · `zoom_out` (- / pad left shoulder) · `menu` (Esc / pad start) · `debug_pick` (right mouse button / pad right-stick press) · `debug_camera` (F1 / pad back). Add actions here when a phase introduces them. Gameplay code only reads actions, never raw keys.

### Performance

- Target 60 fps on the laptop and a stable frame rate on the low-end phone (see Testing). Keep node counts low: prefer one node per feature at most, and plan for chunked streaming of the map when the imported area grows. Do not build per-frame work that scales with the total number of map features.

### Interaction and interiors

- `Interactable` is an `Area2D` on `PhysicsLayers.INTERACTABLES` with `monitoring = false`. `PlayerInteraction` is an `Area2D` child of the player on layer 0 with mask `PhysicsLayers.INTERACTABLES`, `monitorable = false`; it polls `Input.is_action_just_pressed("interact")` each physics frame while overlaps exist, picks the closest target in front with a small preference, ignores input while the entity is `locked`, and emits `message` when the target rejects.
- `Entity` has `locked: bool` with `set_locked(value)` — while locked velocity is zero and the controller is not read.
- Entrances are data in `res://data/overlays/entrances.json` keyed by building OSM ID (`{"version":1,"entrances":[]}`), `position` approximated and snapped to the building footprint edge at load time by `BuildingGeometry`. `EntranceData.is_open(weekday,hour)` uses Monday = 0: entries `{"days":[...],"from":float,"to":float}`; `to < from` wraps past midnight, the listed day is the interval start (and yesterday's wrapped intervals are checked). Unavailable doors show `Closed · opens HH:MM` with the next opening time. Availability updates on `GameClock.minute_changed`.
- Interiors live on the same canvas, far away at `InteriorManager.INTERIOR_ORIGIN_M = Vector2(-10000.0, 0.0)`. The exterior keeps simulating. One interior loads at a time; the same `Entity` is repositioned. Entering: lock → fade out (ScreenFader) → instantiate `res://scenes/interiors/<interior_id>.tscn` if present and has an `Interior` root, else a `PlaceholderInterior` sized from the building footprint (clamped 5×4..14×10 m) with label = entrance label or building ID → place at the interior origin, move the player to `EntryPoint`, set `FollowCamera` limits from `interior.get_bounds_m()` and snap, disable `DayNight.enabled` (restored on exit). Exiting reverses it: free the interior, restore limits, place the player 1 m in front of the door outside, snap the camera.
- Authored interiors extend `Interior` with required `EntryPoint` (`Marker2D`) and `Objects` (`Node2D`, y_sort) children, optional `bounds_m` (meters, local to the interior origin) used for camera limits; `InteriorExit` inside asks the ancestor interior to exit.
- Debug builds with an empty `entrances.json` auto-spawn up to 4 doors on buildings nearest to the player spawn (snapped road-facing, placeholder interiors).

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
- Never reference `EditorInterface` directly from a script that is shipped in a game: editor classes are stripped from export templates and the script then fails to load. Access it only under `Engine.is_editor_hint()` through `Engine.get_singleton(&"EditorInterface")`.
- Regenerate the map with `uv run --python 3.13 --with shapely --with pyproj --with numpy python tools/osm_to_godot.py data/export.geojson data/map.json` when the system Python lacks the geo dependencies.

## Commit Convention

When there are changes to commit, AI agents should suggest an one-line commit message at the end of their response following conventional commit format: `type(scope): description`. Use types like `feat`, `fix`, `refactor`, `docs`, `chore` and keep descriptions concise but descriptive — focus on the "why" rather than the "what". This message must be in own line to facilitate copying.
