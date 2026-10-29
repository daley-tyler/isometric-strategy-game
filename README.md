# Isometric Strategy Game

I’m developing a Godot prototype that combines city building, resource production, and military strategy on one isometric map. I wanted the civilian and military systems to share the same world: roads connect services, industry supplies manufacturing, and units fight over territory and capitals.

This is a playable single-player prototype with one AI opponent. It is still a development project, with simple economic rules and some developer controls. I developed the design and used Codex for implementation, testing, review, and artwork generation.

![A manually built city and a selected infantry unit in the running game](docs/screenshots/unit-orders.png)

The screenshots show the actual Godot game. The [demo notes](docs/DEMO.md) explain what was exercised and how each capture was produced.

## What works

The game generates a deterministic 128 × 128 map with forests, hills, coast, a river, bridges, resource deposits, and two capitals. Construction includes roads, residential and commercial zones, utilities, farms, industrial facilities, research facilities, and military buildings. Power, water, and fire coverage follow the road network.

The simulation advances once per second. Housing provides population, commerce and industry use workforce, and production draws from a shared resource ledger. Imports arrive after a delay, research unlocks facilities and technologies, and manufacturing produces deployable units. Missile production waits for resources if another system spends its required reserves.

Seven unit types support movement and combat. Ground units use a cardinal breadth-first path search and terrain movement delays; aircraft can cross water. Artillery has range limits, splash damage, and a cooldown. Missiles have distance-based flight times and damage both nations’ structures. SAM interception uses a deterministic prototype rule rather than a probability model.

The AI runs its own city economy through the same simulation APIs. It builds infrastructure, researches, imports resources, manufactures units, and assigns defensive and attacking forces. Capturing a capital ends the active campaign. Victory can continue into the same world in sandbox mode; defeat offers load or restart recovery.

Manual saves and three rotating autosaves store versioned JSON. Loading reconstructs simulation objects, reconnects references, and rebuilds presentation caches. The loader checks field types, finite nonnegative resources, enum ranges, positions, unique IDs, path indices, manufacturing facilities, and AI cursors before reconstructing state. Invalid files leave the running world intact. A missing or corrupt primary file can load its validated previous-save backup without overwriting either file. The format is bounded to 16 MiB and is not a supported modding or network protocol.

## Run locally

