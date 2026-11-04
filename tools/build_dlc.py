#!/usr/bin/env python3
"""DLC「设定档案」数据编译：vault(concepts / entities / events) → data/dlc.json

- 只读 vault（Obsidian 剧情知识库，禁止修改）；运行时游戏只读 res://data/dlc.json，
  绝不触碰构建机路径。
- 实体关系：来自每个实体 md 的「关联人物」小节（- [[目标]] — 关系说明）与
  frontmatter related；目标限定为实体名，边自动去重。
- 势力（隶属）：由 tags 推导（守护者/白教/白巫女/不死骑士团/王之盾/暗部/魔术协会/
  国家魔术师团/古老民族/王族…），另有 13 个引擎角色从 data/character_map.json 对齐。
- 事件时间线：以 events/事件时间线.md 的七纪分节为准排序；时间线未收录的事件排尾
  并标「时间待确认」。事件文件本身没有纪年字段（created/updated 是笔记元数据，
  绝不当作故事时间）。
- 图谱坐标：确定性力导向布局（固定种子），0~1 归一化。
用法: python tools/build_dlc.py [vault路径]
  默认 C:/Users/27025/Desktop/iii/enderlilies
"""
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_VAULT = "C:/Users/27025/Desktop/iii/enderlilies"
OUT = os.path.join(ROOT, "data", "dlc.json")

FACTION_TAGS = [
    ("白巫女", "白巫女"),
    ("守护者", "白教·守护者"),
    ("白教", "白教"),
    ("不死骑士团", "不死骑士团"),
    ("王之盾", "王之盾"),
    ("暗部", "暗部"),
    ("魔术协会", "魔术协会"),
    ("国家魔术师团", "国家魔术师团"),
    ("古老民族", "古老民族"),
    ("王族", "边陲之国王室"),
    ("王室", "边陲之国王室"),
    ("国王", "边陲之国王室"),
    ("民众", "边陲之国民众"),
    ("污秽", "污秽"),
]
UNCERTAIN_WORDS = ("存疑", "不可考", "推测", "模糊", "约五十年", "约数十")

WIKI = re.compile(r"\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]+))?\]\]")


def parse_frontmatter(text: str):
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end < 0:
        return {}, text
    head, body = text[3:end], text[end + 4:]
    meta = {}
    for line in head.split("\n"):
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        k, v = k.strip(), v.strip()
        if v.startswith("[") and v.endswith("]"):
            items = [x.strip() for x in v[1:-1].split(",") if x.strip()]
            meta[k] = items
        else:
            meta[k] = v
    return meta, body


def parse_blocks(body: str):
    """md 正文 → 区块列表：h2 / p / quote / li / table"""
    blocks = []
    para, quote, table = [], [], []

    def flush_para():
        if para:
            blocks.append({"t": "p", "text": "\n".join(para).strip()})
            para.clear()

    def flush_quote():
        if quote:
            blocks.append({"t": "quote", "lines": quote})
            quote.clear()

    def flush_table():
        if table:
            rows = []
            for r in table:
                cells = [c.strip() for c in r.strip().strip("|").split("|")]
                if cells and not set("".join(cells)) <= set("-: "):
                    rows.append(cells)
            if rows:
                blocks.append({"t": "table", "rows": rows})
            table.clear()

    for line in body.split("\n"):
        s = line.strip()
        if s.startswith("# "):
            continue  # 一级标题与 frontmatter title 重复，不进正文
        if s.startswith("|"):
            flush_para(); flush_quote()
            table.append(s)
        elif s.startswith("## "):
            flush_para(); flush_quote(); flush_table()
            blocks.append({"t": "h2", "text": s[3:].strip()})
        elif s.startswith(">"):
            flush_para(); flush_table()
            quote.append(s[1:].strip())
        elif s.startswith("- "):
            flush_para(); flush_quote(); flush_table()
            blocks.append({"t": "li", "text": s[2:].strip()})
        elif s == "":
            flush_para(); flush_quote(); flush_table()
        else:
            flush_quote(); flush_table()
            para.append(s)
    flush_para(); flush_quote(); flush_table()
    return blocks


def plain(md_text: str) -> str:
    """wikilink → 显示文本"""
    return WIKI.sub(lambda m: (m.group(2) or m.group(1)).strip(), md_text)


def clean_blocks(blocks):
    """区块文本里的 wikilink 全部转显示文本（JSON 交付物不带 [[语法]]）"""
    out = []
    for b in blocks:
        if b["t"] in ("p", "li", "h2"):
            out.append({"t": b["t"], "text": plain(b["text"])})
        elif b["t"] == "quote":
            out.append({"t": "quote", "lines": [plain(x) for x in b["lines"]]})
        elif b["t"] == "table":
            out.append({"t": "table", "rows": [[plain(c) for c in row] for row in b["rows"]]})
        else:
            out.append(b)
    return out


