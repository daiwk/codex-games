# 问锋 · Web 开发说明

这是可独立重建的 Godot 4.7.2 网页版源码。六位角色赵云、马超、关羽、张飞、吕布、许褚，两把枪、三把长兵器及许褚可选的三种刀剑、三档 AI、自由选对手、三局两胜和角色专属技能都包含在 `godot/`。运行时贴图最高 1024px；保留人物几何、骨骼与烘焙动画。3D 使用完整渲染分辨率与 2× MSAA，画布最高 2× 屏幕像素密度、3840×2400 像素，UI 使用 1280×800 逻辑坐标。

## 直接游玩

在仓库根目录运行 `python3 play.py`，或双击 `play.command`（macOS）/ `play.bat`（Windows）。只需要 Python 3.9+ 和支持 WebGL 2 / DecompressionStream 的浏览器。`dist/` 已包含游戏、字体、图像和许可，完整下载后无需联网。

## 修改和重建

只有修改游戏源码或重新导出才需要安装 **Godot 4.7.2**。构建脚本使用 Python 标准库；首次下载导出模板时需要 `curl`，只下载官方模板中的单线程 Web release 模板，并校验固定 SHA256。字体子集和优化后的模型已随源码提供，无需 Pillow、fontTools 或旧桌面工程。

在本目录运行：

```sh
python3 tools/build_web.py --godot /absolute/path/to/Godot
```

也可以把 `godot` / `godot4` 加入 PATH，或设置 `WENFENG_GODOT`。macOS 上会自动检查 `/Applications/Godot.app/Contents/MacOS/Godot`。脚本首次缺少模板时会自动下载到忽略的 `.cache/`；需要代理时设置 `HTTPS_PROXY`。也可提前单独下载：

```sh
python3 tools/fetch_web_resources.py
```

游戏逻辑在 `godot/scripts/`；场景在 `godot/main.tscn`；运行资源在 `godot/assets/` 和两把兵刃 GLB。网页外壳在 `web/shell.html`，加载器和样式在 `web/web-app.js`、`web/web.css`，浏览器交互桥接在 `web/web_bridge.gd`（修改后同步到 `godot/scripts/web_bridge.gd`）。重建会更新 `dist/`，随后运行根目录的启动脚本查看效果。

`godot/tools/polearm_test.gd` 检查新角色、双手握持、轻重击、Q/E/U 的实际伤害与资源门槛。可运行 `Godot --headless --path godot --script res://tools/polearm_test.gd`；增加 `-- --visual` 可渲染检查图。原有角色回归使用 `Godot --headless --path godot -- --test` 和 `--skills-test`。

`godot/tools/` 保留游戏源码使用的回归和场景检查工具。生成的导入缓存与 `qa/` 输出均忽略，不进入仓库。

## 部署文件

`dist/` 是完整静态站点，使用单线程 WebGL 2，不要求 SharedArrayBuffer 或跨域隔离。WASM 与 PCK 以 gzip 提供，超过上限的压缩包拆为 16 MiB 分片，由加载器按顺序流式拼接、解压，不设置 `Content-Encoding: gzip`；每个文件小于 25 MiB。`assets-manifest.json` 记录下载大小、解压大小和 SHA256。重建后可在仓库根目录运行 `python3 play.py --check` 验证。

现有 Sites 身份记录在 `.openai/hosting.json`。仓库根 Git 统一用于 GitHub，不再包含嵌套 Git 仓库。更新 Sites 时保留该项目 ID，并使用 Sites 的源码同步与部署流程。

## 重新烘焙双手动作（可选）

本目录的 `source-assets/` 保留六位武将及武器的原始 GLB、KayKit 免费动作、UAL1 手指姿势、马匹参考动作与原始许可；无需依赖目录外的旧游戏工程。素材分类、校验清单和重建命令见 [原始素材说明](source-assets/README.md)。安装 `numpy scipy Pillow` 后，在本目录运行 `python3 tools/prepare_polearms.py`，再执行 Web 构建。吕布原模型的两个灰色翎尾片面通过 `tools/repair_lubu.py` 删除，原版保存在 `source-assets/originals/`；修复脚本可重复运行。烘焙工具只读取模型，通过 T-pose 重定向、保留骨长的双臂 IK、闭合手指和地面校正生成 `godot/assets/` 下的网页副本；普通本地游玩和 Web 重建均不需要这些库。

蛇矛网页副本已局部收窄刃头：刃长和厚度为原来的70%、宽度48%，连接处平滑过渡；蛇形弯折、杆身、红缨、总长及刀尖纵向位置保留。三把长兵器和单手刀的网页副本已按实际柄心归中，原始归档GLB均保留。单独重新生成武器可运行 `python3 tools/prepare_polearms.py --weapons-only`，无需重新烘焙角色动作。

