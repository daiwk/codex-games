# Xu Chu UAL2 offline rig lab

This is an experiment/reproduction tool, **not an approved runtime animation pack**. It reads the repository's frozen Xu Chu model and Quaternius UAL2 Standard source, then writes an independent lab directory. It does not edit/export/deploy the game, its controllers, production GLBs or production import settings.

## Run

Python requires `numpy`, `scipy` and `Pillow`, also used by the existing `prepare_polearms.py`. Run from the repository root:

```sh
python3 sites/wenfeng-web/tools/prepare_xuchu_ual2_lab.py \
  --output-dir /private/tmp/xuchu-ual2-lab
```

Optional Godot4.7.2 import and real AnimationPlayer mixer checks:

```sh
python3 sites/wenfeng-web/tools/prepare_xuchu_ual2_lab.py \
  --output-dir /private/tmp/xuchu-ual2-lab \
  --godot /path/to/Godot
```

Use a fresh directory. `--overwrite` only accepts an existing directory carrying this tool's valid marker; `--verify-only` rechecks an existing lab without rebaking. Output must be outside the repository, cannot contain an input, and cannot contain symlinks. Known source/baseline hashes are checked before any output is written. `--baseline-glb` and `--manifest` accept separately saved copies of the same frozen inputs if the current game later advances.

`--assert-reference-shas` additionally verifies exact binary reproduction of the four reviewed experimental GLBs. This is useful with the original numerical-library environment; numeric preservation checks remain the meaningful geometry checks across environments.

## Inputs and provenance

- User-supplied Xu Chu baseline SHA256: `89f369ccbfce8b5ecd4735ed5f4a18467d23ca4dfc9ec684f51b9c7c30dad43c`.
- UAL2 Standard SHA256: `8cee20ab1bc55130092447e810e26df22dd2803eccc54f52137a7d54d7ab88a8`.
- Default inputs are `godot/assets/characters/xuchu.glb`, `godot/assets/characters/animation_manifest.json` and `source-assets/animations/ual2/UAL2_Standard.glb`, resolved relative to this tool, without machine-specific paths.
- Output `provenance/` preserves the UAL2 CC0 license/source/metadata snapshots and the baseline animation manifest. `lab-manifest.json` records source/model/manifest and provenance-file hashes.
- CC0 applies to the Quaternius source animations. The user character and weapon models have separate rights; this tool does not relabel them CC0.

## Output stages

1. `bake_source.py` creates the original full-body comparison (`0f4b…`) from the frozen input. Both arms, fingers, torso and source Hips XYZ are carried; no per-frame grounding, ready-body blend or XZ clamp. Heavy/C remain independent diagnostic clips, with their original constant placements; they are not claimed as compatible Regular recovery branches.
2. `build_twist_rig.py` creates the Regular3s experiment (`184664…`): three forearm roll stations with axial weight interpolation, eight skin influences, original main bone names/global rests retained. Full body, free left hand, source timing, palm orientation and blade path are preserved; only the right arm is retargeted offline.
3. `append_identity.py` creates `71a691…`, adding helper identity tracks to legacy aliases while retaining all original channels/samplers and binary prefix. The current Godot default Mixer also resets the tested unfixed Idle case; a prior residual-roll bug is not established. Explicit ownership makes the intended track behavior unambiguous.
4. `append_recoveries.py` creates `d940035c…`, adding A/B raw and retargeted recovery choices. It does **not** connect a gameplay chain.
5. Verifiers measure original skeleton/skin equivalence, body preservation, exact bone lengths, palm/knife path, geometric wrist cone and branch joins. `numeric-checks.json` contains16 focused assertions. Skin matrix determinants are inspection-location proxies, not global visual pass/fail scores.

Main model: `xuchu-ual2-family-recoveries.glb`.

Aliases:

| Alias | Source duration | Purpose |
| --- | ---: | --- |
| `XuUAL2RegularTwistRig` | 3.000000s | Complete authored Regular performance |
| `XuUAL2RegularARecoveryRaw` / `…ARecoveryTwistRig` | 0.966667s | Single-hit recovery option |
| `XuUAL2RegularBRecoveryRaw` / `…BRecoveryTwistRig` | 1.033333s | Two-hit recovery option |

