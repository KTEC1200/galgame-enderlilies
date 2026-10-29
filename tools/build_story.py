# -*- coding: utf-8 -*-
"""剧情编译器：story-src/*.md  ->  data/story.json + flowchart.json + art_index.json

源稿格式（详见 docs/源稿格式.md）：
  - 每个场景一个 .md 文件，frontmatter 声明 id/chapter/title/bg/music/cast
  - 00_设定.md 为全局配置（config: true），含 cast_names 与 initial_flags
  - 空行分页；普通文本=旁白；`角色id(表情)「台词」`=对话
  - `@bg/@music/@cg/@cast/@set` 独立成块 = stage 节点；`@reaction` 附于当页
  - `@when k=v,k!=v,k>=n` 附于下一页；`| when: k=v | 文本` = 变体
  - `* 选项文本 -> 目标` = 选项，缩进的 `@set` 附于该选项；`-> 目标` 独立成块 = jump
  - `#标签` 给下一页命名；`## 标题` 改场景标题；`//` 注释

校验：跳转目标、角色/表情/背景/音乐/CG 引用、flag 未初始化、不可达节点。
用法：在 game/ 目录执行  python tools/build_story.py [--check]
"""
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME_DIR = os.path.dirname(HERE)
SRC_DIR = os.path.join(GAME_DIR, "story-src")
OUT_DIR = os.path.join(GAME_DIR, "data")

EXPRESSIONS = {"normal", "happy", "shy", "angry", "surprised", "worried", "serious", "soft"}
DIALOGUE_RE = re.compile(r"^(我|[a-z][a-z0-9_]*)(?:\((\w+)\))?「(.+)」$")
DIRECTIVE_RE = re.compile(r"^@(bg|music|cg|cast|set|reaction|when|title|chapter)\b\s*(.*)$")
COND_RE = re.compile(r"^([a-z][a-z0-9_]*)(==|!=|>=|<=|=)(.+)$")

errors = []
warnings = []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def parse_value(text):
    text = text.strip()
    if text == "true":
        return True
    if text == "false":
        return False
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    return text


def parse_condition(text, where):
    """k=v / k!=v / k>=n / k<=n 的逗号列表 -> when 字典"""
    when = {}
    for part in re.split(r"[,，]", text):
        part = part.strip()
        if not part:
            continue
        m = COND_RE.match(part)
        if not m:
            err("%s: 无法解析条件 %r" % (where, part))
            continue
        key, op, value = m.group(1), m.group(2), parse_value(m.group(3))
        if op in ("=", "=="):
            when[key] = value
        elif op == "!=":
            when[key] = {"neq": value}
        elif op == ">=":
            when[key] = {"gte": value}
        elif op == "<=":
            when[key] = {"lte": value}
    return when


def parse_frontmatter(text, path):
    fm = {}
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end < 0:
            err("%s: frontmatter 未闭合" % path)
            return fm, text
        for line in text[3:end].splitlines()[1:]:
            if not line.strip() or line.strip().startswith("#"):
                continue
            key, _, value = line.partition(":")
            fm[key.strip()] = value.strip()
        text = text[end + 4:]
    return fm, text


def split_blocks(text):
    blocks, current = [], []
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        if not stripped:
            if current:
                blocks.append(current)
                current = []
        else:
            current.append(line)
    if current:
        blocks.append(current)
    return blocks


def resolve_target(raw, fileid, id_set, where):
    """选项/跳转目标 -> 全局节点 id 字符串"""
    raw = raw.strip()
    if raw == "next":
        return "next"
    if "#" in raw:
        fid, label = raw.split("#", 1)
    else:
        fid, label = fileid, raw
    key = "%s_%s" % (fid, label)
    if key in id_set:
        return key
    if raw in id_set:  # 允许直接写完整节点 id
        return raw
    err("%s: 跳转目标不存在 %r" % (where, raw))
    return None


