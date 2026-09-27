# AGENTS.md — Novex 发布站操作手册（面向 AI 代理）

> 本文件写给执行发版/公告任务的 AI 代理（Codex / ZCode 等）。你不需要任何对话上下文，按本手册即可完成操作。
> 面向最终用户的内容见 `README.md`，请勿在 README 中混入操作细节。

## 这个仓库是什么

Novex（Android 客户端）的**官方国内分发站**，托管在 Gitee。三个用途：

1. 公告发布（`README.md` + `announcements/`）
2. 安装包下载（Gitee「发行版 / Releases」附件）
3. 应用内更新检查源（`update.json` raw 链接）

- 本地仓库：`/Users/noven/Documents/Codex/CodexProduct/1/novex-hub`（分支 `main`）
- 远程仓库：`https://gitee.com/ccbili/novex`（**必须保持 public**，用户匿名访问）
- 成品 APK 来源：`../Novex-Development/artifacts/`（不要从 build 目录拿中间产物）

## 版本约定

| 通道 | 版本格式 | Gitee Release 参数 | 来源 |
|---|---|---|---|
| 稳定版 stable | `v3.0.x` | `prerelease=false` | `main` 稳定线构建 |
| 预览版 preview | `v3.0.5-beta.n` | `prerelease=true` | `next` 预览线构建 |

> 版本线自 3.0 起与 GitHub（ccbili30-collab/novex-android）同号。发布流程
> 已改为**双推**：每轮 GitHub 发版后，用同一版本号把 APK 经 publish.sh 推
> 到本站，两边 update 信息保持一致（GitHub 侧为 Releases API，本站为
> update.json）。

## 认证（先读这里）

- Gitee 私人令牌存放在 **macOS 钥匙串**，读取方式：

  ```bash
  security find-generic-password -s gitee-token -w
  ```

- `git push` 已免密（credential helper `osxkeychain` 已存 gitee.com 凭据），直接 push 即可。
- 钥匙串不可用时（如换了机器）：请用户提供令牌写入 `local/token` 文件（已被 `.gitignore` 排除），或设置环境变量 `GITEE_TOKEN`。
- ⚠️ **令牌绝对不要写入任何被提交的文件、日志或命令回显。**

## 发版 —— 推荐方式：publish.sh

```bash
cd /Users/noven/Documents/Codex/CodexProduct/1/novex-hub
./publish.sh <apk路径> <版本号> <stable|preview> "更新说明"
# 例：
./publish.sh ../Novex-Development/artifacts/Novex-0.2.3-xxx.apk 0.2.3 stable "修复会话设置闪退"
```

脚本自动完成：创建 Release → 上传 APK 附件 → 更新 `update.json` → commit + push。
发完后必须执行下方「验证清单」。

## 发版 —— 手动方式（脚本不可用时）

API base：`https://gitee.com/api/v5`，认证参数 `access_token=<令牌>`。

1. **创建 Release**（记下返回的 `id`）：

   ```bash
   curl -s -X POST "https://gitee.com/api/v5/repos/ccbili/novex/releases" \
     -d "access_token=$TOKEN" \
     -d "tag_name=v0.2.3" -d "name=Novex v0.2.3" \
     -d "target_commitish=main" -d "prerelease=false" \
     -d "body=<更新说明 markdown>"
   ```

2. **上传 APK 附件**（⚠️ 字段名是单数 `file`，用 `files`/`files[]` 都会报 `file is missing`）：

   ```bash
   curl -s -X POST "https://gitee.com/api/v5/repos/ccbili/novex/releases/<release_id>/attach_files" \
     -F "access_token=$TOKEN" \
     -F "file=@/path/to/app.apk"
   ```

3. **更新 `update.json`** 中对应通道（stable / preview），`download` 字段格式固定：
   `https://gitee.com/ccbili/novex/releases/download/<tag>/<apk文件名>`

4. **提交推送**：`git add update.json && git commit -m "release: v0.2.3" && git push origin main`

## 写公告

1. 新建 `announcements/YYYY-MM-DD-标题.md`（中文正文）；
2. 在 `README.md` 的「📢 公告」列表顶部加一行链接；
3. commit + push。

## 验证清单（每次发版/公告后必须全过）

```bash
# 1. 更新源可匿名读取，且包含新版本号（raw 是 302 跳转，必须 -L）
curl -sL "https://gitee.com/ccbili/novex/raw/main/update.json" | python3 -m json.tool

# 2. APK 直链最终 200，Content-Length 与本地文件一致（302 两跳是正常行为）
curl -sD - -o /dev/null -L "https://gitee.com/ccbili/novex/releases/download/<tag>/<文件名>" | grep -iE "^(HTTP|content-length)"

# 3. 仓库页匿名可访问（若 404 = 仓库被设回私有，需提醒用户在网页端改回公开）
curl -s -o /dev/null -w "%{http_code}" "https://gitee.com/ccbili/novex"
```

## 限制与已知坑

- 单个附件 ≤ **100MB**（`publish.sh` 已内置检查；超限需分卷压缩成多个附件）。
- Release API 响应**没有 `html_url` 字段**（实际字段：`id, tag_name, name, body, assets, prerelease, created_at...`），别依赖它拼地址。
- raw 链接会 302 到 `raw.giteeusercontent.com` 的带签名地址，客户端需跟随重定向，签名会过期（不要缓存重定向结果）。
- 预览版必须 `prerelease=true`，否则会混进稳定列表。
- Gitee 令牌权限只需 `user_info` + `projects`；令牌泄露/过期时让用户在 [gitee.com/profile/personal_access_tokens](https://gitee.com/profile/personal_access_tokens) 重新生成，并更新钥匙串：
  `security add-generic-password -a ccbili -s gitee-token -w <新令牌> -U`
