#!/usr/bin/env bash
# Behavior tests for bin/fm-bearings-board.sh: fail-closed payload validation,
# slot-injection round-trip through the built page, bind-before-arm, and
# idempotent re-arm of the stable board source.
set -u

# shellcheck source=tests/lib.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BOARD="$ROOT/bin/fm-bearings-board.sh"
TMP_ROOT=$(fm_test_tmproot fm-bearings-board)

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }

# A lavish-axi stub that reproduces the shapes verified against the real
# lavish-axi 0.1.61, because the build's liveness verdict is read from what the
# vendor emits. The load-bearing shape is the refusal: opening a session the
# captain ended from the browser EXITS 0 while reporting `status: user-ended`,
# and that session is absent from the server's listing. `--reopen` restores it.
# Markers under lavish-state drive the fixture: `user-ended` makes the next
# plain open refuse, and `refuse-reopen` makes even --reopen leave it dead.
make_home() {  # <name>
  local home="$TMP_ROOT/$1" fakebin
  # Registered with tests/lib.sh, not with a shell array: make_home is called
  # inside a command substitution, so an array append here never reaches the
  # caller and every listener this suite started used to survive the run.
  fm_test_track_procevent_home "$home" "$home/procevent-claims"
  mkdir -p "$home/state" "$home/data" "$home/lavish-state"
  fakebin=$(fm_fakebin "$home")
  cat > "$fakebin/lavish-axi" <<'SH'
#!/usr/bin/env bash
set -u
state=${LAVISH_FAKE_STATE:?}
emit() {  # <canonical-file> <status>
  printf 'session:\n'
  printf '  file: %s\n' "$1"
  printf '  url: "http://127.0.0.1:4387/session/deadbeef"\n'
  printf '  status: %s\n' "$2"
}
case "${1-}" in
  --version) printf '0.1.61\n'; exit 0 ;;
  poll)
    # A real blocking listener: it returns only when the trigger appears, so a
    # live owner in these tests is a live process rather than a timing artifact.
    # Both waits are bounded, so a listener that escapes its test cannot keep
    # spawning processes for as long as the host stays up.
    limit=${FM_TEST_STUB_MAX_BLOCK_SECONDS:-120}
    while [ ! -e "$state/poll-trigger" ]; do
      [ "$SECONDS" -lt "$limit" ] || exit 75
      sleep 0.05
    done
    printf 'session:\n  status: ended\n'
    if [ -e "$state/hold-after-terminal" ]; then
      : > "$state/terminal-emitted"
      while [ -e "$state/hold-after-terminal" ]; do
        [ "$SECONDS" -lt "$limit" ] || exit 75
        sleep 0.05
      done
    fi
    exit 0
    ;;
  '')
    if [ -e "$state/end-before-next-list" ]; then
      : > "$state/open"
      rm -f "$state/end-before-next-list"
    fi
    printf 'sessions[1]{file,status,url,pending_prompts}:\n'
    if [ -s "$state/open" ]; then
      while IFS= read -r listed; do
        [ -n "$listed" ] || continue
        printf '  %s,open,"http://127.0.0.1:4387/session/deadbeef",0\n' "$listed"
      done < "$state/open"
    fi
    exit 0
    ;;
  end) : > "$state/open"; printf 'session:\n  status: ended\n'; exit 0 ;;
esac
file=$1
shift
reopen=0
for arg in "$@"; do [ "$arg" != --reopen ] || reopen=1; done
real=$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")
if [ -e "$state/user-ended" ] && [ "$reopen" = 0 ]; then
  emit "$real" user-ended
  exit 0
fi
if [ -e "$state/refuse-reopen" ]; then
  emit "$real" user-ended
  exit 0
fi
rm -f -- "$state/user-ended"
printf '%s\n' "$real" > "$state/open"
emit "$real" opened
exit 0
SH
  chmod +x "$fakebin/lavish-axi"
  printf '%s\n' "$home"
}

end_session_as_captain() { : > "$1/lavish-state/user-ended"; : > "$1/lavish-state/open"; }

run_board() {  # <home> <args...>
  local home=$1
  shift
  PATH="$home/fakebin:$PATH" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROCEVENT_CLAIM_ROOT="$home/procevent-claims" \
    LAVISH_FAKE_STATE="$home/lavish-state" \
    "$BOARD" "$@"
}

run_procevent() {  # <home> <command args...>
  local home=$1
  shift
  PATH="$home/fakebin:$PATH" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROCEVENT_CLAIM_ROOT="$home/procevent-claims" \
    "$ROOT/bin/fm-procevent.sh" "$@"
}

run_decisions() {  # <home> <command args...>
  local home=$1
  shift
  PATH="$home/fakebin:$PATH" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    "$ROOT/bin/fm-captain-hold.sh" "$@"
}

# A realistic payload: a cross-origin full-identity decision key past the old
# 64-char cap, a merge card, a dispatchable charted row, and a string that
# tries to terminate the data block early.
write_valid_payload() {  # <path>
  cat > "$1" <<'EOF'
{
  "schema": "fm-bearings-board.v1",
  "home": "test-home",
  "generated": "2026-08-19T00:00Z",
  "prs_live": false,
  "captains_call": [
    {
      "key": "sample-instruction-layer-refinement-review-decision-perishable-first-admission-choice",
      "type": "decision",
      "repo": "sample",
      "title": "Perishable-first admission",
      "about": "A payload string that tries to break out: </script><b>x</b>",
      "decide": "Adopt it?",
      "options": [
        { "value": "yes", "label": "Adopt", "hint": "recommended" },
        { "value": "no", "label": "Keep current" }
      ],
      "allow_freeform": true
    },
    {
      "key": "merge.sample-task",
      "type": "merge",
      "repo": "sample",
      "title": "Merge: sample change",
      "detail": "validation green",
      "task_id": "sample-task",
      "pr_url": "https://github.com/example/sample/pull/1",
      "checks": "green",
      "risk": "low",
      "options": [
        { "value": "merge", "label": "Merge now" },
        { "value": "hold", "label": "Not yet" }
      ],
      "allow_freeform": true
    }
  ],
  "underway": [],
  "landed": [],
  "charted": [
    { "id": "sample-queued", "repo": "sample", "title": "Queued work", "reason": "", "dispatchable": true }
  ],
  "charted_more": 0
}
EOF
}

# Extract the injected payload back out of a built board page.
extract_payload() {  # <board-path>
  sed -n '/<script id="bearings-data" type="application\/json">/,/<\/script>/p' "$1" \
    | sed '1d;$d'
}

