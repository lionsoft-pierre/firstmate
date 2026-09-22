#!/usr/bin/env bash
# Regression tests for the per-home Treehouse worktree pool.
#
# Treehouse keys a pool by repository identity and shares every pool under one
# root with every checkout that reaches it. A slot is a linked worktree of
# whichever checkout grew it, and `treehouse get` hands back any FREE slot, so
# two firstmate homes holding their own clones of one repository under a single
# root take turns being handed each other's slots - intermittently, because a
# pool with no free slot grows one from the asking checkout and the spawn works.
# A worker launched into another home's clone commits in a copy that home owns;
# a Claude launch instead stops at bin/fm-claude-trust.sh's structural refusal,
# which reads as a trust problem and names nothing about the pool.
#
# These tests pin the three parts of the fix: each home resolves its own pool
# root outside itself, fm-spawn delivers that root to the pane that actually
# runs `treehouse get`, and a slot backed by a foreign checkout is returned and
# refused rather than launched into.
#
# The last test drives the real treehouse binary and is the reproduction itself:
# one shared root hands home B a worktree of home A's clone, and the per-home
# roots this change resolves do not.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

TMP_ROOT=$(fm_test_tmproot fm-treehouse-per-home-pool)

# The root a home resolves. FM_SPAWN_HOME_DIR mirrors the throwaway HOME that
# fm_test_run_spawn pins for a spawn, because the derived root hangs off it.
treehouse_root_for() {  # <home> [config-dir]
  HOME="${FM_SPAWN_HOME_DIR:-$HOME}" FM_HOME="$1" FM_CONFIG_OVERRIDE='' bash -c \
    '. "$1"; fm_treehouse_root "$2" "${3:-}"' _ "$ROOT/bin/fm-wake-lib.sh" "$1" "${2:-}"
}

# One throwaway world: an origin, two homes whose clones of it carry the SAME
# directory name (the shape that makes both homes resolve one pool), and a
# spawn-world fakebin per home.
make_world() {  # <name>
  local name=$1 world home
  world="$TMP_ROOT/$name"
  mkdir -p "$world/src"
  git init --quiet -b main "$world/src"
  printf 'base\n' > "$world/src/README.md"
  git -C "$world/src" add README.md
  git -C "$world/src" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' \
    commit -qm initial
  git clone --quiet --bare "$world/src" "$world/origin.git"
  for home in A B; do
    mkdir -p "$world/home$home/projects"
    git clone --quiet "file://$world/origin.git" "$world/home$home/projects/app"
    fm_test_spawn_home "$world/home$home" codex
  done
  printf '%s\n' "$world"
}

# --- the root each home resolves -------------------------------------------