def compile_file(path, config):
    """返回 (nodes, labels, pending_refs, blocks_meta)；pending_refs 待二次解析目标"""
    fileid = os.path.splitext(os.path.basename(path))[0]
    text = open(path, encoding="utf-8").read()
    fm, text = parse_frontmatter(text, path)
    if fm.get("config") == "true":
        return None  # 全局配置文件，不产生节点
    base = fm.get("id", fileid)
    where = fileid

    nodes, labels = [], {}
    refs = []          # (node_index, kind, raw_target, where)
    seq = [0]

    def node_id(label):
        return "%s_%s" % (base, label) if label else "%s_n%03d" % (base, seq[0])

    def new_node(n, label=None):
        nid = node_id(label)
        if nid in labels or any(x["id"] == nid for x in nodes):
            err("%s: 节点 id 重复 %s" % (where, nid))
        n["id"] = nid
        seq[0] += 1
        nodes.append(n)
        if label:
            labels[nid] = len(nodes) - 1
        return nid

    # 文件开头：换场节点（frontmatter 声明的舞台状态）
    opening = {"type": "stage", "date": fm.get("chapter", ""), "title": fm.get("title", "")}
    if fm.get("bg"):
        opening["bg"] = fm["bg"]
    if fm.get("music"):
        opening["music"] = fm["music"]
        parts = fm["music"].split()
        if len(parts) > 1:
            opening["music_outro"] = parts[1]
            opening["music"] = parts[0]
    if fm.get("cast"):
        opening["cast"] = [{"id": p.split("/")[0], "expression": p.split("/")[1] if "/" in p else "normal"}
                           for p in re.split(r"[,，]", fm["cast"]) if p.strip()]
    if len(opening) > 3 or "bg" in opening or "cast" in opening:
        new_node(opening)
    

    pending_when = [None]  # 附于下一页

    def take_when(idx):
        if pending_when[0] is not None:
            nodes[idx]["when"] = pending_when[0]
            pending_when[0] = None

    for block in split_blocks(text):
        first = block[0].strip()
        # --- 标签行 ---
        label = None
        while first.startswith("#") and not first.startswith("##"):
            label = first[1:].strip()
            block = block[1:]
            if not block:
                err("%s: 标签 #%s 后没有内容" % (where, label))
                break
            first = block[0].strip()
        # --- 场景小标题 ---
        if first.startswith("##"):
            new_node({"type": "stage", "title": first.lstrip("#").strip()}, label)
            continue        # --- 独立跳转 ---
        if first.startswith("->"):
            target = first[2:].strip()
            idx = len(nodes)
            new_node({"type": "jump"}, label)
            refs.append((idx, "jump", target, where, base))
            continue
        # --- 纯指令块 = stage ---
        directives = [l.strip() for l in block if l.strip().startswith("@")]
        if directives and all(l.strip().startswith("@") for l in block):
            stage = {"type": "stage"}
            stage_set = {}
            for d in directives:
                m = DIRECTIVE_RE.match(d)
                if not m:
                    err("%s: 无法解析指令 %r" % (where, d))
                    continue
                key, arg = m.group(1), m.group(2).strip()
                if key == "bg":
                    stage["bg"] = arg
                elif key == "music":
                    parts = arg.split()
                    stage["music"] = parts[0]
                    if len(parts) > 1:
                        stage["music_outro"] = parts[1]
                elif key == "cg":
                    stage["cg"] = "" if arg == "off" else arg
                elif key == "set":
                    k, _, v = arg.partition("=")
                    stage_set[k.strip()] = parse_value(v)
                elif key == "cast":
                    cast, mode = parse_cast_spec(arg)
                    stage["cast"] = cast
                    stage["_cast_mode"] = mode
                elif key in ("title", "chapter"):
                    stage[key] = arg
                elif key == "reaction":
                    err("%s: @reaction 只能写在页面块内" % where)
                elif key == "when":
                    pending_when[0] = parse_condition(arg, where)
            if stage_set:
                stage["set"] = stage_set
            if len(stage) > 1:
                new_node(stage, label)
            continue
        # --- 页面块（旁白 / 对话 / 选项）---
        page, choice_refs, label = build_page(block, base, label, fileid, where)
        if page is None:
            continue
        idx = len(nodes)
        new_node(page, label)
        take_when(idx)
        for target, choice_idx in choice_refs:
            refs.append((idx, "choice:%d" % choice_idx, target, where, base))
    return base, nodes, labels, refs


