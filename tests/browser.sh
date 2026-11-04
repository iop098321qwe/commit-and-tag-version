#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../cbc-module.sh"
command -v jq >/dev/null
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HYPRLAND_INSTANCE_SIGNATURE=verg-test
log="$work/commands"
url='https://github.com/example/project/releases/edit/v1.0.0?value=a&other=b'
test_desktop=brave-origin.desktop
test_clients='[]'
focus_status=0
browser_status=0
inventory_status=0

function omarchy-cmd-default-browser() { printf '%s\n' "$test_desktop"; }
function _verg_message() { :; }
function _verg_run() { shift 3; "$@"; }
function hyprctl() {
  if [[ $1 == clients ]]; then
    printf '%s\n' "$test_clients"
    return "$inventory_status"
  fi
  printf 'focus:%s\n' "$*" >> "$log"
  return "$focus_status"
}
function brave-origin() {
  printf 'browser:%s\n' "$*" >> "$log"
  [[ $# == 2 && $2 == "$url" ]] || return 99
  return "$browser_status"
}
function firefox() { brave-origin "$@"; }
function assert_contains() {
  local contents
  contents=$(< "$log")
  [[ $contents == *"$1"* ]] || {
    printf 'Expected %s, got: %s\n' "$1" "$contents" >&2
    exit 1
  }
}
function assert_no_browser() {
  [[ $(< "$log") != *browser:* ]] || exit 1
}

# Prefer the most recently used dedicated window over apps and private windows,
# even when the excluded windows have a more recent focus history.
test_clients='[
  {"mapped":true,"class":"brave-origin","address":"0x10","focusHistoryID":4},
  {"mapped":true,"class":"brave-origin","address":"0x20","focusHistoryID":3},
  {"mapped":true,"class":"brave-example.com__-Default","address":"0x30","focusHistoryID":0},
  {"mapped":true,"class":"brave-origin","address":"0x40","focusHistoryID":1,
   "initialTitle":"New Private Tab - Brave Origin","title":"A regular page title"},
  {"mapped":false,"class":"brave-origin","address":"0x50","focusHistoryID":2}
]'
: > "$log"
_verg_open_draft "$url"
assert_contains 'address:0x20'
assert_contains "browser:--new-tab $url"
[[ $(< "$log") != *address:0x40* ]]

# An app-only or private-only session must start a normal window.
for test_clients in \
  '[]' \
  '[{"mapped":true,"class":"brave-example.com__-Default","address":"0x30"}]' \
  '[{"mapped":true,"class":"brave-origin","address":"0x40","initialTitle":"New Private Tab"}]' \
  '[{"mapped":true,"class":"brave-origin","address":"0x40","title":"Incognito"}]' \
  '[{"mapped":true,"class":"brave-origin","address":"0x40","title":"InPrivate"}]' \
  '[{"mapped":true,"class":"brave-origin","address":"0x40","title":"Guest"}]'; do
  : > "$log"
  _verg_open_draft "$url"
  assert_contains "browser:--new-window $url"
  [[ $(< "$log") != *focus:* ]]
done

# Do not retry a failed launch by creating another window.
: > "$log"
browser_status=7
if _verg_open_draft "$url"; then exit 1; else [[ $? == 7 ]]; fi
browser_status=0
assert_contains "browser:--new-window $url"

# Unknown desktop entries (including web apps) must not launch an arbitrary app.
: > "$log"
test_desktop=brave-example.com.desktop
if _verg_open_draft "$url"; then exit 1; fi
assert_no_browser
test_desktop=brave-origin.desktop

# A failed or malformed inventory does not prove that there are no windows.
for test_clients in 'invalid JSON' '{}' '[{"mapped":true,"class":"brave-origin","address":"bad"}]'; do
  : > "$log"
  if _verg_open_draft "$url" 2>/dev/null; then exit 1; fi
  assert_no_browser
done
test_clients='[]'
inventory_status=1
: > "$log"
if _verg_open_draft "$url"; then exit 1; fi
assert_no_browser
inventory_status=0

# Failed focus must not hand the URL to the previously focused web app.
test_clients='[{"mapped":true,"class":"brave-origin","address":"0x20"}]'
focus_status=1
: > "$log"
if _verg_open_draft "$url"; then exit 1; fi
assert_no_browser
focus_status=0

# Firefox uses its native new-tab/new-window commands as well.
test_desktop=firefox.desktop
test_clients='[{"mapped":true,"class":"firefox","address":"0x60"}]'
: > "$log"
_verg_open_draft "$url"
assert_contains 'address:0x60'
assert_contains "browser:--new-tab $url"

# Resolve the XDG preference on systems without Omarchy's resolver.
(
  unset -f omarchy-cmd-default-browser
  function command() {
    [[ $* != '-v omarchy-cmd-default-browser' ]] || return 1
    builtin command "$@"
  }
  function xdg-settings() {
    [[ $* == 'get default-web-browser' ]] || return 1
    printf '%s\n' firefox.desktop
  }
  : > "$log"
  _verg_open_draft "$url"
  assert_contains "browser:--new-tab $url"
)

# Missing compositor context must not fall through to an arbitrary URL handler.
(
  unset HYPRLAND_INSTANCE_SIGNATURE
  : > "$log"
  if _verg_open_draft "$url"; then exit 1; fi
  assert_no_browser
)

printf 'Browser selection regression checks passed.\n'