test_path_is_stable_and_home_scoped() {
  local home
  home=$(make_home path)
  [ "$(run_board "$home" path)" = "$home/.lavish/bearings-board.html" ] \
    || fail "the board path is not the stable home-scoped location"
  pass "path prints the stable home-scoped board location"
}

test_build_refuses_malformed_payloads_before_touching_the_board() {
  local home data board rc out
  home=$(make_home refusal)
  board="$home/.lavish/bearings-board.html"
  data="$home/payload.json"

  printf 'not json\n' > "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a non-JSON payload was accepted"
  assert_contains "$out" "not valid JSON" "the non-JSON refusal did not say why: $out"

  printf '{"schema":"fm-bearings-board.v2"}\n' > "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a wrong-schema payload was accepted"
  assert_contains "$out" "fm-bearings-board.v1" "the schema refusal did not name the contract: $out"

  write_valid_payload "$data"
  jq '.captains_call[0].key = (reduce range(129) as $i (""; . + "x"))' "$data" > "$data.tmp" \
    && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a 129-char captains_call key was accepted"

  write_valid_payload "$data"
  jq 'del(.charted[0].dispatchable)' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a charted row without a dispatchable boolean was accepted"

  write_valid_payload "$data"
  jq '.charted[0].kind = "alarm"' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "an unknown charted kind was accepted"

  write_valid_payload "$data"
  jq '.charted[0].kind = "warning"' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a dispatchable warning row was accepted"

  write_valid_payload "$data"
  jq '.charted_warning_more = -1' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a negative omitted-warning count was accepted"

  write_valid_payload "$data"
  jq '.captains_call[0].subject = {"artifact":"quota-axi","version":"0.1"}' "$data" > "$data.tmp" \
    && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "an invalid structured version subject was accepted"

  write_valid_payload "$data"
  jq '.captains_call[0].type = "verdict"' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "an unknown captains_call type was accepted"

  write_valid_payload "$data"
  jq 'del(.captains_call[0].options[0].value)' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a captains_call option without an answer value was accepted"

  write_valid_payload "$data"
  jq '.captains_call[0].options[0].label = ""' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a captains_call option with an empty label was accepted"

  write_valid_payload "$data"
  jq 'del(.charted[0].repo)' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a fleet row without an explicit repo marker was accepted"

  write_valid_payload "$data"
  jq '.underway = [{"id":"sample-task","repo":"sample","state":"working",
    "kind":"ship","doing":"implementing"}]' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "an underway row without an explicit name marker was accepted"

  for invalid_filed in "last Tuesday" "2026-13-01" "2026-08-14T99:30:00Z" "2026-02-29"; do
    write_valid_payload "$data"
    jq --arg filed "$invalid_filed" '.charted[0].filed = $filed' "$data" > "$data.tmp" \
      && mv "$data.tmp" "$data"
    set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
    [ "$rc" -ne 0 ] || fail "an invalid filed date was accepted: $invalid_filed"
  done

  write_valid_payload "$data"
  jq '.captains_call[0].allow_freeform = "yes"' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a non-boolean renderer field was accepted"

  write_valid_payload "$data"
  jq '.captains_call[0].options = [] | .captains_call[0].allow_freeform = false' "$data" > "$data.tmp" \
    && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "an unanswerable captains_call item was accepted"

  write_valid_payload "$data"
  jq '.captains_call[1].pr_url = "javascript:alert(1)"' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a non-HTTPS Captain’s Call PR URL was accepted"

  write_valid_payload "$data"
  jq '.landed = [{
    "id": "sample-landed",
    "repo": "sample",
    "what": "Landed work",
    "owner": "firstmate",
    "pr_url": "data:text/html,unsafe"
  }]' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e; out=$(run_board "$home" build "$data" 2>&1); rc=$?; set -e
  [ "$rc" -ne 0 ] || fail "a non-HTTPS Landed PR URL was accepted"

  assert_absent "$board" "a refused payload still produced a board"
  pass "build refuses malformed payloads before touching the board"
}

test_build_injects_binds_then_arms() {
  local home data board out sid
  home=$(make_home build)
  data="$home/payload.json"
  board="$home/.lavish/bearings-board.html"
  write_valid_payload "$data"

  out=$(run_board "$home" build "$data") || fail "a valid payload did not build"
  assert_contains "$out" "board: $board" "build did not report the board path: $out"
  assert_contains "$out" "served: $board" "build did not establish the Lavish session: $out"
  assert_contains "$out" "bound: " "build did not report the answer binding: $out"
  assert_contains "$out" "armed: " "the first build did not arm the board source: $out"
  assert_present "$board" "build reported success without a board"

  # Round-trip: apart from the reconcile choice the build adds to every
  # decision card, the payload extracted from the built page is the same JSON
  # document, and the escaped </script> string can no longer terminate the
  # data block.
  extract_payload "$board" | jq -S . > "$home/extracted.json" \
    || fail "the built board does not carry parseable payload JSON"
  jq -S '.captains_call = [.captains_call[]
      | .options = [.options[] | select(.value != "reconcile")]]' \
    "$home/extracted.json" > "$home/stripped.json"
  jq -S '.captains_call = [.captains_call[]
      | .options = [.options[] | select(.value != "reconcile")]]' \
    "$data" > "$home/expected.json"
  diff -u "$home/expected.json" "$home/stripped.json" >/dev/null \
    || fail "the injected payload does not round-trip to the input document"
  grep -qF '</script><b>' "$board" \
    && fail "a payload string embedded a live closing script tag in the page"
  grep -qxF '__FM_BEARINGS_BOARD_DATA__' "$board" \
    && fail "the data slot survived injection"

  sid=$(run_lavish_source_id "$home" "$board")
  assert_contains "$out" "bound: $sid" "the binding does not name the board source: $out"
  [ "$(run_decisions "$home" binding "$sid")" = "(any)" ] \
    || fail "the board source is not bound any-origin"
  run_procevent "$home" list | awk 'NR > 1 { print $1 }' | grep -Fxq "$sid" \
    || fail "the board source is not registered after build"
  pass "build injects the payload, binds any-origin, then arms the source"
}

