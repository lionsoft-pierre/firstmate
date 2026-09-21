Mode: OpenCode TUI plugin background wake.

When this session owns supervision and away mode is not active:
1. Drain first with `bin/fm-wake-drain.sh`.
   After handling all emitted wakes and reconciling open decisions and unread status lines, run the exact `--ack-through` command printed as `WAKE_ACK_REQUIRED`; until then the work remains durable for idempotent re-handling after interruption.
2. First cycle: let `.opencode/plugins/fm-primary-watch-arm.js` arm supervision after the OpenCode session goes idle; it owns every later successor launch and the follow-up wake after an actionable close.
3. Ordinary wake: do not ask the model to re-arm because continuity is plugin-owned.
4. Failure or missing cycle only: if the plugin reports a watcher failure, drain queued wakes, inspect the failure text, and use `bin/fm-watch-arm.sh` manually only as a short recovery probe.
5. Never use shell `&` for watcher supervision.
   The arm mechanism above is plugin-owned, not a model tool call, but a manual recovery probe that backgrounds, pipes, or bundles the arm is denied automatically by the PreToolUse seatbelt (`.opencode/plugins/fm-primary-pretool-check.js`, `bin/fm-arm-pretool-check.sh`).
6. Do not rely on this plugin in headless `opencode run`; firstmate primary supervision targets persistent OpenCode TUI sessions.

OpenCode's persistent TUI plugin runtime is the wake mechanism; the plugin and [`watcher-continuity.md`](../watcher-continuity.md) own its successor verification, bounded retry, and watcher-failure surfacing.
The plugin applies in the main primary checkout and a secondmate's own home, and stays silent only in child crewmate and scout worktrees.
