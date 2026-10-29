# Frozen K-only runtime experiment

This patch is for review/reproduction of the isolated raw/support K tests.
It is **not a release patch**. Run→K, SwordIdle→old J/walk and K→Hit have
visible foot/stance discontinuities. The current lab does not repair them.
The complete continuous-combat quality target remains unfulfilled.

**Subsequent visual rejection:** the raw/support K below cuts with the thick
back of Xu's actual single-edged saber. Their mechanism checks did not test
the real edge/face orientation and do not accept this action. Preserve this
patch only as a reproducible rejected control. Rotating the equipment150°
only during K introduced visible weapon self-spins on transitions; applying
that roll permanently reversed the previously correct J1/J2 cuts. Both
approaches were rejected. The later arm/twist-rig trial is a separate asset
and must not be described as the result of applying this patch.

The patch was made against stable runtime commit
`3fd0a4c392d8ff493b46e19b0670547e30edfb86`. `K-PROTOTYPE-pins.json` records
pre/post script and original character hashes. Use an isolated copy of that
Godot project outside this repository, without its `.godot` cache. Do not
apply it to the production project or a different later baseline.

After making such a copy at `/tmp/xu-k-lab/godot`, check the baseline pins
and dry-run the patch. Commands below are from `sites/wenfeng-web`:

```sh
patch --dry-run --batch --forward --fuzz=0 -p1 -d /tmp/xu-k-lab/godot \
  < tools/xuchu_ual1_lab/K-PROTOTYPE.patch
patch --batch --forward --fuzz=0 -p1 -d /tmp/xu-k-lab/godot \
  < tools/xuchu_ual1_lab/K-PROTOTYPE.patch
```

Prepare the two local assets using this lab's `prepare.py`. Build one explicit
K animation library from them; this command writes only a new outside folder:

```sh
python3 tools/xuchu_ual1_lab/build_k_resource.py \
  --source-glb /tmp/xu-ual1-assets/xuchu-ual1-support-art-trial.glb \
  --variant support --output-dir /tmp/xu-k-library
```

For the raw control use `xuchu-ual1-sword-raw.glb` and `--variant raw`.
Expected GLB/sidecar hashes are respectively:

| Variant | GameK library | Sidecar |
| --- | --- | --- |
| raw | `9dacd7fce44e393637cb57be06e0f90939c25a3cbf2a3893754b9a41591b0ee7` | `931475feb541a655e9a20992665f87f75d40517fa220926b472931e12bc37306` |
| support | `71bb8fcb39c95685348a6a2932dd83de7b0b174d26455a9a66f5009c7210edcc` | `e2ada4e552bddcb97d101dc2bdb09b57417d711e584900c981d71203a6542bf7` |

Manually copy the three generated `xuchu_ual1_k.*` files into the isolated
project's `assets/motion/`. The `.import` file specifies120Hz and disabled
optimizer/compression at that intended resource path. The main Xu GLB and
all27 original clips remain unchanged; only the new K/Idle animations are
loaded from the separate resource. Then explicitly import/run the lab:

```sh
Godot --headless --path /tmp/xu-k-lab/godot --import
Godot --path /tmp/xu-k-lab/godot
```

No tool in this lab runs those commands, copies a game or applies the patch
automatically. The asset builder does not touch a runtime project.

## Mechanism and evidence

Only foot Xu plus his saber opts in. K plays the whole1.5333333s source at1x,
with .35–.55s active, original base36 damage/cost32/heavy rules and the existing
saber multiplier. Hips XZ deltas have one CharacterBody owner; source Y stays
in animation. No default forward lunge, automatic jump, retiming or new J
source is added. This extraction of in-place pelvis motion is not an authored
root-motion lunge.

K advances pose, moves, syncs the hand socket and synchronously resolves the
current strict blade before updating `previous_tip`. The original actor
order is retained. Hit/reset clear ownership; no second K starts without
another input. The original260ms late-input intention remains valid.

Both raw and support were tested independently with real opponent physics
and AI off. Each had14 limited mechanism/capture checks; K did40.32 once at
1.15/1.7/2.3m, none at6m, heavy attacks blocked rather than light-parried,
real J interrupted K, reset cleared state and a single K was followed by two
actual SwordIdle loops without automatic repeat. Old J's192-frame fixed-phase
control was unchanged. These are narrow results, not combat-quality approval.

The support edit changed actual contact points by about4.80cm/6.06cm at1.7/
2.3m despite unchanged damage/time; it was not assumed to inherit raw contact.
Its14s normal recording contains840 actual frames. Raw additionally has a14s
side recording. Source-action blade samples matched the same-tick final
render to below1µm. Offline footage suppresses wall-clock hit-stop/audio and
does not establish real-time FPS or full audiovisual feel.

The important failed visuals are Run→K rapid foot retraction (about31cm in
one tick), new low SwordIdle→old J stance reset, and K→Hit leg gathering
(about25cm in one tick). The support wrist edit leaves those body motions
unchanged. Neither green mechanism checks nor one coherent strike accepts
these transitions. Reports, clips and traces are retained under the ignored
`qa/combat-quality-2026-10-29/ual1-k/` folder.
