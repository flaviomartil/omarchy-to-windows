#!/usr/bin/env bash
# Project rules that no linter knows, each one a mistake that cost a session. Run by `npm run check`.
#
#   scripts/lint-rules.sh              (LINT_RULES_ROOT=DIR checks another tree, for the tests)
#
# detached  A background launch (`setsid -f`) must redirect its own output (`2>&1` on the launch). One that keeps the caller's stdout
#           open makes `scripts/dev up | tail` wait until the background process ends (up to 30 minutes), so the next command never
#           runs and a ready session sits unused.
# tours     A tour must not name the real shell config in TOUR_SANDBOX_COPY or TOUR_SANDBOX_LINK: the sandbox has its own shell.json,
#           and a copy or a link of the real one would let the session write to it.
set -uo pipefail
root=${LINT_RULES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
cd "$root" || exit 1
fail=0

# A launch can span lines (a trailing backslash), so each logical line is joined first.
detached() {
  local f hits
  for f in scripts/dev scripts/*.sh scripts/nested/*.sh scripts/tours/*.sh; do
    [[ -f $f ]] || continue
    hits=$(perl -0pe 's/\\\n\s*//g' "$f" | grep -n 'setsid -f' | grep -v '2>&1' | cut -c1-140 || true)
    [[ -z $hits ]] || { echo "$f: setsid -f without 2>&1 (its output keeps the caller's pipe open):"; printf '    %s\n' "${hits//$'\n'/$'\n    '}"; return 1; }
  done
}

tours() {
  local hits
  hits=$(sed 's/ *#.*//' scripts/tours/*.sh scripts/dev | grep -nE '^TOUR_SANDBOX_(COPY|LINK)=.*shell\.json' || true)
  [[ -z $hits ]] || { echo "a sandbox copy or link names the real shell.json (the session writes its own):"; printf '    %s\n' "${hits//$'\n'/$'\n    '}"; return 1; }
}

for rule in detached tours; do
  out=$($rule 2>&1) || { printf '%s\n' "$out"; fail=1; }
done
((fail == 0)) && echo "lint-rules: ok"
exit $fail
