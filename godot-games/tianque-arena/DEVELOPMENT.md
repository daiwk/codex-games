# 《天阙试炼》二次开发指南

这是一个使用 Godot 4.7 制作的俯视角 3D 动作原型。源码包同时包含可直接运行的 Godot 资源、五个可编辑 Blender 角色工程，以及重建角色所需的 Quaternius CC0 原始 FBX 和贴图。

## 1. 环境

- Godot 4.7.2，Compatibility 渲染器。
- macOS 可双击 `play.command`；找不到 Godot 时脚本会下载官方 4.7.2 到系统临时目录。
- 修改角色模型需要 Blender 5.x。最终 GLB 已包含在 `assets/`，只改玩法时不需要 Blender。
- 项目没有运行时联网、付费插件或付费服务依赖。

## 2. 第一次运行

1. 解压源码包。
2. 用 Godot 选择根目录的 `project.godot`。
3. 等待首次导入 GLB 和贴图。
4. 运行 `main.tscn`。

命令行运行：

```bash
godot --path /path/to/TianqueArena-Source
```

## 3. 目录

```text
assets/                 Godot 运行时 GLB 与贴图
  characters/           主角及四类敌人
scripts/                游戏逻辑
source/                  不由 Godot 导入的可编辑源文件
  hero/                 Warrior Blender 工程
  cast/                 Rogue/Monk/Wizard/Cleric Blender 工程
  third_party/          Quaternius 原始 FBX、贴图和 CC0 许可
tools/                   正式构建、检查和打包工具
qa/                      当前版本的实机参考截图
distribution/            macOS 首次打开说明
main.tscn               主场景
project.godot           Godot 项目配置
export_presets.cfg      Universal macOS 导出配置
```

`.godot/` 是本地导入缓存，不在源码包中。Godot 会在新机器自动重建。

## 4. 主要代码入口

- `scripts/main.gd`：场景、两波遭遇、HUD、特效、输入映射和自动测试。
- `scripts/player.gd`：移动转身、前方锁敌、连击、重击、技能、闪避和五次回血。
- `scripts/enemy.gd`：Guard、Brute、Caster、Boss 的属性、寻路、攻击和动画。
- `scripts/combatant.gd`：玩家与敌人的共同生命、受伤、击退和死亡逻辑。
- `scripts/visual_factory.gd`：场景特效、血条和缺失角色资源时的程序化后备模型。

最常改的难度数值位于 `player.gd::_ready` 和 `enemy.gd::_ready/_melee_attack/_cast_orb`。回血次数与单次恢复量是 `MAX_HEAL_CHARGES` 和 `HEAL_AMOUNT`。

## 5. 输入

- `WASD`：移动；移动会平滑转向。
- `J`：三连斩。
- `K`：破阵斩。
- `L`：坠星。
- `Space`：影步闪避。
- `H`：调息，恢复 50 点，每局 5 次；满血不消耗。
- `R`：胜利或失败后重新开始。

输入动作在 `scripts/main.gd::_configure_input_map` 中配置。

## 6. 角色和动画契约

| 游戏角色 | 模型 | 运行时文件 | 必需动作 |
| --- | --- | --- | --- |
| 玩家 | Warrior | `assets/characters/tianque_hero.glb` | Idle, Run, Attack1-3, Heavy, Dash, Skill, Hit, Death |
| Guard | Rogue | `assets/characters/enemies/guard_rogue.glb` | Idle, Run, Attack, Attack2, Dash, Hit, Death |
| Brute | Monk | `assets/characters/enemies/brute_monk.glb` | Idle, Run, Attack, Attack2, Dash, Hit, Death |
| Caster | Wizard | `assets/characters/enemies/caster_wizard.glb` | Idle, Run, Attack, Cast, Cast2, Hit, Death |
| Boss | Cleric | `assets/characters/enemies/boss_cleric.glb` | Idle, Run, Attack, Cast, Cast2, Hit, Death |

运行时通过这些语义名称寻找动作。替换模型时，可以保持名称不变，或修改 `tools/build_rpg_cast.py` 的 `aliases` 映射。

## 7. 重建角色

原始输入在：

```text
source/third_party/quaternius/rpg-characters/upstream/
```

