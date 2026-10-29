Original prompt: 按上一轮诊断先改《问锋》，认真打磨场景、动作、镜头和特效，做好后部署到原来的 Sites，用户查看实际效果。用户同时授权安装并使用合适的游戏开发、UI 设计 skill。

## 2026-10-28 · 山门秋庭视觉样板

Scope: one detailed foot-combat courtyard; Zhao Yun / Ma Chao normal-combat animation polish; clear shoulder framing; restrained, contact-driven effects; compact readable combat HUD. Preserve all playable roles and mounted mode. No new gameplay systems. Keep the existing Site project identity and audience.

Art direction: weathered blue-grey stone, oxblood timber, curved tiled eaves, moss and autumn foliage, warm low sunlight against cool atmospheric distance. The fighting centre stays clear and level.

Implementation is split by file ownership: arena and environment assets; Duel-only animation aliases; Duel camera and effects; root handles HUD, integration, build and visual QA.

Acceptance: compare real menu/gameplay frames, inspect light combo/heavy/skill/guard/dodge/jump and contact recovery, check lock camera and pause/restart, smoke-test other roles and cavalry. Functional checks supplement continuous rendered motion review. The RPG is not rebuilt or deployed.

Tooling: official Godot 4.7.2 and pinned Web template downloaded to temporary/cache paths. Initial asset/class import completed. New Godot/UI skills are being vetted and installed.

Publication: existing public Site appgprj_6ad22bc314348191a4822de5abd4c9f9. Official source workflow in the sandbox failed DNS. Automatic review rejected sending the temporary source credential to an unsandboxed terminal. Continue local production/verification; resolve the credential boundary before publishing, with a concrete reviewable build available.


### First two rendered passes
- Installed and read godot-gdscript-patterns and web-design-guidelines; applied resource isolation, static batching, browser focus/safe area review.
- Native captures exposed overexposure, overly fine stone detail and a selected character hidden by the menu veil. Revised lighting, stone scale, architecture height and preview positions; a third art pass is in progress.
- Generated an original mountain panorama using the built-in imagegen tool, copied into godot/assets/environment/autumn_court/mountain_panorama.png.
- First actual combat captures used disabled player state by mistake; corrected the QA fixture and re-ran. Verified request_light/request_heavy/request_skill all accepted in second native movie.
- Independent review found a shared shadow setting leak and unsupported-character generator failure; fixes assigned.
- Motion numeric checks passed 72 checks, but angular-speed diagnostics regressed from old baseline; intentionally held for further correction rather than treating functional passes as visual acceptance.


### Final local verification
- Four cardinal directions and actual combat verified in OpenGL; sky wrap seam removed with explicit horizon mapping.
- Final Web release built successfully: 35 static files, approximately 139.36 MB. python3 play.py --check passed compressed length and SHA256 checks.
- Final PCK loaded from an empty folder: all six environment textures, sky Shader, Duel modifier and both new animation aliases present and loadable. Native shutdown retains a small engine resource-cache warning; no corresponding browser error was observed.
- Motion acceptance: 120/120, zero angular-speed limit violations, actual damage retained.
- Camera: 15/15; presentation: 30/30; shared impact feedback: 66/66; environment: 6/6.
- Cavalry: initial 310/312 with two synthetic key-release timing failures preserved. Low-render-FPS probe reproduced 3/4 failures; test-only Input.flush_buffered_events resolved them. Full unchanged assertions then passed 312/312 across68 cases. No production input logic change.
- Official web-game client executed unmodified (temporary module resolution loader only), cover screenshot inspected. Actual final Web gameplay additionally operated in IAB: move, attack, skill, heavy and pause. Browser error log empty.
- Publication resumed: user explicitly approved the official Sites helper using the project-scoped temporary credential in a networked local terminal on 2026-10-28. Source synchronization and deployment are in progress. The original public Site was version15 when publication resumed. Final dist and source edits are retained in this workspace.


### Publication follow-up
- Original Site source safely pushed at 6a0e202d8e7db4dba5042c66ff685193a451778b. Native archive upload twice timed out after300s at the file-blob upload endpoint; no new saved version appeared.
- Reducing release size by excluding only the two original spear models that are absent from all current weapon choices and special prewarming. Canonical original/runtime GLB files remain intact. This changes export contents without changing the visible game. Rebuild and new archive are in progress.
- User also explicitly requested GitHub push. origin/main equals local pre-polish HEAD1410b56; GitHub synchronization is prepared and will push the verified final build.

