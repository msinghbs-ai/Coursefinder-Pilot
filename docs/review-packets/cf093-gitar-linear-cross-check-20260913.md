# CF-093 Gitar / Linear cross-check

Purpose: create a review-only pull request against the current Pilot main branch so newly enabled GitHub integrations can inspect the current CF-093 completion state without changing application/runtime behaviour.

## Current review target

Base main at PR creation: `9b450f9ebb48de70bdcdd409f24909ba39cc3a85`.

CF-093 remains open pending replacement consequential acceptance. Pilot PR #72 has already merged. The old acceptance evidence is superseded for closure purposes. The required replacement sequence remains governed UQ consequential acceptance, then RMIT, followed by deployed-currentness/UAT and authoritative governance reconciliation.

## Review questions

1. Identify any correctness, security, race-condition, stale-binding, dedupe, evidence-integrity, ACL/rank, or fail-open defect in the merged CF-093 implementation that could invalidate UQ/RMIT consequential acceptance.
2. Confirm generic asynchronous discovery remains fail-closed except for the specifically governed Preview-bound continuation path.
3. Check that historical unsuccessful discovery dispositions remain preserved as Evidence while still allowing bounded governed retry, and that terminal/resolved candidates are protected by exact Preview-token and identity freshness requirements.
4. Check scheduler/replay/dedupe behaviour for same-token replay and fresh-preview dedupe, including cancelled, failed, candidate, ambiguous, identity-mismatch and current-page-not-found outcomes.
5. Check that no generic Layer 3/Layer 4 auto-approval or implicit Search/Publication side effect is introduced by the CF-093 path.
6. Check current GitHub Actions acceptance/dispatcher logic for a way a green workflow could be recorded without the intended authenticated Preview -> Run now -> discovery continuation -> deterministic Layer 2 -> Jobs/Evidence assertions actually executing.
7. Flag any issue that should block UQ acceptance now. Separate blocking defects from suggestions.

## Change scope

This file is documentation only. It intentionally makes no application, database, migration, workflow, runtime, security-policy or release change. Do not treat this PR itself as acceptance evidence or as permission to weaken existing governance.

## Integration cross-check

Gitar: please perform code/repository review using the current PR and repository context, with emphasis on the questions above.

Linear: if the installed GitHub integration provides issue/PR linkage or context on this repository, expose/link relevant existing work where available. Do not create or infer a new issue identifier solely from this review packet.
