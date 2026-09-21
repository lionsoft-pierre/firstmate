#!/usr/bin/env bash
# tests/fm-bearings-board-lavish-live-e2e.test.sh - live drift guard proving
# the real lavish-axi still behaves the way bin/fm-bearings-board.sh's session
# liveness check is written against.
#
# Why this file exists: the build's "is this board actually live" verdict comes
# from what lavish-axi emits, which is a surface the vendor controls and changes
# without notice. The defect this guards was exactly that - opening a session
# the captain had ended from the browser EXITS 0 while refusing to reopen, so a
# build that trusted the exit status armed a poll against a dead session and the
# board read "not listening" with nobody watching it. A stubbed lavish-axi can
# only confirm the assumption already written into the stub, so the assumption
# itself needs a run against the real tool.
#
# The captain-ended state is reached through the same server route the browser's
# End session button calls, so no browser is needed and nothing here depends on
# a human. The artifact is a scratch page in a temporary directory, and the
# session it opens is ended again before the guard returns.
#
# Standard CI has no lavish-axi, so this reports a capability skip there. The
# portable counterpart in tests/fm-bearings-board.test.sh pins the build's logic
# in CI against a stub that reproduces these shapes. Run this guard after a
# lavish-axi upgrade and before trusting refreshed evidence.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fm_live_gate default-on FM_BEARINGS_LAVISH_LIVE lavish-axi jq curl

pass() { printf 'ok - %s\n' "$1"; }
note() { printf '# %s\n' "$1"; }

LAB=''
EVENTS_PID=''
cleanup() {
  [ -z "$EVENTS_PID" ] || kill "$EVENTS_PID" >/dev/null 2>&1 || true
  [ -z "$LAB" ] || {
    [ ! -f "$LAB/.lavish/bearings-board.html" ] \
      || lavish-axi end "$LAB/.lavish/bearings-board.html" >/dev/null 2>&1 || true
    rm -rf "$LAB"
  }
}
fail() { printf 'not ok - %s\n' "$1" >&2; cleanup; exit 1; }
trap cleanup EXIT

VERSION=$(lavish-axi --version 2>/dev/null | tr -d '[:space:]')
note "lavish-axi ${VERSION:-version-unknown}"

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-bearings-lavish-live.XXXXXX") || fail "cannot create the guard lab"
LAB=$(cd -P -- "$LAB" && pwd -P)
mkdir -p "$LAB/state" "$LAB/data"

cat > "$LAB/payload.json" <<'JSON'
{
  "schema": "fm-bearings-board.v1",
  "home": "lavish-live-guard",
  "generated": "2026-01-01T00:00Z",
  "prs_live": false,
  "captains_call": [
    {
      "key": "sample-live-guard-call",
      "type": "decision",
      "repo": "sample",
      "title": "Guard placeholder",
      "options": [{ "value": "yes", "label": "Yes" }]
    }
  ],
  "underway": [],
  "landed": [],
  "charted": []
}
JSON

run_board() {
  FM_HOME="$LAB" FM_STATE_OVERRIDE="$LAB/state" FM_DATA_OVERRIDE="$LAB/data" \
    FM_PROCEVENT_CLAIM_ROOT="$LAB/procevent-claims" \
    "$ROOT/bin/fm-bearings-board.sh" "$@"
}

BOARD="$LAB/.lavish/bearings-board.html"
run_board build "$LAB/payload.json" >/dev/null 2>&1 || fail "the guard board did not build"
[ -f "$BOARD" ] || fail "the guard board was not published"

url=$(lavish-axi "$BOARD" | sed -n 's/^[[:space:]]*url:[[:space:]]*//p' | head -1 | tr -d '"')
case "$url" in
  http://*/session/*) ;;
  *) fail "could not read the guard board session url: $url" ;;
esac
key=${url##*/}
base=${url%/session/*}

# End it exactly as the browser's End session button does.
curl -fsS -X POST "$base/api/$key/end" >/dev/null 2>&1 \
  || fail "could not end the guard board session as the captain"

# ASSUMPTION UNDER GUARD: this exits 0 while reporting the session is not live.
set +e
ended_out=$(lavish-axi "$BOARD" 2>&1)
ended_rc=$?
set -e
[ "$ended_rc" -eq 0 ] \
  || fail "lavish-axi ${VERSION:-version-unknown} now exits $ended_rc on a captain-ended session; the board build's liveness check must be revisited"
ended_status=$(printf '%s\n' "$ended_out" | sed -n 's/^[[:space:]]*status:[[:space:]]*//p' | head -1 | tr -d '"')
[ "$ended_status" != opened ] \
  || fail "lavish-axi ${VERSION:-version-unknown} silently reopened a captain-ended session; the board build's liveness check must be revisited"
lavish-axi 2>/dev/null | grep -F "$BOARD," | grep -q ',open,' \
  && fail "lavish-axi ${VERSION:-version-unknown} still lists a captain-ended session as open; the board build's liveness check must be revisited"
pass "lavish-axi ${VERSION:-version-unknown} reports a captain-ended session without reopening it and without failing"

# THE BEHAVIOR UNDER GUARD: the build must not accept that, and must recover.
out=$(run_board build "$LAB/payload.json" 2>&1) \
  || fail "the board build refused a recoverable captain-ended session: $out"
case "$out" in
  *"session: reopened"*) ;;
  *) fail "the board build did not reopen the captain-ended session: $out" ;;
