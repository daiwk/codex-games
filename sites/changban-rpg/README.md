# 长坂行 · 赵云传

独立的骑马探索RPG网站，以赵云为主角，在三国郊野中清剿游骑、升级、收集装备并依次挑战五位武将。故事为架空外传。

本目录保存专属网页入口、封面、构建工具和导出的静态网站。Godot游戏代码与模型原件复用同仓库的 `../wenfeng-web/`：RPG入口为 `../wenfeng-web/godot/rpg.tscn`，准备素材仍在 `../wenfeng-web/source-assets/`。不再复制一套人物、兵器、马匹GLB。

RPG独有的山贼原件另存于本目录 `source-assets/characters/山贼.glb`，哈希见 `source-assets/glb-manifest.json`。`tools/prepare_bandit.py` 复用共享动作参考，重建损坏的原始绑定并生成共享运行项目中的 `assets/characters/bandit.glb`；原始几何、UV及材质不替换为其他武将。这份用户素材不声明为CC0，动作许可随站点一起发布。

构建需要本地已有Godot 4.7.2及 `../wenfeng-web/.cache/web_nothreads_release.zip`，工具不会下载依赖：

```sh
python3 sites/changban-rpg/tools/build_web.py --godot /path/to/Godot
```

构建时临时切换共享工程的主场景、名称和HTML导出入口，并在 `finally` 中按原字节恢复 `project.godot` 与 `export_presets.cfg`。共享工程的两种网站导出应顺序运行。只更新本目录的 `dist/`，不更新问锋的网站输出。

导出的 `dist/` 自包含，可独立部署到静态托管。引擎与资源包按gzip压缩，较大的压缩包切成16MiB分片，每个发布文件小于25MiB。游戏代码在PCK内，浏览器运行不请求仓库里的共享目录。许可与制作信息随包放在 `dist/licenses/` 和 `dist/credits.txt`。

本地预览已构建的网站：

```sh
python3 play.py --game rpg
python3 play.py --game rpg --check
```

在仓库根目录运行以上命令，也可双击 `play-rpg.command`（macOS）或 `play-rpg.bat`（Windows）。默认访问 `http://127.0.0.1:8000`，端口被占用时启动脚本会打印另一个空闲端口。WASD策马，Space冲刺，J/K攻击，Q/E/U技能，F交互，I行囊，M地图，N静音，Enter继续对话。全屏使用网页顶栏按钮。进度自动保存在当前浏览器；不同网站域名的存档各自独立。

五处守将依次为：马超（2级）、许褚（4级）、张飞（6级）、关羽（8级）、吕布（10级）。挑战须同时达到等级并完成前一场试炼。首胜奖励为护腕、战甲、蛇矛、青龙刀、画戟及经验；装备在行囊中装配，兵器切换也会切换突刺或挥砍动作。流寇约45秒后重生，可持续历练。驿站恢复生命与体力，失利后回营保留等级和战利品。故事为架空外传。

后续场景与物件建模说明见 [ASSET_PROMPTS.md](ASSET_PROMPTS.md)。

RPG技能表现使用独立的 `rpg_skill_fx.gd`：枪矛以蓝白螺旋枪芒、金色聚气与锋线呈现，长刀与画戟使用弧形刀气；绝技分为蓄势、连续释放和冲击烟尘收尾。真实接触才触发命中火星、短暂顿帧及镜头微震，特效不改变伤害范围。全部由缓存程序网格与着色器生成，无需另补GLB或外部游戏特效素材；最多24组短时效果、每批最多32粒子。镜头会避开旗面、营门屋顶和建筑，收近后仍可策马穿行。
