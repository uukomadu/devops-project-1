#!/usr/bin/env bash
#
# Security gate for terraform/. Runs checkov, pinned to one image, against the
# checks in checks.txt and exits non-zero if any of them fail.
#
# Usage:
#   ./scan.sh          gated run; exit 1 on any failed check from checks.txt
#   ./scan.sh --full   report every checkov finding, gate on nothing
#
# Requires Docker only. No local checkov, python or pip install.

set -euo pipefail

IMAGE="bridgecrew/checkov:3.3.16"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FULL="${1:-}"

# Strip comments and blanks, join to the comma list checkov's -c wants.
# [:blank:] is space and tab only; [:space:] would eat the newlines too.
CHECKS="$(sed 's/#.*//' "$HERE/checks.txt" | tr -d '[:blank:]' | grep -v '^$' | paste -sd, -)"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

scan() { # scan [extra args...]
  docker run --rm -v "$HERE/terraform:/tf:ro" "$IMAGE" \
    -d /tf --framework terraform --quiet --compact --skip-path '.terraform' "$@" 2>/dev/null
}

if [[ "$FULL" == "--full" ]]; then
  echo "### Unfiltered scan: every checkov policy, gating on none"
  echo
  scan || true
  exit 0
fi

echo "### Gated scan: $(grep -cE '^\s*CKV' "$HERE/checks.txt") checks from checks.txt"
echo

# checkov exits non-zero whenever a check fails. Under `set -e` and `pipefail`
# that would end the script before anything is parsed, so capture first.
OUT="$(scan -c "$CHECKS" -o json || true)"

# Count failures without jq, which is not installed everywhere. Unparseable
# output is a failure, not zero findings.
FAILS="$(printf '%s' "$OUT" | python3 -c 'import json,sys
raw=sys.stdin.read().strip()
if not raw:
    print("PARSE_ERROR"); sys.exit(0)
d=json.loads(raw)
b=d if isinstance(d,list) else [d]
print(sum(len(x.get("results",{}).get("failed_checks",[])) for x in b))')"

# Human-readable listing for the log, after the count so the exit code
# depends on parsed JSON rather than on grep over text.
scan -c "$CHECKS" || true
echo

if ! [[ "$FAILS" =~ ^[0-9]+$ ]]; then
  red "FAIL  could not parse checkov output (got '$FAILS'). Treating as a failure."
  exit 1
fi

if [[ "$FAILS" -ne 0 ]]; then
  red "FAIL  $FAILS gated check(s) failed."
  exit 1
fi

green "OK    0 gated checks failed."
