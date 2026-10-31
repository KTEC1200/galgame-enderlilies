# 交接文档 — ENDER LILIES 同人视觉小说（galgame-enderlilies）

> 生成：2026-10-30；更新：2026-10-31（v0.4.0 修正轮 + 第 06 章合入）。
> **本文已移入仓库根目录（随 git 持久化），D 盘临时副本作废，以此为准。**
> 下一阶段主线：**07~12 章资料包 + Gemini 逐章正文 → 美术成品验证 → 终章正文 → 发布关卡**。
> 本文只写"在哪、怎么跑、坑在哪"，细节一律指向仓库内文档，不重复。

## 1. 工作区

| 位置 | 内容 | 注意 |
|---|---|---|
| `C:\Users\27025\Desktop\iii\enderlilies\` | 用户的剧情知识库（Obsidian vault，GitHub 同步） | **用户明令：剧情和台词原文不许动**（只读）。唯一例外是根 `.gitignore` 里已加 `game/` 一行 |
| `C:\Users\27025\Desktop\iii\enderlilies\game\` | 游戏工程本体 = 独立 git 仓库，remote `git@github.com:KTEC1200/galgame-enderlilies.git`（SSH 可用），分支 main | **所有工作（含交接文档、可行性评估）都在本仓库内进行**；改动一律提交推送 |
| `C:\Users\27025\Desktop\ai game\_extracted\` | 参考游戏《勇者请别攻略队友！》的解包源码与数据（仅作架构参考；该作 README 明确不授权素材复用，不可抄代码/素材） | 只读 |

## 2. 当前状态（截至 2026-10-31 晚，v0.4.0 + 06 章已合入）

- 引擎/功能侧完成并经可行性评估修正：
  **选项级 `@when`**（编译器 + `Main.gd:_visible_choices()` 过滤 + 冒烟覆盖）；`--check` 只读化；
  版本号三处统一 0.4.0（build_story.py / project.godot / 操作说明）；读档槽位校验走
  「章节+场景标题」回退；旧存档新增 flag 按 initial_flags 补默认值。
- **编译器三处加固**（Gemini 初稿踩坑暴露）：
  ① 台词行尾（亡语）标记此前导致亡语页整行按旁白裸露渲染——样章 02 西丽德亡语页在
  已发布包中即受影响，已修复（剥离标记 + groan 标记）；
  ② `##小标题` 与正文同块会**静默丢弃内容**，已改为编译报错；
  ③ frontmatter `cast:` 列表空格未 strip，已修复。
- **白教区样章可玩（01~05）+ 悬崖村正文已合入（06，69 节点/53 页）**：Gemini 初稿
  引用池 15 组全部逐字命中、白名单零越界；合入侧修复指令分块、恢复被吞块、台词按节拍分页。
  待美术：village_square 背景、gerold_memory CG（已入 art_index）。
- **终章 13 是可编译可玩的路由原型**（占位正文）：「追忆」页补齐石板 → 三选项路由
  （C 需八枚 relic 齐全才显示）→ 三结局经 `#coda` 独立收束。
- 石板方案定稿（「保留收集方案」）：relic_1 于 05 章主线必得；relic_2~7 随 06~11 主线
  （relic_2 已在 06 章置位）；relic_8 于 12 章可选探索，终章追忆可补齐。
- **章节资料包制落地**：模板见 `docs/章节资料包/06_悬崖村.md`（原文引用池逐字编号 +
  白名单 + 提纲草案 + 交付规则 + 合入侧检查单）；07~12 章照此模板换素材即可。
- 剧情计划 v0.4 修订：`docs/剧情规划.md`（改编边界、事件依赖表、资料包规范、
  分阶段验收、发布授权关卡）。
- Windows 导出包 v0.4.0 已验证（干净用户数据环境 SMOKE PASS，exit 0）；
  `export/ENDERLILIES-VN-v0.4.0-Windows-x64.zip`（未入 git）。v0.3.1 旧包仅作存档。

## 3. 怎么跑（在 `game/` 目录）

```bash
python tools/build_story.py [--check]   # 源稿 → data/*.json；--check 只读校验不写产物
python tools/build_music_catalog.py  # 重扫 ../music 生成音乐目录（一般不用跑）
python tools/make_placeholders.py    # 重新生成占位美术
# 冒烟测试（Godot 二进制位置见第 4 节）
godot --headless --path . --import   # 首次/资源变更后
godot --headless --path . -- --smoke # 必须 SMOKE PASS（两分支+全正文+终章路由+回溯+面板+设置）
# 导出
godot --headless --path . --export-release "Windows Desktop" export/enderlilies-vn.exe
```

