#!/bin/bash
# 子序列门禁 v2：原文的引文片段与非注释行必须按原顺序完整出现在初稿中；
# 允许在它们之间任意插入新行、拆分引文页、重排分页。
# 用法: bash gate2.sh <原文件> <初稿>
ORIG="$1"; DRAFT="$2"
FAIL=0
# 1) 原文每个引文片段（「…」）必须逐字存在于初稿
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  if ! grep -qF -- "$seg" "$DRAFT"; then
    echo "GATE FAIL 缺失引文片段: $seg"
    FAIL=1
  fi
done < <(sed 's/[[:space:]]*$//' "$ORIG" | grep -vE '^\s*//|^---$' | grep -oE '「[^」]*」' | sort -u)
# 2) 原文非注释行（旁白/台词/结构行）必须按原顺序逐行出现（允许其间插入）
#    例外：含英文的行（作者要求可后置到章末/遗物后）只查存在性，不查顺序
python -I - "$ORIG" "$DRAFT" <<'EOF'
import sys, re
def norm(p):
    out=[]
    for ln in open(p,encoding='utf-8'):
        s=ln.rstrip()
        if not s or s.lstrip().startswith('//') or s=='---': continue
        if re.match(r'^(id|chapter|title|bg|music|cast):',s): continue
        out.append(s)
    return out
orig, draft = norm(sys.argv[1]), norm(sys.argv[2])
ordered = [l for l in orig if not re.search(r'[A-Za-z]{3,}', l)]
i, miss = 0, []
for need in ordered:
    while i < len(draft) and draft[i] != need:
        i += 1
    if i == len(draft):
        miss.append(need)
        break
    i += 1
if miss:
    print("GATE FAIL 原文行缺失/被改（前 10 条）：")
    for m in miss[:10]:
        print("  -", m)
    sys.exit(1)
print("GATE PASS — 原文内容按序完整（英文行除外，允许插入与拆页）")
EOF
[ $? -ne 0 ] && FAIL=1
# 3) 含英文的原行（引文/旁白）必须逐字存在（允许被后置）
while IFS= read -r ln; do
  [ -z "$ln" ] && continue
  if ! grep -qF -- "$ln" "$DRAFT"; then
    echo "GATE FAIL 英文行缺失: $ln"
    FAIL=1
  fi
done < <(sed 's/[[:space:]]*$//' "$ORIG" | grep -vE '^\s*//|^---$|^@' | grep -E '[A-Za-z]{3,}' | sort -u)
# 4) @ 指令行必须逐字存在（顺序可变但不许腐蚀——flash-lite 曾把 @bg 写成 @BgmPlayer.gd）
while IFS= read -r ln; do
  [ -z "$ln" ] && continue
  if ! grep -qF -- "$ln" "$DRAFT"; then
    echo "GATE FAIL @指令行缺失/被改: $ln"
    FAIL=1
  fi
done < <(sed 's/[[:space:]]*$//' "$ORIG" | grep -E '^@' | sort -u)
exit $FAIL