- Compact release rebuilt from pushed Sites source ad0361e8327f78bbbaeac6cb5e1607032bc24ab5: 34 static files,129.23MB total; PCK115.80MB gzip. Only two unselectable original spear runtime resources are excluded; original source models remain in the canonical repository. Native upload retry of this verified compact archive is pending.

## 2026-10-29 · 用户否决v17后，改用既有真人动作

用户实玩指出v17前进、后退比原来更怪。已将原Sites成功回退到v16；GitHub main仍为4a28b6d，否决的程序步态实验只保留在本地codex/zhaoyun-motion-v2，不作为可发布成果。此前数值锁脚检查不能证明自然度，相关视觉验收撤回。

替换输入为CMU官方下载09_01前跑、136_25正常倒走；原件和使用条款完整归档。未沿用v17脚端轨迹、支撑相位或上身权重调整。仅赵云步战单挑opt-in两个新别名；旧46动画/几何/蒙皮与其他角色模式保留。后退按原素材正常步行节奏匹配约0.739m/s，前进仍2.85m/s。

适配中，直接rest-delta迁移造成内收与交叉腿，已用连续正常/侧面录像否决。按Foot→Toe骨方向对齐也错误倾斜实际鞋底：原模型脚骨下倾约42–46度，鞋底本身接近平面。最终候选保留解剖腿/躯干对应，只为Foot/Toe各使用固定source mid-stance→target Idle三轴参考，保留完整源时序旋转；实际鞋底参考帧倾角由约26度降至约2.5度。每段最终仅作一个全身高度常数摆放；不逐帧压地、不生成脚步。

状态：本地连续视觉与控制回归中，尚未发布新真人动作版。最终验证和发布结果在完成后补记。

最终发布候选：赵云运行GLB SHA256 ae7a153643e3471aa7a6956f7c3c96b8ae0a8ae5ab5fce1119d9fe2eb13fab47；portable baker从归档原件精确重现，原46段动画、几何、蒙皮及旧二进制完整保留。正常/侧面前跑与后退各5秒、连续换向/停步/出枪/跳跃10秒均以真实60Hz原生帧录制；检查的真实画面不再出现否决版的交叉腿或扁平脚步。实际鞋底摆放后，后退仍保留约2.7cm左右骨架比例差，未通过逐帧脚端曲线掩盖。

实际输入/模式回归36项有效检查通过，W→S保留制动而非瞬间硬截速度；旧直刺接触/回收120项通过。仅修正临时RPG测试对自由转向的错误预期，未为测试更改产品。最终Web构建成功（35文件、约129.27MB），gzip/解压长度/SHA256校验通过；本机IAB实际进入选将/对局并操作进退、攻击、跳跃、暂停和重新开局，控制台error为空。最终连续预览、输入probe、独立逐样本脚掌核验及构建/部署状态归档在忽略的qa/recorded-locomotion-2026-10-29/。

准备同步原Sites并发布此真人动作候选；此条不把数值检查当作用户的观感认可。原站和GitHub的最终同步结果由发布记录补记。

## 2026-10-29 · 按实玩反馈加快后退

用户确认第18版前进正常，反馈后退偏慢。仅将赵云步战单挑后退从0.7390582调为1.05m/s（+42.07%），同一真人倒走片段统一缩短到1.361853秒，配既有1.65播放速率，实际步态周期0.825365秒；脚步音间隔同步到0.412683秒。前进保持2.85m/s，所有前跑key、全部48段动画姿态输出数据和脚掌校准/高度完全不变；只有后退198个时间key改变。两份GDScript未改，原先W→S制动策略保留。

新运行GLB SHA256 23ba8aabd2bafa6d06ff9332008b1828fa27d1d56d9f1def85ea0acc3dfafe29；portable baker精确重现。正在核对实际后退速度/循环/脚步及换向录像，随后更新原Sites并同步GitHub。

## 2026-10-29 · 保留行走，检查并修复其他遗留问题

