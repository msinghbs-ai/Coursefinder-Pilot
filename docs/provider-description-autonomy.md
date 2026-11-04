# Provider Descriptions — Run & Validate

Development branch: `codex/provider-description-autonomy`. Authority: Platform Admin's 4 November 2026 Codex Cloud mandate; canonical admin record `docs/platform/nz-enrichment-brief/2026-11-04-provider-description-autonomy-mandate.md`, extending the 2 November missing-field mandate. Claude remains the sole Integration Controller. This branch assigns no release and performs no deployment, production write or vendor call.

## Architecture and authority

The existing `provider-description-read` job and `coverage-sweep` mode remain the reader. The existing evidence artefacts, pinned Enrich fields model, shared AI controls, read ledger and individual Layer 4 description decision remain authoritative. The Admin card stays in Layer 2 → Enrich fields; the old retry-only controls are replaced in place. The new typed Run Now adapter uses the existing `job_run_now` task kind, registered outcome codes, catalogue permissions, shared Run Now allowlist and caps, audit events and existing reader fire function. It does not modify the intake-only shared dispatcher owned by the Integration Controller and PR #872/#874.

The migration adds the already-authorised reader to `run_now.jobs`, preserving all existing entries. This is the bounded operator action requested by this mandate; it does not alter eligibility, acquisition, spending or admission authority. It adds no scheduler or approval route. The saved cohort binds requester, reason, exact providers, source versions and run reference; repeat requests recover the same task. Source or identity changes invalidate selection before processing. Stored-only cohorts cannot enable acquisition.

Every new description still requires its applicable individual human Layer 4 decision. Bulk approval and AI authorisation remain unavailable. Apply-time guards recheck scope, lifecycle, identity, evidence lineage, factual validation, unchanged catalogue value and manual locks. Review-capacity work is parked and resumed through the existing scheduled reader without paying to read unchanged evidence again. Publication is checked separately from admission against the existing consumer projection.

The worker keeps final redirect addresses, validates the full current institutional identity, preserves whole claims and quotations, and holds unsupported numerical, historical and long verbatim claims. The prompt and approved model remain unchanged; source-validation behaviour has its own recorded version. Before a paid AI call, conservative pricing bounds for that exact model are reserved inside the existing lifetime and daily caps. Unknown charges retain their reservation until reconciled. No limit is increased.

AI diagnosis reuses the existing operations diagnosis lane only when its approved switch, model, permissions, budget and an exact existing provider/evidence-linked issue permit it. Otherwise the screen gives a saved deterministic evidence explanation with the precise limitation. An explanation cannot authorise admission or change settings.

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

Zoho has an existing provider route (`public.zoho_v2_provider(text)`). Its prepared provider item can override the fresh Website description, so both actual projections must be read independently and stale-cache mismatches retained until the existing sync mechanism repairs them. The earlier admin statement that Zoho does not carry descriptions is outdated. Website proof never counts as Zoho publication. No consumer function or API shape is changed to manufacture parity.

The branch has a targeted Cloudflare build guard in both npm prebuild and Wrangler custom build. Cloudflare's feature-branch integration is known to upload preview versions on push; this branch deliberately refuses that build before upload. Local build/test commands and main retain their build path. A held Cloudflare preview check is intentional and is not a failed development test.

## Controller production acceptance procedure

Only after Platform Admin release authorisation, Claude:

1. Reconciles latest main, the held #872/#874/#875 work and migration ordering. This feature does not edit `security.job_run_now_v1`; invalid `ran`/`refused` outcome codes remain forbidden by the actual FK. Revalidates every guarded production function hash immediately before release and assigns the release number.
2. Records the existing reader/job states and pauses provider-description processing with an audited release reason before the database/worker pair changes. Applies the exact accepted migration and deploys the complete `coverage-sweep` folder and UI through existing release workflows. Confirms the new source-guard behaviour and four-argument cost-reservation service are installed together, then restores only the previously authorised operating state; other policy pauses stay in force. Preserves current scope, locks, review and spending limits. Any broadened scope or recurring budget must cite a separate explicit decision.
3. Within **0–2 minutes**, signs in to Layer 2 → Enrich fields → Provider Descriptions — Run & Validate. Confirms the published/active eligibility denominator, correct country/type and individual selection, current source evidence, exact institutional identity, review status and allowed cost. Confirms read-only roles cannot save/run.
4. Within **2–5 minutes**, previews a genuinely eligible bounded stored-evidence cohort, records an audit reason, saves it and invokes Run Now once. Records cohort/run/read/evidence references, actual saved outcome, source/model version, charge/reservation and next stage. A short or empty denominator is BLOCKED with evidence; no limit or scope is widened to obtain a green result.
5. Within **5–10 minutes**, reads the saved result after refresh and verifies actual evidence extraction, validation and proposal/hold progress. Opens the existing Layer 4 decision item. Human decisions remain subject to their actual authority and ownership; no automatic reviewer impersonation is permitted. If capacity is full, confirms parking and continuation of unrelated eligible work.
6. After an authorised human decision, verifies the active catalogue description and actual Website and Zoho provider read-back separately. Confirms stale prepared items are repaired through existing sync machinery, publication retry and next-provider continuation through the existing schedule, unchanged rejected evidence is not reread, and unknown-response recovery returns the same run. Inspects the saved evidence on phone.
7. Records proposal, admission and publication counts separately, source-unavailable/identity/quality/policy exceptions and actual cost. Returns any failed verification to the existing integration queue. Claude alone declares production acceptance.

Forward recovery: pause the existing reader through its governed switch/job controls with a reason if incorrect processing is found; retain all saved evidence, proposals and decisions. Do not drop tables, delete history, override locks or write directly into the consumer projection. Correct the implementation and use the existing authorised review/correction process.