Raw source branch points are Full `13/30s -> A_Rec0` and Full `1.0s -> B_Rec0`. In `d940` the corrected A join's largest skin difference is0.329mm, B is near float precision; these do not require an expanded blend or further solver optimization. Isolated A/B/C starting poses are **not** assumed to concatenate into Full.

All new Regular recovery options share **one** static calibration: source RegularFull0 Foot/Toe -> frozen target Idle0; hip scale0.5089511975351362; same root reference; constant bodyY−0.008660267634444626rig. No recovery-specific foot calibration or minY fit.

`family-root-motion-120hz.json` includes complete Hips local XYZ and clip-start deltas, before any gameplay root extraction. Apply model/global basis and scale2.15 once when extracting XZ; keep authored Hips Y. The tool does not preapply CharacterBody movement.

## Rig integration constraints

Preserve RightArm, RightForeArm, RightForeArmTwist1/2/3 and RightHand rotation tracks together. Preserve JOINTS_1/WEIGHTS_1. Hand is now under Twist3 with zero local rest translation. Anatomical wrist measurement uses finalTwist3 basis, original hand rest orientation and the mainForeArm->Hand axis/length. Existing wrist code relying on Hand.rest.origin cannot be reused unchanged. Source original clips remain usable at identity helper pose, but this is not a blanket gameplay-controller compatibility claim.

Exact-palm Heavy can be geometrically infeasible within a40° wrist cone at2.15–2.267s; no Heavy twist candidate is generated. Full's final pose also differs from Full0, including right-foot yaw; a gameplay controller must handle its return to ready rather than hard-seeking the start. A toe position difference alone does not establish whole-foot sliding: it can include a pivot about the ankle. This tool does not change authored hips/legs to hide that boundary.

## Actual native images

The command prepares `OUTPUT/godot-preview`, with120Hz import and AnimationPlayer optimizer/compression disabled for faithful comparison. It opens no native window automatically. Record sequentially:

```sh
/path/to/Godot --path OUTPUT/godot-preview --script res://capture_twist.gd -- \
  --camera=normal --seconds=3 --output=OUTPUT/normal
/path/to/Godot --path OUTPUT/godot-preview --script res://capture_twist.gd -- \
  --camera=arm --seconds=3 --output=OUTPUT/arm
ffmpeg -framerate 60 -i OUTPUT/normal/frames/%05d.jpg \
  -c:v libx264 -crf 18 -pix_fmt yuv420p OUTPUT/normal/actual.mp4
```

The full clip produces180 actual rendered frames at0..2.983333s; encoding at60fps retains the original3s cadence. Capture wall-clock speed is irrelevant. The near-arm camera is on the anatomical right side. The standalone renderer emits trace.json with sampled bones, grip and blade points. Review the actual shoulder/elbow/wrist/armor surface and complete performance; neither numeric success nor still frames establish complete combat-animation acceptance.

For a direct sole-level source comparison, record the original UAL2 mannequin and the retargeted Xu with the same close camera and10cm floor grid:

```sh
/path/to/Godot --path OUTPUT/godot-preview --script res://capture_feet.gd -- \
  --kind=source --output=/absolute/new/source-feet
/path/to/Godot --path OUTPUT/godot-preview --script res://capture_feet.gd -- \
  --kind=target --output=/absolute/new/target-feet
```

Each recording contains60 real frames for the first second at1x. The source mannequin is uniformly scaled1.094245; Xu uses the game's2.15 scale. No animated foot, root-height or timing adjustment is introduced. The target retains the single family calibration documented above. The visible opening shows a rapid low-foot slide into the crouch in the source itself; the Xu retarget retains that character. Preserving the source therefore does not establish natural footwork or a suitable heavy-character style. This performance remains an experiment, not an accepted final J replacement. Joint heights in the JSON are not sole heights.