第18版真人动作及第19版后退提速均已成功发布原Sites；GitHub main已同步94c38f0。用户实玩确认当前前后行走基本可接受，本轮保留Zhao运行GLB 23ba8aabd2bafa6d06ff9332008b1828fa27d1d56d9f1def85ea0acc3dfafe29、动画和2.85/1.05m/s速度，不新增动作素材或系统。

确认并修复的产品缺陷：
- 暂停页短点击“继续”或暂停内同tick按键，Input.just_pressed边沿未被action_release清除，恢复后被poll兜底重读为轻攻。清理时消费当帧已有边沿；真实GUI/键鼠/触屏回归先2项失败，修复后11/11，正常快点和短恢复buffer保留。
- 近身非穿刺横斩的XZ宽容路径无Y门槛，真实跳跃攻击在整个active段离目标胶囊表面至少57.5cm仍伤害/触发招架。仅为旧close fallback补兵刃/扫掠与hurt capsule的高度重叠门槛，保留地面横向宽容及line/wave/radial路径；回归先3项失败，修复后23/23，包括六将地面J/K、真实空中接触、guard/parry和技能对照。
- 马战菜单六将头部投影约Y335–340，落在Y309–349的马色控件内。仅调整mounted menu的预览目标高度/FOV，头部下移到约Y388–392、脚下约Y618，避开上方控件和下方对手选择行；实战镜头不变，待最终网页画面复核。

其他审查：当前马战键盘/bridge的Z/C共4场景20项方向检查通过；角色/武器解析、跳跃落地、回合reset完成代码审查，未发现额外可复现严重缺陷，不据此宣称全角色全流程已完整实玩。最终构建、网页复核、源码同步及部署记录保存于忽略的qa/legacy-fixes-2026-10-29/。

## 2026-10-29 · 战斗处理链审查

当前正式基线为GitHub 5b7a3b6 / 原Sites第20版。保留用户接受的前后行走。开发分支codex/hero-combat-quality开始检查完整战斗，范围与验收记录在COMBAT_QUALITY.md。

独立分层探针发现Duel额外手臂限速会改写髋和双腿，并与控制器原前冲脱节；三连空挥髋部最多约15cm、右小腿局部旋转17.65度。仅绕过该层的反事实消除空挥髋腿改写，但近身旧接触层仍有同类改写，正在比较仅手臂与胸坐标历史运输的可行性。此时尚未接受修复或发布候选，不能将探针结果当成自然度验收。

用户新增许褚单手持械动作优化，并明确单手/双手角色最终都对标《影之刃零》的动作效果。许褚独立审看完整进出招、三连、重击、防守与技能；当前普通招源分别为KayKit横/斜/下劈，重击为Jump_Chop。正在核对重击原始跳劈与地面摆放/控制器的匹配，暂不先认定视觉失败。单手不套双握杆约束，仍需全身发力与空闲手配合。

本轮实证更新（未发布）：
- 新增duel_body_preservation_test，真实导入SkeletonModifier前后分别采样，原版静态对手的赵/马6m、2.3m、1.1m三连/重击共92检查、12项源髋腿保真失败，其他腕角、实绘握杆、骨长、杆体净空仍成立。四元数差改用relative-quat atan2，避免相同float四元数angle_to约0.001rad的假阳性。
- 仅保留源髋腿、按源相对IK校正连续的候选虽92/92，且2.3m收枪单帧49.1度降至约6度，但有效正常/侧面12秒真实输入对照抓到1.1m新增85度翻枪与3命中降至1命中。该候选被否决，生产脚本已恢复5b7a3b6；原Site/GitHub main不变。另一份pre-hit物理阻挡校正连续原型仍在/tmp审查，未接受。
- 延长全身换招blend到120/160/200ms的18组实验均否决：手跳变有所下降，但真实CPU-skinned鞋底增加滑移。仅combo换招加长也一样；根因是旧招在源中段取消，新招从不兼容起势重开，髋/脚目标需回退约19–34cm。保留原75ms，不用长blend掩盖。
- 可靠离线原生捕获现已覆盖许褚正常/侧面各20秒、赵云各30秒和同输入12秒接触对照；每帧有实际渲染条码，帧序/场景确实更新。最终骨架采样必须在modifier链尾，render之后Skeleton读到的是恢复的源pose，旧采样口已否决。离线60Hz不代表实时Web性能。
- 已下载并归档6条ACCAD CC BY3.0徒手完整/防守候选，以及CMU官方02_07/08/09单手剑术原件和许可；均未用于正式runtime。CMU02_09完整8.6秒和4–8.6秒重击段已开始许褚原速、完整身体迁移，保留原root XYZ与整段单一高度，先审模型实片再接控制器。

