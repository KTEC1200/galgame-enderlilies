#!/usr/bin/env python3
"""立绘规格规范化：把 assets/sprites/ 下所有立绘统一为
「画布高 1960、角色底对齐画布底、同一角色高恒定」的标准规格。

解决三类来源尺寸混乱：
  1. 骨骼渲染图（紧裁剪、尺寸各异、宽幅角色被引擎垂直居中→悬浮）
  2. AI 生图（1280×1960 画布但角色不满幅、位置偏移 → 表情切换时跳变）
  3. 旧占位图（640×980）

处理规则（幂等，可重复运行）：
  - 抠 alpha 包围盒 → 缩放到该角色目标画布内高 TARGET_H[角色]
  - 宽度超过 MAX_W 时等比再缩（宽身形 Boss 的妥协）
  - 垫入高 1960、宽=角色宽的透明画布，水平居中、垂直底对齐
  - 引擎侧按「纹理宽高比 × 980 显示高」布局，脚底恒在 y=860 逻辑线上

用法： python tools/normalize_sprites.py [--dry]
"""
import sys
import glob
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sprites")

# 每角色目标画布内高（px，画布总高 1960 → 显示高 = H/2 逻辑像素）
# 依据：渲染 normal 的原作相对体型 + 剧情观感（巨人/大帽魔女更大、幼女更小）。
TARGET_H = {
    "lily": 1440,
    "true_lily": 1260,
    "knight": 1540,
    "siegrid": 1480,
    "shilda": 1440,
    "elaine": 1700,
    "gerold": 1680,      # 宽幅战斗姿态被 MAX_W 钳制后的统一高（与差分一致）
    "helnir": 1420,
    "faden": 1040,      # 坐姿
    "wolf": 1380,
    "shield": 1760,
    "fretia": 1500,
    "julius": 1540,
}
DEFAULT_H = 1500
MAX_W = 2300            # 画布宽上限（显示 1150 逻辑像素，屏幕 1280）
ALPHA_THRESHOLD = 8     # alpha ≥ 此值视为实体像素


def bbox(im: Image.Image):
    alpha = im.getchannel("A")
    return alpha.getbbox()  # None if fully transparent


def process(path: str, dry: bool) -> str:
    im = Image.open(path).convert("RGBA")
    box = bbox(im)
    if box is None:
        return "SKIP 全透明"
    role = os.path.basename(os.path.dirname(path))
    target_h = TARGET_H.get(role, DEFAULT_H)
    w0, h0 = box[2] - box[0], box[3] - box[1]
    scale = target_h / h0
    w1 = round(w0 * scale)
    if w1 > MAX_W:  # 宽身形：整体再缩
        scale = MAX_W / w0
        w1, target_h = MAX_W, round(h0 * scale)
    w1 = max(w1, 8)
    canvas = Image.new("RGBA", (w1, 1960), (0, 0, 0, 0))
    body = im.crop(box).resize((w1, target_h), Image.LANCZOS)
    canvas.paste(body, (0, 1960 - target_h), body)
    old = f"{im.size[0]}x{im.size[1]}"
    if not dry:
        canvas.save(path, optimize=True)
    return f"{old} -> {w1}x1960 (角色高 {target_h})"


def main() -> None:
    dry = "--dry" in sys.argv
    files = sorted(glob.glob(os.path.join(ROOT, "*", "*.png")))
    print(f"normalize_sprites: {len(files)} 张{'（DRY 模式）' if dry else ''}")
    for path in files:
        rel = os.path.relpath(path, ROOT)
        print(f"  {rel:24s} {process(path, dry)}")
    print("done")


if __name__ == "__main__":
    main()
