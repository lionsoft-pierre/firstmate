# Round 2: targeted suites run to completion (FM_HOME, FM_TASK_ID, HERDR_ENV unset)

Command shape: `env -u FM_HOME -u FM_TASK_ID -u HERDR_ENV bin/fm-test-run.sh <suite>`
Commit: 854ae20 (branch fm/fm-token-cuts-lossless)

| Suite | Passed (`ok -`) | Failed (`not ok`) | Exit | Duration |
|---|---|---|---|---|
| tests/fm-session-start.test.sh | 55 | 0 | 0 | 414.9 s |
| tests/fm-captain-hold-lifecycle.test.sh | 53 | 0 | 0 | 526.1 s |
| tests/fm-bearings-board.test.sh | 18 | 0 | 0 | 86.0 s |
| tests/fm-harness-adapter-references.test.sh | 1 | 0 | 0 | 0.2 s |
| tests/fm-test-run.test.sh | 39 | 0 | 0 | 284.1 s |

Runner exit codes: session-start run EXIT=0; captain-hold run EXIT=0; batch (bearings-board + adapter-references + test-run) run EXIT=0.

The R8 digest case passed inside session-start:
`ok - the fleet-state section states the wake-EVENT caveat once and omits only a pooled worktree path`

Note: session-start (family session-bootstrap) ran concurrently with the other two runs; it passed, so no serial rerun was needed.

## Verification pass (same commit, same env)

- The batch log interleaves the three batch-B suites, so per-suite counts were re-derived: total `ok -` lines in `fm-r2-batch-b.log` = 58 = 39 (test-run) + 1 (adapter-references) + 18 (bearings-board). The earlier table row said 19 for bearings-board; corrected to 18.
- `tests/fm-bearings-board.test.sh` re-run standalone: 18 `ok -`, 0 `not ok`, exit 0, 54.3 s (`fm-r2-bearings-board-standalone.log`).
- `tests/fm-harness-adapter-references.test.sh` re-run standalone: 1 `ok -`, 0 `not ok`, exit 0, 0.1 s.
- Every suite log ends with an `FM_TEST_END ... exit=0` line and contains zero `not ok` lines; all runs finished after commit 854ae20 was created (11:23 local).

Corrected totals: 55 + 53 + 18 + 1 + 39 = 166 passing cases, 0 failures, 5 suites, all exit 0.