test_registration_cannot_consume_before_any_origin_binding() {
  local home data runtime origin key hold board sid show
  home=$(make_home order-proof)
  data="$home/payload.json"
  runtime="$home/runtime"
  origin=order-proof-review
  key=captain-choice
  hold="$origin-decision-$key"
  board="$home/.lavish/bearings-board.html"

  cp "$ROOT/.tasks.toml" "$home/.tasks.toml"
  cat > "$home/data/backlog.md" <<'EOF'
## In flight

## Queued

## Done
EOF
  fm_write_meta "$home/state/$origin.meta" "project=$home/projects/sample" "kind=scout"
  run_decisions "$home" hold "$hold" --origin "$origin" \
    --title "Choose the order proof" --reason "captain choice pending" --repo sample >/dev/null \
    || fail "could not create the order-proof captain hold"

  write_valid_payload "$data"
  jq --arg hold "$hold" '.captains_call[0].key = $hold' "$data" > "$data.tmp" \
    && mv "$data.tmp" "$data"

  mkdir -p "$runtime"
  cp -R "$ROOT/bin" "$runtime/bin"
  cat > "$runtime/bin/fm-procevent-lavish.sh" <<'SH'
#!/usr/bin/env bash
set -eu
if [ "${1:-}" = arm ]; then
  artifact=${2:-}
  "$REAL_LAVISH_ADAPTER" arm "$artifact" >/dev/null
  sid=$("$REAL_LAVISH_ADAPTER" source-id "$artifact")
  "$REAL_PROCEVENT" start "$sid" >/dev/null
  exit 0
fi
exec "$REAL_LAVISH_ADAPTER" "$@"
SH
  chmod +x "$runtime/bin/fm-procevent-lavish.sh"
  cat > "$home/fakebin/lavish-axi" <<'SH'
#!/usr/bin/env bash
if [ -z "${1:-}" ]; then
  printf 'sessions[1]{file,status,url,pending_prompts}:\n'
  [ ! -s "$FM_HOME/order-open" ] \
    || printf '  %s,open,"http://127.0.0.1/session/order",0\n' "$(cat "$FM_HOME/order-open")"
  exit 0
fi
if [ "${1:-}" != poll ]; then
  real=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
  printf '%s\n' "$real" > "$FM_HOME/order-open"
  printf 'session:\n  status: opened\n'
  exit 0
fi
cat <<EOF
session:
  status: feedback
  session_ended: false
prompts[1]{uid,prompt,selector,tag,text}:
  "2","Order proof: yes\\n\\nContext data:\\n{\\n  \\"schema\\": \\"fm-bearings-answer.v1\\",\\n  \\"question\\": \\"$ORDER_PROOF_HOLD\\",\\n  \\"selection\\": \\"yes\\",\\n  \\"note\\": \\"\\"\\n}","form",choice,"Order proof: yes"
EOF
SH
  chmod +x "$home/fakebin/lavish-axi"

  PATH="$home/fakebin:$PATH" FM_ROOT_OVERRIDE="$runtime" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROCEVENT_CLAIM_ROOT="$home/procevent-claims" \
    FM_BEARINGS_BOARD_TEMPLATE="$ROOT/.agents/skills/bearings/assets/board-template.html" \
    REAL_LAVISH_ADAPTER="$ROOT/bin/fm-procevent-lavish.sh" \
    REAL_PROCEVENT="$ROOT/bin/fm-procevent.sh" ORDER_PROOF_HOLD="$hold" \
    "$runtime/bin/fm-bearings-board.sh" build "$data" >/dev/null \
    || fail "the order-proof board build failed"

  show=$(cd "$home" && tasks-axi show "$hold" --full) \
    || fail "the order-proof captain hold disappeared"
  assert_contains "$show" "state: done" \
    "registration consumed its answer before the any-origin binding existed"
  assert_contains "$show" "Resolution mode: answered" \
    "the answer was not closed through the real keyed-answer intake"
  sid=$(run_lavish_source_id "$home" "$board")
  [ "$(run_decisions "$home" binding "$sid")" = "(any)" ] \
    || fail "the order-proof source did not retain its any-origin binding"
  pass "registration can consume answers only after any-origin binding exists"
}

test_build_does_not_bind_or_arm_when_session_start_fails() {
  local home data rc sid
  home=$(make_home serve-failure)
  data="$home/payload.json"
  write_valid_payload "$data"
  cat > "$home/fakebin/lavish-axi" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$home/fakebin/lavish-axi"

  set +e
  run_board "$home" build "$data" >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "build continued after Lavish session establishment failed"
  sid=$(run_lavish_source_id "$home" "$home/.lavish/bearings-board.html")
  ! run_decisions "$home" binding "$sid" >/dev/null 2>&1 \
    || fail "build bound the board before its Lavish session existed"
  ! run_procevent "$home" list | awk 'NR > 1 { print $1 }' | grep -Fxq "$sid" \
    || fail "build armed the board before its Lavish session existed"
  pass "build establishes the Lavish session before binding and arming"
}

run_lavish_source_id() {  # <home> <artifact>
  local home=$1
  PATH="$home/fakebin:$PATH" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROCEVENT_CLAIM_ROOT="$home/procevent-claims" \
    "$ROOT/bin/fm-procevent-lavish.sh" source-id "$2"
}

test_rebuild_is_idempotent_and_does_not_double_arm() {
  local home data board out records
  home=$(make_home rearm)
  data="$home/payload.json"
  board="$home/.lavish/bearings-board.html"
  write_valid_payload "$data"
  run_board "$home" build "$data" >/dev/null || fail "the first build failed"

  jq '.generated = "2026-08-19T01:00Z"' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  out=$(run_board "$home" build "$data") || fail "the rebuild failed"
  assert_contains "$out" "already-armed: " "the rebuild re-armed an already registered source: $out"
  extract_payload "$board" | jq -e '.generated == "2026-08-19T01:00Z"' >/dev/null \
    || fail "the rebuild did not refresh the board payload in place"
  records=$(find "$home/state/procevent" -name '*.source' | wc -l | tr -d ' ')
  [ "$records" = 1 ] || fail "rebuilding left $records source registrations instead of 1"
  pass "rebuild refreshes the board in place without double-arming"
}

test_build_refuses_a_template_without_exactly_one_slot() {
  local home data rc out
  home=$(make_home badslot)
  data="$home/payload.json"
  write_valid_payload "$data"
  printf '<html><body>no slot</body></html>\n' > "$home/broken-template.html"
  set +e
  out=$(FM_BEARINGS_BOARD_TEMPLATE="$home/broken-template.html" run_board "$home" build "$data" 2>&1)
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "a template with no data slot was accepted"
  assert_contains "$out" "data slot" "the slot refusal did not say why: $out"
  assert_absent "$home/.lavish/bearings-board.html" "a refused template still produced a board"
  pass "build refuses a template without exactly one data slot"
}