赵云与马超当前改用张飞同款丈八蛇矛，保留各自技能与双手突刺；原两把枪的资源继续保留。可用 `python3 tools/prepare_polearms.py --characters zhaoyun machao` 单独烘焙这两位武将；默认烘焙六人。两把枪从源模型的横向轴旋转到纵向并校准杆心，刀剑资源仍保留在工程中。

许褚默认持专用大刀，也可在选将菜单切换单手刀或剑；使用单手横斩、斜斩、劈砍、重击与专属Q/E/U。单独重建可用 `python3 tools/prepare_polearms.py --characters xuchu`。

新增界面文字时，可在缓存完整 Noto 字库后运行 `python3 tools/subset_fonts.py` 补齐两份游戏字体；该可选步骤需要 `fonttools`。`--check` 检查现有子集的中文覆盖。

保留的赵云、马超原枪模型，其金属枪头已按长宽厚65%局部缩小，保持整枪长度和红缨，连接颈平滑过渡；当前两人改用蛇矛，不加载这两把枪。

## 马战

选将菜单可切换步战/马战（B）；默认步战。马战复用所有六将，WASD控马转向，Space冲刺（24体力、3.6秒冷却），J/K和Q/E/U为马上攻击。松键后有短暂减速过程；骑速超过4.8m/s时对命中的武器攻击提供最高30%伤害加成。马战场地与镜头已放大。双方均骑乘，以武将生命判胜，当前无上下马/落马系统。

`horse_visual.gd` 使用 `assets/mounts/horse_brown.glb`、`horse_white.glb`，保留用户提供的真实毛色和贴图，双方坐骑可分别选色。鞍座与鞍垫使用用户提供的马鞍，侧垫分别适配两匹马，马镫跟随骑手靴子；`rider_pose.gd` 在动画后通过SkeletonModifier3D固定髋部和跨马双腿，保留上身攻防，不修改原始人物GLB；`mounted_combat.gd`定义枪刺、刀戟挥斩和骑乘技能。站立马匹的身体碰撞与骑乘者合并为同一角色碰撞体，当前不支持独立击杀马匹。用户马匹原件在 `source-assets/mounts/`，参考骨架、动作和许可在 `source-assets/animations/horse/`。

用户提供的 `马_棕色.glb` / `马_白色.glb` 原件仅用于归档：原导出无动画，骨骼静止变换与逆绑定矩阵异常且几乎所有权重集中于Root，不能直接用于跑步。网页副本保留外观、UV和贴图，按已验证的四足参考骨架重新绑定并接入CC0站立/行走/奔跑动作；转换方式与数据详见 `tools/prepare_mounts.py` 及 `assets/mounts/` 内记录。

`马鞍.glb` 原件也完整保留。运行 `python3 tools/prepare_saddle.py` 生成 `assets/mounts/saddle.glb` 与 `saddle_manifest.json`：保留原三角形、UV、鞍桥和厚度，将贴图缩为2048px。运行副本纵长约68cm（原约90cm），两端平滑缩短而保留中央座区，鞍与骑手前移7.5cm，侧垫分别贴合两匹马。白马适配使用同一模型的形态键，不复制整套纹理。位置参考 [BHS骑具检查](https://www.bhs.org.uk/media/uddbc0np/connemara-champs-activity-plans.pdf) 与 [World Horse Welfare / Animal Health Trust](https://storage.googleapis.com/worldhorsewelfare-cloud/2021/11/9c136a57-saddlery-leaflet-2021.pdf) 的肩胛避让、承重区域与骑手居中原则；尺寸按游戏网格标定。此可选素材准备步骤需要NumPy、SciPy和Pillow，直接运行已打包的游戏无需安装这些库。

马匹使用独立的站立、行走和奔跑片段，奔跑保留原动作的收腿、伸展与腾空。低速至1.8m/s使用完整Walk，1.8–3.6m/s平滑过渡到完整Gallop，普通4.8m/s快跑不再掺入Walk；Space冲刺提高完整奔跑片段的节奏。切换与节奏连续，骨长和马GLB保持不变。`godot --headless --path godot --script res://tools/horse_gait_test.gd` 验证实际腿部摆幅、骨长、速度切换及停止/重置。

## 突刺接触

直刺的射程与前方窄线仅做初筛，实际伤害还须兵刃或上一帧刀尖轨迹接触躯干。`thrust_contact.gd` 在动画与骑姿之后限制过深的伸枪，近身时向准备姿态缩短刺幅，并用双臂IK保持握杆、骨长和武器长度。命中或格挡后收枪并停止本段前冲，连刺每段重新允许出招；闪避、招架、挥砍和震喝保留各自规则。运行 `godot --headless --path godot --script res://tools/thrust_contact_test.gd` 可验证接触、近身、连刺和防守回归。
