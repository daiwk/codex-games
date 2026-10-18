# 问锋 · Duel of Blades

赵云、马超、关羽、张飞、吕布的一对一 3D 决斗。赵云与马超可选刀剑，关羽持青龙偃月刀，张飞持丈八蛇矛，吕布持方天画戟。支持自由选择对手、三档 AI、三局两胜、角色专属 Q/E/U 技能，以及键鼠和触屏操作。画面适配高清屏和全屏。

[在线游玩](https://wenfeng-duel.stormyyew5.chatgpt.site)

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
```

浏览器需支持 WebGL 2 和 DecompressionStream，建议开启硬件加速。首次载入会下载游戏资源；高清模式会增加显卡负载。

## 操作

| 按键 | 操作 |
| --- | --- |
| 1 / 2 / 3 / 4 / 5（菜单） | 赵云 / 马超 / 关羽 / 张飞 / 吕布 |
| WASD / 方向键 | 移动，自动面向对手 |
| J / 鼠标左键 | 轻击与连招 |
| K / 鼠标右键 | 重击 |
| L / Shift | 格挡 |
| Space | 闪避 |
| Q / E / U | 角色技能 / 绝技 |
| Enter / Esc / R / F / M | 开始 / 暂停 / 重开 / 全屏 / 静音 |

## 目录

```text
play.py / play.command / play.bat   本地启动入口
sites/wenfeng-web/
  dist/                            可直接运行、部署的完整网页游戏
  web/                             网页外壳、加载器、样式与浏览器桥接源码
  godot/                           网页版 Godot 游戏源码、优化资源与回归工具
  tools/                           可选的 Web 重建工具
  .openai/hosting.json              已有 Sites 项目标识
godot-games/
  3a-games/                        保留的原始人物、武器和动画 GLB
  tianque-arena/                   保留的其他已有角色 GLB
  glb-manifest.json                29 个归档 GLB（含吕布原始备份及免费动画） 的路径、大小与 SHA256
```

吕布模型已移除两条翎尾末端的灰色片面，未经修改的原文件保存在 `godot-games/3a-games/source/originals/吕布.glb`，修复记录保存在同目录的 `吕布.repair.json`。其他原有 GLB 的路径与内容保持原样；运行游戏使用的是 `sites/wenfeng-web/godot/` 中的网页优化资源。旧桌面工程、安装包、导入缓存、临时截图和历史测试输出已从当前目录清理。

长兵器动作按武器区分：刀、戟可斩扫，蛇矛的三段连招、重击与进攻技能均为突刺。双手动作使用 [KayKit Character Animations Free 1.1](https://kaylousberg.itch.io/kaykit-character-animations)（CC0），已重定向并烘焙到模型中。

需要修改游戏并重新导出时，见 [网页版开发说明](sites/wenfeng-web/README.md)。素材来源与许可见各资源目录中的许可文件和游戏内「制作与许可」。
