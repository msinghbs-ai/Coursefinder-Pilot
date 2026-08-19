# M1-SEARCH — Governed Search/API & Consumer Projection UAT

Date: 19 August 2026
Status: **PASS — FTS/consumer-contract gate; vector content gate remains CLOSED**
Environment: `coursefinder_Pilot` (`fxcwkweaxjtknorudmwp`)

## Scope

Search is a derived, rebuildable projection. This gate does not alter Provider/Course identity and does not make unpublished catalogue rows consumer-visible.

The accepted Search country substrate is explicitly gated to Australia and New Zealand. Country ingestion flags are not sufficient to publish a country into Search because CA and other queued countries can be ingestion-enabled before their Search gate is accepted.

## Governed projection contract

`search.projection_country_gates` is the explicit country admission gate. AU and NZ are approved. No other country is admitted.

`search.enrichment_gates` is the explicit enrichment admission gate. Scholarship is structurally approved from its accepted Layer 2 source gate, but remains subject to scholarship publication state. Course links, fees, intakes and English requirements remain blocked until their dedicated Course Facts UAT gate is accepted.

`search.course_documents` projection v2 adds stable business keys, country/study-level/field codes, exact field name, multi-State `subdivision_codes[]`, relation-derived `delivery_modes[]`, readiness flags, projection version/timestamps and separate full/semantic content hashes. Course State is never collapsed to a representative State.

The rebuild path is now dry-run/apply capable and atomic. The legacy `search.rebuild_course_documents()` wrapper delegates to the governed v2 refresh. It no longer performs an unscoped delete/reinsert across every active country.

## Projection UAT

| Check | Result |
|---|---:|
| Dry-run expected rows | 33,105 |
| AU rows | 26,648 |
| NZ rows | 6,457 |
| New rows | 0 |
| Removed rows | 0 |
| First apply changed rows | 33,105 |
| Replay changed rows | 0 |
| Replay unchanged rows | 33,105 |
| Projection generation | 12 |
| Projection hash | `e4d72aa009ec5ce6ac00ee61d7e2286514c1fe5251faab2292c24d54a26233f6` |
| Field populated | 26,648 |
| State populated | 26,613 |
| Delivery populated | 26,614 |
| AU multi-State courses | 4,388 |
| Search-visible fees/links/intakes/English | 0 / 0 / 0 / 0 |
| Search-visible scholarships | 0 |

The zero enrichment flags are expected: Course Facts domains are Search-blocked pending UAT and current Scholarship rows are unpublished.

## FTS / hybrid / vector benchmark

Representative database-side measurements used `EXPLAIN (ANALYZE, BUFFERS)` against the 33,105-row projection.

| Path | Representative case | Execution |
|---|---|---:|
| Weighted FTS | `data science`, AU, top 20, warm | ~1.95 ms |
| Structured filter | AU + `asced-0803` + `AU-VIC` + `on_campus`, top 20 | ~11.35 ms |
| Hybrid fallback | `data science`, AU, no accepted vector set, top 20, warm | ~11.77 ms |
| Initial generic hybrid fallback | same case before optimisation | ~159.28 ms |

The generic hybrid function was changed after the first benchmark so an absent vector set takes the direct indexed FTS path rather than materialising the full filtered candidate set.

`search.course_embeddings` currently contains **0 accepted embeddings**. The existing cosine HNSW index is valid and ready, and a supplied vector with no matching accepted model/content hash deterministically returns `fts_fallback`. Vector relevance/latency is therefore **not claimed as passed**. Production semantic search remains gated until an embedding model/profile is explicitly approved and an accepted embedding set is generated. No legacy/synthetic vectors were promoted to make this gate appear complete.

## Curated API contracts

### Website

Database contract: `api.website_course_search_v1`

Intended HTTP surface: `GET/POST /v1/courses/search` through a trusted Website gateway/Worker. The browser is not granted direct access to `search`, `catalogue`, `pipeline`, `evidence`, `publishing` or `ref` schemas.

Response contract is `website-course-search-v1` and contains only consumer-safe business fields: `course_key`, title/code, provider key/name, country, study level, field, State array, delivery-mode array, readiness flags and keyword match score.

Database execution is granted to `service_role` only. Results are hard-filtered to `publication_status='published'`.

### Zoho

Database contract: `api.zoho_course_candidates_v1`

Intended HTTP surface: authenticated `/v1/zoho/courses/candidates` or equivalent integration gateway. The function requires CourseFinder role rank >= 2 (Counsellor or higher), and returns only `published` or `internal` rows.

Response contract is `zoho-course-candidates-v1`. It deliberately omits source/evidence IDs, internal review objects, raw canonical tables and vector payloads. Commercial/CRM re-ranking remains a Zoho-side concern.

### Publication-safety UAT

All 33,105 current Search Documents are unpublished. Both curated consumer contracts therefore returned a valid v1 envelope with `items: []`. This is a PASS: Search/API implementation does not implicitly publish data.

Semantic/hybrid HTTP endpoints remain gated until the accepted vector profile exists. Course detail/compare/recommendation endpoints should reuse the same curated DTO and publication rules rather than exposing internal schemas.

## Security and advisor review

New Search functions are not executable by `anon`. Website execution is `service_role` only. Zoho execution is `authenticated` and the function enforces role rank >= 2. Search refresh/rebuild and hybrid candidate functions are service-only.

A final legacy-RPC audit found two older authenticated Search paths that could bypass the curated boundary: `api.search_courses` allowed rank-1 users to use an obsolete Search DTO, and `api.vector_candidates` did not apply a publication filter. Neither was referenced by current Pilot code. Migration `20260819050549_m1_search_retire_legacy_consumer_rpcs_v1` revoked `authenticated` execution and retained them only as explicitly deprecated `service_role` compatibility functions. General Admin `api.courses_list` / `api.providers_list` remain role-gated Admin contracts and are not Website/Zoho consumer Search contracts.

Supabase security advisor reported no new warning attributable to the M1-SEARCH functions. Existing project warnings around Admin/PIM public `SECURITY DEFINER` RPCs and leaked-password protection remain separate work items.

The performance advisor identified the new country-gate FK without a supporting index; migration `20260819045818_m1_search_country_gate_fk_index_v1` added that index before handover. Newly created Search indexes may appear as unused immediately after creation; this is expected until workload accumulates.

## Migration history

- `20260819045418_m1_search_governed_projection_v1`
- `20260819045543_m1_search_consumer_contracts_v1`
- `20260819045719_m1_search_hybrid_fallback_optimisation_v1`
- `20260819045818_m1_search_country_gate_fk_index_v1`
- `20260819050549_m1_search_retire_legacy_consumer_rpcs_v1`

## Gate decision

**M1-SEARCH core projection + FTS + curated contract gate: PASS.**

**Vector-content gate: CLOSED/PENDING.** Required next evidence is an explicitly approved embedding model/profile, generated embeddings keyed to `semantic_content_hash`, vector-only latency/recall checks, hybrid relevance comparison against FTS, and then an explicit semantic publication decision.
