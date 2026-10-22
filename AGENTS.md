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
	- vegetation = procedural vegetation generation, batched drawing, and streaming manager
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
	- objects = shared physical/interaction properties (`ObjectProperties`) used by vegetation, items, and vehicles
	- vegetation = vegetation species, terrain rules, and street-tree rules
	- vehicles = vehicle definitions (`VehicleData`, `WheelSpec`, `VehicleTerrainProfile` scripts) and their `.tres` data
	- world = world-level authored data resources
- autoloaders = all globals auto-loaded `.gd` scripts (file `entity_registry.gd` ↔ autoload `EntityRegistry`, `game_clock.gd` ↔ `GameClock`, `game_weather.gd` ↔ `GameWeather`; do not rename without updating uids and references)
- data = game data files read at runtime
	- `map.json` = GENERATED map data (never hand-edit)
	- overlays = developer-authored data layered on the map, keyed by OSM ID (`entrances.json`, `spawns.json`, `style_overrides.json`, `vehicles.json`)
- tools = offline tooling outside the game runtime (the OSM Python pipeline, validation shell scripts). Contains a `.gdignore` so Godot does not import it.
- tests = headless validation scenes and scripts (compile check, smoke tests). Never part of the game runtime; exclude from release exports.

## Architecture Contracts

### Units and coordinates

