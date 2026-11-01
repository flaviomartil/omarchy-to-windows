#!/usr/bin/env bash
# Print the open release branch: the highest release/<version> on origin whose
# v<version> tag does not exist yet. That is the branch a pull request targets
# (docs/agents/release.md "Branches"). When every release branch is tagged, say so
# and name the next patch version to start from main.
set -euo pipefail

branches=$(git ls-remote --heads origin 'refs/heads/release/*' | sed 's|.*refs/heads/release/||' | sort -V)
tags=$(git ls-remote --tags origin 'refs/tags/v*' | sed 's|.*refs/tags/v||; s|\^{}$||' | sort -uV)

open=""
for v in $branches; do
  grep -qxF "$v" <<<"$tags" || open=$v
done

if [ -n "$open" ]; then
  echo "release/$open"
else
  last=$(tail -n1 <<<"$branches")
  next="${last%.*}.$(( ${last##*.} + 1 ))"
  echo "none open: every release branch is tagged. Start release/$next from origin/main." >&2
  exit 1
fi