### 源动作样片与未解决事项

源码审查工具和许可原件已提交ef8dc8f并推送GitHub开发分支codex/hero-combat-quality；main/原Sites仍为稳定版。新捕获脚本解析通过，迁入后的validator对180张原图及180编码帧完整性通过；不据此称动作验收通过。

许褚CMU02_09无IK完整源表演已生成独立正常/侧面各8.6秒真实模型样片，原速、身体/root/自由左臂完整迁移；仅为源适配研究，未接战斗或替换正式GLB。持久本地副本在忽略的qa/combat-quality-2026-10-29/。源码仍存在Foot/鞋底对应与目标骨段比例问题，不能据骨坐标推导真实sole或强行压地。

已取得CMU02_09的官方原始C3D：1033帧，stored9–1041对应AMC1–1033，含真实Heel/Toe/MT5足部和WEP1/2/3道具标记。C3D证实6秒右Toe较开头仅上移约1.5mm，伴随足部bank；marker附着平面不等于鞋底。三WEP可重建相对刚体转动，但marker名称/最长边不能直接当刀尖和绝对刃轴。ASF/AMC本身没独立prop曲线，不代表整个原capture没有；此前仅静态握刀版还不能称还原真实源刀路。先做共同空间、时钟和marker布局核验，所有未经证实的Foot-up假设均撤回。

接触修正的prehit/release后续候选也未通过：85度翻枪可消除，但同输入F399→400仍36度退出跳；已证进入连续释放后所有可行路径试探失败，回退真实目标导致跳变。没有将它们合入生产代码，也不延长全身blend掩盖。

UAL2完整Regular/Heavy/RegularC的许褚独立原型也已生成，源身体/root/空闲手和时序保留。原源自身按当前项目腕部坐标定义有50/110度以上的swing/twist；仅将pronation从腕移到前臂虽保刀路，却压坏肘部蒙皮，已否决。继续在/tmp做rig实验：连续右肘解、分段forearm twist骨与权重渐变，并验证全部旧clip等价、真实刀/掌路径、肩肘腕皮缝和完整画面。当前没有一个新角色整套动作已达到《影之刃零》标准，不发布这些中间结果。

### 许褚源动作与真实攻击原型（仍未发布）

离线rig实验已变成可复现工具 `tools/prepare_xuchu_ual2_lab.py`：输入锁定的CC0 UAL2原件和原许褚模型，所有产物只能输出到仓库外。新增三段前臂扭转骨和8权重蒙皮、连续肘解；新Regular保留全身、自由左臂、原掌/刀路和1x时序。原有动画的210个姿态、分段恢复接点和真实Godot Mixer已分别核验，四个实验GLB从仓库输入可精确复现。这里是保真与兼容证据，不是动作自然度验收；旧模式与生产GLB均未改动。

临时实战版使用同一连续Full的0→13/30→1→3秒三段；单J/JJ分别转入源作者对应A/B恢复，不再用不兼容片段中途互切。按键驱动、260ms晚输入过期、受击/闪避/技能/重置清空通过针对性验证。源XZ由CharacterBody单独执行，Y保留在源髋部，实际移动后用相同tick刀位同步判定。新J严格按实绘刀刃/扫掠接触，不借近身距离兜底；尚不能据固定敌人录像称完整实战验收通过。

独立逐帧美术审看确认第三次J内有前横撩与后下斩两拍，原一次hit_landed会使后面更重的下斩无结果。临时版已拆分原28基础伤害为12+16，并开启对手真实physics；近处两拍实际接触，2.3米只命中前撩而后斩空，6米全空，不强行保证连中。同类guard/block/evade预算分配，混合“挡前拍再弹后拍”仍可获得20.571能量而旧单次弹反为18，不能声称全部平衡不变。42秒双镜头实际输入片、18案例、独立同tick与清理检查已记录。tools/xuchu_source_combo_lab保留可复现实验补丁，不替换生产脚本；root独立从锁定输入重建b531模型、全新--import与定向真实physics smoke成功。早先--editor--quit退出时的引擎worker崩溃也保留，没有谎称根因已修复。

