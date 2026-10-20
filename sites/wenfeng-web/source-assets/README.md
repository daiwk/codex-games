# 网站原始素材

这里集中保存问锋网页游戏的原始模型、当前素材准备脚本使用的动作、来源记录和许可。与 `godot/assets/` 中的运行副本分开保存，重新烘焙不依赖旧游戏目录。

```text
characters/        六位武将的重建输入
weapons/           八把原始武器，含保留的刀、剑和赵云、马超原枪
mounts/            用户提供的棕马、白马和马鞍
animations/
  kaykit/          四份免费动作 GLB、来源与 CC0 许可
  ual1/            手指握持姿势来源 GLB、来源与 CC0 许可
  horse/           马匹参考 GLB、动作、解剖标定及许可
  ual2/            历史使用来源与许可记录，已移除未使用的动作 GLB
originals/         吕布修复前的原件和修复记录
glb-manifest.json  24 个保留 GLB 的路径、字节数与 SHA256
```

清单中的路径相对于本目录。2026-10-20 整理时保留的全部 GLB 内容与迁移前一致；只清理了五份未使用的人物历史版本、未使用的 UAL2 动作 GLB 和重复的 Horse FBX/Blend 格式。许可与来源记录继续保留。用户提供的人物、武器和坐骑不声明为 CC0；CC0 仅适用于相应第三方动作和参考素材。

在上一级 `wenfeng-web/` 目录安装可选依赖 `numpy scipy Pillow` 后，可重新准备素材：

```sh
python3 tools/repair_lubu.py                 # 可选，修复脚本可重复执行
python3 tools/prepare_polearms.py             # 六位武将的动作和武器
python3 tools/prepare_mounts.py               # 两匹马的绑定和动作
python3 tools/prepare_saddle.py               # 必须在马匹运行副本就绪后执行
python3 tools/build_web.py --godot /absolute/path/to/Godot
```

`onehand_sword.glb` 的原件与现有运行副本均保留，当前准备脚本不重新生成剑。直接本地游玩仅需要仓库根目录的启动脚本和 `dist/`，不需要这些素材准备依赖。
