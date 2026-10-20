# 问锋 · Duel of Blades

赵云、马超、关羽、张飞、吕布、许褚的一对一 3D 决斗。赵云、马超与张飞暂用丈八蛇矛，关羽持青龙偃月刀，吕布持方天画戟，许褚可选专用大刀、单手刀或剑。可选步战或马战，支持自由选择对手、三档 AI、三局两胜、Q/E/U 技能，以及键鼠和触屏操作。马战采用带动画的马匹、跨马骑姿、转向与加减速，冲刺时可继续攻击。画面适配高清屏和全屏。

[在线游玩](https://wenfeng-duel.stormyyew5.chatgpt.site)

另有独立的骑马探索 RPG「长坂行 · 赵云传」：控制赵云在连续郊野中行旅，清剿游骑升级，按 2 / 4 / 6 / 8 / 10 级依次挑战马超、许褚、张飞、关羽和吕布，胜出获得装备与经验。两款游戏使用不同的网站入口和独立的浏览器存档，复用同一套原始素材。

RPG 的构建说明见 [长坂行目录](sites/changban-rpg/README.md)，新增素材建模可用 [Tripo 提示词](sites/changban-rpg/ASSET_PROMPTS.md)。山贼原始 GLB 单独保存在 `sites/changban-rpg/source-assets/characters/`。

## 在本地游玩

安装 **Python 3.9 或更新版本**，克隆或下载整个仓库。游戏已经构建好，无需安装 Godot、Node.js 或 Python 第三方库。

- **macOS**：双击仓库根目录的 `play.command`。
- **Windows**：双击 `play.bat`。
- **macOS / Linux 终端**：在仓库根目录运行：

```sh
python3 play.py
```

脚本会启动本地 HTTP 服务并打开默认浏览器；首次进入点击「入场拔刃」。游戏资源随仓库提供，完整下载后可离线游玩。不要直接双击 `index.html`，浏览器需要通过本地 HTTP 加载 WebAssembly。

默认端口为 8000；被占用时会自动选择空闲端口。终端会打印实际网址，按 **Ctrl+C** 关闭服务。可选参数：

```sh
python3 play.py --port 8080        # 指定端口
python3 play.py --no-browser       # 只启动服务，不自动打开浏览器
python3 play.py --check            # 检查游戏资源完整性
python3 play.py --game rpg         # 启动独立的长坂行 RPG
python3 play.py --game rpg --check # 检查 RPG 资源完整性
```

浏览器需支持 WebGL 2 和 DecompressionStream，建议开启硬件加速。首次载入会下载游戏资源；高清模式会增加显卡负载。

## 操作

| 按键 | 操作 |
| --- | --- |
| 1 / 2 / 3 / 4 / 5 / 6（菜单） | 赵云 / 马超 / 关羽 / 张飞 / 吕布 / 许褚 |
| WASD / 方向键 | 移动，自动面向对手 |
| J / 鼠标左键 | 轻击与连招 |
| K / 鼠标右键 | 重击 |
| L / Shift | 格挡 |
| Space | 步战闪避 / 马战冲刺（消耗24体力，冷却3.6秒） |
| B（菜单） | 切换步战 / 马战 |
| Q / E / U | 步战角色技能；马战突刺或横斩 / 震喝 / 连击绝技 |
| Enter / Esc / R / F / M | 开始 / 暂停 / 重开 / 全屏 / 静音 |

上表为《问锋》的操作。《长坂行》RPG支持 **Tab / 单击鼠标中键**锁定或解除敌人，**R**切换目标；锁定时 **W/S**朝敌进退、**A/D**绕敌，人物与镜头保持面向目标。按住中键拖动会解除锁定并转动自由视角，滚轮调整远近，解除后恢复自由骑行。RPG中 **F**交互、**I**行囊、**M**地图、**N**静音，倒下时按R回营；全屏使用网页顶栏按钮。其它攻击、格挡、技能和冲刺按键相同。

## 目录

```text
play.py / play.command / play.bat   本地启动入口
play-rpg.command / play-rpg.bat     RPG 本地启动入口
sites/changban-rpg/                独立 RPG 网页、输出、构建工具及 Tripo 提示词
sites/wenfeng-web/
  dist/                            可直接运行、部署的完整网页游戏
  web/                             网页外壳、加载器、样式与浏览器桥接源码
  godot/                           网页版 Godot 游戏源码、优化资源与回归工具
  source-assets/                   原始人物、武器、坐骑、动作与许可
  tools/                           可选的 Web 重建工具
  .openai/hosting.json              已有 Sites 项目标识
```

网站相关素材已统一迁入 `sites/wenfeng-web/source-assets/`，包括六位武将、八把武器、棕白马、马鞍、当前使用的免费动作及许可。刀、剑和赵云、马超的原枪均保留。该目录的 `glb-manifest.json` 记录 24 个原始 GLB 的相对路径、大小与 SHA256；迁移未改动任何保留的 GLB 内容。

吕布模型已移除两条翎尾末端的灰色片面，未经修改的原文件保存在 `sites/wenfeng-web/source-assets/originals/吕布.glb`，修复记录在同目录。运行游戏使用 `sites/wenfeng-web/godot/` 中的网页优化资源。未使用的人物历史版本、重复马匹格式及与网站无关的旧 `godot-games/` 目录已清理。

长兵器动作按武器区分：刀、戟可斩扫，枪、蛇矛的三段连招、重击与进攻技能均为突刺。双手动作使用 [KayKit Character Animations Free 1.1](https://kaylousberg.itch.io/kaykit-character-animations)（CC0），已重定向并烘焙到模型中。

需要修改游戏并重新导出时，见 [网页版开发说明](sites/wenfeng-web/README.md)。素材来源与许可见各资源目录中的许可文件和游戏内「制作与许可」。

刀、剑及原两把枪的原始与网页资源均保留；刀剑当前可由许褚选择，也供后续武将使用。赵云和马超暂用张飞同款丈八蛇矛，普通连招、重击和进攻技能使用双手突刺。

马战可在选将菜单右侧切换，六位武将和许褚的三种兵器均可使用。WASD 控马，马匹沿朝向移动，松键后减速；Space 冲刺期间可按 J/K 出招，实际骑速超过4.8米/秒时提升命中伤害（最高30%）。骑乘双方共用生命判胜，暂不包含上下马或落马机制。马匹外观与贴图使用用户提供的棕马、白马；己方和对手可分别选色，所有六位武将均可骑乘。原始马GLB完整保留；网页副本修复绑定，使用 [Quaternius Farm Animal Pack](https://quaternius.com/packs/farmanimal.html) 的 CC0 马骨架和站立、行走、奔跑动作。

马鞍采用用户提供的独立模型，压短到约68cm并校准前后位置，分别适配两种马体与骑手靴子的马镫位置。低速行走、普通快跑和冲刺有清楚的步态与节奏区别，快跑使用包含收腿和腾空的完整奔跑动画。枪矛按实际兵刃接触判定命中，近身限制刺幅，命中或格挡后收枪并停止继续前冲；双手握点和武器原长保留。