最终源选择仍未通过：新增同镜头原UAL2 mannequin与许褚实际鞋底近景，120Hz导入、禁优化、60Hz原速渲染；源本身的起头右脚在低位快速抹出，许褚保留了这种滑步。厚重甲体型与灵巧深蹲腾跃的风格也需审查，不能因为保源/数值过关就称自然。候选暂不作为最终J替换，脚部源/目标原片与拒绝说明保存在忽略的qa/combat-quality-2026-10-29/。Heavy完整源含多次出刀，库内未找到可直接从共同Ready起手并自然收回的完整单发K；不把多击压成单击、不剪掉腕部不可行帧、不以长blend或定格蹲姿伪装收招。

CMU02_09的C3D已并入既有cmu-combat-candidates目录及SOURCE文件，避免重复归档。角色整体连续攻防、旧K与技能/防御、空中身体伤害体积、动态对手、实时网页打击感仍未过验收。GitHub main/原Sites第20版、用户接受的赵云前后行走保持不变。

### 单次K与动作转接的实证

改用仓库UAL1中的完整Sword_Attack（1.533秒）和Sword_Idle作新的独立许褚K候选。两段共用一个静态Foot/Toe参考及高度，全身、手指和髋XYZ原速迁移；单击首尾接近相同姿态，具有完整举刀、下沉斜劈、低位跟随和站回。实际原速全身/脚部/近腕审看允许进入隔离K实战验证，尚不批准最终采用。原source是非root-motion版本，提取髋XZ只保留它现有的骨盆位移，不冒称有原作者前冲轨迹。

K-only临时版保留原Xu角色GLB与27动画，只加载独立K动画资源，未用被拒绝的UAL2 J。真实双角色physics下，1.15/1.7/2.3米单次40.32伤害、6米无伤；heavy格挡规则、真实受击打断和重开清理正确。一个K输入完成后SwordIdle实播跨两循环，不会无输入再出招；末260ms有第二次真实K输入则保留原buffer策略。两条14秒实际正常/侧面片显示新K刀位同tick同步，但也明确抓到Run→K抽脚约31cm/tick、K→Hit急归腿约25cm/tick，以及新SwordIdle→原J/后退的脚位重排。旧J曲线逐帧不变不等于转接自然，下一阶段必须处理这些真实入口/退出；不以延长全身blend掩盖。

原单次K在落刀后.50–.73秒有持续深屈腕、像折腕挂住重刀。另做一份明确的局部美术试验：仅在.40–1.0秒跟随阶段平滑减少最多18度掌屈，保留身体、腿脚、肘/腕位置、原时序与手指本地握持。这里主动改变掌/刀朝向，实绘刀尖最多变化约34.8cm；不称保源刀路，也不能继承raw版命中结论。独立连续帧美术审看认为承刀改善、未见新增刀向回弹或脱握；派生临时版已另行实际验证近中远/落空、格挡、真实受击、重开与单次后Idle循环，14项小范围检查成立。主接触时间/40.32伤害未变，1.7/2.3米实际击点变化约4.80/6.06cm，均由新刀位重新求接触。新14秒原生实战片保持同tick刀位，身体/腿脚与raw相同，因此入口/退出的抽脚仍未修，绝非最终验收。资产可通过tools/xuchu_ual1_lab在仓库外精确重建；K控制器仅以实验patch归档，不安装进生产。全部运行改动仍在隔离原型，未发布。

原计划的Run→K短暂惯性入口试验已暂停，尚无完整对照或通过结论。用户随后指出许褚刀拿反，必须先处理实际刃向，再继续入口。本轮尚未取得或使用Mixamo原件；用户选择继续无需登录的素材，不以登录为前提。

### 用户指出的反刃与修正候选

用户观察正确：原UAL1 raw/support K的主要下劈是厚刀背迎着刀路。实查许褚刀截面/贴图，薄刃为局部+X、厚背为−X，柄与护手首尾没有倒置；漏查的是单刃刀的刃面适配。旧测试只确认轴线、握点、时钟和伤害，不能证明刃口正确。原迁移本身包含源虚拟武器的Rx90关系，并非遗漏该旋转；问题是源剑动作不能直接作为这把刀的正确劈砍。

