# Commit And Tag Version

Convenience wrappers for `commit-and-tag-version` release automation.
Includes preview and guided release flow with an optional GitHub draft.

## Functions

- `verg`: Preview next version, run release, push commits and tags, and draft
  a GitHub release. If run outside the repository root, `verg` prompts to
  change directories; if run outside a git repo, it exits. When
  `zensical.toml` is present and you confirm the release flow, `verg` runs
  `zensical build --clean` and commits updated `site/` output before the
  release commit.

### Opening release drafts

On Hyprland, `verg` uses `hyprctl` and `jq` to select the most recently used
dedicated window of the default browser, then opens the draft in a new tab.
Web-app window classes and private/incognito/guest window title markers are
excluded from focus selection. The browser's native normal-profile URL handling
keeps the draft out of private sessions. If no eligible window is found, `verg`
requests a new normal browser window.

Supported defaults are Brave (including Brave Origin), Chromium, Google Chrome,
Microsoft Edge, and Firefox. Omarchy's browser preference is used when available;
otherwise, `verg` reads `xdg-settings`. If the browser is unsupported or window
selection fails, `verg` reports the failure and prints the created draft URL for
manual opening.

## Aliases

- `ver`: Run `npx commit-and-tag-version`.
- `veras`: Run `npx commit-and-tag-version --release-as`.
