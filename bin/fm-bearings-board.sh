#!/usr/bin/env bash
# fm-bearings-board.sh - publish, serve, and refresh the /bearings lavish fleet board.
#
# The board is the captain-facing interactive surface of the fleet: the shipped
# template (.agents/skills/bearings/assets/board-template.html) plus one injected
# fm-bearings-board.v1 JSON payload (contract: bin/fm-bearings-board-lib.sh).
# The payload is machine-derived by `bin/fm-bearings-snapshot.sh --board`, so no
# agent composes board copy at any point; this script owns the mechanics around
# that seam.
#
# Usage:
#   fm-bearings-board.sh build [<data.json>]
#   fm-bearings-board.sh publish <data.json>
#   fm-bearings-board.sh serve
#   fm-bearings-board.sh refresh [--best-effort | --detach]
#   fm-bearings-board.sh path
#
# publish    Validate the payload, drop the Captain's Call cards whose subject
#            already landed, give every surviving decision card the standard
#            reconcile choice, and inject the result into a fresh copy of the
#            shipped template at the stable board path, atomically. Prints
#            `board: <path>`. Never calls lavish-axi and never touches the
#            answer source: publishing is a file write, and a Lavish session
#            already open on that path reloads it on its own.
# serve      Establish the Lavish session on the published board and PROVE it
#            is live BEFORE binding and arming its answer source, so a
#            registered poll can never race a session that does not exist or
#            attach to one that has ended. Bind to the keyed-answer intake
#            (bin/fm-captain-hold.sh) ALWAYS precedes arm, so the board can
#            never produce an answer that has nowhere to go
#            (captain-hold-lifecycle's ordering rule, enforced here rather than
#            left to agent memory). Output is lavish-axi's session output and
#            the remaining status:
#              session: live | reopened
#              served: <path>
#              bound: <source-id>
#              armed: <source-id>            (first registration)
#              already-armed: <source-id>    (registration already present)
#              listening: <owner>            (only when a replacement was needed)
#            Refuses when no board is published.
# build      publish then serve, the captain-facing entry point of /bearings
#            lavish. With no payload argument it generates the payload itself
#            through `fm-bearings-snapshot.sh --board`; an explicit payload is
#            accepted for tests and diagnostics. Output starts with `board:`.
#            It records the digest and the check stamp of the payload it
#            published, so the watcher's next tick republishes nothing
#            identical and the page the captain just opened is not reloaded.
# refresh    Re-derive the payload and republish the board ONLY when the derived
#            payload changed (its `generated` stamp excluded), so an open page
#            reloads on real fleet change and never on the clock. Prints
#            `refreshed: <path>` or `unchanged: <digest>`. Refuses (exit 3)
#            when no board is published, because the board file is the
#            captain's opt-in; never calls lavish-axi, never binds or arms, and
#            never reopens a session the captain ended - `/bearings lavish`
#            (build) is the deliberate reopen. A concurrent refresh yields
#            (`busy:`) rather than racing, but first touches the pending
#            marker state/.bearings-board-refresh-pending beside the digest;
#            the lock holder checks that marker after its own publish, on the
#            refreshed and the unchanged paths alike, and when present clears
#            it and runs exactly one more generate-and-publish before
#            releasing the lock, so a change that arrives mid-refresh reaches
#            the board without waiting for the next cadence. Never a loop: a
#            marker touched during that follow-up run waits for the next
#            refresh. With --best-effort every failure,
#            including the missing board, is recorded in the bounded
#            state/.bearings-board-refresh.log and the exit status is 0, so no
#            call site can change its own result by calling it. With --detach
#            the best-effort refresh runs in a detached child (stdin from
#            /dev/null, stdout and stderr to /dev/null, failures only in that
#            log) and this command returns at once, which is how session
#            start, spawn, teardown, the PR check, and the captain-hold hooks
#            call it so none of them ever waits on a fleet snapshot; the
#            watcher tracks its own child instead. The generation is bounded
#            by FM_BOARD_REFRESH_TIMEOUT (default 60 s) inside the child.
#            The digest lives in state/.bearings-board-digest; its mtime is the
#            last-attempt stamp bin/fm-watch.sh's refresh cadence reads, and
#            every attempt, a failed one included, touches it, so a failing
#            generation is retried on FM_BOARD_REFRESH_INTERVAL and never on
#            every poll. Every attempt that derives a payload, changed or not,
#            also rewrites the sibling .lavish/bearings-board-checked.js, one
#            line of script carrying the epoch of that check, which the open
#            page loads on its own timer to show how recently the board was
#            verified current; a failed attempt leaves it alone so the footer
#            ages instead of reading current.
# path       Print the stable board path for this home.
#
# A LIVE SESSION IS PROVED, NEVER ASSUMED. `lavish-axi <file>` exits 0 even
# when it refuses to reopen a session the captain ended from the browser,
# reporting `status: user-ended` with the same session id, so exit status alone
# cannot tell a live board from a dead one. serve requires the server's fresh
# session listing to show the canonical board open and refuses rather than
# arming an ended session. After a reopen it retires the pre-reopen source
# generation through the guarded adapter path, arms a fresh registration, and
# accepts only the replacement listener as live. A registered board with no
# live owner also gets a replacement before serve returns, because
# `already-armed` is not the same fact as `listening`.
#
# CAPTAIN'S CALL HYGIENE. A decision card is dropped when its work item, PR, or
# structured artifact/version subject appears among the payload's own landed
# rows, or when `bin/fm-captain-hold.sh open` reports the task is no longer an
# open captain call. A newer published version also supersedes a version card.
# A task whose state cannot be established is kept, because a call wrongly
# hidden is worse than a card wrongly shown. Cleanup is therefore a normal
# publish effect rather than a committed migration or direct state mutation.
# refresh skips the per-card open probe: its payload was derived a moment
# earlier from the very backlog that probe reads, and the probe costs one
# tasks-axi read per card on every cadence tick.
#
# THE RECONCILE CHOICE. Every decision card carries the standard `reconcile`
# option, injected here so the guarantee does not depend on the generator, and
# the payload validator reserves that value across every card type. The
# validator's reservation scope must equal the adapter's reconcile
# classification scope, which is all card types because the captured payload
# carries no card type. Its meaning, and the reason it can never reach the
# keyed-answer intake as a blind close, are owned by
# docs/captain-hold-lifecycle.md.
#
# Validation is fail-closed on every publish: the payload must be valid JSON
# with schema=fm-bearings-board.v1 and every renderer-consumed field must
# satisfy the contract bin/fm-bearings-board-lib.sh owns. Anything else refuses
# before the existing board is touched.
#
# The board path is stable - $FM_HOME/.lavish/bearings-board.html - so a
# republish rewrites the same file in place, which keeps the same Lavish
# session URL and the same canonical process-event source id. Injection escapes
# every `<` in the compact JSON as the < string escape, so a payload string
# containing "</script>" can never terminate the data block early.
#
# FM_BEARINGS_BOARD_TEMPLATE overrides the shipped template path and
# FM_BEARINGS_BOARD_GENERATOR overrides the payload generator (tests only).
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-$FM_ROOT}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
# shellcheck source=bin/fm-bearings-board-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/fm-bearings-board-lib.sh"  # fm_bearings_board_validate: the payload contract
# shellcheck source=bin/fm-timeout-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/fm-timeout-lib.sh"  # fm_run_timed: the shared hard bound
# shellcheck source=bin/fm-wake-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/fm-wake-lib.sh"  # fm_lock_try_acquire / fm_lock_release

