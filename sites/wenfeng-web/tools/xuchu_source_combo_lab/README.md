# Rejected-source combat mechanism lab

UAL2 Full was rejected for the final ordinary J animation after source and
target footwear review. This lab preserves only a reproducible experiment:
one source-family input chain, extracted pelvis displacement, two independently contacting
J3 beats, same-tick drawn weapon sampling and strict blade contact. It does
not approve that animation or replace any shipped runtime file.

`prepare.py` reads a stable Godot project and the explicitly supplied local
rig-lab `d940` model. It verifies `locks.json`, copies the project to a **new
directory outside the repository**, applies `experiment.patch`, and appends
game aliases/root data. It never downloads, launches Godot, opens a native
window, builds, deploys or commits. No experimental GLB is stored here.

## Prepare local inputs

Requires Python with NumPy/SciPy and a local `patch` executable. The stable
runtime is commit `b510af2`; the current checkout can be used only while its
locked scripts, grip manifest and models still match. If they change, use an
isolated copy of that commit's `sites/wenfeng-web/godot` as `--baseline`.
The wrapper also locks the repository's existing `tools/gltf_tools.py`.

The rig input is the output of the existing offline
`tools/prepare_xuchu_ual2_lab.py`, using its documented local source/baseline
inputs. Its exact name is `xuchu-ual2-family-recoveries.glb`, SHA256
`d940035cc72829f37b277dfdefef60e5a6c5d90513fa38ab39028e306d4b7e76`.
This lab does not rerun that costly rig solve automatically. See
`../xuchu_ual2_lab/README.md` for source, license and rig reproduction.

From `sites/wenfeng-web`, explicitly prepare an isolated project:

```sh
python3 tools/xuchu_source_combo_lab/prepare.py \
  --rig-glb /tmp/xu-rig-lab/xuchu-ual2-family-recoveries.glb \
  --output-dir /tmp/xu-combo-lab
```

The expected resulting model SHA is
`b5318e4987623aa6888938d6c5087b474241b539a689ff3eddcaf7ba6f87b58a`.
The accepted Zhao model stays
`23ba8aabd2bafa6d06ff9332008b1828fa27d1d56d9f1def85ea0acc3dfafe29`.
The output has input/output hashes and the complete motion sidecar. The
zero-context unified patch is guarded by exact pre/post file hashes and
`--fuzz=0`; it is not a patch for an arbitrary later runtime. Existing
nodes, meshes, skins, eight-influence weights, animations and binary prefix
are retained from the rig input. Import parameters keep120Hz animation with
optimization/compression disabled; no per-frame leg correction is added.

## Explicit tests and recordings

Godot4.7.2 was used for the recorded experiment. These commands are manual;
the prepare wrapper does not execute them. `Godot` below is your executable.

```sh
Godot --headless --path /tmp/xu-combo-lab/godot --import
Godot --headless --path /tmp/xu-combo-lab/godot --fixed-fps 60 \
  --script res://tools/xuchu_source_combo_lab/combat_cases.gd -- \
  --output=/tmp/xu-combo-lab/combat-cases.json
```

Fresh-import note: one initial complete-project `--editor --quit` invocation
crashed in a Godot worker during xuchu reimport. With no cache, two minimal
b531 projects (the rig lab's parameters and this package's full parameters)
imported successfully using `--import`; a separately newly prepared complete
project also imported successfully with `--import` and ran the1.7m smoke
fixture for75.04 damage with two C contacts. Use the explicit wait-for-import
command above. This records a successful fresh path, not a proven diagnosis
or fix for the engine crash. The original failure is retained in ignored QA.

`--quick` runs only the1.7m JJJ smoke fixture. The complete18-case run uses
J/JJ/JJJ at1.15/1.7/2.0/2.3/6m, held guard and parries of each C beat.
Both actors have real physics; AI is off. Hit-stun, retreat and recovery are
recorded, including natural whiffs. Input uses the original Main intent
consumer. It is an offline simulation, not an input-latency benchmark.

