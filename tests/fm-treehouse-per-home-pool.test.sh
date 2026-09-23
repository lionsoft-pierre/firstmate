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
# These tests pin the three parts of the fix: the root home keeps Treehouse's
# own root while each secondmate home resolves its own pool root outside
# itself, fm-spawn delivers that root to the pane that actually runs
# `treehouse get` (and types the plain command for the root home), and a slot
# backed by a foreign checkout is returned and refused rather than launched into.
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

# One throwaway world: an origin, a primary home and three secondmate homes
# whose clones of that origin all carry the SAME directory name (the shape that
# makes every home resolve one pool), and a spawn-world fakebin per home. Each
# secondmate home carries the .fm-secondmate-home marker seeding leaves behind.
# Homes A and B also carry a local .fm-secondmate-parent record naming the
# primary home; home C carries a route=remote record, the shape of a home
# seeded on another machine (bin/fm-secondmate-parent-lib.sh owns the fields).
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
  for home in R A B C; do
    mkdir -p "$world/home$home/projects"
    git clone --quiet "file://$world/origin.git" "$world/home$home/projects/app"
    fm_test_spawn_home "$world/home$home" codex
  done
  for home in A B C; do
    printf 'sm%s\n' "$home" > "$world/home$home/.fm-secondmate-home"
  done
  for home in A B; do
    printf 'schema=fm-secondmate-parent.v1\nroute=local\nparent_home=%s\n' "$world/homeR" \
      > "$world/home$home/.fm-secondmate-parent"
  done
  printf 'schema=fm-secondmate-parent.v1\nroute=remote\nparent_host=parent-machine\n' \
    > "$world/homeC/.fm-secondmate-parent"
  printf '%s\n' "$world"
}

# --- the root each home resolves -------------------------------------------

test_root_home_keeps_treehouse_own_root() {
  local world root_r

  world=$(make_world rootroot)
  root_r=$(treehouse_root_for "$world/homeR") \
    || fail "the root home could not resolve its pool root"
  [ -z "$root_r" ] \
    || fail "the root home resolved a per-home pool root ($root_r) instead of Treehouse's own"
  pass "the root home resolves no per-home root, so Treehouse's own root stays in effect"
}