TEMPLATE="${FM_BEARINGS_BOARD_TEMPLATE:-$SCRIPT_DIR/../.agents/skills/bearings/assets/board-template.html}"
PLACEHOLDER='__FM_BEARINGS_BOARD_DATA__'
BOARD_SCHEMA=fm-bearings-board.v1

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

# Under a best-effort refresh a failure is recorded in the bounded refresh log
# and the exit status stays 0, so no call site's own result depends on it.
BEST_EFFORT=0
REFRESH_ATTEMPT=0
fail() {
  if [ "$REFRESH_ATTEMPT" -eq 1 ]; then
    touch "$REFRESH_DIGEST" 2>/dev/null || true
  fi
  if [ "$BEST_EFFORT" -eq 1 ]; then
    refresh_log_failure "$*"
    exit 0
  fi
  printf 'fm-bearings-board: %s\n' "$*" >&2
  exit 1
}

board_path() { printf '%s/.lavish/bearings-board.html\n' "$FM_HOME"; }
checked_path() { printf '%s/.lavish/bearings-board-checked.js\n' "$FM_HOME"; }

# The one-line sibling script the open page loads to learn when the board was
# last verified current. Written atomically beside the board, which Lavish
# serves fresh on every read and never treats as a page change.
write_checked_stamp() {
  local path tmp
  path=$(checked_path)
  tmp=$(umask 077; mktemp "${path%/*}/.checked.XXXXXX") || return 1
  if ! printf 'window.__fmBoardChecked && window.__fmBoardChecked({checked: %s});\n' "$(date +%s)" > "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if ! { chmod 0600 "$tmp" && mv -f -- "$tmp" "$path"; }; then
    rm -f -- "$tmp"
    return 1
  fi
}

