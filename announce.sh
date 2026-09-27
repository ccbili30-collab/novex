#!/usr/bin/env bash
#
# 一键写公告：生成日期 md 模板 + announcements.json 索引行 + README 公告行
# 用法:
#   ./announce.sh "标题"                          # 通用公告（双版本互通）
#   ./announce.sh "标题" stable|preview           # 版本公告（只下发对应通道）
#   ./announce.sh "标题" stable|preview ["标语"]  # 发版公告：version/date 自动从
#     update.json 对应通道勾兑（不手填）；badge 按通道默认；封面按约定路径
#     announcements/assets/<版本>-cover.{webp,png,jpg} 自动挂；标语缺省
#     「让创作更简单」句式
set -euo pipefail
TITLE="${1:?用法: ./announce.sh \"标题\" [stable|preview] [\"标语\"]}"
CHANNEL="${2:-}"
TAGLINE="${3:-}"
DATE=$(date +%F)
SLUG=$(echo "$TITLE" | tr ' /' '--' | tr -d '[:punct:]' | head -c 40)
FILE="announcements/${DATE}-${TITLE}.md"

if [[ -f "$FILE" ]]; then echo "❌ 已存在: ${FILE}" >&2; exit 1; fi

# [T-announcement-hero] 发版公告勾兑：通道给了才走发版形态；version/date
# 以 update.json 为准（发布体系唯一事实源），公告索引与更新源永不错位。
HERO_VERSION=""; HERO_BADGE=""; HERO_COVER=""
if [[ -n "$CHANNEL" ]]; then
  HERO_VERSION=$(python3 -c 'import json,sys; print(json.load(open("update.json")).get(sys.argv[1],{}).get("version",""))' "$CHANNEL" 2>/dev/null || true)
  HERO_DATE=$(python3 -c 'import json,sys; print(json.load(open("update.json")).get(sys.argv[1],{}).get("date",""))' "$CHANNEL" 2>/dev/null || true)
  if [[ -n "$HERO_DATE" ]]; then DATE="$HERO_DATE"; fi
  if [[ -z "$HERO_VERSION" ]]; then
    echo "⚠️ update.json 无 ${CHANNEL} 通道版本号，本条退化为无 version 普通公告" >&2
  fi
  if [[ "$CHANNEL" == "stable" ]]; then HERO_BADGE="正式版发布"; else HERO_BADGE="预览版发布"; fi
  for EXT in webp png jpg; do
    if [[ -f "announcements/assets/${HERO_VERSION}-cover.${EXT}" ]]; then
      HERO_COVER="announcements/assets/${HERO_VERSION}-cover.${EXT}"; break
    fi
  done
fi
if [[ -z "$TAGLINE" ]]; then TAGLINE="每一次更新，都让创作更简单。"; fi

# 元信息行：hero 渲染跳过开头元信息段（信息上横幅），通用公告照常显示
cat > "$FILE" <<MD
# ${TITLE}

**日期**：${DATE}
$( [[ -n "$CHANNEL" ]] && echo "**通道**：${CHANNEL}" || true )

（正文写这里）
MD

python3 - "$FILE" "$TITLE" "$DATE" "$CHANNEL" "$HERO_VERSION" "$HERO_BADGE" "$TAGLINE" "$HERO_COVER" <<'PY'
import json, sys
file, title, date, channel, version, badge, tagline, cover = sys.argv[1:9]
with open("announcements.json") as f: data = json.load(f)
entry = {"file": file, "title": title, "date": date}
if channel in ("stable", "preview"): entry["channel"] = channel
if version:
    entry["version"] = version
    entry["badge"] = badge
    entry["tagline"] = tagline
    if cover: entry["cover"] = cover
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
[[ -n "$HERO_COVER" ]] && git add "$HERO_COVER"
NOTE="无 hero（通用公告）"
if [[ -n "$HERO_VERSION" ]]; then
  # [净眼退回件] 命令替换在 cover 空时返回 1，set -e 会静默带走脚本——尾缀 || true
  NOTE="hero: ${HERO_VERSION} / ${HERO_BADGE}$( [[ -n "$HERO_COVER" ]] && echo " / 封面 ${HERO_COVER}" || true )"
fi
echo "✅ 已生成并暂存：${FILE}（索引+README 已加行，${NOTE}）。写完正文后 commit + push 即应用内生效。"
