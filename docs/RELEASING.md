---
summary: Release facts and deviations for Apple-Dev-Skill — tag-driven GitHub Release
read_when:
  - Cutting a release
  - Checking which manifests must be version-synced
---

# Releasing Apple-Dev-Skill

Procedure lives in the `release-flow` skill (`references/tag-ci.md`). CI builds
the GitHub Release from the tag; this file owns only what is true for this repo.

## Facts

```yaml
app: Apple-Dev-Skill
channel: tag-ci

tag:
  format: "{version}"           # bare semver — 0.3.0, never v0.3.0
changelog_heading: "## [{version}]"

sync_files:
  - .claude-plugin/plugin.json          # version field
  - .cursor-plugin/plugin.json          # version field
  - agents/openai.yaml                  # version field
  - README.md                           # BEGIN REFERENCE STRUCTURE block + reference count
```

## Deviations

| 項目 | 這個 repo 的做法 | 為什麼 |
|---|---|---|
| README 需要重新生成 | 從 `ls apple-dev-skill/references/` 重建 `<!-- BEGIN REFERENCE STRUCTURE -->` 區塊，並更新 "What's Inside" 表格裡的 reference 數量 | 上次發版後新增的 reference 檔不會自動出現，兩處都漏掉的話 README 會宣稱一個不存在的內容清單 |
| 三份 manifest 要同步 | plugin.json ×2 + openai.yaml 的 `version` 都要改成新版本 | 版本不一致時沒有任何步驟會失敗，所以它會安靜地漂移下去 |
