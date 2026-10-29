# Validation

The final local pass on 30 October 2026 used Godot `4.7.2.stable.official.ed1daf0bf` on an Apple M2 Mac with Compatibility rendering. Older engines and other operating systems have not been validated locally.

## Automated results

All eleven suites from the initial milestone pass, together with the new save-safety suite. The isolated runner also verifies its resolved user-data directory, imports fresh assets, and starts the configured main scene for 120 fixed-FPS frames. That is twelve suites plus isolation, import, and startup checks. The complete run reports no script errors, engine errors, or shutdown leak diagnostics.

The tests cover map determinism and connectivity, coordinate picking, construction and services, production and resource safety, research progression, manufacturing, paths and damage, strategic weapons, campaign outcomes, persistence, AI behavior, rendering integration, and UI routing. Existing tests retain regressions for missile overspending, removed silos, AI management after loading, city reference cycles, route reuse, and batched chunk rebuilding.

The new save-safety suite performs 69 checks. It rejects malformed field types, invalid enums and import resources, non-finite or negative balances, bad positions and paths, duplicate or conflicting IDs, invalid manufacturing facilities, invalid AI cursors, oversized files, and an invalid JSON root. It checks valid and earlier version-1 reconstruction, read-only backup recovery after missing/corrupt primaries, a real temporary-write failure, preservation of the last valid backup, and skipping a semantically invalid newest autosave. Five accepted invalid states were reproduced against the earlier loader before these changes.

The existing persistence fixture was corrected to queue infantry at a barracks rather than a missile silo. The test still checks exact state reconstruction; its fixture now represents a valid manufacturing state. UI regressions check visible save controls, correct building labels, meaningful no-selection feedback, all Forces entries fitting their panel, and non-overlapping palettes, toolbar, and unit commands.

Run everything with:

```sh
python3 tools/validate.py --godot /path/to/Godot
```

The runner copies project sources and the installed engine into temporary locations. A portable-engine marker isolates editor data/settings/cache, while the project import cache lives in the temporary project. A random, owned user-data directory is checked against `OS.get_user_data_dir()` before import or gameplay. Linux additionally uses temporary XDG directories. Temporary runtime and save directories are removed afterward; results remain in the printed log directory. The campaign fixture also uses a process-specific temporary directory.

The workflow in `.github/workflows/godot-validation.yml` pins the engine version, verifies the official Linux ZIP checksum, uses pinned GitHub action revisions, and grants read-only repository permissions. Workflow syntax, shell syntax, the checksum pin, and its validation entry point were checked locally. Hosted Actions and a Linux run have not occurred; no hosted success badge or result is claimed.

## Actual manual gameplay

The initial milestone opened the project in the installed editor and exercised native-window construction, utility coverage, zone development, farming, imports, research, and infantry manufacture. Manual save/load restored a removed power plant and the saved ledger. Its original screenshot is retained in the demo notes.

The final pass used disposable project and engine copies. A copy of the earlier review save was loaded, then I added housing, an import depot, farm, barracks, and university through actual mouse and keyboard input. Paid military supplies arrived, Industrial Expansion completed, and infantry was manufactured and deployed through the Forces panel. I selected that infantry, issued a move order, and observed movement, its destination, and its command state in the native game. Research progressed through the early university branch. No developer force spawning or injected resource reserves were used in this manual city.

The first portion ran at 2× simulation speed. A manually saved copy was then loaded into a fresh, normal-speed session to inspect the corrected layout and capture the final unit screenshot. All deployment entries, including Bomber and Fighter, were visible above the toolbar, and selecting a unit left the toolbar reachable beneath its command strip. Save/load succeeded on those isolated gameplay states.

## Limits

Some automated suites use controlled resources or developer-spawned units to isolate rules. The initial 600-tick default-seed experiment reached all technologies, eight AI units, and capture of an undefended player capital without resource injection; it was not a full human-played campaign. A complete player campaign, manually observed advanced-weapons battle, packaged export, Windows run, and sustained large-army benchmark remain untested.

The simulation retains full-grid city scans and BFS searches for new paths. The previous diagnostic showed a long first-search tail; this pass does not claim a new FPS or scalability improvement. Save validation adds work during saving, loading, and autosave selection. Timing output is recorded by the persistence suite, not presented as a portable performance guarantee.

Current rule limits include step-count rather than weighted-time paths, shared unit tiles, movement through structures, simple food and service-loss behavior, capital-capture progress that can carry between visits, and developed zoning that can rebuild after bulldozing its building. These are documented prototype limits; this pass did not rebalance the game or add gameplay features.

The loader bounds file size, map dimensions, counters, and typed state. These tests are practical regression coverage, not exhaustive fuzzing or an anti-cheat guarantee. Saves assume one writer; power-loss durability and simultaneous writes from multiple game instances have not been certified.
