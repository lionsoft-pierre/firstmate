Mode: Cursor stop-hook-owned park.

When this session owns supervision and away mode is not active:
1. Drain first with `bin/fm-wake-drain.sh`.
   After handling all emitted wakes and reconciling open decisions, run the exact `--ack-through` command printed as `WAKE_ACK_REQUIRED`; until then the work remains durable for idempotent re-handling after interruption.
2. Routine watcher arm and re-arm are owned by the `stop` hook (`bin/fm-turnend-guard-cursor.sh`), never by you.
   Cursor runs that hook synchronously and awaits it, so every turn end while supervision is needed parks the turn boundary open on one home-scoped watcher cycle, with no model command and no model tokens spent while parked.
3. An actionable close wakes you as a follow-up turn carrying the `watcher` operational kind.
   On that wake, run `bin/fm-wake-drain.sh` first and handle it.
   Do not run `bin/fm-watch-arm.sh` after an ordinary wake; the next turn end parks again automatically when supervision is still needed.
   Do not invent a wake from an attach-status line alone; drain and act only on real wake records, the drain's `OPEN DECISIONS` entries, or a real watcher reason line.
4. The captain keeps control while the hook is parked: a message typed into a parked Cursor pane runs its turn immediately, and an actionable close in that window still arrives as one real follow-up wake.
5. On a `turn-end-guard` follow-up, the park could not establish a live cycle.
   Inspect the watcher startup path rather than turning the notice into a repeating manual-arm loop; the nag is bounded by `FM_CURSOR_TURNEND_BLOCK_BUDGET` (default 3) and then stops on its own.
6. Waiting on the hook-owned park is silent: do not send idle progress while the watcher is parked.

The watcher itself remains `bin/fm-watch.sh`, and `bin/fm-watch-arm.sh` remains the verified arm wrapper that the `stop` hook runs as its own tracked child.
[`watcher-continuity.md`](../watcher-continuity.md) owns the arm layer, its successor chain, the durable wake queue between follow-up and park, and the session-lock recovery boundary.
[`turnend-guard.md`](../turnend-guard.md) owns the park's supersession contract and records (`state/.cursor-park-owner` and its lock), the bounded follow-up that stands in for a blocked turn end, the Pi-host stand-down, the deferred `beforeSubmitPrompt` and `preCompact` registrations, and the compatibility limits, including that a Cursor primary must be launched with `--trust` for its project hooks to load at all.