两种简便翻刀都已否决：仅K旋转150度会在进出K/J/Run/Hit时一帧自转；永久装备旋转150度虽无切换自转，却把原J1/J2正确刃向翻反。只转前臂也不能在源主要刀路中让刃而非刀面切入。所有这些改动均留在/tmp，未合入正式装备或动作。

新的美术候选保留原握柄/装备朝向，重新设计右臂、肘和腕的举刀与下劈，身体、腿、自由左手、手指本地握持和1.533秒源时序保留。这里明确改变实际掌和刀路，不继承原raw/support的距离或命中结论。第一版肩肘被大幅轴向转动压成薄带，已否决；加入三段上臂twist骨及渐变蒙皮后的候选SHA为9fbc41c922c1dd65f87e239da5fa4747eddfbb0c7dab4c06d11110d8efaed064，Godot真实导入8权重。旧31别名93姿态的原骨/蒙皮身份及K→旧Idle/J1的helper归零单独核验，不能外推为所有实战衔接通过。

完整正常/近臂原速画面显示主下斩刃口已迎向切入，薄带黑缝消失，未见刀在手里额外自转；随后隔离实战直接装入同一9fbc模型及同rig K资源，实际可见mesh确认68骨/8权重。正常14秒840帧、近景3秒180帧原生游戏录制均通过原图/编码条码校验，握柄Q和装备Q整段各自保持唯一固定值。独立连续画面审看与root实战近景复核支持这一个K的刃向和基本握持改善，不能接受整套动作。

十个限定场景包含J1对照、四距离K、普通/刚起格挡、真实受击、重开及单K后Idle。新刀路在1.15/1.7米各造成一次40.32伤害，2.3/6米自然落空，未扩攻击距离或窗口保旧命中。J1单次对照仍20.16，不能由此推断全部旧招/技能已验收。低位跟随承刀过久、Run→K/SwordIdle→J/Hit脚位急变仍在；举刀时右肩被披肩遮挡，不能据现有机位完全排除形体问题。素材、影片和trace已持久归档于忽略的qa/combat-quality-2026-10-29/dao-k-edge-candidate；tools/xuchu_ual1_lab/dao_k_trial从原件重建完整e19→b3d→f233→9fbc链，最终SHA精确相同。未发布；原Sites第20版、GitHub main及用户接受的赵云行走不变。

### 保源命中与同帧时钟：已接入开发项目的限定候选

上一轮d9e3425已推送GitHub，刃向候选未部署。本轮重新区分“成功刺入身体”与“武器被硬挡住”：原Main对所有非evade结果统一锁枪，modifier甚至在命中前把身体胶囊当不可穿硬物，再以全身历史姿态回拉。实际A/B三距三连显示，保留源全身和双掌握杆可以保住发力/收枪；旧链近/中/空挥最大髋改写约6.16/13.41/15.01cm，新链源到最终骨位置差0。但近身会刺入过深，J2→J3仍有约18.48度/tick源衔接，不能因此接受整套。

开发项目现仅对玩家赵云步战普通攻击启用这项候选，并把真实receive结果持久记录到本招：hit/heavy_hit为flesh，block/parry/break为hard。实际命中后对手再举挡不会重写本招，挡后放挡/破防转stagger仍保留旧抵抗恢复。最初原型Idle默认保源意外清了未支持的K/skill恢复，已否决该scope；最终只在当前允许的active light attack保源，Idle/move走原链。若新招开始时旧恢复flags未清，本招整段opt-out，不在中途跳回source。限定K/Q退出与原版同输入逐帧骨位置差0、恢复flags完全相同；不是宣称全部旧功能回归已通过。

另修正同角色时钟：原父Fighter判定后子AnimationPlayer才前进，同帧真实枪位在中距/空挥最大相差24.807cm。候选手动推进当前普通攻击、执行原CharacterBody移动、同步双掌武器，再同步发出判定；不全局defer。当前仓库原生9秒/540帧实际录制中，近/中/远52次请求的判定枪尖与同帧实绘最大差1.933µm，保源帧源到最终骨世界位置差0；近/中仍18+21+28=67伤害，6m为0。中距实际命中比旧钟提前1–2tick，按新的真实接触保留，不声称命中时刻不变。真实Zhao敌先手在F11击中玩家HP102，同tick scope和manual clock均清理；Machao先手的尝试没命中，只记录为miss，不拿API调用充数。

