# 交接文档 — ENDER LILIES 同人视觉小说（galgame-enderlilies）

> 生成：2026-10-30；更新：2026-11-01（**全篇扩写完成：935 对话页 + 通读终审修复；同日原作素材提取完成，美术清单大减**）。
> **本文在仓库根目录，随 git 持久化，以此为准。**
> 当前阶段：**全篇实玩验收 → 美术/音乐 → 发布（授权已解决）**。
> 本文只写"在哪、怎么跑、坑在哪"，细节一律指向仓库内文档。

## 1. 工作区

| 位置 | 内容 | 注意 |
|---|---|---|
| `C:\Users\27025\Desktop\iii\enderlilies\game\` | 游戏工程本体 = 独立 git 仓库，remote `git@github.com:KTEC1200/galgame-enderlilies.git`，分支 main | **所有工作都在本仓库内**；改动一律提交推送（含音频与剧情文本） |
| `C:\Users\27025\Desktop\iii\enderlilies\` | 剧情知识库（Obsidian vault，GitHub 同步） | **只读**（剧情和台词原文不许动）；`sources/ENDER LILIES 文本集.md` 是台词唯一权威来源 |

## 2. 当前状态（2026-10-31 深夜）

- **剧情全部完成**：第一章（`01_白教区.md`，由 01~05 合并的单文件版）+ 06~12 七个
  区域章 + 13 终章三结局。9 个场景文件 / 466 节点 / **322 页** / 18 选项 / 21 flag；
  A/B/C 三路线冒烟全通（A 299 页、B 300 页、C 路由条件测试通过）。
- 引擎 v0.4.0 要点：**选项级 `@when`**（编译器 + `_visible_choices()` + 冒烟）、
  读档按「章节+场景标题」回退、旧存档新增 flag 补默认值、编译器加固
  （（亡语）标记剥离 / `##` 块校验 / cast 空格 strip）。
- **v0.5 UI 重构（实测优化清单全项落地，SMOKE PASS）**：
  - 游戏名统一「终焉之雨」（窗口标题 / 标题页 / 导出元数据 / story-src 标题元数据），
    版本号三处对齐 0.5.0（project.godot / build_story.py / README）。用户数据目录名
    `enderlilies_vn_data` **未改**（保住旧存档与图库/分支树进度）。
  - **鼠标点击推进修复**：根 Control 默认 STOP 吞掉全部点击（空格能推、鼠标不动的
    根因），`_ready` 里 `mouse_filter = MOUSE_FILTER_IGNORE` 解决。
  - 输入增强：滚轮↓推进（等价一次空格）、滚轮↑直接打开历史、右键关附加面板
    （Extras `_input`）/ 关弹窗 / 隐藏 UI；对话框快捷条新增「快进」开关（遇选项自动停）。
  - 跳过系统：`skip_unread` 布尔 → `skip_mode`（read=已读跳过 / all=全部跳过），
    旧 profile 自动迁移；打开任何面板自动退出快进。
  - 自动推进卡顿主因 = 每页同步写续玩存档；已改去抖（`resume_dirty` + progress_timer
    统一落盘）。打字速度与自动倍速解耦，新增 `text_speed`（字/秒）。
  - 设置页两列重排（深底/蓝主色/黄绿点缀/投影立体感）：对话字号 20~40、文字速度
    10~90 字/秒（新）、自动前进 1×~8× 均为滑杆；逐字显示胶囊开关；画面尺寸下拉
    （全屏 / 2560×1440 / 1920×1080 / 窗口，随 profile 持久化）。
  - 分支树：一行三列网格卡片（Extras 覆盖编译器长条坐标，不改编译器产物）、
    「已完成 X / Y」计数修正（`_load_profile` 清掉重编译后失效的 flow_seen/checkpoints
    旧块 id）、当前所在块黄绿描边。
  - 新增 `--shots` 截图调试模式（标题/对话/设置/分支树/分支树锁定态五张，
    输出 `SHOTS_DIR`），与 `--smoke` 平级。
- **v0.5 实测返修两轮（2026-10-31 深夜，均 SMOKE PASS + 实图/合成点击验证）**：
  - 菜单按钮死路由：快捷条发 `"menu"` 但 `_menu()` 只有 `"game_menu"` 分支，
    按钮自 v0.3 起从未生效；已补分支（见坑 13）。
  - 设置页移除「关于」分区，操作提示贴面板底部；分支树未解锁块灰色锁定、
    disabled 不可点、光标不变手型。
  - **标题界面弹窗「看得见点不到」**：GUI 命中测试按子节点树序、不看 z_index，
    title_screen 建在 overlay 之后吞掉全部点击（读取/保存弹窗只能 Esc 关）；
    修复 = `_build_ui` 先建 title_screen 再建 overlay（见坑 12，真实窗口合成点击验证）。
