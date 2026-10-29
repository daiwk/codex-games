# Single-edge K arm and upper-arm twist experiment

**Review candidate only; not finally accepted and not PB0.** The main downward
cut now presents the saber's real sharp edge. The prolonged palm-up carrying
posture and stance/action switching remain unaccepted. This is not a production
replacement, a complete body controller, or permission to deploy.

From `sites/wenfeng-web`, with Python, NumPy, SciPy and Pillow available:

```sh
python3 -B tools/xuchu_ual1_lab/dao_k_trial/prepare.py --output-dir /tmp/xu-dao-k-assets
```

The output must be a **new directory outside the repository**. Existing output
directories and changed locked inputs are rejected. Optional `--source`,
`--baseline` and `--manifest` paths must have the same hashes as `locks.json`.
The wrapper does not download, run Godot, record video, modify runtime resources
or code, build, deploy, or commit. Use only `prepare.py`; the two underscore files
retain the numeric experimental bakes with parameterized file paths.

## Exact generation chain

1. Reuse the parent `../prepare.py`: repository UAL1 Standard non-root source
   `69591853…`, original Xu model `89f369cc…`, and grip manifest `3182fe59…`.
   This produces Raw `e19e3cbb…` and Support `b3d35d94…` under `upstream/`.
   Its existing static Foot/Toe calibration, shared height, original body/root
   curves and 18° local follow-through hand art are retained exactly. The
   inherited `library_mapping('ual2')` is intentional for the shared schema.
2. `_bake_arm.py` produces **f233a6dd…**, the right-arm design with a new blade
   path. This first single-bone version has visible upper-arm/elbow skin collapse
   and is a failed diagnostic retained as an input to the rig experiment.
3. `_build_upper_twist.py` produces **9fbc41c9…**, the same reachable arm/knife
   motion with three upper-arm twist stations and redistributed skin weights.
   Only this final model is the current surface-review candidate.

Exact output SHA256 values:

| Output | SHA256 |
| --- | --- |
| `xuchu-dao-k-arm-art.glb` | `f233a6ddb05553bf188e998a0dc20960bf00b95948230134716db1e78b54d0c1` |
| `xuchu-dao-k-upper-twist.glb` | `9fbc41c922c1dd65f87e239da5fa4747eddfbb0c7dab4c06d11110d8efaed064` |

The wrapper checks all four upstream/final GLBs byte-for-byte, generation-script
and helper locks, and unchanged input hashes. A dependency/platform hash mismatch
is a reproduction failure to inspect, not permission to install another result.
Metadata includes local paths and need not be byte-identical across output
directories. NumPy/SciPy/Pillow versions are recorded in `reproduction.json`.

## What the arm design changes

Source hips, legs, torso, left arm, finger local motion, pelvis XYZ and the
1.5333333s source timing remain. The right arm and real knife path are redesigned;
this does **not** preserve the original palm/wrist points or knife trajectory.
Equipment local quaternion stays identity and the original weapon-to-hand grip
frame stays fixed throughout every clip. The source/grip frame was verified;
neither a global equipment turn nor a per-K equipment turn is used.

The blade frame uses model-world F=+Z, U=+Y, N=-X, with shaft
`S=U*cos(theta)+F*sin(theta)` and sharp-edge direction
`E=-U*sin(theta)+F*cos(theta)`. The blade angle rises smoothly from0° to110°
in .30–.55s. The intended wrist is shoulder-relative .31m forward and
.15m high→.12m low. Preserving the Support local wrist orientation derives the
forearm frame; the exact upper-arm-length sphere projects that wrist target by
up to14.1cm. Prep blends in0–.30s and recovery returns to the source by1.30s.
The original 31 aliases and binary remain before the appended art alias.

## What the rig changes

`XuDaoKUpperTwistTrial` keeps the f233 endpoint motion. Proximal `RightArm` uses
the minimum swing that aligns the Support humerus direction with the new elbow.
The remaining full humerus-axis roll is divided equally over
`RightUpperArmTwist1/2/3`, with the final station reaching f233's orientation.
`RightForeArm` is reparented to the final helper with local translation zero;
three rest translations sum to its old translation. ForeArm/Hand/Finger local
rotations and the grip remain. Original RightArm vertex influence is distributed
by rest shoulder→elbow axial coordinate. No original influence is discarded;
the actual maximum is5, stored in8-influence attributes.

All31 previous aliases retain their channel/sampler prefixes and gain explicit
identity tracks for the three helpers. With helpers identity, original bones and
weighted skin are equivalent. This changes the rig hierarchy and weights;
it must not be dropped into a controller on the strength of asset reproduction.
The total large axial roll is unchanged: smaller per-station numbers are not an
anatomical or artistic acceptance criterion.

For the separate, still-unaccepted K-only runtime trial, explicitly build its
animation library and root sidecar into another new outside directory:

```sh
python3 -B tools/xuchu_ual1_lab/build_k_resource.py --variant dao_trial --source-glb /tmp/xu-dao-k-assets/xuchu-dao-k-upper-twist.glb --baseline /tmp/xu-dao-k-assets/xuchu-dao-k-upper-twist.glb --output-dir /tmp/xu-dao-k-library
```

Both inputs must be the identical frozen9fbc model. The library SHA must be
`ef37f13b2f5a2c7fe8288a5a3f992686b338ccf4ce0e4083ae90be9cd7574963`.
Any manual isolated runtime integration must also use9fbc as the **main Xu
character model**; adding this clip/library to the old65-bone model is invalid.
The builder only writes outside resources and does not copy or install anything.
It does not change acceptance of the palm-up posture or stance/action switching.

## Recorded evidence and remaining limits

The frozen review was generated with120Hz import and no optimizer/compression.
Normal and arm-close-up films each had93 ordered images at60 source samples/s,
covering0→1.533333s plus the endpoint (encoded1.55s), with all image/video
barcodes verified. They were offline sampled previews, not real-input combat or
realtime performance tests. The visible f233 thin strip/black seam at .450s was
absent in9fbc; the pauldron did not visibly fly away or abruptly flip. Independent
continuous pose review is still required.

The recorded checks found31 legacy aliases ×3 poses equivalent to about
3.58e−7m in actual CPU-skinned vertices. Eight imported K→Idle/oldJ1 mixer cases
and a short native switch film reset helper rotations to identity after blending.
Native60Hz blade-tip difference from f233 was at most9.21e−7m. At240Hz points
between120Hz keys, quaternion interpolation reconstructed the f233 path with up
to0.915mm /0.154° error; exact continuous equivalence is not claimed. These
checks establish isolation/capture properties, not acceptable carrying posture,
stance transitions, hit windows, actual blade contact or the complete combat feel.

This directory deliberately contains only experimental asset bakes, locks and
these notes. It does not include a runtime patch, scene, controller, or capture
framework. The current local review artifacts were saved separately under
`/private/tmp/wenfeng-dao-k-upper-twist/`; they are not required to reproduce the
asset bytes.

## Source and model rights

UAL1 animation source and its existing CC0/license/source snapshots are inherited
through the parent lab and copied to `upstream/provenance/`. The Xu model/texture
and original target clips are user-provided repository material; their rights
are not converted to CC0 by using CC0 source motion. The original parent lab
README documents that distinction and all upstream inputs. No commercial-game
asset was extracted and no new source download or permission assumption occurs.