record_digest() {  # <digest>
  local tmp
  mkdir -p "$STATE" 2>/dev/null || return 1
  tmp=$(umask 077; mktemp "$STATE/.bearings-board-digest.XXXXXX") || return 1
  if ! { printf '%s\n' "$1" > "$tmp" && mv -f -- "$tmp" "$REFRESH_DIGEST"; }; then
    rm -f -- "$tmp"
    return 1
  fi
}

validate_payload() {  # <data.json>
  fm_bearings_board_validate "$1"
}

# --- Lavish session liveness -------------------------------------------------
# Verified against lavish-axi 0.1.61. `lavish-axi <file>` EXITS 0 even when it
# refuses to reopen a session the captain ended from the browser, reporting
# `status: user-ended` and the same session id, so an exit-code check alone
# cannot tell a live board from a dead one. The establish status is an initial
# signal only; the server's fresh session listing must also show the canonical
# board open before the build may bind or arm its source.

board_realpath() {  # <board>
  perl -MCwd=realpath -e '$p = realpath($ARGV[0]); defined($p) or exit 1; print "$p\n"' "$1" 2>/dev/null
}

lavish_status_field() {  # <lavish-axi output>
  printf '%s\n' "$1" | sed -n 's/^[[:space:]]*status:[[:space:]]*//p' | head -1 | tr -d '"'
}

# The server's own listing, keyed on the canonical artifact path. Rows are
# `<file>,<status>,"<url>",<pending>`, and only a live session is listed `open`.
lavish_session_listed_open() {  # <canonical-board-path>
  local listing
  listing=$(lavish-axi 2>/dev/null) || return 1
  printf '%s\n' "$listing" | awk -v path="$1" '
    { line = $0; sub(/^[[:space:]]+/, "", line) }
    index(line, path ",") == 1 {
      rest = substr(line, length(path) + 2)
      split(rest, field, ",")
      if (field[1] == "open") { found = 1 }
    }
    END { exit found ? 0 : 1 }
  '
}

lavish_board_live() {  # <establish output> <canonical-board-path>
  lavish_session_listed_open "$2"
}

# Establish the board session and PROVE it is live before anything arms a poll
# on it. A session the captain ended is reopened once - the captain asked for
# this board, which is exactly the attention `--reopen` exists for - and a
# session that is still not live after that refuses the build rather than
# arming a poll that can never attach.
establish_board_session() {  # <board>
  local board=$1 real out status version
  BOARD_SESSION_REOPENED=0
  real=$(board_realpath "$board") || fail "cannot resolve the board path: $board"
  out=$(lavish-axi "$board") || fail "cannot establish the board Lavish session"
  printf '%s\n' "$out"
  if lavish_board_live "$out" "$real"; then
    printf 'session: live\n'
    return 0
  fi
  out=$(lavish-axi "$board" --reopen) || fail "cannot reopen the ended board Lavish session"
  printf '%s\n' "$out"
  if lavish_board_live "$out" "$real"; then
    BOARD_SESSION_REOPENED=1
    printf 'session: reopened\n'
    return 0
  fi
  status=$(lavish_status_field "$out")
  version=$(lavish-axi --version 2>/dev/null | tr -d '[:space:]')
  fail "the board Lavish session is not live after reopening it (lavish-axi ${version:-version-unknown} reported status ${status:-none}); refusing to arm a poll on an ended session"
}