- **工具链 Godot 4.7.2**（2026-10-31 起统一）；`user://` 重定向到
  `%APPDATA%\enderlilies_vn_data`（原因见坑 10）。
- **v0.6 全篇扩写（2026-11-01，作者三次校准后定稿）**：
  - 体量：**466 → 1103 节点（956 对话页）**，SMOKE 919/909 页；每章 +80~90
    （06 三拍补写后 108），13 +50 / 01 +65。A/B/C 三结局路由零改动。
  - 管线：Gemini CLI（gemini-3-flash-preview，代理 127.0.0.1:18788 +
    `NODE_USE_ENV_PROXY=1`）逐章起草 → 合入侧 `tools/gate_expansion.sh`
    （子序列门禁：原文引文/正文行按序完整，英文行可后置、@ 指令行须逐字存在）
    → 编译/引用/SMOKE 三关 → 每章一 commit。配额耗尽按作者授权 GLM 直写
    （09 二轮/10/13/01），提交信息已注明引擎。
  - 作者三次校准（最终版）：①引文可拆页穿插衔接（句字面不动）；②加量至 1000+；
    ③每章 Boss 战序列 8~12 页 + 遭遇战 1~2 场；④英文题词页后置到遗物后/章末
    （13 章三处因与结局场景直接关联原地保留）；⑤闲置 flag 变体回响
    （observed/curious、thanks/nod 已启用）。
  - **通读终审（独立代理逐行读完 9 章 + vault 对照）已修复**：P0 两处——06 章提前
    叫破「莉莉」（保住 09 章首次命名戏）、10 章引-04 亡语牌误用 miriel（实为
    梅尔维尔=花之魔女恋人，已改群像无名牌）；P1：01「我会再来的」/圣水两支
    契诃夫枪在 13 章回收、12 章礼冠替代与 vault 矛盾的「腐朽的王冠」、12 章补
    尤利乌斯安置堡垒孩子钩、08 心声 3→2；P2 打磨若干；06 章补三拍 23 页
    （归乡/寂寞的英雄/雨停的那一天）。终审定调：「人造的白巫女怀着真的心」
    由物件链（念珠/头饰/脚链/面具/木壶/委托书）托住，感情线三强两弱报告已留档。
  - 新增 `docs/攻略.md`（A/B/C 通法 + 石板收集 + 追忆补齐）。
  - 新增 `docs/美术需求.md`（作者开工用完整清单：25 背景 / 12 角色 34 立绘 / 9 CG /
    标题图，含规格、画面内容描述、场景对照与 P0~P3 交付顺序；assets/ 现状=全部占位图，
    覆盖同名文件即替换，表情缺字自动回退 normal）。
  - **自定义字体已接入（2026-11-01）**：`assets/fonts/lily.ttf`（作者提供，3.4MB），
    `_build_theme()` 里作为全游戏主题主字体，缺字回退链 = 微软雅黑 UI → 雅黑 → SimHei；
    已截图验证标题/菜单/对话框全部生效，SMOKE PASS。改字体只动 `_build_theme()` 一处。
