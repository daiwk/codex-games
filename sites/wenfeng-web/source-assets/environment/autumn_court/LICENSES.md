# Autumn courtyard environment sources

- Stone Tiles 02, Charlotte Baglioni / Poly Haven: https://polyhaven.com/a/stone_tiles_02
- Weathered Brown Planks / Poly Haven: https://polyhaven.com/a/weathered_brown_planks
- Asset license: **CC0 1.0 Universal** — https://polyhaven.com/license and https://creativecommons.org/publicdomain/zero/1.0/

Retrieved 2026-10-28. Runtime JPEGs are the unmodified original 1K diffuse, OpenGL normal and (stone) roughness maps. Runtime files, byte counts, origin URLs and SHA256 are recorded in `SOURCE.json`; the preparation command is `python3 tools/fetch_autumn_environment.py`. The downloader is powered by Poly Haven asset metadata, with no runtime API or network dependency. Godot import settings enable mipmaps and identify the normal maps.

Architecture, bevelled masonry, curved roof/tile meshes, dougong-inspired brackets, bamboo leaves, autumn foliage, placement are authored for this project in `godot/scripts/arena.gd`. No third-party building or tree meshes are included. The vegetation is opaque, double-sided geometry; static environment surfaces are combined by material after construction.

The photographed slate is a material source, not a historical architectural reconstruction. Mountain gate proportions, roofs, wood tint, weathering and vegetation are a game art interpretation. No assets from commercial reference games were extracted.

## Generated mountain panorama

`mountain_panorama.png` was generated for this project with the image generation tool on 2026-10-28. It depicts a warm sunset over layered forested mountains and a cloud-filled valley, without text or interface. It is mapped by a custom sky shader with a 10% overlap blend to make the left/right boundary continuous, and image V=0.58 at the horizon. It is used only as distant sky scenery and reflections, while local buildings, trees and the court remain geometry. Prompt summary, byte count and SHA256 are recorded under `generated_environment` in SOURCE.json. This project artwork is not attributed to Poly Haven and is not claimed as a third-party CC0 file.
