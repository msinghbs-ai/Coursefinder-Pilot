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

### Standing Rule: Self-Sustaining API & Key Governance (Independent Keys per Consumer and Version)

Platform Admin, 21 Nov 2026 13:11 AEDT (S1-RM-Design, s935). It applies to every change in both repositories.

1. **One key per (consumer, API version).** Every new API version, consumer endpoint, or key issue or rotation uses its own key, scoped to one consumer and one version. A key is never shared across versions or consumers. A new version signs in with `pipeline.api_key_auth_v1(platform, version, hash)` and logs with `pipeline.api_request_log_v1`, so its calls carry its own version and key.
2. **Registered in the database, shown with no screen change.** A new version is a row in `pipeline.api_versions` (platform, version, endpoint, key store, frozen), and its keys are rows in its key store (`private.api_keys`). Settings › API usage reads `public.admin_api_usage` › `versions` (`security.api_usage_versions_v1`): every version, each key's status (Active, Rotating / Grace, Not issued, Revoked), its masked prefix, created, rotated and last-used dates, and live 24 h / 7 d / 30 d usage (calls, 2xx, 4xx, 5xx, error rate, 95th-percentile time). A version or key the register does not name yet is listed too, marked "not registered". No version, key or count is written into the screen.
3. **Rotation without disruption.** Keys rotate with a dual-key overlap (`api.key_rotate_overlap_hours`): the new key is shown once; the old key keeps working as the previous key until the overlap ends. A new version's key starts "Not issued". Where a consumer already calls that version with an earlier version's key, that key works as its previous key for `api.new_key_bridge_days`, until the new key is issued.
4. **Guard.** `security.api_usage_coverage_v1()` lists any active registered version or key the read path misses; each change that adds one checks that it is empty. `tests/uat/cf-247-s935-api-usage-versions-keys-contract.spec.mjs` fails the build otherwise. A frozen version (G3) keeps its own sign-in; it is registered and shown, never changed.

### Standing Rule: Attributed Public Rankings (THE, ARWU and QS)

Platform Admin, 22 Nov 2026 09:22 AEDT (IR-005, RM1J): "We can attribute and use both Times Higher Education (THE) and QS World University Rankings directly. Do NOT gate them behind a manual publisher file upload or a terms = restricted hold." Amended 22 Nov 2026 14:22 (IR-011): QS stays on the annual file upload, and ARWU is the third ranking.

- **How each ranking arrives:**

  | Ranking | How it arrives |
  |---|---|
  | THE World University Rankings | Automated Layer 1 reader of the public ranking JSON (`ranking-layer1-etl`) |
  | ARWU (Academic Ranking of World Universities, ShanghaiRanking) | Automated Layer 1 reader of the public ShanghaiRanking ranking API |
  | QS World University Rankings | Annual file upload in Administration › Sources & Imports (Rankings & statistics › Datasets › Ranking imports) |

- The automated readers use a plain HTTP GET. robots.txt and its crawl-delay are honoured. No Firecrawl, browser automation or AI is used, so the spend is $0.
- QS's public endpoint answers the platform with a bot challenge. It is never read automatically. No proxy, alternative route or challenge bypass is ever used for it, or for any other site.
- **Publishing:**
  - Each edition is published with its attribution (`ranking.editions.licensing_note`) and its source page. No `terms = restricted` hold or draft step is needed.
  - An edition read by a reader is held while it loads and published live as soon as it is complete. An uploaded file is applied when it is checked.
  - The Platform Admin publishes an edition, or unpublishes it to roll back, with a reason, on Rankings & statistics › Datasets › Ranking editions (`public.admin_ranking_editions_v1`, logged in `ranking.edition_status_changes`).
- **Matching:** institutions are matched to providers deterministically:
  1. accepted mappings;
  2. ranking aliases;
  3. the normalised name with its country;
  4. one part of the provider's register name ("A/B", "X, including Y"; a leading "The" and a trailing country are ignored), with exactly one provider matching.

  Rows that still match no provider are listed for review and never fail the run.
- A challenge page is reported and never bypassed. The edition already held stays live.

### Standing Rule: Continuous Delivery Master Plan (Read at Start, Update Before Parking)

Platform Admin, 21 Nov 2026 21:15 AEDT (S1-API-Frontend-Delivery). It applies to every session in both repositories.

1. **Read it at start.** Every session reads `docs/platform/CONTINUOUS-DELIVERY-MASTER-PLAN.md` in the admin repository (`msinghbs-ai/coursefinder-admin`) after `docs/CURRENT-STATE.md`, finds its lane, and keeps to that lane's touch boundaries. A session not named in the plan asks the Platform Admin which lane it is in before changing anything.
2. **Follow its order.** Work the lane's items in the order the plan gives. Work found for another lane is written into the plan for that lane, not done.
3. **Update it before parking.** Before parking, the session updates its lane's status table and adds a line to the plan's status log, in the same admin pull request that records the release, then refreshes the Google Drive copy (`M3 / CONTINUOUS-DELIVERY-MASTER-PLAN.md`). The repository file is the source of truth; the Drive copy is a mirror.
