#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../cbc-module.sh"
work=$(mktemp -d)
trap 'rm -f "$work"/commit-and-tag-version; rmdir "$work"' EXIT
export PATH="$work:$PATH"

cat > "$work/commit-and-tag-version" <<'EOF'
#!/usr/bin/env bash
[[ $# == 5 && $1 == --release-as && $2 == 'two words; literal' &&
   $3 == --dry-run && $4 == --skip.commit && $5 == --skip.tag ]] || exit 99
printf '%s\n' 'outputting changes to CHANGELOG.md' --- 'Test release notes' ---
EOF
chmod +x "$work/commit-and-tag-version"

function npx() {
  [[ $1 == --package=commit-and-tag-version && $2 == -- ]] || return 99
  shift 2
  if [[ -n "$prompt" ]]; then
    printf 'npm %s: Ok to proceed? (y)\n' "$prompt"
    local answer
    read -r answer && [[ $answer == y ]] || return 1
  fi
  "$@"
}

function gum() {
  case "$1" in
    format) sed 's/^/Formatted notes: /' ;;
    style) : ;;
    *) return 99 ;;
  esac
}
function _verg_message() { shift; printf '%s\n' "$@"; }
function _verg_heading() { printf '%s\n' "$@"; }

for prompt in '' install upgrade; do
  output=$(_verg_preview --release-as 'two words; literal' <<< y)
  [[ $output == *'Update CHANGELOG.md'* ]]
  [[ $output == *'Formatted notes: Test release notes'* ]]
  if [[ -n "$prompt" ]]; then
    [[ $output == *"npm $prompt: Ok to proceed? (y)"* ]]
    [[ $output != *'Update npm'* ]]
  fi
done

prompt=install
if output=$(_verg_preview --release-as 'two words; literal' <<< n 2>&1); then
  printf 'Preview unexpectedly succeeded after declining installation.\n' >&2
  exit 1
fi
[[ $output == *'npm install: Ok to proceed? (y)'* ]]
[[ $output == *'Release creation was not attempted.'* ]]
[[ $output != *'Test release notes'* ]]
