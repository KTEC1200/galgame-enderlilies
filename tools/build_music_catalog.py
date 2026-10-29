# -*- coding: utf-8 -*-
"""扫描仓库根目录 music/ 下的 BGM，生成 game/data/music_catalog.json，
并把音频按 cue id 复制到 game/assets/audio/。

文件名约定（与 ENDER LILIES OST 原始文件一致）：
    NNN_BGM_<区域>[_Boss]_<NN>_<曲名>[_Save|_Intro|_intro|_Outro][_Master][ ].ogg

生成的 cue 命名：
    title / opening / awakening / abyss          —— 特殊曲目
    <area>            日常曲（循环）        如 church
    <area>_quiet      Save 氛围变体（循环）  如 church_quiet
    boss_<area>_intro / boss_<area>_outro        Boss 曲两段

用法：在 game/ 目录下执行  python tools/build_music_catalog.py
"""
import json
import os
import re
import shutil
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME_DIR = os.path.dirname(HERE)
VAULT_ROOT = os.path.dirname(GAME_DIR)
MUSIC_DIR = os.path.join(VAULT_ROOT, "music")
OUT_AUDIO = os.path.join(GAME_DIR, "assets", "audio")
OUT_JSON = os.path.join(GAME_DIR, "data", "music_catalog.json")

# 区域前缀（解析文件名用）→ cue id 与中文地名
AREAS = {
    "Title":     ("title", "标题画面"),
    "Opening":   ("opening", "序章"),
    "Church":    ("church", "白教区"),
    "Village":   ("village", "悬崖村"),
    "Forest":    ("forest", "魔女森林"),
    "Cave":      ("cave", "地下墓穴"),
    "Swamp":     ("swamp", "禁区"),
    "Oubliette": ("oubliette", "地牢"),
    "Castle":    ("castle", "边陲之都城"),
    "Fort":      ("fort", "双生堡垒"),
    "LastBoss":  ("boss_final", "深渊最深处"),
    "Abyss":     ("abyss", "深渊"),
}

SUFFIX_RE = re.compile(r"_(Intro|intro|Outro|Save|Master)\b")


def parse_duration_ogg(path):
    """无第三方库读取 Ogg Vorbis 时长：末页 granule position / 采样率。"""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            head = f.read(65536)
            rate = None
            idx = head.find(b"\x01vorbis")
            if idx >= 0 and idx + 16 <= len(head):
                rate = struct.unpack_from("<I", head, idx + 11 + 1)[0]  # +12 from '\x01vorbis'
            f.seek(max(0, size - 65536))
            tail = f.read()
        gpos = None
        pos = tail.rfind(b"OggS")
        while pos >= 0:
            gpos = struct.unpack_from("<q", tail, pos + 6)[0]
            break
        if rate and gpos and gpos > 0:
            return round(gpos / rate, 1)
    except Exception as exc:  # noqa: BLE001
        print("  ! 时长解析失败 %s: %s" % (path, exc))
    return None


def parse_filename(filename):
    """返回 (cue_id, base_key, suffix, display_title) 或 None。"""
    stem = os.path.splitext(filename)[0].rstrip()
    m = re.match(r"^(\d+)_BGM_(.+)$", stem)
    if not m:
        return None
    rest = m.group(2)
    suffix = None
    # 从尾部剥离修饰后缀（_Master 可重复出现且与大小写混排）
    while True:
        m2 = re.search(r"_(Master|master)$", rest)
        if m2:
            rest = rest[: m2.start()]
            continue
        m2 = re.search(r"_(Intro|intro|Outro|Save)$", rest)
        if m2:
            tag = m2.group(1)
            suffix = {"Intro": "intro", "intro": "intro", "Outro": "outro", "Save": "quiet"}[tag]
            rest = rest[: m2.start()]
            continue
        break
    # 区域前缀：优先匹配长名（LastBoss 先于普通词）
    base_key = None
    area_id = None
    area_cn = None
    for key in sorted(AREAS, key=len, reverse=True):
        if rest.startswith(key + "_") or rest == key:
            base_key = key
            area_id, area_cn = AREAS[key]
            rest = rest[len(key):].lstrip("_")
            break
    if base_key is None:
        return None
    # 剩余形如 "01_曲名" 或 "Boss_01_曲名"；Boss 文件的 cue 以 boss_ 开头
    is_boss = rest.startswith("Boss_") or area_id.startswith("boss_")
    rest = re.sub(r"^Boss_", "", rest)
    m_num = re.match(r"^(\d+)_(.+)$", rest)
    if not m_num:
        return None
    track_no, title = m_num.group(1), m_num.group(2).strip()
    if area_id.startswith("boss_"):
        base = area_id  # LastBoss -> boss_final
    elif is_boss:
        base = "boss_" + area_id
    elif track_no == "01":
        base = area_id  # 区域主曲
    else:
        base = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")  # 同区域第 2+ 首，按曲名
    cue = base if not suffix else base + "_" + suffix
    return cue, base_key, suffix, title, area_cn


def main():
    if not os.path.isdir(MUSIC_DIR):
        print("找不到音乐目录: " + MUSIC_DIR)
        sys.exit(1)
    os.makedirs(OUT_AUDIO, exist_ok=True)
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)

    tracks = []
    pairs = {}
    chosen = {}  # cue_id -> (src_path, prefer_master, title, area_cn)
    for filename in sorted(os.listdir(MUSIC_DIR)):
        if not filename.lower().endswith(".ogg"):
            continue
        parsed = parse_filename(filename)
        if parsed is None:
            print("  ? 无法解析（跳过）: " + filename)
            continue
        cue, base_key, suffix, title, area_cn = parsed
        src = os.path.join(MUSIC_DIR, filename)
        is_master = filename.lower().count("_master") > 0
        if cue in chosen:
            keep_master = chosen[cue][1]
            if keep_master and not is_master:
                continue  # 已有 Master 版
        chosen[cue] = (src, is_master, title, area_cn)

    for cue, (src, _m, title, area_cn) in sorted(chosen.items()):
        dst = os.path.join(OUT_AUDIO, cue + ".ogg")
        shutil.copy2(src, dst)
        entry = {
            "id": cue,
            "title": title,
            "area": area_cn,
            "path": "res://assets/audio/%s.ogg" % cue,
            "seconds": parse_duration_ogg(dst),
        }
        if cue.endswith("_intro"):
            outro = cue[: -len("_intro")] + "_outro"
            if outro in chosen:
                entry["pair"] = outro
                pairs[cue] = outro
        tracks.append(entry)
        print("  + %-22s <- %s" % (cue, os.path.basename(src)))

    catalog = {
        "version": "auto-from-music-dir",
        "crossfade_seconds": 1.2,
        "pairs": pairs,
        "tracks": tracks,
    }
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=1)
    print("共 %d 首 -> %s" % (len(tracks), OUT_JSON))


if __name__ == "__main__":
    main()
