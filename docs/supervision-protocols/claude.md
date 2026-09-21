Mode: Claude Stop-hook-owned supervision.

When this session owns supervision and away mode is not active:
1. Drain first with `bin/fm-wake-drain.sh`.
   After handling all emitted wakes and reconciling open decisions and unread status lines, run the exact `--ack-through` command printed as `WAKE_ACK_REQUIRED`; until then the work remains durable for idempotent re-handling after interruption.
2. Routine watcher arm and re-arm are owned by the Stop `asyncRewake` hook (`bin/fm-claude-stop-autoarm.sh`), never by you.
   Every turn end while supervision is needed launches or attaches one home-scoped watcher cycle with no model command and no model tokens.
   An actionable close wakes you through the hook's exit-2 rewake, delivered as a `Stop hook feedback` message.
3. On a `Stop hook feedback` wake (`signal:`, `stale:`, `check:`, or `heartbeat`), run `bin/fm-wake-drain.sh` first and handle the wake.
   Do not run `bin/fm-watch-arm.sh` after an ordinary wake; the next turn end re-arms automatically when supervision is still needed.
   Do not invent a wake from an attach-status line alone; drain and act only on real wake records, the drain's `OPEN DECISIONS` and `UNREAD STATUS` entries, or a real watcher reason line.
4. On the one `Stop hook feedback` automatic-mechanism failure notice (`firstmate watcher auto-arm FAILED ...`), drain, inspect the automatic mechanism failure, and do not turn the notice into a repeating manual-arm loop.
5. If the Stop hook does not claim the home or reports an exhausted failure, inspect its registration and watcher startup path before ending blind.
   Keep the Stop-owned automatic mechanism as the only Claude arm owner.
6. Waiting on the hook-owned cycle is silent: do not send idle progress while the watcher is parked.

The watcher itself remains `bin/fm-watch.sh`, and `bin/fm-watch-arm.sh` remains the verified arm wrapper that the Stop hook foregrounds.
[`watcher-continuity.md`](../watcher-continuity.md) owns the arm layer, its successor chain, the durable wake queue between rewake and re-arm, and the session-lock recovery boundary; [`turnend-guard.md`](../turnend-guard.md) owns the turn-end guard backstop (`bin/fm-turnend-guard.sh --claude`) and its predicates.
