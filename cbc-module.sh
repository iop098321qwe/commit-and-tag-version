#!/usr/bin/env bash

################################################################################
# COMMIT-AND-TAG-VERSION
################################################################################

alias ver='npx commit-and-tag-version'
alias verg='ver && gpfom && printf "\n Run gh cr to create a release\n"'
