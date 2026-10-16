# StudySearch – Component register (generated)

**Generated:** 17 Oct 2026 10:52 Melbourne, from `pipeline.component_register` (Decision 260). Do not edit by hand.

## Summary

| Layer | Kind | Active | Retiring | Retired |
|---|---|---|---|---|
| Access | table | 1 | 0 | 0 |
| API | job | 1 | 0 | 0 |
| API | screen | 1 | 0 | 0 |
| API | table | 6 | 0 | 0 |
| Catalogue | table | 23 | 0 | 0 |
| L1 register | edge_function | 60 | 0 | 0 |
| L1 register | job | 7 | 0 | 0 |
| L1 register | screen | 10 | 0 | 0 |
| L1 register | table | 48 | 1 | 0 |
| L2 read | edge_function | 6 | 0 | 0 |
| L2 read | function | 0 | 2 | 0 |
| L2 read | job | 43 | 0 | 0 |
| L2 read | screen | 16 | 0 | 0 |
| L2 read | table | 139 | 5 | 0 |
| L2 read | view | 8 | 0 | 0 |
| L3 interpret | edge_function | 1 | 0 | 0 |
| L3 interpret | job | 3 | 0 | 0 |
| L3 interpret | table | 35 | 1 | 0 |
| L3 interpret | view | 1 | 0 | 0 |
| L4 admit | job | 16 | 0 | 0 |
| L4 admit | screen | 4 | 0 | 0 |
| L4 admit | table | 28 | 0 | 0 |
| L4 admit | view | 6 | 0 | 0 |
| Layer 2 | function | 2 | 0 | 0 |
| Layer 2 | job | 1 | 0 | 0 |
| Layer 3 (retired) | table | 2 | 0 | 0 |
| Platform | edge_function | 11 | 0 | 0 |
| Platform | function | 3 | 0 | 0 |
| Platform | job | 30 | 2 | 0 |
| Platform | screen | 35 | 0 | 0 |
| Platform | table | 155 | 7 | 0 |
| Platform | view | 9 | 0 | 0 |
| Website API | edge_function | 3 | 0 | 0 |
| Website API | function | 1 | 1 | 0 |
| Website API | job | 5 | 0 | 0 |
| Website API | table | 10 | 1 | 0 |
| Zoho API | edge_function | 1 | 0 | 0 |
| Zoho API | function | 1 | 1 | 0 |
| Zoho API | job | 1 | 0 | 0 |
| Zoho API | table | 2 | 0 | 0 |

## Latest hygiene check

```
{
    "sync": {
        "gone": 0,
        "jobs": 102,
        "tables_and_views": 474
    },
    "compared_with": null,
    "ready_to_drop": 0,
    "unused_tables": 0,
    "unused_indexes": 0,
    "tables_without_rls": 39,
    "jobs_not_catalogued": 0,
    "tables_without_purpose": 420,
    "edge_functions_not_called": 0,
    "public_functions_open_to_anon": 0,
    "definer_functions_without_search_path": 0
}
```

## Components

