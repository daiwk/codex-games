"""Check native mechanism evidence, never motion quality or global balance.

Run the repository's validate_native_capture.py separately for image integrity.
"""
from pathlib import Path
import argparse
import json
import math


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    data = json.loads(args.trace.read_text())
    if not data["suite"].startswith("two_dynamic") or not data.get("defender_physics"):
        parser.error("Use the actual dynamic-defender experiment capture")
    failures, errors, contacts = [], [], []
    comparable = 0
    for attempt in data["strike_attempts"]:
        frame = data["frames"][attempt["frame"]]
        tick = frame["physics_frame"]
        if attempt["physics"] != tick or attempt["profile"]["source_sample_tick"] != tick:
            failures.append([attempt["frame"], "source/request clock differs from visible physics tick"])
        if frame["player"]["bone_sample_physics_frame"] != tick:
            failures.append([attempt["frame"], "final modifier observer is stale"])
        if attempt["registered_contact"]:
            contacts.append(attempt["distance"])
            if attempt["distance"] > .430001:
                failures.append([attempt["frame"], "registered contact exceeds unchanged strict geometry gate"])
        # A synchronous parry changes the rendered pose to GuardBreak. That is
        # real feedback, not evidence that the preceding source hand was stale.
        if (attempt["player"]["state"] == frame["player"]["state"] == "attack"
                and attempt["profile"]["clip"] == frame["player"]["clip"]):
            comparable += 1
            errors.append(math.dist(attempt["blade_tip"], frame["player"]["blade_tip"]))
    if not comparable or max(errors, default=0) > .00001:
        failures.append([None, "same-pose request tip differs from final visible tip"])
    seen, damage = set(), {}
    for event in data["source_events"]:
        if event["kind"] != "source_beat_contact":
            continue
        key = (event["fixture"], event["target_id"], event["source_beat_id"])
        if key in seen:
            failures.append([event["frame"], "same target contacted twice in one beat"])
        seen.add(key)
        profile = event["last_melee_hit"]["data"]
        actor = (event["fixture"], event["target_id"])
        damage[actor] = damage.get(actor, 0) + profile["damage"]
        if damage[actor] > profile["source_stage_damage_total"] + .000001:
            failures.append([event["frame"], "per-target declared beat damage exceeds original C budget"])
    result = {
        "passed_mechanism_checks": not failures,
        "failures": failures,
        "same_pose_tip_comparisons": comparable,
        "max_used_vs_visible_tip_error_m": max(errors, default=None),
        "registered_contacts": len(contacts),
        "max_registered_capsule_axis_distance_m": max(contacts, default=None),
        "unique_per_target_beats": len(seen),
        "same_outcome_budget_only": True,
        "mixed_reward_warning": "Block then full parry can grant 20.571429 C energy, exceeding old single parry18; no cross-outcome cap",
        "limitations": "Does not approve the rejected animation, sole support, hurt volumes, presentation, capture images or global mixed-outcome balance",
    }
    output = args.output or args.trace.parent / "mechanism-verification.json"
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
