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

  local branch branch_choice
  branch=$(git branch --show-current) || return 1
  branch=${branch:-detached HEAD}
  if [[ "$branch" != "main" ]]; then
    printf "verg is running outside the main branch: %s\n" "$branch" >&2
    branch_choice=$(gum choose "Switch to main" "Run anyway on $branch" "Cancel") || return 1
    case "$branch_choice" in
      "Switch to main")
        if ! git switch main; then
          printf "Failed to switch to main; stopping verg.\n" >&2
          return 1
        fi
        ;;
      "Run anyway on $branch") ;;
      *) return 1 ;;
    esac
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

  local tags_before release_tags latest_tag tag
  tags_before=$(git tag --list) || return 1

  if npx commit-and-tag-version "${args[@]}"; then
    release_tags=$(git tag --points-at HEAD) || return 1
    latest_tag=""
    # Only select a tag created by this invocation on the release commit.
    while IFS= read -r tag; do
      [[ -n "$tag" ]] || continue
      if [[ $'\n'"$tags_before"$'\n' != *$'\n'"$tag"$'\n'* ]]; then
        if [[ -n "$latest_tag" ]]; then
          printf "Multiple new release tags found; refusing to push tags.\n" >&2
          return 1
        fi
        latest_tag="$tag"
      fi
    done <<< "$release_tags"
    if [[ -z "$latest_tag" ]]; then
      printf "No new release tag found on HEAD; refusing to push tags.\n" >&2
      return 1
    fi

    if gum spin --spinner dot --title "Pushing commits..." --show-error -- git push; then
      if gum spin --spinner dot --title "Pushing tags..." --show-error -- \
        git -c push.followTags=false push origin "refs/tags/$latest_tag:refs/tags/$latest_tag"; then

        local changelog_file
        local notes_file
        local release_url_file
        local created_release_url
        local release_edit_url
        local line
        local release_status=0
        changelog_file="CHANGELOG.md"

        if [[ ! -f "$changelog_file" ]]; then
          printf "%s not found; skipping release draft.\n" "$changelog_file" >&2
          return 0
        fi

        notes_file=$(mktemp) || return 1
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

        if gum spin --spinner dot --title "Creating GitHub release draft..." --show-error -- \
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
              if gum spin --spinner dot --title "Waiting for GitHub release draft..." -- sleep 4; then
                gum spin --spinner dot --title "Opening GitHub release draft..." --show-error -- xdg-open "$release_edit_url" || release_status=$?
              else
                release_status=$?
              fi
              ;;
            */releases/edit/*)
              if gum spin --spinner dot --title "Waiting for GitHub release draft..." -- sleep 4; then
                gum spin --spinner dot --title "Opening GitHub release draft..." --show-error -- xdg-open "$created_release_url" || release_status=$?
              else
                release_status=$?
              fi
              ;;
            *)
              printf "Could not determine created release draft URL; skipping browser open.\n" >&2
              release_status=1
              ;;
          esac
        else
          release_status=$?
        fi

        rm -f "$release_url_file" "$notes_file" || {
          [[ "$release_status" -ne 0 ]] || release_status=1
        }
        return "$release_status"
      else
        return 1
      fi
    else
      return 1
    fi
  else
    return 1
  fi
}
