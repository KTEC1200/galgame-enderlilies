# ENDER LILIES · 终焉之雨（同人视觉小说）

把《ENDER LILIES: Quietus of the Knights》改编为数据驱动视觉小说。
剧情知识库见仓库根目录（`entities/` `events/` `concepts/` `sources/`），游戏本体在本目录。

> 同人作品 · 免费发布 · ENDER LILIES © Live Wire / Adglobe

## 运行

1. 安装 [Godot 4.4+](https://godotengine.org/download)（标准版即可，不用 .NET 版）
2. 用 Godot 打开本目录（含 `project.godot` 的文件夹）
3. 按 F5 运行

**命令行构建与冒烟测试**：

```
python tools/build_story.py          # 源稿 story-src/*.md → data/*.json（有错不写产物）
godot --headless --path . --import   # 首次/资源变更后导入
godot --headless --path . -- --smoke # 两条分支自动跑通 + 存读档往返校验
```

## 剧情开发工作流（日常只碰 story-src/）

1. 编辑 `story-src/*.md`（格式见 `docs/源稿格式.md`）
2. `python tools/build_story.py` → 0 错误（校验跳转/角色/表情/音乐/flag/不可达节点）
3. `--smoke` 冒烟测试 → 打开 Godot 实玩

## 目录

```
story-src/              剧情源稿（00_设定 + 每场景一个 .md）← 剧情的唯一出处
Main.gd                 运行时（剧情渲染/选项/条件/打字机/存读档）
BgmPlayer.gd            双声道交叉淡入淡出 BGM（支持 Boss Intro→Outro 接力）
data/story.json         编译产物（勿手改）
data/flowchart.json     分支树布局（编译产物）
data/art_index.json     逐页美术需求清单（编译产物，美术生产的依据）
data/music_catalog.json 由 tools/build_music_catalog.py 从仓库 music/ 生成
assets/                 占位美术（按正式规格生成，正式美术覆盖同名文件即可）+ 原作 OST
docs/源稿格式.md         源稿语法
docs/数据规范.md         story.json 节点格式、角色/背景/表情/BGM 命名约定
tools/                  构建脚本（剧情编译器、音乐目录、占位美术）
```

## 当前状态（v0.3）

- ✅ 剧情编译器：Markdown 源稿 → story.json + flowchart + 美术需求清单 + 全量校验
- ✅ 白教区完整样章（5 个场景源稿文件，91 节点 / 72 页 / 4 选项 / 2 分支 + 亡语 + CG 记忆）
- ✅ 三节点剧情引擎（line / stage / jump）+ `when` 条件 + `set` flag + 选项 + 变体文本
- ✅ 打字机、Esc 菜单、多槽存档 / 读档 / 自动续档
- ✅ 38 个 BGM cue（原作 OST），Boss 曲 Intro→Outro 自动接力
- ✅ 旅途图库（CG / 背景 / 立绘三分区，随游玩解锁，点击放大）
- ✅ 剧情分支树（场景块 + 连线，进入新场景自动存检查点，可点击回溯）
- ✅ 旅途回看（最近 200 页）+ 自动播放（1×/2×/4×/8×）+ Ctrl 快进（未读自动停）
- ✅ 游戏设置（倍速 / 打字机 / 音量）+ 进度档案持久化（图库与分支树跨会话保留）
- ⬜ 悬崖村样章（格落特 / 无头骑士）
- ⬜ 正式美术（需求清单见 art_index.json）

## 操作

| 按键 | 作用 |
|---|---|
| 空格 / 回车 / 左键 | 推进 |
| Esc | 菜单（继续/存/读/回标题） |
| H / 右键 | 隐藏或恢复 UI |

## 常用命令（在本目录执行）

```bash
python tools/build_story.py          # 编译剧情
python tools/build_music_catalog.py  # 重新扫描 ../music 生成音乐目录
python tools/make_placeholders.py    # 重新生成占位美术
```
