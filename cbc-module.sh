#!/usr/bin/env bash

################################################################################
# COMMIT-AND-TAG-VERSION
################################################################################

alias ver='npx commit-and-tag-version'
alias veras='npx commit-and-tag-version --release-as'

function verg() {
  gum style \
    --border rounded \
    --border-foreground "#b4befe" \
    --margin "1 0" \
    --padding "0 2" \
    "PREVIEWING NEXT VERSION"
  if ! npx commit-and-tag-version "$@" --dry-run --skip.commit --skip.tag; then
    return 1
  fi

  if ! gum confirm "Proceed with commit-and-tag-version?"; then
    return 0
  fi

  if npx commit-and-tag-version "$@"; then
    if gum confirm "Push commits and tags?"; then
      if git push && git push --tags; then
        local latest_tag
        latest_tag=$(git describe --tags --abbrev=0)

        local changelog_file
        local notes_file
        changelog_file="CHANGELOG.md"

        if [[ ! -f "$changelog_file" ]]; then
          printf "%s not found; skipping release draft.\n" "$changelog_file" >&2
          return 0
        fi

        notes_file=$(mktemp)
        if ! awk '
          BEGIN { found_release=0 }
          /^## / {
            if (!found_release) {
              if ($0 ~ /^## \[Unreleased\]/) {
                print
                next
              }
              found_release=1
              print
              next
            }
            exit
          }
          { print }
          END { if (!found_release) exit 1 }
        ' "$changelog_file" > "$notes_file"; then
          printf "No release section found in %s; skipping release draft.\n" "$changelog_file" >&2
          rm -f "$notes_file"
          return 0
        fi

        if [[ ! -s "$notes_file" ]]; then
          printf "No release notes found in %s; skipping release draft.\n" "$changelog_file" >&2
          rm -f "$notes_file"
          return 0
        fi

        if gh release create "$latest_tag" --notes-file "$notes_file" -d; then
          sleep 2
          gh browse -r
        fi

        rm -f "$notes_file"
      fi
    fi
  fi
}
