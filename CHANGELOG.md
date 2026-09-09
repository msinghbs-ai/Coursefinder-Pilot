# Changelog

## [0.1.2] - 2026-09-09

### Changed
- Added Playwright global authentication setup for deployed UAT so authenticated browser state is captured once per run and reused through `storageState.json`.
- Kept all existing test files and assertions under `tests/uat/` unchanged; existing UAT helpers continue to enforce governed shell/role readiness and browser data access remains on the existing `public.admin_read` RPC path.
- Retained trace, screenshot, and video artifacts only on failure to reduce routine Playwright overhead.

### Security
- Added `storageState.json` to `.gitignore` so cached authenticated session material is not committed.
- UAT credentials remain environment-provided; no plaintext credentials or tokens were added to source.

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