The project is tested with [**Godot 4.7.2 standard**](https://godotengine.org/download/archive/4.7.2-stable/), using the Compatibility renderer. No plugins or third-party packages are required. Compatibility with older Godot releases has not been established.

Import `project.godot` in Godot, open the project, and run it with **F5**. The main scene is `scenes/main.tscn`.

With Godot on your PATH, you can also run it from the project directory:

```sh
godot --path .
godot --path . -- --world-seed=20260913
```

Use WASD or the arrow keys to pan, middle-mouse drag to move the camera, and the wheel or `+` / `-` to zoom. Left-click selects a tile or unit. The bottom toolbar opens construction palettes; the right panel shows the selected object and its available actions. Escape or right-click cancels a placement preview.

To start a city, place connected roads, put a power plant and water facility beside them, then zone housing and commerce next to the serviced roads. Housing develops on a simulation tick. Add housing before staffing research and industry, since commercial jobs also use the available workforce. Farms produce food; an import depot can buy materials, fuel, and military supplies while production develops.

Select a barracks to queue infantry. Once production finishes, deploy it from the Forces panel while its facility or your capital is selected. Select the unit, then right-click empty ground to move or an enemy to attack. The command bar also provides Move, Attack, Defend, and Stop.

Save Game, Load Game, and Load Latest Autosave are in the right panel. This review copy uses the custom `user://` directory **City Game Portfolio Review**, separate from the original prototype’s directory. On macOS it is normally `~/Library/Application Support/City Game Portfolio Review/`. Manual saves use `saves/manual_save.json`; autosaves rotate every 120 seconds of active simulation.

The [controls reference](docs/CONTROLS.md) lists keyboard shortcuts, including developer-only force spawning.

## How the code is organized

I keep authoritative simulation data separate from the visual nodes. Most simulation objects extend `RefCounted`, so deterministic rules can run without the game window. The main scene creates the camera, renderers, HUD, and simulation objects, then coordinates their fixed ticks.

| Area | Main files | Responsibility |
| --- | --- | --- |
| World | `map_data.gd`, `iso_math.gd` | Seeded generation, packed tile layers, coordinate conversion, and picking |
| City | `city_simulation.gd`, `city_config.gd` | Construction, coverage, population, production, research, imports, and manufacturing |
| Military | `combat_simulation.gd`, `strategic_simulation.gd` | Units, orders, paths, damage, capture, missiles, and defenses |
| Campaign | `ai_campaign_controller.gd`, `campaign_state.gd` | AI policy, outcomes, and sandbox continuation |
| Persistence | `persistence_manager.gd` | JSON serialization, reconstruction, temporary-file verification, and save rotation |
| Presentation | `world_renderer.gd`, overlays, `prototype_hud.gd` | Chunk meshes, sprite regions, selection, and controls |

Terrain is cached in 16 × 16 tile chunks rather than represented by one node per tile. The renderer culls chunks against the camera and batches tile changes so a chunk is rebuilt at most once per simulation tick. Building and unit sprites use atlas regions with shared tile-foot depth ordering. Camera movement does not rebuild static terrain. AI planning runs every third simulation tick and retains an existing route when its destination is unchanged.

A practical challenge is keeping construction previews and simulation rules in agreement. The preview and committed building share the same footprint validator and sprite foot point, so visual overhang does not change which tile is occupied. Save/load has a similar boundary: reconstructing JSON is only useful if references and AI behavior still agree afterward. The tests compare the next simulation step after loading with uninterrupted execution.

## Validation

From the project directory, run the importer and all twelve suites with Python 3:

```sh
python3 tools/validate.py --godot /path/to/Godot
```

For a standard macOS app installation, the executable is inside `Godot.app/Contents/MacOS/Godot`. The runner stages a disposable project and portable copy of the installed engine, checks the resolved test-save directory, and imports fresh assets. Project caches, editor settings, and test saves are isolated from normal play. It runs all twelve suites plus main-scene startup, prints its log directory, enforces timeouts, and treats script errors and leaked objects as failures even when Godot returns zero. Allow temporary disk space for a copy of the engine.

For an isolated graphical playtest:

```sh
python3 tools/playtest.py --godot /path/to/Godot --log-file test-results/playtest.log
```

That session uses disposable saves. Closing its window discards them; ordinary play through the editor uses the persistent directory described above.

The GitHub Actions workflow pins Godot 4.7.2, checks the Linux archive against the official SHA-512 digest, and runs the same validator on Ubuntu. Its YAML, download-script syntax, checksum pin, and validation entry point were checked locally. A hosted Actions run has not happened yet.

The suites cover world determinism, coordinate picking, services and development, resource calculations, research progression, manufacturing, pathfinding and combat, strategic weapons, campaign outcomes, persistence, AI policy, UI routing, and rendering integration. The reliability suite adds regression cases for competing missile costs, removed silos, AI save/load behavior, city object lifetime, route reuse, and batched chunk updates. See [validation notes](docs/VALIDATION.md) for the distinction between automated checks and actual playtesting.

## Current limits and attribution

The economy is intentionally simple. Food cannot fall below zero, but starvation is not simulated. Fire stations provide coverage without a fire-event simulation. Units can share tiles, paths do not avoid buildings or other units, and breadth-first search minimizes step count rather than terrain travel time. Movement is discrete rather than interpolated. The campaign has one known-state AI policy, with no diplomacy, fog of war, multiplayer, or difficulty balancing.

The initial design included broader future ideas; those are not completed features. Long campaign balance, packaged builds, other operating systems, and large armies have not been validated. The remaining rule and test limits are described in the validation notes, including uninterrupted-capital-capture behavior and developed-zone bulldozing.

The three sprite atlases were generated for this project through Codex. Their generation prompts and cached outputs have been recovered and matched to the current files by SHA-256. I confirmed that no outside reference images, external packs, collaborator code, or employer/client material were supplied. The [asset notes](docs/ASSETS.md) give the provenance and redistribution assessment.

The [development history and attribution notes](docs/PROVENANCE.md) explain why the public repository starts with a reviewed snapshot.

No project source-code or artwork reuse license has been selected. Godot Engine has its own [MIT license](https://godotengine.org/license/); that does not assign the same license to this project.