# --- Captain's Call hygiene ---------------------------------------------------
# A held decision whose subject already shipped is not a live call, so it is
# dropped here instead of being carded again. All checks use exact structured
# identities; unknown subject state keeps the card.

decision_card_is_stale() {  # <task-id> <landed-0-or-1>
  local task=$1 landed=$2 rc=0
  if [ "$landed" = 1 ]; then
    printf 'structured subject already landed\n'
    return 0
  fi
  # refresh derived this payload from the backlog a moment ago; see the header.
  [ "${BOARD_STALE_PROBE:-1}" = 1 ] || return 1
  "$SCRIPT_DIR/fm-captain-hold.sh" open "$task" --distinguish-absent >/dev/null 2>&1 || rc=$?
  # 1 is a definite "no longer an open captain call". 2 is "cannot tell", 3 is
  # absent from this backlog, and a call wrongly hidden is worse than a card
  # wrongly shown, so both uncertain and absent cards stay.
  if [ "$rc" -eq 1 ]; then
    printf 'no longer an open captain call\n'
    return 0
  fi
  return 1
}

# Drop every stale decision card, then give every surviving decision card the
# standard reconcile choice. Injecting it here is what makes "every decision
# card offers reconcile" a property of the board rather than of the composer's
# memory; the validator prevents duplicate decision options.
effective_payload() {  # <data.json> <dest.json>
  local data=$1 dest=$2 landed_keys key reason drop='' tmp landed=0
  landed_keys=$(jq -c '
    def version_parts: split(".") | map(tonumber);
    . as $payload
    | [$payload.captains_call[]
      | select(.type == "decision")
      | . as $card
      | select(
          ($payload.landed | any(.id == $card.key))
          or (($card.pr_url? != null) and ($payload.landed | any(.pr_url? == $card.pr_url)))
          or (($card.subject? != null) and ($payload.landed | any(
            (.subject? != null)
            and (.subject.artifact == $card.subject.artifact)
            and ((.subject.version | version_parts) >= ($card.subject.version | version_parts)))))
        )
      | .key]
  ' "$data") || return 1
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    landed=0
    if jq -e --arg key "$key" 'index($key) != null' <<< "$landed_keys" >/dev/null; then
      landed=1
    fi
    reason=$(decision_card_is_stale "$key" "$landed") || continue
    printf 'dropped-landed-card: %s (%s)\n' "$key" "$reason" >&2
    drop=$drop$key$'\n'
  done < <(jq -r '.captains_call[]? | select(.type == "decision") | .key' "$data")
  tmp=$(printf '%s' "$drop" | jq -R -s 'split("\n") | map(select(length > 0))') || return 1
  jq --argjson dropped "$tmp" '
    .captains_call = [
      .captains_call[]
      | . as $card
      | select($card.type != "decision" or (($dropped | index($card.key)) == null))
      | if .type == "decision"
        then .options += [{
          value: "reconcile",
          label: "Reconcile",
          hint: "Re-check the latest state, then close this with evidence or keep it open with a note"
        }]
        else . end
    ]' "$data" > "$dest" || return 1
}

# The OWNER column bin/fm-procevent.sh already publishes: live, none,
# orphaned, or uncertain. Empty means the source is not registered at all.
source_owner() {  # <source-id>
  "$SCRIPT_DIR/fm-procevent.sh" list 2>/dev/null \
    | awk -v id="$1" 'NR > 1 && $1 == id { print $3 }'
}

# A replacement listener is started detached, so it claims the source shortly
# after reconcile returns. Wait for that claim rather than reporting the race.
await_source_owner() {  # <source-id>
  local owner i=0
  while [ "$i" -lt 50 ]; do
    owner=$(source_owner "$1")
    [ "$owner" != live ] || { printf '%s\n' "$owner"; return 0; }
    sleep 0.1
    i=$((i + 1))
  done
  printf '%s\n' "${owner:-none}"
}

GENERATOR="${FM_BEARINGS_BOARD_GENERATOR:-$SCRIPT_DIR/fm-bearings-snapshot.sh}"

generate_payload() {  # <dest.json>
  "$GENERATOR" --board > "$1"
}

publish_board() {  # <data.json>
  local data=$1 board json tmp extracted effective
  command -v jq >/dev/null 2>&1 || fail "jq is required"
  [ -f "$data" ] || fail "board data does not exist: $data"
  jq empty "$data" 2>/dev/null || fail "board data is not valid JSON: $data"
  validate_payload "$data" || fail "board data does not satisfy $BOARD_SCHEMA: $data"
  [ -f "$TEMPLATE" ] && [ ! -L "$TEMPLATE" ] || fail "board template is missing: $TEMPLATE"
  [ "$(grep -cxF "$PLACEHOLDER" "$TEMPLATE")" -eq 1 ] \
    || fail "board template does not carry exactly one data slot: $TEMPLATE"

  effective=$(umask 077; mktemp "${TMPDIR:-/tmp}/fm-bearings-payload.XXXXXX") \
    || fail "cannot stage the board payload"
  if ! effective_payload "$data" "$effective"; then
    rm -f -- "$effective"
    fail "cannot reconcile the board payload against landed work"
  fi
  json=$(jq -c . "$effective") || { rm -f -- "$effective"; fail "cannot compact the board data"; }
  rm -f -- "$effective"
  # `<` never appears in JSON syntax outside strings, so escaping every
  # occurrence keeps the payload valid JSON while making </script> inert.
  json=${json//</\\u003c}

  board=$(board_path)
  (umask 077; mkdir -p "${board%/*}") || fail "cannot create ${board%/*}"
  tmp=$(umask 077; mktemp "${board%/*}/.board.XXXXXX") || fail "cannot stage the board"
  if ! BOARD_JSON="$json" perl -pe "s/^\\Q$PLACEHOLDER\\E\$/\$ENV{BOARD_JSON}/" "$TEMPLATE" > "$tmp"; then
    rm -f -- "$tmp"
    fail "cannot inject the board data"
  fi
  if grep -qxF "$PLACEHOLDER" "$tmp"; then
    rm -f -- "$tmp"
    fail "the board data slot survived injection"
  fi
  # Round-trip the injected payload back out of the built page, so a board that
  # would fail to parse in the browser fails here instead.
  extracted=$(sed -n '/<script id="bearings-data" type="application\/json">/,/<\/script>/p' "$tmp" \
    | sed '1d;$d')
  if ! printf '%s\n' "$extracted" | jq -e --arg schema "$BOARD_SCHEMA" '.schema == $schema' >/dev/null 2>&1; then
    rm -f -- "$tmp"
    fail "the built board does not carry a readable $BOARD_SCHEMA payload"
  fi
  if ! { chmod 0600 "$tmp" && mv -f -- "$tmp" "$board"; }; then
    rm -f -- "$tmp"
    fail "cannot publish the board"
  fi
  printf 'board: %s\n' "$board"
}

serve_board() {
  local board sid owner version pre_reopen_owner
  board=$(board_path)
  [ -f "$board" ] && [ ! -L "$board" ] || fail "no board is published at $board; run build first"
  command -v lavish-axi >/dev/null 2>&1 || fail "lavish-axi is not installed"
  sid=$("$SCRIPT_DIR/fm-procevent-lavish.sh" source-id "$board") \
    || fail "cannot derive the board source id"
  pre_reopen_owner=$(source_owner "$sid")
  establish_board_session "$board"
  if [ "$BOARD_SESSION_REOPENED" = 1 ]; then
    "$SCRIPT_DIR/fm-procevent-lavish.sh" retire "$board" >/dev/null \
      || fail "cannot retire the pre-reopen source generation (observed owner: ${pre_reopen_owner:-none})"
  fi
  if ! lavish_session_listed_open "$(board_realpath "$board")"; then
    version=$(lavish-axi --version 2>/dev/null | tr -d '[:space:]')
    fail "the board Lavish session is not listed open immediately before arming (lavish-axi ${version:-version-unknown}); refusing to arm a poll on observed state not-open"
  fi
  printf 'served: %s\n' "$board"

  "$SCRIPT_DIR/fm-captain-hold.sh" bind "$sid" >/dev/null \
    || fail "cannot bind the board source to the keyed-answer intake"
  printf 'bound: %s\n' "$sid"

  owner=$(source_owner "$sid")
  if [ "$BOARD_SESSION_REOPENED" = 1 ]; then
    "$SCRIPT_DIR/fm-procevent-lavish.sh" arm "$board" >/dev/null \
      || fail "cannot arm a fresh board source after reopening"
    printf 'armed: %s\n' "$sid"
    owner=$(source_owner "$sid")
  elif [ -n "$owner" ]; then
    printf 'already-armed: %s\n' "$sid"
  else
    "$SCRIPT_DIR/fm-procevent-lavish.sh" arm "$board" >/dev/null \
      || fail "cannot arm the board as a process-event source"
    printf 'armed: %s\n' "$sid"
    owner=$(source_owner "$sid")
  fi
  # Registered is not listening. A board whose source has no live owner gets a
  # replacement started now rather than at the next supervision cycle, which is
  # what keeps a rebuilt board from sitting silent behind `already-armed`.
  if [ "$owner" != live ]; then
    "$SCRIPT_DIR/fm-procevent.sh" reconcile >/dev/null 2>&1 || true
    owner=$(await_source_owner "$sid")
    if [ "$owner" != live ]; then
      fail "source $sid is not listening after reconcile (observed owner: ${owner:-none})"
    fi
    printf 'listening: live\n'
  fi
}

GENERATED_PAYLOAD=
cleanup_generated_payload() {
  [ -z "$GENERATED_PAYLOAD" ] || rm -f -- "$GENERATED_PAYLOAD"
}

command_build() {
  local data=${1-} digest
  [ "$#" -le 1 ] || { usage >&2; exit 2; }
  if [ -z "$data" ]; then
    GENERATED_PAYLOAD=$(umask 077; mktemp "${TMPDIR:-/tmp}/fm-bearings-board-gen.XXXXXX") \
      || fail "cannot stage the generated board payload"
    trap cleanup_generated_payload EXIT
    generate_payload "$GENERATED_PAYLOAD" || fail "cannot generate the board payload"
    data=$GENERATED_PAYLOAD
  fi
  publish_board "$data"
  digest=$(payload_digest "$data") || fail "cannot digest the published board payload"
  record_digest "$digest" || fail "cannot record the board digest"
  write_checked_stamp || fail "cannot record the board check stamp"
  serve_board
}

command_publish() {
  [ "$#" -eq 1 ] || { usage >&2; exit 2; }
  publish_board "$1"
}

command_serve() {
  [ "$#" -eq 0 ] || { usage >&2; exit 2; }
  serve_board
}

# --- refresh -----------------------------------------------------------------
REFRESH_TIMEOUT=${FM_BOARD_REFRESH_TIMEOUT:-60}
case "$REFRESH_TIMEOUT" in ''|*[!0-9]*|0) REFRESH_TIMEOUT=60 ;; esac
REFRESH_LOG_MAX_BYTES=${FM_BOARD_REFRESH_LOG_MAX_BYTES:-65536}
case "$REFRESH_LOG_MAX_BYTES" in ''|*[!0-9]*|0) REFRESH_LOG_MAX_BYTES=65536 ;; esac
REFRESH_DIGEST="$STATE/.bearings-board-digest"
REFRESH_LOG="$STATE/.bearings-board-refresh.log"
REFRESH_LOCK="$STATE/.bearings-board-refresh.lock"
REFRESH_PENDING="$STATE/.bearings-board-refresh-pending"
REFRESH_LOCK_HELD=0
REFRESH_TMP=