- Map data is in **meters**, relative to a pinned UTM origin (`meta.origin_utm`, projection EPSG:31982), +X east, +Y south (Y is already flipped for Godot's coordinate system). The origin never moves when the imported area changes, so authored positions stay valid across re-imports.
- `meta.size_m` is the imported extent; `meta.bounds_m` is `[min_x, min_y, max_x, max_y]` of every written coordinate. Frame using `bounds_m`; derive bounds from polygons only for old data that has no `bounds_m`.
- The single source of truth for scale is `Units.PX_PER_METER` in `scripts/units.gd` (`class_name Units`). Never hard-code a scale anywhere else. Convert with `Units.m_to_px()` / `Units.px_to_m()`.
- Gameplay values (speeds, ranges, sizes) are expressed in meters and m/s and converted to pixels at the edge.

### Map data pipeline

- The current source export is `data/export_0002.geojson` (about 55 MB, gitignored and kept local). `make map` converts it with `tools/osm_to_godot.py` (Python, shapely + pyproj, projection EPSG:31982) into `res://data/map.json` (about 18 MB, tracked as runtime data). Pass `MAP_SOURCE=path/to/other.geojson` to regenerate from a different export. Raw `.geojson` exports are not committed.
- The imported city is about 19.5 × 19.1 km with roughly 68k features (56k buildings). The pinned origin keeps every authored coordinate, OSM-ID-keyed overlay, and entrance valid when the export grows; the original playtest area is contained in the full-city bounds.
- The converter's pinned origin is `DEFAULT_ORIGIN_UTM = (228400.0, 6712900.0)` and is written to `meta.origin_utm`. `--origin-utm X Y` exists for a deliberate re-origin only; changing it invalidates every authored position and overlay.
- `map.json` schema: top level keys `landuse`, `waterways`, `roads`, `buildings`, `meta`. Every feature has `id` (string, e.g. `"way/123"` or `"relation/456"`), `name` (string, may be empty), `tags` (Dictionary of kept OSM tags), `kind` (string), and `polys`: an Array of polygons, each polygon an Array of rings (`[outer, hole1, ...]`), each ring an Array of `[x, y]` points in meters (rings are not closed). Roads additionally have `width` (m), `oneway` (bool, the `line` already points in the travel direction), `layer` (int), `bridge`, `tunnel` (bool), and `line` (the centerline, Array of `[x, y]`). Waterways additionally have `line`. Buildings additionally have `levels`. `meta` has `crs`, `origin_utm`, `size_m`, `bounds_m`, `attribution`, `counts`.
- Developer-authored data (interiors, entrances, spawn points, building properties) lives in `res://data/overlays/` **keyed by OSM ID**, never by array index or node path, so the map can be re-imported without losing work.
- Map styling is data-driven through `MapStyle` / `TerrainStyle` (`id`, `kind`, `surface`, color/texture/scale). Resolution order is: exact style-id override → kind + surface → kind → category default. Surface keys are normalized to lowercase and stripped before `;` and `:` (for example `concrete:lanes` becomes `concrete`). Road `*_link` kinds fall back to their base kind (`trunk_link` → `trunk`). No colors or textures are hard-coded in loader logic.
- “Add missing styles” on a `MapStyle` merges the built-in palette into an authored resource without touching existing entries or values; “Reset to defaults” is destructive. Use the merge when the map import introduces new kinds or surfaces.
- `TerrainSample.WATER_LANDUSE_KINDS` (`water`, `reservoir`, `swimming_pool`, `basin`) is the single list for water-like landuse. Those polygons get water styling, block entity movement, and block vegetation.
- `res://data/overlays/style_overrides.json` maps OSM ID to style ID, for example `{"version": 1, "overrides": {"way/123": "residential_asphalt"}}`. Unknown OSM IDs and unknown style IDs fall back safely and produce one aggregated warning per rebuild, not one per feature.
- Attribution "© OpenStreetMap contributors (ODbL)" must be shown in the credits before any release.

### Rendering layers (draw order, bottom to top)

`Landuse` → `Waterways` → `Roads` → `Buildings` (footprints draw as roofs) → `Decals` (vegetation ground batches, shadows) → `TerrainState` (reserved for future dynamic overlays) → `Objects` (y-sorted: entities, vehicles, items) → `Canopy` (vegetation tree tops, roof fade-outs).

- Base ground/road/building polygons are **static art**: never modify them at runtime. Anything dynamic (burn marks, wetness, regrowth, puddles) goes in an overlay layer above.
- Terrain appearance is data-driven through `MapStyle` / `TerrainStyle` (style id + kind + surface → color/texture/scale). No colors or textures hard-coded in loader logic. A new `MapStyle` resource can be seeded from the inspector with “Reset to defaults” (destructive); “Add missing styles” appends only the palette entries the resource does not have yet.
- `scripts/world/map_loader.gd` is the only `@tool` **node** script. The resource scripts it uses in the editor (`resources/map_style.gd`, `resources/terrain_style.gd`) are also `@tool`, because Godot loads non-tool resource scripts as placeholder instances whose methods cannot be called from the preview. `MapLoader` previews the full generated map in the editor by default, has “Rebuild map” and “Frame full map” inspector buttons, and opens the 2D view on `editor_initial_view_m` once per editor session instead of fitting the whole city. `editor_preview = false` skips generation entirely for a fast, empty editor. Generated layer/polygon nodes deliberately have no `owner`, so they are never saved into a scene. Other node scripts (including `world.gd`) stay non-tool and connect `map_loaded` in `_ready()`.
- `scripts/world/map_picker.gd` is a non-tool debug node. The `debug_pick` action picks the top-most polygon under the mouse (or the screen center for the pad), draws a closed white `Line2D` outline, copies the OSM ID to the clipboard, and sends the feature report (category, kind, surface, style, up to eight tags) to the HUD.

### Data versus nodes

- Entity data is a `Resource` (`EntityData`: abilities, full name, birth date, sex, likes, dislikes, ...) referenced by an `Entity` node; the node is only the on-screen presentation. Entities far from the player must be representable as data only (no node).
- Relationships between entities are stored as edges between entity IDs in a central registry (kinship terms: consanguinity, affinity, adoption; plus social states such as stranger, acquaintance, friend, enemy, couple). Resources never hold direct references to each other (avoids cyclic references).
- The player is an `Entity` driven by a `PlayerController`; NPCs are the same `Entity` driven by an AI controller. Same body, different controller.
- Interactive world objects (doors, windows, vehicles, containers, vegetation) use composition: an `Interactable` component exposing `interact(actor)`; behavior-specific components are added as needed.
- Items: `ItemData` (static definition, Resource) versus an item instance (runtime state: stack count, durability, owner/location). A dropped item is a node carrying an instance.
- `ObjectProperties` is the shared physical/interaction description for world objects (vegetation, items, vehicles): mass, friction, flammability (ignition temperature and energy), breakability (force and energy), and lifespan/decay. Definitions live on the data resource; per-instance state does not. No simulation consumes these fields yet.
- Buildings block entities (static collision). They are entered only through entrances (door objects) that switch to an interior scene.
- "What terrain is at this point?" is answered by `TerrainQuery` (`TerrainQuery.active.sample(position_m)` → a `TerrainSample` with category, kind, surface, style id, and OSM id; `TerrainSample.default_sample()` when nothing matches; coordinates in **meters**). The index is a 32 m uniform grid built once per map load, at runtime only (`active` is `null` before `map_loaded`), outer rings only (holes ignored, exactly like drawing and collisions), priority buildings → roads → waterways → landuse with later features winning — the same top-most polygon `MapPicker` shows. `TerrainRules` maps a sample's surface, then kind, to a walking-speed factor that `Entity` re-samples at most every 0.25 s or per 1 m moved. Callers go through one method, so the implementation can later move from polygon tests to a raster grid without touching them.
- Procedural vegetation placement is deterministic (details under Vegetation). Any other procedural placement must also be deterministic: seed from the OSM ID. Persist only the differences from the generated state, keyed by OSM ID plus index.

### Vegetation

- `VegetationGenerator` places plants on a **global 4 m cell grid**, 1,024 cells per **128 m chunk**. Each cell `(cx, cy)` is mixed with `vegetation_seed` through a stable integer seed, jittered inside the cell, sampled with `TerrainQuery`, matched through `VegetationRules` by category + kind (+ surface), then accepted by density and clearance. Clearance samples four cardinal points and requires the same landuse category, so plants never spill onto roads, building footprints, or streams.
- `VegetationRules` holds `VegetationSpecies` definitions (trees, bushes, rock/boulders), per-terrain density rules, and per-road street-tree rules. Species colors and optional textures are placeholders until real art exists; trees batch a trunk/shadow in `Decals` and a canopy in `Canopy`, bushes and rocks draw only in `Decals`. Street trees are seeded per road ID, offset from the road edge, spaced along the centerline, and keyed `"s:<road_osm_id>:<index>"`. `prepare_street_tree_index()` indexes street-tree roads by 128 m chunk at startup (~31 ms for the full city); each road's trees are generated lazily the first time a visible chunk needs them, so the ~50k street trees no longer block startup.
- Vegetation is **runtime-only**: no editor preview, no saved generated nodes, and no per-plant nodes. `VegetationManager` streams the chunks covering the camera view (plus margin and a 30 m focus area), generates at most one chunk per frame from a distance-sorted queue, caches up to 64 chunks, and frees views that leave the area. Pooled collisions (48 `StaticBody2D` on `PhysicsLayers.WORLD`) and inspections (6 `Interactable`s) follow the focus entity within 30 m / 3 m. NPCs outside the focus radius can walk through plants.
- The same `Entity` remains the focus on foot. The manager skips and clears vegetation when the camera or focus is outside `meta.bounds_m`; interiors are outside it, so the interior canvas never receives vegetation. `World._set_focus_entity()` is the one place the camera target and vegetation anchor are swapped; driving passes the vehicle instead (the manager accepts any `Node2D`).
- Per-instance age lives in `VegetationChunkData.ages_years`, sampled from `ObjectProperties.max_age_years`. Stable keys are `"cx:cy"` for terrain plants and `"s:<road_osm_id>:<index>"` for street trees; only differences from generated state should ever be saved. Inspection shows name, radius, description, mass, ignition, breaking force, and age.

### World state

- `GameClock` (autoload) is the single source of truth for in-game time: `total_seconds` (float seconds since 1970-01-01 00:00) is the only time state; year/month/day/hour/minute, weekday, sunrise/sunset, and the `Period` are all derived through `GameCalendar` (proleptic Gregorian, weekday 0 = Monday; the sunrise/sunset model is for Santa Maria, UTC−3, no DST). The six `Period`s (NIGHT, DAWN, MORNING, AFTERNOON, DUSK, EVENING) are relative to today's sunrise/sunset (±1 h twilight windows) and always partition the whole day.
- `GameWeather` (autoload) is a pure function of `weather_seed` and clock time: `GameWeather.compute(seed, total_seconds)` holds no accumulated state, so clock jumps and future save/load reproduce identical weather. It recomputes on `GameClock.minute_changed` and emits `weather_changed` only when the condition changes or the temperature moves at least 0.5 °C.
- Day/night is the `DayNight` `CanvasModulate` in `world.tscn`: `smoothstep`-blended night → twilight → day around sunrise/sunset, plus an overcast blend weighted by daylight from `cloud_cover`/`rain_intensity`. It tints the world only; the HUD is a `CanvasLayer` and stays untinted. This is the only weather visual for now — no rain particles, no wetness.
- Systems react to clock and weather **signals** (`minute_changed`, `hour_changed`, `day_changed`, `period_changed`, `time_scale_changed`, `paused_changed`, `weather_changed`) instead of polling every frame. `GameClock` and `GameWeather` each expose `get_state()` / `load_state()` as the future save hooks: validation happens up front, and unknown or invalid input warns and changes nothing. No file I/O exists yet.
- The HUD's debug time panel (pause, time scale, +1 h) exists **only in debug builds** (`OS.is_debug_build()`) and its buttons are mouse/touch only (`FOCUS_NONE`) — the one deliberate exception to full gamepad support.

### Entities

- `EntityData` is a `Resource` holding identity and D&D 5.5e ability scores; the `Entity` node is only presentation. The player and debug NPCs share the same `Entity` body and swap behavior through an `EntityController` (`PlayerController` or `WanderController`).
- Movement is mode-selectable on the controller via `movement_mode` (`OMNI` = move in the stick/key direction, today’s behavior; `RELATIVE` = up/down throttle along facing, left/right turn in place). The option is set on `PlayerController` in `scenes/entities/player.tscn` before launch (defaults to `OMNI`). `get_move_intent()` provides axis intent for RELATIVE; both modes reuse the same input actions so keyboard, gamepad, and touch work. `Entity.facing` remains the heading (used by `PlayerInteraction`). NPCs default to `OMNI`.
- `EntityRegistry` is the `autoloaders/entity_registry.gd` autoload. It assigns IDs of the form `e_000001`, stores `EntityData` by ID, and stores relationship edges as directed ID pairs. Relationship resources never hold references to other resources.
- Entities collide with `PhysicsLayers.WORLD` and `PhysicsLayers.VEHICLES` (parked cars are solid), and do not block each other. Buildings and water-like landuse polygons (`TerrainSample.WATER_LANDUSE_KINDS`) block entities; waterways (streams) do not block. Collision bodies are generated at runtime only, never saved into the editor scene.
- `set_riding(true)` is the shared "inside a vehicle" body state: hidden, physics disabled, collision layer 0. Only the vehicle that seated the entity calls it, and `exit()` restores the defaults.

### Vehicles

- `VehicleData` (`resources/vehicles/*.tres`) is the static definition: identity, body size, sprite frames, durability, handling, wheel layout, seats, storage, and a composed `ObjectProperties`. Runtime state (health, per-wheel `WheelState`, occupants, contents) lives on the `Vehicle` node, never in the `.tres`.
- `Vehicle` is a `CharacterBody2D` with an arcade bicycle model (yaw from wheelbase + steer, lateral slip damped by grip). It mirrors the entity split: `VehicleController` returns throttle/steer/handbrake intent, and `PlayerVehicleController` reads the shared movement actions. A vehicle only reads its controller while occupied, so parked cars ignore input; NPC controllers are future work.
- Handling is authored in metres and m/s (`max_speed_mps`, `acceleration_mps2`, `brake_mps2`, `max_steer_deg`, `wheelbase_m`, `lateral_grip`, tyre grip) and converted once at the edge. Art is scaled from `length_m` and `sprite_length_px`; north-facing sprites get a fixed +90° child rotation, so the vehicle node's rotation is always the heading.
- Terrain handling uses `VehicleTerrainProfile` (surface, then kind → speed and grip multipliers): asphalt 1.0, grass ~0.6, gravel ~0.7, and so on. Water-like landuse blocks vehicles, with a slow/loose fallback if one ever gets there.
- Wheels come from `wheel_count` (2, 4, or 6) or an authored `WheelSpec` list. Each runtime `WheelState` has `present`, `pressure_kpa`, and `tread`; a missing wheel gives zero traction, and flat or worn tires reduce grip and top speed. No wheel visuals yet.
- Vehicles collide with `WORLD`, `VEHICLES`, and `ENTITIES`, so they are solid to pedestrians and to each other. Entering reuses the normal `Interactable` component; exiting is polled by `World` from the `interact` action (keyboard, gamepad, and touch) with a 300 ms entry cooldown. The exit spot is searched left, right, rear, then front and validated against collision and water.
- Impacts above `impact_damage_threshold_mps` reduce `health` using the body's real velocity component along the collision normal, scaled by mass; the speed readout also uses the real velocity, so a vehicle held against an obstacle reports 0 km/h and stops taking damage. `damaged` and `destroyed` signals exist, but visual damage and fire are not implemented. `get_state()` / `load_state()` are save hooks for position, heading, health, lights, and tire condition.
- Placement is `data/overlays/vehicles.json` (`{"version":1,"vehicles":[{"id","data","position":[x,y],"heading_deg","lights"}]}`), keyed by stable IDs and spawned after the map and before NPCs. Debug builds with an empty list place two cars on the nearest road; `V` (pad east) spawns the inspector-assigned `debug_vehicle_data` (default `car.tres`) in front of the player. Blocked spawn points are skipped with an aggregated warning.
- Camera: `FollowCamera` has `MANUAL` (wheel and zoom actions) and `AUTO` (speed-based zoom and look-ahead). Driving forces `AUTO` and restores the previous mode and manual zoom on exit. The follow update and Camera2D smoothing run on the physics clock (`process_callback = PHYSICS`) so the camera samples bodies on the same tick they move; idle-time smoothing jitters moving sprites when the frame rate differs from physics. F1 keeps the free `DebugCamera`; debug builds cycle modes on foot with `C` (pad north). Pan is never player-controlled in `AUTO`. The HUD replaces the player line with the vehicle name, speed, health, tire count, and terrain while driving.
- Storage is capacity metadata plus `contents` and `store_item()` / `take_item()`; the item system does not exist yet. Multiple occupants are supported by the seat list, but only the driver is wired to input.

### Physics layers (named in project settings)

1 `world` (buildings, water, static obstacles) · 2 `entities` · 3 `vehicles` · 4 `items` · 5 `interactables`. The bit masks are `PhysicsLayers.WORLD = 1`, `ENTITIES = 2`, `VEHICLES = 4`, `ITEMS = 8`, `INTERACTABLES = 16`; collision layer/mask assignment uses those constants.

### Input actions

Canonical actions, persisted in `project.godot`, one keyboard key + one pad button each, left stick implicitly bound to movement: `move_up` (Up, W / D-pad up) · `move_down` (Down, S / D-pad down) · `move_left` (Left, A / D-pad left) · `move_right` (Right, D / D-pad right) · `run` (Shift / pad button west) · `interact` (E / pad button south) · `zoom_in` (= / pad right shoulder) · `zoom_out` (- / pad left shoulder) · `menu` (Esc / pad start) · `debug_pick` (right mouse button / pad right-stick press) · `debug_camera` (F1 / pad back) · `camera_mode` (C / pad north, debug builds only) · `debug_spawn_vehicle` (V / pad east, debug builds only). Add actions here when a phase introduces them. Gameplay code only reads actions, never raw keys.

### Performance

- Target 60 fps on the laptop and a stable frame rate on the low-end phone (see Testing). Keep node counts low: prefer one node per feature at most, and plan for chunked streaming of the map when the imported area grows. Do not build per-frame work that scales with the total number of map features.
- The full-city import currently loads monolithically: roughly 5.5–6 s and ~125k nodes at runtime on the desktop, with collision and terrain indexing included. Street-tree indexing adds ~31 ms; the ~50k trees are now generated lazily per visible chunk. Full-map editor preview follows the same node cost. Visible-feature streaming and deferred collision streaming are the next performance work before the phone release; measure with `make bench`.

### Interaction and interiors

- `Interactable` is an `Area2D` on `PhysicsLayers.INTERACTABLES` with `monitoring = false`. `PlayerInteraction` is an `Area2D` child of the player on layer 0 with mask `PhysicsLayers.INTERACTABLES`, `monitorable = false`; it polls `Input.is_action_just_pressed("interact")` each physics frame while overlaps exist, picks the closest target in front with a small preference, ignores input while the entity is `locked`, and emits `message` when the target rejects.
- `Entity` has `locked: bool` with `set_locked(value)` — while locked velocity is zero and the controller is not read.
- Entrances are data in `res://data/overlays/entrances.json` keyed by building OSM ID (`{"version":1,"entrances":[]}`), `position` approximated and snapped to the building footprint edge at load time by `BuildingGeometry`. `EntranceData.is_open(weekday,hour)` uses Monday = 0: entries `{"days":[...],"from":float,"to":float}`; `to < from` wraps past midnight, the listed day is the interval start (and yesterday's wrapped intervals are checked). Unavailable doors show `Closed · opens HH:MM` with the next opening time. Availability updates on `GameClock.minute_changed`.
- Interiors live on the same canvas, far away at `InteriorManager.INTERIOR_ORIGIN_M = Vector2(-10000.0, 0.0)`. The exterior keeps simulating. One interior loads at a time; the same `Entity` is repositioned. Entering: lock → fade out (ScreenFader) → instantiate `res://scenes/interiors/<interior_id>.tscn` if present and has an `Interior` root, else a `PlaceholderInterior` sized from the building footprint (clamped 5×4..14×10 m) with label = entrance label or building ID → place at the interior origin, move the player to `EntryPoint`, set `FollowCamera` limits from `interior.get_bounds_m()` and snap, disable `DayNight.enabled` (restored on exit). Exiting reverses it: free the interior, restore limits, place the player 1 m in front of the door outside, snap the camera.
- Authored interiors extend `Interior` with required `EntryPoint` (`Marker2D`) and `Objects` (`Node2D`, y_sort) children, optional `bounds_m` (meters, local to the interior origin) used for camera limits; `InteriorExit` inside asks the ancestor interior to exit.
- Debug builds with an empty `entrances.json` auto-spawn up to 4 doors on buildings nearest to the player spawn (snapped road-facing, placeholder interiors).

## Testing

All **gameplay** testing is manual by the human after every iteration: do not run the main game scene. The testing devices are:

1. Samsung Odyssey laptop running Omarchy Quattro in 1920 x 1080 @ 60 Hz.
2. Samsung Galaxy A03 phone running Android in 360 x 800 (portrait mode).

Agents must validate scripts without running gameplay. Use the headless harness:

- `make check` — imports the project headlessly (refreshes class/UID caches), runs `gdparse` over every game script, then loads every game script with autoloads through `res://tests/compile_check.tscn`.
- `make smoke` — runs `make check`, then the headless map + vegetation integration test in `res://tests/smoke.tscn` (map load, lazy street-tree generation, chunk streaming, collider and interaction pools, inspection output).
- `make vehicle-smoke` — runs `make check`, then the headless vehicle test in `res://tests/vehicle_smoke.tscn` (all nine data resources, wheel/tire grip, terrain profile, acceleration and impact damage, enter/exit, overlay spawning, and world-scene wiring).
- `make bench` — runs `make check`, then the headless runtime map benchmark in `res://tests/map_benchmark.tscn` (build timings, node count, static memory).
- `make lint` / `make format` — run `gdlint` / `gdformat` through `uv`; `.gdlintrc` sets a 120-column project baseline and disables legacy structural rules. `make format` rewrites files, so use it deliberately.
- `make map` — regenerate `res://data/map.json` from `data/export_0002.geojson` (or `MAP_SOURCE=... make map`) with the pinned Python dependencies.

`tools/godot_bin.sh` resolves Godot from `GODOT_BIN`, then `godot` on `PATH`, then the known local 4.7.2 binary. Keep the editor closed while agents write and run automated checks; open it only for manual playtesting. Add new automated validation under `tests/`, not as temporary scenes in the project root. If export presets are added, exclude `tests/*` from release builds.

Never ship a script with parse or compile errors. Each phase prompt lists its own manual checklist.

Before shipping a build: remove any `_mcp_game_helper` dev autoload and its editor plugin entry if present.

## Agent Workflow Notes (learned the hard way — keep current)

- While the agent writes files, keep those files **closed** in the Godot script editor: an open buffer can silently revert external writes on focus/undo/save.
- After every script write, **read the file back from disk** — never trust the write receipt alone.
- `node_set_property` cannot coerce strings to bool/int — set non-string properties in GDScript instead.
- `input_map` calls must be **sequential** (parallel bursts wedge the backend lock); `project_manage settings_set` accepts invalid keys without complaint (verify setting names against engine docs).
- Godot 4 API differs from Godot 3 memory (e.g. `ScrollContainer.horizontal_scroll_mode`). When unsure about a property or method, check the Godot 4.7 docs instead of guessing.
- Editor-log ghosts: the log buffer re-emits stale diagnostics on scans — confirm errors against current file contents (grep) before treating them as live.
- Never reference `EditorInterface` directly from a script that is shipped in a game: editor classes are stripped from export templates and the script then fails to load. Access it only under `Engine.is_editor_hint()` through `Engine.get_singleton(&"EditorInterface")`.
- Run `make check` after script changes, `make smoke` after systems that load the world, and `make vehicle-smoke` after vehicle changes; do not leave `.tmp_*` scenes or scripts in the project root.
- Godot generates `.gd.uid` sidecars; keep them tracked so scenes and references stay stable.
- Regenerate the map with `make map` (or `MAP_SOURCE=data/export_0002.geojson make map`; raw exports are gitignored, so keep one locally).

## Commit Convention

When there are changes to commit, AI agents should suggest an one-line commit message at the end of their response following conventional commit format: `type(scope): description`. Use types like `feat`, `fix`, `refactor`, `docs`, `chore` and keep descriptions concise but descriptive — focus on the "why" rather than the "what". This message must be in own line to facilitate copying.