test_charted_kind_is_optional_and_accepts_both_values() {
  local home data
  home=$(make_home chartedkind)
  data="$home/payload.json"
  write_valid_payload "$data"
  jq '.charted = [
        {"id":"a","repo":"sample","title":"Queued","reason":"","dispatchable":true},
        {"id":"b","repo":"sample","title":"Queued too","reason":"gated","dispatchable":true,"kind":"queued"},
        {"id":"c","repo":"sample","title":"Integrity notice","reason":"main inventory","dispatchable":false,"kind":"warning"}
      ] | .charted_warning_more = 2' "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  run_board "$home" build "$data" >/dev/null \
    || fail "an omitted, queued, and warning charted kind was refused"
  extract_payload "$home/.lavish/bearings-board.html" | jq -e '
    ([.charted[] | .kind // "queued"]) == ["queued", "queued", "warning"]
      and .charted_warning_more == 2
  ' >/dev/null || fail "the built board did not carry the charted kinds and omitted-warning count it was given"
  pass "charted kind is optional and accepts queued and warning"
}


# --- part 1: never arm a poll on an ended session ---------------------------

test_build_reopens_a_session_the_captain_ended() {
  local home data board out sid claim old_pid old_token new_pid new_token
  home=$(make_home ended-session)
  data="$home/payload.json"
  board="$home/.lavish/bearings-board.html"
  write_valid_payload "$data"
  run_board "$home" build "$data" >/dev/null || fail "the first build failed"
  sid=$(run_lavish_source_id "$home" "$board")
  claim="$home/procevent-claims/$sid.claim"
  old_pid=$(sed -n '2p' "$claim")
  old_token=$(sed -n '3p' "$claim")

  # The reported case: the captain ends the board from the browser, so opening
  # it again keeps the same session id, reports it ended, and EXITS 0. A build
  # that trusts the exit status arms a poll nothing can ever attach to.
  : > "$home/lavish-state/hold-after-terminal"
  : > "$home/lavish-state/poll-trigger"
  for _ in $(seq 1 100); do
    [ -e "$home/lavish-state/terminal-emitted" ] && break
    sleep 0.05
  done
  [ -e "$home/lavish-state/terminal-emitted" ] \
    || fail "the old listener did not receive its terminal result"
  rm -f "$home/lavish-state/poll-trigger"
  end_session_as_captain "$home"
  out=$(run_board "$home" build "$data") || fail "the rebuild refused a recoverable ended session"
  rm -f "$home/lavish-state/hold-after-terminal"
  assert_contains "$out" "session: reopened" \
    "the rebuild did not reopen the ended session: $out"
  [ ! -e "$home/lavish-state/user-ended" ] \
    || fail "the rebuild reported success while the session was still ended"
  new_pid=$(sed -n '2p' "$claim")
  new_token=$(sed -n '3p' "$claim")
  [ "$new_pid" != "$old_pid" ] || [ "$new_token" != "$old_token" ] \
    || fail "the rebuild accepted the pre-reopen source generation"
  [ "$(run_procevent "$home" list | awk -v id="$sid" 'NR > 1 && $1 == id { print $3 }')" = live ] \
    || fail "the reopened board has no live listener"
  pass "a board build reopens a session the captain ended instead of arming a dead one"
}

test_build_reopens_when_an_opened_session_ends_before_listing() {
  local home data out board sid
  home=$(make_home establish-list-race)
  data="$home/payload.json"
  board="$home/.lavish/bearings-board.html"
  write_valid_payload "$data"
  : > "$home/lavish-state/end-before-next-list"
  out=$(run_board "$home" build "$data") || fail "the raced session build failed: $out"
  assert_contains "$out" "session: reopened" \
    "the build trusted an opened response after the server no longer listed it: $out"
  sid=$(run_lavish_source_id "$home" "$board")
  [ -s "$home/lavish-state/open" ] || fail "the raced session was not live before arming"
  [ "$(run_procevent "$home" list | awk -v id="$sid" 'NR > 1 && $1 == id { print $3 }')" = live ] \
    || fail "the replacement session did not receive a live listener"
  pass "build reopens a session that ends between establish and listing"
}

test_build_refuses_to_arm_when_the_session_stays_ended() {
  local home data rc out sid
  home=$(make_home dead-session)
  data="$home/payload.json"
  write_valid_payload "$data"
  # An ended session that will not come back: the build must stop rather than
  # register a poll against it.
  : > "$home/lavish-state/refuse-reopen"
  set +e
  out=$(run_board "$home" build "$data" 2>&1)
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "build armed a poll on a session that stayed ended: $out"
  assert_contains "$out" "ended session" "the refusal did not say why: $out"
  sid=$(run_lavish_source_id "$home" "$home/.lavish/bearings-board.html")
  ! run_decisions "$home" binding "$sid" >/dev/null 2>&1 \
    || fail "build bound the board to a session that stayed ended"
  ! run_procevent "$home" list | awk 'NR > 1 { print $1 }' | grep -Fxq "$sid" \
    || fail "build armed the board against a session that stayed ended"
  pass "build refuses to arm a poll on a session that stays ended"
}

test_build_starts_a_listener_for_an_already_armed_board() {
  local home data board out sid claim
  home=$(make_home relisten)
  data="$home/payload.json"
  board="$home/.lavish/bearings-board.html"
  write_valid_payload "$data"
  run_board "$home" build "$data" >/dev/null || fail "the first build failed"
  sid=$(run_lavish_source_id "$home" "$board")

  # Registered is not listening: drop the listener the way a crashed generation
  # would, then rebuild. `already-armed` must not be the end of the story.
  claim="$home/procevent-claims/$sid.claim"
  assert_present "$claim" "the first build left no listener to lose"
  kill -KILL -"$(sed -n '2p' "$claim")" 2>/dev/null || true
  kill -KILL "$(sed -n '2p' "$claim")" 2>/dev/null || true
  sleep 1

  out=$(run_board "$home" build "$data") || fail "the rebuild failed"
  assert_contains "$out" "already-armed: $sid" "the rebuild re-registered the source: $out"
  [ "$(run_procevent "$home" list | awk -v id="$sid" 'NR > 1 && $1 == id { print $3 }')" = live ] \
    || fail "the rebuilt board is registered but nothing is listening"
  pass "a rebuild starts a listener when an already-armed board has none"
}

# --- part 2: a landed subject is not a live call ----------------------------

test_build_drops_decision_cards_whose_subject_already_landed() {
  local home data board out
  home=$(make_home landed-cards)
  data="$home/payload.json"
  board="$home/.lavish/bearings-board.html"
  write_valid_payload "$data"
  jq '.captains_call = [
        {"key":"landed-by-task","type":"decision","repo":"sample","title":"Already shipped",
         "options":[{"value":"yes","label":"Yes"}]},
        {"key":"timeout-reattach","type":"decision","repo":"sample","title":"Already merged",
         "pr_url":"https://github.com/sample/sample/pull/7",
         "options":[{"value":"yes","label":"Yes"}]},
        {"key":"quota-version","type":"decision","repo":"sample","title":"Old quota release",
         "subject":{"artifact":"quota-axi","version":"0.1.37"},
         "options":[{"value":"yes","label":"Yes"}]},
        {"key":"still-open","type":"decision","repo":"sample","title":"Genuinely open",
         "subject":{"artifact":"quota-axi","version":"0.2.0"},
         "options":[{"value":"yes","label":"Yes"}]}
      ]
      | .landed = [
        {"id":"landed-by-task","repo":"sample","what":"shipped it","owner":"crew"},
        {"id":"some-other-task","repo":"sample","what":"merged timeout reattach","owner":"crew",
         "pr_url":"https://github.com/sample/sample/pull/7"},
        {"id":"quota-release","repo":"sample","what":"published quota-axi","owner":"crew",
         "subject":{"artifact":"quota-axi","version":"0.1.38"}},
        {"id":"unrelated\nstill-open","repo":"sample","what":"unrelated multiline identity","owner":"crew"}
      ]' "$data" > "$data.tmp" && mv "$data.tmp" "$data"

  out=$(run_board "$home" build "$data" 2>&1) || fail "the hygiene build failed: $out"
  assert_contains "$out" "dropped-landed-card: landed-by-task" \
    "the build did not report dropping the landed work item card: $out"
  assert_contains "$out" "dropped-landed-card: timeout-reattach" \
    "the build did not report dropping the merged timeout/reattach card: $out"
  assert_contains "$out" "dropped-landed-card: quota-version" \
    "the build did not report dropping the superseded quota-axi version card: $out"
  extract_payload "$board" | jq -e '[.captains_call[].key] == ["still-open"]' >/dev/null \
    || fail "the board dropped an open card or kept one whose subject already landed"
  pass "build drops decision cards whose subject already landed and keeps open ones"
}

