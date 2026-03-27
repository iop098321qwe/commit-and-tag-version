# Commit And Tag Version

Convenience wrappers for `commit-and-tag-version` release automation.
Includes preview and guided release flow with an optional GitHub draft.

## Functions
- `verg`: Preview next version, run release, push commits and tags, and draft
  a GitHub release. Run only from the repository root.

## Aliases
- `ver`: Run `npx commit-and-tag-version`.
- `veras`: Run `npx commit-and-tag-version --release-as`.
