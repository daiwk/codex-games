# Xu source-K preparation interruption experiment

**Frozen experiment; not release accepted.** The complete body/weapon audit still
finds non-grip hilt/shoulder intersections inherited from the original preparation.
Neither this trial nor the whole50eb K family is installed in the canonical game.

The old50eb integration changes from a side-on sword stance directly into the old
front-facing Hit. Its actual K interruption has a large foot/hand reordering. The
first compatible-Hit experiment blends the incoming pose back to SwordIdle within
the original Hit duration and adds the original Hit's local pose delta. This
reduces the jump but sends the saber into the ground. Removing the old Hit delta
from the weapon arm still fails: the straight local-rotation interpolation itself
takes the raised blade through the ground and right-leg armor.

This third experiment reuses the **real imported GameK preparation FK route** for
the right-weapon branch instead: source time returns from the interrupted time
to0 as the reaction progresses. It never reverses the actual cut. Scope is only
source-K time.075–.30s; .30 is where the authored cut starts, and the initial75ms
entry blend is excluded. A further local-pose identity guard opts out if the
incoming weapon branch does not match that pure source sample. Ready, active
cut/recovery, other branches and unsupported entries retain legacy handling.

The rest of the reaction retains the previous trial: incoming-to-SwordIdle body
base, original Hit-relative local rotation/hip delta, original Hit duration and
CharacterBody knockback. It cancels queued K motion/strikes and returns to the
existing SwordIdle. Source clips, weapon grip, role models, gameplay damage,
root trajectory and input remain unchanged. Only the right branch route differs
from v2; the other41 bone matrices match throughout the measured reaction.

## Reproduction boundary

`integration.patch` targets the **frozen isolated50eb K runtime**, whose exact
script/resource hashes are in `locks.json`. It is not a patch for the canonical
Zhao WIP. The parent `K-PROTOTYPE.patch` and FK asset/library builders describe
that separate runtime; source model/library must be50eb/16ed with120Hz import,
immutable tracks retained and optimizer/compression disabled. Verify every
baseline hash before manual copying or applying anything.

In that isolated Godot project, dry-run the zero-context patch with
`git apply --check --unidiff-zero -p1 integration.patch`, apply with the same
options, then copy `xu_family_hit.gd` into `scripts/`. The helper alone is not a
complete game. This folder does not copy a checkout, install assets, capture,
build, commit or deploy. No temporary file/movie is a generation input.

## Actual recorded result and rejection

One unchanged14s/840-frame input sequence, real opponent physics, Hit at source
K time.266667s. Commands, all events, HP/state/action clocks and root trajectory
match the old50eb input run. Actual frames before Hit are unchanged. New entry
matches the actual incoming pose to floating-point precision; the normal75ms
exit handles the nonzero GameK0-to-SwordIdle endpoint difference. No claims are
made about untested windup times, NPC/modes or real-time Web performance.

The earlier floor/leg cut is removed: all11189 saber vertices remain at least
.71407m above ground in the recorded Hit/recovery. Independent CPU skin audit of
all16889 body faces at F724–756 finds no blade-surface(localY>=30) crossing,
including head/shoulders/arms. It does find hilt(localY<30) crossings with
non-grip shoulder/chest armor in preparation and early reaction; F736 has a
1.887cm intersection segment. This is not a penetration-depth measurement.
Original preparation already has the same defect, so source preservation does
not approve it. Normal-frame review also finds limited heavy-weapon inertia.

The trial remains unaccepted. Run→K and other K exits are still known failures.
Full clips, original input driver, final-pose geometry and reports are retained
locally in ignored `qa/combat-quality-2026-10-30/xuchu-family-hit-v3/`.
