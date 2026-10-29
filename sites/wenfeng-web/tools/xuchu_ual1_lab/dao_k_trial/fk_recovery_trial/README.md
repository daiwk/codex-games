# Frozen FK recovery candidate50eb

**Only permitted for isolated gameplay review. Art is not final; not PB0.**
Independent review of the complete normal/wrist sequences allowed this candidate
to proceed to isolated gameplay. It still has a slight pause in .55–.667 and a
concentrated blade-rise beat in .75–.9. Weight/inertia, stance transitions and
actual combat remain unaccepted. Reproducing asset bytes does not approve them.

From `sites/wenfeng-web`, with Python, NumPy, SciPy and Pillow available:

```sh
python3 -B tools/xuchu_ual1_lab/dao_k_trial/fk_recovery_trial/prepare.py --output-dir /tmp/xu-fk-recovery-assets
```

Use a new output directory outside the repository. Existing output and changed
locked inputs/dependencies are rejected. Optional `--source`, `--baseline` and
`--manifest` paths must match `locks.json`; the default baseline is the original
89f Xu model, not a runtime candidate. The wrapper reuses the parent asset chain
and never runs Godot, records video, writes production resources/code, builds,
deploys or commits. No temporary path or captured movie is a generation input.

## Exact chain and outputs

1. Parent `../prepare.py` reproduces Raw e19→Support b3d→failed arm diagnostic
   f233→upper-arm twist rig9fbc from the locked repository UAL1 source, original
   model and grip manifest. This remains unchanged under `upstream/`.
2. `_prepare_keys.py` reproduces the approved .65/.80/1.05 **static FK poses**
   in `xuchu-dao-fk-keys.glb`, SHA256
   `84a43012d9d670a5439d0df10aaba99bb92e2dedb9e0357f0b0ea8f20b2f59ab`.
3. `_bake_full.py` appends `XuDaoKFKRecoveryTrial` in
   `xuchu-dao-k-fk-recovery.glb`, SHA256
   `50ebed213d9f4d90e12935474d6b992ae75e9815774037a2b366134b78ff8a55`.

The wrapper verifies all six upstream/current GLBs byte-for-byte and writes
input/helper/output hashes and actual dependency versions to `reproduction.json`.
Source/license snapshots remain in `upstream/upstream/provenance/`. Metadata
records local paths, so its bytes may differ across output directories. A GLB
hash mismatch is a reproduction failure to inspect, not permission to install
a substitute. This directory adds only two numeric bakes, the wrapper, locks and
these notes; it contains no controller or capture framework.

## FK authoring scope

The main cut through .55 is9fbc. After that, upper-arm and forearm **bone
directions** are authored relative to the source chest frame: low elbow/right-side
hand, axial-roll relaxation and a softly neutralizing local wrist. Wrist position
and blade orientation are full-FK results. There is no prescribed wrist target,
blade frame, theta curve, hand-derived elbow IK, reach clamp or blade rotation
inside the hand. The 2da9 raised-elbow and earlier ground-penetrating attempts
are rejected comparisons, not inputs to this generation chain.

The continuous candidate passes the three approved local-rotation key poses with
SO(3) cubic curves. It uses dense original controls before .55 and from1.30 onward;
interior keys do not impose zero angular velocity or holds. Only six right-arm
tracks change: Arm, ForeArm, Hand and three upper-arm twist stations. Each track
reuses its original time accessor and byte-copies output samples through .55 and
from1.30 through the end. All original aliases and BIN are unchanged prefixes.

Body/pelvis XYZ, legs, free left arm, finger local motion and total1.5333333s timing
remain original. The9fbc rig/skin/weights are unchanged (68 skin joints,8 influence
attributes); the grip frame and equipment quaternion0 remain fixed. The three
twist stations distribute arm roll without changing bone lengths. The blade and
right-arm trajectory after .55 intentionally differ from9fbc; main-cut or contact
results cannot be blindly extended into that new recovery.

## Recorded review boundary

The frozen normal and wrist previews each had93 ordered frames at60 source
samples/s, encoded1.55s including the endpoint. Import used120Hz with optimizer
and compression disabled. Image and encoded-video barcodes were continuous.
These were offline sampled previews, not actual-input combat or performance
tests. The imported mesh reported8 weights per vertex. Native main-cut blade-tip
difference from9fbc was about2e−7m, body sample positions were unchanged, and the
actual complete blade mesh stayed at least .3897m above the preview ground.

The high-elbow/crowded-arm defect of2da9 and the long palm-up platform were not
seen in the inspected new recovery. That does not establish final weight,
collision clearance at every interpolation time, stance transitions or combat
quality. The current local evidence is separately frozen under
`/private/tmp/wenfeng-dao-k-fk-full/`; it is not a reproduction dependency.

This wrapper produces no runtime library. The parent library builder can now
reproduce the frozen isolated GameK resource, without the old `/tmp`-specific
script:

```sh
python3 -B tools/xuchu_ual1_lab/build_k_resource.py \
  --source-glb /tmp/xu-fk-recovery-assets/xuchu-dao-k-fk-recovery.glb \
  --baseline /tmp/xu-fk-recovery-assets/xuchu-dao-k-fk-recovery.glb \
  --variant fk_trial --output-dir /tmp/xu-fk-game-k
```

Both inputs must be the identical50eb model. The builder verifies the GameK
binary SHA `16edc9f4b3a2e70e12040eaad2c0156078b097a373f8d6720b0ec338c3ddeb0d`
and sidecar SHA `06ce586f0e7fd713d07f7bc7c9ce83f999db4a699de15c601167adbef57ce1d8`
before writing. Its import stub uses120Hz, keeps immutable tracks and disables
optimizer/compression, matching the frozen runtime trial. The main character
import needs those same settings; the original production30Hz import is not
equivalent. This command does not copy, patch, build or deploy a game project.

Any later isolated runtime experiment must explicitly retain the
matching9fbc rig/skin and grip frame; this clip must not be imported onto the
old65-bone model. UAL1 motion keeps its existing CC0 provenance; the user-provided
Xu model/texture and original target animations do not become CC0.
