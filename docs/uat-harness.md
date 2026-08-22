# CourseFinder UAT Harness v1.0

## Purpose

The harness replaces routine screenshot-driven regression with repeatable Playwright browser acceptance while preserving normal Supabase Auth, CourseFinder role checks and the Evidence private boundary.

Human UAT remains for wording, information hierarchy and visual/semantic judgement. Deterministic navigation, counts, paging, drill-down and unexpected HTTP 5xx detection are automated.

## Release stages

### 1. Pull-request gate

`.github/workflows/pim-build.yml` performs:

1. Node 22 install;
2. dependency install;
3. production Vite build;
4. Chromium install;
5. unauthenticated local browser smoke;
6. upload of Playwright report/runtime evidence.

The local smoke uses placeholder public Supabase configuration only to render the unauthenticated login shell. It does not authenticate and does not bypass production security.

### 2. Deployed acceptance gate

`.github/workflows/deployed-uat.yml` is manually dispatched against an HTTPS deployed URL, defaulting to:

`https://coursefinder-pilot.techm.workers.dev`

It runs desktop and mobile Chromium projects with a normal CourseFinder UAT identity.

Required GitHub Actions repository secrets:

- `COURSEFINDER_UAT_EMAIL`;
- `COURSEFINDER_UAT_PASSWORD`.

Do not commit these values or paste them into test source. The UAT identity must be a normal Supabase Auth user with the minimum CourseFinder role required by the test. The current Evidence critical path requires Curator rank 3 or higher.

## Current governed fixture

`tests/uat/expectations.json` records accepted CF-CHG-018 values, including:

- AU Courses: 26,648;
- AU+NZ Courses: 33,105;
- all-country Courses: 43,461;
- regulatory fee present: 26,326;
- source-null: 191;
- not-applicable: 6,457;
- zero: 131;
- readiness: 99.28%.

These are governance fixtures, not auto-updated snapshots. A legitimate changed count must be investigated and accepted before changing the fixture.

## Deployed critical path

The initial suite proves:

`Login → Data Quality → Regulatory fee → Course → Source-null → 191 records → pages 1–4 → canonical Course → Evidence Regulatory Snapshot`.

It explicitly checks the deployed `evidence_id` route that was browser-proven during CF-CHG-018.

## Evidence output

Each workflow uploads:

- `playwright-report/` — HTML report;
- `test-results/` — Playwright traces/videos/screenshots retained according to config;
- `uat-artifacts/results.json` — machine-readable results;
- `uat-artifacts/junit.xml` — CI/JUnit results;
- `uat-artifacts/environment.json` — run/base URL/commit metadata;
- `uat-artifacts/*-runtime.json` — captured 4xx/5xx and browser console/page errors;
- explicit milestone screenshots from the deployed critical path.

Unexpected HTTP 5xx responses fail the deployed test even if the final screen eventually renders. This addresses the transient-timeout visibility gap observed during manual CF-CHG-018 UAT.

## Local commands

```bash
npm install
npx playwright install chromium
npm run test:uat:smoke
```

For deployed acceptance, set `UAT_BASE_URL`, `UAT_EMAIL` and `UAT_PASSWORD` in the local process environment and run:

```bash
npm run test:uat:deployed
npm run test:uat:deployed:mobile
```

Do not store credentials in `.env` files committed to the repository.

## Security rules

- no service-role browser credentials;
- no auth bypass/test-only production endpoint;
- no role spoofing;
- no committed Playwright storage state containing tokens;
- no direct private Storage URL exposure;
- no automatic fixture update after a failure;
- no generic production mutation/retry/reset action as part of UAT.

## Governance

Primary control:

`CF-CHG-20260822-019 — M1 UAT Harness automated operational acceptance`.

The harness validates accepted product semantics. It does not redefine them.