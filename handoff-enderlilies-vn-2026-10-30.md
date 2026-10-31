# 交接文档 — ENDER LILIES 同人视觉小说（galgame-enderlilies）

> 生成：2026-10-30；更新：2026-10-31 晚（**全篇剧情完成 + 素材许可取得**）。
> **本文在仓库根目录，随 git 持久化，以此为准。**
> 当前阶段：**全篇实玩验收 → 美术/音乐/UI → 发布（授权已解决）**。
> 本文只写"在哪、怎么跑、坑在哪"，细节一律指向仓库内文档。

## 1. 工作区

| 位置 | 内容 | 注意 |
|---|---|---|
| `C:\Users\27025\Desktop\iii\enderlilies\game\` | 游戏工程本体 = 独立 git 仓库，remote `git@github.com:KTEC1200/galgame-enderlilies.git`，分支 main | **所有工作都在本仓库内**；改动一律提交推送。仓库建议保持 Private（除音频外还含全部改编文本） |
| `C:\Users\27025\Desktop\iii\enderlilies\` | 剧情知识库（Obsidian vault，GitHub 同步） | **只读**（剧情和台词原文不许动）；`sources/ENDER LILIES 文本集.md` 是台词唯一权威来源 |

## 2. 当前状态（2026-10-31 晚）

- **剧情全部完成**：第一章（`01_白教区.md`，由 01~05 合并的单文件版）+ 06~12 七个
  区域章 + 13 终章三结局。9 个场景文件 / 466 节点 / **322 页** / 18 选项 / 21 flag；
  A/B/C 三路线冒烟全通（A 299 页、B 300 页、C 路由条件测试通过）。
- 引擎 v0.4.0 要点：**选项级 `@when`**（编译器 + `_visible_choices()` + 冒烟）、
  读档按「章节+场景标题」回退、旧存档新增 flag 补默认值、编译器加固
  （（亡语）标记剥离 / `##` 块校验 / cast 空格 strip）。
- **工具链 Godot 4.7.2**（2026-10-31 起统一）；`user://` 重定向到
  `%APPDATA%\enderlilies_vn_data`（原因见坑 10）。
- **验收工具链**：`tools/check_quotes.py` 引用核对（必引/可选/备选分级）已纳入
  每章合入流程；`tools/build_story.py --check` 只读校验。
- **素材许可已取得（2026-10-31，作者确认）**：OST 配乐方案保留，发布关卡中的
  授权项解除。许可凭证建议存档（如 `docs/licenses/`）。
- 音频已移出 git 跟踪（`assets/audio/` 本地保留，见坑 10 相关说明）。
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

## 6. 下一阶段任务（按优先级）

1. **全篇实玩验收（作者）**：A/B/C 三结局各通一遍 + 试一次「故意漏石板 → 终章追忆补齐」；
   记录节奏与文本问题，交合入侧修。
2. **美术**：先做成品场景验证门禁（lily/knight 常用表情立绘 + 1 背景 + 1 记忆 CG），
   通过后按 `data/art_index.json`（当前 66 项：立绘 32 / 背景 25 / CG 9）分批替换
   占位图，覆盖同名文件即可。
3. **音乐调整与 UI 美化**（作者提出的待办）；BGM 双声道交叉淡化已内建。
4. **发布**：装 4.7.2 导出模板 → 出新版本包（建议 v0.5.0，同步三处版本号：
   build_story.py / project.godot / 操作说明）→ itch.io 上架（授权已解决；
   页面署名按许可范围核对）。
5. **发布前全篇验收矩阵**：A/B/C 条件矩阵、缺石板矩阵、条件选项存读档一致性、
   跨版本存档验证（旧档按「章节+标题」迁移）、干净环境导出包实读。

## 7. 建议技能（本环境可用）

- `implement`：执行具体编码任务
- `code-review`：合入章节前过一遍源稿与编译产物
- `github:release`：把 zip 发布为仓库 Release
- `handoff`：下次交接时直接更新本文档