test_build_keeps_a_decision_absent_from_the_main_backlog() {
  local home data board out
  home=$(make_home remote-decision-card)
  data="$home/payload.json"
  board="$home/.lavish/bearings-board.html"
  cp "$ROOT/.tasks.toml" "$home/.tasks.toml"
  cat > "$home/data/backlog.md" <<'EOF'
## In flight

## Queued

## Done
EOF
  write_valid_payload "$data"
  jq '.captains_call = [{
        "key":"remote-mate-call","type":"decision","repo":"sample",
        "title":"Remote secondmate decision",
        "options":[{"value":"yes","label":"Yes"}]
      }]
      | .landed = []' "$data" > "$data.tmp" && mv "$data.tmp" "$data"

  out=$(run_board "$home" build "$data" 2>&1) || fail "the remote-card build failed: $out"
  assert_not_contains "$out" "dropped-landed-card: remote-mate-call" \
    "an absent remote card was reported as landed: $out"
  extract_payload "$board" | jq -e '
    [.captains_call[] | select(.key == "remote-mate-call")] | length == 1
  ' >/dev/null || fail "the hygiene check dropped a decision absent from the main backlog"
  pass "build keeps remote decisions absent from the main backlog"
}

# --- part 3: every decision card offers reconcile ---------------------------

test_build_fails_when_reconcile_cannot_establish_a_listener() {
  local home data out rc sid
  home=$(make_home no-listener)
  data="$home/payload.json"
  write_valid_payload "$data"
  run_board "$home" build "$data" >/dev/null || fail "could not establish the listener fixture"
  sid=$(run_lavish_source_id "$home" "$home/.lavish/bearings-board.html")
  cat > "$home/fakebin/ps" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$home/fakebin/ps"
  set +e
  out=$(FM_PROC_ROOT_OVERRIDE="$home/no-proc" run_board "$home" build "$data" 2>&1)
  rc=$?
  set -e
  rm -f "$home/fakebin/ps"
  [ "$rc" -ne 0 ] || fail "a build with an uncertain listener reported success: $out"
  assert_contains "$out" "source $sid is not listening after reconcile" \
    "the refusal did not name the source: $out"
  assert_contains "$out" "observed owner: uncertain" \
    "the refusal did not name the observed owner: $out"
  pass "build fails when reconcile cannot prove a live listener"
}

test_every_decision_card_carries_the_reconcile_choice() {
  local home data board
  home=$(make_home reconcile-option)
  data="$home/payload.json"
  board="$home/.lavish/bearings-board.html"
  write_valid_payload "$data"
  run_board "$home" build "$data" >/dev/null || fail "the reconcile-option build failed"
  extract_payload "$board" | jq -e '
    ([.captains_call[] | select(.type == "decision")] | length) > 0
    and ([.captains_call[]
      | select(.type == "decision")
      | ([.options[] | select(.value == "reconcile")] | length) == 1
        and ([.options[] | select(.value == "reconcile") | .label | length > 0] | all)] | all)
  ' >/dev/null || fail "a decision card was published without the reconcile choice"
  extract_payload "$board" | jq -e '
    ([.captains_call[] | select(.type != "decision")
      | .options[] | select(.value == "reconcile")] | length) == 0
  ' >/dev/null || fail "reconcile was injected into a non-decision card"
  pass "every decision card carries exactly one reconcile choice"
}

test_build_refuses_a_payload_that_occupies_the_reconcile_value() {
  local home data rc out
  home=$(make_home reconcile-reserved)
  data="$home/payload.json"
  write_valid_payload "$data"
  jq '.captains_call[0].options += [{"value":"reconcile","label":"Something else"}]' \
    "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e
  out=$(run_board "$home" build "$data" 2>&1)
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "a payload occupying the reserved reconcile value was accepted"
  assert_absent "$home/.lavish/bearings-board.html" "a refused payload still produced a board"
  pass "build refuses a payload that occupies the reserved reconcile value"
}

test_build_refuses_a_nondecision_reconcile_value() {
  local home data rc out
  home=$(make_home merge-reconcile-reserved)
  data="$home/payload.json"
  write_valid_payload "$data"
  jq '.captains_call[1].options += [{"value":"reconcile","label":"Merge action"}]' \
    "$data" > "$data.tmp" && mv "$data.tmp" "$data"
  set +e
  out=$(run_board "$home" build "$data" 2>&1)
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "a merge card occupying the reconcile value was accepted"
  assert_absent "$home/.lavish/bearings-board.html" "a refused merge card still produced a board"
  pass "build reserves reconcile across non-decision cards"
}

# --- part 4: publish, refresh, and build without a composed payload ----------
# A lavish-axi that records every invocation and refuses, for the commands that
# must never reach Lavish at all.
forbid_lavish() {  # <home>
  cat > "$1/fakebin/lavish-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${LAVISH_FAKE_STATE:?}/calls"
exit 1
SH
  chmod +x "$1/fakebin/lavish-axi"
}

