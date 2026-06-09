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
3. **Commit** — `git add CHANGELOG.md && git commit -m "docs: update CHANGELOG for X.Y.Z"`.
4. **Tag** — `git tag X.Y.Z` (bare semver, no `v` prefix).
5. **Push** — `git push origin main --tags`.

All 5 steps execute without interruption after the version is confirmed.

## Rules

- Tag format: bare semver only. `0.3.0` ✅ / `v0.3.0` ❌
- The tag version MUST match the `## [X.Y.Z]` heading in CHANGELOG.md exactly — CI extracts the release body by this match.
- Do NOT create a tag if CHANGELOG.md has no matching heading.
