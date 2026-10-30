# Xu anatomical single-hand blade family

Ground Xu Chu's J/Q/E/U use the archived **Quaternius UAL2 Standard** CC0 animations: `Sword_Regular_Combo`, A/A_Rec, B/B_Rec, C, `Sword_Block`, and `OverhandThrow`. Original character geometry/materials belong to the user. No commercial reference game's motion is included.

Run from `sites/wenfeng-web`, with NumPy/SciPy available:

```sh
python3 tools/prepare_xuchu_blade.py
```

The wrapper checks the unchanged 50eb character and archived 8cee UAL2 input, builds static anatomical correspondence (5ee4), fits source foot contacts to the existing unequal leg proportions (16bd), then compiles the ten gameplay clips (1209). Every intermediate/output SHA is checked. The independent compiler verifier compares all 1,346 serialized source samples and root curves. Temporary files are removed only after validation succeeds.

Shoulders, elbows, wrists and finger rotations retain anatomical source correspondence. There is no weapon-driven arm IK, wrist clamp, shaft-roll search or independent upper-body retiming. Real parent-to-child leg axes and original segment lengths are used. Source foot XZ/orientation and raised soles are preserved; animated soles below the flat floor are constrained to the floor. Two-bone legs and the nearest feasible pelvis Y handle the character's shorter calves. The source Combo's low single-leg finishing stance remains; this is not a newly generated step cycle.

J1 and J2 use source Combo main segments plus the matching authored recovery. Early input selects the next continuous Combo segment; late input finishes recovery and starts a fresh J1. J3 includes the original finisher and recovery. Runtime holds skeleton Hips XZ at one common anchor, applies source root deltas through collision-constrained `CharacterBody3D`, and samples the whole pose on the same action clock. K and Zhao Yun's accepted locomotion assets are unchanged. Entering J from an unrelated stance first settles into the family Ready pose over 180ms.

## Fixed equipment frame

The free Standard skeleton has no weapon socket. The [official UAL2 viewer](https://quaternius.com/animviewer.html), linked from the [official pack page](https://quaternius.com/packs/universalanimationlibrary2.html), includes a genuine static `RightHand → Sword` attachment. Its blade-plane normal in the reference hand is approximately `[-.00264356, .02359714, -.99971785]`. Transfer through the same reference correspondence and project perpendicular to the existing round-hilt axis:

```
Qfamily = Q0 * Quaternion(localY, 91.35219431993688 degrees)
```

This preserves shaft, grip point, size and all hand/arm bones. Of the plane's two physically equivalent single-edge polarities, this one keeps the saber's cutting edge below its back in Ready and leads with the sharp edge through both main cuts. The opposite polarity leads with the blade back. No angle sweep or per-clip equipment roll is used. The admitted K keeps its previous Q0; the equipment frame blends during stance preparation, before its cut.

## Throw and return

Q uses the full overhand throw. U uses the same gesture with a three-blade fan released together, then receives the blades individually. This avoids regenerating delayed blades from an empty hand after the follow-through has already dropped below the waist. Count, per-blade damage, fan spread and range retain the existing values; U's release spacing changes to simultaneous for this ground family.

`duel_specials.gd` uses the actual equipped opaque PBR mesh, UVs and world scale. Release samples this physics tick's final palm; the original held mesh stays hidden while blades are outstanding. Incoming blades wait in safe space until the receiving hand is ready, and only an actual handle/orientation match restores the held mesh. Fingers open for release/receiving and close after the final actual catch. Cancellation/reset/death withdraw existing entities through their existing lifecycle, without a fake caught event.

Godot import must retain the authored 120Hz keys, constant tracks and uncompressed rotations. The committed `.glb.import` profile and export preset preserve that configuration.