refresh_log_failure() {  # <message>
  local size tmp
  if ! printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$REFRESH_LOG" 2>/dev/null; then
    printf 'fm-bearings-board: %s\n' "$1" >&2
    return 0
  fi
  size=$(wc -c < "$REFRESH_LOG" 2>/dev/null | tr -d '[:space:]')
  case "$size" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$size" -ge "$REFRESH_LOG_MAX_BYTES" ]; then
    tmp="$REFRESH_LOG.tmp.${BASHPID:-$$}"
    tail -n 200 "$REFRESH_LOG" > "$tmp" 2>/dev/null && mv -f -- "$tmp" "$REFRESH_LOG" 2>/dev/null
    rm -f -- "$tmp" 2>/dev/null || true
  fi
}

refresh_cleanup() {
  [ -z "$REFRESH_TMP" ] || rm -f -- "$REFRESH_TMP" "$REFRESH_TMP.err" 2>/dev/null || true
  if [ "$REFRESH_LOCK_HELD" -eq 1 ]; then
    fm_lock_release "$REFRESH_LOCK" || true
    REFRESH_LOCK_HELD=0
  fi
}

payload_digest() {  # <payload.json>; the generated stamp is not a change
  local canonical
  canonical=$(jq -S 'del(.generated)' "$1") || return 1
  if command -v shasum >/dev/null 2>&1; then
    printf '%s\n' "$canonical" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s\n' "$canonical" | sha256sum | awk '{print $1}'
  fi
}

