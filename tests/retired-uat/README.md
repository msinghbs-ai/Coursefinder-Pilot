# Retired UAT suites

This directory preserves historical, state-changing, superseded, or milestone-specific acceptance suites that must not be auto-discovered by the default Playwright UAT command.

## Policy

- `tests/uat/` contains the current safe/read-only regression and release-readiness acceptance surface.
- Tests that trigger ingestion, acquisition, ranking import/apply, scheduler execution, Layer 1–3 operational workflows, or other governed backend mutations belong here and must be run only under an explicitly authorised recovery/acceptance procedure.
- Superseded source contracts remain here for audit history instead of blocking current acceptance with obsolete version or implementation assertions.
- A retired test may return to `tests/uat/` only after it is reconciled to current runtime semantics and proven safe for routine CI discovery.

Retired during the post-2.15.74 UAT cleanup on 2026-09-09. The accepted baseline before this cleanup was main commit `0950d3a7ee7380d8846db49ccea504cbe8a02c50`.
