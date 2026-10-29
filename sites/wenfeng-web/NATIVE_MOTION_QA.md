# Native combat diagnostics

The capture scripts live in `godot/tools/`; the validator lives in `tools/`:

- `native_combat_capture.gd`
- `native_capture_bridge.gd`
- `tools/validate_native_capture.py`

No production scripts or assets are replaced by this tool. For an A/B test,
make two project snapshots and replace only the production file under review
in the candidate snapshot. Keep the accepted character GLBs unchanged.

## Capture

Run the native Godot renderer, **without `--headless`**:

```sh
Godot --path /absolute/path/to/godot-project \
  --disable-render-loop --fixed-fps 60 \
  --script res://tools/native_combat_capture.gd -- \
  --role=xuchu --camera=side --seconds=3 \
  --source-commit=BASE_COMMIT --output-root=/absolute/writable/output
```

First validate a 3-second recording. Then use `--seconds=20` for Xu Chu's
normal/side baseline, or `--role=zhaoyun --seconds=30` for the full Zhao Yun
diagnostic. Repeat with `--camera=normal`. Optional `--tag=NAME` distinguishes
variants without overwriting existing captures.

`--suite=contacts --seconds=12` records four marked fixtures: 6m J combo
air swings (0–3s), 2.3m J combo contact (3–6s), 1.1m too-close J combo
(6–9s), heavy attack and recovery (9–12s). `--suite=counter --seconds=3`
records an early enemy strike against Zhao Yun's E, allowing the actual
evasion and return animation to complete. The full scenario includes a later
enemy strike and intentionally records the resulting E interruption.

The output folder contains `frames/00000.jpg...` and `trace.json`. Frames
are 1280×800 at 60 simulation ticks/second. The renderer draws a 16-bit
little-endian frame barcode at the top, plus frame/time/scenario labels.
`SubViewport.UPDATE_ALWAYS` and explicit `RenderingServer.force_draw` avoid
depending on the visible OS window or its focus. The small native window may
look blank because the diagnostic world renders to the offscreen viewport.

## Encode and validate

Pillow, NumPy and ffmpeg are required:

```sh
python3 tools/validate_native_capture.py /absolute/output/CAPTURE_FOLDER --encode
```

This writes `capture.mp4` and `capture-validation.json`. Alternatively pass
`--video /absolute/movie.mp4` to check an existing encoding. `--ffmpeg PATH`
selects a specific ffmpeg executable.

Validation checks every JPG frame barcode, consecutive physics ticks, every
encoded video frame barcode, and changes in character-body image regions
across active actions. It flags active stages whose sampled body regions
remain static. **Also inspect the actual body/weapon image sequence:** a
barcode that changes alone does not establish valid 3D capture, and changing
body pixels do not establish good animation.

## Trace and interpretation

- Player commands use the production `web_bridge._command` dispatch. Only
  its native-unavailable JavaScript publication sink is omitted.
- An input driver calls the original `main._player_input` once per physics
  tick. The actual Main, Fighter, contact solver, collision, animation and
  effect code execute normally. AI is disabled.
- The existing testing flag suppresses wall-clock hit-stop and duplicate
  input polling. This is a **silent offline diagnostic, not a real-time FPS,
  latency, complete match, or animation-quality acceptance result**.
- Marked fixture resets restore positions/resources between scenarios.
  Do not evaluate these resets as natural combat transitions. J1→J2→J3,
  movement entry/exit and recovery **within** each scenario are uncut.
- Input/action/impact/state records share the encoded frame index. Do not
  assume a case named `J_hit`, `parry` or `counter` succeeded: inspect its
  actual `events`, HP changes, states and images.
- Final bone samples come from a read-only observer at the tail of the
  `SkeletonModifier3D` chain, before Godot restores the animation pose.
  `bone_sample_physics_frame` should match the captured physics tick.
  Reading bones after rendering would return the restored base pose and
  cannot prove that final contact/grip modifiers left the body unchanged.
- `source_grasp` is sampled immediately before the contact modifier and
  `final_grasp` at the modifier tail. Each uses the live global hand-bone
  transform multiplied by the actor's actual grip offset. The actor's cached
  `palm_position()` is deliberately not used. Both include left/right palm
  coordinates, palm separation, signed shaft direction and sampling tick.
- `bones` are joints, not shoe soles. Never use ankle/ToeBase heights alone
  as proof of correct footwear grounding. Do not judge Xu Chu's free left
  hand as though he must hold a two-handed polearm.

Read-only final-pose recording, frame labels, fixture scheduling and image
validation are QA instrumentation. They do not change the source GLB,
retargeting, gameplay timings, movement speeds or hit profiles.

## Body preservation regression

Run `res://tools/duel_body_preservation_test.gd` headless to compare the raw
pelvis/legs and final output within the same modifier tick, alongside actual
wrist, bone-length, rendered grip, capsule and damage checks. These fixtures
keep the opponent physics disabled to isolate static distances. They do not
cover the moving defender, pushback or full real-match continuity.

The unchanged v20 runtime fails the twelve body-preservation cases. A proposed
correction-relative solver passed all92 checks but failed the actual native
moving-defender replay with a new close-range shaft flip and fewer contacts;
it was rejected. The production script remains v20. Do not weaken the body,
wrist or grip assertions, or treat numeric passes as visual acceptance.
