# Assets and attribution

I designed this project and developed it with Codex assistance. The atlas provenance is now supported by original generation records and matching output files, rather than inferred only from embedded metadata.

## Sprite atlases

All three atlases were generated through Codex on 13 September 2026. During the October portfolio review, their cached generation outputs matched the repository files byte for byte by SHA-256. The recovered generation records contain the revised prompts and completed outputs; the original request required project-specific artwork, prohibited downloading packs, and explicitly prohibited copying TheoTown assets. The generation prompts request generic structures and units, no copied designs, text, logos, or brand references.

On 30 October 2026, I confirmed that this was my own project with Codex assistance, with no outside reference images, collaborator code, employer/client material, or other third-party source files supplied outside those records. All three atlases were visually inspected during the review. No recognizable third-party logo or named character was identified. This is a visual review, not an exhaustive image-similarity search.

| File | Dimensions | Source and redistribution assessment |
| --- | --- | --- |
| `assets/terrain/isometric_terrain_atlas_v1.png` | 1536 × 1024 | Project-generated OpenAI output; exact cached-output match; suitable for inclusion in this portfolio snapshot on the evidence above |
| `assets/buildings/isometric_buildings_atlas_v1.png` | 1246 × 1263 | Same evidence and assessment |
| `assets/units/isometric_units_atlas_v1.png` | 1774 × 887 | Same evidence and assessment |

The [provenance record](ASSET_PROVENANCE.json) contains file hashes and the recovered generation prompts, without private chat paths or account details. PNG C2PA/JUMBF metadata also names `gpt-image` and OpenAI Media Service API. The images and metadata remain unchanged. The old raw invocation stream is unavailable, and embedded signatures have not been independently authenticated; those limits do not replace the recovered outputs and owner confirmation.

The [OpenAI Terms of Use effective 1 January 2026](https://openai.com/policies/row-terms-of-use/) assign output rights to the user as between the user and OpenAI, subject to applicable law. They also place responsibility for input rights and appropriate output use on the user and explain that output may be similar to other output. This supports using these project-generated assets; it is not a guarantee of exclusive copyright or universal non-infringement. No purchased-pack or separate third-party asset license dependency was identified.

## Other asset categories

| Category | Source | Permission or restrictions | Repository status |
| --- | --- | --- | --- |
| Roads, bridges, markers, placement outlines, and interface layout | Project GDScript drawing code developed with Codex assistance | Same unresolved reuse-license choice as the project source | Included as source |
| UI controls, default font rendering, and engine functionality | Godot 4.7.2 and its bundled components | Godot's MIT license and component notices apply to the engine distribution | Engine and font files are not bundled in this source repository |
| UI symbols | Unicode characters rendered by the engine | No external icon pack is distributed | Included in GDScript strings |
| Sounds and music | None supplied | No audio redistribution question identified | No audio files included |
| Plugins, shaders, and external runtime libraries | No project addons, shaders, GDExtensions, or external packages supplied | No additional project dependency license identified | No plugin or library binaries included |
| Gameplay screenshots | Unedited captures of this running project | Contain the assessed project art and rendered Godot UI | Included with capture notes; no generated gameplay mockups |

Godot documents its licensing requirements in [Complying with licenses](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html). The engine's [license](https://godotengine.org/license/) and [4.7.2 third-party notices](https://github.com/godotengine/godot/blob/4.7.2-stable/COPYRIGHT.txt) remain applicable when distributing an engine binary or packaged game. This candidate distributes project sources and images, not an engine executable or packaged game.

No project source-code or artwork reuse license has been selected. This repository does not claim that Godot's MIT license covers the game source, and it does not describe the generated artwork as hand-drawn. Any future license choice must be made explicitly; no blanket source or asset license was added during preparation.