def wiki_targets(md_text: str):
    return [m.group(1).strip() for m in WIKI.finditer(md_text)]


def derive_faction(tags) -> str:
    for tag, faction in FACTION_TAGS:
        if tag in tags:
            return faction
    return "未明"


def load_entities(vault: str):
    ents = []
    d = os.path.join(vault, "entities")
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".md"):
            continue
        meta, body = parse_frontmatter(open(os.path.join(d, fn), encoding="utf-8").read().replace("\r\n", "\n"))
        title = str(meta.get("title") or fn[:-3]).strip()
        raw_blocks = parse_blocks(body)
        blocks = clean_blocks(raw_blocks)
        relations = []
        in_rel = False
        for b in raw_blocks:  # 关系解析用原始块（wikilink 语法还在）
            if b["t"] == "h2":
                in_rel = b["text"].startswith("关联人物")
                continue
            if in_rel and b["t"] == "li":
                m = re.match(r"\s*\[\[([^\]|]+)(?:\|([^\]]+))?\]\]\s*[—–-]+\s*(.+)", b["text"])
                if m:
                    relations.append({"target": m.group(1).strip(), "label": plain(m.group(3)).strip()})
        summary = ""
        for b in blocks:
            if b["t"] == "quote" and b["lines"]:
                summary = plain(b["lines"][0])
                break
            if b["t"] == "p":
                summary = plain(b["text"]).split("\n")[0]
                break
        ents.append({
            "id": "ent-" + re.sub(r"\s+", "", title),
            "title": title,
            "tags": meta.get("tags", []) if isinstance(meta.get("tags"), list) else [],
            "faction": derive_faction(meta.get("tags", []) if isinstance(meta.get("tags"), list) else []),
            "summary": summary,
            "relations": relations,
            "related_meta": meta.get("related", []) if isinstance(meta.get("related"), list) else [],
            "blocks": clean_blocks(blocks),
        })
    return ents


def load_concepts(vault: str):
    cs = []
    d = os.path.join(vault, "concepts")
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".md"):
            continue
        meta, body = parse_frontmatter(open(os.path.join(d, fn), encoding="utf-8").read().replace("\r\n", "\n"))
        title = str(meta.get("title") or fn[:-3]).strip()
        summary = ""
        for b in parse_blocks(body):
            if b["t"] == "p":
                summary = plain(b["text"]).split("\n")[0]
                break
        cs.append({
            "id": "con-" + re.sub(r"\s+", "", title),
            "title": title,
            "tags": meta.get("tags", []) if isinstance(meta.get("tags"), list) else [],
            "summary": summary,
            "blocks": clean_blocks(parse_blocks(body)),
        })
    return cs


def load_events(vault: str):
    """返回 (events, timeline)；事件排序以时间线为准"""
    events = {}
    d = os.path.join(vault, "events")
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".md") or fn == "事件时间线.md":
            continue
        meta, body = parse_frontmatter(open(os.path.join(d, fn), encoding="utf-8").read().replace("\r\n", "\n"))
        title = str(meta.get("title") or fn[:-3]).strip()
        summary = ""
        for b in parse_blocks(body):
            if b["t"] == "quote" and b["lines"]:
                summary = plain(b["lines"][0]); break
            if b["t"] == "p":
                summary = plain(b["text"]).split("\n")[0]; break
        events[title] = {
            "id": "evt-" + re.sub(r"\s+", "", title),
            "title": title,
            "tags": meta.get("tags", []) if isinstance(meta.get("tags"), list) else [],
            "summary": summary,
            "blocks": clean_blocks(parse_blocks(body)),
        }

    timeline = []
    tl_path = os.path.join(d, "事件时间线.md")
    if os.path.exists(tl_path):
        _, body = parse_frontmatter(open(tl_path, encoding="utf-8").read().replace("\r\n", "\n"))
        era = None
        for b in parse_blocks(body):
            if b["t"] == "h2":
                if b["text"].startswith("相关"):
                    era = None
                    continue
                era = {"era": b["text"], "items": []}
                timeline.append(era)
                continue
            if era is None:
                continue
            if b["t"] == "li":
                text = plain(b["text"])
                targets = wiki_targets(b["text"])
                era["items"].append({
                    "text": text,
                    "links": targets,
                    "event": next((t for t in targets if t in events), None),
                    "uncertain": any(w in text for w in UNCERTAIN_WORDS),
                })
    # 时间线未收录的事件 → 排尾 + 时间待确认
    placed = {it["event"] for era in timeline for it in era["items"] if it["event"]}
    extra = [t for t in events if t not in placed]
    if extra:
        timeline.append({"era": "时间待确认", "items": [
            {"text": t, "links": [t], "event": t, "uncertain": True} for t in extra]})
    return events, timeline


