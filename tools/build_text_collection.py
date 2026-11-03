#!/usr/bin/env python3
"""文本集编译：《ENDER LILIES 文本集.md》→ data/text_collection.json

解析规则（作者 2026-11-04 指定）：
  - 只收录三个分类，顺序固定：人物和记忆 / 笔记内容 / 遗物。
  - 整个「### 对话剧情」章节不解析、不进数据（其中角色名不得混入任何列表）。
  - 「#### 」行 = 条目标题；条目内连续「> 」行 = 描述/引言（多行，含编者注）；
    其余非空行 = 正文/台词逐行保留；空行 = 段落分隔（lines 中保留 ""）。
  - 条目 id = 分类前缀 + 标题 slug；分类内重名追加序号。
用法: python tools/build_text_collection.py [md路径]
  默认读取 vault 权威源 ../sources/ENDER LILIES 文本集.md（只读）。
"""
import json
import os
import re
import sys

DEFAULT_MD = "C:/Users/27025/Desktop/iii/enderlilies/sources/ENDER LILIES 文本集.md"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "text_collection.json")

CATEGORIES = [
    ("characters", "人物和记忆"),
    ("notes", "笔记内容"),
    ("relics", "遗物"),
]
SKIPPED_SECTIONS = {"对话剧情"}  # 整章忽略


def slugify(title: str) -> str:
    return re.sub(r"[^\w\u4e00-\u9fff]+", "", title)


def parse(md_path: str) -> dict:
    with open(md_path, "r", encoding="utf-8") as f:
        raw = f.read().replace("\r\n", "\n")

    lines = raw.split("\n")
    # ---- 第一遍：切分类，跳过忽略章节 ----
    buckets: dict = {cid: [] for cid, _ in CATEGORIES}
    current_cat = None
    skipping = False
    for line in lines:
        if line.startswith("### "):
            name = line[4:].strip()
            skipping = name in SKIPPED_SECTIONS
            current_cat = None
            for cid, cname in CATEGORIES:
                if name == cname:
                    current_cat = cid
                    break
            continue
        if line.startswith("## "):  # 回到顶层标题
            current_cat = None
            skipping = False
            continue
        if skipping or current_cat is None:
            continue
        buckets[current_cat].append(line)

    # ---- 第二遍：每个分类内切条目并解析 ----
    categories = []
    total = 0
    for cid, cname in CATEGORIES:
        entries = []
        cur = None  # {"title", "description", "lines", "in_quote"}
        seen_titles = {}

        def flush():
            nonlocal cur
            if cur is not None:
                slug = slugify(cur["title"]) or "entry"
                n = seen_titles.get(slug, 0) + 1
                seen_titles[slug] = n
                entry_id = f"{cid}-{slug}" if n == 1 else f"{cid}-{slug}-{n}"
                entries.append({
                    "id": entry_id,
                    "title": cur["title"],
                    "description": cur["description"],
                    "lines": cur["lines"],
                })
                cur = None

        for line in buckets[cid]:
            if line.startswith("#### "):
                flush()
                cur = {"title": line[5:].strip(), "description": [], "lines": []}
                continue
            if cur is None:
                continue  # 分类头与条目之间的杂散行（如「> 不知名角色仅丰富内容…」）
            s = line.strip()
            if s.startswith(">"):
                # 引用行：去 > 前缀；仅「>」的行 = 引用内段落分隔
                inner = s[1:].strip()
                cur["description"].append(inner)
            elif s == "":
                # 空行：引用段落已在上一行以 "" 记录；正文段落分隔
                if cur["lines"] and cur["lines"][-1] != "":
                    cur["lines"].append("")
            else:
                # 引用块结束后接正文：引用若以空串结尾则去掉冗余
                while cur["description"] and cur["description"][-1] == "" and cur["lines"]:
                    cur["description"].pop()
                cur["lines"].append(s)
        flush()
        # 去掉描述首尾空段
        for e in entries:
            while e["description"] and e["description"][0] == "":
                e["description"].pop(0)
            while e["description"] and e["description"][-1] == "":
                e["description"].pop()
            while e["lines"] and e["lines"][-1] == "":
                e["lines"].pop()
        categories.append({"id": cid, "name": cname, "entries": entries})
        total += len(entries)

    return {"version": 1, "source": os.path.basename(md_path), "total": total, "categories": categories}


def main() -> None:
    md_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MD
    if not os.path.exists(md_path):
        print(f"[text-collection] 源文件不存在：{md_path}（等作者放入后再跑）")
        sys.exit(1)
    data = parse(md_path)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    for c in data["categories"]:
        print(f"[text-collection] {c['name']}: {len(c['entries'])} 条")
    print(f"[text-collection] 共 {data['total']} 条 → {OUT}")


if __name__ == "__main__":
    main()
