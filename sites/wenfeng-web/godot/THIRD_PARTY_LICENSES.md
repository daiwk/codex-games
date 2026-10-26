# 素材来源

## Quaternius 动画

- 作者：Quaternius
- UAL 1：https://quaternius.itch.io/universal-animation-library
- UAL 2：https://quaternius.itch.io/universal-animation-library-2
- 官方说明：https://quaternius.com/packs/universalanimationlibrary2.html
- 版本：两套 **免费 Standard** 版中的 Unreal-Godot / 非根运动 GLB。
- 获取日期：2026-10-15。
- 授权：**CC0 1.0 Universal / Public Domain Dedication**。
- 法律文本：https://creativecommons.org/publicdomain/zero/1.0/
- 作者随包的完整许可保存在 `assets/licenses/Quaternius-UAL1-CC0.txt` 和 `assets/licenses/Quaternius-UAL2-CC0.txt`，也随网页部署在 `dist/licenses/`。

当前素材准备使用 UAL1 的手指握持姿势，并在2026-10-24补入 UAL2 免费 Standard 的 Sword_Dash / Sword_Block 作为许褚专属冲刀、架刀动作来源。对应原件、许可和SHA256保存在 `source-assets/animations/ual1/` 与 `source-assets/animations/ual2/`。腰肩与兵器路径的独立编排由项目离线烘焙工具生成。没有采用付费 Source 版本。

## KayKit 双手动作

- 作者：Kay Lousberg。
- 官方来源：https://kaylousberg.itch.io/kaykit-character-animations
- 版本：Character Animations **Free 1.1**，获取日期 2026-10-18。
- 授权：**CC0 1.0 Universal**，作者随包许可保存在 `assets/licenses/KayKit-CC0.txt`。
- 使用内容：Rig_Medium 的 CombatMelee、General、MovementBasic、MovementAdvanced。
- 赵云、马超、关羽、张飞、吕布使用原包的双手待机、劈砍、横扫、旋斩与突刺；许褚使用单手横斩、斜斩、劈砍、跳劈及格挡动作。保留原骨长，按 T-pose 重定向、校正地面与长兵器握持，再烘焙到运行时 GLB；移动时将双手持械上身与原包步态组合。
- 下载来源、压缩包 SHA256 和原始动画 GLB 保存在仓库 `sites/wenfeng-web/source-assets/animations/kaykit/`。没有使用付费 Source Files。

## 仓库原有素材

赵云、马超、关羽、张飞、吕布、许褚及两把枪、许褚大刀、原刀剑、青龙刀、丈八蛇矛、方天画戟由本仓库用户提供，除按用户要求修正吕布的两个灰色翎尾片面外，原始 GLB 文件未改写；吕布未经修改的原文件另存于 `sites/wenfeng-web/source-assets/originals/`。运行时人物的几何、材质、贴图和蒙皮来自这些原始角色。网页副本使用较小贴图，赵云、马超沿用原网页的单网格、单材质优化以降低绘制批次。原有赵云枪、马超枪已生成网页运行副本，许褚大刀则校准为与旧刀剑兼容的单手握点。

## 本项目生成内容

庭院、山景、旗帜、刀光和命中反馈由 Godot 代码生成；声音为程序合成音效。

2026-10-26 的单挑特殊招式沿用上述免费动作，重新编排武将的动作阶段、步法与出手时序，并以程序实现当前装备的长矛齐射、刀阵、低位矛阵、六戟包夹、三刃回旋和推进压力前沿；没有新增动捕或从商业参考游戏提取资源。六骑阵列用本项目原有马匹、马超与兵器运行副本生成低精度网格，随队小旗为程序网格、蹄尘沿用Kenney CC0纹理，奔跑姿态来自已保留的 Quaternius CC0 Gallop；角色与马匹几何仍属于用户提供素材。生成器、输入/输出 SHA256 和三角形预算记录在 `assets/vfx/duel/SOURCE.json`，详细机制与来源说明在 `source-assets/vfx/duel/README.md`，六将兵器阵列输入哈希见同目录 `ARMY_SOURCE.json`。

## Kenney 特效纹理

- 作者：Kenney Vleugels / Kenney.nl，**Particle Pack 1.1**。
- 作者官网与授权说明：https://kenney.nl/assets/particle-pack （CC0 1.0 Universal）。
- 获取日期：2026-10-24。原包许可完整保存在 `assets/licenses/Kenney-Particle-Pack-CC0.txt`。
- 仅选用透明版 `smoke_07`、`trace_06`、`star_05`、`trace_02`、`slash_02` 五张纹理，用于柔边烟尘、飞散火花、聚能微光和刀枪光痕；网页运行副本缩小为 256 × 256。
- 选中的未修改原始 PNG、原许可、直接下载地址、源包与逐文件 SHA256 保存在 `sites/wenfeng-web/source-assets/vfx/kenney/`。没有把用户提供的角色模型声明为 CC0。

## 中文字体

网页版内嵌 Noto Sans SC 和 Noto Serif SC 的游戏字符子集，使用 SIL Open Font License 1.1。完整许可保存在 `assets/fonts/NotoSans-LICENSE.txt` 和 `assets/fonts/NotoSerif-LICENSE.txt`，并随网页部署在 `dist/licenses/`。未打包系统字体。

## 马匹外观与骑行动作

- Horse / Farm Animals Pack by **Quaternius**, released under **CC0 1.0 Universal**.
- Author: https://quaternius.com/packs/farmanimal.html
- GLB: https://poly.pizza/m/qvTrSG9pZF
- Original FBX/Blend and license: https://opengameart.org/content/lowpoly-animated-farm-animal-pack
- Original files and provenance: `sites/wenfeng-web/source-assets/animations/horse/`.
- 动作来源：上述 Quaternius 马的 Idle、Walk、Gallop，经解剖标定、分腿蒙皮重绑和重定向用于新坐骑。CC0 只适用于此参考素材和动作。
- 当前两匹马的外观来自用户提供的 Tripo 原件 `马_棕色.glb`、`马_白色.glb`；不将这些用户素材声明为 CC0。原始几何、三角形、UV 和贴图归档保留，运行副本仅统一旋转/缩放、重建损坏骨架蒙皮、缩小纹理到 2048。
- 当前运行副本：`assets/mounts/horse_brown.glb`、`horse_white.glb`，配置与原文件 SHA256 见同目录 `manifest.json`；可用 `tools/prepare_mounts.py` 离线复现。
- 参考 GLB、作者许可及解剖标定在 `sites/wenfeng-web/source-assets/animations/horse/`。马鞍外观来自用户提供的 Tripo 原件，原件保存在 `sites/wenfeng-web/source-assets/mounts/`；缰绳、马镫及鞍具适配由本项目生成。
- License copy: `assets/licenses/Horse-CC0.txt`.