test_remote_seeded_secondmate_home_resolves_its_own_root() {
  local world root_r root_a root_c

  world=$(make_world remote)
  root_r=$(treehouse_root_for "$world/homeR") || fail "the primary home could not resolve its pool root"
  root_a=$(treehouse_root_for "$world/homeA") || fail "home A could not resolve a pool root"
  root_c=$(treehouse_root_for "$world/homeC") \
    || fail "the remote-seeded secondmate home could not resolve a pool root"

  [ -n "$root_c" ] \
    || fail "the remote-seeded secondmate home was classed as a primary home and resolved no pool root"
  [ "$root_c" != "$root_r" ] && [ "$root_c" != "$root_a" ] \
    || fail "the remote-seeded home shares a pool root with another home (C='$root_c' R='$root_r' A='$root_a')"
  case "$root_c" in
    "$world/homeC"/*) fail "the remote-seeded home's pool root sits inside the home itself: $root_c" ;;
    /*) ;;
    *) fail "the remote-seeded home's pool root is not absolute: $root_c" ;;
  esac
  pass "a remote-seeded secondmate home resolves its own pool root, distinct from the primary home's and every other home's"
}

test_symlinked_secondmate_marker_is_refused() {
  local world

  world=$(make_world symlinked)
  printf 'smR\n' > "$world/planted-marker"
  ln -s "$world/planted-marker" "$world/homeR/.fm-secondmate-home"
  if treehouse_root_for "$world/homeR" >/dev/null 2>&1; then
    fail "a symlinked .fm-secondmate-home marker was followed instead of refused"
  fi
  pass "a symlinked .fm-secondmate-home marker is refused rather than used to classify the home"
}

test_each_secondmate_home_resolves_its_own_root_outside_itself() {
  local world root_a root_b again config home

  world=$(make_world roots)
  root_a=$(treehouse_root_for "$world/homeA") || fail "home A could not resolve a pool root"
  root_b=$(treehouse_root_for "$world/homeB") || fail "home B could not resolve a pool root"

  [ -n "$root_a" ] && [ -n "$root_b" ] \
    || fail "a secondmate home resolved no pool root of its own (A='$root_a' B='$root_b')"
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
  pass "each secondmate home resolves its own absolute pool root, stable across calls and outside the home"

  for home in R A; do
    config="$world/home$home/config"
    printf '%s\n' "$world/configured-root" > "$config/treehouse-root"
    root_a=$(treehouse_root_for "$world/home$home" "$config") \
      || fail "an absolute config/treehouse-root was refused for home $home"
    [ "$root_a" = "$world/configured-root" ] \
      || fail "config/treehouse-root did not override home $home's root: $root_a"
    rm -f "$config/treehouse-root"
  done

  config="$world/homeA/config"
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
  pass "config/treehouse-root overrides either home kind's root and refuses a non-absolute value"
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
  [ -n "$expected" ] || fail "the secondmate home resolved no pool root to type"

  pane_log="$world/pane.log"
  out=$(FM_FAKE_PANE_LOG="$pane_log" \
    fm_test_run_spawn "$world/homeB" "$slot" "$fakebin" "$id" "$world/homeB/projects/app" --scout)
  status=$?
  expect_code 0 "$status" "the spawn into this home's own slot should launch"$'\n'"$out"

  grep -Fxq "treehouse get --root '$expected'" "$pane_log" \
    || fail "the pane was not told which pool root to acquire from"$'\n'"--- pane log ---"$'\n'"$(cat "$pane_log")"
  grep -Fxq 'treehouse get' "$pane_log" \
    && fail "the pane still received a rootless acquisition"$'\n'"$(cat "$pane_log")"
  pass "fm-spawn types a secondmate home's own pool root into the pane that runs the acquisition"
}

test_root_home_spawn_types_a_plain_acquisition() {
  local world id slot fakebin pane_log out status

  world=$(make_world plain)
  id='perhomepool-plain-r1'
  fm_test_spawn_brief "$world/homeR" "$id"
  fakebin=$(make_spawn_fakebin "$world/fake")
  git -C "$world/homeR/projects/app" worktree add --quiet --detach "$world/checkout" HEAD
  slot=$(lay_out_pool_slot "$world/homeR/projects/app" "$world/checkout" "$world/slots")

  pane_log="$world/pane.log"
  out=$(FM_FAKE_PANE_LOG="$pane_log" \
    fm_test_run_spawn "$world/homeR" "$slot" "$fakebin" "$id" "$world/homeR/projects/app" --scout)
  status=$?
  expect_code 0 "$status" "the root home's spawn into its own slot should launch"$'\n'"$out"

  grep -Fxq 'treehouse get' "$pane_log" \
    || fail "the root home's pane did not receive the plain acquisition"$'\n'"--- pane log ---"$'\n'"$(cat "$pane_log")"
  grep -Fq -- '--root' "$pane_log" \
    && fail "the root home's pane was pinned to a per-home pool root"$'\n'"$(cat "$pane_log")"
  pass "fm-spawn types the plain acquisition for the root home, leaving Treehouse's own root in effect"
}

# --- a slot backed by another home's clone ---------------------------------

test_spawn_refuses_a_slot_backed_by_another_homes_clone() {
  local world id slot fakebin out status treehouse_log

  world=$(make_world foreign)
  id='perhomepool-foreign-r1'
  fm_test_spawn_brief "$world/homeB" "$id"
  fakebin=$(make_spawn_fakebin "$world/fake")
  treehouse_log="$world/treehouse.argv"
  cat > "$fakebin/treehouse" <<SH
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> '$treehouse_log'
exit 0
SH
  chmod +x "$fakebin/treehouse"
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
  grep -Fxq "return --force $slot" "$treehouse_log" \
    || fail "the refused spawn did not return exactly the slot it was handed"$'\n'"--- treehouse argv ---"$'\n'"$(cat "$treehouse_log" 2>/dev/null)"
  pass "fm-spawn refuses a pool slot backed by another home's clone instead of launching into it"
}

# --- the reproduction, against the real treehouse binary -------------------

test_real_pool_hands_a_shared_root_the_other_homes_clone() {
  local world shared slot_a slot_b backing_b root_b typed slot_own

  if ! command -v treehouse >/dev/null 2>&1; then
    echo "skip: treehouse not found (required to reproduce pool allocation)"
    return 0
  fi
  if ! treehouse --help 2>&1 | grep -Eq '(^|[^[:alnum:]_-])--root([^[:alnum:]_-]|$)'; then
    echo "skip: installed treehouse has no --root (2.2.0+ required to reproduce pool allocation)"
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

test_root_home_keeps_treehouse_own_root
test_each_secondmate_home_resolves_its_own_root_outside_itself
test_remote_seeded_secondmate_home_resolves_its_own_root
test_symlinked_secondmate_marker_is_refused
test_spawn_types_the_home_pool_root_into_the_pane
test_root_home_spawn_types_a_plain_acquisition
test_spawn_refuses_a_slot_backed_by_another_homes_clone
test_real_pool_hands_a_shared_root_the_other_homes_clone
