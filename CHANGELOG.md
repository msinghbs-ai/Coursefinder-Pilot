# Changelog

## [0.1.2] - 2026-09-09

### Changed
- Added a one-time Playwright global authentication setup for deployed UAT and configured all tests to reuse the resulting `storageState.json` session state.
- Retained trace, screenshot, and video evidence only when tests fail to reduce routine Playwright execution overhead.
- Documented opt-in `@smoke` tagging and the `npx playwright test --grep "@smoke"` fast-path command without modifying existing UAT test files.
- Added a three-runner GitHub Actions UAT matrix using Playwright native `--shard=1/3`, `2/3`, and `3/3` execution.
- Added npm download-cache and Playwright browser-cache restoration to reduce repeated CI setup overhead.
- Added a PR release-governance gate that requires a package version bump and matching CHANGELOG release entry for governed UI/code/UAT orchestration changes.
- Added a manual production deployment matrix with AU, UK, US, and CA country gates backed by separate GitHub Environments.

### Security
- Added `storageState.json` to `.gitignore` so authenticated browser state cannot be committed accidentally.
- Kept UAT credentials environment-only and preserved existing browser data-access routing; no direct catalogue/PIM browser data path was introduced.
- Passed UAT credentials to CI only through GitHub Actions secrets and the UAT target through repository/environment variables.
- Audited `catalogue.provider_assets.storage_path` and `pipeline.evidence_artifacts.storage_path`; populated values are relative storage references with no HTTP/S, object-store scheme, or root-absolute environment-bound paths.
- Verified the browser Supabase client uses only environment-provided `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`; database integration configuration stores Vault IDs or secret names/environment-key references rather than plaintext secret values.
- Production deployment consumes environment-scoped Supabase/Cloudflare configuration and GitHub secret-backed deployment credentials with fail-closed validation.

## [0.1.1] - 2026-09-08

### Changed
- Migrated the governed Supabase browser boundary from `src/lib/supabase.js` to `src/lib/supabase.ts` with TypeScript contracts while preserving all browser reads through `public.admin_read`.
- Retained the existing incremental TypeScript, ESLint, and Vitest guardrails without changing catalogue layouts or database migrations.

### Added
- Added a lightweight `DynamicAttributeSection` for self-describing long-tail PIM metadata already returned by governed course-detail payloads.

### Fixed
- Kept course code, study level, fees, intakes, and English requirements on the existing relational Course detail path and excluded them from dynamic PIM rendering.
- Preserved relational-only fallback for unassigned entities or payloads without renderable PIM values, with no secondary browser reads for PIM definitions or options.
- Updated source-contract references for the typed Supabase boundary as part of the validation hardening pass.
- Kept deployed PR acceptance explicitly bounded/read-only so routine validation cannot trigger ranking imports, acquisition jobs, or other state-changing UAT flows.

### Database
- No existing SQL file under `supabase/migrations/` was modified by this release.