def parse_cast_spec(arg):
    """@cast lily/soft, knight  |  @cast + siegrid/normal  |  @cast - siegrid"""
    mode = "replace"
    arg = arg.strip()
    if arg.startswith("+"):
        mode, arg = "add", arg[1:].strip()
    elif arg.startswith("-"):
        mode, arg = "remove", arg[1:].strip()
    cast = []
    for part in re.split(r"[,，]", arg):
        part = part.strip()
        if not part:
            continue
        role, _, expr = part.partition("/")
        cast.append({"id": role.strip(), "expression": expr.strip() or "normal"})
    return cast, mode


def build_page(block, base, label, fileid, where):
    page = {"type": "line"}
    page_set = {}
    text_lines, dialogue, variants = [], None, []
    choices, choice_refs = [], []
    reactions = []
    current_choice = [None]

    def attach_set_to_choice(value):
        if current_choice[0] is not None:
            choices[current_choice[0]].setdefault("set", {})[k] = value
        else:
            page_set[k] = value

    for raw in block:
        line = raw.strip()
        indent = len(raw) - len(raw.lstrip())
        m = DIRECTIVE_RE.match(line)
        if m:
            key, arg = m.group(1), m.group(2).strip()
            if key == "set":
                k, _, v = arg.partition("=")
                if indent >= 2 and choices:
                    attach_set_to_choice(parse_value(v))
                else:
                    page_set[k] = parse_value(v)
            elif key == "reaction":
                role, _, expr = arg.partition("/")
                reactions.append((role.strip(), expr.strip() or "normal"))
            elif key == "when":
                # 页内 when：视为对下一页的声明（写在块首）
                page["when"] = parse_condition(arg, where)
            else:
                err("%s: 指令 @%s 不能写在页面块内（请独立成块）" % (where, key))
            continue
        if line.startswith("|"):
            body = line.lstrip("|").strip()
            cond_text, _, vtext = body.partition("|")
            variant = {"when": parse_condition(cond_text.replace("when:", "", 1), where)}
            dm = DIALOGUE_RE.match(vtext.strip())
            if dm:  # 变体可整体替换为另一角色的台词
                variant["speaker"] = dm.group(1)
                if dm.group(2):
                    variant["expression"] = dm.group(2)
                variant["text"] = dm.group(3)
            else:
                variant["text"] = vtext.strip()
            variants.append(variant)
            continue
        if line.startswith("*"):
            body = line[1:].strip()
            label_text, sep, target = body.partition("->")
            if not sep:
                err("%s: 选项缺少目标 ->  %r" % (where, body))
                target = "next"
            choices.append({"label": label_text.strip()})
            choice_refs.append((target.strip(), len(choices) - 1))
            current_choice[0] = len(choices) - 1
            continue
        dm = DIALOGUE_RE.match(line)
        if dm and dialogue is None and not choices:
            dialogue = {"speaker": dm.group(1), "text": dm.group(3)}
            if dm.group(2):
                page.setdefault("expression", dm.group(2))
            continue
        text_lines.append(line)
    # 未缩进的 @set 落到页面
    if page_set:
        page["set"] = page_set
    # 组装文本
    if dialogue:
        if text_lines:
            err("%s: 对话块中混入了非台词文本行: %s" % (where, text_lines[0]))
        page["speaker"] = dialogue["speaker"]
        page["text"] = dialogue["text"]
    elif choices:
        page["text"] = "\n".join(text_lines)
    elif text_lines:
        page["text"] = "\n".join(text_lines)
    else:
        err("%s: 空页面块" % where)
        return None, [], label
    if variants:
        page["variants"] = variants
    if reactions:
        page["reactions"] = {r: e for r, e in reactions}
    if choices:
        if not page["text"]:
            err("%s: 选项页缺少引导文本" % where)
        page["choices"] = choices
    return page, choice_refs, label


