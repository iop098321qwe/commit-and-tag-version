#!/usr/bin/env bash

################################################################################
# COMMIT-AND-TAG-VERSION
################################################################################

alias ver='npx commit-and-tag-version'
alias ver='npx commit-and-tag-version --release-as'

function verg() {
  echo "Previewing next version (no changes made):"
  if ! npx commit-and-tag-version --dry-run --skip.commit --skip.tag; then
    return 1
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
