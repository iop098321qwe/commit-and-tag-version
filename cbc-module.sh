#!/usr/bin/env bash

################################################################################
# COMMIT-AND-TAG-VERSION
################################################################################

alias ver='npx commit-and-tag-version'
alias veras='npx commit-and-tag-version --release-as'

function _verg_heading() {
  gum style --border rounded --border-foreground '#b4befe' \
    --foreground '#b4befe' --bold --margin '1 0' --padding '0 2' -- "$@"
}

function _verg_message() {
  local color="$1"
  shift
  gum style --foreground "$color" --padding '0 2' -- "$@"
}

function _verg_run() (
  local title="$1" completed="$2" failure="$3"
  shift 3
  local status output_file
  output_file=$(mktemp) || return 1
  trap 'rm -f "$output_file"' EXIT
  # Gum passes command output through when stdout is not a terminal. Capture
  # it explicitly so successful operations stay quiet in every environment.
  if gum spin --spinner dot --spinner.foreground '#b4befe' \
    --title.foreground '#b4befe' --padding '0 2' \
    --title "$title" --show-error -- \
    bash -c 'output=$1; shift; exec "$@" > "$output" 2>&1' _ "$output_file" "$@"; then
    _verg_message '#a6e3a1' "$completed" || true
    return 0
  else
    status=$?
    _verg_message '#f38ba8' "Error: $failure" >&2
    if [[ -s "$output_file" ]]; then
      gum style --foreground '#cdd6f4' --padding '0 2' < "$output_file" >&2
    fi
    return "$status"
  fi
)