test_each_home_resolves_its_own_root_outside_itself() {
  local world root_a root_b again config

  world=$(make_world roots)
  root_a=$(treehouse_root_for "$world/homeA") || fail "home A could not resolve a pool root"
  root_b=$(treehouse_root_for "$world/homeB") || fail "home B could not resolve a pool root"

  [ "$root_a" != "$root_b" ] \
    || fail "two homes resolved the same pool root ($root_a), so they still share slots"

  again=$(treehouse_root_for "$world/homeA")
  [ "$again" = "$root_a" ] \
    || fail "one home resolved two different pool roots ($root_a then $again)"

  case "$root_a" in
    "$world/homeA"/*) fail "home A's pool root sits inside the home itself: $root_a" ;;
    /*) ;;
    *) fail "home A's pool root is not absolute: $root_a" ;;
  esac
  pass "each home resolves its own absolute pool root, stable across calls and outside the home"

  config="$world/homeA/config"
  printf '%s\n' "$world/configured-root" > "$config/treehouse-root"
  root_a=$(treehouse_root_for "$world/homeA" "$config") \
    || fail "an absolute config/treehouse-root was refused"
  [ "$root_a" = "$world/configured-root" ] \
    || fail "config/treehouse-root did not override the derived root: $root_a"

  printf '  %s  \n' "$world/My Pools" > "$config/treehouse-root"
  root_a=$(treehouse_root_for "$world/homeA" "$config") \
    || fail "an absolute config/treehouse-root containing a space was refused"
  [ "$root_a" = "$world/My Pools" ] \
    || fail "config/treehouse-root with a space did not come back byte-identical: $root_a"

  printf 'pools\n' > "$config/treehouse-root"
  if treehouse_root_for "$world/homeA" "$config" >/dev/null 2>&1; then
    fail "a relative config/treehouse-root was accepted instead of refused"
  fi
  rm -f "$config/treehouse-root"
  pass "config/treehouse-root overrides the derived root and refuses a non-absolute value"
}

# --- what fm-spawn types into the pane -------------------------------------

# Re-lay <checkout> as a managed Treehouse slot (<pool>/<slot>/<repo> beside the
# pool state file), which is the shape fm-spawn claims for its task. Echoes the
# relocated checkout.
lay_out_pool_slot() {  # <backing-project> <checkout> <pool-root>
  local backing=$1 checkout=$2 slot_root=$3 slot
  slot="$slot_root/1/app"
  mkdir -p "$slot_root/1"
  git -C "$backing" worktree move "$checkout" "$slot"
  printf '{"worktrees":[{"name":"1","path":"%s"}]}\n' "$slot" > "$slot_root/treehouse-state.json"
  printf '%s\n' "$slot"
}

test_spawn_types_the_home_pool_root_into_the_pane() {
  local world id slot fakebin pane_log out status expected

  world=$(make_world typed)
  id='perhomepool-typed-r1'
  fm_test_spawn_brief "$world/homeB" "$id"
  fakebin=$(make_spawn_fakebin "$world/fake")
  git -C "$world/homeB/projects/app" worktree add --quiet --detach "$world/checkout" HEAD
  slot=$(lay_out_pool_slot "$world/homeB/projects/app" "$world/checkout" "$world/slots")
  mkdir -p "$world/homeB/user-home"
  expected=$(FM_SPAWN_HOME_DIR="$world/homeB/user-home" treehouse_root_for "$world/homeB")

  pane_log="$world/pane.log"
  out=$(FM_FAKE_PANE_LOG="$pane_log" \
    fm_test_run_spawn "$world/homeB" "$slot" "$fakebin" "$id" "$world/homeB/projects/app" --scout)
  status=$?
  expect_code 0 "$status" "the spawn into this home's own slot should launch"$'\n'"$out"

  grep -Fxq "treehouse get --root '$expected'" "$pane_log" \
    || fail "the pane was not told which pool root to acquire from"$'\n'"--- pane log ---"$'\n'"$(cat "$pane_log")"
  grep -Fxq 'treehouse get' "$pane_log" \
    && fail "the pane still received a rootless acquisition"$'\n'"$(cat "$pane_log")"
  pass "fm-spawn types this home's pool root into the pane that runs the acquisition"
}

# --- a slot backed by another home's clone ---------------------------------

test_spawn_refuses_a_slot_backed_by_another_homes_clone() {
  local world id slot fakebin out status

  world=$(make_world foreign)
  id='perhomepool-foreign-r1'
  fm_test_spawn_brief "$world/homeB" "$id"
  fakebin=$(make_spawn_fakebin "$world/fake")
  # The slot is a worktree of home A's clone, exactly as a shared pool hands it
  # back; home B spawns into its OWN clone of the same origin.
  git -C "$world/homeA/projects/app" worktree add --quiet --detach "$world/checkout" HEAD
  slot=$(lay_out_pool_slot "$world/homeA/projects/app" "$world/checkout" "$world/slots")

  out=$(fm_test_run_spawn "$world/homeB" "$slot" "$fakebin" "$id" "$world/homeB/projects/app" --scout)
  status=$?
  [ "$status" -ne 0 ] \
    || fail "spawn launched a worker into another home's clone"$'\n'"$out"
  assert_contains "$out" "rather than to the spawning project" \
    "the refusal did not name the foreign backing repository"
  assert_contains "$out" "$world/homeA/projects/app" \
    "the refusal did not name the checkout the slot actually belongs to"
  [ ! -e "$world/homeB/state/$id.meta" ] \
    || fail "the refused spawn published a task record"
  [ ! -e "$world/slots/1/.fm-slot-owner" ] \
    || fail "the refused spawn claimed a slot it does not own"
  pass "fm-spawn refuses a pool slot backed by another home's clone instead of launching into it"
}

# --- the reproduction, against the real treehouse binary -------------------

test_real_pool_hands_a_shared_root_the_other_homes_clone() {
  local world shared slot_a slot_b backing_b root_b typed slot_own

  if ! command -v treehouse >/dev/null 2>&1; then
    echo "skip: treehouse not found (required to reproduce pool allocation)"
    return 0
  fi

  world=$(make_world real)
  shared="$world/shared-root"

  # Home A grows the pool, then releases the slot. The slot stays a worktree of
  # home A's clone whether or not anything is using it.
  slot_a=$(cd "$world/homeA/projects/app" && treehouse get --lease --lease-holder A --root "$shared" 2>/dev/null) \
    || fail "home A could not lease a worktree from the shared root"
  ( cd "$world/homeA/projects/app" && treehouse return --force "$slot_a" ) >/dev/null 2>&1 \
    || fail "home A could not return its leased worktree"

  # Home B asks the same root and is handed that free slot.
  slot_b=$(cd "$world/homeB/projects/app" && treehouse get --lease --lease-holder B --root "$shared" 2>/dev/null) \
    || fail "home B could not lease a worktree from the shared root"
  backing_b=$(git -C "$slot_b" rev-parse --path-format=absolute --git-common-dir)
  backing_b=$(cd "$backing_b" && pwd -P)
  [ "$backing_b" = "$(cd "$world/homeA/projects/app/.git" && pwd -P)" ] \
    || fail "the shared pool did not reproduce the cross-home handout; home B got $backing_b"
  ( cd "$world/homeB/projects/app" && treehouse return --force "$slot_b" ) >/dev/null 2>&1 || true
  pass "real treehouse: one shared root hands home B a worktree of home A's clone"

  # The same acquisition, through the command fm-spawn now types, lands in home
  # B's own clone. The subshell `treehouse get` opens is driven over stdin so
  # this runs the interactive form the pane runs, not the lease form.
  # config/treehouse-root keeps the pool this creates inside the throwaway world
  # instead of the developer's real one; the resolver is the same either way.
  printf '%s\n' "$world/homeB-pool" > "$world/homeB/config/treehouse-root"
  root_b=$(treehouse_root_for "$world/homeB" "$world/homeB/config") \
    || fail "home B could not resolve a pool root"
  typed="treehouse get --root '$root_b'"
  slot_own=$( cd "$world/homeB/projects/app" \
    && printf 'pwd -P\nexit\n' | eval "$typed" 2>/dev/null | grep -v '^🌳' | tail -n 1 )
  [ -n "$slot_own" ] && [ -d "$slot_own" ] \
    || fail "the typed acquisition did not enter a worktree (got '${slot_own:-none}')"
  backing_b=$(git -C "$slot_own" rev-parse --path-format=absolute --git-common-dir)
  backing_b=$(cd "$backing_b" && pwd -P)
  [ "$backing_b" = "$(cd "$world/homeB/projects/app/.git" && pwd -P)" ] \
    || fail "home B's own root still handed back another clone's worktree: $backing_b"
  case "$slot_own" in
    "$root_b"/*) ;;
    *) fail "the typed acquisition ignored the pool root it was given: $slot_own" ;;
  esac
  pass "real treehouse: the acquisition fm-spawn types lands in this home's own clone"
}

test_each_home_resolves_its_own_root_outside_itself
test_spawn_types_the_home_pool_root_into_the_pane
test_spawn_refuses_a_slot_backed_by_another_homes_clone
test_real_pool_hands_a_shared_root_the_other_homes_clone
