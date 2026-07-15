# Team Plan — {one-line goal}

meta:
- date: {YYYY-MM-DD}
- repo/branch: {branch} @ {sha}
- mode: waves | workflow | solo
- team-cap: {N ≤ 10}

## Advisor decisions
<!-- Manager applies advisor output here. Binding for all agents. -->
- D1: {decision} — {one-line rationale}

## Critical items
<!-- Task IDs that must return to the advisor before merge. -->
- {T#} — {why}

## Tasks
<!-- One block per task. Keep field names exactly — agents parse by heading. -->

### T1: {short title}
- status: pending | executing | in-review | fixed | approved | must-fix | deferred | cancelled
- wave: {1}
- depends: — | {T#, T#}
- owns: {exact file paths, comma-separated}
- goal: {verifiable outcome}
- done-check: `{command}` | {observable behavior}
- result: <!-- manager fills after review: verdict, reviewer findings that mattered -->

### T2: {short title}
- status: pending
- wave: {1}
- depends: —
- owns: {files}
- goal: {outcome}
- done-check: `{command}`
- result:

## Escalations log
<!-- Manager appends: {T#} — question → advisor decision (one line each). -->

## Integration
<!-- Filled by the integrator gate (integrator skill). Fix tasks get F# IDs, appended under ## Tasks. -->
- verdict: pending | GO | FIXED-GO | NO-GO
- rounds: {n}
- e2e: {what was run/driven}
- seam findings: {one line each, or none}
- fix tasks: {F# ids, or none}

## Retro (filled at end of run)
- tasks: {approved}/{total}, deferred: {ids or none}
- breakdown corrections by advisor: {count + one-line what}
- reviewer verdicts: {approve}/{fixed}/{must-fix}
- lesson: {one line}
