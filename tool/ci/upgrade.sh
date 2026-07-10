#!/usr/bin/env bash
set -euo pipefail
#
# Upgrade radar — the ONE place that watches this repo's own auto-bumpable pin.
# upgrade-check.yml runs `apply` daily and opens a single reviewed PR if pana
# drifted from pub.dev's latest.
#
# Watched here (this package's LOCAL pin):
#   pana   PANA_VERSION   pub.dev — the platform gate must run the SAME pana
#                         pub.dev runs, or it drifts from the verdict it exists
#                         to predict, so this tracks pub.dev's latest.
#
# Owned elsewhere by design (NOT here):
#   Flutter SDK (.fvmrc), lockfiles   the shared upgrade-check reusable workflow
#   fvm / Chrome / bore gate pins     whuppi/ci (its self-upgrade bumps them;
#                                       they reach this repo via a whuppi/ci
#                                       release + the whuppi-ci Dependabot group)
#   pub deps, GitHub-action SHAs      Dependabot (.github/dependabot.yml)
#
# No sha-pinned assets here (pana resolves from pub.dev), so no verify-pinned /
# check-availability — nothing to re-hash or HEAD.
#
# Usage:  tool/ci/upgrade.sh check   # report drift, write nothing
#         tool/ci/upgrade.sh apply   # rewrite versions.env in place

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"  # tool/ci/ -> repo root
VERSIONS="$ROOT/tool/versions.env"

# shellcheck source=/dev/null  # runtime path; not followed at lint time
source "$VERSIONS"

MODE="${1:-check}"
case "$MODE" in
  check|apply) ;;
  *) echo "usage: tool/ci/upgrade.sh [check|apply]" >&2; exit 2 ;;
esac

command -v jq >/dev/null 2>&1 || { echo "upgrade: jq not found (needed to parse the pub.dev manifest)" >&2; exit 2; }

# Hardened GET: fail-closed, capped redirects, a few retries so a transient blip
# doesn't fail the daily run.
_fetch() { curl -fsSL --retry 3 --retry-delay 2 --max-redirs 5 --connect-timeout 10 --max-time 30 "$@"; }

set_kv() {  # KEY value file — replace the KEY="old" line with KEY="new"
  # versions.env is sourced, so a value is executed on read. Validate the shape
  # before writing so a malformed upstream string can't be persisted and run.
  case "$1" in
    *VERSION*) printf '%s' "$2" | grep -qE '^[A-Za-z0-9._+-]+$' \
                 || { echo "set_kv: refusing malformed version for $1: '$2'" >&2; return 1; } ;;
    *) echo "set_kv: unknown key shape '$1' (expect *_VERSION)" >&2; return 1 ;;
  esac
  # The value travels via the environment — not a sed replacement, not awk -v —
  # so a |, &, or backslash in it stays literal data. tmp+mv leaves the file
  # intact if awk ever fails mid-write.
  local tmp="$3.tmp"
  if sk_key="$1" sk_val="$2" awk '
        BEGIN { k = ENVIRON["sk_key"]; v = ENVIRON["sk_val"] }
        $0 ~ "^" k "=" { print k "=\"" v "\""; next }
        { print }
      ' "$3" > "$tmp"; then
    mv "$tmp" "$3"
  else
    rm -f "$tmp"
    return 1
  fi
}

# ── pana (PANA_VERSION in versions.env; the `platforms` make target + CI gate).
# Track pub.dev's LATEST from its own API — the gate must run the same pana
# pub.dev runs, or it drifts from the platform verdict it exists to predict.
drift=0
pana_latest="$(_fetch https://pub.dev/api/packages/pana 2>/dev/null | jq -r '.latest.version // empty' 2>/dev/null || true)"
if [ -n "${PANA_VERSION:-}" ] && [ -n "$pana_latest" ] && [ "$PANA_VERSION" != "$pana_latest" ]; then
  drift=1
  echo "pana: $PANA_VERSION -> $pana_latest"
  [ "$MODE" = apply ] && set_kv PANA_VERSION "$pana_latest" "$VERSIONS"
fi

[ "$drift" -eq 0 ] && echo "pana pin is current."
exit 0