command_refresh() {
  local best_effort=0 detach=0 arg board
  for arg in "$@"; do
    case "$arg" in
      --best-effort) best_effort=1 ;;
      --detach) detach=1; best_effort=1 ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  board=$(board_path)
  if [ ! -f "$board" ] || [ -L "$board" ]; then
    [ "$best_effort" -eq 0 ] || exit 0
    printf 'fm-bearings-board: no board is published for this home; run build first\n' >&2
    exit 3
  fi
  if [ "$detach" -eq 1 ]; then
    "$SCRIPT_DIR/fm-bearings-board.sh" refresh --best-effort </dev/null >/dev/null 2>&1 &
    exit 0
  fi
  # From here every failure is a refresh failure: logged and swallowed under
  # --best-effort, reported otherwise, and always stamped on the digest so the
  # watcher's cadence sees the attempt.
  BEST_EFFORT=$best_effort
  mkdir -p "$STATE" 2>/dev/null || fail "state directory is unavailable: $STATE"
  trap refresh_cleanup EXIT
  if ! fm_lock_try_acquire "$REFRESH_LOCK"; then
    touch "$REFRESH_PENDING" 2>/dev/null || true
    printf 'busy: another refresh holds %s\n' "$REFRESH_LOCK"
    exit 0
  fi
  REFRESH_LOCK_HELD=1
  REFRESH_ATTEMPT=1
  REFRESH_TMP=$(umask 077; mktemp "$STATE/.bearings-board-payload.XXXXXX") \
    || fail "cannot stage the refreshed board payload"
  refresh_once "$board"
  if [ -e "$REFRESH_PENDING" ]; then
    rm -f -- "$REFRESH_PENDING"
    refresh_once "$board"
  fi
}