Native recording opens a diagnostic window only when explicitly invoked:

```sh
Godot --path /tmp/xu-combo-lab/godot --disable-render-loop --fixed-fps 60 \
  --script res://tools/xuchu_source_combo_lab/capture_dynamic.gd -- \
  --role=xuchu --camera=normal --seconds=27 --suite=two_dynamic \
  --tag=split28 --source-commit=b510af2 --output-root=/tmp/xu-combo-lab/native
```

For the side schedule use `--camera=side --seconds=15
--suite=two_dynamic_side`. These use production bridge dispatch and original
Main input consumption, a forced SubViewport render, frame barcodes and a
final modifier-tail bone observer. Fixture resets are marked; each chain
within a fixture is continuous. Audio/hit-stop are suppressed for the offline
diagnostic. Use the existing validator (Pillow/NumPy/ffmpeg required):

```sh
python3 tools/validate_native_capture.py \
  /tmp/xu-combo-lab/native/xuchu-normal-two_dynamic-split28-27s --encode
python3 tools/xuchu_source_combo_lab/verify_trace.py \
  /tmp/xu-combo-lab/native/xuchu-normal-two_dynamic-split28-27s/trace.json
```

The trace verifier checks sample/visible physics ticks, same-pose used versus
drawn tips, strict contact distance, per-target beat uniqueness and declared
C damage. A synchronous parry legitimately changes the final render pose;
those pose comparisons are excluded and the interruption remains visible.
Neither validator accepts animation quality, sole support or global balance.

## Mechanics and balance limits

J1/J2/J3 cut Full at0/.433333/1/3s. Real inputs decide continuation; absent
buffer selects the genuine A/B recovery. Late new-J intentions expire after
260ms of source time. One owner moves the CharacterBody from source Hips XZ;
source Y/rotations remain in animation. Normal attack tempo/lunge smoothing
is bypassed only for the source opt-in. The hand socket is synchronized after
manual animation advancement and movement, before the synchronous strike
signal and before updating `previous_tip`. Strict source blade/capsule
contact uses the unchanged radius+.07m gate; no close-slash fallback applies.
The archived official source is the non-root-motion export; these extracted
pelvis deltas do not establish an original authored forward-lunge trajectory.

J3 has Full windows1.15–1.31s and1.54–1.68s. Base damage12+16 keeps28
(saber13.44+17.92). Each beat can contact each target once. Same-outcome
budgets split guard24 as10+14, block energy6/3 and evade9 by damage share,
nominal stun .10+.20s, hit velocity .5+1.1m/s and block velocity .3+.5m/s.
Assigned velocities are not equal displacements: the observed split retreat
is about4.8cm, versus about9.3cm for a default1.6m/s contact. The .10s/.20s
hit states are separated by about .267s when the defender can act.

Both beats stay nonheavy/parryable. Parry keeps the full18 energy/13 stamina
reward and .70s attacker stagger; skill guard keeps the full10 counter reward.
Either counter synchronously interrupts the remaining source chain.

**Mixed defense rewards are not globally capped.** Blocking C's lift then
parrying its downcut grants2.571429+18 =20.571429 defender energy, exceeding
the old single parry18. The attacker also retains1.285714 earned on the first
block. This explicit unapproved balance change remains; no cross-outcome
cap was added for a rejected source. Do not describe every total budget as
unchanged. Successful physical evade/skill-guard captures, guard-break
balance, hurt volumes during the source crouch/jump, walls, mixed jump inputs,
moving-opponent tactics and final audiovisual feel remain unaccepted.

The complete42s footage, traces, numeric cases, resource/control report and
source hashes are archived in the ignored
`qa/xuchu-source-combo-2026-10-29/` folder. They are evidence, not release
assets. No publication or deployment is part of this lab.
