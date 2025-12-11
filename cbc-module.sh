#!/usr/bin/env bash

################################################################################
# COMMIT-AND-TAG-VERSION
################################################################################

alias ver='npx commit-and-tag-version'
alias veras='npx commit-and-tag-version --release-as'

function verg() {
  local dry_run_output
  if ! dry_run_output=$(npx commit-and-tag-version --dry-run --skip.commit --skip.tag 2>&1); then
    echo "$dry_run_output"
    return 1
  fi

  local new_version
  new_version=$(echo "$dry_run_output" | sed -n 's/.*bumping version[^[:digit:]]*\([0-9][^[:space:]]*\)\s*$/\1/p' | tail -n 1)
  if [[ -z "$new_version" ]]; then
    new_version=$(echo "$dry_run_output" | sed -n 's/.*tagging release \(v[^[:space:]]*\).*/\1/p' | tail -n 1)
  fi

  if [[ -n "$new_version" ]]; then
    echo "Previewing next version ($new_version):"
  else
    echo "Previewing next version (unknown):"
  fi

  echo "$dry_run_output"

  if [[ -n "$new_version" ]]; then
    echo
    echo "========================================"
    echo "Next version: $new_version"
    echo "========================================"
    echo
  fi

  if ! gum confirm "Proceed with commit-and-tag-version?"; then
    return 0
  fi

  if npx commit-and-tag-version; then
    if gum confirm "Push commits and tags?"; then
      if git push && git push --tags; then
        local latest_tag
        latest_tag=$(git describe --tags --abbrev=0)

        if gh release create "$latest_tag" --notes-file CHANGELOG.md -d; then
          gh browse -r
        fi
      fi
    fi
  fi
}
