# Two-hand parry weapon-frame experiment

**Mechanism prototype only. Real torso intersections remain. Do not install as a
release or describe this as the requested final combat quality.** Baseline:
`b2a1f43` on the development branch. Production main/Sites are unchanged.

This is a frozen, rejected experiment, including a known missing fitting-axis
assignment before the contact IK's round-grip solve. It is retained for exact
reproduction of the recorded result, not as a recommended implementation.

The current 60ms attack→GuardBreak local-bone crossfade shrinks the two-palm gap
and creates a large shaft overshoot. Pure imported GuardBreak has no equivalent
single-tick flip. This experiment interpolates one rigid weapon frame, its palm
span and hand-relative orientations, then solves the two actual arms with the
existing wrist limits. Hips, torso and legs remain the original animation output.
The collision/gameplay clock is unchanged. IK failure restores the old arm pose;
there is no detached visual weapon or fabricated successful result.

`parry_frame_source.json` is sampled directly from the imported original Zhao
model, without actor scale, modifiers or animation blending. It contains105
Skeleton-space samples at120Hz across the complete GuardBreak. `export_source.gd`
reproduces it from the locked23ba model through Godot's actual importer, because
Python glTF evaluation and the imported resource differ slightly. From the repo:

```sh
Godot --headless --path sites/wenfeng-web/godot \
  --script /absolute/path/to/tools/duel_parry_frame_lab/export_source.gd \
  -- --output=/tmp/new-parry-frame-source.json
```

The output must be new, absolute and outside the Godot project, with an existing
parent. The script reads source/manifest and writes that one file; it does not
install resources, run gameplay, capture, build or deploy. With the recorded
Godot4.7.2 importer, the output SHA is
`064b49d6c1fe9b0492a15f2510a2846ce94e729e657158c726acd2d6b1e3f50d`.
The target model and existing animation rights are not changed by this export.

For manual reproduction only, copy the baseline Godot project outside the repo,
verify `locks.json`, dry-run/apply `integration.patch` with `-p1`, copy
`duel_weapon_transition.gd` to its `scripts/` and `parry_frame_source.json` to
its `assets/motion/`, then explicitly import/run the isolated copy. Nothing in
this directory copies a project or applies the patch automatically. The helper
loads its table during Actor setup and checks the model/table source hash; it
retains the old contact modifier interfaces and flags. This is not a general
multi-character animation system.

The patch has zero context to avoid representing original GDScript indentation
as whitespace errors inside a tracked patch file. With Git, use
`git apply --check --unidiff-zero -p1 integration.patch` before applying with
the same `--unidiff-zero` option. Verify the locked baseline first.

Recorded actual-input evidence, separate from final artistic acceptance:

- Three2.3m timings, defender guard atF12/15/18 after player inputF6. Paired
  control and experiment have exactly identical pre-parry rendered joints.
- Parry-active shaft maximum changes from56.72°/tick to12.07°. Complete clip
  maximum remains20.01° on Idle exit, identical to the control's existing exit.
- All126 parry-active samples solve; palm errors stay sub-micrometre, actual
  wrist limits remain within40° swing/35° twist, unchanged body/leg positions,
  and arm segment length differences below0.9µm.
- Close and side films show reduced overshoot, not final naturalness. The helper
  extraction reproduces the prototype's180-frame gameplay output exactly.

**Geometric rejection boundary:** new F23 has three actual torso-triangle
intersections along the complete rod centreline; the paired control has none at
that sampled frame. AtF25 both have six, so the pure target/source posture also
has a self-intersection problem. Rest/bind equivalence and tail/draw clock were
verified; a simplified body capsule was not used as proof. Unsampled frames and
rod radius are not declared clear. A fixed side-carry adjustment is being
investigated separately, not silently included here.

The fixed-side follow-up is also rejected. Its single constant Skeleton+X shift
is19.4635cm in world space. Although pure-source105-pose centreline tests clear,
the actual mixed native3s clip has21 unsafe samples out of42 active samples;
F27 jumps back about18cm when the IK restores the old pose. Even safe F22 has
five true torso-triangle intersections. The old GuardBreak→Idle output also
intersects at sampled F62/63. Assigning the final shared axis to
`contact._fitting_shaft_axis` before solving both arms fixes that state omission
but still leaves21 unsafe samples; it does not rescue the carry design.

The replacement direction under investigation uses the original Idle's correct
two-hand carry in chest space, rather than translating the incompatible source
GuardBreak hands across the body. The pure-body geometric check supports that
direction; entry/exit, actual skin and visual acceptance still require separate
evidence. No replacement is silently included in these frozen files.

Evidence is retained locally in ignored
`qa/combat-quality-2026-10-30/parry-weapon-frame/` and the temporary native
projects. The recorded tests do not approve chest/hand clearance, all distances,
Idle/Run exits, other characters/modes, Web performance or the full PB0 target.
