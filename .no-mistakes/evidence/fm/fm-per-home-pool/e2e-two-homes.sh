#!/usr/bin/env bash
# E2E: two firstmate homes, each with its own clone of one origin, spawn real
# workers through real bin/fm-spawn.sh + real treehouse + real herdr (isolated lab
# session). TREEHOUSE_ROOT is one machine-wide base shared by both homes, which is
# the shape the secondmate reported. Usage: e2e-two-homes.sh <firstmate-checkout>
set -u
ROOT=$1
W=$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd -P)/fm-perhome-e2e.XXXXXX")
. "$ROOT/tests/herdr-test-safety.sh" 2>/dev/null && herdr_forget_inherited_pane 2>/dev/null
LAB="$ROOT/bin/fm-herdr-lab.sh"
[ -x "$LAB" ] || LAB="$NEWROOT/bin/fm-herdr-lab.sh"
S=$("$LAB" name fm-perhome-e2e) ; export HERDR_SESSION=$S
"$LAB" provision "$S" >/dev/null || { echo "lab provision failed"; exit 1; }
trap '"$LAB" teardown "$S" >/dev/null 2>&1; rm -rf "$W"' EXIT
export FM_GATE_REFUSE_BYPASS=1 TREEHOUSE_ROOT="$W/machine-treehouse"

git init -q -b main "$W/src"; echo base > "$W/src/README.md"
git -C "$W/src" add README.md; git -C "$W/src" -c user.name=t -c user.email=t@x commit -qm init
git clone -q --bare "$W/src" "$W/origin.git"
for h in A B; do
  mkdir -p "$W/home$h"/{state,data,config,projects}
  printf 'off\n' > "$W/home$h/config/herdr-presentation-spaces"
  git clone -q "file://$W/origin.git" "$W/home$h/projects/app"
done
spawn() { # home id
  local h=$1 id=$2 hd="$W/home$1"
  mkdir -p "$hd/data/$id"; printf '# Task\n## Captain'"'"'s intent\nx\n\n## Firstmate spec\ny\n' > "$hd/data/$id/brief.md"
  env -u TMUX -u FM_BACKEND HERDR_ENV=1 FM_HOME="$hd" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$hd/state" FM_DATA_OVERRIDE="$hd/data" FM_CONFIG_OVERRIDE="$hd/config" \
    FM_PROJECTS_OVERRIDE="$hd/projects" FM_SPAWN_NO_GUARD=1 \
    "$ROOT/bin/fm-spawn.sh" "$id" "$hd/projects/app" "sh -c 'echo worker-running; pwd -P'" --mode no-mistakes --yolo off 2>&1 | tail -3
  echo "fm-spawn exit=${PIPESTATUS[0]}"
}
teardown() { local hd="$W/home$1"
  FM_HOME="$hd" FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$hd/state" FM_DATA_OVERRIDE="$hd/data" FM_CONFIG_OVERRIDE="$hd/config" \
    "$ROOT/bin/fm-teardown.sh" "$2" >/dev/null 2>&1; echo "teardown $2 exit=$?"; }
report() { local hd="$W/home$1" m="$W/home$1/state/$2.meta" wt c
  [ -f "$m" ] || { echo "home $1 task $2: no task record published"; return; }
  wt=$(grep '^worktree=' "$m" | cut -d= -f2-)
  c=$(cd "$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)" && pwd -P)
  echo "home $1 task $2 worktree: ${wt#$W/}"
  echo "  backed by clone:       ${c#$W/}"
  [ "$c" = "$(cd "$hd/projects/app/.git" && pwd -P)" ] && echo "  => OWN clone of home $1" || echo "  => FOREIGN clone (not home $1's)"
}
echo "### step 1: home A spawns a1 (grows a pool slot from A's clone), then tears down (slot now FREE)"
spawn A a1; report A a1; teardown A a1
echo "### step 2: home B spawns b1 into its OWN clone of the same repo"
spawn B b1; report B b1
echo "### pool directories on disk"
find "$TREEHOUSE_ROOT" -maxdepth 4 -name 'treehouse-state.json' 2>/dev/null | sed "s|$W/||"
teardown B b1