def main():
    check_only = "--check" in sys.argv
    if not os.path.isdir(SRC_DIR):
        print("找不到源稿目录: " + SRC_DIR)
        sys.exit(1)
    files = sorted(f for f in os.listdir(SRC_DIR) if f.endswith(".md"))
    # 全局配置
    config = {"title": "ENDER LILIES · 终焉之雨", "cast_names": {}, "initial_flags": {}}
    for f in files:
        text = open(os.path.join(SRC_DIR, f), encoding="utf-8").read()
        fm, _ = parse_frontmatter(text, f)
        if fm.get("config") == "true":
            for key in ("title", "cast_names", "initial_flags"):
                if key in fm:
                    config[key] = json.loads(fm[key])
    cast_names = config["cast_names"]
    music_catalog = json.load(open(os.path.join(OUT_DIR, "music_catalog.json"), encoding="utf-8"))
    music_ids = {t["id"] for t in music_catalog["tracks"]}

    all_nodes, ref_lists, file_metas = [], [], []
    for f in files:
        path = os.path.join(SRC_DIR, f)
        result = compile_file(path, config)
        if result is None:
            continue
        base, nodes, labels, refs = result
        offset = len(all_nodes)
        for idx, kind, target, where, base in refs:
            ref_lists.append((offset + idx, kind, target, where, base, f))
        file_metas.append({"file": f, "base": base, "nodes": nodes, "labels": labels})
        all_nodes.extend(nodes)

    # 二次解析跳转/选项目标
    id_set = {n["id"] for n in all_nodes}
    resolved_targets = {}
    for idx, kind, target, where, base, f in ref_lists:
        nid = resolve_target(target, base, id_set, where)
        if nid is None:
            continue
        if nid == "next":
            continue
        resolved_targets.setdefault(idx, {})[kind] = nid
    for idx, mapping in resolved_targets.items():
        for kind, nid in mapping.items():
            if kind == "jump":
                all_nodes[idx]["next"] = nid
            else:
                choice_i = int(kind.split(":")[1])
                all_nodes[idx]["choices"][choice_i]["next"] = nid

    # --- 校验 ---
    known_flags = set(config["initial_flags"].keys())
    set_flags = {}
    for n in all_nodes:
        for src in ([n.get("set", {})] + [c.get("set", {}) for c in n.get("choices", [])]):
            for k, v in src.items():
                set_flags.setdefault(k, v)
        for cond in [n.get("when")] + [v.get("when") for v in n.get("variants", [])]:
            if cond:
                collect_flag_uses(cond)
    used_flags = flag_uses
    for k in used_flags - known_flags:
        if k in set_flags:
            guess = set_flags[k]
            config["initial_flags"][k] = False if not isinstance(guess, (int, float)) or isinstance(guess, bool) else 0
            warn("flag %r 未在 initial_flags 声明（已按 %r 自动补默认值）" % (k, config["initial_flags"][k]))
        else:
            err("flag %r 被条件引用，但从未初始化或赋值" % k)

    lookup = {n["id"]: i for i, n in enumerate(all_nodes)}
    for n in all_nodes:
        where = n.get("id", "?")
        # 角色与表情
        for actor in n.get("cast", []):
            if actor["id"] not in cast_names:
                err("%s: 未知角色 id %r" % (where, actor["id"]))
            if actor["expression"] not in EXPRESSIONS:
                err("%s: 未知表情 %r（角色 %s）" % (where, actor["expression"], actor["id"]))
        sp = n.get("speaker", "")
        if sp and sp != "我" and sp not in cast_names:
            err("%s: 未知说话人 %r" % (where, sp))
        for role, expr in n.get("reactions", {}).items():
            if role not in cast_names:
                err("%s: reaction 未知角色 %r" % (where, role))
            if expr not in EXPRESSIONS:
                err("%s: reaction 未知表情 %r" % (where, expr))
        if n.get("expression") and n["expression"] not in EXPRESSIONS:
            err("%s: 未知表情 %r" % (where, n["expression"]))
        # 背景与 CG
        bg = n.get("bg")
        if bg and bg != "black" and not os.path.exists(os.path.join(GAME_DIR, "assets", "backgrounds", bg + ".png")):
            warn("%s: 背景文件不存在 assets/backgrounds/%s.png（运行时将用占位图）" % (where, bg))
        cg = n.get("cg")
        if cg and not os.path.exists(os.path.join(GAME_DIR, "assets", "cg", cg + ".png")):
            warn("%s: CG 文件不存在 assets/cg/%s.png（运行时将用占位图）" % (where, cg))
        # 音乐
        cue = n.get("music")
        if cue:
            if cue not in music_ids:
                err("%s: 未登记的 BGM cue %r" % (where, cue))
            outro = n.get("music_outro")
            if outro:
                if outro not in music_ids:
                    err("%s: 未登记的 BGM cue %r" % (where, outro))
            elif cue.endswith("_intro"):
                pair = music_catalog.get("pairs", {}).get(cue)
                if pair:
                    n["music_outro"] = pair
        # 选项与跳转完整性
        for c in n.get("choices", []):
            if "next" not in c:
                err("%s: 选项 %r 缺少可用目标" % (where, c.get("label", "")))
        if n.get("type") == "jump" and "next" not in n:
            err("%s: jump 缺少目标" % where)

    # 不可达节点
    reachable, stack = set(), [0] if all_nodes else []
    while stack:
        i = stack.pop()
        if i in reachable or i >= len(all_nodes):
            continue
        reachable.add(i)
        n = all_nodes[i]
        if "next" in n:
            stack.append(lookup.get(n["next"], -1))
        for c in n.get("choices", []):
            stack.append(lookup.get(c.get("next", ""), -1))
        if n.get("type") != "jump":
            stack.append(i + 1)
    for i, n in enumerate(all_nodes):
        if i not in reachable:
            warn("节点不可达（从首节点无法到达）: %s" % n.get("id"))

    # --- 美术需求清单（模拟运行时渲染状态）---
    art_index = {}
    state_bg, state_cast, state_cg = "black", [], ""
    state_title, state_chapter = "", ""
    for n in all_nodes:
        if n.get("type") == "stage":
            state_bg = n.get("bg", state_bg)
            state_cg = n.get("cg", state_cg)
            state_title = n.get("title", state_title)
            state_chapter = n.get("date", state_chapter)
            mode = n.get("_cast_mode", "replace")
            if "cast" in n:
                if mode == "replace":
                    state_cast = [dict(a) for a in n["cast"]]
                elif mode == "add":
                    state_cast = [a for a in state_cast if a["id"] not in {x["id"] for x in n["cast"]}] + [dict(a) for a in n["cast"]]
                else:
                    state_cast = [a for a in state_cast if a["id"] not in {x["id"] for x in n["cast"]}]
            continue
        if n.get("type") != "line":
            continue
        arts = []
        if state_bg != "black":
            arts.append("background/" + state_bg)
        if state_cg:
            arts.append("cg/" + state_cg)
        else:
            speaker = n.get("speaker", "")
            # 与运行时一致：说话人不在舞台则自动登场
            if speaker and speaker != "我" and speaker in cast_names and all(a["id"] != speaker for a in state_cast):
                state_cast.append({"id": speaker, "expression": "normal"})
            for a in state_cast:
                expr = a.get("expression", "normal")
                if speaker and (a["id"] == speaker or cast_names.get(a["id"]) == speaker):
                    expr = n.get("expression", expr)
                if a["id"] in n.get("reactions", {}):
                    expr = n["reactions"][a["id"]]
                arts.append("sprite/%s/%s" % (a["id"], expr))
        art_index[n["id"]] = {"arts": arts, "title": state_title, "chapter": state_chapter}

    # --- 报告（有错误则不写产物）---
    n_pages = sum(1 for n in all_nodes if n.get("type", "line") == "line")
    n_choices = sum(len(n.get("choices", [])) for n in all_nodes)
    print("场景文件 %d | 节点 %d | 对话页 %d | 选项 %d | flag %d"
          % (len(file_metas), len(all_nodes), n_pages, n_choices, len(config["initial_flags"])))
    for w in warnings:
        print("警告: " + w)
    for e in errors:
        print("错误: " + e)
    if errors:
        print("编译失败（%d 个错误），未写出任何产物" % len(errors))
        sys.exit(1)

    # 清理内部字段后再输出
    for n in all_nodes:
        for key in [k for k in n if k.startswith("_")]:
            del n[key]

    # --- 输出 ---
    os.makedirs(OUT_DIR, exist_ok=True)
    story = {
        "version": "el-vn-1",
        "title": config["title"],
        "release_version": "0.2.0",
        "cast_names": cast_names,
        "initial_flags": {k: config["initial_flags"][k] for k in sorted(config["initial_flags"])},
        "nodes": all_nodes,
    }
    with open(os.path.join(OUT_DIR, "story.json"), "w", encoding="utf-8") as f:
        json.dump(story, f, ensure_ascii=False, indent=1)
    with open(os.path.join(OUT_DIR, "art_index.json"), "w", encoding="utf-8") as f:
        json.dump(art_index, f, ensure_ascii=False, indent=1)

    # flowchart：每个源稿文件 = 一个块
    owner = {}
    for meta in file_metas:
        for n in meta["nodes"]:
            owner[n["id"]] = meta["base"]
    blocks = []
    for i, meta in enumerate(file_metas):
        fid = meta["base"]
        node_ids = [n["id"] for n in meta["nodes"]]
        edges, seen = [], set()
        for n in meta["nodes"]:
            targets = []
            if "next" in n:
                targets.append(("", n["next"]))
            for c in n.get("choices", []):
                targets.append((c["label"][:12], c.get("next", "")))
            for label, t in targets:
                to_block = owner.get(t)
                if to_block and to_block != fid and (to_block, label) not in seen:
                    seen.add((to_block, label))
                    edges.append({"to": to_block, "label": label})
        if i + 1 < len(file_metas):
            nxt = os.path.splitext(file_metas[i + 1]["file"])[0]
            if not any(e["to"] == nxt for e in edges):
                edges.append({"to": nxt, "label": ""})
        blocks.append({
            "id": fid, "title": node_title(meta), "date": "", "pages": len(node_ids),
            "kind": "scene", "entry": node_ids[0] if node_ids else "",
            "node_ids": node_ids, "edges": edges,
            "when": {}, "x": 40 + i * 300, "y": 40,
        })
    flow = {"blocks": blocks, "owner": owner, "width": 40 + max(1, len(blocks)) * 300,
            "height": 200, "start": blocks[0]["id"] if blocks else ""}
    with open(os.path.join(OUT_DIR, "flowchart.json"), "w", encoding="utf-8") as f:
        json.dump(flow, f, ensure_ascii=False, indent=1)

    art_needs = sorted({k for entry in art_index.values() for k in entry["arts"]})
    print("美术需求 %d 项（其中立绘 %d / 背景 %d / CG %d）" % (
        len(art_needs),
        sum(1 for a in art_needs if a.startswith("sprite/")),
        sum(1 for a in art_needs if a.startswith("background/")),
        sum(1 for a in art_needs if a.startswith("cg/"))))
    print("编译完成 -> data/story.json, data/flowchart.json, data/art_index.json")


flag_uses = set()


def collect_flag_uses(cond):
    if isinstance(cond, list):
        for c in cond:
            collect_flag_uses(c)
        return
    for k in cond or {}:
        flag_uses.add(k)


def node_title(meta):
    for n in meta["nodes"]:
        if n.get("type") == "stage" and n.get("title"):
            return n["title"]
    return os.path.splitext(meta["file"])[0]


if __name__ == "__main__":
    main()