| Kind | Name | Layer | Status | Purpose | Last used | Size | Replaces / replaced by | Note |
|---|---|---|---|---|---|---|---|---|
| table | `security.user_deletions` | Access | active | CF-247 16 Oct 2026: users deleted from Users & roles by a Platform Admin: who, when, the email and roles the user had, and whether Supabase Auth removed the use |  | 16 kB |  |  |
| job | `api-usage-rollup` | API | active | API usage: daily statistics: Daily (about 00:20 Melbourne) and on demand from Operations > API usage: sums the API v2 request log into calls per day, key and ac |  |  |  |  |
| screen | `Integrations › API usage` | API | active | Calls, errors and times per key and action |  |  |  |  |
| table | `pipeline.api_key_events` | API | active | CF-247 16 Oct 2026 (Platform Admin: "be able to rotate their keys"): every key rotation, switch off or on, and early end of an old key, from Operations > API us |  | 32 kB |  |  |
| table | `pipeline.api_requests` | API | active | CF-247 16 Oct 2026 (Platform Admin: "summary and stat collection"): one row per call to a versioned API URL (from Zoho API v2 on): key, action, HTTP status, tim |  | 976 kB |  |  |
| table | `pipeline.api_usage_daily` | API | active | CF-247 16 Oct 2026: calls per day, platform, version, key and action (ok, client errors, rate limited, server errors, average, 95th percentile and slowest time, |  | 64 kB |  |  |
| table | `pipeline.api_usage_refreshes` | API | active | CF-247 16 Oct 2026: each refresh of the API statistics, daily (api-usage-rollup job) or on demand from Operations > API usage: when, by whom and how long it too |  | 32 kB |  |  |
| table | `pipeline.api_usage_summary` | API | active | CF-247 16 Oct 2026: statistics per API key for the last 24 hours, 7 days and 30 days (calls, success and failure, last call, bandwidth, reply sizes, times, full |  | 96 kB |  |  |
| table | `private.api_keys` | API | active | CF-247 16 Oct 2026: keys for the versioned API URLs (from Zoho API v2 on). One row per consumer; a key works only on its own platform and version. Only the SHA- |  | 48 kB |  |  |
| table | `catalogue.course_academic_options` | Catalogue | active |  |  | 40 kB |  |  |
| table | `catalogue.course_collection_memberships` | Catalogue | active |  |  | 32 kB |  |  |
| table | `catalogue.course_collections` | Catalogue | active |  |  | 48 kB |  |  |
| table | `catalogue.course_english_requirements` | Catalogue | active |  |  | 15 MB |  |  |
| table | `catalogue.course_fees` | Catalogue | active | Temporal evidence-backed Course fee observations. Layer 1 regulatory ingestion does not fabricate fee facts; authoritative/provider Layer 2 sources populate thi |  | 134 MB |  |  |
| table | `catalogue.course_field_observations` | Catalogue | active |  |  | 12 MB |  |  |
| table | `catalogue.course_identifiers` | Catalogue | active |  |  | 25 MB |  |  |
| table | `catalogue.course_intakes` | Catalogue | active |  |  | 12 MB |  |  |
| table | `catalogue.course_registrations` | Catalogue | active |  |  | 14 MB |  |  |
| table | `catalogue.course_regulatory_observations` | Catalogue | active | Time-scoped regulatory course facts asserted by an authoritative registration source. Rows preserve source snapshot and evidence; they do not redefine canonical |  | 32 MB |  |  |
| table | `catalogue.course_study_level_observations` | Catalogue | active |  |  | 31 MB |  |  |
| table | `catalogue.courses` | Catalogue | active |  |  | 45 MB |  |  |
| table | `catalogue.outcome_benchmarks` | Catalogue | active |  |  | 80 kB |  |  |
| table | `catalogue.provider_aliases` | Catalogue | active |  |  | 48 kB |  |  |
| table | `catalogue.provider_assets` | Catalogue | active |  |  | 2496 kB |  |  |
| table | `catalogue.provider_associations` | Catalogue | active |  |  | 80 kB |  |  |
| table | `catalogue.provider_collection_memberships` | Catalogue | active |  |  | 80 kB |  |  |
| table | `catalogue.provider_fee_ranges` | Catalogue | active |  |  | 768 kB |  |  |
| table | `catalogue.provider_identifiers` | Catalogue | active |  |  | 1688 kB |  |  |
| table | `catalogue.provider_outcomes` | Catalogue | active |  |  | 5728 kB |  |  |
| table | `catalogue.provider_registrations` | Catalogue | active |  |  | 4376 kB |  |  |
| table | `catalogue.providers` | Catalogue | active |  |  | 7800 kB |  |  |
| table | `catalogue.student_flow_observations` | Catalogue | active |  |  | 6952 kB |  |  |
| edge_function | `layer1-au-cricos-facts` | L1 register | active | v1.3.0 (CF-247 Phase 2, 8 Oct 2026): when the CRICOS register adapter (au_cricos) is switched on, the course facts are read from the |  |  |  |  |
| edge_function | `layer1-au-depth` | L1 register | active | v1.8.0 (CF-247 Phase 2, 8 Oct 2026): when the CRICOS register adapter (au_cricos) is switched on, the plan fingerprints and every row a |  |  |  |  |
| edge_function | `layer1-ca-ab-alis-degrees` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-ab-alis-probe` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-algonquin-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-bc-epbc-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-boreal-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-cambrian-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-centennial-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-cna-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-conestoga-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-confederation-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-cpic-probe` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-durham-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-fanshawe-pgwp` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-fanshawe-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-firstparty-catalogues` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-fleming-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-georgian-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-ircc-nvit-probe` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-lambton-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-live` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-loyalist-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-mb-designation-probe` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-mb-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-mohawk-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-niagara-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-northern-code-audit` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-northern-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-ns-sk-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-on-college-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-provider-geography` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-qc-audit` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-qc-parse-audit` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-qc-pdf-probe` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-qc-pdf-probe2` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-qc-prefix-audit` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-qc-strict-audit` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-qc-university-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-sault-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-seneca-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-sheridan-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-sk-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-sk-sitemap-probe` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-stclair-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-stlawrence-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-nz-live` | L1 register | active | NZQA tertiary register worker (Layer 1, NZ). |  |  |  |  |
| edge_function | `layer1-operations-control` | L1 register | active | v1.8.0 (CF-247): Canadian catalogue and register readers on Layer 1. Each source names its reader in | 2026-10-16 |  |  |  |
| edge_function | `layer1-operations-scheduled` | L1 register | active | v1.2.0: the statistics branches called these helpers without defining them (every scheduled QILT/PRISMS check failed); | 2026-10-14 |  |  |  |
| edge_function | `layer1-provider-facts` | L1 register | active | CF-247 v2.15.276 (14 Oct 2026) Decision 258: Layer 1 reader for provider register facts. | 2026-10-14 |  |  |  |
| edge_function | `layer1-register-etl` | L1 register | active |  |  |  |  |  |
| edge_function | `prisms-au-etl` | L1 register | active |  | 2026-10-16 |  |  |  |
| edge_function | `qilt-au-etl` | L1 register | active | v0.3.0 (Decision 134): an edition found by the statistics discovery job is read from its own file. The address must be a | 2026-10-16 |  |  |  |
| edge_function | `ranking-evidence-export` | L1 register | active |  |  |  |  |  |
| edge_function | `ranking-layer1-etl` | L1 register | active |  |  |  |  |  |
| edge_function | `ranking-publisher-control` | L1 register | active | CF-247 R5: internal callers (one-time nonce from the database) may apply an import that is already validated, |  |  |  |  |
| edge_function | `ranking-publisher-import` | L1 register | active |  |  |  |  |  |
| edge_function | `ranking-qs-official-etl` | L1 register | active |  |  |  |  |  |
| edge_function | `ranking-the-official-etl` | L1 register | active |  |  |  |  |  |
| edge_function | `statcan-ca-psis-etl` | L1 register | active |  |  |  |  |  |
| job | `coursefinder-layer1-housekeeping` | L1 register | active | Layer 1 housekeeping: Daily tidy-up of register runs. |  |  |  |  |
| job | `coursefinder-layer1-regulatory-scheduler` | L1 register | active | Register refresh scheduler: Starts register refreshes (CRICOS and others) when they are due. |  |  |  |  |
| job | `layer1-auto-ingest` | L1 register | active | Register auto-ingest: Ingests new register files when they appear. |  |  |  |  |
| job | `layer1-run-driver` | L1 register | active | Register run driver: Moves running register refreshes forward. |  |  |  |  |
| job | `provider-type-classify` | L1 register | active | Institution type: Every day: sets each provider's institution type from the register facts with the rules on Settings > Pipeline settings. A type set by a perso |  |  |  |  |
| job | `ranking-link` | L1 register | active | Link ranked universities to providers: Links QS and THE universities to providers in the same country when the names agree (Decision 208 rules), for every editi |  |  |  |  |
| job | `statistics-edition-discovery` | L1 register | active | New statistics editions: Looks for new QILT and PRISMS editions each month. |  |  |  |  |
| screen | `Layer 1 Register` | L1 register | active | Official registers such as CRICOS: each source, its health, schedule and settings. |  |  |  |  |
| screen | `Layer 1 Register › Scholarships` | L1 register | active |  |  |  |  |  |
| screen | `Layer 1 Register › Sources` | L1 register | active |  |  |  |  |  |
| screen | `Rankings & statistics` | L1 register | active | QILT, PRISMS, QS and THE data, and side-by-side comparison. |  |  |  |  |
| screen | `Rankings & statistics › Compare` | L1 register | active |  |  |  |  |  |
| screen | `Rankings & statistics › Datasets` | L1 register | active |  |  |  |  |  |
| screen | `Rankings & statistics › Outcomes (QILT)` | L1 register | active |  |  |  |  |  |
| screen | `Rankings & statistics › Overview` | L1 register | active |  |  |  |  |  |
| screen | `Rankings & statistics › Student flow (PRISMS)` | L1 register | active |  |  |  |  |  |
| screen | `Reference data › Ranking imports` | L1 register | active |  |  |  |  |  |
| table | `catalogue.provider_rankings` | L1 register | active |  |  | 48 kB |  |  |
| table | `catalogue.provider_register_facts` | L1 register | active |  |  | 952 kB |  |  |
| table | `pipeline.component_register` | L1 register | active | CF-247 Decision 260: every job, table, view, edge function and screen, with its layer, purpose, status (active, retiring, retired), what it replaces, and when i |  | 424 kB |  |  |
| table | `pipeline.layer1_course_retirements` | L1 register | active |  |  | 312 kB |  |  |
| table | `pipeline.layer1_dataset_editions` | L1 register | active |  |  | 80 kB |  |  |
| table | `pipeline.layer1_dataset_families` | L1 register | active |  |  | 48 kB |  |  |
| table | `pipeline.layer1_provider_departures` | L1 register | active |  |  | 32 kB |  |  |
| table | `pipeline.layer1_register_row_state` | L1 register | active |  |  | 9920 kB |  |  |
| table | `pipeline.layer1_run_plans` | L1 register | active |  |  | 408 kB |  |  |
| table | `pipeline.layer1_run_queue` | L1 register | active |  |  | 664 kB |  |  |
| table | `pipeline.layer1_seed_snapshots` | L1 register | active |  |  | 32 kB |  |  |
| table | `pipeline.layer1_source_operation_versions` | L1 register | active |  |  | 104 kB |  |  |
| table | `pipeline.layer1_source_operations` | L1 register | active |  |  | 120 kB |  |  |
| table | `pipeline.ranking_inline_evidence_payloads` | L1 register | active | Private exact-byte Evidence bridge for authorised ranking files supplied through a control plane that cannot write directly to Storage. Migrate to private Evide |  | 16 kB |  |  |
| table | `pipeline.register_adapters` | L1 register | active |  |  | 128 kB |  |  |
| table | `pipeline.register_replay_keys` | L1 register | active |  |  | 237 MB |  |  |
| table | `pipeline.register_replay_runs` | L1 register | active |  |  | 224 kB |  |  |
| table | `public._layer1_depth_uat_control` | L1 register | retiring |  |  | 32 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `ranking.editions` | L1 register | active |  |  | 96 kB |  |  |
| table | `ranking.indicator_observations` | L1 register | active |  |  | 62 MB |  |  |
| table | `ranking.manual_imports` | L1 register | active |  |  | 224 kB |  |  |
| table | `ranking.observation_provider_links` | L1 register | active |  |  | 384 kB |  |  |
| table | `ranking.observations` | L1 register | active |  |  | 67 MB |  |  |
| table | `ranking.provider_mappings` | L1 register | active |  |  | 152 kB |  |  |
| table | `ranking.publisher_institutions` | L1 register | active |  |  | 3680 kB |  |  |
| table | `ranking.systems` | L1 register | active |  |  | 48 kB |  |  |
| table | `ref.au_regional_postcode_ranges` | L1 register | active |  |  | 64 kB |  |  |
| table | `ref.countries` | L1 register | active |  |  | 128 kB |  |  |
| table | `ref.course_code_schemes` | L1 register | active |  |  | 32 kB |  |  |
| table | `ref.course_link_types` | L1 register | active |  |  | 32 kB |  |  |
| table | `ref.currencies` | L1 register | active |  |  | 32 kB |  |  |
| table | `ref.english_tests` | L1 register | active |  |  | 48 kB |  |  |
| table | `ref.external_study_area_mappings` | L1 register | active |  |  | 72 kB |  |  |
| table | `ref.external_study_areas` | L1 register | active |  |  | 48 kB |  |  |
| table | `ref.fields_of_study` | L1 register | active |  |  | 1304 kB |  |  |
| table | `ref.identifier_schemes` | L1 register | active |  |  | 32 kB |  |  |
| table | `ref.institution_collections` | L1 register | active |  |  | 80 kB |  |  |
| table | `ref.languages` | L1 register | active |  |  | 16 kB |  |  |
| table | `ref.nationality_terms` | L1 register | active |  |  | 32 kB |  |  |
| table | `ref.outcome_metrics` | L1 register | active |  |  | 48 kB |  |  |
| table | `ref.outcome_surveys` | L1 register | active |  |  | 48 kB |  |  |
| table | `ref.provider_types` | L1 register | active |  |  | 48 kB |  |  |
| table | `ref.ranking_sources` | L1 register | active |  |  | 24 kB |  |  |
| table | `ref.regions` | L1 register | active |  |  | 40 kB |  |  |
| table | `ref.study_level_source_mappings` | L1 register | active |  |  | 80 kB |  |  |
| table | `ref.study_levels` | L1 register | active |  |  | 64 kB |  |  |
| table | `ref.subdivisions` | L1 register | active |  |  | 120 kB |  |  |
| table | `scholarship.register_listings` | L1 register | active |  |  | 1224 kB |  |  |
| table | `scholarship.registers` | L1 register | active |  |  | 48 kB |  |  |
| edge_function | `coverage-sweep` | L2 read | active | v0.17.32: same normalising as extract.ts siteNorm (kept here so the shared extract.ts, used by other functions, is unchanged) | 2026-10-16 |  |  |  |
| edge_function | `layer2-provider-control` | L2 read | active |  |  |  |  |  |
| edge_function | `provider-contact-discover-scheduled` | L2 read | active |  |  |  |  |  |
| edge_function | `provider-contact-enrich-apollo` | L2 read | active |  |  |  |  |  |
| edge_function | `statistics-edition-discovery` | L2 read | active | CF-247 / Decision 134: find new statistics editions from each family's stable publisher page. |  |  |  |  |
| edge_function | `website-course-api` | L2 read | active |  |  |  |  |  |
| function | `public.layer2_provider_asset_fetch_routes()` | L2 read | retiring | Old logo finder (retired 10 Oct 2026); no caller, no job |  |  | job logo-find (coverage-sweep mode logo_find) |  |
| function | `public.layer2_provider_asset_promotion_context(uuid)` | L2 read | retiring | Old logo finder (retired 10 Oct 2026); no caller, no job |  |  | public.svc_logo_find_record |  |
| job | `better-page-revert` | L2 read | active | Return to the better course page: Puts a course back on its better page when a newer page proved weaker. |  |  |  |  |
| job | `central-ai` | L2 read | active | Read central pages with AI: Sends queued English language policy and academic calendar pages to the pinned model (GPT-4.1 mini); each score and month must be qu |  |  |  |  |
| job | `central-find` | L2 read | active | Find central pages: Maps each provider's own site with Firecrawl and suggests its key dates, international fee and English requirements pages, for a person to a |  |  |  | switched off |
| job | `course-link-reverse` | L2 read | active | Match known course pages by CRICOS code: Reads course pages already found on the top universities' sites that are matched to no course, and matches them by the  |  |  |  | switched off |
| job | `course-link-search` | L2 read | active | Find course pages by CRICOS code: Searches each university's own site for the CRICOS code (then the exact course title) and matches the result to the university |  |  |  |  |
| job | `course-link-search-worker` | L2 read | active | Search for course pages: Searches each provider's site for a course's own page (CRICOS code, then title), several at a time; a found page is used only after the |  |  |  | switched off |
| job | `coursefinder-layer2-housekeeping` | L2 read | active | Layer 2 housekeeping: Daily tidy-up of Layer 2 runs. |  |  |  |  |
| job | `coursefinder-m2-3-refresh-intelligence-tick` | L2 read | active | Refresh policies: Runs the refresh policies set under Scheduled jobs. |  |  |  |  |
| job | `coverage-bind` | L2 read | active | Match pages to courses: Links each discovered page to its course using the CRICOS code printed on the page. |  |  |  |  |
| job | `coverage-discover` | L2 read | active | Discover course pages: Maps each provider's website to find its course pages. |  |  |  |  |
| job | `coverage-discover-2` | L2 read | active | Discover course pages (second worker): Runs beside Discover course pages to map more provider websites at once (added for New Zealand, 1 Oct 2026). |  |  |  |  |
| job | `coverage-find-site` | L2 read | active | Find provider websites: Looks up the official website of providers that do not have one yet. |  |  |  |  |
| job | `coverage-read` | L2 read | active | Read course pages: Fetches matched course pages and saves them as evidence. |  |  |  | switched off |
| job | `coverage-read-2` | L2 read | active | Read course pages (second worker): Every 30 seconds: a second reader of found course pages (up to 60 a call, up to 20 a university), so onboarding is not held b |  |  |  | switched off |
| job | `coverage-reextract` | L2 read | active | Re-read saved pages: Extracts facts again from saved pages after the reading rules improve. |  |  |  |  |
| job | `coverage-reidentify` | L2 read | active | Identify course pages again: Checks saved course pages again against the course's code and title. |  |  |  | switched off |
| job | `cricos-peo` | L2 read | active | Read CRICOS contact (internal): Reads the Principal Executive Officer from the CRICOS website (Firecrawl). Held for internal use; never published. |  |  |  |  |
| job | `enrich-focus-refresh` | L2 read | active | Focus providers for course-page search: Weekly: ranks Australian providers by missing English and intakes; course-page search runs only for the top ones (Pipeli |  |  |  |  |
| job | `layer2-onboarding-snapshot` | L2 read | active | Provider onboarding figures: Updates the provider onboarding figures. |  |  |  |  |
| job | `link-refresh` | L2 read | active | Refresh course links: Re-reads official course pages, searches again for courses with no page, and keeps link check dates current, on the schedule set per count |  |  |  |  |
| job | `logo-find` | L2 read | active | Logo finder: provider logos from their own websites: Every 10 minutes: reads the home page of providers with a website and no logo (asked-for providers first, t |  |  |  |  |
| job | `onboarding-pilot-snapshot` | L2 read | active | Snapshot the onboarding pilot: Hourly: records the onboarding pilot group by country — stages reached, courses with intakes, English, fee and delivery against w |  |  |  | switched off |
| job | `provider-contact-page` | L2 read | active | Find provider phone and email: Reads the provider's own home and contact pages for its public phone and email (direct reads, no Firecrawl). Fills only empty val |  |  |  | switched off |
| job | `provider-document-check-monthly` | L2 read | active | Fee documents check (monthly): Checks provider fee documents for new versions. |  |  |  |  |
| job | `provider-document-check-weekly-q4` | L2 read | active | Fee documents check (weekly, Oct to Dec): Checks provider fee documents weekly during the fee-publishing season. |  |  |  |  |
| job | `provider-facts` | L2 read | active | Find and read fee schedules, English policies and calendars: Finds each university's international fee schedule, English language policy and academic calendar o |  |  |  | switched off |
| job | `provider-onboarding` | L2 read | active | Onboard universities: Runs each university's onboarding a step at a time: website, course pages, sample pages, the model's proposal, save and apply, qualify, ce |  |  |  |  |
| job | `scholarship-ai-backfill` | L2 read | active | AI re-check of refused pages (nightly): While AI admission is on, queues the next universities whose refused pages have not been read with the active model and  |  |  |  |  |
| job | `scholarship-ai-extract` | L2 read | active | Read scholarship pages with AI: Sends queued scholarship pages to the active AI model (and the qualification sample to the model being qualified); each answer i |  |  |  |  |
| job | `scholarship-audience` | L2 read | active | Scholarship audience from wording: Hourly: reads who each active scholarship is for from its own name, description and criteria (international, domestic, both,  |  |  |  |  |
| job | `scholarship-auto-publish` | L2 read | active | Publish scholarships automatically: Publishes scholarships that pass every check, as one batch named auto-publish. |  |  |  |  |
| job | `scholarship-course-attribute` | L2 read | active | Course scholarship attribute: Every 15 minutes: refreshes the scholarships shown on each course (search, website, Zoho) for courses linked to a scholarship that |  |  |  |  |
| job | `scholarship-course-attribute-full` | L2 read | active | Course scholarship attribute (nightly sweep): Nightly at 06:51 AEST, after the publication review and the savings run: refreshes the scholarships shown on every |  |  |  |  |
| job | `scholarship-discover` | L2 read | active | Discover scholarships: Finds scholarship pages on provider websites. |  |  |  | switched off |
| job | `scholarship-discover-refill` | L2 read | active | Line up providers for discovery: Keeps 30 providers waiting for scholarship discovery, adding the largest not yet searched. |  |  |  |  |
| job | `scholarship-fee-alignment` | L2 read | active | Scholarship fee alignment: Recalculates savings for courses whose fee changed. |  |  |  |  |
| job | `scholarship-listing` | L2 read | active | Read scholarship listing pages: Reads each provider's scholarship listing page through the scraper for the coverage check. |  |  |  |  |
| job | `scholarship-nationality` | L2 read | active | Scholarship nationality from wording: Hourly: reads which nationalities each active scholarship names in its own wording (country names, demonyms and regions) a |  |  |  |  |
| job | `scholarship-publication-review` | L2 read | active | Nightly publication review: Withdraws published scholarships that no longer qualify. |  |  |  |  |
| job | `scholarship-read` | L2 read | active | Read scholarship pages: Reads each scholarship's own page and records value, levels, field and closing date. |  |  |  | switched off |
| job | `scholarship-reread-cadence` | L2 read | active | Re-read published scholarships monthly: Daily at 05:37 AEST: a published or ready-to-publish scholarship's page is re-read at least every 30 days, so a changed  |  |  |  |  |
| job | `scholarship-savings` | L2 read | active | Work out scholarship savings: Works out the saving a year for percentage-off-tuition scholarships from each course's annual international fee. |  |  |  |  |
| job | `university-reread-requests` | L2 read | active | University read-again requests: Sends university pages a person asked to read again to the reader. |  |  |  |  |
| screen | `Coverage & completeness` | L2 read | active | How complete each course is, and each attribute across all courses. |  |  |  |  |
| screen | `Coverage & completeness › Attributes` | L2 read | active |  |  |  |  |  |
| screen | `Coverage & completeness › Courses` | L2 read | active |  |  |  |  |  |
| screen | `Coverage & completeness › Flags` | L2 read | active |  |  |  |  |  |
| screen | `Coverage & completeness › Progress` | L2 read | active |  |  |  |  |  |
| screen | `Layer 2 Discovery & reading` | L2 read | active | University adapters: build, qualify, admit, switch on or off, and when the pages of each university are read again. |  |  |  |  |
| screen | `Layer 2 Discovery & reading › Adapter builder` | L2 read | active |  |  |  |  |  |
| screen | `Layer 2 Discovery & reading › Adapters` | L2 read | active |  |  |  |  |  |
| screen | `Layer 2 Discovery & reading › Enrich fields` | L2 read | active |  |  |  |  |  |
| screen | `Layer 2 Discovery & reading › Onboarding` | L2 read | active |  |  |  |  |  |
| screen | `Layer 2 Discovery & reading › Scholarships` | L2 read | active |  |  |  |  |  |
| screen | `Providers › Campuses` | L2 read | active |  |  |  |  |  |
| screen | `Scholarships` | L2 read | active | Scholarships, where each value came from, and what is published. |  |  |  |  |
| screen | `Scholarships › Coverage` | L2 read | active |  |  |  |  |  |
| screen | `Scholarships › Extraction` | L2 read | active |  |  |  |  |  |
| screen | `Scholarships › Scholarships` | L2 read | active |  |  |  |  |  |
| table | `catalogue.campuses` | L2 read | active |  |  | 5104 kB |  |  |
| table | `catalogue.course_campuses` | L2 read | active |  |  | 15 MB |  |  |
| table | `catalogue.course_links` | L2 read | active | Evidence-backed relational URLs for canonical Courses. courses.course_url remains a compatibility/current-primary field, not the multi-link source of truth. |  | 21 MB |  |  |
| table | `pipeline.adapter_autobuilds` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.adapter_overwrite_changes` | L2 read | active |  |  | 8584 kB |  |  |
| table | `pipeline.adapter_qualifications` | L2 read | active |  |  | 1192 kB |  |  |
| table | `pipeline.adapter_shadow_reads` | L2 read | active |  |  | 2440 kB |  |  |
| table | `pipeline.adapter_shadow_settings` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.campus_region_cleared` | L2 read | active |  |  | 72 kB |  |  |
| table | `pipeline.campus_regional_class` | L2 read | active |  |  | 608 kB |  |  |
| table | `pipeline.course_attribute_coverage` | L2 read | active |  |  | 47 MB |  |  |
| table | `pipeline.course_coverage_daily` | L2 read | active |  |  | 576 kB |  |  |
| table | `pipeline.course_coverage_daily_by_country` | L2 read | active |  |  | 1152 kB |  |  |
| table | `pipeline.course_host_pages` | L2 read | active |  |  | 600 kB |  |  |
| table | `pipeline.course_link_recipes` | L2 read | active |  |  | 1344 kB |  |  |
| table | `pipeline.course_link_reverse` | L2 read | active |  |  | 2384 kB |  |  |
| table | `pipeline.course_link_search` | L2 read | active |  |  | 33 MB |  |  |
| table | `pipeline.course_link_search_settings` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.coverage_course_pages` | L2 read | active |  |  | 52 MB |  |  |
| table | `pipeline.coverage_identity_cases` | L2 read | active |  |  | 208 kB |  |  |
| table | `pipeline.coverage_identity_results` | L2 read | active |  |  | 1024 kB |  |  |
| table | `pipeline.coverage_identity_sets` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.coverage_provider_discovery` | L2 read | active |  |  | 2160 kB |  |  |
| table | `pipeline.coverage_provider_urls` | L2 read | active |  |  | 332 MB |  |  |
| table | `pipeline.coverage_reidentify_done` | L2 read | active |  |  | 13 MB |  |  |
| table | `pipeline.coverage_vendor_usage` | L2 read | active |  |  | 48 MB |  |  |
| table | `pipeline.directory_pages` | L2 read | active |  |  | 2200 kB |  |  |
| table | `pipeline.enrich_coverage_snapshots` | L2 read | active |  |  | 216 kB |  |  |
| table | `pipeline.enrich_focus_providers` | L2 read | active | CF-247 15 Oct 2026: Australian providers ranked by missing English and intakes; in_focus = within enrich.focus_top_n. |  | 224 kB |  |  |
| table | `pipeline.enrichment_coverage_snapshots` | L2 read | active |  |  | 2704 kB |  |  |
| table | `pipeline.enrichment_flags` | L2 read | active | CF-247 flag unit (15 Oct 2026): one row per held item (provider, course field or job) and reason. state raised = held out of every queue; counting = a soft reas |  | 36 MB |  |  |
| table | `pipeline.field_enrich_items` | L2 read | active |  |  | 46 MB |  |  |
| table | `pipeline.firecrawl_budget_refusals` | L2 read | active |  |  | 72 kB |  |  |
| table | `pipeline.firecrawl_calls` | L2 read | active |  |  | 10 MB |  |  |
| table | `pipeline.firecrawl_panel_figures` | L2 read | active |  |  | 64 kB |  |  |
| table | `pipeline.firecrawl_refusals_by_provider` | L2 read | active |  |  | 96 kB |  |  |
| table | `pipeline.firecrawl_run_items` | L2 read | active |  |  | 20 MB |  |  |
| table | `pipeline.firecrawl_runs` | L2 read | active |  |  | 520 kB |  |  |
| table | `pipeline.firecrawl_search_holds` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.firecrawl_search_resumes` | L2 read | active |  |  | 16 kB |  |  |
| table | `pipeline.firecrawl_target_cache` | L2 read | active |  |  | 1896 kB |  |  |
| table | `pipeline.firecrawl_targets` | L2 read | active |  |  | 216 kB |  |  |
| table | `pipeline.layer2_acquisition_providers` | L2 read | active |  |  | 80 kB |  |  |
| table | `pipeline.layer2_auto_discovery_attempts` | L2 read | active |  |  | 184 kB |  |  |
| table | `pipeline.layer2_auto_discovery_settings` | L2 read | active |  |  | 24 kB |  |  |
| table | `pipeline.layer2_auto_discovery_settings_audit` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.layer2_completeness_trial_courses` | L2 read | active |  |  | 136 kB |  |  |
| table | `pipeline.layer2_completeness_trials` | L2 read | active |  |  | 48 kB |  |  |
| table | `pipeline.layer2_country_completeness_profiles` | L2 read | active |  |  | 48 kB |  |  |
| table | `pipeline.layer2_course_discovery_candidates` | L2 read | active |  |  | 3168 kB |  |  |
| table | `pipeline.layer2_domain_refresh_policies` | L2 read | retiring |  |  | 32 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.layer2_enrichment_hourly_admin_cache_v1` | L2 read | active |  |  | 96 kB |  |  |
| table | `pipeline.layer2_execution_policies` | L2 read | active |  |  | 96 kB |  |  |
| table | `pipeline.layer2_execution_policy` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.layer2_fanout_tasks` | L2 read | retiring |  |  | 272 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.layer2_onboarding_snapshot` | L2 read | active |  |  | 792 kB |  |  |
| table | `pipeline.layer2_profile_provider_routes` | L2 read | active |  |  | 8944 kB |  |  |
| table | `pipeline.layer2_provider_attempts` | L2 read | active |  |  | 9256 kB |  |  |
| table | `pipeline.layer2_provider_benchmark_observations` | L2 read | retiring |  |  | 120 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.layer2_provider_catalogue_submissions` | L2 read | active |  |  | 208 kB |  |  |
| table | `pipeline.layer2_provider_environment_gates` | L2 read | active | Scraper/acquisition-provider qualification per environment. Provider config and credentials remain separate. |  | 32 kB |  |  |
| table | `pipeline.layer2_provider_probe_requests` | L2 read | active |  |  | 64 kB |  |  |
| table | `pipeline.layer2_provider_trial_results` | L2 read | active |  |  | 56 kB |  |  |
| table | `pipeline.layer2_run_batches` | L2 read | active |  |  | 504 kB |  |  |
| table | `pipeline.layer2_run_items` | L2 read | active |  |  | 27 MB |  |  |
| table | `pipeline.layer2_scale_qualification_items` | L2 read | active |  |  | 11 MB |  |  |
| table | `pipeline.layer2_scale_qualification_runs` | L2 read | active |  |  | 232 kB |  |  |
| table | `pipeline.layer2_scholarship_discovery_candidates` | L2 read | active | Layer 2 Scholarship discovery candidates. CF-198 adds only bounded verified first-party UQ/UWA detail seeds backed by newly captured catalogue Evidence; automat |  | 2880 kB |  |  |
| table | `pipeline.layer2_scope_wave_items` | L2 read | retiring |  |  | 37 MB |  | Usage audit 15 Oct 2026, decision D9 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.layer2_scope_wave_requests` | L2 read | active |  |  | 104 kB |  |  |
| table | `pipeline.layer2_shared_fetches` | L2 read | active |  |  | 504 kB |  |  |
| table | `pipeline.layer2_source_profile_versions` | L2 read | active |  |  | 18 MB |  |  |
| table | `pipeline.layer2_source_profiles` | L2 read | active |  |  | 2840 kB |  |  |
| table | `pipeline.layer2_tuning_events` | L2 read | active |  |  | 48 kB |  |  |
| table | `pipeline.onboarding_cases` | L2 read | active |  |  | 128 kB |  |  |
| table | `pipeline.onboarding_lifecycle_events` | L2 read | active |  |  | 64 kB |  |  |
| table | `pipeline.onboarding_pilot` | L2 read | active |  |  | 96 kB |  |  |
| table | `pipeline.onboarding_pilot_snapshots` | L2 read | active |  |  | 96 kB |  |  |
| table | `pipeline.page_link_repairs` | L2 read | active |  |  | 13 MB |  |  |
| table | `pipeline.provider_central_search` | L2 read | active | CF-247 Feature 4 (11 Oct 2026): central pages (key dates, international fees, English requirements) suggested from a Firecrawl map of the provider's own site. S |  | 1584 kB |  |  |
| table | `pipeline.provider_contact_enrichment_attempts` | L2 read | active |  |  | 600 kB |  |  |
| table | `pipeline.provider_discovery_links` | L2 read | active |  |  | 103 MB |  |  |
| table | `pipeline.provider_logo_finds` | L2 read | active | Logo finder (CF-247, 15 Oct 2026): one row per provider the background job has checked or a person has asked it to check; what was found, from which page and ho |  | 744 kB |  |  |
| table | `pipeline.provider_onboarding` | L2 read | active |  |  | 1560 kB |  |  |
| table | `pipeline.provider_onboarding_events` | L2 read | active |  |  | 14 MB |  |  |
| table | `pipeline.provider_onboarding_settings` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.provider_scholarship_search` | L2 read | active |  |  | 64 kB |  |  |
| table | `pipeline.provider_scholarship_search_log` | L2 read | active |  |  | 64 kB |  |  |
| table | `pipeline.rule6_page_checks` | L2 read | active |  |  | 184 kB |  |  |
| table | `pipeline.scholarship_acquisition_trace` | L2 read | active |  |  | 1792 kB |  |  |
| table | `pipeline.scholarship_attribute_sync` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_catalogue_runs` | L2 read | active |  |  | 152 kB |  |  |
| table | `pipeline.scholarship_coverage_benchmarks` | L2 read | active |  |  | 80 kB |  |  |
| table | `pipeline.scholarship_coverage_checks` | L2 read | active |  |  | 16 kB |  |  |
| table | `pipeline.scholarship_discovery_providers` | L2 read | active |  |  | 536 kB |  |  |
| table | `pipeline.scholarship_etl_schedules` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_jobs` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_layer_settings` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_listing_pages` | L2 read | active |  |  | 192 kB |  |  |
| table | `pipeline.scholarship_maintenance_runs` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_page_candidates` | L2 read | active |  |  | 81 MB |  |  |
| table | `pipeline.scholarship_page_searches` | L2 read | active |  |  | 208 kB |  |  |
| table | `pipeline.scholarship_pages` | L2 read | active |  |  | 10 MB |  |  |
| table | `pipeline.scholarship_publication_batches` | L2 read | active |  |  | 96 kB |  |  |
| table | `pipeline.scholarship_publication_holds` | L2 read | active |  |  | 64 kB |  |  |
| table | `pipeline.scholarship_reread_snapshots` | L2 read | retiring |  |  | 136 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.scholarship_runtime_settings` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_scope_acquisition_requests` | L2 read | active |  |  | 104 kB |  |  |
| table | `pipeline.scholarship_scope_decisions` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_skip_rules` | L2 read | active |  |  | 48 kB |  |  |
| table | `pipeline.scholarship_source_qualifications` | L2 read | active |  |  | 64 kB |  |  |
| table | `pipeline.scholarship_source_records` | L2 read | active |  |  | 1600 kB |  |  |
| table | `pipeline.scholarship_sweep_changes` | L2 read | active |  |  | 5704 kB |  |  |
| table | `pipeline.scholarship_watch` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.site_hint_checks` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.uni_adapter_delivery_exclusions` | L2 read | active |  |  | 192 kB |  |  |
| table | `pipeline.uni_adapter_drafts` | L2 read | active |  |  | 20 MB |  |  |
| table | `pipeline.uni_adapter_exclusions` | L2 read | active |  |  | 1144 kB |  |  |
| table | `pipeline.uni_adapter_models` | L2 read | active |  |  | 16 kB |  |  |
| table | `pipeline.uni_adapter_requests` | L2 read | active |  |  | 72 kB |  |  |
| table | `pipeline.uni_adapter_results` | L2 read | active |  |  | 48 MB |  |  |
| table | `pipeline.uni_adapters` | L2 read | active |  |  | 1976 kB |  |  |
| table | `pipeline.website_reference_cache` | L2 read | active |  |  | 232 kB |  |  |
| table | `pipeline.website_sync_items` | L2 read | active |  |  | 162 MB |  |  |
| table | `pipeline.website_sync_scan` | L2 read | active |  |  | 32 kB |  |  |
| table | `private.website_integration_credentials` | L2 read | active |  |  | 32 kB |  |  |
| table | `private.website_integration_rate_windows` | L2 read | active |  |  | 32 kB |  |  |
| table | `scholarship.application_windows` | L2 read | active |  |  | 152 kB |  |  |
| table | `scholarship.audience_readings` | L2 read | active |  |  | 552 kB |  |  |
| table | `scholarship.award_tiers` | L2 read | active |  |  | 672 kB |  |  |
| table | `scholarship.country_onboarding` | L2 read | active |  |  | 32 kB |  |  |
| table | `scholarship.course_financial_calculations` | L2 read | active |  |  | 39 MB |  |  |
| table | `scholarship.course_mapping_candidates` | L2 read | active | Human-review Scholarship→Course candidates. CF-200 expands candidates only for evidence-backed UQ/UWA provider-course scope; no candidate becomes a mapped Cours |  | 22 MB |  |  |
| table | `scholarship.course_mappings` | L2 read | active |  |  | 98 MB |  |  |
| table | `scholarship.coverage` | L2 read | active |  |  | 160 kB |  |  |
| table | `scholarship.criteria` | L2 read | active |  |  | 3440 kB |  |  |
| table | `scholarship.criterion_groups` | L2 read | active |  |  | 208 kB |  |  |
| table | `scholarship.identifiers` | L2 read | active |  |  | 1984 kB |  |  |
| table | `scholarship.nationality_readings` | L2 read | active |  |  | 392 kB |  |  |
| table | `scholarship.offering_cycles` | L2 read | active |  |  | 272 kB |  |  |
| table | `scholarship.scholarships` | L2 read | active |  |  | 2120 kB |  |  |
| table | `scholarship.scopes` | L2 read | active |  |  | 4320 kB |  |  |
| table | `search.enrichment_gates` | L2 read | active |  |  | 32 kB |  |  |
| table | `search.enrichment_source_gates` | L2 read | active |  |  | 1128 kB |  |  |
| view | `pipeline.au_nz_enrichment_backlog_summary_v1` | L2 read | active | CF-245 AU/NZ enrichment backlog summary by field/state/reason. |  |  |  |  |
| view | `pipeline.au_nz_enrichment_backlog_v1` | L2 read | active | CF-245 per-course/per-field AU/NZ enrichment demand classification. Missing values are never synthesized. |  |  |  |  |
| view | `pipeline.layer2_enrichment_hourly_v1` | L2 read | active | CF-245 hourly enrichment outcome metrics; service-role only until governed Admin read projection is added. |  |  |  |  |
| view | `pipeline.layer2_enrichment_operational_ledger_v1` | L2 read | active | CF-245 governed operational ledger derived from Layer 2 run items, jobs, attempts, Evidence, candidates and Search state. Observability only; no mutation author |  |  |  |  |
| view | `pipeline.scholarship_candidate_classification_stats` | L2 read | active |  |  |  |  |  |
| view | `pipeline.scholarship_provider_stats` | L2 read | active | Internal scholarship provider summary for operational completeness and traceability. Landscape benchmark fields are non-authoritative internal coverage signals  |  |  |  |  |
| view | `pipeline.scholarship_verified_detail_reconciliation_candidates` | L2 read | active | CF-194 current-state reconciliation boundary: captured/applied Evidence only; individual first-party international Scholarship details only; generic/support/fil |  |  |  |  |
| view | `public.scholarship_catalogue_v2` | L2 read | active |  |  |  |  |  |
| edge_function | `layer3-provider-control` | L3 interpret | active |  |  |  |  |  |
| job | `coverage-ai-match` | L3 interpret | active | AI course page matching: Asks the tested AI model whether each candidate page is the course's own page. |  |  |  | switched off |
| job | `coverage-ai-match-prepare` | L3 interpret | active | Prepare AI course page matching: Picks the candidate pages that need an AI match next. |  |  |  |  |
| job | `fee-period-settle` | L3 interpret | active | Settle fee periods from page wording: Confirms a fee added as per year when the page wording it quoted says per year, or the course runs a year or less. Anythin |  |  |  |  |
| table | `pipeline.central_ai_queue` | L3 interpret | active |  |  | 216 kB |  |  |
| table | `pipeline.central_ai_settings` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.coverage_ai_match` | L3 interpret | active |  |  | 62 MB |  |  |
| table | `pipeline.layer3_benchmark_jobs` | L3 interpret | active |  |  | 80 kB |  |  |
| table | `pipeline.layer3_fact_handoffs` | L3 interpret | active |  |  | 18 MB |  | Usage audit 15 Oct 2026, decisions D6 and D7: rows nothing live uses exported to Storage and purged by paste file; still used rows kept |
| table | `pipeline.layer3_holdout_cases` | L3 interpret | active |  |  | 168 kB |  |  |
| table | `pipeline.layer3_holdout_results` | L3 interpret | active |  |  | 1832 kB |  |  |
| table | `pipeline.layer3_holdout_sets` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.layer3_intake_benchmark_cases` | L3 interpret | active | CF-247 A3: gold set of sweep course pages with the true international intake months (or not stated), justified by a verbatim excerpt of the stored page text; te |  | 136 kB |  |  |
| table | `pipeline.layer3_intake_benchmark_results` | L3 interpret | active | CF-247 A3: per-case Layer 2 and Layer 3 intake results against the gold set, one row per benchmark run and case, with OpenRouter usage. |  | 248 kB |  |  |
| table | `pipeline.layer3_intake_gold_sets` | L3 interpret | active | CF-247 A3: frozen intake gold sets (sha256 of every case's answer fields, in case_key order). A benchmark run is refused when the current digest differs. |  | 32 kB |  |  |
| table | `pipeline.layer3_interpretations` | L3 interpret | active |  |  | 203 MB |  | Usage audit 15 Oct 2026, decisions D6 and D7: rows nothing live uses exported to Storage and purged by paste file; still used rows kept |
| table | `pipeline.layer3_model_profiles` | L3 interpret | active | M2.4 Layer 3 model profiles. A16 international-contact profile uses retry_ceiling=2 only after immutable benchmark evidence showed malformed structured output;  |  | 352 kB |  |  |
| table | `pipeline.layer3_openrouter_observations` | L3 interpret | active |  |  | 6792 kB |  |  |
| table | `pipeline.layer3_profile_activation_events` | L3 interpret | active |  |  | 72 kB |  |  |
| table | `pipeline.layer3_profile_environment_gates` | L3 interpret | active | AI model/task profile qualification per environment. No profile receives generic canonical mutation authority. |  | 32 kB |  |  |
| table | `pipeline.layer3_provider_credential_audit` | L3 interpret | active |  |  | 48 kB |  |  |
| table | `pipeline.layer3_quality_benchmark_runs` | L3 interpret | active |  |  | 480 kB |  |  |
| table | `pipeline.layer3_route_budget` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.layer3_route_events` | L3 interpret | active |  |  | 80 kB |  |  |
| table | `pipeline.layer3_route_tiers` | L3 interpret | active | CF-247 Layer 3 cascade ladder per task class (Platform Admin direction 29 Sep 2026 20:38 IST). Active rows are used only when layer3_route_budget.route_mode = l |  | 104 kB |  |  |
| table | `pipeline.layer3_task_contract_freezes` | L3 interpret | active |  |  | 48 kB |  |  |
| table | `pipeline.layer3_tier_audits` | L3 interpret | active |  |  | 264 kB |  |  |
| table | `pipeline.layer3_work_item_rebinds` | L3 interpret | retiring |  |  | 32 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.layer3_work_items` | L3 interpret | active |  |  | 75 MB |  | Usage audit 15 Oct 2026, decisions D6 and D7: rows nothing live uses exported to Storage and purged by paste file; still used rows kept |
| table | `pipeline.scholarship_ai_extract_settings` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_ai_extractions` | L3 interpret | active |  |  | 58 MB |  |  |
| table | `pipeline.scholarship_ai_models` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_ai_prompts` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_ai_queue` | L3 interpret | active |  |  | 14 MB |  |  |
| table | `pipeline.scholarship_ai_reviews` | L3 interpret | active |  |  | 2200 kB |  |  |
| table | `pipeline.scholarship_ai_run_items` | L3 interpret | active |  |  | 40 kB |  |  |
| table | `pipeline.scholarship_ai_runs` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_ai_sample` | L3 interpret | active |  |  | 80 kB |  |  |
| table | `pipeline.scholarship_ai_settings` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `security.layer3_aggregator_credentials` | L3 interpret | active |  |  | 32 kB |  |  |
| view | `pipeline.cf245_layer3_fee_validation_backlog_v1` | L3 interpret | active |  |  |  |  |  |
| job | `adapter-overwrite` | L4 admit | active | Adapter values replace older ones: Where a university adapter is admitted, its values replace older values from other sources. Runs only when new input has arri |  |  |  |  |
| job | `coverage-admit` | L4 admit | active | Admit official page and English: Writes checked facts (official page, English scores) where the course has none; differences go to Layer 4. Runs only when new i |  |  |  |  |
| job | `coverage-admit-intakes` | L4 admit | active | Admit intakes from course pages: Admits intakes read from accepted course pages. Runs only when new input has arrived, with a full check every few hours (Waste  |  |  |  |  |
| job | `exit-awards-apply` | L4 admit | active | Exit awards take parent values: Gives exit awards the values of their single-degree parent once the register check passes. |  |  |  |  |
| job | `fee-wording-rules` | L4 admit | active | Apply approved fee wording rules: Admits international tuition from newly read pages using the fee wording rules approved in Layer 4 › Batch rules. |  |  |  |  |
| job | `host-pages-apply` | L4 admit | active | Hosted courses take host page values: Gives courses carried on a host page the values on that page once host pages are admitted. |  |  |  |  |
| job | `l4-rule-fee-year-align` | L4 admit | active | Review rule: fee year: Sends fees whose year does not match the intake year to review. |  |  |  |  |
| job | `l4-rule-low-agreement` | L4 admit | active | Review rule: sources disagree: Sends values that sources disagree on to review. |  |  |  |  |
| job | `l4-rule-unofficial-source` | L4 admit | active | Review rule: unofficial source: Sends values that came only from an unofficial source to review. |  |  |  |  |
| job | `policy-auto-approve` | L4 admit | active | Approve checked AI readings of central pages: Every 10 minutes: approves an AI reading of a focus provider's English policy or calendar when every value is quot |  |  |  |  |
| job | `provider-basis-rule-admit` | L4 admit | active | Admit tuition under provider fee rules: Writes fees covered by an approved rule for how a provider states its fees. |  |  |  |  |
| job | `provider-calendar-defaults` | L4 admit | active | College intakes from the approved calendar: Every 10 minutes: for an Australian college (not a university) with an approved academic calendar, gives Intake 1 an |  |  |  |  |
| job | `provider-calendar-intakes` | L4 admit | active | Answer semester-only intakes from calendars: Every 10 minutes: answers a waiting intake review whose course page names only its study periods ("Semester 1", "Tr |  |  |  |  |
| job | `provider-english-defaults` | L4 admit | active | Apply approved English policies: Every 10 minutes: works out each English policy's course-by-course plan, then gives courses the English requirement from their  |  |  |  |  |
| job | `provider-fee-profiles-apply` | L4 admit | active | Apply provider fee profiles: Applies provider fee schedules to their courses. |  |  |  |  |
| job | `provider-rule-admit` | L4 admit | active | Admit facts under provider rules: Writes facts covered by approved provider rules. |  |  |  |  |
| screen | `Layer 4 Review` | L4 admit | active | Decisions that need a person, with an audit trail. |  |  |  |  |
| screen | `Layer 4 Review › AI could not decide` | L4 admit | active |  |  |  |  |  |
| screen | `Layer 4 Review › Review queue` | L4 admit | active |  |  |  |  |  |
| screen | `Layer 4 Review › Websites to find` | L4 admit | active |  |  |  |  |  |
| table | `pipeline.admission_lifecycle_policy` | L4 admit | active |  |  | 32 kB |  |  |
| table | `pipeline.course_exit_awards` | L4 admit | active |  |  | 536 kB |  |  |
| table | `pipeline.course_page_blocks` | L4 admit | active |  |  | 88 kB |  |  |
| table | `pipeline.coverage_admission_countries` | L4 admit | active |  |  | 64 kB |  |  |
| table | `pipeline.fee_rule_admissions` | L4 admit | active |  |  | 184 kB |  |  |
| table | `pipeline.layer2_field_admissions` | L4 admit | active |  |  | 720 kB |  |  |
| table | `pipeline.layer4_block_decisions` | L4 admit | active | Append-only reversible governance decisions. Blocking is state, never deletion; each scope is independent. |  | 48 kB |  |  |
| table | `pipeline.layer4_course_field_resolutions` | L4 admit | active |  |  | 48 kB |  |  |
| table | `pipeline.layer4_decisions` | L4 admit | active |  |  | 728 kB |  |  |
| table | `pipeline.layer4_field_registry` | L4 admit | active |  |  | 32 kB |  |  |
| table | `pipeline.layer4_mass_operations` | L4 admit | active |  |  | 136 kB |  |  |
| table | `pipeline.layer4_override_decisions` | L4 admit | active | A16 append-only Layer 4 effective-value override ledger. Source/canonical history is not overwritten. |  | 32 kB |  |  |
| table | `pipeline.layer4_publication_decisions` | L4 admit | active | A16 separate append-only publication override decisions. Does not itself authorise Production/Website/Zoho cutover. |  | 48 kB |  |  |
| table | `pipeline.layer4_quality_findings` | L4 admit | active |  |  | 24 kB |  |  |
| table | `pipeline.layer4_reroutes` | L4 admit | active |  |  | 2000 kB |  |  |
| table | `pipeline.layer4_review_items` | L4 admit | active |  |  | 37 MB |  |  |
| table | `pipeline.layer4_rule_runs` | L4 admit | active |  |  | 64 kB |  |  |
| table | `pipeline.layer4_scope_rules` | L4 admit | active |  |  | 24 kB |  |  |
| table | `pipeline.provider_rule_admissions` | L4 admit | active |  |  | 144 kB |  |  |
| table | `pipeline.scholarship_admission_log` | L4 admit | active |  |  | 5976 kB |  |  |
| table | `pipeline.uni_adapter_previews` | L4 admit | active |  |  | 9672 kB |  |  |
| table | `publishing.channels` | L4 admit | active |  |  | 32 kB |  |  |
| table | `publishing.entity_states` | L4 admit | active |  |  | 48 kB |  |  |
| table | `publishing.publication_approvals` | L4 admit | active |  |  | 48 kB |  |  |
| table | `publishing.publication_events` | L4 admit | active |  |  | 64 kB |  |  |
| table | `publishing.publication_profiles` | L4 admit | active |  |  | 32 kB |  |  |
| table | `workflow.review_actions` | L4 admit | active |  |  | 40 kB |  |  |
| table | `workflow.review_queue` | L4 admit | active |  |  | 64 kB |  |  |
| view | `public.review_queue` | L4 admit | active |  |  |  |  |  |
| view | `security.layer4_active_blocks` | L4 admit | active |  |  |  |  |  |
| view | `security.layer4_search_blocked_campuses` | L4 admit | active |  |  |  |  |  |
| view | `security.layer4_search_blocked_courses` | L4 admit | active |  |  |  |  |  |
| view | `security.layer4_search_blocked_providers` | L4 admit | active |  |  |  |  |  |
| view | `security.layer4_search_blocked_scholarships` | L4 admit | active |  |  |  |  |  |
| function | `public.svc_provider_english_add_tests_v1` | Layer 2 | active | Adds a newly read test to an approved English policy and its level-default courses |  |  |  |  |
| function | `public.svc_provider_policy_add_tests_next` | Layer 2 | active | Approved English policies not yet checked by the current parser |  |  |  |  |
| job | `policy-add-tests` | Layer 2 | active | English policies: add new tests: Hourly: reads approved English policy pages again from their stored copies (no Firecrawl, no AI) and adds tests the parser has  |  |  |  |  |
| table | `pipeline.layer3_call_costs_hourly` | Layer 3 (retired) | active | CF-247 15 Oct 2026 (usage audit D7): Layer 3 AI calls, tokens and estimated cost per hour, summed from layer3_interpretations before it was purged. Platform res |  | 40 kB |  |  |
| table | `pipeline.layer3_validated_readings` | Layer 3 (retired) | active | CF-247 15 Oct 2026 (usage audit D7): every validated Layer 3 reading of intakes, English and tuition, copied from layer3_interpretations (same id, value and tim |  | 4976 kB |  |  |
| edge_function | `admin-evidence-access` | Platform | active |  |  |  |  |  |
| edge_function | `admin-user-management` | Platform | active |  | 2026-10-16 |  |  |  |
| edge_function | `evidence-link-index` | Platform | active | Package 7 (Decision 146): evidence link index. | 2026-10-16 |  |  |  |
| edge_function | `evidence-storage-dedupe` | Platform | active | CF-247 / Decision 155 step 5: remove redundant copies of identical evidence files. | 2026-10-16 |  |  |  |
| edge_function | `fee-schedule-etl` | Platform | active | CF-247 Decision 162 step 2: provider international fee schedules (one document per provider per fee year). |  |  |  |  |
| edge_function | `platform-environment-control` | Platform | active |  | 2026-10-16 |  |  |  |
| edge_function | `provider-asset-access` | Platform | active |  | 2026-10-16 |  |  |  |
| edge_function | `provider-asset-upload` | Platform | active |  |  |  |  |  |
| edge_function | `provider-contact-control` | Platform | active |  |  |  |  |  |
| edge_function | `provider-contact-import` | Platform | active |  |  |  |  |  |
| edge_function | `toolset-runner` | Platform | active | CF-247 Decision 252 (4 Oct 2026, amended 14:26): sample runs of Serper (web search) and ScrapingBee (browser rendering) |  |  |  |  |
| function | `public.admin_flags(text,jsonb)` | Platform | active | Flags screen |  |  |  |  |
| function | `security.flag_recheck_v1()` | Platform | active | Flag unit recheck |  |  |  |  |
| function | `security.housekeeping_daily_v1` | Platform | active | Daily housekeeping run (settings retention.nonce_keep_days, retention.job_log_keep_days, batch.housekeeping_rows) |  |  |  |  |
| job | `admin-jobs` | Platform | active | Task manager tasks: Moves every waiting or running task in Task manager on by one step each minute (adapters, page reads, Firecrawl runs, scholarship tasks). |  |  |  |  |
| job | `admin-summary-snapshots-refresh` | Platform | active | Admin summary figures: Refreshes dashboard summary figures. |  |  |  |  |
| job | `course-completeness-build` | Platform | active | Completeness score: Works out how complete each course and provider is. |  |  |  |  |
| job | `course-coverage-build` | Platform | active | Coverage by attribute: Works out coverage state per course attribute. |  |  |  |  |
| job | `course-field-source-build` | Platform | active | Who supplied each course value: Rebuilds the record of which source supplied each course value, for the Attributes panel. |  |  |  |  |
| job | `coursefinder-cf245-enrichment-coverage-snapshot` | Platform | active | Enrichment coverage snapshot: Hourly snapshot of enrichment coverage. |  |  |  |  |
| job | `coursefinder-cf245-enrichment-hourly-admin-cache` | Platform | active | Admin figures cache: Refreshes figures shown on admin screens. |  |  |  |  |
| job | `coursefinder-data-quality-overview-refresh` | Platform | active | Data quality overview: Daily data quality figures. |  |  |  |  |
| job | `coursefinder-platform-capacity-observation` | Platform | active | Capacity reading: Records platform capacity daily. |  |  |  |  |
| job | `cron-history-retention` | Platform | retiring | Trim job history: Deletes job history older than 14 days. Retired 16 Oct 2026: replaced by Daily housekeeping (housekeeping-daily). |  |  | housekeeping-daily | switched off |
| job | `cron-history-trim` | Platform | retiring | Trim scheduler run history: Keeps the last 3 days of scheduled-job run history (about 30,000 runs a day) so the Automations and Task manager screens stay fast.  |  |  | housekeeping-daily | switched off |
| job | `enrich-coverage-snapshot` | Platform | active | Field coverage snapshot: Every hour: per country and field, how many active courses have the field. Shown on Layer 2 › Enrich fields. |  |  |  |  |
| job | `evidence-filter-options-refresh` | Platform | active | Evidence filter options: Refreshes the filters on the Evidence screen. |  |  |  |  |
| job | `evidence-link-index` | Platform | active | Index evidence links: Links saved evidence to the records it supports. |  |  |  |  |
| job | `evidence-storage-dedupe-daily` | Platform | active | Remove duplicate evidence files: Deletes duplicate copies of saved evidence files. |  |  |  |  |
| job | `firecrawl-credit` | Platform | active | Check the Firecrawl balance: Reads the Firecrawl account balance every 15 minutes; the budget guard uses it when it is lower than the platform's own count. |  |  |  |  |
| job | `firecrawl-panel-figures` | Platform | active | Firecrawl panel figures: Refreshes the credit and result figures shown on the Firecrawl panel. |  |  |  |  |
| job | `firecrawl-runs` | Platform | active | Firecrawl runs: Moves each Firecrawl run on by one step each minute and closes it when its pages are done or its credit cap is reached. |  |  |  |  |
| job | `firecrawl-targets` | Platform | active | Firecrawl target lists: Refreshes the lists of pages each Firecrawl use case can be run on. |  |  |  |  |
| job | `flag-recheck` | Platform | active | Flags: hold, recheck and release: Every 10 minutes: pauses worker jobs whose recent runs found nothing (trial run on a back-off), releases flags whose date has  |  |  |  |  |
| job | `housekeeping-daily` | Platform | active | Daily housekeeping: Daily (about 03:47 Melbourne): removes expired one-time request codes and scheduled-job run records older than their settings (Settings › Pi |  |  |  |  |
| job | `hygiene-check` | Platform | active | Housekeeping: component register and hygiene check: Weekly: brings the component register up to date with the live jobs, tables and views, records usage counter |  |  |  |  |
| job | `openrouter-balance` | Platform | active | Read the OpenRouter balance: Every 15 minutes: reads the OpenRouter balance the AI uses (scholarship pages, adapter proposals, central pages, course-page matchi |  |  |  |  |
| job | `platform-health` | Platform | active | Platform health checks: Checks jobs, queues, budgets and the database, and records issues. |  |  |  |  |
| job | `platform-resource-observe` | Platform | active | Resource usage reading: Records database size and connections every hour. |  |  |  |  |
| job | `progress-snapshot` | Platform | active | Snapshot progress (hourly): Hourly at :09: refreshes each onboarding university's courses, fields and scholarships, and records the Progress overview for all un |  |  |  |  |
| job | `provider-fee-ranges-refresh` | Platform | active | University fee ranges: Works out each university's lowest and highest whole-course fee. |  |  |  |  |
| job | `provider-priority-refresh` | Platform | active | Rank providers by size: Ranks providers by number of active courses so the largest (top universities) are worked first. |  |  |  |  |
| job | `retention-worker` | Platform | active | Data retention: Removes logs and copies older than their retention period, a small batch at a time. |  |  |  |  |
| job | `storage-size-daily` | Platform | active | Storage sizes: daily record: Daily (about 00:25 Melbourne): records the size of the database, each schema, each table (rows, table, index and TOAST bytes) and e |  |  |  |  |
| job | `studysearch-codes` | Platform | active | Give StudySearch codes: Courses with no code printed by the university or regulator get a short StudySearch code (university, level, number). A code never chang |  |  |  |  |
| job | `waste-guard` | Platform | active | Waste rules: pause idle jobs, freeze flip-flops, flag: Hourly: pauses a watched job that produced nothing with nothing waiting (and switches it on again when wo |  |  |  |  |
| screen | `API usage` | Platform | active | Zoho API v2 and Website API v2: calls, success and failure, last use, full loads and deltas, bandwidth; rotate or switch off keys |  |  |  |  |
| screen | `Courses` | Platform | active | Every course, with its sources and evidence. |  |  |  |  |
| screen | `Dashboard` | Platform | active | What needs attention today, and recent activity. |  |  |  |  |
| screen | `Data model` | Platform | active | Attributes, families, groups and options. |  |  |  |  |
| screen | `Evidence` | Platform | active | Saved source pages and files, and what they changed. |  |  |  |  |
| screen | `Go-live checklist` | Platform | active | What must be set up and pass before Production is switched on. |  |  |  |  |
| screen | `Guides` | Platform | active | How to run the platform: the Platform guide, and the standard operating procedures for Platform Admins and operators. |  |  |  |  |
| screen | `Guides › Operator SOP` | Platform | active |  |  |  |  |  |
| screen | `Guides › Platform Admin SOP` | Platform | active |  |  |  |  |  |
| screen | `Guides › Platform guide` | Platform | active |  |  |  |  |  |
| screen | `Models & services` | Platform | active | Switch AI models and page-fetching services on or off; configure the AI that runs now and OpenRouter; and the limits each layer depends on. |  |  |  |  |
| screen | `Models & services › AI & OpenRouter` | Platform | active |  |  |  |  |  |
| screen | `Models & services › Services` | Platform | active |  |  |  |  |  |
| screen | `Models & services › Toolsets & limits` | Platform | active |  |  |  |  |  |
| screen | `Platform health` | Platform | active | Automatic checks across jobs, queues, budgets and the database. |  |  |  |  |
| screen | `Platform health › Capacity` | Platform | active |  |  |  |  |  |
| screen | `Platform health › Health checks` | Platform | active |  |  |  |  |  |
| screen | `Provider contacts` | Platform | active | International recruitment contacts for each provider. |  |  |  |  |
| screen | `Providers` | Platform | active | Providers, their campuses and their logos. |  |  |  |  |
| screen | `Providers › Archived` | Platform | active |  |  |  |  |  |
| screen | `Providers › Logos & assets` | Platform | active |  |  |  |  |  |
| screen | `Providers › Providers` | Platform | active |  |  |  |  |  |
| screen | `Reference data` | Platform | active | Ranking files, key dates and the third-party sites the platform refers to. |  |  |  |  |
| screen | `Reference data › Key dates` | Platform | active |  |  |  |  |  |
| screen | `Reference data › Reference sources` | Platform | active |  |  |  |  |  |
| screen | `Scheduled jobs` | Platform | active | Every automation the platform runs, the order work is taken in, job history and refresh schedules. |  |  |  |  |
| screen | `Scheduled jobs › Automations` | Platform | active |  |  |  |  |  |
| screen | `Scheduled jobs › Jobs` | Platform | active |  |  |  |  |  |
| screen | `Scheduled jobs › Priority queue` | Platform | active |  |  |  |  |  |
| screen | `Scheduled jobs › Task manager` | Platform | active |  |  |  |  |  |
| screen | `Scrapers & fetchers` | Platform | active | How pages are fetched: services, keys and limits. |  |  |  |  |
| screen | `Settings` | Platform | active | Every pipeline setting in one place, by step: throughput, reading, page identity and budgets; keys for outside services below (never shown). |  |  |  |  |
| screen | `Sources` | Platform | active | Every source the pipeline reads, across all layers, with its health and history. |  |  |  |  |
| screen | `Storage & retention` | Platform | active | What takes space in the database and file storage, the rule for each category, and purging it. |  |  |  |  |
| screen | `Users & roles` | Platform | active | Who can sign in and what each person may do. |  |  |  |  |
| table | `integration.extraction_profiles` | Platform | active |  |  | 40 kB |  |  |
| table | `integration.model_profiles` | Platform | active |  |  | 24 kB |  |  |
| table | `integration.systems` | Platform | active |  |  | 88 kB |  |  |
| table | `pim.attribute_definitions` | Platform | active |  |  | 112 kB |  |  |
| table | `pim.attribute_families` | Platform | active |  |  | 48 kB |  |  |
| table | `pim.attribute_groups` | Platform | active |  |  | 48 kB |  |  |
| table | `pim.attribute_options` | Platform | active |  |  | 32 kB |  |  |
| table | `pim.attribute_values` | Platform | active |  |  | 160 kB |  |  |
| table | `pim.categories` | Platform | active |  |  | 40 kB |  |  |
| table | `pim.completeness_profiles` | Platform | active |  |  | 40 kB |  |  |
| table | `pim.completeness_requirements` | Platform | active |  |  | 32 kB |  |  |
| table | `pim.entity_categories` | Platform | active |  |  | 16 kB |  |  |
| table | `pim.entity_registry` | Platform | active |  |  | 14 MB |  |  |
| table | `pim.family_attributes` | Platform | active |  |  | 48 kB |  |  |
| table | `pim.family_groups` | Platform | active |  |  | 40 kB |  |  |
| table | `pipeline.acquisition_policies` | Platform | active |  |  | 56 kB |  |  |
| table | `pipeline.admin_control_events` | Platform | active |  |  | 15 MB |  |  |
| table | `pipeline.admin_job_events` | Platform | active |  |  | 2552 kB |  |  |
| table | `pipeline.admin_job_items` | Platform | active |  |  | 2768 kB |  |  |
| table | `pipeline.admin_job_kinds` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.admin_jobs` | Platform | active |  |  | 3392 kB |  |  |
| table | `pipeline.automation_catalogue` | Platform | active |  |  | 96 kB |  |  |
| table | `pipeline.award_link_settings` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.ca_course_scope_keys` | Platform | active |  |  | 1760 kB |  |  |
| table | `pipeline.ca_source_qualifications` | Platform | active |  |  | 72 kB |  |  |
| table | `pipeline.claims` | Platform | active |  |  | 40 kB |  |  |
| table | `pipeline.completeness_daily` | Platform | active |  |  | 7504 kB |  |  |
| table | `pipeline.component_usage_snapshots` | Platform | active | CF-247 Decision 260: weekly counters of table reads and writes and index scans, so the hygiene check can tell what nothing has used. |  | 408 kB |  |  |
| table | `pipeline.consumer_api_baselines` | Platform | active |  |  | 14 MB |  |  |
| table | `pipeline.consumer_reference_bundle_cache` | Platform | active |  |  | 592 kB |  |  |
| table | `pipeline.course_completeness` | Platform | active |  |  | 7816 kB |  |  |
| table | `pipeline.course_fact_source_qualifications` | Platform | active |  |  | 952 kB |  |  |
| table | `pipeline.course_fact_source_records` | Platform | active |  |  | 53 MB |  |  |
| table | `pipeline.course_field_source` | Platform | active |  |  | 12 MB |  |  |
| table | `pipeline.course_priority` | Platform | active |  |  | 24 kB |  |  |
| table | `pipeline.data_flags` | Platform | active |  |  | 800 kB |  |  |
| table | `pipeline.directory_institutions` | Platform | active |  |  | 208 kB |  |  |
| table | `pipeline.edge_request_log` | Platform | active |  |  | 10 MB |  |  |
| table | `pipeline.enrichment_flag_events` | Platform | active | CF-247 flag unit (15 Oct 2026): the history of every flag: raised, counted, released, re-queued, free check failed; by a job or a person; why; and the evidence. |  | 10088 kB |  |  |
| table | `pipeline.environment_settings` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.environment_source_gates` | Platform | active | Environment-specific country/source capability approval. Pilot qualification never implies Production enablement. |  | 48 kB |  |  |
| table | `pipeline.evidence_artifacts` | Platform | active |  |  | 319 MB |  |  |
| table | `pipeline.evidence_audit_columns` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.evidence_audit_refs` | Platform | active |  |  | 10 MB |  |  |
| table | `pipeline.evidence_capacity_policy` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.evidence_entity_links` | Platform | active | Derived governed Evidence-to-entity link cache restored to migration history by CF-241. |  | 75 MB |  |  |
| table | `pipeline.evidence_lineage_reconciliations` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.evidence_lineage_stats` | Platform | active | Derived Evidence lineage counters restored to migration history by CF-241; maintained by evidence_lineage_stats_sync triggers. |  | 6992 kB |  |  |
| table | `pipeline.evidence_link_index_state` | Platform | active |  |  | 12 MB |  |  |
| table | `pipeline.evidence_links` | Platform | retiring |  |  | 32 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.evidence_storage_dedupe_log` | Platform | active |  |  | 11 MB |  |  |
| table | `pipeline.fc_extract_results` | Platform | active |  |  | 376 kB |  |  |
| table | `pipeline.fee_wording_rules` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.field_source_rules` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.hygiene_reports` | Platform | active | CF-247 Decision 260: the weekly hygiene check (unused, insecure, unregistered and ready-to-drop components). |  | 32 kB |  |  |
| table | `pipeline.important_dates` | Platform | active |  |  | 72 kB |  |  |
| table | `pipeline.important_links` | Platform | active |  |  | 192 kB |  |  |
| table | `pipeline.integration_secret_registry` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.job_idle_watch` | Platform | active | CF-247 15 Oct 2026: jobs the waste guard pauses when they produce nothing and nothing waits (output_sql takes $1 = since; input_sql counts waiting work). Only j |  | 32 kB |  |  |
| table | `pipeline.job_input_marks` | Platform | active | CF-247 15 Oct 2026: newest input each input-driven job has seen, and when it last did a full check. |  | 32 kB |  |  |
| table | `pipeline.jobs` | Platform | active |  |  | 31 MB |  |  |
| table | `pipeline.l4_rule4_holds` | Platform | active |  |  | 16 kB |  |  |
| table | `pipeline.link_portals` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.link_refresh_policies` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.live_error_acks` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.manual_edit_log` | Platform | active |  |  | 2544 kB |  |  |
| table | `pipeline.manual_locks` | Platform | active |  |  | 1312 kB |  |  |
| table | `pipeline.night_run_queue` | Platform | retiring |  |  | 264 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.night_run_rebatch` | Platform | retiring |  |  | 120 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.performance_workload_profiles` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.pilot_automation_keys` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.pilot_edge_execution_queue` | Platform | retiring |  |  | 80 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.pilot_edge_nonces` | Platform | active |  |  | 35 MB |  |  |
| table | `pipeline.pilot_nonce_functions` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.pim_source_candidates` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.platform_capacity_observations` | Platform | active |  |  | 112 kB |  |  |
| table | `pipeline.platform_capacity_policy` | Platform | active | Operational warning/high/critical planning thresholds. These are CourseFinder policy thresholds, not vendor hard quotas. |  | 32 kB |  |  |
| table | `pipeline.platform_compute_profile` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.platform_cost_model` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.platform_edge_calls` | Platform | active |  |  | 5440 kB |  |  |
| table | `pipeline.platform_health_checks` | Platform | active |  |  | 96 kB |  |  |
| table | `pipeline.platform_health_runs` | Platform | active |  |  | 1816 kB |  |  |
| table | `pipeline.platform_issues` | Platform | active |  |  | 312 kB |  |  |
| table | `pipeline.platform_job_layers` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.platform_notice_acks` | Platform | active |  |  | 16 kB |  |  |
| table | `pipeline.platform_resource_observations` | Platform | active |  |  | 328 kB |  |  |
| table | `pipeline.platform_toolset_settings` | Platform | active |  |  | 184 kB |  |  |
| table | `pipeline.platform_toolsets` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.platform_uat_catalogue` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.priority_pins` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.production_migration_manifest` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.progress_provider_facts` | Platform | active |  |  | 712 kB |  |  |
| table | `pipeline.progress_snapshots` | Platform | active |  |  | 448 kB |  |  |
| table | `pipeline.provider_archives` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.provider_asset_candidates` | Platform | active |  |  | 736 kB |  |  |
| table | `pipeline.provider_contact_audit_events` | Platform | active |  |  | 136 kB |  |  |
| table | `pipeline.provider_contact_checks` | Platform | active |  |  | 1976 kB |  |  |
| table | `pipeline.provider_contact_dispositions` | Platform | active | A16 explicit AU/NZ Provider international-contact coverage/disposition history. Older successful profile runs without attempt-row telemetry are retained as not_ |  | 120 kB |  |  |
| table | `pipeline.provider_contact_import_batches` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.provider_contact_import_rows` | Platform | active |  |  | 136 kB |  |  |
| table | `pipeline.provider_contact_observations` | Platform | active |  |  | 224 kB |  |  |
| table | `pipeline.provider_contact_points` | Platform | active |  |  | 2584 kB |  |  |
| table | `pipeline.provider_contact_profiles` | Platform | active |  |  | 144 kB |  |  |
| table | `pipeline.provider_contact_provider_mappings` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.provider_contact_versions` | Platform | active |  |  | 256 kB |  |  |
| table | `pipeline.provider_contact_watch_events` | Platform | active |  |  | 152 kB |  |  |
| table | `pipeline.provider_contacts` | Platform | active |  |  | 112 kB |  |  |
| table | `pipeline.provider_credit_fees` | Platform | active |  |  | 112 kB |  |  |
| table | `pipeline.provider_directory_observations` | Platform | active |  |  | 104 kB |  |  |
| table | `pipeline.provider_document_checks` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.provider_fact_search` | Platform | active |  |  | 184 kB |  |  |
| table | `pipeline.provider_fact_sources` | Platform | active |  |  | 1272 kB |  |  |
| table | `pipeline.provider_fee_basis_rules` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.provider_fee_profiles` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.provider_fee_range_settings` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.provider_fee_rows` | Platform | active |  |  | 1136 kB |  |  |
| table | `pipeline.provider_policy_proposals` | Platform | active |  |  | 3424 kB |  |  |
| table | `pipeline.provider_priority` | Platform | active |  |  | 480 kB |  |  |
| table | `pipeline.provider_type_rules` | Platform | active | Decision 258: institution type rules. Text fields are case-insensitive patterns matched against register facts. First enabled match by position wins. |  | 32 kB |  |  |
| table | `pipeline.publication_control_settings` | Platform | active |  |  | 24 kB |  |  |
| table | `pipeline.reading_restores_20261005` | Platform | retiring |  |  | 40 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.reference_institutions` | Platform | active |  |  | 3432 kB |  |  |
| table | `pipeline.refresh_policies` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.refresh_policy_action_events` | Platform | active |  |  | 56 kB |  |  |
| table | `pipeline.refresh_requests` | Platform | active |  |  | 3408 kB |  |  |
| table | `pipeline.refused_host_changes` | Platform | retiring |  |  | 224 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `pipeline.retention_class_policies` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.retention_estimates` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.retention_evidence_skips` | Platform | active |  |  | 16 kB |  |  |
| table | `pipeline.retention_file_queue` | Platform | active |  |  | 936 kB |  |  |
| table | `pipeline.retention_runs` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.scheduler_workflow_async_bindings` | Platform | active |  |  | 312 kB |  |  |
| table | `pipeline.search_pass_links` | Platform | active |  |  | 3224 kB |  |  |
| table | `pipeline.search_refresh_signals` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.source_provider_mappings` | Platform | active |  |  | 488 kB |  |  |
| table | `pipeline.source_record_staging` | Platform | active |  |  | 3432 kB |  |  |
| table | `pipeline.sources` | Platform | active |  |  | 2168 kB |  |  |
| table | `pipeline.statistics_dataset_registry` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.statistics_edition_candidates` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.statistics_edition_rules` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.storage_size_daily` | Platform | active | CF-247 16 Oct 2026 (Platform Admin: "record all db and tables data and sizes also prepare total bucket usage ... on daily basis"): one row a day for the databas |  | 288 kB |  |  |
| table | `pipeline.toolset_sample_items` | Platform | active |  |  | 4152 kB |  |  |
| table | `pipeline.toolset_sample_runs` | Platform | active |  |  | 424 kB |  |  |
| table | `pipeline.university_reread_requests` | Platform | active |  |  | 240 kB |  |  |
| table | `pipeline.vendor_credit_observations` | Platform | active |  |  | 608 kB |  |  |
| table | `pipeline.vendor_credit_requests` | Platform | active |  |  | 200 kB |  |  |
| table | `pipeline.zz_qualify_scratch_v1` | Platform | retiring |  |  | 304 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `security.admin_summary_snapshots` | Platform | active |  |  | 304 kB |  |  |
| table | `security.data_quality_overview_snapshots` | Platform | active |  |  | 224 kB |  |  |
| table | `security.roles` | Platform | active |  |  | 48 kB |  |  |
| table | `security.service_permissions` | Platform | active |  |  | 24 kB |  |  |
| table | `security.user_access_events` | Platform | active |  |  | 64 kB |  |  |
| table | `security.user_roles` | Platform | active |  |  | 64 kB |  |  |
| table | `workflow.export_jobs` | Platform | active |  |  | 24 kB |  |  |
| table | `workflow.handover_events` | Platform | active |  |  | 48 kB |  |  |
| table | `workflow.import_errors` | Platform | active |  |  | 32 kB |  |  |
| table | `workflow.import_jobs` | Platform | active |  |  | 24 kB |  |  |
| table | `workflow.import_rows` | Platform | active |  |  | 48 kB |  |  |
| table | `workflow.migration_entity_map` | Platform | active |  |  | 112 kB |  |  |
| table | `workflow.migration_runs` | Platform | active |  |  | 32 kB |  |  |
| table | `workflow.reconciliation_checks` | Platform | active |  |  | 24 kB |  |  |
| table | `workflow.suggestions` | Platform | active |  |  | 48 kB |  |  |
| view | `pipeline.evidence_acquisition_provenance_v1` | Platform | active |  |  |  |  |  |
| view | `public.catalogue_stats` | Platform | active |  |  |  |  |  |
| view | `public.course_completeness_v2` | Platform | active |  |  |  |  |  |
| view | `public.evidence_artifacts` | Platform | active |  |  |  |  |  |
| view | `public.field_values` | Platform | active |  |  |  |  |  |
| view | `public.ingest_jobs` | Platform | active |  |  |  |  |  |
| view | `public.pim_attribute_definitions` | Platform | active |  |  |  |  |  |
| view | `public.providers` | Platform | active |  |  |  |  |  |
| view | `security.provider_hidden_v1` | Platform | active |  |  |  |  |  |
| edge_function | `website-api-v2` | Website API | active | Website API v2 at its own URL (CF-247, 16 Oct 2026). Platform Admin 09:55: "I want a separate URL for each API version going forward. Lets | 2026-10-16 |  |  |  |
| edge_function | `wix-course-api` | Website API | active | CF-CHG-20260915-247 WP3c: this function previously existed only in the live | 2026-10-14 |  |  |  |
| edge_function | `zoho-course-api` | Website API | active |  | 2026-10-16 |  |  |  |
| function | `public.website_v2_sync(text,boolean,text[],integer)` | Website API | active | Website sync: serves the items the change check stored |  |  |  |  |
| function | `search.refresh_course_documents_v2(boolean)` | Website API | retiring | Old projection refresh; no caller and no job since search.refresh_course_base_v3 |  |  | search.refresh_course_base_v3(boolean) |  |
| job | `campus-regional-class-refresh` | Website API | active | Campus regional category: Updates each campus's metro or regional category. |  |  |  |  |
| job | `consumer-reference-bundle-refresh` | Website API | active | Rebuild API reference data: Rebuilds the reference data the website API serves (providers, groups, fields). |  |  |  |  |
| job | `search-refresh-requested` | Website API | active | Refresh search for changed courses: Updates search and the API for courses whose facts changed. |  |  |  |  |
| job | `website-reference-cache` | Website API | active | Website reference: build the copy: Every 15 minutes: builds the website API reference (vocabularies with counts) so the reference action answers at once. |  |  |  |  |
| job | `website-sync-check` | Website API | active | Website sync: change check: Every minute: builds website API items in a rolling pass and numbers each new, changed or removed item (and each logo whose link is  |  |  |  |  |
| table | `private.zoho_integration_credentials` | Website API | active |  |  | 32 kB |  |  |
| table | `private.zoho_integration_rate_windows` | Website API | active |  |  | 112 kB |  |  |
| table | `search.course_documents` | Website API | active |  |  | 233 MB |  |  |
| table | `search.course_embeddings` | Website API | active |  |  | 40 kB |  |  |
| table | `search.embedding_jobs` | Website API | active |  |  | 40 kB |  |  |
| table | `search.intent_aliases` | Website API | retiring |  |  | 48 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop |
| table | `search.profiles` | Website API | active |  |  | 64 kB |  |  |
| table | `search.projection_country_gates` | Website API | active |  |  | 48 kB |  |  |
| table | `search.projection_state` | Website API | active |  |  | 112 kB |  |  |
| table | `search.query_embedding_cache` | Website API | active |  |  | 24 kB |  |  |
| table | `search.refresh_requests` | Website API | active |  |  | 104 kB |  |  |
| edge_function | `zoho-api-v2` | Zoho API | active | Zoho API v2 (CF-247, 16 Oct 2026). Platform Admin 09:43: "create separate API URL and Key for Zoho V2 API and keep it separate from | 2026-10-16 |  |  |  |
| function | `public.zoho_v2_export_page(text, integer)` | Zoho API | active | Zoho v2 CSV export, one page |  |  |  |  |
| function | `public.zoho_v2_export(text)` | Zoho API | retiring | Zoho v2 CSV export, whole file (timed out for courses) |  |  | public.zoho_v2_export_page(text, integer) | The whole-file export timed out for courses (16 Oct 2026); the edge function calls the paged export from 20261016040000 |
| job | `zoho-sync-check` | Zoho API | active | Zoho sync: change check: Every minute: builds Zoho API v2 items (providers, campuses, contacts, courses of the countries in Zoho API settings) in a rolling pass |  |  |  |  |
| table | `pipeline.zoho_sync_items` | Zoho API | active | CF-247 16 Oct 2026 (Zoho API v2): the Zoho change stream. One row per provider, campus, contact and course of the countries in zoho.sync_countries, numbered (se |  | 68 MB |  |  |
| table | `pipeline.zoho_sync_scan` | Zoho API | active | CF-247 16 Oct 2026 (Zoho API v2): where the Zoho change check has got to in its rolling pass, per entity, and when it last finished a pass. |  | 32 kB |  |  |

