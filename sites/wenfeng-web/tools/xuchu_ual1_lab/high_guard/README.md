# Xu saber preparation and cut entry

The production entry point is `tools/prepare_xuchu_heavy.py`. From the Web
project, with NumPy, SciPy and Pillow installed:

```sh
python3 -B tools/prepare_xuchu_heavy.py --output-dir /tmp/xu-heavy-assets
```

The destination must be new and outside the repository. The wrapper reads the
archived original Xu model and animation/grip manifest from
`source-assets/animations/runtime-baselines/`, reproduces the frozen FK model,
then applies this character-fit preparation and builds the animation library.
It verifies every released GLB and sidecar hash. Captures, temporary source
projects, Godot caches and rendered trajectories are not generation inputs.

The three files in the resulting `runtime/` reproduce the installed character
and motion library. Copy `xuchu.glb` to `godot/assets/characters/`, and the other
two files to `godot/assets/motion/`. Keep both committed `.glb.import` profiles:
120 Hz, immutable tracks retained, optimizer/compression disabled. Rebuild Web
after importing. Reproducing these same bytes requires no manifest change.

The main character is 50eb, with 68 bones and eight skin influences. All original
27 clip aliases remain. Only the new K alias changes its right Arm, ForeArm,
Hand and three upper-arm twist rotation tracks in .075–.425s. Its high guard
widens and raises the held saber; the cutting entry uses the whole arm and
shares elbow extension with wrist counter-rotation. From .425s, source tracks
are byte-identical to the FK recovery candidate. Body, legs, free arm, finger
locals, root curve, bone lengths, grip and weapon mesh remain source data.

Runtime stopping steps and state cleanup live in `xu_run_entry.gd` and
`xu_ual1_k.gd`. Their world-space shoe contacts use the actual skin, handle a
body collision that occurs after planning, and release ground anchors on a
jump. K damage still requires actual blade contact. This asset bake does not
perform input, gameplay, visual or performance acceptance.

The UAL1 source animation is archived under its existing CC0 license. The
user-provided Xu model, textures, saber and original animations retain their
existing rights; the derived character is not relabeled CC0.