# Capture and render the dry run in a subshell so cleanup cannot change caller traps.
function _verg_preview() (
  set -o pipefail
  local preview_file
  preview_file=$(mktemp) || return 1
  trap 'rm -f "$preview_file"' EXIT

  if ! gum spin --spinner dot --spinner.foreground '#b4befe' \
    --title.foreground '#b4befe' --padding '0 2' \
    --title 'Preparing release preview...' --show-error -- \
    bash -c 'output=$1; shift; exec "$@" > "$output" 2>&1' _ "$preview_file" \
      npx commit-and-tag-version "$@" --dry-run --skip.commit --skip.tag; then
    gum style --foreground '#f38ba8' --padding '0 2' < "$preview_file" >&2
    _verg_message '#f38ba8' 'Error: Preview failed. Release creation was not attempted.' >&2
    return 1
  fi

  # The tool wraps its Markdown preview in standalone delimiters. Keep any
  # unrecognized messages visible and preserve delimiters inside the notes.
  local -a sections=()
  local section content
  for section in changes notes; do
    content=$(awk -v section="$section" '
      {
        gsub(sprintf("%c", 27) "\\[[0-9;]*m", "")
        lines[NR]=$0
        if ($0 == "---") {
          if (!first) first=NR
          last=NR
        }
      }
      END {
        for (i=1; i<=NR; i++) {
          in_notes=(first && last>first && i>first && i<last)
          if (section == "notes") {
            if (in_notes) print lines[i]
          } else if (!in_notes && !(last>first && (i==first || i==last))) {
            line=lines[i]
            if (line ~ /bumping version in /) {
              sub(/^.*bumping version in /, "Bump version in ", line)
            } else if (line ~ /outputting changes to /) {
              sub(/^.*outputting changes to /, "Update ", line)
            }
            if (line ~ /[^[:space:]]/) print line
          }
        }
      }
    ' "$preview_file") || return 1
    sections+=("$content")
  done

  gum style --foreground '#b4befe' --bold --padding '0 2' -- 'Planned changes' || return 1
  if [[ -n "${sections[0]}" ]]; then
    _verg_message '#cdd6f4' "${sections[0]}" || return 1
  else
    _verg_message '#9399b2' 'No changes reported by the release tool.' || return 1
  fi
  _verg_heading 'Release Notes Preview' || return 1
  if [[ -n "${sections[1]}" ]]; then
    printf '%s\n' "${sections[1]}" | gum format --type markdown || return 1
  else
    _verg_message '#9399b2' 'No release notes reported by the release tool.' || return 1
  fi
)

function verg() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    _verg_message '#f38ba8' 'Error: Run verg inside a Git repository.' >&2
    return 1
  }

  local cwd
  cwd=$(pwd -P)
  if [[ "$cwd" != "$repo_root" ]]; then
    _verg_message '#f9e2af' 'Current directory is not the repository root.' "$repo_root"
    if ! gum confirm --prompt.foreground '#b4befe' \
      --selected.background '#b4befe' --selected.foreground '#1e1e2e' \
      --affirmative Continue --negative Cancel 'Continue from the repository root?'; then
      _verg_message '#9399b2' 'Release cancelled.'
      return 1
    fi
    if ! cd "$repo_root"; then
      _verg_message '#f38ba8' "Error: Could not change directory to $repo_root." >&2
      return 1
    fi
  fi

  local branch branch_choice
  branch=$(git branch --show-current) || return 1
  branch=${branch:-detached HEAD}
  if [[ "$branch" != main ]]; then
    _verg_message '#f9e2af' "Current branch: $branch" 'Releases normally run from main.'
    branch_choice=$(gum choose --header 'Choose how to continue' \
      --header.foreground '#b4befe' --cursor.foreground '#b4befe' \
      'Switch to main' "Run anyway on $branch" Cancel) || return 1
    case "$branch_choice" in
      'Switch to main')
        _verg_run 'Switching to main...' 'Using branch main.' \
          'Could not switch to main. Release creation was not attempted.' git switch main || return 1
        branch=main
        ;;
      "Run anyway on $branch") ;;
      *) _verg_message '#9399b2' 'Release cancelled.'; return 1 ;;
    esac
  fi

  _verg_heading 'Release Preview' "Repository  ${repo_root##*/}" "Branch      $branch" || return 1
  local -a args=("$@")
  local release_override=0 arg
  for arg in "${args[@]}"; do
    case "$arg" in
      --release-as|--release-as=*|-r) release_override=1; break ;;
    esac
  done
  if [[ "$release_override" -eq 0 ]]; then
    if ! git describe --tags --abbrev=0 >/dev/null 2>&1; then
      args+=(--release-as 0.0.1)
      _verg_message '#f9e2af' 'No reachable tag found; previewing version 0.0.1.'
    fi
  fi
  _verg_preview "${args[@]}" || return 1

  local zensical_config=zensical.toml zensical_cmd=zensical
  _verg_heading 'Ready To Release' || return 1
  if [[ -f "$zensical_config" ]]; then
    _verg_message '#cdd6f4' 'Build documentation and commit updated site output.'
  fi
  _verg_message '#cdd6f4' 'Create the release commit and tag, then push both.' \
    'Create a GitHub draft if changelog notes are available; do not publish it.'
  if ! gum confirm --prompt.foreground '#b4befe' \
    --selected.background '#b4befe' --selected.foreground '#1e1e2e' \
    --affirmative Release --negative Cancel 'Create this release?'; then
    _verg_message '#9399b2' 'Release cancelled. No release was created.'
    return 0
  fi

  _verg_heading 'Release Progress' || return 1
  if [[ -f "$zensical_config" ]]; then
    if [[ -x .venv/bin/zensical ]]; then
      zensical_cmd=.venv/bin/zensical
    elif ! command -v zensical >/dev/null 2>&1; then
      _verg_message '#f38ba8' 'Error: Install Zensical or create .venv/bin/zensical before releasing.' >&2
      return 1
    fi
    _verg_run 'Building documentation...' 'Documentation built.' \
      'Documentation build failed. Release creation was not attempted.' \
      "$zensical_cmd" build --clean || return 1
    if [[ -n "$(git status --porcelain -- site)" ]]; then
      _verg_run 'Staging documentation...' 'Documentation staged.' \
        'Could not stage documentation. Release creation was not attempted.' \
        git add -A -- site || return 1
      _verg_run 'Committing documentation...' 'Documentation changes committed.' \
        'Could not commit documentation. Release creation was not attempted.' \
        git commit -m 'build(site): build zensical docs site' || return 1
    else
      _verg_message '#9399b2' 'Documentation up to date; no site commit needed.'
    fi
  fi

  local tags_before release_tags latest_tag tag
  tags_before=$(git tag --list) || return 1
  _verg_run 'Creating release...' 'Release command completed.' \
    'Release command failed. Pushes were not attempted; inspect local changes before retrying.' \
    npx commit-and-tag-version "${args[@]}" || return 1
  release_tags=$(git tag --points-at HEAD) || return 1
  latest_tag=''
  # Only select a tag created by this invocation on the release commit.
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    if [[ $'\n'"$tags_before"$'\n' != *$'\n'"$tag"$'\n'* ]]; then
      if [[ -n "$latest_tag" ]]; then
        _verg_message '#f38ba8' 'Error: Multiple new release tags found. Pushes were not attempted.' >&2
        return 1
      fi
      latest_tag="$tag"
    fi
  done <<< "$release_tags"
  if [[ -z "$latest_tag" ]]; then
    _verg_message '#f38ba8' 'Error: No new release tag found on HEAD. Pushes were not attempted.' >&2
    return 1
  fi
  _verg_message '#a6e3a1' "Release tag: $latest_tag"
  _verg_run 'Pushing commits...' 'Commits pushed.' \
    "Commit push failed. Release $latest_tag exists locally; draft creation was not attempted." \
    git push || return 1
  _verg_run 'Pushing release tag...' "Release tag $latest_tag pushed." \
    'Tag push failed. The commit push completed; draft creation was not attempted.' \
    git -c push.followTags=false push origin "refs/tags/$latest_tag:refs/tags/$latest_tag" || return 1

  local changelog_file=CHANGELOG.md notes_file release_url_file
  local created_release_url='' release_edit_url='' line release_status=0
  if [[ ! -f "$changelog_file" ]]; then
    _verg_heading 'Release Pushed' "Tag  $latest_tag"
    _verg_message '#f9e2af' "$changelog_file not found; GitHub draft skipped."
    return 0
  fi
  notes_file=$(mktemp) || return 1
  if ! awk '
    BEGIN { found_release=0 }
    /^## / {
      if (!found_release) {
        if ($0 ~ /^## \[Unreleased\]/) { print; next }
        found_release=1
        print
        next
      }
      exit
    }
    { print }
    END { if (!found_release) exit 1 }
  ' "$changelog_file" > "$notes_file"; then
    _verg_heading 'Release Pushed' "Tag  $latest_tag"
    _verg_message '#f9e2af' "No release section found in $changelog_file; GitHub draft skipped."
    rm -f "$notes_file"
    return 0
  fi
  if [[ ! -s "$notes_file" ]]; then
    _verg_heading 'Release Pushed' "Tag  $latest_tag"
    _verg_message '#f9e2af' "No release notes found in $changelog_file; GitHub draft skipped."
    rm -f "$notes_file"
    return 0
  fi
  if ! release_url_file=$(mktemp); then
    rm -f "$notes_file"
    return 1
  fi

  if _verg_run 'Creating GitHub draft...' 'GitHub draft created; not published.' \
    'GitHub draft creation failed. The release commit and tag have already been pushed.' \
    bash -c 'exec gh release create "$1" --notes-file "$2" -d > "$3"' _ \
      "$latest_tag" "$notes_file" "$release_url_file"; then
    while IFS= read -r line; do
      case "$line" in
        https://*|http://*) created_release_url="$line" ;;
      esac
    done < "$release_url_file"
    case "$created_release_url" in
      */releases/tag/*) release_edit_url=${created_release_url/\/releases\/tag\//\/releases\/edit\/} ;;
      */releases/edit/*) release_edit_url="$created_release_url" ;;
      *)
        _verg_message '#f9e2af' 'Draft created, but its URL could not be determined. Browser opening skipped.' >&2
        release_status=1
        ;;
    esac
    if [[ -n "$release_edit_url" ]]; then
      if _verg_run 'Waiting to open draft...' 'Draft ready to open.' \
        'Could not wait to open the draft. The draft already exists.' sleep 4; then
        _verg_run 'Opening GitHub draft...' 'Draft opened in browser.' \
          'Could not open the browser. The draft already exists; use the URL below.' \
          xdg-open "$release_edit_url" || release_status=$?
      else
        release_status=$?
      fi
    fi
    if [[ "$release_status" -eq 0 ]]; then
      _verg_heading 'Release Complete' "Tag      $latest_tag" \
        'Commits  Pushed' 'Tag      Pushed' 'GitHub   Draft created'
    else
      _verg_heading 'Release Pushed' "Tag     $latest_tag" 'GitHub  Draft created'
    fi
    _verg_message '#9399b2' 'Draft saved; not published.'
    if [[ -n "$created_release_url" ]]; then
      _verg_message '#b4befe' "$created_release_url"
    fi
  else
    release_status=$?
  fi
  rm -f "$release_url_file" "$notes_file" || {
    [[ "$release_status" -ne 0 ]] || release_status=1
  }
  return "$release_status"
}
