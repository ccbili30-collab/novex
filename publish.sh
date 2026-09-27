#!/usr/bin/env bash
#
# Novex 一键发版脚本
#
# 用法:
#   ./publish.sh <apk路径> <版本号> <stable|preview> "更新说明"
# 例如:
#   ./publish.sh ../Novex-Development/artifacts/Novex-0.2.3-xxx.apk 0.2.3 stable "修复了会话设置闪退"
#
# 令牌来源(二选一):
#   1. 环境变量 GITEE_TOKEN
#   2. local/token 文件(已被 .gitignore 排除)
#
# 脚本会自动: 创建 Release → 上传 APK 附件 → 更新 update.json → 提交并推送

set -euo pipefail

APK="$1"; VERSION="$2"; CHANNEL="${3:-stable}"; NOTES="$4"
TAG="v${VERSION}"
API="https://gitee.com/api/v5"

# ---------- 令牌 ----------
TOKEN="${GITEE_TOKEN:-$(cat "$(dirname "$0")/local/token" 2>/dev/null || true)}"
if [[ -z "$TOKEN" ]]; then
  echo "❌ 未找到令牌: 请设置 GITEE_TOKEN 环境变量, 或写入 local/token" >&2
  exit 1
fi
if [[ ! -f "$APK" ]]; then echo "❌ APK 不存在: $APK" >&2; exit 1; fi
SIZE_MB=$(du -m "$APK" | cut -f1)
if (( SIZE_MB > 100 )); then
  echo "❌ 单附件超过 Gitee 100MB 上限(${SIZE_MB}MB), 请先压缩或分卷" >&2
  exit 1
fi

cd "$(dirname "$0")"

# ---------- 解析仓库(从 remote 地址提取 owner/repo) ----------
REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
REMOTE_URL="${REMOTE_URL#https://}"
REMOTE_URL="${REMOTE_URL#git@}"
OWNER_REPO="$(echo "$REMOTE_URL" | sed -E 's#^gitee.com[:/]##; s#\.git$##')"
if [[ -z "$OWNER_REPO" ]]; then
  echo "❌ 未配置 origin 远程仓库, 请先完成首次推送" >&2
  exit 1
fi
FILENAME="$(basename "$APK")"
DOWNLOAD_URL="https://gitee.com/${OWNER_REPO}/releases/download/${TAG}/${FILENAME}"

# ---------- 1. 创建 Release ----------
echo "📦 创建 Release ${TAG} (${CHANNEL}) ..."
BODY_JSON="$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "
${NOTES}

---
⬇️ 附件: ${FILENAME} (${SIZE_MB}MB)
📥 应用内更新源: [update.json](../blob/main/update.json)
")"
RELEASE_JSON="$(curl -sf -X POST "$API/repos/${OWNER_REPO}/releases" \
  -d "access_token=${TOKEN}" \
  -d "tag_name=${TAG}" \
  -d "name=Novex ${TAG}" \
  -d "target_commitish=main" \
  -d "prerelease=$([[ "$CHANNEL" == "preview" ]] && echo true || echo false)" \
  -d "body=${BODY_JSON}")"
RELEASE_ID="$(echo "$RELEASE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
echo "   Release ID: ${RELEASE_ID}"

# ---------- 2. 上传 APK 附件 ----------
echo "⬆️ 上传附件 ${FILENAME} (${SIZE_MB}MB) ..."
curl -sf -X POST "$API/repos/${OWNER_REPO}/releases/${RELEASE_ID}/attach_files" \
  -H "Content-Type: multipart/form-data" \
  -F "access_token=${TOKEN}" \
  -F "files=@${APK}" > /dev/null

# ---------- 3. 更新 update.json ----------
echo "📝 更新 update.json ..."
python3 - "$VERSION" "$CHANNEL" "$DOWNLOAD_URL" "$NOTES" <<'PY'
import json, sys, datetime
version, channel, url, notes = sys.argv[1:5]
with open("update.json") as f: data = json.load(f)
data[channel] = {
    "version": version,
    "channel": channel,
    "date": datetime.date.today().isoformat(),
    "notes": notes,
    "download": url,
}
with open("update.json", "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

# ---------- 4. 提交推送 ----------
echo "🚀 推送 ..."
git add update.json
git commit -m "release: ${TAG} (${CHANNEL})" -q
git push -q origin main

echo "✅ 完成: ${DOWNLOAD_URL}"