- **原作素材提取完成（2026-11-01，授权已解决）**：
  - 产出在 `D:\K\zcode\enderlilies_spine\<角色>\`：**123 角色 × (.skel + .atlas + .png)**
    三件套，骨骼为 **Spine 3.8.99** 二进制（含全部动画）。VN 需要的 12 角色全齐：
    lily=p0001~p0006_Lily（六套皮肤）、knight=s5000_Unknown、siegrid=e5030_Leader、
    shilda=e5020_Old_Sister（+妹妹 e5010）、elaine=e5040_Witch、gerold=e5050_Giant、
    helnir=e5060_Assassin、wolf=e5070_Killer、shield=e2030_Big_Knight、faden=n5080_Alchemist。
    游戏源数据在 `D:\HY\EnderLilies`，FModel 在 `D:\K\galgame\UE`。
  - **渲染已验证**：`D:\K\galgame\UE\SpineViewer\SpineViewerCLI.exe export <skel>
    --atlas <atlas> -f Png -o out.png -a "locomotion/idle" --skins "<包名>"
    --color "#00000000"` → 透明站姿 PNG（Lily 实测成功）。`--skins` 必须指定
    （默认无皮肤=空图）；动画列表用 `query <skel> --animation` 查；颜色只认
    `#RRGGBB`/`#AARRGGBB` 格式。
  - 提取工具 `D:\K\zcode\tools\SpineExtract\`（C# net8 + CUE4Parse 1.2.2，
    `dotnet run` 即可重导）。**坑**：①本 pak 是 IoStore+Zlib，CUE4Parse 不自动初始化
    原生解压库，需下载 `zlib-ng2.dll` 进 exe 目录并反射调
    `ZlibHelper.Initialize(path)`；②骨骼不在独立资产，在每角色包内
    `SpineSkeletonDataAsset` 导出的 **`rawData`** 字节属性里（组件上的 `skeletonData`
    只是对象引用）；③79/120 贴图顶 mip 不在本地文件，只有**半分辨率**（atlas 坐标
    是归一化 UV 所以渲染正确，游戏实机即此清晰度；生图补正可用渲染帧当底图）。
  - **美术清单影响**：10/12 角色 normal 可骨骼渲染，无需生图；**仍需生图** =
    fretia（normal+soft+worried）、julius（normal+worried）两张整卡 +
    其余角色表情差分 12 张（可用渲染 normal 当 img2img 底图保画风）+
    背景 25 / 标题 1 / CG 9（无游戏数据，维持原计划）。
  - **10 角色 normal 已渲染完成（2026-11-01）**：`D:\K\zcode\enderlilies_spine\renders\<vn>.png`
    （lily/knight/siegrid/shilda/elaine/gerold/helnir/faden/wolf/shield，透明底已自动裁边，
    原始帧在 renders/raw/）。批量脚本 `D:\K\zcode\tools\SpineExtract\render_batch.sh`
    （自动选 idle 动画+空图重试，可重跑）。注意：Boss 们是**污化战斗待机形态**
    （红眼/持武器，Boss 战场景直接可用）；faden 只有坐姿动画（游戏数据如此），
    记忆场景需要的"生前干净形态/温柔站姿"仍需按渲染底图生图。
  - **实机验证通过（2026-11-01）**：`assets/sprites/` 下 **12 角色normal 已全部入库**
    （10 张骨骼渲染 + fretia/julius 仍缺待生图），`--shots` 截图确认对话场景立绘显示、
    非说话人压暗、UI 搭配全部正常。
  - **`docs/美术需求.md` 已重写为生图工单（2026-11-01）**：作者照着做即可——
    待生成 = fretia/julius 整卡 5 张 + 表情差分 15 张（底图 img2img，路径在文内）+
    背景 25 / CG 9（含 ev 缩略图构图对照）/ 标题 1；含背景 MapImg 参考图池、
    CG 构图参考列、污化/干净形态决策点（4.3 节）。
- **验收工具链**：`tools/check_quotes.py` 引用核对（必引/可选/备选分级）已纳入
  每章合入流程；`tools/build_story.py --check` 只读校验。
- **素材许可已取得（2026-10-31，作者确认）**：OST 配乐方案保留，发布关卡中的
  授权项解除。许可凭证建议存档（如 `docs/licenses/`）。
- 音频已入库（`assets/audio/` 38 首 OST，作者确认后恢复跟踪）。
- Windows 导出包 v0.4.0 为旧版（不含 07~13 与 4.7 迁移），仅作存档；
  **下次导出前需安装 4.7.2 导出模板**。

## 3. 怎么跑（在 `game/` 目录）

```bash
python tools/build_story.py [--check]   # 源稿 → data/*.json；--check 只读校验不写产物
python tools/check_quotes.py            # 引用核对（必引缺漏=错误，池外项人工判断）
python tools/build_music_catalog.py     # 重扫 ../music 生成音乐目录（一般不用跑）
python tools/make_placeholders.py       # 重新生成占位美术
# 冒烟测试
Godot --headless --path . --import   # 首次/资源变更后
Godot --headless --path . -- --smoke # 必须 SMOKE PASS（双分支全篇+终章路由+回溯+面板+设置）
Godot --path . -- --shots            # UI 截图调试（SHOTS_DIR 指定输出目录，弹真窗口几秒）
# 导出（先装 4.7.2 导出模板）
Godot --headless --path . --export-release "Windows Desktop" export/enderlilies-vn.exe
```

（Godot 二进制位置见第 4 节。）每章合入验收清单见 `docs/剧情规划.md` 第七节：
编译 0 错误 + 引用核对 + SMOKE PASS + 占位移除 + 实玩。

## 4. 环境备注（换会话可能失效，重取方式在括号里）

- Godot 4.7.2 二进制在 `game/Godot_v4.7.2-stable_win64.exe/`（已 gitignore）。
  重取：`https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip`，
  本机 GitHub 直连不稳，前缀 `https://ghfast.top/` 镜像可用。
