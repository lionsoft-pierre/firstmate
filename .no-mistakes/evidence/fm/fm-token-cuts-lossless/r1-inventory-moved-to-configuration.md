# R1: every removed AGENTS.md section-2 inventory entry names a path that docs/configuration.md now carries

Removed inventory lines checked: 100; entries whose path token(s) appear in docs/configuration.md at the target commit: 100

| removed inventory entry (truncated) | path present in docs/configuration.md |
|---|---|
| `AGENTS.md            this file (CLAUDE.md is a real @AGENTS.md pointer` | yes |
| `CONTRIBUTING.md      contributor workflow and repo conventions` | yes |
| `README.md            public overview and development notes` | yes |
| `.github/workflows/   shared CI and PR enforcement, committed` | yes |
| `.tasks.toml          tracked tasks-axi markdown backend config for the` | yes |
| `.agents/skills/      firstmate-loaded internal skills, committed; each` | yes |
| `.claude/skills       symlink to .agents/skills for claude compatibilit` | yes |
| `.claude/mods/        Claude Code mods (function-hooks plugins), commit` | yes |
| `skills/              standalone public installer-facing skills, commit` | yes |
| `bin/                 helper scripts, committed; read each script's hea` | yes |
| `.env                 optional Relay pairing token (presence-gates sect` | yes |
| `config/crew-harness  crewmate harness override; LOCAL, gitignored; abs` | yes |
| `config/claude-permission-mode  optional one-token permission posture f` | yes |
| `config/crew-dispatch.json  optional crewmate dispatch profiles; LOCAL,` | yes |
| `config/secondmate-harness  harness the PRIMARY uses to launch SECONDMA` | yes |
| `config/backlog-backend  backlog backend override; LOCAL, gitignored; a` | yes |
| `config/backend  runtime session-provider backend override for new task` | yes |
| `config/calm     Calm presentation preference shared by the Pi extensio` | yes |
| `config/supervision-branch-model config/supervision-branch-effort  Pi s` | yes |
| `config/startup-memory-budget     primary-authoritative per-home startu` | yes |
| `config/stow-pass-horizon  optional presence flag opting this home in t` | yes |
| `config/herdr-presentation-spaces  optional "off" opt-out from, or "on"` | yes |
| `config/trace-context  optional presence flag enabling default-off nati` | yes |
| `config/lavish-axi-host  optional one-line per-machine Lavish server ad` | yes |
| `config/brief-include.md  optional standing worker instructions appende` | yes |
| `config/turnend-churn-absorb  optional presence flag opting this home i` | yes |
| `config/wedge-defer-parked-gate  optional presence flag opting this hom` | yes |
| `config/cmux-socket-password  optional cmux control-socket password; LO` | yes |
| `config/wedge-alarm  optional away-mode wedge-alarm active-alert direct` | yes |
| `config/watched-tools.json  optional list of the tools this home depend` | yes |
| `config/x-mode.env    generated Relay watcher cadence; LOCAL, gitignore` | yes |
| `data/                personal fleet records; LOCAL, gitignored as a wh` | yes |
| `backlog.md         task queue, dependencies, history` | yes |
| `captain.md         this home's domain-local captain preferences and wo` | yes |
| `captain-shared.md  main-authoritative shared captain preferences propa` | yes |
| `learnings.md       fleet-local operational facts and gotchas; LOCAL, g` | yes |
| `projects.md        thin fleet navigation registry recording each proje` | yes |
| `secondmates.md      local and remote secondmate routing table; firstma` | yes |
| `<id>/brief.md      per-task crewmate brief, or per-secondmate charter ` | yes |
| `<id>/report.md     scout task deliverable, written by the crewmate; su` | yes |
| `projects/            cloned repos; gitignored; read-only except under ` | yes |
| `state/               runtime records and signals; gitignored` | yes |
| `<id>.status        append-only wake events, not current-state truth; b` | yes |
| `<id>.turn-ended    touched by turn-end hooks` | yes |
| `<id>.progress      touched for observed native-harness activity inside` | yes |
| `<id>.busy-state <id>.busy-gen   semantic busy-state record (one line, ` | yes |
| `<id>.grok-turnend-token   firstmate-owned grok hook registry token for` | yes |
| `<id>.kimi-turnend-token   firstmate-owned Kimi hook registry token for` | yes |
| `<id>.gemini-settings.json  firstmate-owned per-task Gemini settings ca` | yes |
| `<id>.muse-session  muse busy-source binding (sessions root plus task w` | yes |
| `<id>.cursor-session  cursor busy-source binding (projects root, task w` | yes |
| `<id>.reconcile-nudged  epoch second of the last inventory-reconcile nu` | yes |
| `<id>.backlog-close  the exact backlog transition a teardown recorded b` | yes |
| `<id>.inbox/          durable steering inbox: sequenced firstmate instr` | yes |
| `<id>.meta          task metadata; each producer script's header owns i` | yes |
| `<id>.herdr-presentation  quarantinable attempt and restart-binding jou` | yes |
| `<id>.check.sh      authenticated slow poll; the watcher dispatches val` | yes |
| `<id>.check-trust   private content binding created by fm-check-registe` | yes |
| `<id>.pr-poll       private validated data sidecar for the byte-static ` | yes |
| `<id>.pr-poll-registration  private transactional provenance record bin` | yes |
| `<id>.pr-poll-retirement  private identity-bound crash-recovery receipt` | yes |
| `<id>.merge-authority  private canonical-PR-bound authority persisted a` | yes |
| `<id>.pr-poll-merge-notified  canonical PR identity of the last merge o` | yes |
| `branch-outcomes.jsonl .branch-outcomes-cursor .branch-outcomes-process` | yes |
| `branch-session/ .branch-session .branch-mirror-cursor  the branch's pe` | yes |
| `.branch-eligible-rows .branch-eligible-owner .main-eligible-rows  per-` | yes |
| `.lease-<task>        per-task supervision lease naming which actor (ma` | yes |
| `x-watch.check.sh   generated Relay poll shim; present only when opted ` | yes |
| `tool-updates.check.sh  generated watched-tool update poll shim and its` | yes |
| `mail.check.sh      generated received-mail poll shim and its .check-tr` | yes |
| `.mail-seen .mail-woken .mail-retry .mail-retry-pos .mail-turn .mail-se` | yes |
| `pending-replies/   parent-owned secondmate pending-reply records (corr` | yes |
| `procevent/         registered process-to-event sources, one private re` | yes |
| `procevent-inbox/   private captured results and their durable handled-` | yes |
| `decision-bindings/ private records marking a captured-answer source as` | yes |
| `reconcile-requests/ private open obligations to re-check a captain cal` | yes |
| `when/              private condition->action watch specs, their trust ` | yes |
| `inbox/             captain notes captured out of band by bin/fm-inbox.` | yes |
| `x-inbox/           generated Relay pending mention payloads; fmx-respo` | yes |
| `x-context/         generated Relay durable per-request reply context a` | yes |
| `x-outbox/          generated Relay dry-run reply and dismiss previews;` | yes |
| `public-followup/   generated private transport for promised public rep` | yes |
| `x-poll.error x-poll.claim-error  generated Relay and offer-claim diagn` | yes |
| `.startup-network.*  status, report, per-step elapsed timings, inline-p` | yes |
| `.wake-queue        durable queued wakes retained until post-handling a` | yes |
| `.watcher-down      private generation-bound recovery state coupling wa` | yes |
| `.<id>.open-decisions-cursor  per-task byte cursor and folded open-deci` | yes |
| `.status-presentation-cursor .status-presentation-lock  fleet-wide per-` | yes |
| `.afk-contract      the away-posture record: the captain's verbatim awa` | yes |
| `afk-contracts/     archived away-posture records: one final record per` | yes |
| `.afk               durable away/quiet-mode daemon flag on the harnesse` | yes |
| `.lock-session      trusted Claude session-lock sidecar; written only b` | yes |
| `.watch.lock .wake-queue.lock watcher singleton and queue serialization` | yes |
| `.claude-autoarm.lock .claude-autoarm-epoch .claude-autoarm-failure-not` | yes |
| `.cursor-park-owner .cursor-park-owner.lock .turnend-cursor-blocks   Cu` | yes |
| `.hash-* .count-* .stale-* .stale-since-* .churn-since-* .paused-* .wed` | yes |
| `.watch-triage.log  watcher's absorbed-wake debug log (size-capped); ne` | yes |
| `.last-watcher-beat watcher liveness beacon, touched every poll (includ` | yes |
| `.subsuper-* .supervise-daemon.*   sub-supervisor internals; never touc` | yes |
| `.no-mistakes/        local validation state and evidence; gitignored` | yes |

AGENTS.md size: base 85264 chars (~21316 tokens) -> target 64608 chars (~16152 tokens)
docs/configuration.md at target has the section 'Operational home layout and state': yes
AGENTS.md at target keeps 'A state/<id>.status line is a wake event, not current-state truth': yes
