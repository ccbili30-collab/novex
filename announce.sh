#!/usr/bin/env bash
#
# 一键写公告：生成日期 md 模板 + announcements.json 索引行 + README 公告行
# 用法: ./announce.sh "标题" [stable|preview]   （通道缺省=通用，双版本互通）
set -euo pipefail
TITLE="$1"; CHANNEL="${2:-}"
DATE=$(date +%F)
SLUG=$(echo "$TITLE" | tr ' /' '--' | tr -d '[:punct:]' | head -c 40)
FILE="announcements/${DATE}-${TITLE}.md"

if [[ -f "$FILE" ]]; then echo "❌ 已存在: $FILE" >&2; exit 1; fi

cat > "$FILE" <<MD
# ${TITLE}

**日期**：${DATE}

（正文写这里）
MD

python3 - "$FILE" "$TITLE" "$DATE" "$CHANNEL" <<'PY'
import json, sys
file, title, date, channel = sys.argv[1:5]
with open("announcements.json") as f: data = json.load(f)
entry = {"file": file, "title": title, "date": date}
if channel in ("stable", "preview"): entry["channel"] = channel
data["announcements"].insert(0, entry)
with open("announcements.json", "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2); f.write("\n")
PY

# README 公告列表顶部加行
python3 - "$FILE" "$TITLE" "$DATE" <<'PY'
import sys, pathlib
file, title, date = sys.argv[1:4]
p = pathlib.Path("README.md"); lines = p.read_text().splitlines(keepends=True)
line = f"- [{date} · {title}](./{file})\n"
for i, l in enumerate(lines):
    if l.startswith("- [") and "·" in l:
        lines.insert(i, line); break
else:
    raise SystemExit("README 公告列表未找到，请手动加一行")
p.write_text("".join(lines))
PY

git add "$FILE" announcements.json README.md
echo "✅ 已生成并暂存：$FILE（索引+README 已加行）。写完正文后 commit + push 即应用内生效。"