lavish_calls() {  # <home>
  if [ -f "$1/lavish-state/calls" ]; then
    wc -l < "$1/lavish-state/calls" | tr -d '[:space:]'
  else
    printf 0
  fi
}

# A home whose generator has something to derive: one queued row and no workers.
seed_backlog() {  # <home>
  mkdir -p "$1/data"
  cat > "$1/data/backlog.md" <<'EOF2'
## In flight

## Queued
- [ ] seeded-row - Seeded queued work (repo: sample) (kind: ship) (since 2026-08-01)

## Done
EOF2
}

append_queued_row() {  # <home> <id> <title>
  python3 - "$1/data/backlog.md" "$2" "$3" <<'PY'
from pathlib import Path
import sys
path, row_id, title = sys.argv[1], sys.argv[2], sys.argv[3]
p = Path(path)
text = p.read_text()
p.write_text(text.replace("\n## Done", "- [ ] %s - %s (repo: sample) (kind: ship) (since 2026-08-02)\n\n## Done" % (row_id, title), 1))
PY
}

board_charted_ids() {  # <home>
  extract_payload "$1/.lavish/bearings-board.html" | jq -r '[.charted[].id] | join(",")'
}

test_publish_writes_the_board_without_lavish() {
  local home data out
  home=$(make_home publish-only)
  forbid_lavish "$home"
  data="$home/payload.json"
  write_valid_payload "$data"
  out=$(run_board "$home" publish "$data") || fail "publish failed: $out"
  [ "$out" = "board: $home/.lavish/bearings-board.html" ] \
    || fail "publish did not report exactly the board path: $out"
  extract_payload "$home/.lavish/bearings-board.html" \
    | jq -e '.schema == "fm-bearings-board.v1" and (.captains_call | length) == 2' >/dev/null \
    || fail "the published board does not carry the payload"
  [ "$(lavish_calls "$home")" = 0 ] || fail "publish reached lavish-axi"
  [ "$(run_procevent "$home" list)" = "no sources registered" ] \
    || fail "publish registered an answer source"
  pass "publish writes the board and never touches Lavish or the answer source"
}

test_refresh_refuses_without_a_board_and_stays_silent_best_effort() {
  local home out rc
  home=$(make_home refresh-none)
  forbid_lavish "$home"
  seed_backlog "$home"
  set +e
  out=$(run_board "$home" refresh 2>&1)
  rc=$?
  set -e
  [ "$rc" -eq 3 ] || fail "refresh without a board exited $rc instead of 3: $out"
  case "$out" in *"no board is published"*) ;; *) fail "refresh did not name the missing board: $out" ;; esac
  out=$(run_board "$home" refresh --best-effort) || fail "a best-effort refresh without a board did not exit 0"
  [ -z "$out" ] || fail "a best-effort refresh without a board printed: $out"
  out=$(run_board "$home" refresh --detach) || fail "a detached refresh without a board did not exit 0"
  [ -z "$out" ] || fail "a detached refresh without a board printed: $out"
  assert_absent "$home/.lavish/bearings-board.html" "refresh created a board in a home that never opened one"
  assert_absent "$home/.lavish/bearings-board-checked.js" "refresh stamped a check in a home that never opened a board"
  assert_absent "$home/state/.bearings-board-refresh.log" "a home without a board logged a refresh failure"
  [ "$(lavish_calls "$home")" = 0 ] || fail "refresh reached lavish-axi"
  pass "refresh refuses without a board, and is silent about it under --best-effort"
}

test_refresh_republishes_only_when_the_payload_changed() {
  local home out first second
  home=$(make_home refresh-gate)
  forbid_lavish "$home"
  seed_backlog "$home"
  write_valid_payload "$home/payload.json"
  run_board "$home" publish "$home/payload.json" >/dev/null || fail "the seed publish failed"
  out=$(run_board "$home" refresh) || fail "the first refresh failed: $out"
  case "$out" in "refreshed: $home/.lavish/bearings-board.html") ;; *) fail "the first refresh did not republish: $out" ;; esac
  [ -s "$home/state/.bearings-board-digest" ] || fail "the first refresh recorded no digest"
  first=$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime)' "$home/state/.bearings-board-digest")
  sleep 1
  out=$(run_board "$home" refresh) || fail "the unchanged refresh failed: $out"
  case "$out" in unchanged:*) ;; *) fail "an unchanged fleet was republished: $out" ;; esac
  second=$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime)' "$home/state/.bearings-board-digest")
  python3 -c 'import sys; sys.exit(0 if float(sys.argv[2]) > float(sys.argv[1]) else 1)' "$first" "$second" \
    || fail "an unchanged refresh did not advance the digest's last-attempt stamp"
  append_queued_row "$home" second-row "A second queued row"
  out=$(run_board "$home" refresh) || fail "the changed refresh failed: $out"
  case "$out" in refreshed:*) ;; *) fail "a changed fleet was not republished: $out" ;; esac
  [ "$(board_charted_ids "$home")" = "second-row,seeded-row" ] \
    || fail "the republished board does not carry the new row: $(board_charted_ids "$home")"
  [ "$(lavish_calls "$home")" = 0 ] || fail "refresh reached lavish-axi"
  pass "refresh republishes the board only when the derived payload changed"
}

test_refresh_never_reopens_a_session_the_captain_ended() {
  local home out
  home=$(make_home refresh-ended)
  seed_backlog "$home"
  run_board "$home" build >/dev/null || fail "the first build failed"
  end_session_as_captain "$home"
  # Stop the listener the build armed so its own poll retries cannot be
  # mistaken for a refresh reaching Lavish; the board file stays.
  run_procevent "$home" retire "$(run_lavish_source_id "$home" "$home/.lavish/bearings-board.html")" >/dev/null \
    || fail "could not retire the armed listener"
  forbid_lavish "$home"
  append_queued_row "$home" after-end "Filed after the captain closed the board"
  out=$(run_board "$home" refresh) || fail "refresh after an ended session failed: $out"
  case "$out" in refreshed:*) ;; *) fail "refresh did not republish after an ended session: $out" ;; esac
  [ "$(lavish_calls "$home")" = 0 ] \
    || fail "refresh called lavish-axi on an ended session: $(cat "$home/lavish-state/calls")"
  pass "refresh republishes silently and never reopens a session the captain ended"
}

checked_epoch() {  # <home>
  sed -n 's/.*{checked: \([0-9][0-9]*\)}.*/\1/p' "$1/.lavish/bearings-board-checked.js" 2>/dev/null
}

