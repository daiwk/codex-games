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
- 作者随包许可与说明保存在 `source/third_party/ual1/` 和 `ual2/`。

这些动作经 T-pose 空间重定向、骨长保留、地面校正和采样后用于两个运行时角色。没有采用付费 Source 版本。

## 仓库原有素材

原始角色、刀、剑由本仓库提供，原始 GLB 文件未改写。原始两把长枪不参与本游戏。运行时人物的几何、材质、贴图和蒙皮来自上述原有角色；运行时纹理合并为图集并重映射 UV，以降低绘制批次。

## 本项目生成内容

庭院、山景、旗帜、刀光和命中反馈由 Godot 代码生成；八种声音由 `tools/generate_audio.py` 合成。中文字体使用运行设备的系统字体，不复制或打包系统字体文件。