def build_graph(entities):
    names = [e["title"] for e in entities]
    nset = set(names)
    by_name = {e["title"]: e for e in entities}
    edges, seen = [], set()
    for e in entities:
        rels = list(e["relations"])
        rels += [{"target": t, "label": "相关"} for t in e["related_meta"] if t in nset]
        for r in rels:
            t = r["target"]
            if t not in nset or t == e["title"]:
                continue
            key = tuple(sorted((e["title"], t)))
            if key in seen:
                continue
            seen.add(key)
            edges.append({"a": e["title"], "b": t, "label": r["label"][:40]})

    # ---- 弦图式布局（确定性、保证无重叠）：同势力节点连续占一段弧，
    #      内外双圈交替拉开标签间距；连线为弦，跨势力关系一目了然 ----
    factions = []
    for e in entities:
        if e["faction"] not in factions:
            factions.append(e["faction"])
    order = sorted(entities, key=lambda e: (factions.index(e["faction"]), e["title"]))
    n = len(order)
    pos = {}
    cx, cy, rx, ry = 0.5, 0.5, 0.38, 0.33
    for i, e in enumerate(order):
        ang = 2 * math.pi * i / n - math.pi / 2
        ring = 1.0 if i % 2 == 0 else 0.72
        pos[e["title"]] = [cx + rx * ring * math.cos(ang), cy + ry * ring * math.sin(ang)]
    nodes = [{"id": e["id"], "title": e["title"], "faction": e["faction"],
              "x": round(pos[e["title"]][0], 4), "y": round(pos[e["title"]][1], 4)} for e in entities]
    return {"nodes": nodes, "edges": edges, "factions": factions}


def link_engine_ids(entities):
    """引擎 13 角色与 vault 实体对齐（供详情页显示官方立绘）"""
    cmap_path = os.path.join(ROOT, "data", "character_map.json")
    if not os.path.exists(cmap_path):
        return
    cmap = json.load(open(cmap_path, encoding="utf-8")).get("characters", {})
    for cid, info in cmap.items():
        disp = info.get("display_name", "")
        core = disp.replace("黑色骑士", "").replace("守护者", "").replace("骑士长", "") \
                   .replace("老战士", "").replace("黑色魔女", "").replace("深渊的守卫", "") \
                   .replace("狂骑士", "").replace("单眼的", "").replace("异端者", "") \
                   .replace("泉之白巫女", "")
        best = None
        for e in entities:
            if core and (core in e["title"] or e["title"] in disp):
                if best is None or len(e["title"]) > len(best["title"]):
                    best = e
        if best is not None and not best.get("engine_id"):
            best["engine_id"] = cid


def main():
    vault = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_VAULT
    entities = load_entities(vault)
    concepts = load_concepts(vault)
    events, timeline = load_events(vault)
    link_engine_ids(entities)
    # 文本集互跳：若已生成 text_collection.json，为人物和记忆条目回挂 entity id
    tc_path = os.path.join(ROOT, "data", "text_collection.json")
    if os.path.exists(tc_path):
        tc = json.load(open(tc_path, encoding="utf-8"))

        def _norm(s):
            return re.sub(r"\s+", "", s)

        def _core(s):
            # 去空白 + 剥掉尾部括号注记（如「黑色骑士费林（开端）」→「黑色骑士费林」）
            return re.sub(r"[（(][^（）()]*[）)]$", "", _norm(s))

        ent_norm = {e["title"]: _norm(e["title"]) for e in entities}
        ent_names = sorted(ent_norm, key=lambda n: len(ent_norm[n]), reverse=True)
        for cat in tc.get("categories", []):
            if cat.get("id") != "characters":
                continue
            for entry in cat.get("entries", []):
                t_core = _core(entry["title"])
                match = next((n for n in ent_names
                              if ent_norm[n] in t_core or t_core in ent_norm[n]), None)
                if match:
                    entry["entity_id"] = "ent-" + ent_norm[match]
                    ent = next(e for e in entities if e["title"] == match)
                    ent.setdefault("text_entry_ids", []).append(entry["id"])
        json.dump(tc, open(tc_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    data = {
        "version": 1,
        "vault": os.path.basename(vault),
        "concepts": concepts,
        "entities": entities,
        "events": list(events.values()),
        "timeline": timeline,
        "graph": build_graph(entities),
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print(f"[dlc] concepts={len(concepts)} entities={len(entities)} events={len(events)} "
          f"timeline_eras={len(timeline)} edges={len(data['graph']['edges'])} → {OUT}")


if __name__ == "__main__":
    main()