refresh_once() {  # <board>; generate, compare, and publish one derived payload
  local board=$1 rc=0 digest previous
  fm_run_timed "$REFRESH_TIMEOUT" "$GENERATOR" --board \
    > "$REFRESH_TMP" 2> "$REFRESH_TMP.err" || rc=$?
  if [ "$rc" -eq 124 ]; then
    fail "board payload generation exceeded its ${REFRESH_TIMEOUT}-second deadline"
  elif [ "$rc" -ne 0 ]; then
    fail "board payload generation failed with exit $rc: $(tail -n 1 "$REFRESH_TMP.err" 2>/dev/null | cut -c1-500)"
  fi
  digest=$(payload_digest "$REFRESH_TMP") || fail "cannot digest the refreshed board payload"
  previous=$(cat "$REFRESH_DIGEST" 2>/dev/null || true)
  if [ "$digest" = "$previous" ]; then
    touch "$REFRESH_DIGEST" 2>/dev/null || true
    write_checked_stamp || fail "cannot record the board check stamp"
    printf 'unchanged: %s\n' "$digest"
    return 0
  fi
  BOARD_STALE_PROBE=0 publish_board "$REFRESH_TMP" >/dev/null
  record_digest "$digest" || fail "cannot record the board digest"
  write_checked_stamp || fail "cannot record the board check stamp"
  printf 'refreshed: %s\n' "$board"
}

case "${1-}" in
  build) shift; command_build "$@" ;;
  publish) shift; command_publish "$@" ;;
  serve) shift; command_serve "$@" ;;
  refresh) shift; command_refresh "$@" ;;
  path) board_path ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
