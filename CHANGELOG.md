# Changelog

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
