# -*- coding: utf-8 -*-
"""引用核对：校验 story-src 章节正文中的「」引文与 docs/章节资料包 引用池的一致性。

用法（在 game/ 目录）：
  python tools/check_quotes.py           # 核对全部已登记章节
  python tools/check_quotes.py 07 12     # 只核对指定章号前缀

规则：
  [缺引] 资料包「必引」池（C-1 小节与含"必引"字样小节中、出现"备选"标记之前的句子）
         没有逐字出现在正文 —— 错误，必须处理
  [池外] 正文里出现了引用池之外的「」句子（长度>=4）—— 提示，人工判断：
         连接文本的引号用法 or 凭空杜撰的"原文"（后者必须删除）
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
SRC = os.path.join(GAME, "story-src")
PACKS = os.path.join(GAME, "docs", "章节资料包")

QUOTE_RE = re.compile(r"「([^」]+)」")

# 章节前缀 -> 资料包文件（01 白教区早于资料包制度、13 正文未写，均不在核对范围）
CHAPTERS = {
    "06": "06_悬崖村.md",
    "07": "07_魔女森林.md",
    "08": "08_地下墓穴.md",
    "09": "09_地牢.md",
    "10": "10_禁区.md",
    "11": "11_双生堡垒.md",
    "12": "12_边陲之都城.md",
    "13": "13_终章.md",
}


def extract_pack_quotes(path):
    """返回 (必引集合, 可选集合)。只认行首引文（> 「 / 「），忽略注释文字中的「」。"""
    required, optional = set(), set()
    in_c = False
    subsection_optional = False
    inline_optional = False
    for line in open(path, encoding="utf-8").read().splitlines():
        stripped = line.strip()
        if stripped.startswith("## "):
            title = stripped[3:]
            if title.startswith("C."):
                in_c = True
                continue
            if in_c and (title.startswith("D.") or title.startswith("E.")):
                break
            continue
        if not in_c:
            continue
        if stripped.startswith("### "):
            head = stripped[4:]
            subsection_optional = ("可选" in head) or ("备选" in head)
            inline_optional = False
            continue
        if "备选" in stripped:
            inline_optional = True
        target = optional if (subsection_optional or inline_optional) else required
        body = stripped.lstrip("> ").strip()
        # 「说话人：『引文』」形式（13 终章资料包）→ 从第一个「 起取
        m_spk = re.match(r"^[^「]{1,10}：", body)
        if m_spk:
            body = body[m_spk.end():]
        if body.startswith("「"):
            for q in QUOTE_RE.findall(body):
                q = q.strip()
                if len(q) >= 2 and q not in ("（亡语）", "……"):
                    target.add(q)
    return required, optional


def extract_story_quotes(path):
    text = open(path, encoding="utf-8").read()
    text = re.sub(r"^---.*?---", "", text, flags=re.S)
    lines = [l for l in text.splitlines() if not l.strip().startswith("//")]
    return set(q.strip() for q in QUOTE_RE.findall("\n".join(lines)) if q.strip())


def main():
    only = set(sys.argv[1:])
    fail = False
    for prefix in sorted(CHAPTERS):
        if only and prefix not in only:
            continue
        story_path = os.path.join(SRC, CHAPTERS[prefix])
        if not os.path.exists(story_path):
            print("== %s == 源稿不存在" % prefix)
            fail = True
            continue
        required, optional = extract_pack_quotes(os.path.join(PACKS, CHAPTERS[prefix]))
        story = extract_story_quotes(story_path)
        missing = sorted(q for q in required if q not in story)
        extra = sorted(q for q in story if q not in required and q not in optional and len(q) >= 4)
        print("== %s %s ==" % (prefix, CHAPTERS[prefix]))
        for q in missing:
            print("  [缺引] " + q)
        for q in extra:
            print("  [池外] " + q)
        if missing:
            fail = True
    if fail:
        print("\n引用核对：存在缺引（错误）")
        sys.exit(1)
    print("\n引用核对：必引全部命中（[池外] 项请人工确认是否为杜撰原文）")


if __name__ == "__main__":
    main()
