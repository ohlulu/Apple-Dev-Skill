---
name: release-Apple-Dev-Skill
description: >-
  Execute the tag-driven release flow for this project: update changelog,
  commit, tag, push, and let GitHub Actions create the Release.
  Use when asked to release, publish a new version, or prepare a release.
  Trigger words: "release", "publish", "tag", "發佈", "發版", "出版本".
---

# Release

Tag-driven release. GitHub Actions creates the Release automatically from the changelog.

## Steps

1. **Ask version** — ask the user for the version number up front (bare semver, no `v` prefix: `0.1.0`, `1.0.0`). This is the only question — everything after runs without confirmation.
2. **Update CHANGELOG.md** — use the `update-changelog` skill. Ensure the `## [X.Y.Z]` heading matches the version exactly.
3. **Sync manifests** — set `version` to X.Y.Z in ALL of: `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`, `agents/openai.yaml`. These drift silently when skipped.
4. **Sync README** — regenerate the `<!-- BEGIN REFERENCE STRUCTURE -->` block from `ls apple-dev-skill/references/` and update the reference-file count in the "What's Inside" table. New references added since the last release must appear in both.
5. **Commit** — `git add -A && git commit -m "docs: prepare release X.Y.Z"`.
6. **Tag** — `git tag X.Y.Z` (bare semver, no `v` prefix).
7. **Push** — `git push origin main --tags`.

All steps after 1 execute without interruption once the version is confirmed.

## Rules

- Tag format: bare semver only. `0.3.0` ✅ / `v0.3.0` ❌
- The tag version MUST match the `## [X.Y.Z]` heading in CHANGELOG.md exactly — CI extracts the release body by this match.
- Do NOT create a tag if CHANGELOG.md has no matching heading.
