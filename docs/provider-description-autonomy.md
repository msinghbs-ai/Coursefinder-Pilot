# Provider Descriptions — Run & Validate

Development branch: `codex/provider-description-autonomy`. Authority: Platform Admin's 4 November 2026 Codex Cloud mandate; canonical admin record `docs/platform/nz-enrichment-brief/2026-11-04-provider-description-autonomy-mandate.md`, extending the 2 November missing-field mandate. Claude remains the sole Integration Controller. This branch assigns no release and performs no deployment, production write or vendor call.

## Architecture and authority

The existing `provider-description-read` job and `coverage-sweep` mode remain the reader. The existing evidence artefacts, pinned Enrich fields model, shared AI controls, read ledger and individual Layer 4 description decision remain authoritative. The Admin card stays in Layer 2 → Enrich fields; the old retry-only controls are replaced in place. The new typed Run Now adapter uses the existing `job_run_now` task kind, registered outcome codes, catalogue permissions, shared Run Now allowlist and caps, audit events and existing reader fire function. It does not modify the intake-only shared dispatcher owned by the Integration Controller. The feature is rebased onto current main `9d907cff` (PR #872, v2.15.478); that upstream release number is inherited, not assigned by this branch.

The migration does **not** add the reader to `pipeline.run_now.jobs` (changed 5 Nov: nothing switches itself on). Run & Validate previews and saves cohorts; Run parks with `job_not_allowlisted` until `provider-description-read` is added to Run now after deployment and role verification (Platform Admin decision 5 Nov 2026 20:03 §1; exact change in "Release readiness" below). It does not alter eligibility, acquisition, spending or admission authority. It adds no scheduler or approval route. The saved cohort binds requester, reason, exact providers, source versions and run reference; repeat requests recover the same task. Source or identity changes invalidate selection before processing. Stored-only cohorts cannot enable acquisition.

Every new description still requires its applicable individual human Layer 4 decision. Bulk approval and AI authorisation remain unavailable. Apply-time guards recheck scope, lifecycle, identity, evidence lineage, factual validation, unchanged catalogue value and manual locks. Review-capacity work is parked and resumed through the existing scheduled reader without paying to read unchanged evidence again. Publication is checked separately from admission against the existing consumer projection.

The worker keeps final redirect addresses, validates the full current institutional identity, preserves whole claims and quotations, and holds unsupported numerical, historical and long verbatim claims. The prompt and approved model remain unchanged; source-validation behaviour has its own recorded version. Before a paid AI call, conservative pricing bounds for that exact model are reserved inside the existing lifetime and daily caps. Unknown charges retain their reservation until reconciled. No limit is increased.

AI diagnosis reuses the existing operations diagnosis lane only when its approved switch, model, permissions, budget and an exact existing provider/evidence-linked issue permit it. Otherwise the screen gives a saved deterministic evidence explanation with the precise limitation. An explanation cannot authorise admission or change settings.

## Claude reconciliation, 5 November 2026 (ownership transferred by Platform Admin decision 19:14)

Codex Cloud is discontinued; this PR is owned by Claude agent B and integrated, not rebuilt.

- **Migration renumbered** to `20261106200000_cf247_provider_description_autonomy.sql` (reserved range 20261106200000–299999); workflow fixtures, scripts, evidence and component register rows follow.
- **Main merged** (`cf77ef78`, v2.15.485; merge, no rebase). None of v2.15.479–485 changed a function this PR guards.
- **Workers Builds** failed by design (the branch build guard threw on `WORKERS_CI_BRANCH`); the guard is removed.
- **Course descriptions protected.** `descriptionSentences` is shared with the course-description reader (`course-text.ts`). The exact-source quote match is now a separate `providerDescriptionSentences`, used only by the provider-description mode; `descriptionSentences` is byte-identical to main.
- **Run Now allowlist** is no longer written by the migration (see above).
- **Live re-read (5 Nov, read-only):** all six replaced functions still have their 4 Nov before-hashes; every captured live fixture function matches production. `security.job_run_now_v1` is `2640319b…` live, which is the hash the fixture reaches after applying main's `20261104640000` correction. Production is PostgreSQL 17.6, the qualified version.
- **Live settings differ from the 4 Nov narrative:** `pdesc.enabled` 1, `pdesc.acquire_direct` 1, `pdesc.acquire_firecrawl` 1 (`pdesc.firecrawl_reads_max` 20). The scheduled reader therefore runs in the existing approved-acquisition mode; this PR adds no acquisition authority and saved Run & Validate cohorts default to stored-only.
- **Layer 4 ownership:** `layer4_provider_description_apply_impl` now requires an active rank-4 role (Pipeline Operator). This matches the existing Layer 4 Inbox (`admin_layer4_inbox` requires rank 4 for a choice unless the choice names a higher one) and closes the rank-3 route through `layer4_review_decide`. Approved by the Platform Admin 5 Nov 2026 20:03 §3.

## Release readiness (Platform Admin decisions 5 Nov 2026 20:03)

Recorded verbatim in admin `docs/platform/2026-11-05-intake-milestone-pr877-pr889-decisions-2003.md`.

### §2 Evidence-aware campus, scholarship and guarantee validation

"Do not reject legitimate supported claims solely by keyword." The words have their own provider-only list, `pipeline.pdesc.evidence_claim_words` (`["campus","scholarship","guarantee"]`, label, unit and `used_by` on Settings). **`pdesc.claim_words` is not changed**: `security.course_description_check_v1` (course descriptions; live md5 `ff3d6dd7…`) also reads it, so course descriptions keep their behaviour.

A word in the list never holds a sentence on its own. It triggers `security.pdesc_claim_check_v1(sentence, quote, word)`, a bounded extension of `pdesc_has_term_v1`:

- The sentence does not use the word or a form of it (plural or tense: campus/campuses, scholarship/scholarships, guarantee/guarantees/guaranteed) → no effect.
- The sentence's own quote uses the same word or a form of it → supported. That quote has already been proved, character for character, to be on the stored official page.
- The quote does not contain it → held `unsupported_claim`.
- The quote negates it ("does not guarantee", "no guarantee", "can't guarantee") and the sentence does not → held `claim_negated_in_source`.

The sentence must still pass the existing `pdesc_support_v1` share, the `pdesc_similarity_v1` duplicate checks and every other rule. Tested in `tests/fixtures/provider-description-autonomy/claim-policy.mjs` against the real validator:

- supported campus claim: passes;
- unsupported campus claim: held;
- supported scholarship mention: passes;
- unsupported guarantee: held;
- non-claim use ("advances maritime scholarship"): passes;
- negated guarantee: held;
- negation kept as stated: passes.

**Independent validation, 5 Nov 2026** (admin `docs/platform/validation/2026-11-05-pr877-provider-descriptions-validation.md`). Three more rules were made evidence-aware, with every case in `claim-policy.mjs`:

- **`historic_claim_context`** holds only when the present-tense part of the quote does not support the sentence (`security.pdesc_present_support_v1`; clauses with became, merged, formerly and similar words are left out).
  - Passes: "became …; today offers more than 300 courses" and "formed when two colleges merged, it is a public research university".
  - Held: "formerly operated a campus in Gippsland, which closed".
- **`unsupported_numeric_claim`** compares numbers after `security.pdesc_number_norm_v1`: thousands separators, "per cent" and the quote's number words up to ninety-nine.
  - Passes: 80,000 against 80 000; 4 against four; 25% against twenty-five per cent.
  - Held: 90,000, 5 and 35% against the same quotes.
- **Negation:** "no matter which" and "not only" are not negations. "none" and "neither" are.
  - Held: "none of our campuses" against a campus claim.
- **The worker** (`descriptionClaimCheck`) now checks only long copied passages. Numbers and historic context are decided once, by the database validator.

### §3 Rank 4 for provider-description approval: regression tests (`integration.mjs`)

- **Rank 3 refused on every approval route:** `layer4_review_decide`, `layer4_review_decide_impl`, `admin_layer4_inbox('decide')` and batch. Batches never admit provider descriptions at any rank (`one_at_a_time`).
- **Ranks 4 and 5 approve:** rank 4 (Pipeline Operator) and rank 5 (`pim_admin`, the production code) approve, inside a rolled-back transaction.
- **Read-only roles unchanged:** rank 1 (`viewer`) and rank 2 keep no decision right and no Inbox access, as before.
- **Other kinds unchanged:** the nine functions that set their rank are byte-identical before and after the migration (decide, decide_impl, Inbox, batch, the entry-matrix, course-entry and no-page apply functions, AER kinds, `current_role_rank`). AER still needs rank 6, and rank 3 still decides `scholarship scope_resolution`.
- **Unchanged nuance:** a rank-3 curator can still **reject** a provider description through the direct `layer4_review_decide` RPC, because rejection never runs `apply_impl`. The Inbox needs rank 4 for both choices.

### No automatic admission

`catalogue.providers.description` is written in this feature only by `security.layer4_provider_description_apply_impl`. That function is executable only by `postgres` and is reached only from an individual `layer4_review_decide_impl` approval; batches skip provider descriptions. Live check, 5 Nov: the auto-admit functions (`no_page_auto_admit_v1`, `no_page_sample_check_v1`) do not touch provider descriptions. The scope (5 AU university keys) and the US$1 lifetime and US$1 daily limits are unchanged and are not written by the migration.

### Deploy order (Integration Controller)

`deploy-on-merge` applies the migration and then deploys the edge functions automatically when the PR merges. So the pause in step 1 comes **before the merge**.

1. **Before merging:**
   - Re-check the six before-hashes on production.
   - Pause `provider-description-read` with a reason, through the existing job control. Or set `pdesc.enabled` to 0 with a reason.
   - Let any open lease finish or expire (20-minute claim timer).
2. Merge. `deploy-on-merge` then:
   - applies `20261106200000_cf247_provider_description_autonomy.sql` (its after-hash check refuses a partial apply);
   - deploys the complete `supabase/functions/coverage-sweep/` folder;
   - releases the UI.
3. Confirm the deployed worker leases with `svc_provider_description_lease_v1`.
4. Resume `provider-description-read`, or restore `pdesc.enabled`, to its previous state.
5. Verify roles on production: a rank-4 user can approve, and a rank-3 user is refused.
6. Then turn on Run Now, as below.

**Mismatch windows.**

- **New worker against the old database.** The worker asks for `svc_provider_description_lease_v1`, which does not exist yet. It gets an error, takes no item and makes no AI call.
- **Old worker against the new database.** The old worker leases with `svc_provider_description_next(p_limit)` and never reserves. Since 5 Nov, that call returns `worker_protocol_required` with no items when the caller is a service-role worker that has not declared the reservation protocol. So the old worker gets nothing to read and makes no paid call.
- **The pause still comes first.** It is the primary control. The lease gate is a second line of defence.

### Website feed: the existing scan is the only writer (Integration Controller decision, 5 Nov 2026)

This feature does **not** write `pipeline.website_sync_items`. The immediate single-provider refresh (`provider_description_sync_provider_v1`) has been removed, together with its calls from the publication check and from Verify.

**After a Layer 4 approval:**
1. The approval updates `catalogue.providers.description`. Nothing else changes.
2. The existing job `website-sync-check` (`security.website_sync_check_v1`, every minute, live md5 `f8095625…`) builds the provider item with `website_sync_item_v1`. It finds the hash changed and writes the item with a new sequence, as it does for any catalogue change. Zoho and the Website then serve it.
3. **Verify and the scheduled publication check only read back.** Until the scan reaches the provider, Zoho can show the stale prepared item. That is reported as `mismatch`, never as published.

**Fixture proof** (`integration.mjs`, `negative.mjs` and the browser spec):

- The live `website_sync_check_v1` and `website_sync_candidates_v1` are copied into `live/` and md5-checked against `production-website-sync.json`, together with the production `website_sync_scan` table.
- After ten approvals, one pass of the scan writes each approved description as a changed item: new sequence, hash correct. A second pass changes nothing. Zoho and Website read-back then verify all ten.
- The publication verifier alone leaves a stale feed item untouched.

### Post-deploy Run Now setting (§1), through the existing settings mechanism

Screen: Settings › Pipeline settings, register section "Run now" (`SettingsRegister.jsx` → `public.admin_toolsets_write`, rank 6, reason required, audited in `pipeline.admin_control_events`).

- Toolset `pipeline`, key `run_now.jobs`.
- Value: the current list plus `"provider-description-read"`. Today that is `["intake-dates-apply","provider-description-read"]`.
- Reason: `Platform Admin 5 Nov 2026 20:03 §1 (PR #877): governed Run Now for provider-description-read, activated after deployment of <release> and role verification (rank 4 approves, rank 3 refused)`

RPC form, when signed in as the Platform Admin:

```
admin_toolsets_write('setting', {"toolset":"pipeline","key":"run_now.jobs","value":["intake-dates-apply","provider-description-read"],"reason":"…"})
```

### Forward recovery

- **Stop new work first, before any rollback:** pause the `provider-description-read` job with a reason, or set `pdesc.enabled` to 0. Also take `provider-description-read` out of `run_now.jobs` if it was added.
- **Keep the record:** retain saved cohorts, evidence, proposals, reservations and decisions. Drop nothing.
- **Bad proposal:** reject it in Layer 4. Unchanged rejected evidence is never read again.
- **Worker fault:**
  - Pause the job, or set `pdesc.enabled` to 0, **before** redeploying a previous `coverage-sweep`.
  - A worker from before this release would call the model without a reservation if it were given an item. The new lease refuses it (`worker_protocol_required`), but the pause is the procedure, and the gate is only a safeguard.
  - Resume only after a reservation-capable worker is deployed again.
- **Database fault:** forward-fix with a new migration that is guarded on the after-hashes. Never edit the consumer projection directly.

## Verified production baseline

Read-only measurements on 4 November 2026, 11:53–11:58 UTC, against `fxcwkweaxjtknorudmwp`:

| Country | Active published providers | Currently typed universities | Description held | Reader scope |
|---|---:|---:|---:|---:|
| AU | 1,279 | 45 | 0 | 5 |
| NZ | 416 | 8 | 0 | 0 |
| CA | 1,130 | 0 | 0 | 0 |

CA's zero is its present catalogue classification. The five-member authorised pilot has **three** currently suitable stored About sources, **zero unread sources**, **four actual pending proposals**, one `quote_not_on_page` hold, and **zero admissions/publications**. The ledger records eight AI calls costing **US$0.0065848**; current mutable read rows retain five tries after retries. Current proposal yield is four over eight ledger calls; cost per current proposal is US$0.0016462. Cost per admission is undefined.

An independent read-only check at **12:34:39 UTC** returns all five pilot providers through both the actual Website and Zoho provider projections, with zero non-empty descriptions in either. The picker timeout correction is already in main/live (`20261103100000`, stored-source function hash `b4bef5671c9b2125b530df3abc9c502a`). Four outstanding human decisions and one quality hold explain present non-publication. The AI ceiling is not exhausted. The maximum description length is already 1,200 under D-M2; 900 is historical. The shared Firecrawl lane currently reports its reserve hold; stored-only processing consumes no acquisition credits.

The current five provider keys, AU/university scope, US$1 lifetime pilot ceiling, US$1 daily lane guard and pending cap of 10 are retained. A ten-provider production target cannot override this denominator. Broader AU/NZ/CA eligibility and a recurring replacement for the lifetime pilot budget require explicit policy decisions; admission authority remains human regardless of any source-read configuration.

## Development and production boundary

The isolated tests use PostgreSQL 17.6, schema/code metadata captured read-only, fictional providers and controlled stored source documents. The model transport is the simulated external boundary; actual worker request, identity, cost-quote, claim and quote parsing plus database reader, validator, Layer 4 and provider consumer projection execute. Fixture costs are controlled test values, never claimed as vendor expenditure. No production source content or user data is copied into these fixtures.

Zoho has an existing provider route (`public.zoho_v2_provider(text)`). Its prepared provider item can override the fresh Website description, so both actual projections must be read independently and stale-cache mismatches retained until the existing `website-sync-check` scan refreshes them (this feature never writes the feed). The earlier admin statement that Zoho does not carry descriptions is outdated. Website proof never counts as Zoho publication. No consumer function or API shape is changed to manufacture parity.

The 4 Nov feature-branch Cloudflare build guard (`scripts/guard-provider-description-no-deploy.mjs`, npm prebuild and Wrangler custom build) was removed on 5 Nov: it made the "Workers Builds: coursefinder-pilot" check fail on purpose. A Workers Builds run on a feature branch uploads a preview version only; production deployment stays with the Integration Controller.

## Reproduce development acceptance

```sh
npm install --ignore-scripts --no-package-lock --no-audit --no-fund
npx playwright install --with-deps chromium
bash tests/fixtures/provider-description-autonomy/run.sh
npx playwright test --config=playwright.provider-description.config.mjs
npm run build
npm run ui:tokens
```

The database command creates/recreates only the named scratch Docker database, never accepts a production connection and requires PostgreSQL 17.6. It reconstructs captured schema contracts before applying current main's outcome correction and the feature migration. The fixture checks exact function hashes, including guarded migration replay and refusal of drift; captured function files intentionally preserve their original whitespace, including CRLF bodies. Tests exercise invalid outcome FKs, permission denials, unsupported admission states, cost and manual locks, dispatch failure recovery, changed cohort caps and review capacity. The real SQL browser suite uses a loopback-only transport and a small test page mounting the actual existing card; its model/storage/auth boundaries are controlled explicitly. Navigation UI mocks are supplemental and never counted as admission proof.

[Detailed validation and limitations](ui-evidence/provider-description-test-results.md), [schema parity](ui-evidence/provider-description-schema-parity.json), [benchmark and plans](ui-evidence/provider-description-benchmark.json), [desktop](ui-evidence/provider-description-database-desktop.png) and [phone](ui-evidence/provider-description-database-phone.png) are retained in this PR. CI repeats the isolated database, browser, governance, build and token gates without production secrets.

Canonical admin records are supplied as a reviewable patch in `docs/governance/provider-description-admin.patch` for `msinghbs-ai/coursefinder-admin`. Apply it from that repository with `git apply --check` followed by `git apply`; it contains documentation only. It records the original mandate, read-only baseline and evidence, UI/lineage/register updates and full handover. This preserves the requested single draft Pilot PR; no second approval mechanism or admin PR is created.

## Controller production acceptance procedure

Only after Platform Admin release authorisation, Claude:

1. Reconciles latest main, other held Controller work and migration ordering. Reconciled base: main `cf77ef78` (v2.15.485); this feature is `20261106200000_cf247_provider_description_autonomy.sql` (renumbered from `20261105010000`, which v2.15.479 applied in production for `intake_preview_identity_lookup`). This feature does not edit `security.job_run_now_v1`; invalid `ran`/`refused` outcome codes remain forbidden by the actual FK. Revalidates every guarded production function hash immediately before release and assigns the release number.
2. Records the existing reader/job states and pauses provider-description processing with an audited release reason before the database/worker pair changes. Lets any in-flight provider-description lease finish or expire under its existing policy; does not reset unknown-charge reservations. Applies the exact accepted migration and deploys the complete `coverage-sweep` folder and UI through existing release workflows. Confirms the new source-guard behaviour and four-argument cost-reservation service are installed together, then restores only the previously authorised operating state; other policy pauses stay in force. Preserves current scope, locks, review and spending limits. Any broadened scope or recurring budget must cite a separate explicit decision.
3. Within **0–2 minutes**, signs in to Layer 2 → Enrich fields → Provider Descriptions — Run & Validate. Confirms the published/active eligibility denominator, correct country/type and individual selection, current source evidence, exact institutional identity, review status and allowed cost. Confirms read-only roles cannot save/run.
4. Within **2–5 minutes**, previews a genuinely eligible bounded stored-evidence cohort, records an audit reason, saves it and invokes Run Now once. Records cohort/run/read/evidence references, actual saved outcome, source/model version, charge/reservation and next stage. A short or empty denominator is BLOCKED with evidence; no limit or scope is widened to obtain a green result.
5. Within **5–10 minutes**, reads the saved result after refresh and verifies actual evidence extraction, validation and proposal/hold progress. Opens the existing Layer 4 decision item. Human decisions remain subject to their actual authority and ownership; no automatic reviewer impersonation is permitted. If capacity is full, confirms parking and continuation of unrelated eligible work.
6. After an authorised human decision, verifies the active catalogue description and actual Website and Zoho provider read-back separately. Confirms stale prepared items are refreshed by the existing `website-sync-check` scan (this feature never writes the feed), publication retry and next-provider continuation through the existing schedule, unchanged rejected evidence is not reread, and unknown-response recovery returns the same run. Inspects the saved evidence on phone.
7. Records proposal, admission and publication counts separately, source-unavailable/identity/quality/policy exceptions and actual cost. Returns any failed verification to the existing integration queue. Claude alone declares production acceptance.

Forward recovery: pause the existing reader through its governed switch/job controls with a reason if incorrect processing is found; retain all saved evidence, proposals and decisions. Do not drop tables, delete history, override locks or write directly into the consumer projection. Correct the implementation and use the existing authorised review/correction process.

## Machine admission and whole-platform delivery (Platform Admin decision, 9 Nov 2026)

Migrations `20261109020000_cf247_pdesc_machine_admission.sql` and `20261109030000_cf247_pdesc_whole_platform_queue.sql` add a constrained machine route for a provider's FIRST description. Both are inert until the Platform Admin switches `pdesc.machine_admit_on` on; with it at 0 the reader behaves exactly as before (Layer 4 decides every description, `pdesc.pending_max` holds the reader back).

- **Rule `pdesc-machine-v1`** (security.provider_description_machine_gate_v1): the provider is active, published, in scope, has no description, no manual lock, no earlier human rejection, no open identity finding and no withdrawn machine description; the text has none of the claim, ranking, superlative, accreditation, campus, scholarship, fee, visa or other refused words (`pdesc.claim_words`, `pdesc.superlatives`, `pdesc.evidence_claim_words`, `pdesc.machine_refused_words`) and no figure other than a four-digit year (`pdesc.machine_numbers_allowed` = 0). Tiers 1 to 3 (stored, direct, Firecrawl page) are proved by the existing identity, lineage and per-sentence quote checks, then re-proved at admission.
- **Tier 4 `registry_factual`**: a short profile built only from the verified register listing (CRICOS, NZQA, IRCC DLI wording in `pipeline.provider_description_registry_templates`), the provider record (type, city, region, country) and the active catalogue courses (study levels, fields). No AI, no page read, no cost. Too few facts (`pdesc.registry_min_facts`) gives a held read `insufficient_verified_facts`. Switched on by `pdesc.registry_factual_on` (needs `pdesc.machine_admit_on`); applies to providers whose latest read was held with a rule in `pdesc.registry_after_rules`, to dead letters, and to providers with no website and no stored page.
- **Admission path** (security.provider_description_machine_admit_v1): never calls the human Layer 4 decision. It writes the one description, settles the Layer 4 item as `approved` with a `layer4_decisions` row by the system automation account (`c0ffee00-0000-4000-8000-000000000150`) whose reason says "Not a person's decision" and whose `layer2_state` carries `machine_rule`, `tier` and `actor_kind: machine`, writes an `admin_control_events` row and a `search_refresh_signals` row, and records the before and after text, source, hash and facts in `pipeline.provider_description_machine_admissions`. Items already waiting are settled the same way (`security.provider_description_machine_settle_pending_v1`, `pdesc.machine_settle_per_run` a run); an item the rule does not pass stays for a person with the reason on it.
- **Withdrawal**: the Platform Admin (rank 6) calls `public.admin_provider_description_machine_withdraw_v1(provider_id, reason)`, which names the person and calls `security.provider_description_machine_withdraw_v1(provider_id, reason, person)` (not callable by users). It restores the earlier text of one provider unless a person changed the description since or a hand lock was added since (then nothing is restored and the reason says so), proves the catalogue row changed, keeps the audit row, queues the search refresh again on the existing signal (production allows one signal for each decision), and holds that provider out of automatic admission until a person decides.
- **Queues**: in machine mode the reader keeps one bounded queue per country (AU, NZ, CA), sized from the providers still to do and the observed rate (`pdesc.target_hours`, `pdesc.backlog_hours`, `pdesc.rate_window_hours`, `pdesc.queue_cap`), leases the quietest country first, bounds reads in progress by `pdesc.concurrency_max` and by the AI spend still available (`pdesc.read_cost_floor_usd`), and sends up to `pdesc.dispatch_max` worker calls a run. The ceilings `pdesc.ai_usd_max`, `pdesc.firecrawl_reads_max` and `pdesc.pending_max` are not changed. Pace is also set by existing settings: `pdesc.every_minutes` (hourly floor, minimum 10), `batch.provider_description` (up to 10 a call).
- **Speed at the live size (3,103 providers, 766 stored pages)**: a run looks at a bounded slice of the providers (`pdesc.scan_factor` times the size, at most `pdesc.scan_max`), the ones looked at least recently first, so the whole catalogue is covered over several runs and a run stays inside the 8 second limit. The cheap checks (no description, published, in scope, no open read, a stored page exists) come before the identity, lineage and text checks. A provider the rule would refuse (hand lock, earlier rejection, withdrawn, description cleared by hand, open finding, unusable name) is not queued, leased or read, so no AI cost is spent on it. The funnel counts the large groups without checking each provider above `pdesc.funnel_detail_max`. One index beside `catalogue.providers` on the website host (additive, no consumer API object changes) makes the host match an index lookup.
- **Waiting items when the machine rule declines a proposal (N3)**: while fewer than `pdesc.machine_pending_max` proposals wait, a proposal the text rule refuses waits for a person in Layer 4 (this can add up to that many waiting items above `pdesc.pending_max`; the extra is bounded and tested). Beyond it the read is held with the whole proposal kept.
- **Firecrawl in parallel (N4)**: each worker call is granted at most `pdesc.firecrawl_per_call` reads, taken from what `pdesc.firecrawl_reads_max` still allows after the reads other calls hold in flight.
- **Scope**: an empty `pdesc.provider_types` is every type and a provider with no type is the token `unclassified` (all Canadian providers have none); an empty `pdesc.provider_keys` is every provider. Settings › Pipeline settings now accepts an empty list where the setting's minimum is 0; `pdesc.countries` needs at least one value.
- **Parity**: the existing publication check reads each admitted description back from `website_v2_provider` and the Zoho read and records it on the read; `security.provider_description_machine_report_v1()` reports providers by country, admissions by tier, holds and declines, the Website and Zoho verified counts, any mismatch and the throughput. No consumer API object is created, changed or dropped.

Release order, each step by the authorised owner: apply `20261109010000`, `20261109020000`, `20261109030000`; deploy the coverage-sweep worker (v0.59.12); then, with an audit reason in Settings, set `pdesc.provider_keys` to empty, `pdesc.countries` to AU, NZ and CA, `pdesc.provider_types` to empty (or the chosen types), and last `pdesc.machine_admit_on` (then `pdesc.registry_factual_on`) to 1. Check the report after the first run. To stop, set `pdesc.machine_admit_on` back to 0.

### Neutral population words in context (Directive 3, Blocker A, 9 Nov 2026)

Migration `20261109120000_cf247_pdesc_claim_word_context.sql`. The machine rule used to refuse any description holding a word of `pdesc.claim_words`, so a neutral, source-backed sentence such as "The university's essence is found in its students, staff, alumni and donors" was declined (`refused_word:students`, `refused_word:alumni`). The rule is now context-sensitive:

- The words in the new setting `pdesc.machine_neutral_words` (seeded `students`, `staff`, `alumni`; Settings › Pipeline settings, changed with a reason) are allowed in a machine-admitted description only when **every sentence that uses the word is supported by its exact official quote**: the quote (proved on the stored page, `on_page`) holds the same word and does not negate it, and the description text is exactly those sentences. With no sentences (the register-fact profile, tier 4) the strict rule applies.
- The exemption reaches only `pdesc.claim_words` and the French list `pdesc.machine_refused_words_fr`. Ranking, rating, outcome (employment, employability, salary, graduate outcomes), accreditation, award and facility words, every superlative, finance, visa and availability words, campus, scholarship and guarantee words, page markup and every figure (`pdesc.machine_numbers_allowed` stays 0) still stop automatic admission wherever they appear.
- Provenance is unchanged: the audit row keeps the source address, source hash, evidence id and each sentence with its quote, and now also the neutral words relied on (`checks.neutral_words`). A proposal the rule still declines waits for a person in Layer 4 (or is held with the whole proposal), as before.
- Re-evaluation of what was declined needs no new job and no row written: `security.provider_description_machine_step_v1` (run on every fire while `pdesc.machine_admit_on` is 1) offers each waiting Layer 4 provider-description item to the admission again, `pdesc.machine_settle_per_run` items a run and a declined item at most hourly.
- Not covered by this change, reported for decision: the French list is applied to English text too, so a sentence with "unique" (for example the UNSW proposal) is still declined; the Monash sentence as proposed still holds "campus" and the figure 400.
- Guard: `tests/uat/cf-247-s504-pdesc-claim-word-context-contract.spec.mjs` and the isolated PostgreSQL fixture `tests/fixtures/pdesc-claim-context/`.

### Register-fact profile no longer ends source-backed enrichment (P0, 9 and 10 Nov 2026)

Migration `20261110040000_cf247_pdesc_basic_profile_upgrade.sql` (not applied by the author; the release controller applies it). One new setting, `pdesc.registry_upgrade_on` (0 or 1, created OFF). Nothing else becomes a setting (Platform Admin, 10 Nov 2026): the revisit, the rate and the identity-test count come from `pdesc.recheck_days`, the same-evidence parking, `pdesc.queue_per_run`, `pdesc.queue_cap` and `batch.provider_description`.

- **Why**: About 910 providers hold a register-fact profile (rule `registry_factual`; 912 on 10 Nov 2026). Every gate treated it as "description already held", so the 304 with a website (184 with a stored About page) could never be read for a source-backed description.
- **What a profile is**: `security.provider_description_basic_profile_v1(provider)` returns it only while the setting is on, the provider's current text is exactly its live `registry_factual` machine admission, and that admission's read is the admitted `registry_factual` read. A text a person changed is not a profile.
- **What still blocks**: manual lock, an earlier Layer 4 rejection, a withdrawal awaiting review, an open identity finding, an unusable name, an edited description. Only the "description already held" tests step aside, and only for the profile.
- **Upgrade admission**: the new text comes from a source tier (stored, direct, Firecrawl), has the profile as its before text, differs from it, has at least `pdesc.min_sentences` quote-verified sentences, and passes the same machine text gate. The profile admission is closed with an "Upgraded ..." reason (never deleted), the profile read becomes `superseded`, and the new admission keeps `before_description` and `checks.upgrade` (prior admission and read, source address, hash, evidence, sentences). The existing withdraw route restores the profile text. A proposal the rule declines (for example "campus") waits in Layer 4 for a person with the profile as the before text.
- **Identity hold**: a queued read of an active, published provider whose identity test gives `wrong_host` (this includes a provider with no website) or `provider_host_conflict` is held with that rule and the mark `checks.identity_hold`, instead of sitting unseen. Any other outcome (`provider_inactive`, a lifecycle hold, an open finding) leaves the read queued as before. The test uses the stored About copy the lease has already found, and takes `batch.provider_description` reads a call, the ones tested longest ago first. This was part of the 241 queued reads on 9 Nov (the 96 oldest were identity failures; the rest were throttled by record calls that hit the 8 s limit).
- **Offered again after a correction**: the selection does not park a read held by the identity hold once the provider passes the identity test again (website or host corrected), so `pdesc.recheck_days` never delays it. A hold made by the worker keeps its existing parking.
- **Layer 4 approval of a waiting upgrade**: when a person approves the waiting upgrade, the description changes and the profile read becomes `superseded`, but the profile admission row is not closed with the "Upgraded ..." reason (that happens on the machine path). The profile rule returns nothing from then on because the text differs. Closing the row needs a change to `layer4_provider_description_apply_impl`, which this change does not edit.
- **`pdesc.pending_max`** gates Run Now (`review_full`) and resume; the scheduled lease does not read it while `pdesc.machine_admit_on` is 1. The upgrade path does not read it either.
- **Guard**: `tests/uat/cf-247-s516-pdesc-basic-profile-upgrade-contract.spec.mjs` and the isolated PostgreSQL fixture `tests/fixtures/pdesc-basic-upgrade/` (52 scenario results, md5 refusal, earlier fixtures unchanged, forward recovery `supabase/held/pdesc_basic_profile_upgrade_forward_recovery.sql`).
