#!/usr/bin/env bash

################################################################################
# COMMIT-AND-TAG-VERSION
################################################################################

alias ver='npx commit-and-tag-version'
alias veras='npx commit-and-tag-version --release-as'

function verg() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    printf "verg must be run from a git repository root.\n" >&2
    return 1
  }

  local cwd
  cwd=$(pwd -P)
  if [[ "$cwd" != "$repo_root" ]]; then
    printf "verg must be run from repository root: %s\n" "$repo_root" >&2
    return 1
  fi

  gum style \
    --border rounded \
    --border-foreground "#b4befe" \
    --margin "1 0" \
    --padding "0 2" \
    "PREVIEWING NEXT VERSION"

  local args
  args=("$@")

  local release_override=0
  local arg
  for arg in "${args[@]}"; do
    case "$arg" in
      --release-as|--release-as=*|-r)
        release_override=1
        break
        ;;
    esac
  done

  if [[ "$release_override" -eq 0 ]]; then
    if ! git describe --tags --abbrev=0 >/dev/null 2>&1; then
      args+=(--release-as 0.0.1)
    fi
  fi

  if ! npx commit-and-tag-version "${args[@]}" --dry-run --skip.commit --skip.tag; then
    return 1
  fi

  if ! gum confirm "Proceed with commit-and-tag-version, push commits/tags, and draft release?"; then
    return 0
  fi

  if npx commit-and-tag-version "${args[@]}"; then
    if gum spin --spinner dot --title "Pushing commits..." --show-error -- git push; then
      if gum spin --spinner dot --title "Pushing tags..." --show-error -- git push --tags; then
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

        if gum spin --spinner dot --title "Creating GitHub release draft..." -- \
          gh release create "$latest_tag" --notes-file "$notes_file" -d; then
          gum spin --spinner dot --title "Waiting for GitHub release draft..." -- sleep 2
          gum spin --spinner dot --title "Opening GitHub release draft..." -- gh browse -r
        fi

        rm -f "$notes_file"
      fi
    fi
  fi
}
