# -*- coding: utf-8 -*-
"""生成占位美术（纯 Python，无第三方依赖）：
    assets/key_visual.png            标题图
    assets/backgrounds/*.png         1280x720 渐变
    assets/sprites/<角色>/<表情>.png  640x980 剪影（头+身），带透明
    assets/cg/cg_awaken.png          1280x720

颜色按文件名哈希取自一套低饱和冷色调色板，保持整体氛围统一。
正式美术就位后直接覆盖同名文件即可，无需改代码。

用法：在 game/ 目录下执行  python tools/make_placeholders.py
"""
import hashlib
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
GAME_DIR = os.path.dirname(HERE)
ASSETS = os.path.join(GAME_DIR, "assets")

# 低饱和冷色调（蓝灰/紫灰/青灰），贴合 ENDER LILIES 阴雨氛围
PALETTE = [
    (74, 90, 112), (64, 78, 100), (86, 80, 104), (58, 84, 96),
    (92, 98, 116), (70, 70, 94), (62, 92, 88), (100, 92, 110),
]

EXPRESSIONS = ["normal", "happy", "shy", "angry", "surprised", "worried", "serious", "soft"]


def color_for(name):
    digest = hashlib.md5(name.encode("utf-8")).digest()
    base = PALETTE[digest[0] % len(PALETTE)]
    shift = (digest[1] % 24) - 12
    return tuple(max(0, min(255, c + shift)) for c in base)


def write_png(path, width, height, pixel_fn):
    """pixel_fn(x, y) -> (r, g, b, a)"""
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: None
        for x in range(width):
            raw.extend(pixel_fn(x, y))
    def chunk(tag, data):
        block = tag + data
        return struct.pack(">I", len(data)) + block + struct.pack(">I", zlib.crc32(block) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    print("  + %-46s %dx%d" % (os.path.relpath(path, GAME_DIR), width, height))


def gradient_bg(name, width=1280, height=720):
    top, bottom = color_for(name), color_for(name + "#bottom")
    ground = tuple(int(c * 0.55) for c in bottom)
    def px(x, y):
        t = y / height
        if y > height * 0.72:  # 下四分之一压暗当地面
            k = (y - height * 0.72) / (height * 0.28)
            r = int(top[0] * (1 - t) + bottom[0] * t)
            g = int(top[1] * (1 - t) + bottom[1] * t)
            b = int(top[2] * (1 - t) + bottom[2] * t)
            return (int(r * (1 - k) + ground[0] * k), int(g * (1 - k) + ground[1] * k), int(b * (1 - k) + ground[2] * k), 255)
        r = int(top[0] * (1 - t) + bottom[0] * t)
        g = int(top[1] * (1 - t) + bottom[1] * t)
        b = int(top[2] * (1 - t) + bottom[2] * t)
        return (r, g, b, 255)
    return px


def key_visual(width=1280, height=720):
    top, bottom = (30, 38, 54), (16, 20, 30)
    def px(x, y):
        t = y / height
        r = int(top[0] * (1 - t) + bottom[0] * t)
        g = int(top[1] * (1 - t) + bottom[1] * t)
        b = int(top[2] * (1 - t) + bottom[2] * t)
        # 中央微光，模拟雨夜教堂彩窗
        dx, dy = x - width * 0.5, y - height * 0.42
        d = (dx * dx + dy * dy) / (width * width * 0.25)
        glow = max(0.0, 1.0 - d)
        return (min(255, int(r + glow * 36)), min(255, int(g + glow * 44)), min(255, int(b + glow * 60)), 255)
    return px


def sprite(name, width=640, height=980):
    body = color_for(name)
    light = tuple(min(255, int(c * 1.35)) for c in body)
    dark = tuple(int(c * 0.5) for c in body)
    cx, head_r = width / 2, width * 0.19
    head_cy = height * 0.16
    body_top = head_cy + head_r * 1.15
    body_w = width * 0.42
    def px(x, y):
        # 头
        if (x - cx) ** 2 + (y - head_cy) ** 2 <= head_r ** 2:
            return (*light, 255)
        # 肩身（上宽下略收）
        if body_top <= y <= height:
            shrink = (y - body_top) / (height - body_top) * body_w * 0.18
            half = body_w / 2 - shrink
            if abs(x - cx) <= half:
                if (x - cx) ** 2 + (y - head_cy) ** 2 <= (head_r * 1.4) ** 2 and y < body_top + head_r * 0.3:
                    return (*dark, 255)  # 肩部阴影
                return (*body, 255)
        return (0, 0, 0, 0)
    return px


def main():
    print("生成 key_visual")
    write_png(os.path.join(ASSETS, "key_visual.png"), 1280, 720, key_visual())

    backgrounds = [
        "church_nave", "church_alcove", "church_bell",
        "village_hut", "village_cliff",
        "forest_path", "forest_lake",
        "catacomb_hall",
        "dungeon_cell",
        "fort_wall", "fort_snowfield",
        "castle_hall",
        "forbidden_pool",
        "spring", "abyss",
    ]
    print("生成背景占位")
    for name in backgrounds:
        write_png(os.path.join(ASSETS, "backgrounds", name + ".png"), 1280, 720, gradient_bg(name))

    sprites = {
        "lily": EXPRESSIONS,
        "knight": EXPRESSIONS,
        "siegrid": EXPRESSIONS,
        "true_lily": EXPRESSIONS,
    }
    print("生成立绘占位（剪影）")
    for char_id, expressions in sprites.items():
        for expr in expressions:
            write_png(os.path.join(ASSETS, "sprites", char_id, expr + ".png"), 640, 980, sprite("%s/%s" % (char_id, expr)))

    print("生成 CG 占位")
    write_png(os.path.join(ASSETS, "cg", "cg_awaken.png"), 1280, 720, key_visual())
    print("完成。")


if __name__ == "__main__":
    main()