mtime_of() {  # <path>
  python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime)' "$1"
}

# Every attempt that derives a payload stamps the sibling check script the
# open page loads, and every attempt, a failed one included, touches the
# digest so the watcher retries on its cadence rather than on every poll.
test_refresh_stamps_every_attempt_and_every_failure() {
  local home out first second third before after recorded
  home=$(make_home refresh-stamps)
  forbid_lavish "$home"
  seed_backlog "$home"
  write_valid_payload "$home/payload.json"
  run_board "$home" publish "$home/payload.json" >/dev/null || fail "the seed publish failed"
  assert_absent "$home/.lavish/bearings-board-checked.js" "publish alone stamped a check"
  out=$(run_board "$home" refresh) || fail "the first refresh failed: $out"
  first=$(checked_epoch "$home")
  case "$first" in ''|*[!0-9]*) fail "a changed refresh did not stamp the check script: $(cat "$home/.lavish/bearings-board-checked.js" 2>/dev/null)" ;; esac
  sleep 1.1
  out=$(run_board "$home" refresh) || fail "the unchanged refresh failed: $out"
  case "$out" in unchanged:*) ;; *) fail "an unchanged fleet was republished: $out" ;; esac
  second=$(checked_epoch "$home")
  [ "$second" -gt "$first" ] || fail "an unchanged refresh did not advance the check stamp: $first -> $second"
  append_queued_row "$home" broken-row "A change that cannot be published"
  before=$(mtime_of "$home/state/.bearings-board-digest")
  recorded=$(cat "$home/state/.bearings-board-digest")
  sleep 1.1
  out=$(FM_BEARINGS_BOARD_TEMPLATE="$home/missing-template.html" run_board "$home" refresh --best-effort) \
    || fail "a best-effort refresh whose publish failed did not exit 0"
  [ -z "$out" ] || fail "a failed best-effort refresh printed: $out"
  after=$(mtime_of "$home/state/.bearings-board-digest")
  python3 -c 'import sys; sys.exit(0 if float(sys.argv[2]) > float(sys.argv[1]) else 1)' "$before" "$after" \
    || fail "a failed refresh did not touch the digest as its last-attempt stamp"
  [ "$(cat "$home/state/.bearings-board-digest")" = "$recorded" ] \
    || fail "a failed refresh changed the recorded digest"
  grep -q "board template is missing" "$home/state/.bearings-board-refresh.log" \
    || fail "the failed refresh was not recorded in the refresh log: $(cat "$home/state/.bearings-board-refresh.log" 2>/dev/null)"
  third=$(checked_epoch "$home")
  [ "$third" = "$second" ] || fail "a failed refresh stamped the check script: $second -> $third"
  [ "$(board_charted_ids "$home")" = "seeded-row" ] \
    || fail "a failed refresh changed the published board: $(board_charted_ids "$home")"
  out=$(run_board "$home" refresh) || fail "the recovery refresh failed: $out"
  case "$out" in refreshed:*) ;; *) fail "the recovery refresh did not republish the pending change: $out" ;; esac
  [ "$(board_charted_ids "$home")" = "broken-row,seeded-row" ] \
    || fail "the recovery refresh did not carry the pending row: $(board_charted_ids "$home")"
  [ "$(lavish_calls "$home")" = 0 ] || fail "refresh reached lavish-axi"
  pass "refresh stamps the check on every derived attempt and touches the digest on every failure"
}

# The non-watcher call sites hand the refresh to a detached child, so a slow
# generation never sits in front of session start, a captain answer, a spawn,
# a teardown, or a PR check. The one-shot slow jq stands in for a slow fleet.
test_refresh_detach_returns_before_the_generation_finishes() {
  local home out started elapsed real_jq i
  home=$(make_home refresh-detach)
  forbid_lavish "$home"
  seed_backlog "$home"
  write_valid_payload "$home/payload.json"
  run_board "$home" publish "$home/payload.json" >/dev/null || fail "the seed publish failed"
  real_jq=$(command -v jq)
  cat > "$home/fakebin/jq" <<SH
#!/usr/bin/env bash
if [ -e "$home/slow-once" ]; then rm -f "$home/slow-once"; sleep 2; fi
exec "$real_jq" "\$@"
SH
  chmod +x "$home/fakebin/jq"
  : > "$home/slow-once"
  started=$(python3 -c 'import time; print(time.time())')
  out=$(run_board "$home" refresh --detach) || fail "a detached refresh did not exit 0: $out"
  elapsed=$(python3 -c 'import sys,time; print(time.time() - float(sys.argv[1]))' "$started")
  [ -z "$out" ] || fail "a detached refresh printed: $out"
  python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < 1.5 else 1)' "$elapsed" \
    || fail "a detached refresh waited ${elapsed}s for the generation instead of returning at once"
  i=0
  while [ "$(board_charted_ids "$home")" != "seeded-row" ] || [ ! -s "$home/state/.bearings-board-digest" ] \
    || [ -z "$(checked_epoch "$home")" ]; do
    [ "$i" -lt 300 ] || fail "the detached child never republished and stamped the board: $(board_charted_ids "$home")"
    sleep 0.1
    i=$((i + 1))
  done
  assert_absent "$home/slow-once" "the detached child did not run the generation"
  assert_absent "$home/state/.bearings-board-refresh.log" "the detached child logged a failure: $(cat "$home/state/.bearings-board-refresh.log" 2>/dev/null)"
  [ "$(lavish_calls "$home")" = 0 ] || fail "the detached refresh reached lavish-axi"
  pass "refresh --detach returns at once and the detached child publishes the board on its own"
}

