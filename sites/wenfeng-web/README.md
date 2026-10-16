# 问锋 · Web 开发说明

这是可独立重建的 Godot 4.7.2 网页版源码。赵云、马超、刀剑、三档 AI、三局两胜和角色专属技能都包含在 `godot/`。人物贴图为 1024px，兵刃贴图为 512px；保留几何、骨骼和全部动画。3D 使用完整渲染分辨率与 2× MSAA，画布最高 2× 屏幕像素密度、3840×2400 像素，UI 使用 1280×800 逻辑坐标。

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

`godot/tools/` 保留游戏源码使用的回归和场景检查工具。生成的导入缓存与 `qa/` 输出均忽略，不进入仓库。

## 部署文件

`dist/` 是完整静态站点，使用单线程 WebGL 2，不要求 SharedArrayBuffer 或跨域隔离。WASM 与 PCK 以 gzip 文件提供，由加载器流式解压，不设置 `Content-Encoding: gzip`；每个文件小于 25 MiB。`assets-manifest.json` 记录下载大小、解压大小和 SHA256。重建后可在仓库根目录运行 `python3 play.py --check` 验证。

现有 Sites 身份记录在 `.openai/hosting.json`。仓库根 Git 统一用于 GitHub，不再包含嵌套 Git 仓库。更新 Sites 时保留该项目 ID，并使用 Sites 的源码同步与部署流程。