验收标准：编译 0 错误 + SMOKE PASS（美术缺失警告属占位阶段预期，计入 art_index 待办）；
逐项清单见 `docs/剧情规划.md` 第七节。导出包可用
`enderlilies-vn.exe --headless -- --smoke` 验证（exit 0 = PASS）。

## 4. 环境备注（换会话可能失效，重取方式在括号里）

- Godot 4.5 二进制本次放在 `/tmp/godot-dl/Godot_v4.5-stable_win64_console.exe`（临时区，
  会清）。重取：`https://github.com/godotengine/godot-builds/releases/download/4.5-stable/Godot_v4.5-stable_win64.exe.zip`，
  本机 GitHub 直连不稳，前缀 `https://ghfast.top/` 镜像可用（git 克隆用 `https://gitclone.com/github.com/...`）。
- 导出模板已装到 `%APPDATA%\Godot\export_templates\4.5.stable\`（丢失则重新下载
  `Godot_v4.5-stable_export_templates.tpz`）。
- git 身份已配好（全局 user.name=KTEC1200）；推送偶发 `repository exists` 报错，重试即可。

## 5. 已踩过的坑（不要重蹈）

1. GDScript `strip_edges()` 只接受 bool，不接受字符集；截字符用 `lstrip/rstrip`。
2. GDScript 闭包函数体若引用外部循环变量而非参数，会静默用到旧值（编译器曾因此把 flag 存成字符串）。
3. **导出 exe 会因 user://logs 里"编辑器会话遗留的旧日志"在启动时段错误**（模板日志轮转 bug）。全新环境无此问题，但若导出包启动即崩，先清 `%APPDATA%\Godot\app_userdata\enderlilies-vn\logs\`（导出新包前顺手清一次）。
4. `Array.back()` 返回 Variant，`:=` 推断会报错；需显式类型。
5. 数据驱动红线：剧情只存在于 story-src/*.md；改剧情永远走编译器，不手改 data/*.json；新 flag 必须登记 `00_设定.md` 的 initial_flags（编译器会拦截）。
6. **选选项必须走 `Main.gd` 的 `_visible_choices()`**（选项级 `@when` 过滤后的列表）；按原始 `choices` 数组按索引选会选中隐藏选项、死循环（冒烟已改）。
7. 选项下缩进的 `@when` 是**该选项**的条件；页面块首的 `@when` 作用于整页——别混用。
8. **指令必须独立成块**：`@bg/@cg/@music` 与正文之间空行分隔，`##小标题` 独占一块（否则报错或曾静默吞内容）；`@reaction` 例外，须与作用的台词同块。
9. **行尾（亡语）标记**写在台词 」 之后（编译器剥离并打 groan 标记）；冒烟查流程不查渲染内容——引用逐字核对必须人工/脚本做，冒烟不能替代。

## 6. 下一阶段任务（按优先级）

1. **07~12 章正文**：照 `docs/章节资料包/06_悬崖村.md` 模板逐章做资料包（换素材行号、
   白名单、提纲；先核对文本集行号内容再用）→ Gemini 三次对话法（提纲→正文→编译报错回传）→
   每章合入跑编译 + 冒烟 + 引用核对 + 实玩。已登记 flag：relic_2~8、cleared_village~castle；
   gerold 已登记 cast_names，各章新说话人照此先登记。
2. **06 章实玩验收**（你）：打开 Godot 通读一遍演出节奏与 BGM 衔接；顺手记录本章实际耗时校准排期。
3. **美术成品场景验证（批量前门禁）**：lily/knight 常用表情立绘 + 1 背景 + 1 记忆 CG
   按正式规格做一版实玩确认，再按 `data/art_index.json`（当前 28 项）分批替换占位图。
4. **终章 13 正文**：路由结构已就绪，替换占位页（文本集 205-282、769-924）；建议 12 章后做。
5. **发布关卡**（`docs/剧情规划.md` 第八节）：OST 授权核查或换原创/许可配乐 →
   文本/角色改编范围确认 → 才可上架 itch.io；发新版前做跨版本存档验证。
6. 可选打磨：存档槽缩略截图、Gemini 产出 lint 规则（每页字数上限）。
   （BGM 双声道交叉淡化 1.2s 已内建于 `BgmPlayer.gd`，不再是待办。）

## 7. 建议技能（本环境可用）

- `implement`：执行第 6 节的具体编码任务
- `code-review`：合入 Gemini 产出的章节前过一遍源稿与编译产物
- `github:release`：把 zip 发布为仓库 Release（比让用户手动传方便）
- `handoff`：下次交接时更新本文档（**本文已在仓库内**，直接改这份即可）