# A change that arrives while a refresh is already deriving would otherwise
# wait for the next cadence: the busy refresh leaves a pending marker and the
# lock holder runs exactly one follow-up publish before releasing the lock. A
# marker touched during that follow-up waits, so the holder can never loop.
test_a_busy_refresh_yields_exactly_one_follow_up_publish() {
  local home out i refresh_pid
  home=$(make_home refresh-pending)
  forbid_lavish "$home"
  seed_backlog "$home"
  write_valid_payload "$home/payload.json"
  run_board "$home" publish "$home/payload.json" >/dev/null || fail "the seed publish failed"
  # Each generation blocks on its own release file and derives a distinct
  # payload, so every run is a real publish and every run is countable.
  cat > "$home/fakebin/generator" <<SH
#!/usr/bin/env bash
n=\$(cat "$home/gen-count" 2>/dev/null || printf 0)
n=\$((n + 1))
printf '%s\\n' "\$n" > "$home/gen-count"
: > "$home/gen-started-\$n"
while [ ! -e "$home/gen-release-\$n" ]; do
  [ "\$SECONDS" -lt 60 ] || exit 75
  sleep 0.05
done
jq --arg n "\$n" '.charted += [{id: ("generation-" + \$n), repo: "sample", title: ("Generation " + \$n), reason: "", dispatchable: true}]' "$home/payload.json"
SH
  chmod +x "$home/fakebin/generator"
  wait_for() {  # <path> <what>
    local j=0
    while [ ! -e "$1" ]; do
      [ "$j" -lt 200 ] || fail "$2"
      sleep 0.05
      j=$((j + 1))
    done
  }
  FM_BEARINGS_BOARD_GENERATOR="$home/fakebin/generator" run_board "$home" refresh > "$home/first.out" 2>&1 &
  refresh_pid=$!
  wait_for "$home/gen-started-1" "the first refresh never started deriving"
  out=$(FM_BEARINGS_BOARD_GENERATOR="$home/fakebin/generator" run_board "$home" refresh) \
    || fail "a refresh during a running refresh failed: $out"
  case "$out" in busy:*) ;; *) fail "a refresh during a running refresh did not yield: $out" ;; esac
  [ -e "$home/state/.bearings-board-refresh-pending" ] || fail "the busy refresh left no pending marker"
  out=$(FM_BEARINGS_BOARD_GENERATOR="$home/fakebin/generator" run_board "$home" refresh)
  case "$out" in busy:*) ;; *) fail "a second busy refresh did not yield: $out" ;; esac
  : > "$home/gen-release-1"
  wait_for "$home/gen-started-2" "the lock holder ran no follow-up after finding the pending marker"
  assert_absent "$home/state/.bearings-board-refresh-pending" "the follow-up run did not clear the pending marker first"
  [ "$(board_charted_ids "$home")" = "sample-queued,generation-1" ] \
    || fail "the first run did not publish its own payload before the follow-up: $(board_charted_ids "$home")"
  out=$(FM_BEARINGS_BOARD_GENERATOR="$home/fakebin/generator" run_board "$home" refresh)
  case "$out" in busy:*) ;; *) fail "a refresh during the follow-up did not yield: $out" ;; esac
  : > "$home/gen-release-2"
  wait "$refresh_pid" || fail "the first refresh failed: $(cat "$home/first.out")"
  [ "$(grep -c '^refreshed: ' "$home/first.out")" = 2 ] \
    || fail "the lock holder did not report exactly one follow-up publish: $(cat "$home/first.out")"
  [ "$(board_charted_ids "$home")" = "sample-queued,generation-2" ] \
    || fail "the follow-up run did not publish the newer payload: $(board_charted_ids "$home")"
  i=0
  while [ "$i" -lt 10 ]; do sleep 0.1; i=$((i + 1)); done
  [ "$(cat "$home/gen-count")" = 2 ] || fail "the lock holder looped past one follow-up: $(cat "$home/gen-count") generations"
  [ -e "$home/state/.bearings-board-refresh-pending" ] \
    || fail "a marker touched during the follow-up did not wait for the next refresh"
  assert_absent "$home/state/.bearings-board-refresh.lock" "the refresh lock was not released"
  [ "$(lavish_calls "$home")" = 0 ] || fail "refresh reached lavish-axi"
  pass "a busy refresh leaves a pending marker and the lock holder publishes exactly one follow-up"
}

test_build_without_a_payload_generates_one() {
  local home out
  home=$(make_home build-generated)
  seed_backlog "$home"
  out=$(run_board "$home" build) || fail "build without a payload failed: $out"
  case "$out" in "board: $home/.lavish/bearings-board.html"*) ;; *) fail "build did not start with the board line: $out" ;; esac
  case "$out" in *"armed: lavish-"*) ;; *) fail "build did not arm the generated board: $out" ;; esac
  extract_payload "$home/.lavish/bearings-board.html" | jq -e '
    .schema == "fm-bearings-board.v1"
      and (.captains_call | length) == 0
      and (.charted | length) == 1
      and (.charted[0] | .id == "seeded-row" and .repo == "sample" and .dispatchable == true and .filed == "2026-08-01")
  ' >/dev/null || fail "the generated board does not reflect the seeded backlog"
  [ -s "$home/state/.bearings-board-digest" ] || fail "build recorded no digest for the payload it published"
  [ -n "$(checked_epoch "$home")" ] || fail "build did not stamp the check script"
  out=$(run_board "$home" refresh) || fail "the refresh after build failed: $out"
  case "$out" in unchanged:*) ;; *) fail "the refresh after build republished an identical board: $out" ;; esac
  pass "build derives its own payload when none is given and records its digest"
}

test_serve_refuses_without_a_board() {
  local home out rc
  home=$(make_home serve-none)
  set +e
  out=$(run_board "$home" serve 2>&1)
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "serve without a board succeeded"
  case "$out" in *"no board is published"*) ;; *) fail "serve did not name the missing board: $out" ;; esac
  [ "$(run_procevent "$home" list)" = "no sources registered" ] \
    || fail "serve without a board registered an answer source"
  pass "serve refuses to bind or arm when no board is published"
}

test_path_is_stable_and_home_scoped
test_build_refuses_malformed_payloads_before_touching_the_board
test_charted_kind_is_optional_and_accepts_both_values
test_build_injects_binds_then_arms
test_registration_cannot_consume_before_any_origin_binding
test_build_does_not_bind_or_arm_when_session_start_fails
test_rebuild_is_idempotent_and_does_not_double_arm
test_build_refuses_a_template_without_exactly_one_slot
test_build_reopens_a_session_the_captain_ended
test_build_reopens_when_an_opened_session_ends_before_listing
test_build_refuses_to_arm_when_the_session_stays_ended
test_build_starts_a_listener_for_an_already_armed_board
test_build_drops_decision_cards_whose_subject_already_landed
test_build_keeps_a_decision_absent_from_the_main_backlog
test_build_fails_when_reconcile_cannot_establish_a_listener
test_every_decision_card_carries_the_reconcile_choice
test_build_refuses_a_payload_that_occupies_the_reconcile_value
test_build_refuses_a_nondecision_reconcile_value
test_publish_writes_the_board_without_lavish
test_refresh_refuses_without_a_board_and_stays_silent_best_effort
test_refresh_republishes_only_when_the_payload_changed
test_refresh_never_reopens_a_session_the_captain_ended
test_refresh_stamps_every_attempt_and_every_failure
test_refresh_detach_returns_before_the_generation_finishes
test_a_busy_refresh_yields_exactly_one_follow_up_publish
test_build_without_a_payload_generates_one
test_serve_refuses_without_a_board
