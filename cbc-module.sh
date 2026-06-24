#!/usr/bin/env bash

################################################################################
# COMMIT-AND-TAG-VERSION
################################################################################

alias ver='npx commit-and-tag-version'
alias veras='npx commit-and-tag-version --release-as'

function verg() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    printf "verg must be run inside a git repository.\n" >&2
    return 1
  }

  local cwd
  cwd=$(pwd -P)
  if [[ "$cwd" != "$repo_root" ]]; then
    printf "verg is running outside the repository root: %s\n" "$repo_root" >&2
    if ! gum confirm "Change directory to repository root and continue?"; then
      return 1
    fi
    if ! cd "$repo_root"; then
      printf "Failed to change directory to repository root: %s\n" "$repo_root" >&2
      return 1
    fi
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

  local zensical_config
  local zensical_cmd
  zensical_config="zensical.toml"
  zensical_cmd="zensical"

  if [[ -f "$zensical_config" ]]; then
    if [[ -x ".venv/bin/zensical" ]]; then
      zensical_cmd=".venv/bin/zensical"
    elif ! command -v zensical >/dev/null 2>&1; then
      printf "zensical not found. Install it or create .venv/bin/zensical before running verg.\n" >&2
      return 1
    fi

    if ! gum spin --spinner dot --title "Building zensical docs site..." --show-error -- "$zensical_cmd" build --clean; then
      return 1
    fi

    if [[ -n "$(git status --porcelain -- site)" ]]; then
      if ! git add -A -- site; then
        return 1
      fi

      if ! git commit -m "build(site): build zensical docs site"; then
        return 1
      fi
    fi
  fi

  if npx commit-and-tag-version "${args[@]}"; then
    if gum spin --spinner dot --title "Pushing commits..." --show-error -- git push; then
      if gum spin --spinner dot --title "Pushing tags..." --show-error -- git push --tags; then
        local latest_tag
        latest_tag=$(git describe --tags --abbrev=0)

        local changelog_file
        local notes_file
        local release_url_file
        local created_release_url
        local release_edit_url
        local line
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

        if ! release_url_file=$(mktemp); then
          rm -f "$notes_file"
          return 1
        fi

        if gum spin --spinner dot --title "Creating GitHub release draft..." -- \
          bash -c 'gh release create "$1" --notes-file "$2" -d > "$3"' _ \
            "$latest_tag" "$notes_file" "$release_url_file"; then
          created_release_url=""
          while IFS= read -r line; do
            case "$line" in
              https://*|http://*)
                created_release_url="$line"
                ;;
            esac
          done < "$release_url_file"

          case "$created_release_url" in
            */releases/tag/*)
              release_edit_url=${created_release_url/\/releases\/tag\//\/releases\/edit\/}
              gum spin --spinner dot --title "Waiting for GitHub release draft..." -- sleep 4
              gum spin --spinner dot --title "Opening GitHub release draft..." -- xdg-open "$release_edit_url"
              ;;
            */releases/edit/*)
              gum spin --spinner dot --title "Waiting for GitHub release draft..." -- sleep 4
              gum spin --spinner dot --title "Opening GitHub release draft..." -- xdg-open "$created_release_url"
              ;;
            *)
              printf "Could not determine created release draft URL; skipping browser open.\n" >&2
              ;;
          esac
        fi

        rm -f "$release_url_file"
        rm -f "$notes_file"
      fi
    fi
  fi
}
