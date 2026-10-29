# UAL1 raw single strike and local follow-through art trial

These are **two unaccepted asset experiments**, not runtime replacements or
combat-quality approval. The source is the repository's UAL1 Standard
**non-root version**. The raw retarget keeps its authored pelvis XYZ; this
tool does not extract controller displacement or integrate attacks.

Both controls were subsequently rejected for a visible single-edge error:
their main downcut leads with the saber's thick back. Exact reproduction
does not make either action usable. See `K-PROTOTYPE.md` for that failure
and the rejected equipment-roll fixes. `dao_k_trial/`, when present, is the
separate redesigned-arm candidate; it does not turn these controls into
accepted animations.

From `sites/wenfeng-web`, with Python/NumPy/SciPy/Pillow available:

```sh
python3 tools/xuchu_ual1_lab/prepare.py --output-dir /tmp/xu-ual1-assets
```

The output must be a new directory outside the repository. Existing output
directories are rejected, and all input files remain read-only. Optional
`--source`, `--baseline` and `--manifest` paths must still match `locks.json`.
The wrapper only runs the two local asset bakes. It does not download, launch
Godot, capture, build, write runtime resources, deploy or commit.

Frozen inputs:

- UAL1 source `69591853d817488edaa8fd9bf8fc1d821eaeaf789f8627b3cd23b41c4ed67997`.
- Original Xu model `89f369ccbfce8b5ecd4735ed5f4a18467d23ca4dfc9ec684f51b9c7c30dad43c`.
- Animation/grip manifest `3182fe59c2175d820cacccfe70f97e6b0bb2bfbc170d0682011307d024eec6b0`.
- The existing `prepare_polearms.py` and `gltf_tools.py` hashes are also locked.

The numeric bake retains the original `library_mapping('ual2')` call: UAL1
and UAL2 here share that bone schema. Do not rename the mapping or rewrite
its semantics while reproducing these assets.

Outputs are only:

- `xuchu-ual1-sword-raw.glb`, expected SHA
  `e19e3cbbf4c78146c6a34980189c40ef2e0c5445673612ae7a14401078179106`.
- `xuchu-ual1-support-art-trial.glb`, expected SHA
  `b3d35d9459e3f59820a4560e551fc7d8a6cfaa952d1a1632af72c7ebe4eef4e5`.
- Raw/art metadata, a reproduction record with dependency/input/output hashes,
  and snapshots of the existing CC0 license, source note and baseline manifest.

CC0 applies to the archived UAL1 animation source. The Xu model, texture and
original target clips are user-provided repository material; these bakes do
not change their rights or relabel the entire derived character as CC0.

The wrapper verifies both GLBs byte-for-byte and rechecks the input hashes.
On dependency/platform differences, a hash mismatch is a failure to inspect,
not permission to install a different result. Metadata records actual local
paths, so metadata bytes need not match an earlier temporary directory.

## Raw retarget

`Sword_Attack` is1.5333333s/185 samples and `Sword_Idle` is1.6666666s/201
samples, both at the unchanged source rate resampled to120Hz. Whole-body
rotations and authored finger motion are retargeted with a static T-pose
correspondence. Foot/Toe use one `Sword_Idle0` to original target `Idle0`
reference. Both clips share one constant body Y from that reference; there
is no per-frame grounding, foot planner, IK, wrist clamp or timing edit.
Original target geometry, bind data, animations and binary prefix remain.

## Explicit local art change

The art file appends `XuUAL1SwordAttackSupportTrial`; it retains all original
raw aliases and binary data. Only the right Hand rotation track changes:
in the .40–1.0s follow-through, deep palm flexion is reduced smoothly by at
most18°. Source forearm pronation is retained. Body/legs, elbow and wrist
joint positions, source timing and pelvis curves do not change. Authored
finger local motion remains, but fingers follow the newly oriented palm.

**Palm and knife orientation are intentionally changed.** Native comparison
of this exact trial measured up to **.347818m (34.8cm) blade-tip displacement**.
It therefore does not preserve the raw blade path and cannot inherit raw
contact, hit-window or damage results. Keeping the wrist joint point does
not keep the attached knife tip. The18° edit is not a general anatomical
constraint; residual deep flexion remains. Raw and art both still require
separate visual and, if used in a game, actual blade-contact acceptance.

No animation-quality, footwear-support, final wrist posture or production
adoption conclusion follows from exact byte reproduction. There is no
capture framework or full Godot project in this lab.

`K-PROTOTYPE.md` separately documents a frozen, isolated K-only runtime patch
and the explicit animation-library builder. Its blade direction and stance transitions failed
visual review; it is retained for review/reproduction, not installation.
