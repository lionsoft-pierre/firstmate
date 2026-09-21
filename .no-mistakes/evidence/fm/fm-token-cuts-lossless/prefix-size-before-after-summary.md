# Always-loaded prefix: measured before (base 43bf6d3) and after (target 854ae20)

Token estimates are chars/4 over the exact text a primary session receives. Each figure is reproduced from the artifacts beside this file.

| surface | before | after | how measured |
|---|---:|---:|---|
| AGENTS.md (R1 + R4 section 13) | 85,264 chars (~21,300 tokens) | 64,608 chars (~16,150 tokens) | `r1-inventory-moved-to-configuration.md` |
| skill descriptions, all `.agents/skills/*/SKILL.md` (R4) | 9,747 chars (~2,440 tokens), 21 skills | 3,866 chars (~970 tokens), 20 skills | `r4-skill-listing-before-after.md` |
| supervision block, Claude, as `bin/fm-supervision-instructions.sh` prints it (R3) | 3,964 chars (~990 tokens) | 2,820 chars (~705 tokens) | `r3-supervision-block-before-after.txt` |
| supervision block, Pi (R3) | 7,625 chars (~1,900 tokens) | 6,152 chars (~1,540 tokens) | `r3-supervision-block-before-after.txt` |
| read-once contract exception bullets (R3) | 7 | 3 | `r8-session-start-fleet-state-before-after.txt` |
| fleet-state digest, two-task fixture (R8) | 1,792 chars, wake-EVENT caveat x2, absolute log paths, pooled worktree printed | 1,705 chars, caveat x1 per section, home-relative log paths, pooled worktree omitted while a plain worktree stays | `r8-session-start-fleet-state-before-after.txt` |

Lossless checks that passed:
- All 100 removed AGENTS.md inventory entries have their path, every owning script or doc they referenced, and their never-touch / safe-to-delete / inherited phrasing present in `docs/configuration.md` "Operational home layout and state".
- AGENTS.md still states that a `state/<id>.status` line is a wake event, not current-state truth, and section 3 still treats an ABSENT marker as meaningful.
- The Claude block still carries drain-first, ack-after, and never-arm-manually; the Pi block still carries never shell `&`, the `fm_branch_processed` acknowledgement duty, and the verbatim regression example.
- `decision-hold-lifecycle` skill and `bin/fm-decision-hold.sh` are gone; no remaining reference outside "retired" notes and the legacy record recogniser in `bin/fm-captain-hold.sh`; `bin/fm-test-run.sh --changed` still resolves families after the table edit.
