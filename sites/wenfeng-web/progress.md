Original prompt: 按上一轮诊断先改《问锋》，认真打磨场景、动作、镜头和特效，做好后部署到原来的 Sites，用户查看实际效果。用户同时授权安装并使用合适的游戏开发、UI 设计 skill。

## 2026-10-28 · 山门秋庭视觉样板

Scope: one detailed foot-combat courtyard; Zhao Yun / Ma Chao normal-combat animation polish; clear shoulder framing; restrained, contact-driven effects; compact readable combat HUD. Preserve all playable roles and mounted mode. No new gameplay systems. Keep the existing Site project identity and audience.

Art direction: weathered blue-grey stone, oxblood timber, curved tiled eaves, moss and autumn foliage, warm low sunlight against cool atmospheric distance. The fighting centre stays clear and level.

Implementation is split by file ownership: arena and environment assets; Duel-only animation aliases; Duel camera and effects; root handles HUD, integration, build and visual QA.

Acceptance: compare real menu/gameplay frames, inspect light combo/heavy/skill/guard/dodge/jump and contact recovery, check lock camera and pause/restart, smoke-test other roles and cavalry. Functional checks supplement continuous rendered motion review. The RPG is not rebuilt or deployed.

Tooling: official Godot 4.7.2 and pinned Web template downloaded to temporary/cache paths. Initial asset/class import completed. New Godot/UI skills are being vetted and installed.

Publication: existing public Site appgprj_6ad22bc314348191a4822de5abd4c9f9. Official source workflow in the sandbox failed DNS. Automatic review rejected sending the temporary source credential to an unsandboxed terminal. Continue local production/verification; resolve the credential boundary before publishing, with a concrete reviewable build available.


### First two rendered passes
- Installed and read godot-gdscript-patterns and web-design-guidelines; applied resource isolation, static batching, browser focus/safe area review.
- Native captures exposed overexposure, overly fine stone detail and a selected character hidden by the menu veil. Revised lighting, stone scale, architecture height and preview positions; a third art pass is in progress.
- Generated an original mountain panorama using the built-in imagegen tool, copied into godot/assets/environment/autumn_court/mountain_panorama.png.
- First actual combat captures used disabled player state by mistake; corrected the QA fixture and re-ran. Verified request_light/request_heavy/request_skill all accepted in second native movie.
- Independent review found a shared shadow setting leak and unsupported-character generator failure; fixes assigned.
- Motion numeric checks passed 72 checks, but angular-speed diagnostics regressed from old baseline; intentionally held for further correction rather than treating functional passes as visual acceptance.


### Final local verification
- Four cardinal directions and actual combat verified in OpenGL; sky wrap seam removed with explicit horizon mapping.
- Final Web release built successfully: 35 static files, approximately 139.36 MB. python3 play.py --check passed compressed length and SHA256 checks.
- Final PCK loaded from an empty folder: all six environment textures, sky Shader, Duel modifier and both new animation aliases present and loadable. Native shutdown retains a small engine resource-cache warning; no corresponding browser error was observed.
- Motion acceptance: 120/120, zero angular-speed limit violations, actual damage retained.
- Camera: 15/15; presentation: 30/30; shared impact feedback: 66/66; environment: 6/6.
- Cavalry: initial 310/312 with two synthetic key-release timing failures preserved. Low-render-FPS probe reproduced 3/4 failures; test-only Input.flush_buffered_events resolved them. Full unchanged assertions then passed 312/312 across68 cases. No production input logic change.
- Official web-game client executed unmodified (temporary module resolution loader only), cover screenshot inspected. Actual final Web gameplay additionally operated in IAB: move, attack, skill, heavy and pause. Browser error log empty.
- Publication resumed: user explicitly approved the official Sites helper using the project-scoped temporary credential in a networked local terminal on 2026-10-28. Source synchronization and deployment are in progress. The original public Site was version15 when publication resumed. Final dist and source edits are retained in this workspace.


### Publication follow-up
- Original Site source safely pushed at 6a0e202d8e7db4dba5042c66ff685193a451778b. Native archive upload twice timed out after300s at the file-blob upload endpoint; no new saved version appeared.
- Reducing release size by excluding only the two original spear models that are absent from all current weapon choices and special prewarming. Canonical original/runtime GLB files remain intact. This changes export contents without changing the visible game. Rebuild and new archive are in progress.
- User also explicitly requested GitHub push. origin/main equals local pre-polish HEAD1410b56; GitHub synchronization is prepared and will push the verified final build.

- Compact release rebuilt from pushed Sites source ad0361e8327f78bbbaeac6cb5e1607032bc24ab5: 34 static files,129.23MB total; PCK115.80MB gzip. Only two unselectable original spear runtime resources are excluded; original source models remain in the canonical repository. Native upload retry of this verified compact archive is pending.