esac
lavish-axi 2>/dev/null | grep -F "$BOARD," | grep -q ',open,' \
  || fail "the board build reported success while the session was still not live"
pass "the board build reopens a captain-ended session against real lavish-axi instead of arming a dead one"

# THE VENDOR BEHAVIORS THE LIVE BOARD LEANS ON. bin/fm-bearings-board.sh refresh
# rewrites the board file atomically and calls nothing else, so the open page
# must be reloaded by the server's own file watcher; and every attempt that
# derives a payload rewrites the sibling bearings-board-checked.js the page
# loads through a script tag, so that sibling must be served fresh on every
# read through the artifact route WITHOUT the page being reloaded for it.
printf '# Live guard home\n' > "$LAB/AGENTS.md"
cat > "$LAB/data/backlog.md" <<'EOF2'
## In flight

## Queued
- [ ] guard-row - Guard queued row (repo: sample) (kind: ship) (since 2026-08-01)

## Done
EOF2
checked_epoch() {
  curl -fsS "$base/artifact/$key/bearings-board-checked.js?t=$(date +%s)-$RANDOM" \
    | sed -n 's/.*{checked: \([0-9][0-9]*\)}.*/\1/p'
}
first=$(checked_epoch)
case "$first" in ''|*[!0-9]*) fail "lavish-axi ${VERSION:-version-unknown} does not serve the check stamp beside the board: $(curl -sS "$base/artifact/$key/bearings-board-checked.js")" ;; esac
# The first refresh replaces the hand-written guard payload with the derived
# one, which is a real board change; the second finds the fleet unchanged and
# must still advance the check stamp without touching the page.
run_board refresh >/dev/null 2>&1 || fail "the guard board refresh failed: $(cat "$LAB/state/.bearings-board-refresh.log" 2>/dev/null)"
sleep 1.5
curl -sN --max-time 20 "$base/events/$key" > "$LAB/events.log" 2>/dev/null &
EVENTS_PID=$!
sleep 1.1
out=$(run_board refresh 2>&1) || fail "the unchanged guard board refresh failed: $out"
case "$out" in unchanged:*) ;; *) fail "the second refresh of an unchanged fleet republished the board: $out" ;; esac
second=$(checked_epoch)
[ "$second" -gt "$first" ] 2>/dev/null \
  || fail "lavish-axi ${VERSION:-version-unknown} served a stale check stamp after a refresh: $first -> $second"
sleep 1
kill "$EVENTS_PID" >/dev/null 2>&1 || true
wait "$EVENTS_PID" >/dev/null 2>&1 || true
EVENTS_PID=''
grep -q '^event: reload' "$LAB/events.log" \
  && fail "lavish-axi ${VERSION:-version-unknown} reloaded the open board when only the check stamp beside it changed; the footer's script-tag poll must be revisited"
pass "lavish-axi ${VERSION:-version-unknown} serves the check stamp fresh on every read without reloading the page"

curl -sN --max-time 20 "$base/events/$key" > "$LAB/events.log" 2>/dev/null &
EVENTS_PID=$!
sleep 1
jq '.captains_call[0].title = "Guard placeholder, rewritten"' "$LAB/payload.json" > "$LAB/payload-rewritten.json"
run_board publish "$LAB/payload-rewritten.json" >/dev/null 2>&1 || fail "the guard board did not republish"
i=0
while ! grep -q '^event: reload' "$LAB/events.log" 2>/dev/null && [ "$i" -lt 100 ]; do
  sleep 0.1
  i=$((i + 1))
done
kill "$EVENTS_PID" >/dev/null 2>&1 || true
wait "$EVENTS_PID" >/dev/null 2>&1 || true
EVENTS_PID=''
grep -q '^event: reload' "$LAB/events.log" \
  || fail "lavish-axi ${VERSION:-version-unknown} pushed no reload after an atomic board rewrite; the live board's refresh path must be revisited"
pass "lavish-axi ${VERSION:-version-unknown} reloads the open board after an atomic rewrite"
