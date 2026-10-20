# 长坂行独有素材

`characters/山贼.glb` 是用户提供的 Tripo 原件，按原字节归档；人物网格、UV、贴图不声明为 CC0。哈希见同目录 `glb-manifest.json`。

运行副本在共享 Godot 项目的 `assets/characters/bandit.glb`。原文件的骨架零位、inverse bind 和权重损坏，派生副本重建 Mixamo 骨架与分区蒙皮。骨架参考来自同仓库用户提供的赵云原件，仅借骨架和绑定参考，不复制赵云几何。

动作：KayKit Character Animations Free 1.1，作者 Kay Lousberg，CC0 1.0。来源 https://kaylousberg.itch.io/kaykit-character-animations 。完整许可见共享素材目录 `../../wenfeng-web/source-assets/animations/kaykit/License.txt`，随网站发布为 `licenses/KayKit-CC0.txt`。

握持手指参考：Quaternius Universal Animation Library 1，CC0 1.0。来源 https://quaternius.itch.io/universal-animation-library 。完整运行许可位于共享项目 `godot/assets/licenses/Quaternius-UAL1-CC0.txt`，随独立网站发布。

运行副本可用 `../tools/prepare_bandit.py` 重建；依赖同仓库 `../../wenfeng-web/source-assets/` 的 KayKit、UAL1 与有效 Mixamo 骨架参考。
