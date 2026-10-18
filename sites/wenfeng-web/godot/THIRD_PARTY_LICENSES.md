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

这些原始单手动作继续归档保留，手指握持姿势用于当前武将。没有采用付费 Source 版本。

## KayKit 双手动作

- 作者：Kay Lousberg。
- 官方来源：https://kaylousberg.itch.io/kaykit-character-animations
- 版本：Character Animations **Free 1.1**，获取日期 2026-10-18。
- 授权：**CC0 1.0 Universal**，作者随包许可保存在 `assets/licenses/KayKit-CC0.txt`。
- 使用内容：Rig_Medium 的 CombatMelee、General、MovementBasic、MovementAdvanced。
- 赵云、马超、关羽、张飞、吕布使用原包的双手待机、劈砍、横扫、旋斩与突刺；许褚使用单手横斩、斜斩、劈砍、跳劈及格挡动作。保留原骨长，按 T-pose 重定向、校正地面与长兵器握持，再烘焙到运行时 GLB；移动时将双手持械上身与原包步态组合。
- 下载来源、压缩包 SHA256 和原始动画 GLB 保存在仓库 `godot-games/3a-games/source/third_party/kaykit/`。没有使用付费 Source Files。

## 仓库原有素材

赵云、马超、关羽、张飞、吕布、许褚及两把枪、许褚大刀、原刀剑、青龙刀、丈八蛇矛、方天画戟由本仓库用户提供，除按用户要求修正吕布的两个灰色翎尾片面外，原始 GLB 文件未改写；吕布未经修改的原文件另存于 `source/originals/`。运行时人物的几何、材质、贴图和蒙皮来自这些原始角色。网页副本使用较小贴图，赵云、马超沿用原网页的单网格、单材质优化以降低绘制批次。原有赵云枪、马超枪已生成网页运行副本，许褚大刀则校准为与旧刀剑兼容的单手握点。

## 本项目生成内容

庭院、山景、旗帜、刀光和命中反馈由 Godot 代码生成；声音为程序合成音效。

## 中文字体

网页版内嵌 Noto Sans SC 和 Noto Serif SC 的游戏字符子集，使用 SIL Open Font License 1.1。完整许可保存在 `assets/fonts/NotoSans-LICENSE.txt` 和 `assets/fonts/NotoSerif-LICENSE.txt`，并随网页部署在 `dist/licenses/`。未打包系统字体。

## 马匹外观与骑行动作

- Horse / Farm Animals Pack by **Quaternius**, released under **CC0 1.0 Universal**.
- Author: https://quaternius.com/packs/farmanimal.html
- GLB: https://poly.pizza/m/qvTrSG9pZF
- Original FBX/Blend and license: https://opengameart.org/content/lowpoly-animated-farm-animal-pack
- Original files and provenance: `godot-games/3a-games/source/third_party/horse/`.
- 动作来源：上述 Quaternius 马的 Idle、Walk、Gallop，经解剖标定、分腿蒙皮重绑和重定向用于新坐骑。CC0 只适用于此参考素材和动作。
- 当前两匹马的外观来自用户提供的 Tripo 原件 `马_棕色.glb`、`马_白色.glb`；不将这些用户素材声明为 CC0。原始几何、三角形、UV 和贴图归档保留，运行副本仅统一旋转/缩放、重建损坏骨架蒙皮、缩小纹理到 2048。
- 当前运行副本：`assets/mounts/horse_brown.glb`、`horse_white.glb`，配置与原文件 SHA256 见同目录 `manifest.json`；可用 `tools/prepare_mounts.py` 离线复现。
- 参考原始 GLB/FBX/Blend、作者许可及解剖标定在 `godot-games/3a-games/source/third_party/horse/`。程序鞍具、缰绳与马镫由本项目生成。
- License copy: `assets/licenses/Horse-CC0.txt`.