在项目根目录执行：

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --python tools/build_rpg_cast.py
```

脚本会：

1. 导入五个原始 FBX。
2. 按游戏契约复制并重命名动作。
3. 将 Warrior 的克制五官绘制进真实 Face 网格的 UV 贴图，不生成悬空五官网格。
4. 保存五份 `.blend`。
5. 导出五个 Godot GLB。

脚本通过自身路径寻找项目根目录，可在任意解压位置运行。重新导出后打开一次 Godot，让引擎重新导入 GLB。

## 8. 自动验证

以下命令分别验证转身、前方锁敌、五次回血和完整两波流程：

```bash
godot --headless --path . -- --turn-test
godot --headless --path . -- --aim-test
godot --headless --path . -- --heal-test
godot --headless --path . -- --smoke-test
```

通过标志分别是 `TIANQUE_TURN_TEST=PASS`、`TIANQUE_AIM_TEST=PASS`、`TIANQUE_HEAL_TEST=PASS` 和 `TIANQUE_SMOKE_TEST=PASS`。

## 9. macOS 打包

安装 Godot 4.7.2 export templates 后执行：

```bash
bash tools/package_macos.sh
```

输出为 `dist/TianqueArena-macOS.dmg`。它是 Apple Silicon/Intel Universal 应用并使用免费 ad-hoc 签名。没有 Apple Developer ID，因此其他用户第一次打开需要 Control 点击应用并选择“打开”。

## 10. 授权和来源

- Quaternius RPG Characters、骨骼和原始动画：CC0 1.0 Universal。原始许可见 `source/third_party/quaternius/rpg-characters/License.txt`。
- 具体来源见同目录的 `SOURCE.txt`。
- 远景大雁塔及其专属 GLB、贴图已移出当前项目；庭院地台、桥梁和碰撞由代码生成。
- 本项目原创脚本尚未由项目所有者指定公开许可证。公开发布、出售或再授权前，请由项目所有者补充明确的代码许可。

## 11. 已知限制

- 角色是风格化低多边形资产，不是商业 MOBA 的高精度角色。
- 场景和角色均针对当前俯视镜头优化。把镜头改为近距离第三人称需要重新制作材质、面部和动作。
- 当前 AI 是直接追踪/拉距逻辑，没有导航网格和复杂行为树。

## 12. 分层技能特效（2026-10-08）

`scripts/combat_vfx.gd` 是独立的纯表现层：每个特效使用一个批量 ImmediateMesh，带端部收尖、边缘软化、程序化纹理与加色混合。没有外部贴图、粒子插件、付费资源或后处理依赖，Compatibility 渲染器可运行。

- J 三连斩：收尖刀芒、亮刃与切向余烬；第二式反向，第三式挑起。
- K 破阵斩：定向聚气后挥出较厚刀锋，命中迸火。
- L 坠星：地面刻痕提示范围，灵气内收、星芒下降，落地后放射裂光与碎屑消退。
- Space 影步：采样实际位移，留下多层灵光拖尾。
- H 调息：青色灵气螺旋与上升叶状光点。
- 敌人的圆形危险预警保留，双方颜色语义保留；玩家判定、伤害、前摇、冷却、输入与无敌时间未改。

特效使用局部确定性伪随机数，不消耗玩法随机序列。节点在各自寿命结束后释放；闪避目标提前被删除时也能正常清理。

新增验证命令：

```bash
godot --headless --path . -- --vfx-test
godot --path . -- --vfx-showcase
# 可选：录制实际引擎画面，需图形桌面；AVI 文件较大，随后用 ffmpeg 压缩。
godot --path . --write-movie /tmp/tianque-vfx.avi --fixed-fps 60 -- --vfx-showcase
```

`--vfx-test` 覆盖重复释放、目标提前删除和生命周期清理。`--vfx-showcase` 调用真实玩家技能，自动保存 `qa/vfx/` 中的十一张截图；仅该参数下使用固定近景镜头，以及最后一段普通镜头下的静止敌人可读性验证。普通启动保持原有两波战斗。

本轮测试环境为 Linux Godot 4.6.3；项目声明的 4.7.2 和 macOS 导出仍需在对应环境复测。

## 13. 远景资产精简（2026-10-08）

移除大雁塔远景加载函数、GLB、五张专属贴图及其导入描述。当前源码包原本不含大雁塔 Blender 工程；五份角色 Blender 源文件全部保留。可玩场景、碰撞、战斗、角色动画和上一轮分层特效未改。
