# Combat presentation references — 2026-10-24

These are visual and design references, not asset sources. No models, animations,
textures, video frames, audio or logos from these games are distributed with this
project. The runtime uses only the existing Kenney CC0 textures and original
procedural meshes. All values below are this project's own tuning.

## Primary material actually inspected

- **Elden Ring:** [Bandai Namco's combat guide](https://www.bandainamcoent.com/es_mx/news/elden-ring-introduction-part-4-combat-guide)
  describes weapon-specific moves, committed heavy attacks and charged animations.
  The [official product page](https://en.bandainamcoent.eu/elden-ring/elden-ring)
  links a [10-second gameplay feature clip](https://static.bandainamcoent.eu/video/eldenring-kf-03-animated-new.webm).
  Selected frames at 0.3, 1.0, 1.7, 2.4, 3.1 and 3.8 seconds were decoded and
  inspected locally, followed by a closer 0.45–2.10 s sequence at 0.15 s intervals.
  In that excerpt, the blue sword gathers overhead around 0.60–1.65 s and swings
  around 1.80–1.95 s; the clip cuts to another shot by 2.10 s. The initial six-frame
  contact sheet contains multiple shots and is not a continuous attack study.
  The blue sword/casting examples have a concentrated bright
  core, a coloured body and sparse surrounding points; the character silhouette
  remains legible. This is an observation of selected frames, not a frame-by-frame
  analysis of the full game's combat or a claim about its internal VFX methods.
- **Clair Obscur: Expedition 33:** [Sandfall's creative director on PlayStation Blog](https://blog.playstation.com/2024/08/28/new-clair-obscur-expedition-33-gameplay-fighting-and-exploring-the-flying-waters-region/)
  explains precise reactive timing, distinct character abilities and Gustave's
  charged release. [Epic's interview with Sandfall's technical lead](https://www.unrealengine.com/developer-interviews/inside-the-development-journey-of-clair-obscur-expedition-33)
  discusses coordinated polish of animation, camera and VFX. The combat screenshot
  linked in that interview was inspected: fragments and ground-level dust frame
  the contact, with darker surrounding space preserving the fighters' poses.
  The embedded video was not viewed; no claim is made about its unseen frames.
- **Black Myth: Wukong:** [NVIDIA's official technology article](https://www.nvidia.com/en-us/geforce/news/black-myth-wukong-full-ray-tracing-dlss-3/)
  describes semi-transparent attack/explosion/fire particles and their reflections.
  The [official particle comparison](https://www.nvidia.com/en-us/geforce/comparisons/black-myth-wukong-full-ray-tracing-dlss-3-comparison-003/)
  screenshot was inspected. Its small hot contact points, directional fine streaks
  and broad areas of dark, unobscured environment give the effect contrast and
  depth. The current WebGL game does not reproduce its ray tracing or rendering
  fidelity, and no official gameplay video is claimed as watched here.

## Project-specific adaptation

The following choices are inferences for this game's smaller models and browser
renderer, rather than statements about those games' proprietary implementations.

1. Replace a static full-bright crescent image with a 36-segment curved blade
   surface. A leading edge scans across the surface, leaving an irregular eroding
   wake. Its dark shoulder and saturated character colour use normal alpha
   blending, so pale sand does not bleach the entire blade white.
2. Give a thrust two narrow tapered planes and a separate forward pressure mist.
   A slash gets tangential mist instead. Current hit shape determines blade or
   lance presentation; `chase` alone never implies a thrust.
3. Keep the sharp contact beat separate from the release. Only a real impact
   event emits a local directional cut (0.14 s), a tiny light core (0.085 s),
   sparks (0.30–0.40 s) and, for a heavy hit, soft fragments/dust (0.58 s).
4. Intermediate skill strokes use a 0.23 s blade lifetime and 0.72 presentation
   power. The final stroke uses 0.30 s / 1.0 power, a faster leading edge and a
   denser coloured crest, followed by a 0.48 s pressure wake. Damage and attack
   timing remain owned by the existing fighter state machine.
5. Real weapon trails use the actual blade-base/tip history, a textured
   cross-section, normal alpha blending and a 0.11 s squared fade. They are not
   broad opaque quads, screen flashes, enlarged attack circles or fake impacts.
6. Every skill/contact layer shares the existing 24-mesh budget and material
   pools. Shader animation uses the pausable owner's `effect_time`, not global
   `TIME`. No depth-texture particles, post-process bloom or paid asset pack is
   required.

Visual verification must compare windup, the actual strike and the settling phase
in both the duel and the RPG. The reference images remain temporary analysis
files and are not included in the website source or exported game.

## Signature move presentation

The later six-character revision replaces the old spear/crescent and mounted
weapon-only presentation branches. `presentation_profile()` combines the real
skill profile with its current hit, including `fx_style`, `shape`, `reach`, and
the authored `clip`. The RPG delegates to this same role presentation.

| Character | Presentation tied to the actual action |
| --- | --- |
| Zhao Yun | Narrow needle strokes at the actual high/low `Dragon*` clip height; a sideways departure echo and short airy wakes; separate beats for the two/five real thrust contacts. |
| Ma Chao | Low, heavier couched spear core; forward compressed dark pressure; one long charge and one committed breakthrough, without a roar or radial light ring. |
| Guan Yu | Low sweeping edge, reversed dragging-return edge, then a diagonal split and a travelling full-body revolving edge. The revolving wake scans over time instead of displaying a complete luminous circle. |
| Zhang Fei | Narrow forward bracing preparation, rooted counter-thrust, the distinct radial voice-pressure fans, then a separate anchored long thrust. The radial introductory hit never displays a lance. |
| Lü Bu | A rising vertical edge, a broad close orbit, then distinct lift/spin/drop surfaces, selected from the actual per-hit style and contact shape. |
| Xu Chu | Close diagonal mass after the shoulder step, a shorter guarded rebuke, and a broad descending execution edge followed by a forward ground fissure and local settling debris. |

The leading edge samples `blade_base()` and `blade_tip()` for its initial 0.08 s.
The thrust axis follows the actual weapon, and the generated stroke's endpoint
coincides with that frame's blade tip. A pre-render synchronization resolves the
latest AnimationPlayer/SkeletonModifier pose; the remaining wake then stays in
world space. Preparation particles converge toward the actual blade midpoint.

For inspection, each role layer records `fx_style`, `emitted_stage`,
`contact_shape`, and, for a blade stroke, `weapon_clip`, `blade_base`, `blade_tip`
and `visual_blade_tip`. `complete` removes attached preparation cues but allows
finite released layers to settle; `cancel` still removes every layer owned by
the interrupted cast. Real contact bursts remain separate, ownerless events.

### Duel Boss-flow pass, 2026-10-26

Primary references located again: Game Science's official pre-alpha gameplay
https://www.youtube.com/watch?v=oRLhCxC886o and final trailer
https://www.youtube.com/watch?v=bzyMLoSwYvk ; NVIDIA's official article
https://www.nvidia.com/en-us/geforce/news/black-myth-wukong-full-ray-tracing-dlss-3/ .
The article was readable. The official YouTube player could be opened but returned
an error instead of decoded video (readyState0 / durationNaN); no successful
continuous viewing of those clips is claimed. GameSpot's own boss gameplay page
https://www.gamespot.com/videos/black-myth-wukong-new-boss-gameplay/2300-6464516/
was behind a human challenge; Steam showed its age gate. Neither was bypassed.
Reference pages are research links, not asset licenses or packaged media.

Current changes derive from directly observed defects in our own continuous
native capture: spear contact prematurely switched to Idle during the attack
state, recovery inputs were lost, and the foot opponent repeated near-static
close stabbing. Authored recovery continuation, whole-body source timing,
phase-linked foot steps, readable AI pressure/reposition, separately smoothed
shoulder framing and real traveling special entities address those observed
issues. Their implementation is our project-specific interpretation; it is not
a claim about Game Science's private implementation or equivalent AAA fidelity.
