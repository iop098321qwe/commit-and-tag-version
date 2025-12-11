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
