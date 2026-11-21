# Agent working rules (Coursefinder-Pilot)

Every agent working in this repository follows `CLAUDE.md` in full (G1 to G4, the consumer API freeze, housekeeping, automatic merging and the rest). This file repeats the standing mandate below so that agents that read `AGENTS.md` first see it.

### Standing Mandate: Immediate Live Activation (No Unrequested Shadow or Future Deferrals)

Platform Admin, 21 Nov 2026 10:07 AEDT. Non-negotiable; it applies to every change in both repositories.

1. **Reported Bugs & Verified Fixes Ship Live Immediately:** Every reported bug fix, UI/filter fix, parser fix, or verified deterministic admission rule MUST take effect **immediately upon deploy** in the same PR.
2. **Zero Unrequested Shadow Soaks or Delayed Cutovers:** NEVER place a bug fix or verified admission rule into shadow-only mode, behind an off-by-default flag, or on a 24-hour / next-day cutover timer unless the user explicitly instructs a shadow period first.
3. **No Assumed Future Work:** NEVER defer a reported fix to "tomorrow", "a future lane", or "a follow-up PR" without explicit user confirmation. Either ship and activate the complete fix immediately in the current PR, or—if a hard guardrail conflict exists—ask the user for an immediate decision before writing deferred code.

### Standing Rule: Dynamic Database-Driven Lookups (No Static Lists or Cut Subsets)

Platform Admin, 21 Nov 2026 11:55 AEDT (S1-Dynamic-Lookups, s930). It applies to every change in both repositories.

1. **Every dropdown, filter option, pill set and picker reads the live database.** Providers, destination and source countries, study levels, campuses, qualifications, grade scales, English tests and bands, and currencies come from the `ref` tables and the live rows (active and Layer 4 pending), never from a list written into the code.
2. **No inner-joined or cut subsets.** A provider list holds every active provider (and any provider with rows of the kind shown), whatever it already has admitted. A list is never cut by an unordered `limit`; a long list is searched or paged on the server.
3. **Rolling years.** Intake-year lists and year-rollover rules use the current year (Melbourne time) to the setting `lookups.intake_years_ahead`, beside the years the data holds. No year is written into a filter or a rule.
4. **Shared source.** Screens read `public.admin_lookups_v1` through `src/lib/lookups.js` (`useLookups`), or the screen's own server read; coverage figures in the guide are read live, never typed. Guard: `tests/uat/cf-247-s930-dynamic-lookups-contract.spec.mjs`.