该候选已接入codex/hero-combat-quality的实际Godot项目，仍是WIP；未同步到main/原Sites。NPC、其他招式/角色、硬抵抗姿态、动态AI/实时时停与音效、整套连续动作和Web性能均未由本轮批准。已接受的赵云GLB23ba、前后2.85/1.05m/s和源步态不变。

### 许褚收刀与跑动入口

9fbc托刀平台的原因是.55–.75固定刀角/腕目标，并保留源腕局部姿态。进一步的刀路反推肘方案2da9虽继续下沉并内收，实片却出现高肘夹胸，另一个145度样片刀尖穿地，均拒绝。改为先作者自然低肘、前臂和腕，再由FK生成刀路；0–.55主刀保持9fbc，身体/脚/自由左手/时钟不动。连续SO(3)曲线经过三姿而不逐点停住，最终50ebed213d9f4d90e12935474d6b992ae75e9815774037a2b366134b78ff8a55可从仓库源完整重建。

50eb已完成独立实战10场景、正常14秒/近腕3秒；实际尾modifier主刀刃向、刃面、锐刃点和刀尖与9fbc差≤1.31e−7，命中/落空结果保留。低肘收回较长臂托刀改善，但.55–.667仍稍停，.75–.9集中立刀像额外归架一拍，承重不成熟；原Run→K、Ready→J、Hit衔接未变。仅准继续隔离实战/动作审查，未替换正式许褚模型。

Run→K固定.25秒全腿惯性在四个真实W步相均完成A/B：虽减轻瞬间抽脚，接地相位却先倒退/抬起支撑鞋再前回，腾空相位延长悬空，上下身错时。方案一明确拒绝，不继续扫参数。官方CMU Kendo项目有论文描述却没有公开数据入口/对应许可；09_01原件只有148帧且末尾仍在跑，没有可用停止段。本轮未取得新过渡源，不用公开视频或未知许可补造资产。

### 录制可信度修正

原生窗可能接收桌面键鼠；一批入口片出现F2无脚本命令的攻击/闪避，全部标INVALID并重录。其他旧片已逐条核actions与commands才保留，不能谎称当时已完全隔离物理绑定。Main初始化会重新补InputMap事件，因此维护的capture现在在角色初始化之后清空物理event，保留原action、bridge与Main输入消费者，并记录剩余event数量。当前仓库直接录制确认数量0、所有action对应脚本命令。动态game脚本加载失败也会立即退出，避免空节点重复错误被误作有效录制。捕获完整性仍只是时钟/图像证据，不是美术绿灯。

### 首次命中前临时举挡：已抓到的开发版退化

95932de已提交并推送GitHub开发分支，仍未部署。本轮继续对2.3m、玩家F6起招、敌方F12/15/18临时举挡的三种真实时机作旧钟/新钟A/B，初始化后物理绑定均为0。旧钟三例均F21起弹反，新钟均F20；当前候选的枪轴单帧最大跳变从45.586度增至56.720度，明确为未通过边界，不能把先前三距离肉身命中结果外推到这里。

两个只改时钟交接的临时方案都没有解决动作。首个根据动画position判断补拍，会与晚到的Physics自动更新重叠而推进两次；改为手动完整负责交接拍并在物理帧结束后归还时钟，时间序列正常了，枪轴仍约56.06度跳变。两方案均未合入当前Godot项目。

分层采样表明，弹反后pre-contact与final枪轴跳变相同，CombatMotion在stagger的活动权重为0；大幅变化已在动画混合输出里。两掌距离从约35.6cm短暂变为20–25cm，枪轴向侧上方过冲，再在GuardBreak完全接管时恢复。下一步需检验双手/武器共同坐标的转接及手臂可达性，而非继续补时钟、改全身长blend或宣称只是晚接触层的问题。完整真实帧/影片、COMPARISON及失败方案留在qa/combat-quality-2026-10-29/prehit-guard-clock。原main/Sites和已接受的步态继续保留。
