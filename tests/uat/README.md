# Active UAT suite

`tests/uat/` is the current routine CI/UAT discovery surface.

Only tests suitable for normal validation belong here. In particular, routine UAT must not trigger ingestion, acquisition, ranking import/apply, scheduler execution, or other governed backend mutations.

Historical, superseded, milestone-specific, or state-changing suites are retained under `tests/retired-uat/` and are excluded from Playwright discovery because `playwright.config.mjs` scopes `testDir` to `./tests/uat`.

Current release baseline: UI `2.15.74`, package `0.1.1`.