- 导出模板目前只有 `4.5.stable`（`%APPDATA%\Godot\export_templates\`）——**导出前
  需装 4.7.2 模板**（`Godot_v4.7.2-stable_export_templates.tpz`）。
- git 身份已配好（全局 user.name=KTEC1200）；推送偶发 `repository exists` 报错，重试即可。
- 用户数据（存档/图库/设置）在 `%APPDATA%\enderlilies_vn_data\`（不在工程目录内）。

## 5. 已踩过的坑（不要重蹈）

1. GDScript `strip_edges()` 只接受 bool；截字符用 `lstrip/rstrip`。
2. GDScript 闭包引用外部循环变量会静默用旧值；`:=` 遇 Variant 推断会报错（需显式类型）。
3. **导出 exe 会因 user://logs 旧日志启动段错误**；导出新包前清 `%APPDATA%\enderlilies_vn_data\logs\`。
4. `Array.back()` 返回 Variant，`:=` 推断会报错；需显式类型。
5. 数据驱动红线：剧情只存在于 story-src/*.md；改剧情永远走编译器，不手改 data/*.json；新 flag 必须登记 `00_设定.md` 的 initial_flags。
6. **选选项必须走 `Main.gd` 的 `_visible_choices()`**；按原始 choices 数组按索引选会选中隐藏选项、死循环。
7. 选项下缩进的 `@when` 是**该选项**的条件；页面块首的 `@when` 作用于整页——别混用。
8. **指令必须独立成块**（`@bg/@cg/@music` 与正文之间空行、`##小标题` 独占一块）；`@reaction` 例外，须与台词同块。Gemini 初稿最常犯的就是这条。
9. **行尾（亡语）标记**写在台词 」 之后（编译器剥离并打 groan 标记）；冒烟查流程不查渲染——引用核对靠 `check_quotes.py` + 人工。
10. **安全软件按"应用身份"拦截新引擎写旧数据**（4.7.2 写 4.5 时代的存档/同名目录 err=12）；解法 = `use_custom_user_dir` + 换目录名 + 文件由新引擎自建自拥。换引擎大版本时存档再现写入失败，优先怀疑此机制。
11. **台词行之间必须空行分页**——同一块里出现两条台词行（或台词+旁白）会报"混入非台词文本行"；这是 Gemini 初稿第二常见错误，`--check` 可直接定位。
12. **Godot GUI 命中测试按子节点树序（后建者优先），不看 z_index**（z 只管绘制）。
    全屏控件建在弹窗层之后就「看得见点不到」。层级顺序现在是 hud → title_screen →
    overlay → extras（Extras 在 `_ready` 最后挂载，天然最优先）；再调 UI 层级时
    用「调整创建顺序」而不是 z_index，真窗口验证别信无头合成事件（进不了 GUI 命中）。
13. **按钮路由 kind 与 `_menu()` 的 match 分支不匹配 = 静默无效果**（菜单按钮死了一个
    大版本才发现）。新增按钮先把 kind 在 match 里补上；GDScript 对未命中分支零警告。

## 6. 下一阶段任务（按优先级）

1. **全篇实玩验收（作者）**：A/B/C 三结局各通一遍（一周目约 919 页）+ 试一次
   「故意漏石板 → 终章追忆补齐」；重点感受扩写后各章的节奏（战斗序列/支线/回忆），
   记录问题交合入侧修。攻略见 `docs/攻略.md`。
2. **美术**：清单见 `docs/美术需求.md`。**（2026-11-01 更新）原作骨骼数据已提取**
   （见第 2 节）：10/12 角色 normal 由骨骼渲染直出（不再生图），作者只需生图
   **fretia/julius 整卡 5 张 + 表情差分 12 张** + 背景/标题/CG（P3 量不变）。
   合入侧批量渲染 → auto-crop → 入 `assets/sprites/` 覆盖占位，覆盖同名文件即替换，
   缺表情自动回退 normal，可随时分批验证。
3. **音乐调整**（作者提出的待办）；BGM 双声道交叉淡化已内建。UI 美化 v0.5 已完成，
   后续微调直接改 Main.gd 调色板常量与 Extras.gd 小部件。
4. **发布**：装 4.7.2 导出模板 → 出新版本包（建议 v0.6.0，同步三处版本号：
   project.godot / build_story.py / README）→ 导出前清
   `%APPDATA%\enderlilies_vn_data\logs\`（坑 3）→ itch.io 上架（授权已解决；
   页面署名按许可范围核对）。
5. **发布前全篇验收矩阵**：A/B/C 条件矩阵、缺石板矩阵、条件选项存读档一致性、
   跨版本存档验证（旧档按「章节+标题」迁移）、干净环境导出包实读。

## 7. 建议技能（本环境可用）

- `implement`：执行具体编码任务
- `code-review`：合入章节前过一遍源稿与编译产物
- `github:release`：把 zip 发布为仓库 Release
- `handoff`：下次交接时直接更新本文档
