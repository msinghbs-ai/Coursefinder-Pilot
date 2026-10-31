# StudySearch – Component register (generated)

**Generated:** 31 Oct 2026 12:02 Melbourne, from `pipeline.component_register` (Decision 260). Do not edit by hand.

## Summary

| Layer | Kind | Active | Retiring | Retired |
|---|---|---|---|---|
| Access | table | 1 | 0 | 0 |
| Admin | function | 1 | 0 | 0 |
| Administration | function | 1 | 0 | 0 |
| Admission | function | 1 | 2 | 0 |
| API | function | 4 | 0 | 0 |
| API | job | 2 | 0 | 0 |
| API | screen | 1 | 0 | 0 |
| API | table | 7 | 0 | 0 |
| Catalogue | function | 6 | 0 | 0 |
| Catalogue | job | 1 | 0 | 0 |
| Catalogue | table | 25 | 0 | 0 |
| Course pages | function | 2 | 0 | 0 |
| Enrichment | function | 1 | 0 | 0 |
| Housekeeping | function | 1 | 0 | 0 |
| L1 register | edge_function | 48 | 0 | 12 |
| L1 register | job | 8 | 0 | 0 |
| L1 register | screen | 7 | 0 | 3 |
| L1 register | table | 48 | 0 | 1 |
| L2 read | edge_function | 6 | 0 | 0 |
| L2 read | function | 16 | 3 | 0 |
| L2 read | job | 49 | 0 | 0 |
| L2 read | screen | 16 | 0 | 10 |
| L2 read | table | 123 | 0 | 25 |
| L2 read | view | 7 | 0 | 1 |
| L3 interpret | edge_function | 1 | 0 | 6 |
| L3 interpret | job | 3 | 0 | 0 |
| L3 interpret | table | 25 | 0 | 11 |
| L3 interpret | view | 1 | 0 | 0 |
| L4 admit | job | 16 | 0 | 0 |
| L4 admit | screen | 2 | 0 | 3 |
| L4 admit | table | 28 | 0 | 0 |
| L4 admit | view | 6 | 0 | 0 |
| Layer 1 | function | 20 | 1 | 0 |
| Layer 1 | job | 7 | 0 | 0 |
| Layer 1 | table | 11 | 0 | 0 |
| Layer 2 | function | 92 | 0 | 0 |
| Layer 2 | job | 11 | 0 | 0 |
| Layer 2 | table | 30 | 0 | 0 |
| Layer 2/3 | function | 1 | 0 | 0 |
| Layer 2/3 | screen | 2 | 0 | 0 |
| Layer 3 | table | 2 | 0 | 0 |
| Layer 3 (retired) | table | 2 | 0 | 0 |
| Layer 4 | function | 16 | 0 | 0 |
| Layer 4 | table | 2 | 0 | 0 |
| Operations | function | 8 | 1 | 1 |
| Operations | job | 0 | 0 | 1 |
| Operations | table | 0 | 0 | 2 |
| Pipeline | function | 11 | 0 | 0 |
| Platform | edge_function | 11 | 0 | 0 |
| Platform | function | 37 | 0 | 0 |
| Platform | job | 39 | 2 | 0 |
| Platform | screen | 37 | 0 | 9 |
| Platform | table | 162 | 0 | 18 |
| Platform | view | 9 | 0 | 0 |
| Reporting | function | 3 | 0 | 0 |
| Reporting | job | 2 | 0 | 0 |
| Reporting | table | 2 | 0 | 0 |
| Scholarships | function | 3 | 0 | 0 |
| Scholarships | job | 1 | 0 | 0 |
| Search and API | function | 2 | 0 | 0 |
| Website API | edge_function | 3 | 0 | 0 |
| Website API | function | 1 | 1 | 0 |
| Website API | job | 5 | 0 | 0 |
| Website API | table | 10 | 0 | 1 |
| Zoho API | edge_function | 1 | 0 | 0 |
| Zoho API | function | 3 | 1 | 0 |
| Zoho API | job | 1 | 0 | 0 |
| Zoho API | table | 2 | 0 | 0 |

## Latest hygiene check

```
{
    "sync": {
        "gone": 0,
        "jobs": 141,
        "tables_and_views": 491
    },
    "compared_with": null,
    "ready_to_drop": 0,
    "unused_tables": 0,
    "unused_indexes": 0,
    "tables_without_rls": 53,
    "jobs_not_catalogued": 0,
    "tables_without_purpose": 368,
    "edge_functions_not_called": 0,
    "public_functions_open_to_anon": 1,
    "definer_functions_without_search_path": 0
}
```

## Components

| Kind | Name | Layer | Status | Purpose | Last used | Size | Replaces / replaced by | Note |
|---|---|---|---|---|---|---|---|---|
| table | `security.user_deletions` | Access | active | CF-247 16 Oct 2026: users deleted from Users & roles by a Platform Admin: who, when, the email and roles the user had, and whether Supabase Auth removed the use |  | 16 kB |  |  |
| function | `public.admin_entry_requirements` | Admin | active | Track C Step B (B5): admin entry-requirements reads and the one-course read request |  |  |  |  |
| function | `public.svc_admin_access_last_active` | Administration | active | Last activity per user for Users & roles |  |  |  |  |
| function | `security.calendar_default_intakes_apply_v1` | Admission | retiring | College intakes from the approved calendar |  |  |  |  |
| function | `security.course_fee_identity_gate_tg` | Admission | active | Gate hotfix: tuition identity check at the table for every fee writer (trigger course_fee_identity_gate) |  |  |  |  |
| function | `security.semester_intake_apply_v1` | Admission | retiring | Semester-only intakes turned into months by the calendar |  |  |  |  |
| function | `security.consumer_api_check_v1` | API | active | Compares the consumer API with its baseline |  |  |  |  |
| function | `security.consumer_api_functions_v1` | API | active | The consumer API functions |  |  |  |  |
| function | `security.consumer_api_rebaseline_v1` | API | active | Re-takes the baseline (approved consumer API changes only) |  |  |  |  |
| function | `security.consumer_api_relations_v1` | API | active | Relations the consumer API functions read |  |  |  |  |
| job | `api-usage-rollup` | API | active | API usage: daily statistics: Daily (about 00:20 Melbourne) and on demand from Operations > API usage: sums the API v2 request log into calls per day, key and ac |  |  |  |  |
| job | `consumer-api-guard` | API | active | Consumer API guard: Daily: compares what the website and Zoho read (API functions, the tables and columns behind them) with the frozen baseline; any change rais |  |  |  |  |
| screen | `Integrations › API usage` | API | active | Calls, errors and times per key and action |  |  |  |  |
| table | `pipeline.api_key_events` | API | active | CF-247 16 Oct 2026 (Platform Admin: "be able to rotate their keys"): every key rotation, switch off or on, and early end of an old key, from Operations > API us |  | 32 kB |  |  |
| table | `pipeline.api_requests` | API | active | CF-247 16 Oct 2026 (Platform Admin: "summary and stat collection"): one row per call to a versioned API URL (from Zoho API v2 on): key, action, HTTP status, tim |  | 11 MB |  |  |
| table | `pipeline.api_usage_daily` | API | active | CF-247 16 Oct 2026: calls per day, platform, version, key and action (ok, client errors, rate limited, server errors, average, 95th percentile and slowest time, |  | 96 kB |  |  |
| table | `pipeline.api_usage_refreshes` | API | active | CF-247 16 Oct 2026: each refresh of the API statistics, daily (api-usage-rollup job) or on demand from Operations > API usage: when, by whom and how long it too |  | 32 kB |  |  |
| table | `pipeline.api_usage_summary` | API | active | CF-247 16 Oct 2026: statistics per API key for the last 24 hours, 7 days and 30 days (calls, success and failure, last call, bandwidth, reply sizes, times, full |  | 120 kB |  |  |
| table | `pipeline.consumer_api_baseline` | API | active | CF-247 Decision 266: the consumer API as found live (function definition checksums; columns of the relations they read). security.consumer_api_check_v1 compares |  | 200 kB |  |  |
| table | `private.api_keys` | API | active | CF-247 16 Oct 2026: keys for the versioned API URLs (from Zoho API v2 on). One row per consumer; a key works only on its own platform and version. Only the SHA- |  | 48 kB |  |  |
| function | `security.admin_providers_page_v2` | Catalogue | active | Providers list page with the Adapter filter and column |  |  | security.admin_providers_page |  |
| function | `security.course_url_fill_v1` | Catalogue | active | nightly course_url fill with the four guards |  |  |  |  |
| function | `security.course_url_retraction_30d_v1` | Catalogue | active | 30-day retraction figure for the fill (guard 4; hourly report) |  |  |  |  |
| function | `security.entry_matrix_identity_tg` | Catalogue | active | AER v1.1: fills row_hash and bumps version on catalogue.provider_entry_matrix |  |  |  |  |
| function | `security.entry_matrix_row_hash_v1` | Catalogue | active | AER v1.1: entry-matrix row identity (provider, course, country, level, band, condition keys) |  |  |  |  |
| function | `security.provider_adapter_status_v1` | Catalogue | active | Adapter status of a provider |  |  |  |  |
| job | `course-url-fill` | Catalogue | active | Official link: fill from the proven page: Daily at 02:23 UTC: for courses with no official link in Official link: countries filled, writes the address of the co |  |  |  |  |
| table | `catalogue.course_academic_options` | Catalogue | active |  |  | 40 kB |  |  |
| table | `catalogue.course_collection_memberships` | Catalogue | active |  |  | 32 kB |  |  |
| table | `catalogue.course_collections` | Catalogue | active |  |  | 48 kB |  |  |
| table | `catalogue.course_english_requirements` | Catalogue | active |  |  | 19 MB |  |  |
| table | `catalogue.course_fees` | Catalogue | active | Temporal evidence-backed Course fee observations. Layer 1 regulatory ingestion does not fabricate fee facts; authoritative/provider Layer 2 sources populate thi |  | 135 MB |  |  |
| table | `catalogue.course_field_observations` | Catalogue | active |  |  | 12 MB |  |  |
| table | `catalogue.course_identifiers` | Catalogue | active |  |  | 27 MB |  |  |
| table | `catalogue.course_intakes` | Catalogue | active |  |  | 14 MB |  |  |
| table | `catalogue.course_registrations` | Catalogue | active |  |  | 15 MB |  |  |
| table | `catalogue.course_regulatory_observations` | Catalogue | active | Time-scoped regulatory course facts asserted by an authoritative registration source. Rows preserve source snapshot and evidence; they do not redefine canonical |  | 32 MB |  |  |
| table | `catalogue.course_specialisations` | Catalogue | active | CF-247 Decision 267: majors and specialisations a course page names, admitted from a Ready adapter field (one row per name). Not sent by the website API (Decisi |  | 24 kB |  |  |
| table | `catalogue.course_study_level_observations` | Catalogue | active |  |  | 31 MB |  |  |
| table | `catalogue.courses` | Catalogue | active |  |  | 53 MB |  |  |
| table | `catalogue.outcome_benchmarks` | Catalogue | active |  |  | 80 kB |  |  |
| table | `catalogue.provider_aliases` | Catalogue | active |  |  | 48 kB |  |  |
| table | `catalogue.provider_assets` | Catalogue | active |  |  | 2512 kB |  |  |
| table | `catalogue.provider_associations` | Catalogue | active |  |  | 80 kB |  |  |
| table | `catalogue.provider_collection_memberships` | Catalogue | active |  |  | 80 kB |  |  |
| table | `catalogue.provider_fee_ranges` | Catalogue | active |  |  | 792 kB |  |  |
| table | `catalogue.provider_identifiers` | Catalogue | active |  |  | 1688 kB |  |  |
| table | `catalogue.provider_outcomes` | Catalogue | active |  |  | 5728 kB |  |  |
| table | `catalogue.provider_registrations` | Catalogue | active |  |  | 4376 kB |  |  |
| table | `catalogue.providers` | Catalogue | active |  |  | 7800 kB |  |  |
| table | `catalogue.student_flow_observations` | Catalogue | active |  |  | 6952 kB |  |  |
| table | `pipeline.course_url_fills` | Catalogue | active | course_url values the platform filled from a proven course-page binding (NZ brief item 5): one row per course, the page copy (evidence_id) as proof; a retractio |  | 6544 kB |  |  |
| function | `security.search_asked_by_person_v1` | Course pages | active | A course search asked for by a person passes the search gates |  |  |  |  |
| function | `security.site_not_checked_v1` | Course pages | active | Search waits for the site map in the check-first countries |  |  |  |  |
| function | `security.enrich_fallback_v1` | Enrichment | active | Provider-level or registered fact when the course page is silent |  |  |  |  |
| function | `security.screenshot_in_open_build_v1` | Housekeeping | active | Adapter builder screenshot of a build still open (kept) |  |  |  |  |
| edge_function | `layer1-au-cricos-facts` | L1 register | active | v1.3.0 (CF-247 Phase 2, 8 Oct 2026): when the CRICOS register adapter (au_cricos) is switched on, the course facts are read from the |  |  |  |  |
| edge_function | `layer1-au-depth` | L1 register | active | v1.8.0 (CF-247 Phase 2, 8 Oct 2026): when the CRICOS register adapter (au_cricos) is switched on, the plan fingerprints and every row a |  |  |  |  |
| edge_function | `layer1-ca-ab-alis-degrees` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-ab-alis-probe` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-algonquin-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-bc-epbc-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-boreal-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-cambrian-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-centennial-programs` | L1 register | active |  | 2026-10-20 |  |  |  |
| edge_function | `layer1-ca-cna-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-conestoga-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-confederation-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-cpic-probe` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-durham-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-fanshawe-pgwp` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-fanshawe-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-firstparty-catalogues` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-fleming-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-georgian-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-ircc-nvit-probe` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-lambton-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-live` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-loyalist-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-mb-designation-probe` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-mb-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-mohawk-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-niagara-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-northern-code-audit` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-northern-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-ns-sk-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-on-college-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-provider-geography` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-qc-audit` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-qc-parse-audit` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-qc-pdf-probe` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-qc-pdf-probe2` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-qc-prefix-audit` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-qc-strict-audit` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-qc-university-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-sault-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-seneca-catalogue` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-sheridan-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-sk-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-sk-sitemap-probe` | L1 register | retired |  |  |  |  | Phase 5, 19 Oct 2026: removed from git and from live |
| edge_function | `layer1-ca-stclair-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-ca-stlawrence-programs` | L1 register | active |  |  |  |  |  |
| edge_function | `layer1-nz-live` | L1 register | active | NZQA tertiary register worker (Layer 1, NZ). | 2026-10-30 |  |  |  |
| edge_function | `layer1-operations-control` | L1 register | active | v1.8.0 (CF-247): Canadian catalogue and register readers on Layer 1. Each source names its reader in | 2026-10-30 |  |  |  |
| edge_function | `layer1-operations-scheduled` | L1 register | active | v1.2.0: the statistics branches called these helpers without defining them (every scheduled QILT/PRISMS check failed); | 2026-10-29 |  |  |  |
| edge_function | `layer1-provider-facts` | L1 register | active | CF-247 v2.15.276 (14 Oct 2026) Decision 258: Layer 1 reader for provider register facts. | 2026-10-29 |  |  |  |
| edge_function | `layer1-register-etl` | L1 register | active |  |  |  |  |  |
| edge_function | `prisms-au-etl` | L1 register | active |  | 2026-10-25 |  |  |  |
| edge_function | `qilt-au-etl` | L1 register | active | v0.3.0 (Decision 134): an edition found by the statistics discovery job is read from its own file. The address must be a | 2026-10-25 |  |  |  |
| edge_function | `ranking-evidence-export` | L1 register | active |  |  |  |  |  |
| edge_function | `ranking-layer1-etl` | L1 register | active |  | 2026-10-28 |  |  |  |
| edge_function | `ranking-publisher-control` | L1 register | active | CF-247 R5: internal callers (one-time nonce from the database) may apply an import that is already validated, |  |  |  |  |
| edge_function | `ranking-publisher-import` | L1 register | active |  |  |  |  |  |
| edge_function | `ranking-qs-official-etl` | L1 register | active |  |  |  |  |  |
| edge_function | `ranking-the-official-etl` | L1 register | active |  |  |  |  |  |
| edge_function | `statcan-ca-psis-etl` | L1 register | active |  |  |  |  |  |
| job | `ca-dli-flag` | L1 register | active | Canada: international-enrolment flag from the IRCC DLI list: Daily: sets each Canadian provider with a current IRCC Designated Learning Institution number to en |  |  |  |  |
| job | `coursefinder-layer1-housekeeping` | L1 register | active | Layer 1 housekeeping: Daily tidy-up of register runs. |  |  |  |  |
| job | `coursefinder-layer1-regulatory-scheduler` | L1 register | active | Register refresh scheduler: Starts register refreshes (CRICOS and others) when they are due. |  |  |  |  |
| job | `layer1-auto-ingest` | L1 register | active | Register auto-ingest: Ingests new register files when they appear. |  |  |  |  |
| job | `layer1-run-driver` | L1 register | active | Register run driver: Moves running register refreshes forward. |  |  |  |  |
| job | `provider-type-classify` | L1 register | active | Institution type: Every day: sets each provider's institution type from the register facts with the rules on Settings > Pipeline settings. A type set by a perso |  |  |  |  |
| job | `ranking-link` | L1 register | active | Link ranked universities to providers: Links QS and THE universities to providers in the same country when the names agree (Decision 208 rules), for every editi |  |  |  |  |
| job | `statistics-edition-discovery` | L1 register | active | New statistics editions: Looks for new QILT and PRISMS editions each month. |  |  |  |  |
| screen | `Layer 1 Register` | L1 register | active | Every source the pipeline reads. Registers (such as CRICOS) first: each with its health, schedule and settings; choose All layers for every other source. |  |  |  |  |
| screen | `Layer 1 Register › Scholarships` | L1 register | retired |  |  |  | Layer 2/3 Build & enrich › Scholarships | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
| screen | `Layer 1 Register › Sources` | L1 register | retired |  |  |  | Layer 1 Register (Sources, Registers filter) | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
| screen | `Rankings & statistics` | L1 register | active | QILT, PRISMS, QS and THE data, and side-by-side comparison. |  |  |  |  |
| screen | `Rankings & statistics › Compare` | L1 register | active |  |  |  |  |  |
| screen | `Rankings & statistics › Datasets` | L1 register | active |  |  |  |  |  |
| screen | `Rankings & statistics › Outcomes (QILT)` | L1 register | active |  |  |  |  |  |
| screen | `Rankings & statistics › Overview` | L1 register | active |  |  |  |  |  |
| screen | `Rankings & statistics › Student flow (PRISMS)` | L1 register | active |  |  |  |  |  |
| screen | `Reference data › Ranking imports` | L1 register | retired |  |  |  | Rankings & statistics › Datasets (Ranking imports) | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
| table | `catalogue.provider_rankings` | L1 register | active |  |  | 48 kB |  |  |
| table | `catalogue.provider_register_facts` | L1 register | active |  |  | 952 kB |  |  |
| table | `pipeline.component_register` | L1 register | active | CF-247 Decision 260: every job, table, view, edge function and screen, with its layer, purpose, status (active, retiring, retired), what it replaces, and when i |  | 592 kB |  |  |
| table | `pipeline.layer1_course_retirements` | L1 register | active |  |  | 536 kB |  |  |
| table | `pipeline.layer1_dataset_editions` | L1 register | active |  |  | 80 kB |  |  |
| table | `pipeline.layer1_dataset_families` | L1 register | active |  |  | 48 kB |  |  |
| table | `pipeline.layer1_provider_departures` | L1 register | active |  |  | 32 kB |  |  |
| table | `pipeline.layer1_register_row_state` | L1 register | active |  |  | 9920 kB |  |  |
| table | `pipeline.layer1_run_plans` | L1 register | active |  |  | 440 kB |  |  |
| table | `pipeline.layer1_run_queue` | L1 register | active |  |  | 696 kB |  |  |
| table | `pipeline.layer1_seed_snapshots` | L1 register | active |  |  | 32 kB |  |  |
| table | `pipeline.layer1_source_operation_versions` | L1 register | active |  |  | 104 kB |  |  |
| table | `pipeline.layer1_source_operations` | L1 register | active |  |  | 128 kB |  |  |
| table | `pipeline.ranking_inline_evidence_payloads` | L1 register | active | Private exact-byte Evidence bridge for authorised ranking files supplied through a control plane that cannot write directly to Storage. Migrate to private Evide |  | 16 kB |  |  |
| table | `pipeline.register_adapters` | L1 register | active |  |  | 128 kB |  |  |
| table | `pipeline.register_replay_keys` | L1 register | active |  |  | 16 kB |  |  |
| table | `pipeline.register_replay_runs` | L1 register | active |  |  | 224 kB |  |  |
| table | `public._layer1_depth_uat_control` | L1 register | retired |  |  | 32 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `ranking.editions` | L1 register | active |  |  | 96 kB |  |  |
| table | `ranking.indicator_observations` | L1 register | active |  |  | 62 MB |  |  |
| table | `ranking.manual_imports` | L1 register | active |  |  | 224 kB |  |  |
| table | `ranking.observation_provider_links` | L1 register | active |  |  | 384 kB |  |  |
| table | `ranking.observations` | L1 register | active |  |  | 67 MB |  |  |
| table | `ranking.provider_mappings` | L1 register | active |  |  | 152 kB |  |  |
| table | `ranking.publisher_institutions` | L1 register | active |  |  | 3680 kB |  |  |
| table | `ranking.systems` | L1 register | active |  |  | 48 kB |  |  |
| table | `ref.au_regional_postcode_ranges` | L1 register | active |  |  | 64 kB |  |  |
| table | `ref.countries` | L1 register | active |  |  | 184 kB |  |  |
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
| edge_function | `coverage-sweep` | L2 read | active | v0.17.32: same normalising as extract.ts siteNorm (kept here so the shared extract.ts, used by other functions, is unchanged) | 2026-10-31 |  |  |  |
| edge_function | `layer2-provider-control` | L2 read | active |  |  |  |  |  |
| edge_function | `provider-contact-discover-scheduled` | L2 read | active |  |  |  |  |  |
| edge_function | `provider-contact-enrich-apollo` | L2 read | active |  |  |  |  |  |
| edge_function | `statistics-edition-discovery` | L2 read | active | CF-247 / Decision 134: find new statistics editions from each family's stable publisher page. |  |  |  |  |
| edge_function | `website-course-api` | L2 read | active |  |  |  |  |  |
| function | `public.admin_adapter_build` | L2 read | active | Build adapter: list, read, build, admit, waves |  |  |  |  |
| function | `public.admin_course_search_queue` | L2 read | active | Adapter builder guide: whether a provider's course-page searches will run, and how many asked-for searches are ahead |  |  |  |  |
| function | `public.admin_provider_website_check` | L2 read | active | Adapter builder 1.1: list, check, change a website |  |  |  |  |
| function | `public.layer2_hotcourses_directory_apply` | L2 read | retiring | Earlier directory import that proposed logo candidates |  |  | Logo finder (job logo-find) | 18 Oct 2026: no caller and no job |
| function | `public.layer2_provider_asset_fetch_routes()` | L2 read | retiring | Old logo finder (retired 10 Oct 2026); no caller, no job |  |  | job logo-find (coverage-sweep mode logo_find) |  |
| function | `public.layer2_provider_asset_promotion_context(uuid)` | L2 read | retiring | Old logo finder (retired 10 Oct 2026); no caller, no job |  |  | public.svc_logo_find_record |  |
| function | `public.svc_coverage_text_sha` | L2 read | active | Text hash of the copy a course page uses now (unchanged-page reuse) |  |  |  |  |
| function | `public.svc_provider_website_check_next` | L2 read | active | Worker: claims waiting website checks |  |  |  |  |
| function | `public.svc_provider_website_check_record` | L2 read | active | Worker: records a website check and applies a checked change |  |  |  |  |
| function | `security.adapter_build_admit_majors_v1` | L2 read | active | Writes majors from Ready readings |  |  |  |  |
| function | `security.adapter_build_fields_v1` | L2 read | active | Readiness of eight fields for one university |  |  |  |  |
| function | `security.course_relink_provider_v1` | L2 read | active | Candidate addresses for one university's refused course pages |  |  |  |  |
| function | `security.course_relink_tick_v1` | L2 read | active | Settles relink outcomes and starts the next batch |  |  |  |  |
| function | `security.page_refind_settle_v1` | L2 read | active | Settles re-finds: replaced, or old page put back |  |  |  |  |
| function | `security.page_refind_start_v1` | L2 read | active | Starts a re-find of a provider's pages from an old domain |  |  |  |  |
| function | `security.provider_website_change_apply_v1` | L2 read | active | Saves a checked website change and restarts searches |  |  |  |  |
| function | `security.provider_website_check_kick_v1` | L2 read | active | Starts the worker only when a check waits |  |  |  |  |
| function | `security.provider_website_list_v1` | L2 read | active | Splits a website field holding several addresses |  |  |  |  |
| function | `security.provider_website_verdict_v1` | L2 read | active | Verified, Likely or Failed from what the worker found |  |  |  |  |
| job | `adapter-build-readiness` | L2 read | active | Build adapter readiness: Hourly: measures, for universities with an adapter, which of eight fields are Ready, for Review or Not ready, and what each would add ( |  |  |  |  |
| job | `better-page-revert` | L2 read | active | Return to the better course page: Puts a course back on its better page when a newer page proved weaker. |  |  |  |  |
| job | `central-ai` | L2 read | active | Read central pages with AI: Sends queued English language policy and academic calendar pages to the pinned model (GPT-4.1 mini); each score and month must be qu |  |  |  |  |
| job | `central-attach` | L2 read | active | University English rules: find and read: Every hour at :48: for each university with no approved English rule, attaches the best suggested central English page  |  |  |  |  |
| job | `central-find` | L2 read | active | Find central pages: Maps each provider's own site with Firecrawl and suggests its key dates, international fee and English requirements pages, for a person to a |  |  |  |  |
| job | `course-link-reverse` | L2 read | active | Match known course pages by CRICOS code: Reads course pages already found on the top universities' sites that are matched to no course, and matches them by the  |  |  |  | switched off |
| job | `course-link-search` | L2 read | active | Find course pages by CRICOS code: Searches each university's own site for the CRICOS code (then the exact course title) and matches the result to the university |  |  |  |  |
| job | `course-link-search-worker` | L2 read | active | Search for course pages: Searches each provider's site for a course's own page (CRICOS code, then title), several at a time; a found page is used only after the |  |  |  |  |
| job | `course-relink` | L2 read | active | Relink refused course pages: Every 10 minutes: for courses whose page was refused as another course's page, builds candidate addresses (the university's address |  |  |  |  |
| job | `coursefinder-layer2-housekeeping` | L2 read | active | Layer 2 housekeeping: Daily tidy-up of Layer 2 runs. |  |  |  |  |
| job | `coursefinder-m2-3-refresh-intelligence-tick` | L2 read | active | Refresh policies: Runs the refresh policies set under Scheduled jobs. |  |  |  |  |
| job | `coverage-bind` | L2 read | active | Match pages to courses: Links each discovered page to its course using the CRICOS code printed on the page. |  |  |  |  |
| job | `coverage-discover` | L2 read | active | Discover course pages: Maps each provider's website to find its course pages. |  |  |  |  |
| job | `coverage-discover-2` | L2 read | active | Discover course pages (second worker): Runs beside Discover course pages to map more provider websites at once (added for New Zealand, 1 Oct 2026). |  |  |  |  |
| job | `coverage-find-site` | L2 read | active | Find provider websites: Looks up the official website of providers that do not have one yet. |  |  |  |  |
| job | `coverage-read` | L2 read | active | Read course pages: Fetches matched course pages and saves them as evidence. |  |  |  | switched off |
| job | `coverage-read-2` | L2 read | active | Read course pages (second worker): Every 30 seconds: a second reader of found course pages (up to 60 a call, up to 20 a university), so onboarding is not held b |  |  |  | switched off |
| job | `coverage-reextract` | L2 read | active | Re-read saved pages: Extracts facts again from saved pages after the reading rules improve. |  |  |  |  |
| job | `coverage-reidentify` | L2 read | active | Identify course pages again: Checks saved course pages again against the course's code and title. |  |  |  |  |
| job | `cricos-peo` | L2 read | active | Read CRICOS contact (internal): Reads the Principal Executive Officer from the CRICOS website (Firecrawl). Held for internal use; never published. |  |  |  |  |
| job | `enrich-focus-refresh` | L2 read | active | Focus providers for course-page search: Weekly: ranks Australian providers by missing English and intakes; course-page search runs only for the top ones (Pipeli |  |  |  |  |
| job | `gap-causes` | L2 read | active | Why values are missing: Every hour at :55: for every active course and attribute (official page, fee, English, intakes, campus, campus region, duration, deliver |  |  |  |  |
| job | `layer2-onboarding-snapshot` | L2 read | active | Provider onboarding figures: Updates the provider onboarding figures. |  |  |  |  |
| job | `layer4-auto-admit` | L2 read | active | Layer 4 first runs: auto-admit proven shapes: Hourly at :47, while Auto-admit first runs: on is 1: checks each waiting no-page or conjoint first run against sto |  |  |  |  |
| job | `link-refresh` | L2 read | active | Refresh course links: Re-reads official course pages, searches again for courses with no page, and keeps link check dates current, on the schedule set per count |  |  |  |  |
| job | `logo-find` | L2 read | active | Logo finder: provider logos from their own websites: Every 10 minutes: reads the home page of providers with a website and no logo (asked-for providers first, t |  |  |  |  |
| job | `onboarding-pilot-snapshot` | L2 read | active | Snapshot the onboarding pilot: Hourly: records the onboarding pilot group by country — stages reached, courses with intakes, English, fee and delivery against w |  |  |  | switched off |
| job | `provider-contact-page` | L2 read | active | Find provider phone and email: Reads the provider's own home and contact pages for its public phone and email (direct reads, no Firecrawl). Fills only empty val |  |  |  |  |
| job | `provider-document-check-monthly` | L2 read | active | Fee documents check (monthly): Checks provider fee documents for new versions. |  |  |  |  |
| job | `provider-document-check-weekly-q4` | L2 read | active | Fee documents check (weekly, Oct to Dec): Checks provider fee documents weekly during the fee-publishing season. |  |  |  |  |
| job | `provider-facts` | L2 read | active | Find and read fee schedules, English policies and calendars: Finds each university's international fee schedule, English language policy and academic calendar o |  |  |  |  |
| job | `provider-onboarding` | L2 read | active | Onboard universities: Runs each university's onboarding a step at a time: website, course pages, sample pages, the model's proposal, save and apply, qualify, ce |  |  |  |  |
| job | `provider-website-check` | L2 read | active | Website checks (Adapter builder 1.1): Every 5 minutes: starts the worker for Check website and Change website requests still waiting (the request itself starts  |  |  |  |  |
| job | `scholarship-ai-backfill` | L2 read | active | AI re-check of refused pages (nightly): While AI admission is on, queues the next universities whose refused pages have not been read with the active model and  |  |  |  |  |
| job | `scholarship-ai-extract` | L2 read | active | Read scholarship pages with AI: Sends queued scholarship pages to the active AI model (and the qualification sample to the model being qualified); each answer i |  |  |  |  |
| job | `scholarship-audience` | L2 read | active | Scholarship audience from wording: Hourly: reads who each active scholarship is for from its own name, description and criteria (international, domestic, both,  |  |  |  |  |
| job | `scholarship-auto-publish` | L2 read | active | Publish scholarships automatically: Publishes scholarships that pass every check, as one batch named auto-publish. |  |  |  |  |
| job | `scholarship-course-attribute` | L2 read | active | Course scholarship attribute: Every 15 minutes: refreshes the scholarships shown on each course (search, website, Zoho) for courses linked to a scholarship that |  |  |  |  |
| job | `scholarship-course-attribute-full` | L2 read | active | Course scholarship attribute (nightly sweep): Nightly at 06:51 AEST, after the publication review and the savings run: refreshes the scholarships shown on every |  |  |  |  |
| job | `scholarship-discover` | L2 read | active | Discover scholarships: Finds scholarship pages on provider websites. |  |  |  |  |
| job | `scholarship-discover-refill` | L2 read | active | Line up providers for discovery: Keeps 30 providers waiting for scholarship discovery, adding the largest not yet searched. |  |  |  |  |
| job | `scholarship-fee-alignment` | L2 read | active | Scholarship fee alignment: Recalculates savings for courses whose fee changed. |  |  |  |  |
| job | `scholarship-listing` | L2 read | active | Read scholarship listing pages: Reads each provider's scholarship listing page through the scraper for the coverage check. |  |  |  |  |
| job | `scholarship-nationality` | L2 read | active | Scholarship nationality from wording: Hourly: reads which nationalities each active scholarship names in its own wording (country names, demonyms and regions) a |  |  |  |  |
| job | `scholarship-publication-review` | L2 read | active | Nightly publication review: Withdraws published scholarships that no longer qualify. |  |  |  |  |
| job | `scholarship-read` | L2 read | active | Read scholarship pages: Reads each scholarship's own page and records value, levels, field and closing date. |  |  |  |  |
| job | `scholarship-reread-cadence` | L2 read | active | Re-read published scholarships monthly: Daily at 05:37 AEST: a published or ready-to-publish scholarship's page is re-read at least every 30 days, so a changed  |  |  |  |  |
| job | `scholarship-savings` | L2 read | active | Work out scholarship savings: Works out the saving a year for percentage-off-tuition scholarships from each course's annual international fee. |  |  |  |  |
| job | `university-reread-requests` | L2 read | active | University read-again requests: Sends university pages a person asked to read again to the reader. |  |  |  |  |
| screen | `Coverage & completeness` | L2 read | active | How complete each course is, and each attribute across all courses. |  |  |  |  |
| screen | `Coverage & completeness › Attributes` | L2 read | active |  |  |  |  |  |
| screen | `Coverage & completeness › Counsellor reports` | L2 read | retired |  |  |  | Layer 4 Review › Inbox (Counsellor report) | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Coverage & completeness › Courses` | L2 read | active |  |  |  |  |  |
| screen | `Coverage & completeness › Flags` | L2 read | retired |  |  |  | Layer 2/3 Build & enrich › Flags | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
| screen | `Coverage & completeness › Progress` | L2 read | active |  |  |  |  | v2.15.301: Running now and Levers views retired; Overview and Journeys kept |
| screen | `Layer 2 Discovery & reading` | L2 read | retired | University adapters: build, qualify, admit, switch on or off, and when the pages of each university are read again. |  |  | Layer 2/3 Build & enrich | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Layer 2 Discovery & reading › Adapter builder` | L2 read | retired |  |  |  | Layer 2/3 Build & enrich › Adapter builder (opened from a university) | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Layer 2 Discovery & reading › Adapters` | L2 read | retired |  |  |  | Layer 2/3 Build & enrich › Universities | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Layer 2 Discovery & reading › Build adapter` | L2 read | retired |  |  |  | Layer 2/3 Build & enrich › Build adapter | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Layer 2 Discovery & reading › Enrich fields` | L2 read | retired |  |  |  | Layer 2/3 Build & enrich › Enrich fields | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Layer 2 Discovery & reading › Onboarding` | L2 read | retired |  |  |  | Layer 2/3 Build & enrich › Universities and Operations | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Layer 2 Discovery & reading › Scholarships` | L2 read | retired |  |  |  | Layer 2/3 Build & enrich › Scholarships | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Layer 2/3 Build & enrich` | L2 read | active | Find each university's pages, build and admit its adapter, enrich its courses and check its scholarships: what is working, waiting or stopped, and the jobs behi |  |  |  |  |
| screen | `Layer 2/3 Build & enrich › Adapter builder` | L2 read | active |  |  |  |  |  |
| screen | `Layer 2/3 Build & enrich › Build adapter` | L2 read | active |  |  |  |  |  |
| screen | `Layer 2/3 Build & enrich › Course sources` | L2 read | active |  |  |  |  |  |
| screen | `Layer 2/3 Build & enrich › Enrich fields` | L2 read | active |  |  |  |  |  |
| screen | `Layer 2/3 Build & enrich › Enrichment plan` | L2 read | active |  |  |  |  |  |
| screen | `Layer 2/3 Build & enrich › Operations` | L2 read | active |  |  |  |  |  |
| screen | `Layer 2/3 Build & enrich › Universities` | L2 read | active |  |  |  |  |  |
| screen | `Providers › Campuses` | L2 read | active |  |  |  |  |  |
| screen | `Scholarships` | L2 read | active | Scholarships, where each value came from, and what is published. |  |  |  |  |
| screen | `Scholarships › Coverage` | L2 read | active |  |  |  |  |  |
| screen | `Scholarships › Extraction` | L2 read | retired |  |  |  | Models & services › AI & OpenRouter (Scholarship extraction) | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
| screen | `Scholarships › Scholarships` | L2 read | active |  |  |  |  |  |
| table | `catalogue.campuses` | L2 read | active |  |  | 5128 kB |  |  |
| table | `catalogue.course_campuses` | L2 read | active |  |  | 15 MB |  |  |
| table | `catalogue.course_links` | L2 read | active | Evidence-backed relational URLs for canonical Courses. courses.course_url remains a compatibility/current-primary field, not the multi-link source of truth. |  | 21 MB |  |  |
| table | `pipeline.adapter_autobuilds` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.adapter_builds` | L2 read | active | CF-247 Decision 267: Build adapter, one row per university: the latest field readiness (job adapter-build-readiness), its wave and what one click admitted (late |  | 2136 kB |  |  |
| table | `pipeline.adapter_overwrite_changes` | L2 read | active |  |  | 9128 kB |  |  |
| table | `pipeline.adapter_qualifications` | L2 read | active |  |  | 1200 kB |  |  |
| table | `pipeline.adapter_shadow_reads` | L2 read | active |  |  | 2440 kB |  |  |
| table | `pipeline.adapter_shadow_settings` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.campus_region_cleared` | L2 read | active |  |  | 72 kB |  |  |
| table | `pipeline.campus_regional_class` | L2 read | active |  |  | 624 kB |  |  |
| table | `pipeline.course_attribute_coverage` | L2 read | active |  |  | 93 MB |  |  |
| table | `pipeline.course_coverage_daily` | L2 read | active |  |  | 1056 kB |  |  |
| table | `pipeline.course_coverage_daily_by_country` | L2 read | active |  |  | 2520 kB |  |  |
| table | `pipeline.course_host_pages` | L2 read | active |  |  | 600 kB |  |  |
| table | `pipeline.course_link_recipes` | L2 read | active |  |  | 1392 kB |  |  |
| table | `pipeline.course_link_reverse` | L2 read | active |  |  | 2384 kB |  |  |
| table | `pipeline.course_link_search` | L2 read | active |  |  | 34 MB |  |  |
| table | `pipeline.course_link_search_settings` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.course_relink` | L2 read | active | CF-247 relink (18 Oct 2026): courses whose page was refused as another course's page; candidate addresses from the university's address pattern, its stored addr |  | 3704 kB |  |  |
| table | `pipeline.coverage_course_pages` | L2 read | active |  |  | 56 MB |  |  |
| table | `pipeline.coverage_identity_cases` | L2 read | retired |  |  | 208 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_coverage_identity_cases, public.svc_coverage_identity_result; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.coverage_identity_results` | L2 read | retired |  |  | 1024 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_coverage_identity_result, security.admin_running_now_v1; readers moved off 20 Oct 2026 (migration 20261020140000); drop by paste file; dropped 20 Oct 2026 by paste file (D11 second step; rows in Storage: archive/cf247-d11-drop-9-2026-10-20/39409708653) |
| table | `pipeline.coverage_identity_sets` | L2 read | retired |  |  | 32 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_coverage_identity_cases; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.coverage_provider_discovery` | L2 read | active |  |  | 2240 kB |  |  |
| table | `pipeline.coverage_provider_urls` | L2 read | active |  |  | 140 MB |  |  |
| table | `pipeline.coverage_reidentify_done` | L2 read | active |  |  | 16 MB |  |  |
| table | `pipeline.coverage_vendor_usage` | L2 read | active |  |  | 63 MB |  |  |
| table | `pipeline.directory_pages` | L2 read | retired |  |  | 2200 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_directory_page_record, security.directory_match_v1; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.enrich_coverage_snapshots` | L2 read | active |  |  | 1080 kB |  |  |
| table | `pipeline.enrich_focus_providers` | L2 read | active | CF-247 15 Oct 2026: Australian providers ranked by missing English and intakes; in_focus = within enrich.focus_top_n. |  | 360 kB |  |  |
| table | `pipeline.enrichment_coverage_snapshots` | L2 read | active |  |  | 3880 kB |  |  |
| table | `pipeline.enrichment_flags` | L2 read | active | CF-247 flag unit (15 Oct 2026): one row per held item (provider, course field or job) and reason. state raised = held out of every queue; counting = a soft reas |  | 51 MB |  |  |
| table | `pipeline.field_enrich_items` | L2 read | active |  |  | 93 MB |  |  |
| table | `pipeline.firecrawl_budget_refusals` | L2 read | active |  |  | 72 kB |  |  |
| table | `pipeline.firecrawl_calls` | L2 read | active |  |  | 11 MB |  |  |
| table | `pipeline.firecrawl_panel_figures` | L2 read | active |  |  | 64 kB |  |  |
| table | `pipeline.firecrawl_refusals_by_provider` | L2 read | active |  |  | 336 kB |  |  |
| table | `pipeline.firecrawl_run_items` | L2 read | active |  |  | 20 MB |  |  |
| table | `pipeline.firecrawl_runs` | L2 read | active |  |  | 520 kB |  |  |
| table | `pipeline.firecrawl_search_holds` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.firecrawl_search_resumes` | L2 read | active |  |  | 120 kB |  |  |
| table | `pipeline.firecrawl_target_cache` | L2 read | active |  |  | 4192 kB |  |  |
| table | `pipeline.firecrawl_targets` | L2 read | active |  |  | 280 kB |  |  |
| table | `pipeline.layer2_acquisition_providers` | L2 read | active |  |  | 80 kB |  |  |
| table | `pipeline.layer2_auto_discovery_attempts` | L2 read | retired |  |  | 184 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer2_provider_onboarding_queue_v1; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.layer2_auto_discovery_settings` | L2 read | retired |  |  | 24 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer2_auto_discovery_settings_read_v1, public.layer2_auto_discovery_settings_save_v1; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.layer2_auto_discovery_settings_audit` | L2 read | retired |  |  | 32 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer2_auto_discovery_settings_read_v1, public.layer2_auto_discovery_settings_save_v1; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.layer2_completeness_trial_courses` | L2 read | retired |  |  | 136 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer2_completeness_trial_create, public.layer2_completeness_trial_finalize, public.layer2_provider_trial_record, public.layer2_record_course_trial_result, public.svc_layer2_trial_course_update, public.svc_layer2_trial_detail; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.layer2_completeness_trials` | L2 read | retired |  |  | 48 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer2_completeness_trial_create, public.layer2_completeness_trial_finalize, public.layer2_record_course_trial_result, public.svc_layer2_trial_detail, public.svc_layer2_trial_list; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.layer2_country_completeness_profiles` | L2 read | active |  |  | 48 kB |  |  |
| table | `pipeline.layer2_course_discovery_candidates` | L2 read | active |  |  | 2080 kB |  |  |
| table | `pipeline.layer2_domain_refresh_policies` | L2 read | retired |  |  | 32 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.layer2_enrichment_hourly_admin_cache_v1` | L2 read | active |  |  | 80 kB |  |  |
| table | `pipeline.layer2_execution_policies` | L2 read | active |  |  | 96 kB |  |  |
| table | `pipeline.layer2_execution_policy` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.layer2_fanout_tasks` | L2 read | retired |  |  | 272 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.layer2_onboarding_snapshot` | L2 read | active |  |  | 792 kB |  |  |
| table | `pipeline.layer2_profile_provider_routes` | L2 read | active |  |  | 8944 kB |  |  |
| table | `pipeline.layer2_provider_attempts` | L2 read | active |  |  | 9256 kB |  |  |
| table | `pipeline.layer2_provider_benchmark_observations` | L2 read | retired |  |  | 120 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.layer2_provider_catalogue_submissions` | L2 read | active |  |  | 208 kB |  |  |
| table | `pipeline.layer2_provider_environment_gates` | L2 read | active | Scraper/acquisition-provider qualification per environment. Provider config and credentials remain separate. |  | 32 kB |  |  |
| table | `pipeline.layer2_provider_probe_requests` | L2 read | active |  |  | 64 kB |  |  |
| table | `pipeline.layer2_provider_trial_results` | L2 read | retired |  |  | 56 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: pipeline.layer2_provider_trial_summary, public.layer2_provider_trial_record, public.layer2_record_course_trial_result, security.retention_estimate_v1, security.retention_tick_v1; readers moved off 20 Oct 2026 (migration 20261020140000); drop by paste file; dropped 20 Oct 2026 by paste file (D11 second step; rows in Storage: archive/cf247-d11-drop-9-2026-10-20/39409708653) |
| table | `pipeline.layer2_run_batches` | L2 read | active |  |  | 504 kB |  |  |
| table | `pipeline.layer2_run_items` | L2 read | active |  |  | 25 MB |  |  |
| table | `pipeline.layer2_scale_qualification_items` | L2 read | retired |  |  | 11 MB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer2_provider_onboarding_queue_v1, public.layer2_scale_cross_layer_handoff, public.layer2_scale_pattern_reconcile, public.layer2_scale_qualification_context, public.layer2_scale_qualification_prepare, public.layer2_scale_qualification_provider_finish, public.layer2_scale_scope_service, security.retention_estimate_v1, security.retention_tick_v1; readers moved off 20 Oct 2026 (migration 20261020140000); drop by paste file; dropped 20 Oct 2026 by paste file (D11 second step; rows in Storage: archive/cf247-d11-drop-9-2026-10-20/39409708653) |
| table | `pipeline.layer2_scale_qualification_runs` | L2 read | retired |  |  | 232 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer2_scale_cross_layer_handoff, public.layer2_scale_pattern_reconcile, public.layer2_scale_qualification_context, public.layer2_scale_qualification_prepare, public.layer2_scale_qualification_provider_finish, public.layer2_scale_scope_service, security.layer2_qualification_root, security.layer2_wave_parent_stamp; readers moved off 20 Oct 2026 (migration 20261020140000); drop by paste file; dropped 20 Oct 2026 by paste file (D11 second step; rows in Storage: archive/cf247-d11-drop-9-2026-10-20/39409708653) |
| table | `pipeline.layer2_scholarship_discovery_candidates` | L2 read | active | Layer 2 Scholarship discovery candidates. CF-198 adds only bounded verified first-party UQ/UWA detail seeds backed by newly captured catalogue Evidence; automat |  | 2880 kB |  |  |
| table | `pipeline.layer2_scope_wave_items` | L2 read | retired |  |  | 37 MB |  | Usage audit 15 Oct 2026, decision D9 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.layer2_scope_wave_requests` | L2 read | active |  |  | 104 kB |  |  |
| table | `pipeline.layer2_shared_fetches` | L2 read | active |  |  | 504 kB |  |  |
| table | `pipeline.layer2_source_profile_versions` | L2 read | active |  |  | 18 MB |  |  |
| table | `pipeline.layer2_source_profiles` | L2 read | active |  |  | 2840 kB |  |  |
| table | `pipeline.layer2_tuning_events` | L2 read | retired |  |  | 48 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer2_ops_policy_update, security.admin_layer2_dispatcher_tuning_read_v1; readers moved off 20 Oct 2026 (migration 20261020140000); drop by paste file; dropped 20 Oct 2026 by paste file (D11 second step; rows in Storage: archive/cf247-d11-drop-9-2026-10-20/39409708653) |
| table | `pipeline.onboarding_cases` | L2 read | retired |  |  | 128 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: security.onboarding_case_context_impl, security.onboarding_case_create_impl, security.onboarding_case_metadata_update_impl, security.onboarding_case_transition_impl, security.onboarding_cases_list_impl; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.onboarding_lifecycle_events` | L2 read | retired |  |  | 64 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: security.onboarding_case_context_impl, security.onboarding_case_create_impl, security.onboarding_case_metadata_update_impl, security.onboarding_case_transition_impl, security.onboarding_cases_list_impl; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.onboarding_pilot` | L2 read | active |  |  | 96 kB |  |  |
| table | `pipeline.onboarding_pilot_snapshots` | L2 read | active |  |  | 96 kB |  |  |
| table | `pipeline.page_link_repairs` | L2 read | active |  |  | 13 MB |  |  |
| table | `pipeline.page_refind` | L2 read | active | CF-247 (19 Oct 2026): course pages re-found on the provider's current website; the old page is kept until a new one passes the reader's identity check, and put  |  | 248 kB |  |  |
| table | `pipeline.provider_central_search` | L2 read | active | CF-247 Feature 4 (11 Oct 2026): central pages (key dates, international fees, English requirements) suggested from a Firecrawl map of the provider's own site. S |  | 1720 kB |  |  |
| table | `pipeline.provider_contact_enrichment_attempts` | L2 read | active |  |  | 600 kB |  |  |
| table | `pipeline.provider_discovery_links` | L2 read | active |  |  | 95 MB |  |  |
| table | `pipeline.provider_logo_finds` | L2 read | active | Logo finder (CF-247, 15 Oct 2026): one row per provider the background job has checked or a person has asked it to check; what was found, from which page and ho |  | 744 kB |  |  |
| table | `pipeline.provider_onboarding` | L2 read | active |  |  | 2056 kB |  |  |
| table | `pipeline.provider_onboarding_events` | L2 read | active |  |  | 24 MB |  |  |
| table | `pipeline.provider_onboarding_settings` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.provider_scholarship_search` | L2 read | active |  |  | 64 kB |  |  |
| table | `pipeline.provider_scholarship_search_log` | L2 read | active |  |  | 64 kB |  |  |
| table | `pipeline.provider_website_checks` | L2 read | active | Adapter builder 1.1 (bug 18/10-01): Check website and Change website requests, what the worker found on the home page, the verdict, and for a change what was sa |  | 280 kB |  |  |
| table | `pipeline.rule6_page_checks` | L2 read | active |  |  | 184 kB |  |  |
| table | `pipeline.scholarship_acquisition_trace` | L2 read | active |  |  | 2016 kB |  |  |
| table | `pipeline.scholarship_attribute_sync` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_catalogue_runs` | L2 read | retired |  |  | 152 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer2_scholarship_catalogue_apply; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.scholarship_coverage_benchmarks` | L2 read | retired |  |  | 80 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: no function reads it; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.scholarship_coverage_checks` | L2 read | active |  |  | 16 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.admin_scholarship_coverage_read, public.admin_scholarship_coverage_write, security.scholarship_coverage_row_v1; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `pipeline.scholarship_discovery_providers` | L2 read | active |  |  | 552 kB |  |  |
| table | `pipeline.scholarship_etl_schedules` | L2 read | active |  |  | 32 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.admin_scholarship_layer_read, public.admin_scholarship_layer_write, public.scholarship_operations_read, security.scholarship_scheduler_tick_impl; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `pipeline.scholarship_jobs` | L2 read | active |  |  | 32 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.admin_scholarship_layer_read, public.admin_scholarship_layer_write; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `pipeline.scholarship_layer_settings` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_listing_pages` | L2 read | active |  |  | 216 kB |  |  |
| table | `pipeline.scholarship_maintenance_runs` | L2 read | retired |  |  | 32 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.scholarship_operations_read, security.scholarship_maintenance_tick_impl; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.scholarship_page_candidates` | L2 read | active |  |  | 84 MB |  |  |
| table | `pipeline.scholarship_page_searches` | L2 read | active |  |  | 208 kB |  |  |
| table | `pipeline.scholarship_pages` | L2 read | active |  |  | 10 MB |  |  |
| table | `pipeline.scholarship_publication_batches` | L2 read | active |  |  | 96 kB |  |  |
| table | `pipeline.scholarship_publication_holds` | L2 read | active |  |  | 128 kB |  |  |
| table | `pipeline.scholarship_reread_snapshots` | L2 read | retired |  |  | 136 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.scholarship_runtime_settings` | L2 read | retired |  |  | 32 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: admin_api.scholarship_runtime_settings_write; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.scholarship_scope_acquisition_requests` | L2 read | retired |  |  | 104 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.scholarship_scope_job_mark; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.scholarship_scope_decisions` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_skip_rules` | L2 read | active |  |  | 48 kB |  |  |
| table | `pipeline.scholarship_source_qualifications` | L2 read | active |  |  | 64 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.admin_scholarship_layer_read, public.scholarship_operations_read, security.scholarship_scheduler_tick_impl; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `pipeline.scholarship_source_records` | L2 read | active |  |  | 1600 kB |  |  |
| table | `pipeline.scholarship_sweep_changes` | L2 read | active |  |  | 6048 kB |  |  |
| table | `pipeline.scholarship_watch` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.site_hint_checks` | L2 read | active |  |  | 32 kB |  |  |
| table | `pipeline.uni_adapter_delivery_exclusions` | L2 read | active |  |  | 192 kB |  |  |
| table | `pipeline.uni_adapter_drafts` | L2 read | active |  |  | 21 MB |  |  |
| table | `pipeline.uni_adapter_exclusions` | L2 read | active |  |  | 1200 kB |  |  |
| table | `pipeline.uni_adapter_models` | L2 read | active |  |  | 16 kB |  |  |
| table | `pipeline.uni_adapter_requests` | L2 read | active |  |  | 72 kB |  |  |
| table | `pipeline.uni_adapter_results` | L2 read | active |  |  | 13 MB |  |  |
| table | `pipeline.uni_adapters` | L2 read | active |  |  | 2216 kB |  |  |
| table | `pipeline.website_reference_cache` | L2 read | active |  |  | 240 kB |  |  |
| table | `pipeline.website_sync_items` | L2 read | active |  |  | 98 MB |  |  |
| table | `pipeline.website_sync_scan` | L2 read | active |  |  | 72 kB |  |  |
| table | `private.website_integration_credentials` | L2 read | active |  |  | 32 kB |  |  |
| table | `private.website_integration_rate_windows` | L2 read | active |  |  | 32 kB |  |  |
| table | `scholarship.application_windows` | L2 read | active |  |  | 152 kB |  |  |
| table | `scholarship.audience_readings` | L2 read | active |  |  | 576 kB |  |  |
| table | `scholarship.award_tiers` | L2 read | active |  |  | 672 kB |  |  |
| table | `scholarship.country_onboarding` | L2 read | active |  |  | 32 kB |  |  |
| table | `scholarship.course_financial_calculations` | L2 read | active |  |  | 40 MB |  |  |
| table | `scholarship.course_mapping_candidates` | L2 read | active | Human-review Scholarship→Course candidates. CF-200 expands candidates only for evidence-backed UQ/UWA provider-course scope; no candidate becomes a mapped Cours |  | 22 MB |  |  |
| table | `scholarship.course_mappings` | L2 read | active |  |  | 99 MB |  |  |
| table | `scholarship.coverage` | L2 read | active |  |  | 160 kB |  |  |
| table | `scholarship.criteria` | L2 read | active |  |  | 3488 kB |  |  |
| table | `scholarship.criterion_groups` | L2 read | active |  |  | 208 kB |  |  |
| table | `scholarship.identifiers` | L2 read | active |  |  | 2024 kB |  |  |
| table | `scholarship.nationality_readings` | L2 read | active |  |  | 392 kB |  |  |
| table | `scholarship.offering_cycles` | L2 read | active |  |  | 272 kB |  |  |
| table | `scholarship.scholarships` | L2 read | active |  |  | 2256 kB |  |  |
| table | `scholarship.scopes` | L2 read | active |  |  | 4328 kB |  |  |
| table | `search.enrichment_gates` | L2 read | active |  |  | 32 kB |  |  |
| table | `search.enrichment_source_gates` | L2 read | active |  |  | 1192 kB |  |  |
| view | `pipeline.au_nz_enrichment_backlog_summary_v1` | L2 read | active | CF-245 AU/NZ enrichment backlog summary by field/state/reason. |  |  |  |  |
| view | `pipeline.au_nz_enrichment_backlog_v1` | L2 read | active | CF-245 per-course/per-field AU/NZ enrichment demand classification. Missing values are never synthesized. |  |  |  |  |
| view | `pipeline.layer2_enrichment_hourly_v1` | L2 read | active | CF-245 hourly enrichment outcome metrics; service-role only until governed Admin read projection is added. |  |  |  |  |
| view | `pipeline.layer2_enrichment_operational_ledger_v1` | L2 read | active | CF-245 governed operational ledger derived from Layer 2 run items, jobs, attempts, Evidence, candidates and Search state. Observability only; no mutation author |  |  |  |  |
| view | `pipeline.scholarship_candidate_classification_stats` | L2 read | active |  |  |  |  |  |
| view | `pipeline.scholarship_provider_stats` | L2 read | retired | Internal scholarship provider summary for operational completeness and traceability. Landscape benchmark fields are non-authoritative internal coverage signals  |  |  |  | gone 2026-10-21 |
| view | `pipeline.scholarship_verified_detail_reconciliation_candidates` | L2 read | active | CF-194 current-state reconciliation boundary: captured/applied Evidence only; individual first-party international Scholarship details only; generic/support/fil |  |  |  |  |
| view | `public.scholarship_catalogue_v2` | L2 read | active |  |  |  |  |  |
| edge_function | `layer3-cf245-tuition-benchmark` | L3 interpret | retired | Layer 3 model benchmark (retired Layer 3) |  |  |  | Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list |
| edge_function | `layer3-contact-benchmark` | L3 interpret | retired | Layer 3 model benchmark (retired Layer 3) |  |  |  | Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list |
| edge_function | `layer3-intake-benchmark` | L3 interpret | retired | Layer 3 model benchmark (retired Layer 3) |  |  |  | Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list |
| edge_function | `layer3-model-routing` | L3 interpret | retired | Layer 3 model routing (retired Layer 3) |  |  |  | Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list |
| edge_function | `layer3-provider-control` | L3 interpret | active |  |  |  |  |  |
| edge_function | `layer3-work-dispatch` | L3 interpret | retired | Layer 3 work dispatch (retired Layer 3) |  |  |  | Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list |
| edge_function | `layer3-work-interpret` | L3 interpret | retired | Layer 3 work interpretation (retired Layer 3) |  |  |  | Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list |
| job | `coverage-ai-match` | L3 interpret | active | AI course page matching: Asks the tested AI model whether each candidate page is the course's own page. |  |  |  |  |
| job | `coverage-ai-match-prepare` | L3 interpret | active | Prepare AI course page matching: Picks the candidate pages that need an AI match next. |  |  |  |  |
| job | `fee-period-settle` | L3 interpret | active | Settle fee periods from page wording: Confirms a fee added as per year when the page wording it quoted says per year, or the course runs a year or less. Anythin |  |  |  |  |
| table | `pipeline.central_ai_queue` | L3 interpret | active |  |  | 384 kB |  |  |
| table | `pipeline.central_ai_settings` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.coverage_ai_match` | L3 interpret | active |  |  | 85 MB |  |  |
| table | `pipeline.layer3_benchmark_jobs` | L3 interpret | retired |  |  | 80 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: security.layer3_benchmark_claim_impl, security.layer3_benchmark_claim_job_impl, security.layer3_benchmark_record_impl; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.layer3_fact_handoffs` | L3 interpret | active |  |  | 10 MB |  | Usage audit 15 Oct 2026, D6 and D7: rows nothing live uses purged by paste file; exported first to Storage archive/cf247-usage-audit-2026-10-15/38729659914 |
| table | `pipeline.layer3_holdout_cases` | L3 interpret | active |  |  | 184 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: pipeline.layer3_holdout_digest, public.layer3_holdout_cases_service, public.layer3_holdout_finalise_service, public.layer3_holdout_results_service, public.svc_fc_extract_cases, security.layer3_tier_evidence; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `pipeline.layer3_holdout_results` | L3 interpret | active |  |  | 1832 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: pipeline.layer3_cascade_test_spent_usd, pipeline.layer3_qualification_spent_usd, public.layer3_cascade_result_record_service, public.layer3_holdout_finalise_service, public.layer3_holdout_result_record_service, public.layer3_holdout_results_service, security.layer3_tier_evidence; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `pipeline.layer3_holdout_sets` | L3 interpret | active |  |  | 32 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer3_holdout_cases_service, public.layer3_holdout_finalise_service; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `pipeline.layer3_intake_benchmark_cases` | L3 interpret | retired | CF-247 A3: gold set of sweep course pages with the true international intake months (or not stated), justified by a verbatim excerpt of the stored page text; te |  | 152 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: pipeline.layer3_intake_gold_digest, public.layer3_intake_benchmark_cases_service, public.layer3_intake_benchmark_finalise_service; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.layer3_intake_benchmark_results` | L3 interpret | retired | CF-247 A3: per-case Layer 2 and Layer 3 intake results against the gold set, one row per benchmark run and case, with OpenRouter usage. |  | 248 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer3_intake_benchmark_finalise_service, public.layer3_intake_benchmark_profile_service, public.layer3_intake_benchmark_result_record_service; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.layer3_intake_gold_sets` | L3 interpret | retired | CF-247 A3: frozen intake gold sets (sha256 of every case's answer fields, in case_key order). A benchmark run is refused when the current digest differs. |  | 32 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer3_intake_benchmark_cases_service, public.layer3_intake_benchmark_finalise_service; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.layer3_interpretations` | L3 interpret | active |  |  | 54 MB |  | Usage audit 15 Oct 2026, D6 and D7: rows nothing live uses purged by paste file; exported first to Storage archive/cf247-usage-audit-2026-10-15/38729659914 |
| table | `pipeline.layer3_model_profiles` | L3 interpret | active | M2.4 Layer 3 model profiles. A16 international-contact profile uses retry_ceiling=2 only after immutable benchmark evidence showed malformed structured output;  |  | 352 kB |  |  |
| table | `pipeline.layer3_openrouter_observations` | L3 interpret | active |  |  | 6952 kB |  |  |
| table | `pipeline.layer3_profile_activation_events` | L3 interpret | retired |  |  | 72 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer3_fail_interpretation_service, security.layer3_profile_activate_impl, security.layer3_profile_pause_impl; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.layer3_profile_environment_gates` | L3 interpret | active | AI model/task profile qualification per environment. No profile receives generic canonical mutation authority. |  | 32 kB |  |  |
| table | `pipeline.layer3_provider_credential_audit` | L3 interpret | active |  |  | 48 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: security.layer3_provider_credential_set_impl, security.layer3_provider_validation_record_impl; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `pipeline.layer3_quality_benchmark_runs` | L3 interpret | retired |  |  | 480 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer3_cf245_tuition_benchmark_record_service, public.layer3_contact_benchmark_record_service, public.layer3_holdout_finalise_service, public.layer3_intake_benchmark_finalise_service, public.layer3_source_pattern_benchmark_record_service, public.layer3_usage_window_service, security.admin_layer3_operations_read_v1, security.layer3_benchmark_record_impl, security.layer3_operational_alerts_read, security.platform_health_check_v1, security.platform_resource_observe_v1; readers moved off 20 Oct 2026 (migration 20261020140000); drop by paste file; dropped 20 Oct 2026 by paste file (D11 second step; rows in Storage: archive/cf247-d11-drop-9-2026-10-20/39409708653) |
| table | `pipeline.layer3_route_budget` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.layer3_route_events` | L3 interpret | active |  |  | 80 kB |  |  |
| table | `pipeline.layer3_route_tiers` | L3 interpret | active | CF-247 Layer 3 cascade ladder per task class (Platform Admin direction 29 Sep 2026 20:38 IST). Active rows are used only when layer3_route_budget.route_mode = l |  | 104 kB |  |  |
| table | `pipeline.layer3_task_contract_freezes` | L3 interpret | retired |  |  | 48 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer3_contract_freeze_record_service; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.layer3_tier_audits` | L3 interpret | active |  |  | 264 kB |  |  |
| table | `pipeline.layer3_work_item_rebinds` | L3 interpret | retired |  |  | 32 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.layer3_work_items` | L3 interpret | active |  |  | 16 MB |  | Usage audit 15 Oct 2026, D6 and D7: rows nothing live uses purged by paste file; exported first to Storage archive/cf247-usage-audit-2026-10-15/38729659914 |
| table | `pipeline.scholarship_ai_extract_settings` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_ai_extractions` | L3 interpret | active |  |  | 69 MB |  |  |
| table | `pipeline.scholarship_ai_models` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_ai_prompts` | L3 interpret | active |  |  | 32 kB |  |  |
| table | `pipeline.scholarship_ai_queue` | L3 interpret | active |  |  | 19 MB |  |  |
| table | `pipeline.scholarship_ai_reviews` | L3 interpret | active |  |  | 3256 kB |  |  |
| table | `pipeline.scholarship_ai_run_items` | L3 interpret | retired |  |  | 48 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.scholarship_ai_item_finish_service, public.scholarship_ai_next_item_service, security.scholarship_ai_run_create_impl, security.scholarship_ai_scheduler_tick_impl; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.scholarship_ai_runs` | L3 interpret | retired |  |  | 32 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: admin_api.scholarship_ai_run_status, public.admin_scholarship_layer_read, public.scholarship_ai_budget_service, public.scholarship_ai_item_finish_service, public.scholarship_ai_next_item_service, security.admin_platform_health_cf221, security.platform_health_check_v1, security.scholarship_ai_control_read_impl, security.scholarship_ai_run_create_impl, security.scholarship_ai_scheduler_tick_impl; readers moved off 20 Oct 2026 (migration 20261020140000); drop by paste file; dropped 20 Oct 2026 by paste file (D11 second step; rows in Storage: archive/cf247-d11-drop-9-2026-10-20/39409708653) |
| table | `pipeline.scholarship_ai_sample` | L3 interpret | active |  |  | 80 kB |  |  |
| table | `pipeline.scholarship_ai_settings` | L3 interpret | retired |  |  | 32 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: admin_api.scholarship_ai_settings_write, public.admin_scholarship_layer_read, public.scholarship_ai_budget_service, security.platform_health_check_v1, security.scholarship_ai_control_read_impl, security.scholarship_ai_scheduler_tick_impl; readers moved off 20 Oct 2026 (migration 20261020140000); drop by paste file; dropped 20 Oct 2026 by paste file (D11 second step; rows in Storage: archive/cf247-d11-drop-9-2026-10-20/39409708653) |
| table | `security.layer3_aggregator_credentials` | L3 interpret | active |  |  | 32 kB |  |  |
| view | `pipeline.cf245_layer3_fee_validation_backlog_v1` | L3 interpret | active |  |  |  |  |  |
| job | `adapter-overwrite` | L4 admit | active | Adapter values replace older ones: Where a university adapter is admitted, its values replace older values from other sources. Runs only when new input has arri |  |  |  |  |
| job | `coverage-admit` | L4 admit | active | Admit official page and English: Writes checked facts (official page, English scores) where the course has none; differences go to Layer 4. Runs only when new i |  |  |  |  |
| job | `coverage-admit-intakes` | L4 admit | active | Admit intakes from course pages: Admits intakes read from accepted course pages. Runs only when new input has arrived, with a full check every few hours (Waste  |  |  |  |  |
| job | `exit-awards-apply` | L4 admit | active | Exit awards take parent values: Gives exit awards the values of their single-degree parent once the register check passes. |  |  |  |  |
| job | `fee-wording-rules` | L4 admit | active | Apply approved fee wording rules: Admits international tuition from newly read pages using the fee wording rules approved in Layer 4 › Batch rules. |  |  |  |  |
| job | `host-pages-apply` | L4 admit | active | Hosted courses take host page values: Gives courses carried on a host page the values on that page once host pages are admitted. |  |  |  |  |
| job | `l4-rule-fee-year-align` | L4 admit | active | Review rule: fee year: Sends fees whose year does not match the intake year to review. |  |  |  |  |
| job | `l4-rule-low-agreement` | L4 admit | active | Review rule: sources disagree: PAUSED (Platform Admin 31 Oct 2026, StudySearch decision F1c: keep paused until the rule is reviewed). Daily Rule 4 "low agreemen |  |  |  | switched off |
| job | `l4-rule-unofficial-source` | L4 admit | active | Review rule: unofficial source: Sends values that came only from an unofficial source to review. |  |  |  |  |
| job | `policy-auto-approve` | L4 admit | active | Approve checked AI readings of central pages: Every 10 minutes: approves an AI reading of a focus provider's English policy or calendar when every value is quot |  |  |  |  |
| job | `provider-basis-rule-admit` | L4 admit | active | Admit tuition under provider fee rules: Writes fees covered by an approved rule for how a provider states its fees. |  |  |  |  |
| job | `provider-calendar-defaults` | L4 admit | active | College intakes from the approved calendar: Every 10 minutes: for an Australian college (not a university) with an approved academic calendar, gives Intake 1 an |  |  |  | switched off |
| job | `provider-calendar-intakes` | L4 admit | active | Answer semester-only intakes from calendars: Every 10 minutes: answers a waiting intake review whose course page names only its study periods ("Semester 1", "Tr |  |  |  | switched off |
| job | `provider-english-defaults` | L4 admit | active | Apply approved English policies: Every 10 minutes: keeps one approved English policy in force per university and level (Decision 262: a real admission page with |  |  |  |  |
| job | `provider-fee-profiles-apply` | L4 admit | active | Apply provider fee profiles: Applies provider fee schedules to their courses. |  |  |  |  |
| job | `provider-rule-admit` | L4 admit | active | Admit facts under provider rules: Writes facts covered by approved provider rules. |  |  |  |  |
| screen | `Layer 4 Review` | L4 admit | active | Decisions that need a person, with an audit trail. |  |  |  |  |
| screen | `Layer 4 Review › AI could not decide` | L4 admit | retired |  |  |  | Layer 4 Review › Inbox (Held scholarship) | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Layer 4 Review › Inbox` | L4 admit | active |  |  |  |  |  |
| screen | `Layer 4 Review › Review queue` | L4 admit | retired |  |  |  | Layer 4 Review › Inbox (Course link) | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Layer 4 Review › Websites to find` | L4 admit | retired |  |  |  | Layer 4 Review › Inbox (Website needed) | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| table | `pipeline.admission_lifecycle_policy` | L4 admit | active |  |  | 32 kB |  |  |
| table | `pipeline.course_exit_awards` | L4 admit | active |  |  | 536 kB |  |  |
| table | `pipeline.course_page_blocks` | L4 admit | active |  |  | 160 kB |  |  |
| table | `pipeline.coverage_admission_countries` | L4 admit | active |  |  | 88 kB |  |  |
| table | `pipeline.fee_rule_admissions` | L4 admit | active |  |  | 184 kB |  |  |
| table | `pipeline.layer2_field_admissions` | L4 admit | active |  |  | 768 kB |  |  |
| table | `pipeline.layer4_block_decisions` | L4 admit | active | Append-only reversible governance decisions. Blocking is state, never deletion; each scope is independent. |  | 48 kB |  |  |
| table | `pipeline.layer4_course_field_resolutions` | L4 admit | active |  |  | 48 kB |  |  |
| table | `pipeline.layer4_decisions` | L4 admit | active |  |  | 2792 kB |  |  |
| table | `pipeline.layer4_field_registry` | L4 admit | active |  |  | 32 kB |  |  |
| table | `pipeline.layer4_mass_operations` | L4 admit | active |  |  | 136 kB |  |  |
| table | `pipeline.layer4_override_decisions` | L4 admit | active | A16 append-only Layer 4 effective-value override ledger. Source/canonical history is not overwritten. |  | 32 kB |  |  |
| table | `pipeline.layer4_publication_decisions` | L4 admit | active | A16 separate append-only publication override decisions. Does not itself authorise Production/Website/Zoho cutover. |  | 48 kB |  |  |
| table | `pipeline.layer4_quality_findings` | L4 admit | active |  |  | 24 kB |  |  |
| table | `pipeline.layer4_reroutes` | L4 admit | active |  |  | 2072 kB |  |  |
| table | `pipeline.layer4_review_items` | L4 admit | active |  |  | 43 MB |  |  |
| table | `pipeline.layer4_rule_runs` | L4 admit | active |  |  | 72 kB |  |  |
| table | `pipeline.layer4_scope_rules` | L4 admit | active |  |  | 32 kB |  |  |
| table | `pipeline.provider_rule_admissions` | L4 admit | active |  |  | 144 kB |  |  |
| table | `pipeline.scholarship_admission_log` | L4 admit | active |  |  | 7688 kB |  |  |
| table | `pipeline.uni_adapter_previews` | L4 admit | active |  |  | 4320 kB |  |  |
| table | `publishing.channels` | L4 admit | active |  |  | 32 kB |  |  |
| table | `publishing.entity_states` | L4 admit | active |  |  | 48 kB |  |  |
| table | `publishing.publication_approvals` | L4 admit | active |  |  | 48 kB |  |  |
| table | `publishing.publication_events` | L4 admit | active |  |  | 64 kB |  |  |
| table | `publishing.publication_profiles` | L4 admit | active |  |  | 32 kB |  |  |
| table | `workflow.review_actions` | L4 admit | active |  |  | 40 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_admin_access_guard_delete, public.svc_layer1_reset_au_uat, public.svc_layer1_reset_database, security.admin_evidence_detail, security.admin_pipeline_ops_read; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `workflow.review_queue` | L4 admit | active |  |  | 64 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: l4_api.layer4_review_bulk_decide, public.svc_admin_access_guard_delete, public.svc_layer1_reset_au_uat, public.svc_layer1_reset_database, public.ui_dashboard, public.ui_review_filter_options, public.ui_review_queue, public.ui_reviews_page, security.admin_evidence_detail, security.admin_evidence_has_unresolved_conflict, security.admin_evidence_page, security.admin_evidence_page_default_fast, security.admin_operational_page, security.admin_pipeline_ops_read, security.data_quality_campus_base, security.data_quality_course_base, security.data_quality_exceptions_impl, security.data_quality_overview_impl, security.data_quality_provider_base, security.data_quality_scholarship_base; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| view | `public.review_queue` | L4 admit | active |  |  |  |  |  |
| view | `security.layer4_active_blocks` | L4 admit | active |  |  |  |  |  |
| view | `security.layer4_search_blocked_campuses` | L4 admit | active |  |  |  |  |  |
| view | `security.layer4_search_blocked_courses` | L4 admit | active |  |  |  |  |  |
| view | `security.layer4_search_blocked_providers` | L4 admit | active |  |  |  |  |  |
| view | `security.layer4_search_blocked_scholarships` | L4 admit | active |  |  |  |  |  |
| function | `public.admin_provider_domain_moved` | Layer 1 | active | Move a provider's course pages to a new host after a website change (NZ transition) |  |  |  |  |
| function | `public.svc_nz_cop_next` | Layer 1 | active | NZQA stored files to read for the Code signatory sentence |  |  |  |  |
| function | `public.svc_nz_cop_record` | Layer 1 | retiring | Records what the worker found on the stored NZQA pages |  |  | public.svc_nz_cop_record(text,jsonb,text,text) |  |
| function | `public.svc_nz_cop_record(text,jsonb,text,text)` | Layer 1 | active | Records what the worker found on the stored NZQA pages (reader, type and wording) |  |  |  |  |
| function | `public.svc_programme_next` | Layer 1 | active | Programme pages due for reading |  |  |  |  |
| function | `public.svc_programme_record` | Layer 1 | active | Records a programme page heading and its level |  |  |  |  |
| function | `public.svc_programme_source_next` | Layer 1 | active | Programme lists due for reading |  |  |  |  |
| function | `public.svc_programme_source_record` | Layer 1 | active | Records the programme pages a list gave |  |  |  |  |
| function | `public.svc_source_find_next` | Layer 1 | active | Universities due for the source finder |  |  |  |  |
| function | `public.svc_source_find_record` | Layer 1 | active | Records what the source finder tried and adds the source |  |  |  |  |
| function | `security.au_publish_eligibility_v1` | Layer 1 | active | AU week step 2: unpublished AU providers, eligible to publish or held with cause and owner |  |  |  |  |
| function | `security.ca_dli_apply_v1` | Layer 1 | active | Sets the Canadian international-enrolment flag from the IRCC DLI number |  |  |  |  |
| function | `security.country_scope_gate_v1` | Layer 1 | active | Hide and show courses by country scope |  |  |  |  |
| function | `security.course_in_country_scope_v1` | Layer 1 | active | Course level in its country's scope |  |  |  |  |
| function | `security.layer1_register_end_dates_v1` | Layer 1 | active | AU week step 1: CRICOS course and provider registration end dates (job layer1-register-end-dates) |  |  |  |  |
| function | `security.nz_cop_apply_v1` | Layer 1 | active | Sets the NZ international-enrolment flag from the NZQA Code signatory |  |  |  |  |
| function | `security.nz_cop_fire_v1` | Layer 1 | active | Starts nz_cop reads or applies the flag |  |  |  |  |
| function | `security.programme_create_v1` | Layer 1 | active | Creates inactive courses from programme lists, or matches existing ones |  |  |  |  |
| function | `security.programme_norm_v1` | Layer 1 | active | Title comparison form (accents and punctuation removed) |  |  |  |  |
| function | `security.programme_provider_approved_v1` | Layer 1 | active | Whether a person approved a university's programme list |  |  |  |  |
| function | `security.transition_recheck_v1` | Layer 1 | active | Daily re-check of transition providers (website check and source finder queued) |  |  |  |  |
| job | `layer1-register-end-dates` | Layer 1 | active | Register end dates (CRICOS): Daily at 04:41 UTC, while Register end dates: on is 1: from the latest CRICOS register edition, records the end date of every cours |  |  |  |  |
| job | `nz-cop` | Layer 1 | active | New Zealand: international-enrolment flag from NZQA: Every 10 minutes while new NZQA files are stored: reads each New Zealand provider's stored NZQA page for th |  |  |  |  |
| job | `programme-create` | Layer 1 | active | Courses from programme lists: Hourly: a programme whose level is in the country's scope becomes an inactive, unpublished course with its page bound (or is match |  |  |  |  |
| job | `programme-discover` | Layer 1 | active | Programme lists: Every 30 minutes while a list is due: reads each university's own programme site map or list page (pipeline.programme_sources) and records its  |  |  |  |  |
| job | `programme-read` | Layer 1 | active | Programme pages: Every 10 minutes while pages wait: reads each programme page found on a programme list for its heading; the credential it names gives the study |  |  |  |  |
| job | `source-find` | Layer 1 | active | Course source finder: Every 20 minutes while universities wait: learns the address pattern of a university's course pages and finds its own course site map or l |  |  |  |  |
| job | `transition-recheck` | Layer 1 | active | New Zealand: polytechnic transition re-check: Daily at 03:41: for each NZ provider in the polytechnic transition whose interval has passed (Transition: re-check |  |  |  |  |
| table | `pipeline.country_scope_levels` | Layer 1 | active | CF-247 22 Oct 2026: the study levels shown per country (a course of another level, or with no level, is hidden by job country-scope-gate). Canada: scope ca-intl |  | 32 kB |  |  |
| table | `pipeline.course_scope_changes` | Layer 1 | active | CF-247 22 Oct 2026: every course hidden or shown by the country scope gate, with the scope and rule, so a change can be reversed. |  | 360 kB |  |  |
| table | `pipeline.nz_cop_reads` | Layer 1 | active | CF-247 20 Oct 2026: stored NZQA batch files read for the Code of Practice signatory sentence (coverage-sweep mode nz_cop). |  | 32 kB |  |  |
| table | `pipeline.nz_cop_status` | Layer 1 | active | CF-247 20 Oct 2026: per NZQA organisation number, whether its NZQA page says it is a signatory to the Code of Practice for international students, with the sent |  | 376 kB |  |  |
| table | `pipeline.programme_candidates` | Layer 1 | active | CF-247 22 Oct 2026: each programme page found on a university's programme list, its heading and the study level the heading names, and what became of it (create |  | 1032 kB |  |  |
| table | `pipeline.programme_sources` | Layer 1 | active | CF-247 22 Oct 2026: a university's own programme site map (kind sitemap; child_pattern picks the files of a site map index) or list page (kind list), and the ad |  | 48 kB |  |  |
| table | `pipeline.provider_transitions` | Layer 1 | active | CF-247 23 Oct 2026 (NZ brief C1): NZ providers in the polytechnic transition, each with the Government page it comes from (source_url, source_quote, as_at). ris |  | 64 kB |  |  |
| table | `pipeline.register_end_date_runs` | Layer 1 | active | CF-247 AU completion week (Platform Admin 26 Oct 2026 17:01): each run of security.layer1_register_end_dates_v1 — the register edition used, the guard, and the  |  | 32 kB |  |  |
| table | `pipeline.source_find_countries` | Layer 1 | active | CF-247 22 Oct 2026: countries the course source finder works on (Course sources screen). |  | 32 kB |  |  |
| table | `pipeline.source_find_paths` | Layer 1 | active | CF-247 22 Oct 2026: what the course source finder tries: list_path, list page addresses tried on a university's site (in sort order); folder_word, words a cours |  | 48 kB |  |  |
| table | `pipeline.source_find_runs` | Layer 1 | active | CF-247 22 Oct 2026: the course source finder's last look at each university: the pattern it learnt, every site map and list page it tried with its counts, what  |  | 560 kB |  |  |
| function | `public.admin_course_list` | Layer 2 | active | Course list pages: list, add, stop, read now |  |  |  |  |
| function | `public.admin_enrich_plan` | Layer 2 | active | Layer 2/3 › Enrichment plan |  |  |  |  |
| function | `public.admin_entry_matrix_seed` | Layer 2 | active | Track C: Platform Admin seeds known entry pages |  |  |  |  |
| function | `public.admin_fee_reader` | Layer 2 | active | Layer 2/3 › Enrich fields › Fee reader |  |  |  |  |
| function | `public.admin_field_coverage` | Layer 2 | active | Coverage › Attributes: every field by country, the standing queue and the cross-check |  |  |  |  |
| function | `public.admin_provider_extra_domain` | Layer 2 | active | SP-1 Platform Admin adds a course domain |  |  |  |  |
| function | `public.admin_ui_error_report` | Layer 2 | active | the app reports an error it showed |  |  |  |  |
| function | `public.svc_companion_next` | Layer 2 | active | Due companion pages for the worker |  |  |  |  |
| function | `public.svc_companion_record` | Layer 2 | active | Records a companion page reading |  |  |  |  |
| function | `public.svc_course_list_next` | Layer 2 | active | Due course list pages for the worker |  |  |  |  |
| function | `public.svc_course_list_record` | Layer 2 | active | Course list links into the provider's site addresses |  |  |  |  |
| function | `public.svc_credential_next` | Layer 2 | active | Course pages to read for a credential |  |  |  |  |
| function | `public.svc_credential_record` | Layer 2 | active | Credential found to study level |  |  |  |  |
| function | `public.svc_entry_matrix_fetch_next` | Layer 2 | active | Track C worker fetch lease |  |  |  |  |
| function | `public.svc_entry_matrix_fetch_record` | Layer 2 | active | Track C worker fetch record (evidence) |  |  |  |  |
| function | `public.svc_entry_matrix_next` | Layer 2 | active | Track C worker lease |  |  |  |  |
| function | `public.svc_entry_matrix_record` | Layer 2 | active | Track C worker record |  |  |  |  |
| function | `public.svc_fc_refusal_note_v1` | Layer 2 | active | SP-1 worker-side Firecrawl refusals recorded by name |  |  |  |  |
| function | `public.svc_fee_ai_next` | Layer 2 | active | Fee reader: work for the worker |  |  |  |  |
| function | `public.svc_fee_ai_record` | Layer 2 | active | Fee reader: rows, admission, review, findings |  |  |  |  |
| function | `public.svc_provider_english_add_tests_v1` | Layer 2 | active | Adds a newly read test to an approved English policy and its level-default courses |  |  |  |  |
| function | `public.svc_provider_policy_add_tests_next` | Layer 2 | active | Approved English policies not yet checked by the current parser |  |  |  |  |
| function | `public.svc_worker_report_v1` | Layer 2 | active | worker call report into the ledger (service role) |  |  |  |  |
| function | `security.admin_job_status_v1` | Layer 2 | active | task last progress, forwarded, next attempt, blocking reason |  |  |  |  |
| function | `security.bind_match_scope_refresh_v1` | Layer 2 | active | SP-1 AI match scope refresh |  |  |  |  |
| function | `security.campus_regions_apply_v1` | Layer 2 | active | Known city regions given to campuses |  |  |  |  |
| function | `security.central_pages_attach_v1` | Layer 2 | active | Job central-attach: next suggested central English page per university without a rule; read pages to the AI |  |  |  |  |
| function | `security.companion_sync_v1` | Layer 2 | active | Lists companion pages for bound course pages |  |  |  |  |
| function | `security.course_list_bonus_v1` | Layer 2 | active | One more AI page match after a course list read |  |  |  |  |
| function | `security.course_list_read_v1` | Layer 2 | active | Provider has a read course list |  |  |  |  |
| function | `security.course_page_rebind_v1` | Layer 2 | active | Relinks a course to another page of the university's site by rule (logged) |  |  |  |  |
| function | `security.course_page_rule_v1` | Layer 2 | active | Decision 263: which official course page wins when the coverage sweep proposes a different one (keep, take or a person decides) |  |  |  |  |
| function | `security.credential_level_v1` | Layer 2 | active | Credential wording to study level |  |  |  |  |
| function | `security.delivery_mode_read_v1` | Layer 2 | active | Reads a delivery mode with the university's own wording first |  |  |  |  |
| function | `security.english_level_apply_all_v1` | Layer 2 | active | English levels for every university whose approved policy names levels (job provider-english-defaults) |  |  |  |  |
| function | `security.english_level_apply_v1` | Layer 2 | active | Writes the English level a course page names from the approved policy in force (Decision 264) |  |  |  |  |
| function | `security.english_level_group` | Layer 2 | active | Study level code to English policy level (undergraduate, postgraduate, research) |  |  |  |  |
| function | `security.english_level_key` | Layer 2 | active | English level name as compared (Decision 264) |  |  |  |  |
| function | `security.english_policy_in_force_all_v1` | Layer 2 | active | Runs the in-force rule for every university with overlapping approved English policies |  |  |  |  |
| function | `security.english_policy_in_force_v1` | Layer 2 | active | One English policy in force per university and level (Decision 262) |  |  |  |  |
| function | `security.enrich_item_held_v1` | Layer 2 | active | Whether a course field is held out of Enrich fields queues (flag unit) |  |  |  |  |
| function | `security.enrich_parse_english_v1` | Layer 2 | active | IELTS overall and band from an AI reading, checked against its quote |  |  |  |  |
| function | `security.enrich_parse_intake_periods_v1` | Layer 2 | active | Semesters, trimesters and terms a course page names, to start months from the approved university calendar |  |  |  |  |
| function | `security.enrich_parse_intakes_v1` | Layer 2 | active | Start months from an AI reading, checked against its quote |  |  |  |  |
| function | `security.enrich_plan_auto_v1` | Layer 2 | active | Starts automatic plans, most missing first |  |  |  |  |
| function | `security.enrich_plan_needs_person_v1` | Layer 2 | active | What a person has to do after an enrichment plan finished |  |  |  |  |
| function | `security.enrich_plan_priority_v1` | Layer 2 | active | Universities by missing values |  |  |  |  |
| function | `security.enrich_plan_start_step_v1` | Layer 2 | active | Starts one plan step with the existing task or onboarding |  |  |  |  |
| function | `security.enrich_plan_tick_v1` | Layer 2 | active | Runs the open plans step by step |  |  |  |  |
| function | `security.enrich_plan_v1` | Layer 2 | active | A university's enrichment plan from its gaps, with estimates |  |  |  |  |
| function | `security.enrich_provider_fields_v1` | Layer 2 | active | Filled and missing values per field for one university |  |  |  |  |
| function | `security.enrich_unit_costs_v1` | Layer 2 | active | What each enrichment step used in the last 30 days |  |  |  |  |
| function | `security.entry_level_map_v1` | Layer 2 | active | Track C: provider level label to reference study level |  |  |  |  |
| function | `security.entry_matrix_attach_v1` | Layer 2 | active | Track C: found entry pages become fact sources |  |  |  |  |
| function | `security.entry_matrix_enabled_v1` | Layer 2 | active | Track C reader gate |  |  |  |  |
| function | `security.entry_matrix_enqueue_v1` | Layer 2 | active | Track C: new stored page versions queued once |  |  |  |  |
| function | `security.entry_matrix_fire_v1` | Layer 2 | active | Track C: job entry-matrix-read |  |  |  |  |
| function | `security.entry_matrix_use_stored_v1` | Layer 2 | active | Track C: stored copy before a fetch |  |  |  |  |
| function | `security.fc_on_demand_today_v1` | Layer 2 | active | Firecrawl credits charged to the on-demand allowance today |  |  |  |  |
| function | `security.fc_search_stopped_for_v1` | Layer 2 | active | Course search stopped, for one provider (Firecrawl spend check) |  |  |  |  |
| function | `security.fee_below_floor_v1` | Layer 2 | active | The country floor an international annual fee falls below, else null (quarantine) |  |  |  |  |
| function | `security.fee_course_pages_enqueue_v1` | Layer 2 | active | Queue course pages with one international fee for the AI fee reader (course with no fee held, proof admits tuition) |  |  |  |  |
| function | `security.fee_reader_in_scope_v1` | Layer 2 | active | Fee reader rollout scope from settings |  |  |  |  |
| function | `security.fee_reader_tick_v1` | Layer 2 | active | Fee reader: pages, queue, learning, worker |  |  |  |  |
| function | `security.fee_row_units_v1` | Layer 2 | active | Fee reader: points or credits a fee row covers, from its quote |  |  |  |  |
| function | `security.fee_title_similarity_v1` | Layer 2 | active | Fee row and course title agreement |  |  |  |  |
| function | `security.field_coverage_record_v1` | Layer 2 | active | Records today's field coverage row per country |  |  |  |  |
| function | `security.field_crosscheck_v1` | Layer 2 | active | Cross-checks held duration, level and delivery against the latest page reading |  |  |  |  |
| function | `security.field_gap_queue_tick_v1` | Layer 2 | active | Standing gap queue: cross-check, then one Fill the gaps task when due |  |  |  |  |
| function | `security.field_stalled_v1` | Layer 2 | active | Fields below target that are not moving or are behind, with cause and action |  |  |  |  |
| function | `security.firecrawl_target_rule_reasons_v1` | Layer 2 | active | which Firecrawl targets rule condition each university fails |  |  |  |  |
| function | `security.flag_tool_summary_v1` | Layer 2 | active | Toolset used before a flag (Layer 2/3 › Flags) |  |  |  |  |
| function | `security.gap_scraper_room_v1` | Layer 2 | active | Standing Fill the gaps task: room left in the daily page-read limit |  |  |  |  |
| function | `security.health_hourly_v1` | Layer 2 | active | R3 hourly delta rollup |  |  |  |  |
| function | `security.health_latest_v1` | Layer 2 | active | latest hour for the report |  |  |  |  |
| function | `security.lane_queue_wait_v1` | Layer 2 | active | queue wait percentiles per reader lane from queue timestamps |  |  |  |  |
| function | `security.lane_why_idle_v1` | Layer 2 | active | R1 Q4 why-idle line per work queue |  |  |  |  |
| function | `security.ledger_retention_v1` | Layer 2 | active | ledger and snapshot retention |  |  |  |  |
| function | `security.link_search_block_v1` | Layer 2 | active | course-search stall cause (gate order) |  |  |  |  |
| function | `security.link_search_person_task_v1` | Layer 2 | active | a person's Find course pages task row |  |  |  |  |
| function | `security.no_page_hold_v1` | Layer 2 | active | SP-1 hold out of search and AI match |  |  |  |  |
| function | `security.no_page_propose_v1` | Layer 2 | active | SP-1 job no-page-propose |  |  |  |  |
| function | `security.not_course_page_v1` | Layer 2 | active | Addresses that are never a course page (setting pages.not_course_patterns) |  |  |  |  |
| function | `security.page_match_bonus_v1` | Layer 2 | active | course-list or rejection bonus for the AI page match |  |  |  |  |
| function | `security.page_refused_v1` | Layer 2 | active | one negative-evidence predicate (rejections and blocks) for every automatic binding path |  |  |  |  |
| function | `security.page_rejection_bonus_v1` | Layer 2 | active | one more AI page match after a rejection |  |  |  |  |
| function | `security.provider_field_coverage_v1` | Layer 2 | active | Provider fields filled per country |  |  |  |  |
| function | `security.refind_wave_discovery_v1` | Layer 2 | active | Re-find waves: site discovery again for providers whose site was never mapped |  |  |  |  |
| function | `security.search_stop_gate_v1` | Layer 2 | active | one course-search stop gate for the picker, the credit check and the stall-cause walk |  |  |  |  |
| function | `security.zero_yield_detect_v1` | Layer 2 | active | nightly detect job |  |  |  |  |
| function | `security.zero_yield_pages_v1` | Layer 2 | active | zero-yield predicate and verified-wrong signals per bound page |  |  |  |  |
| function | `security.zero_yield_reset_v1` | Layer 2 | active | reset of verified-wrong pages for one provider (count-limited) |  |  |  |  |
| job | `companion-read` | Layer 2 | active | Companion pages (for example entry requirements): Hourly: lists the companion page of every course whose university has one (the bound page address plus a suffi |  |  |  |  |
| job | `enrich-plan-auto` | Layer 2 | active | Enrichment plans: start automatic plans: Hourly, while switched on: starts plans for the universities with the most missing values (then world ranking), within  |  |  |  |  |
| job | `enrich-plan-run` | Layer 2 | active | Enrichment plans: run the steps: Every 5 minutes: starts the next step of each open university plan (manual or automatic) with the existing task or onboarding,  |  |  |  |  |
| job | `entry-matrix-read` | Layer 2 | active | Entry matrices: find and read: Every 5 minutes while Entry matrices: reader on is 1 (off until the Platform Admin activates it): attaches found entry-requiremen |  |  |  |  |
| job | `fee-reader` | Layer 2 | active | Fee reader (AI): Every few minutes (Fee reader: run every, 2 by default): adds suggested fee pages for providers in scope (Settings › Pipeline settings › Enrich |  |  |  |  |
| job | `field-gap-queue` | Layer 2 | active | Fill the gaps (standing queue) and cross-check: Every 6 hours: cross-checks held duration, level and delivery against the latest course page reading (difference |  |  |  |  |
| job | `health-hourly` | Layer 2 | active | Health: hourly delta: Hourly at :11: writes the hour's health rows (pages read and values admitted against Health: headline target, field changes per country ov |  |  |  |  |
| job | `ledger-retention` | Layer 2 | active | Ledgers: retention: Daily at 03:37 UTC: removes rows of the per-call worker ledger older than Worker ledger: kept for, and zero-yield snapshots older than Zero- |  |  |  |  |
| job | `no-page-propose` | Layer 2 | active | No page published / conjoint: propose: Hourly at :37: refreshes the AI page match scope (tranche overrides and the top Australian providers by courses without a |  |  |  |  |
| job | `policy-add-tests` | Layer 2 | active | English policies: add new tests: Hourly: reads approved English policy pages again from their stored copies (no Firecrawl, no AI) and adds tests the parser has  |  |  |  |  |
| job | `zero-yield-detect` | Layer 2 | active | Zero-yield pages: detect and reset: Hourly at :21 (Detect: providers measured a run providers a run, every provider once a day): counts bound course pages whose |  |  |  |  |
| table | `pipeline.bind_match_scope` | Layer 2 | active | CF-247 SP-1: Australian providers added to the AI page match beyond the focus set (tranche overrides and the top bind.match_scope_top_n by courses without a pag |  | 184 kB |  |  |
| table | `pipeline.city_regions` | Layer 2 | active | CF-247 23 Oct 2026 (Platform Admin 10:25 "Locations state and city are also missing"): the region (state, province or NZ region, from ref.subdivisions) of a cam |  | 32 kB |  |  |
| table | `pipeline.course_companion_pages` | Layer 2 | active | CF-247 Decision 265: one companion page per course (pipeline.uni_adapter_companions), its stored copy and the values read on it (for example english_level). Use |  | 624 kB |  |  |
| table | `pipeline.course_credential_reads` | Layer 2 | active | CF-247 22 Oct 2026: the credential-read result for each course page read (evidence), with what was found and the level it gave; a page read again (new evidence) |  | 560 kB |  |  |
| table | `pipeline.course_no_page` | Layer 2 | active | CF-247 SP-1: courses recorded as having no page published by the provider (kind no_page) or as a conjoint / double degree without a page of its own (kind conjoi |  | 960 kB |  |  |
| table | `pipeline.credential_level_map` | Layer 2 | active | CF-247 22 Oct 2026: credential wording to study level, by country; the first row (by sort) whose match_regex (PostgreSQL, case-insensitive) matches the credenti |  | 48 kB |  |  |
| table | `pipeline.credential_rules` | Layer 2 | active | CF-247 22 Oct 2026: what the credential-read job looks for on a stored course page, by country. regex is a JavaScript regular expression read case-insensitively |  | 32 kB |  |  |
| table | `pipeline.delivery_wording` | Layer 2 | active | CF-247 21 Oct 2026: a university's own delivery wording (a phrase, matched without regard to case) and the mode it means; provider_id null applies to every univ |  | 48 kB |  |  |
| table | `pipeline.enrich_plan_control` | Layer 2 | active | CF-247 21 Oct 2026: automatic enrichment plans on or off and who switched them (automatic steps run as that Platform Admin). Changed on Layer 2/3 › Enrichment p |  | 32 kB |  |  |
| table | `pipeline.enrich_plan_runs` | Layer 2 | active | CF-247 21 Oct 2026: a run of a university's enrichment plan (manual Run now or automatic): its steps in order, each step's task or onboarding reference, status, |  | 4024 kB |  |  |
| table | `pipeline.enrich_value_retractions` | Layer 2 | active | CF-247 23 Oct 2026: values the AI reader filled from a page found to be another course's (status mismatch), taken back with the Platform Admin's approval; value |  | 6400 kB |  |  |
| table | `pipeline.entry_matrix_runs` | Layer 2 | active | CF-247 Track C: one AI read (pinned model entry.matrix_model) of one stored entry-requirements page version. Rows land in catalogue.provider_entry_matrix as pro |  | 528 kB |  |  |
| table | `pipeline.entry_matrix_sources` | Layer 2 | active | CF-247 Track C: the entry matrix reader's own page list (one entry-requirements page per row: found by central-page discovery or seeded by the Platform Admin),  |  | 184 kB |  |  |
| table | `pipeline.fee_country_profiles` | Layer 2 | active | CF-247 21 Oct 2026: how a country publishes tuition, for the AI fee reader: currency, usual unit, full-time load a year (credits or points) and terms a year, us |  | 32 kB |  |  |
| table | `pipeline.fee_reader_findings` | Layer 2 | active | CF-247 21 Oct 2026 ("collect and feed error to build and evolve data reader"): what the fee reader got wrong or could not do, per provider; the newest open ones |  | 2832 kB |  |  |
| table | `pipeline.fee_reader_queue` | Layer 2 | active | CF-247 21 Oct 2026: one AI fee read per fee page and page version (content hash); a changed page is read again. Filled by job fee-reader, worked by worker mode  |  | 3568 kB |  |  |
| table | `pipeline.fee_reader_recipes` | Layer 2 | active | CF-247 21 Oct 2026: how a provider's fee pages are laid out, in the AI's words or a person's (versioned, the last five kept in history); given to the AI with ev |  | 744 kB |  |  |
| table | `pipeline.fee_reader_rows` | Layer 2 | active | CF-247 21 Oct 2026: every fee row the AI fee reader read, as published (amount or range, unit, audience, fee year, quote), its yearly figure (published or estim |  | 5280 kB |  |  |
| table | `pipeline.field_coverage_daily` | Layer 2 | active | CF-247 21 Oct 2026: each field of the field register, filled share per country, one row a day (the latest reading of the day; kept 120 days). Platform health ch |  | 224 kB |  |  |
| table | `pipeline.field_crosscheck_findings` | Layer 2 | active | CF-247 21 Oct 2026: a held course value that differs from a newer reading of the course page (field, held value, page value, wording, evidence). Nothing is over |  | 1896 kB |  |  |
| table | `pipeline.field_gap_queue_control` | Layer 2 | active | CF-247 21 Oct 2026: the standing gap queue switch (job field-gap-queue). owner = the Platform Admin who last switched it; the standing Fill the gaps tasks are r |  | 32 kB |  |  |
| table | `pipeline.field_register` | Layer 2 | active | CF-247 21 Oct 2026: every course and provider field the platform holds, how it is filled (register, coverage pipeline, Enrich fields, or no reader yet) and its  |  | 32 kB |  |  |
| table | `pipeline.health_snapshots` | Layer 2 | active | R3 (24 Oct 2026): hourly delta rollups for the health report — headline, fields_delta per country, lane_wait, ledger, idle, bound_empty, negative_movers, budget |  | 1528 kB |  |  |
| table | `pipeline.mode_outcome_ledger` | Layer 2 | active | R1 Q3 (24 Oct 2026): one row per worker call — the mode, what it processed (items), how much succeeded and failed, where the work landed (the call's tally), the |  | 45 MB |  |  |
| table | `pipeline.page_rejections` | Layer 2 | active | pages proven wrong for a course (negative evidence): the AI page match and the reidentify lane never offer or re-bind a rejected page; written by the zero-yield |  | 104 kB |  |  |
| table | `pipeline.provider_course_lists` | Layer 2 | active | CF-247 22 Oct 2026: a provider's own course list or course finder page entered by a person; read by job course-list-read for its course links (with their link t |  | 176 kB |  |  |
| table | `pipeline.provider_extra_domains` | Layer 2 | active | CF-247 SP-1: extra course domains of a provider whose courses are published on another website (e.g. NZIST work-based learning on the ITO domains). Added by a p |  | 16 kB |  |  |
| table | `pipeline.ui_error_log` | Layer 2 | active | UI audit Phase 0 (24 Oct 2026): every error the admin app showed a person, keyed by the short reference printed on screen (ref); the plain message shown and the |  | 96 kB |  |  |
| table | `pipeline.uni_adapter_companions` | Layer 2 | active | CF-247 Decision 265: a university's companion page (a page beside the bound course page, the bound address plus a suffix) and the patterns read on it (field ->  |  | 32 kB |  |  |
| table | `pipeline.zero_yield_snapshots` | Layer 2 | active | per-provider zero-yield figures written by the nightly zero-yield-detect job: bound pages with a stored copy, zero-yield pages, verified-wrong pages, the rate,  |  | 2976 kB |  |  |
| function | `public.admin_layer23` | Layer 2/3 | active | Layer 2/3 › Operations and Universities (read only) |  |  |  |  |
| screen | `Layer 2/3 Build & enrich › Flags` | Layer 2/3 | active | The flag unit: what is held out of the queues, why, and its history; release or hold (moved from Coverage) |  |  |  |  |
| screen | `Layer 2/3 Build & enrich › Scholarships` | Layer 2/3 | active | Finding scholarships (countries and sources) and reading them (jobs and limits), one tab |  |  |  |  |
| table | `catalogue.course_entry_requirements` | Layer 3 | active | CF-247 entry requirements (B1 course-level table, extended by Track C): a course's own academic entry requirements (prior qualification, minimum grade, prerequi |  | 4120 kB |  |  |
| table | `catalogue.provider_entry_matrix` | Layer 3 | active | CF-247 Track C (entry requirements step A): one published academic entry minimum per provider (or per course), country of prior education, study level and quali |  | 5416 kB |  |  |
| table | `pipeline.layer3_call_costs_hourly` | Layer 3 (retired) | active | CF-247 15 Oct 2026 (usage audit D7): Layer 3 AI calls, tokens and estimated cost per hour, summed from layer3_interpretations before it was purged. Platform res |  | 40 kB |  |  |
| table | `pipeline.layer3_validated_readings` | Layer 3 (retired) | active | CF-247 15 Oct 2026 (usage audit D7): every validated Layer 3 reading of intakes, English and tuition, copied from layer3_interpretations (same id, value and tim |  | 4976 kB |  |  |
| function | `public.admin_layer4_inbox` | Layer 4 | active | Layer 4 Inbox: everything that needs a person, by university, with choices and return paths |  |  |  |  |
| function | `public.layer4_aer_review_read` | Layer 4 | active | AER A1: Layer 4 > Inbox reads one AER item |  |  |  |  |
| function | `security.aer_approve_except_v1` | Layer 4 | active | AER A1: checks an Approve except and builds the decision's final value |  |  |  |  |
| function | `security.aer_review_kinds_v1` | Layer 4 | active | AER A1-A3: the Layer 4 kinds that take the AER review path only |  |  |  |  |
| function | `security.aer_review_lineage_v1` | Layer 4 | active | AER A1: lineage of a waiting AER item (item, run, source, stored copy hash, rows), recorded with each AER decision |  |  |  |  |
| function | `security.aer_review_read_v1` | Layer 4 | active | AER A1: one AER item for the reviewer (rows, quotes, lineage) |  |  |  |  |
| function | `security.course_list_check_v1` | Layer 4 | active | SP-2a: course list verified and list shape |  |  |  |  |
| function | `security.entry_matrix_review_apply_v1` | Layer 4 | active | Track C: admit or quarantine a run's rows |  |  |  |  |
| function | `security.entry_matrix_review_trg_v1` | Layer 4 | active | Track C: non-approval decisions quarantine the run |  |  |  |  |
| function | `security.layer4_course_english_apply_impl` | Layer 4 | active | Writes a course's English requirement decided in Layer 4 (a person's decision, locked) |  |  |  |  |
| function | `security.layer4_fee_item_rebind_v1` | Layer 4 | active | held-fee item: a person's page address through the bind path |  |  |  |  |
| function | `security.layer4_inbox_items_v1` | Layer 4 | active | Layer 4 Inbox: items from every source that needs a person |  |  |  |  |
| function | `security.layer4_inbox_kinds_v1` | Layer 4 | active | Layer 4 Inbox: kinds, choices and return paths |  |  |  |  |
| function | `security.no_page_auto_admit_v1` | Layer 4 | active | SP-2a: auto-admit proven-shape first runs (job layer4-auto-admit) |  |  |  |  |
| function | `security.no_page_review_apply_v1` | Layer 4 | active | SP-1 first-run decisions |  |  |  |  |
| function | `security.no_page_sample_check_v1` | Layer 4 | active | SP-2a: first-run sample confirmed against the course list |  |  |  |  |
| table | `pipeline.layer4_auto_admissions` | Layer 4 | active | CF-247 SP-2a (Platform Admin 26 Oct 2026 08:25): the machine check of each no-page / conjoint first run (list verified, sample confirmed, list shape already app |  | 272 kB |  |  |
| table | `pipeline.no_page_trust` | Layer 4 | active | CF-247 SP-1: per provider and kind (no_page / conjoint), the Layer 4 first-run result: trusted (at least bind.no_page_trust_pct of the sample confirmed, or the  |  | 96 kB |  |  |
| function | `public.admin_counsellor_reports` | Operations | active | Counsellor reports screen: list and close |  |  |  |  |
| function | `public.admin_evidence_copy_roles` | Operations | active | Evidence list: which copy of a course page is in use, older, or a different kind of page |  |  |  |  |
| function | `public.admin_evidence_reuse_today` | Operations | active | Live activity: course pages read today that kept their copy (unchanged-page reuse) |  |  |  |  |
| function | `public.admin_evidence_summary` | Operations | active | Evidence panel: what a saved page is, what it supplied, accepted how, copies |  |  |  |  |
| function | `public.admin_jobs_pulse` | Operations | active | Task manager pulse: runner last run, place in line, items by state, AI backlog |  |  |  |  |
| function | `security.admission_sheet_v1` | Operations | active | Per-university data admission running sheet (daily, admin repo) |  |  |  |  |
| function | `security.evidence_purge_prepare_v1` | Operations | retiring | Seeds and checks evidence removal candidates |  |  | nothing | The evidence purge of 19 Oct 2026 is done; kept for its record of checked and kept snapshots |
| function | `security.jsonb_or_null_v1` | Operations | active | Reads a worker answer as JSON, or nothing when it is not JSON |  |  |  |  |
| function | `security.worker_mode_waiting_v1` | Operations | active | Whether work is waiting for a paused worker job (read, link_search), so the flag check switches it on again |  |  |  |  |
| function | `security.zz_probe_v1` | Operations | retired | One-off probe left behind (executable by postgres only) |  |  | nothing | Phase 5, 19 Oct 2026: dropped by the Platform Admin's paste file / dropped by paste file 19 Oct 2026 |
| job | `evidence-purge-prepare` | Operations | retired | Prepare removal of replaced snapshots: Every 5 minutes until done: checks replaced course-page snapshots against every column that refers to evidence; nothing i |  |  |  | Done 19 Oct 2026: 8,531 replaced snapshots removed by paste file (export cf247-evidence-purge-2026-10-19/39208392871) |
| table | `pipeline.evidence_purge` | Operations | retired | CF-247 (19 Oct 2026): course-page snapshots replaced by a newer snapshot of the same page; candidate, checked (referred to nowhere, ready to archive and remove) |  | 31 MB | nothing | The evidence purge of 19 Oct 2026 is done; kept for its record of checked and kept snapshots; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.orphan_files` | Operations | retired | CF-247 (19 Oct 2026): evidence-bucket files no record names (course pages, adapter captures of drafts that are gone, scholarship pages), listed once for archive |  | 13 MB | nothing | Files listed for removal 19 Oct 2026 (export cf247-orphan-files-2026-10-19/39234401795); dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| function | `security.aer_reread_v1` | Pipeline | active | AER W12: one Read again mechanism (re-read, re-queue a failed read, or fetch a markdown-stored page again as HTML) |  |  |  |  |
| function | `security.course_entry_batch_v1` | Pipeline | active | AER course-level programme: preview and one bounded batch of course reads |  |  |  |  |
| function | `security.course_entry_cost_v1` | Pipeline | active | AER course-level programme: cost a course read (measured, or the setting) |  |  |  |  |
| function | `security.course_entry_eligible_v1` | Pipeline | active | AER course-level programme: courses eligible for an entry-requirements read (B1), in priority order |  |  |  |  |
| function | `security.course_entry_programme_v1` | Pipeline | active | AER course-level programme: per-provider counts, cost and balance |  |  |  |  |
| function | `security.course_entry_read_enqueue_v1` | Pipeline | active | Track C Step B (B1): one course's entry-requirements read on the Enrich fields lane |  |  |  |  |
| function | `security.course_entry_review_apply_v1` | Pipeline | active | Track C Step B (B1): Layer 4 admission of a course entry read |  |  |  |  |
| function | `security.enrich_entry_record_v1` | Pipeline | active | Track C Step B (B1): course entry-requirement rows proposed under the B1 rules; Layer 4 course_entry_first_read |  |  |  |  |
| function | `security.entry_label_levels_v1` | Pipeline | active | AER W19: every level a published matrix level label names |  |  |  |  |
| function | `security.entry_rendered_note_v1` | Pipeline | active | AER Step C: Layer 4 note for a rendered page with no requirements table |  |  |  |  |
| function | `security.entry_resolve_v1` | Pipeline | active | Track C Step B: the five-rule entry resolution over active rows |  |  |  |  |
| edge_function | `admin-evidence-access` | Platform | active | v1.1 (CF-247, Platform Admin 19 Oct 2026 22:13: "tried opening view page and error Preview_not_allowed"): course pages and markdown pages | 2026-10-30 |  |  |  |
| edge_function | `admin-user-management` | Platform | active |  | 2026-10-25 |  |  |  |
| edge_function | `evidence-link-index` | Platform | active | Package 7 (Decision 146): evidence link index. | 2026-10-31 |  |  |  |
| edge_function | `evidence-storage-dedupe` | Platform | active | CF-247 / Decision 155 step 5: remove redundant copies of identical evidence files. | 2026-10-30 |  |  |  |
| edge_function | `fee-schedule-etl` | Platform | active | CF-247 Decision 162 step 2: provider international fee schedules (one document per provider per fee year). | 2026-10-26 |  |  |  |
| edge_function | `platform-environment-control` | Platform | active |  | 2026-10-25 |  |  |  |
| edge_function | `provider-asset-access` | Platform | active |  | 2026-10-30 |  |  |  |
| edge_function | `provider-asset-upload` | Platform | active |  |  |  |  |  |
| edge_function | `provider-contact-control` | Platform | active |  |  |  |  |  |
| edge_function | `provider-contact-import` | Platform | active |  |  |  |  |  |
| edge_function | `toolset-runner` | Platform | active | CF-247 Decision 252 (4 Oct 2026, amended 14:26): sample runs of Serper (web search) and ScrapingBee (browser rendering) |  |  |  |  |
| function | `public.admin_aer_outcomes` | Platform | active | AER closure C1: the register read and download (rank 4+) |  |  |  |  |
| function | `public.admin_course_audit` | Platform | active | What happened to one course: pages, reads, searches, AI tries, field fills, admissions, values held |  |  |  |  |
| function | `public.admin_course_read_now` | Platform | active | Read with AI: read one course page again first in line and fill its missing fields with AI |  |  |  |  |
| function | `public.admin_course_sources` | Platform | active | Course sources screen |  |  |  |  |
| function | `public.admin_flags(text,jsonb)` | Platform | active | Flags screen |  |  |  |  |
| function | `public.admin_gap_causes` | Platform | active | Why values are missing, for Platform health and the hourly report |  |  |  |  |
| function | `public.admin_governed_action` | Platform | active | Decision 268: governed action runner (preview with a rolled-back dry run, approve once under an idempotency key, post-checks, audit); one allowlisted action |  |  |  |  |
| function | `public.admin_programme_lists` | Platform | active | Programme lists: list and approve |  |  |  |  |
| function | `public.admin_queue_watch` | Platform | active | Work queues screen: list, report, run now |  |  |  |  |
| function | `public.admin_screen_open` | Platform | active | Counts admin screen opens per day, page, tab and person |  |  |  |  |
| function | `public.admin_screen_usage` | Platform | active | Screen use over the window (Platform health › Screen use) |  |  |  |  |
| function | `public.admin_settings_backup` | Platform | active | Settings › Backup & restore (Platform Admin) |  |  |  |  |
| function | `public.admin_stats_15m` | Platform | active | Work queues screen: 15-minute stats |  |  |  |  |
| function | `security.admin_read_snapshot_build_v1` | Platform | active | W35: builds one snapshot from the live source |  |  |  |  |
| function | `security.admin_read_snapshot_every_v1` | Platform | active | W35: rebuild interval of a snapshot (settings) |  |  |  |  |
| function | `security.admin_read_snapshot_meta_v1` | Platform | active | W35: generation time, age and stale flag the reads add |  |  |  |  |
| function | `security.admin_read_snapshots_refresh_v1` | Platform | active | W35: job admin-read-snapshots (due check, single-flight build) |  |  |  |  |
| function | `security.aer_course_outcomes_build_v1` | Platform | active | AER closure C1: builds the course outcome register |  |  |  |  |
| function | `security.aer_course_outcomes_refresh_v1` | Platform | active | AER closure C1: job aer-outcome-register (due check) |  |  |  |  |
| function | `security.course_coverage_snapshot_refresh_v1` | Platform | active | W34: single-flight rebuild of the coverage totals snapshot (job course-coverage-snapshot) |  |  |  |  |
| function | `security.flag_recheck_v1()` | Platform | active | Flag unit recheck |  |  |  |  |
| function | `security.gap_causes_run_meta_v1` | Platform | active | W35: the run time, age and stale flag of Why values are missing |  |  |  |  |
| function | `security.gap_causes_run_v1` | Platform | active | W35: job gap-causes (snapshot and its run time) |  |  |  |  |
| function | `security.gap_causes_snapshot_v1` | Platform | active | Job gap-causes: why values are missing |  |  |  |  |
| function | `security.governed_aer_close_snapshot_v1` | Platform | active | Decision 268: live state and preconditions of the AER PR A recovery closure |  |  |  |  |
| function | `security.housekeeping_daily_v1` | Platform | active | Daily housekeeping run (settings retention.nonce_keep_days, retention.job_log_keep_days, batch.housekeeping_rows) |  |  |  |  |
| function | `security.platform_notices_cached_v1` | Platform | active | W35: notices from the snapshot, items acted on since left out |  |  |  |  |
| function | `security.queue_watch_alerts_take_v1` | Platform | active | Progress watchdog: alerts to the delivery |  |  |  |  |
| function | `security.queue_watch_report_v1` | Platform | active | Progress watchdog: daily report |  |  |  |  |
| function | `security.queue_watch_run_v1` | Platform | active | Progress watchdog run |  |  |  |  |
| function | `security.queue_watch_tool_state_v1` | Platform | active | Progress watchdog: tool out, waiting or ok |  |  |  |  |
| function | `security.scholarship_publishability_cached_v1` | Platform | active | W35: publishability rows from the snapshot (admin reads only) |  |  |  |  |
| function | `security.settings_backup_diff_v1` | Platform | active | What differs now from a backup |  |  |  |  |
| function | `security.settings_backup_take_v1` | Platform | active | Takes a backup of publishing and settings |  |  |  |  |
| function | `security.stats_15m_fields_v1` | Platform | active | Fields held per country |  |  |  |  |
| function | `security.stats_15m_report_v1` | Platform | active | Latest 15-minute stats |  |  |  |  |
| function | `security.stats_15m_v1` | Platform | active | 15-minute stats snapshot |  |  |  |  |
| job | `admin-jobs` | Platform | active | Task manager tasks: Moves every waiting or running task in Task manager on by one step each minute (adapters, page reads, Firecrawl runs, scholarship tasks). |  |  |  |  |
| job | `admin-read-snapshots` | Platform | active | Cached admin figures: Each minute: rebuilds the cached snapshot of toolset notices, scholarship publishability and field coverage by country when it is older th |  |  |  |  |
| job | `admin-summary-snapshots-refresh` | Platform | active | Admin summary figures: Refreshes dashboard summary figures. |  |  |  |  |
| job | `aer-outcome-register` | Platform | active | AER course outcome register: Every 5 minutes: rebuilds the course outcome register for academic entry requirements when it is older than its setting (Pipeline s |  |  |  |  |
| job | `country-scope-gate` | Platform | active | Country course scope: Hourly: hides active Canadian courses whose level is missing or out of scope (ca-intl-college-plus-v2) once their page was read for a cred |  |  |  |  |
| job | `course-completeness-build` | Platform | active | Completeness score: Works out how complete each course and provider is. |  |  |  |  |
| job | `course-coverage-build` | Platform | active | Coverage by attribute: Works out coverage state per course attribute. |  |  |  |  |
| job | `course-coverage-snapshot` | Platform | active | Coverage totals snapshot: Every 5 minutes: when the hourly coverage, completeness or field-source build has changed, rebuilds the coverage totals that Completen |  |  |  |  |
| job | `course-field-source-build` | Platform | active | Who supplied each course value: Rebuilds the record of which source supplied each course value, for the Attributes panel. |  |  |  |  |
| job | `course-list-read` | Platform | active | Course list pages: Every 10 minutes when one is due: reads the course list pages people entered for providers (directly, or through the scraper when the page is |  |  |  |  |
| job | `coursefinder-cf245-enrichment-coverage-snapshot` | Platform | active | Enrichment coverage snapshot: Hourly snapshot of enrichment coverage. |  |  |  |  |
| job | `coursefinder-cf245-enrichment-hourly-admin-cache` | Platform | active | Admin figures cache: Refreshes figures shown on admin screens. |  |  |  |  |
| job | `coursefinder-data-quality-overview-refresh` | Platform | active | Data quality overview: Daily data quality figures. |  |  |  |  |
| job | `coursefinder-platform-capacity-observation` | Platform | active | Capacity reading: Records platform capacity daily. |  |  |  |  |
| job | `credential-read` | Platform | active | Credential from course pages: Every 10 minutes while pages wait: reads the credential a Canadian college course page states (for example "Credential: Ontario Co |  |  |  |  |
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
| job | `queue-watch` | Platform | active | Progress watchdog: Every 15 minutes: gives each enrichment queue a state (Moving, Waiting for budget, Stuck, Failing, Out of toolset, Nothing left to try, Done, |  |  |  |  |
| job | `retention-worker` | Platform | active | Data retention: Removes logs and copies older than their retention period, a small batch at a time. |  |  |  |  |
| job | `settings-backup-daily` | Platform | active | Daily backup of publishing and settings: Daily at 6:50 am Melbourne (daylight time): keeps a copy of every provider's Published switch and every setting value,  |  |  |  |  |
| job | `stats-15m` | Platform | active | 15-minute stats: Every 15 minutes: active courses and fields held for New Zealand and Canada with the change in 15 minutes and 24 hours, Firecrawl and AI use ag |  |  |  |  |
| job | `storage-size-daily` | Platform | active | Storage sizes: daily record: Daily (about 00:25 Melbourne): records the size of the database, each schema, each table (rows, table, index and TOAST bytes) and e |  |  |  |  |
| job | `studysearch-codes` | Platform | active | Give StudySearch codes: Courses with no code printed by the university or regulator get a short StudySearch code (university, level, number). A code never chang |  |  |  |  |
| job | `waste-guard` | Platform | active | Waste rules: pause idle jobs, freeze flip-flops, flag: Hourly: pauses a watched job that produced nothing with nothing waiting (and switches it on again when wo |  |  |  |  |
| screen | `API usage` | Platform | retired | Zoho API v2 and Website API v2: calls, success and failure, last use, full loads and deltas, bandwidth; rotate or switch off keys |  |  | Settings › API usage | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
| screen | `Courses` | Platform | active | Every course, with its sources and evidence. |  |  |  |  |
| screen | `Dashboard` | Platform | active | What needs attention today, and recent activity. |  |  |  | v2.15.301: Waiting for you is the Layer 4 Inbox by kind |
| screen | `Data model` | Platform | retired | Attributes, families, groups and options. |  |  | Nothing: retired (read only, no use); Coverage & completeness › Attributes | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
| screen | `Entry requirements` | Platform | active | Academic entry requirements by country of prior education: provider tables, course requirements, their sources and how a course resolves. |  |  |  |  |
| screen | `Entry requirements › Course entry requirements` | Platform | active |  |  |  |  |  |
| screen | `Entry requirements › Provider entry matrix` | Platform | active |  |  |  |  |  |
| screen | `Entry requirements › Resolution inspection` | Platform | active |  |  |  |  |  |
| screen | `Entry requirements › Sources, reads and holds` | Platform | active |  |  |  |  |  |
| screen | `Evidence` | Platform | active | Saved source pages and files, and what they changed. |  |  |  |  |
| screen | `Go-live checklist` | Platform | active | What must be set up and pass before Production is switched on, and the capacity it needs. |  |  |  |  |
| screen | `Guides` | Platform | active | How to run the platform: the Platform guide, and the standard operating procedures for Platform Admins and operators. |  |  |  |  |
| screen | `Guides › Operator SOP` | Platform | active |  |  |  |  |  |
| screen | `Guides › Platform Admin SOP` | Platform | active |  |  |  |  |  |
| screen | `Guides › Platform guide` | Platform | active |  |  |  |  |  |
| screen | `Models & services` | Platform | active | Switch AI models and page-fetching services on or off; configure the AI that runs now and OpenRouter; and the limits each layer depends on. |  |  |  |  |
| screen | `Models & services › AI & OpenRouter` | Platform | active |  |  |  |  |  |
| screen | `Models & services › Fetchers` | Platform | active |  |  |  |  |  |
| screen | `Models & services › Services` | Platform | active |  |  |  |  |  |
| screen | `Models & services › Toolsets & limits` | Platform | active |  |  |  |  |  |
| screen | `Platform health` | Platform | active | Automatic checks across jobs, queues, budgets and the database; what takes space and purging it. |  |  |  |  |
| screen | `Platform health › Capacity` | Platform | retired |  |  |  | Go-live checklist (Capacity) | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
| screen | `Platform health › Health checks` | Platform | active |  |  |  |  |  |
| screen | `Platform health › Storage & retention` | Platform | active | What takes space, the rule for each category, and purging it (moved from its own page) |  |  |  |  |
| screen | `Platform health › Work queues` | Platform | active |  |  |  |  |  |
| screen | `Provider contacts` | Platform | active | International recruitment contacts for each provider. |  |  |  |  |
| screen | `Providers` | Platform | active | Providers, their campuses and their logos. |  |  |  |  |
| screen | `Providers › Archived` | Platform | active |  |  |  |  |  |
| screen | `Providers › Logos & assets` | Platform | active |  |  |  |  |  |
| screen | `Providers › Providers` | Platform | active |  |  |  |  |  |
| screen | `Reference data` | Platform | active | Key dates and the third-party sites the platform refers to, in one list with a type filter. |  |  |  |  |
| screen | `Reference data › Key dates` | Platform | retired |  |  |  | Reference data (one list, type Key dates) | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
| screen | `Reference data › Reference sources` | Platform | retired |  |  |  | Reference data (one list, type Reference sources) | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
| screen | `Scheduled jobs` | Platform | active | Every automation the platform runs, the order work is taken in, job history and refresh schedules. |  |  |  |  |
| screen | `Scheduled jobs › Automations` | Platform | active |  |  |  |  |  |
| screen | `Scheduled jobs › Jobs` | Platform | active |  |  |  |  |  |
| screen | `Scheduled jobs › Priority queue` | Platform | retired |  |  |  | Focus list and Layer 2/3 › Build adapter waves; search cap on Models & services › Toolsets & limits | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Scheduled jobs › Task manager` | Platform | active |  |  |  |  |  |
| screen | `Scrapers & fetchers` | Platform | retired | How pages are fetched: services, keys and limits. |  |  | Models & services › Fetchers | retired v2.15.300 (Platform Admin 20 Oct 2026) |
| screen | `Settings` | Platform | active | Every pipeline setting in one place, by step: throughput, reading, page identity and budgets; keys for outside services (never shown); calls to the consumer API |  |  |  |  |
| screen | `Settings › API usage` | Platform | active | Calls to Zoho API v2 and Website API v2 by key and action; rotate or switch off keys (moved from the API usage page) |  |  |  |  |
| screen | `Settings › Backup & restore` | Platform | active |  |  |  |  |  |
| screen | `Settings › Settings` | Platform | active |  |  |  |  |  |
| screen | `Sources` | Platform | retired | Every source the pipeline reads, across all layers, with its health and history. |  |  | Layer 1 Register (Sources, All layers filter) | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
| screen | `Storage & retention` | Platform | retired | What takes space in the database and file storage, the rule for each category, and purging it. |  |  | Platform health › Storage & retention | retired v2.15.301 (Platform Admin 20 Oct 2026 menu review) |
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
| table | `pim.entity_registry` | Platform | active |  |  | 15 MB |  |  |
| table | `pim.family_attributes` | Platform | active |  |  | 48 kB |  |  |
| table | `pim.family_groups` | Platform | active |  |  | 40 kB |  |  |
| table | `pipeline.acquisition_policies` | Platform | active |  |  | 56 kB |  |  |
| table | `pipeline.admin_control_events` | Platform | active |  |  | 80 MB |  |  |
| table | `pipeline.admin_job_events` | Platform | active |  |  | 7440 kB |  |  |
| table | `pipeline.admin_job_items` | Platform | active |  |  | 5144 kB |  |  |
| table | `pipeline.admin_job_kinds` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.admin_jobs` | Platform | active |  |  | 11 MB |  |  |
| table | `pipeline.admin_read_snapshots` | Platform | active | CF-247 decision W35 (Platform Admin 30 Oct 2026 06:53): derived, read-only snapshots of three slow admin sources (platform notices, scholarship publishability,  |  | 368 kB |  |  |
| table | `pipeline.admin_screen_opens` | Platform | active | CF-247 20 Oct 2026: admin screen use, one row per Melbourne day, page, tab and person (counted). Used to decide which screens retire; read on Platform health. |  | 128 kB |  |  |
| table | `pipeline.aer_course_outcome_builds` | Platform | active | CF-247 AER production closure C1: each build of the course outcome register with its count by outcome (the history of consumer coverage for entry requirements). |  | 32 kB |  |  |
| table | `pipeline.aer_course_outcomes` | Platform | active | CF-247 AER production closure C1 (Platform Admin mandate 30 Oct 2026 §4): derived, read-only course outcome register for academic entry requirements, one primar |  | 29 MB |  |  |
| table | `pipeline.automation_catalogue` | Platform | active |  |  | 136 kB |  |  |
| table | `pipeline.award_link_settings` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.ca_course_scope_keys` | Platform | active |  |  | 1760 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_layer1_apply_course_scope, public.svc_layer1_stage_course_scope_keys; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `pipeline.ca_source_qualifications` | Platform | retired |  |  | 72 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: no function reads it; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.claims` | Platform | active |  |  | 40 kB |  |  |
| table | `pipeline.completeness_daily` | Platform | active |  |  | 14 MB |  |  |
| table | `pipeline.component_usage_snapshots` | Platform | active | CF-247 Decision 260: weekly counters of table reads and writes and index scans, so the hygiene check can tell what nothing has used. |  | 1120 kB |  |  |
| table | `pipeline.consumer_api_baselines` | Platform | active |  |  | 21 MB |  |  |
| table | `pipeline.consumer_reference_bundle_cache` | Platform | active |  |  | 536 kB |  |  |
| table | `pipeline.course_completeness` | Platform | active |  |  | 9288 kB |  |  |
| table | `pipeline.course_coverage_snapshot` | Platform | active | CF-247 W34 (Platform Admin 30 Oct 2026 06:53): one row saying when the coverage totals snapshot (pipeline.course_coverage_totals) was built, when it was last ch |  | 56 kB |  |  |
| table | `pipeline.course_coverage_totals` | Platform | active | CF-247 W34 (Platform Admin 30 Oct 2026 06:53): derived, read-only coverage totals by provider, tier and country, built from pipeline.course_attribute_coverage,  |  | 12 MB |  |  |
| table | `pipeline.course_fact_source_qualifications` | Platform | active |  |  | 952 kB |  |  |
| table | `pipeline.course_fact_source_records` | Platform | active |  |  | 53 MB |  |  |
| table | `pipeline.course_field_source` | Platform | active |  |  | 12 MB |  |  |
| table | `pipeline.course_priority` | Platform | active |  |  | 208 kB |  |  |
| table | `pipeline.data_flags` | Platform | active |  |  | 800 kB |  |  |
| table | `pipeline.directory_institutions` | Platform | retired |  |  | 208 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_directory_anchor_hints, public.svc_directory_page_record, security.directory_match_v1; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.edge_request_log` | Platform | active |  |  | 16 MB |  |  |
| table | `pipeline.enrichment_flag_events` | Platform | active | CF-247 flag unit (15 Oct 2026): the history of every flag: raised, counted, released, re-queued, free check failed; by a job or a person; why; and the evidence. |  | 33 MB |  |  |
| table | `pipeline.environment_settings` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.environment_source_gates` | Platform | active | Environment-specific country/source capability approval. Pilot qualification never implies Production enablement. |  | 48 kB |  |  |
| table | `pipeline.evidence_artifacts` | Platform | active |  |  | 348 MB |  |  |
| table | `pipeline.evidence_audit_columns` | Platform | active |  |  | 80 kB |  |  |
| table | `pipeline.evidence_audit_refs` | Platform | active |  |  | 12 MB |  |  |
| table | `pipeline.evidence_capacity_policy` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.evidence_entity_links` | Platform | active | Derived governed Evidence-to-entity link cache restored to migration history by CF-241. |  | 72 MB |  |  |
| table | `pipeline.evidence_lineage_reconciliations` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.evidence_lineage_stats` | Platform | active | Derived Evidence lineage counters restored to migration history by CF-241; maintained by evidence_lineage_stats_sync triggers. |  | 7640 kB |  |  |
| table | `pipeline.evidence_link_index_state` | Platform | active |  |  | 17 MB |  |  |
| table | `pipeline.evidence_links` | Platform | retired |  |  | 32 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.evidence_storage_dedupe_log` | Platform | active |  |  | 51 MB |  |  |
| table | `pipeline.fc_extract_results` | Platform | active |  |  | 376 kB |  |  |
| table | `pipeline.fee_course_requests` | Platform | active | CF-247 23 Oct 2026 (Platform Admin 09:03 "push it as priority from course page"): a course whose fee the AI fee reader reads first in line once its page has bee |  | 1560 kB |  |  |
| table | `pipeline.fee_wording_rules` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.field_source_rules` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.gap_cause_runs` | Platform | active | CF-247 decision W35 (Platform Admin 30 Oct 2026 06:53): each successful gap-causes run (security.gap_causes_run_v1) with the snapshot hour it wrote and when it  |  | 48 kB |  |  |
| table | `pipeline.gap_cause_snapshots` | Platform | active | CF-247 23 Oct 2026 (Platform Admin 10:25 "What is point of hourly reporting if you are not finding gaps"): every hour, for each country and course attribute, ho |  | 13 MB |  |  |
| table | `pipeline.hygiene_reports` | Platform | active | CF-247 Decision 260: the weekly hygiene check (unused, insecure, unregistered and ready-to-drop components). |  | 32 kB |  |  |
| table | `pipeline.important_dates` | Platform | active |  |  | 72 kB |  |  |
| table | `pipeline.important_links` | Platform | active |  |  | 192 kB |  |  |
| table | `pipeline.integration_secret_registry` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.job_idle_watch` | Platform | active | CF-247 15 Oct 2026: jobs the waste guard pauses when they produce nothing and nothing waits (output_sql takes $1 = since; input_sql counts waiting work). Only j |  | 32 kB |  |  |
| table | `pipeline.job_input_marks` | Platform | active | CF-247 15 Oct 2026: newest input each input-driven job has seen, and when it last did a full check. |  | 32 kB |  |  |
| table | `pipeline.jobs` | Platform | active |  |  | 38 MB |  |  |
| table | `pipeline.l4_rule4_holds` | Platform | active |  |  | 16 kB |  |  |
| table | `pipeline.link_portals` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.link_refresh_policies` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.live_error_acks` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.manual_edit_log` | Platform | active |  |  | 3872 kB |  |  |
| table | `pipeline.manual_locks` | Platform | active |  |  | 1464 kB |  |  |
| table | `pipeline.night_run_queue` | Platform | retired |  |  | 264 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.night_run_rebatch` | Platform | retired |  |  | 120 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.performance_workload_profiles` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.pilot_automation_keys` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.pilot_edge_execution_queue` | Platform | retired |  |  | 80 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.pilot_edge_nonces` | Platform | active |  |  | 31 MB |  |  |
| table | `pipeline.pilot_nonce_functions` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.pim_source_candidates` | Platform | retired |  |  | 48 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: pim_api.manual_pim_candidate_decide, pim_api.manual_pim_candidate_register, pim_api.manual_pim_candidates_read; readers moved off 20 Oct 2026 (migration 20261020140000); drop by paste file; dropped 20 Oct 2026 by paste file (D11 second step; rows in Storage: archive/cf247-d11-drop-9-2026-10-20/39409708653) |
| table | `pipeline.platform_capacity_observations` | Platform | active |  |  | 136 kB |  |  |
| table | `pipeline.platform_capacity_policy` | Platform | active | Operational warning/high/critical planning thresholds. These are CourseFinder policy thresholds, not vendor hard quotas. |  | 32 kB |  |  |
| table | `pipeline.platform_compute_profile` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.platform_cost_model` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.platform_edge_calls` | Platform | active |  |  | 5440 kB |  |  |
| table | `pipeline.platform_health_checks` | Platform | active |  |  | 96 kB |  |  |
| table | `pipeline.platform_health_runs` | Platform | active |  |  | 1968 kB |  |  |
| table | `pipeline.platform_issues` | Platform | active |  |  | 616 kB |  |  |
| table | `pipeline.platform_job_layers` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.platform_notice_acks` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.platform_resource_observations` | Platform | active |  |  | 504 kB |  |  |
| table | `pipeline.platform_toolset_settings` | Platform | active |  |  | 320 kB |  |  |
| table | `pipeline.platform_toolsets` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.platform_uat_catalogue` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.priority_pins` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.production_migration_manifest` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.progress_provider_facts` | Platform | active |  |  | 1024 kB |  |  |
| table | `pipeline.progress_snapshots` | Platform | active |  |  | 1904 kB |  |  |
| table | `pipeline.provider_archives` | Platform | active |  |  | 80 kB |  |  |
| table | `pipeline.provider_asset_candidates` | Platform | retired |  |  | 736 kB | Logo finder (job logo-find) and the Logos & assets screen | 18 Oct 2026: earlier logo-discovery candidates; nothing reads them after 20261018060000; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.provider_contact_audit_events` | Platform | active |  |  | 136 kB |  |  |
| table | `pipeline.provider_contact_checks` | Platform | active |  |  | 1976 kB |  |  |
| table | `pipeline.provider_contact_dispositions` | Platform | active | A16 explicit AU/NZ Provider international-contact coverage/disposition history. Older successful profile runs without attempt-row telemetry are retained as not_ |  | 120 kB |  |  |
| table | `pipeline.provider_contact_import_batches` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.provider_contact_import_rows` | Platform | active |  |  | 136 kB |  |  |
| table | `pipeline.provider_contact_observations` | Platform | active |  |  | 224 kB |  |  |
| table | `pipeline.provider_contact_points` | Platform | active |  |  | 2640 kB |  |  |
| table | `pipeline.provider_contact_profiles` | Platform | active |  |  | 144 kB |  |  |
| table | `pipeline.provider_contact_provider_mappings` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.provider_contact_versions` | Platform | active |  |  | 256 kB |  |  |
| table | `pipeline.provider_contact_watch_events` | Platform | active |  |  | 152 kB |  |  |
| table | `pipeline.provider_contacts` | Platform | active |  |  | 112 kB |  |  |
| table | `pipeline.provider_credit_fees` | Platform | active |  |  | 112 kB |  |  |
| table | `pipeline.provider_directory_observations` | Platform | retired |  |  | 120 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.layer2_hotcourses_directory_apply; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `pipeline.provider_document_checks` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.provider_fact_search` | Platform | active |  |  | 184 kB |  |  |
| table | `pipeline.provider_fact_sources` | Platform | active |  |  | 2120 kB |  |  |
| table | `pipeline.provider_fee_basis_rules` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.provider_fee_profiles` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.provider_fee_range_settings` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.provider_fee_rows` | Platform | active |  |  | 1648 kB |  |  |
| table | `pipeline.provider_policy_proposals` | Platform | active |  |  | 4192 kB |  |  |
| table | `pipeline.provider_priority` | Platform | active |  |  | 480 kB |  |  |
| table | `pipeline.provider_type_rules` | Platform | active | Decision 258: institution type rules. Text fields are case-insensitive patterns matched against register facts. First enabled match by position wins. |  | 32 kB |  |  |
| table | `pipeline.publication_control_settings` | Platform | active |  |  | 24 kB |  |  |
| table | `pipeline.queue_watch` | Platform | active | CF-247 22 Oct 2026 (progress watchdog): the enrichment queues the watchdog watches. pending_sql counts work a tool can take now, progress_sql gives the time the |  | 128 kB |  |  |
| table | `pipeline.queue_watch_alerts` | Platform | active | CF-247 22 Oct 2026 (progress watchdog): alert outbox. channel notify (Stuck, Out of toolset) is sent as push and email; channel report (Done, Nothing left to tr |  | 128 kB |  |  |
| table | `pipeline.queue_watch_events` | Platform | active | CF-247 22 Oct 2026 (progress watchdog): every change of a watched queue's state, for the history on Platform health and the daily report. |  | 200 kB |  |  |
| table | `pipeline.queue_watch_fixes` | Platform | active | CF-247 22 Oct 2026 (progress watchdog): log of the safe fixes the watchdog made by itself (one more try for items that gave up on a passing error). |  | 88 kB |  |  |
| table | `pipeline.queue_watch_retries` | Platform | active | CF-247 22 Oct 2026 (progress watchdog): items the watchdog gave one more try, so each gets it at most once per queue_watch.retry_days. |  | 280 kB |  |  |
| table | `pipeline.queue_watch_state` | Platform | active | CF-247 22 Oct 2026 (progress watchdog): the latest state of each watched queue (moving, waiting, stuck, failing, out_of_toolset, nothing_left, done, paused) wit |  | 32 kB |  |  |
| table | `pipeline.reading_restores_20261005` | Platform | retired |  |  | 40 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.reference_institutions` | Platform | active |  |  | 3432 kB |  |  |
| table | `pipeline.refresh_policies` | Platform | active |  |  | 64 kB |  |  |
| table | `pipeline.refresh_policy_action_events` | Platform | active |  |  | 56 kB |  |  |
| table | `pipeline.refresh_requests` | Platform | active |  |  | 3408 kB |  |  |
| table | `pipeline.refused_host_changes` | Platform | retired |  |  | 224 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `pipeline.retention_class_policies` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.retention_estimates` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.retention_evidence_skips` | Platform | active |  |  | 16 kB |  |  |
| table | `pipeline.retention_file_queue` | Platform | active |  |  | 936 kB |  |  |
| table | `pipeline.retention_runs` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.scheduler_workflow_async_bindings` | Platform | active |  |  | 312 kB |  |  |
| table | `pipeline.search_pass_links` | Platform | active |  |  | 3224 kB |  |  |
| table | `pipeline.search_refresh_signals` | Platform | active |  |  | 360 kB |  |  |
| table | `pipeline.settings_backups` | Platform | active | CF-247 22 Oct 2026 (Platform Admin "daily unpublished providers ... backup on daily basis and restore it, only by platform admin"): a copy of every provider's P |  | 1344 kB |  |  |
| table | `pipeline.source_provider_mappings` | Platform | active |  |  | 488 kB |  |  |
| table | `pipeline.source_record_staging` | Platform | active |  |  | 3432 kB |  |  |
| table | `pipeline.sources` | Platform | active |  |  | 2168 kB |  |  |
| table | `pipeline.statistics_dataset_registry` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.statistics_edition_candidates` | Platform | active |  |  | 48 kB |  |  |
| table | `pipeline.statistics_edition_rules` | Platform | active |  |  | 32 kB |  |  |
| table | `pipeline.stats_15m` | Platform | active | CF-247 22 Oct 2026: a snapshot every 15 minutes (job stats-15m) of course progress per country, toolset use, worker calls, watchdog states and the gaps found; r |  | 3152 kB |  |  |
| table | `pipeline.storage_size_daily` | Platform | active | CF-247 16 Oct 2026 (Platform Admin: "record all db and tables data and sizes also prepare total bucket usage ... on daily basis"): one row a day for the databas |  | 1888 kB |  |  |
| table | `pipeline.toolset_sample_items` | Platform | active |  |  | 4152 kB |  |  |
| table | `pipeline.toolset_sample_runs` | Platform | active |  |  | 424 kB |  |  |
| table | `pipeline.university_reread_requests` | Platform | active |  |  | 240 kB |  |  |
| table | `pipeline.vendor_credit_observations` | Platform | active |  |  | 1072 kB |  |  |
| table | `pipeline.vendor_credit_requests` | Platform | active |  |  | 320 kB |  |  |
| table | `pipeline.zz_qualify_scratch_v1` | Platform | retired |  |  | 304 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `public._tmp_cf265_fetch` | Platform | retired | CF-247 scratch (18 Oct 2026, Decision 265 survey): request ids of direct reads of Torrens and Wollongong course pages to find which page prints each course's CR |  | 152 kB |  | gone 2026-10-18 |
| table | `security.admin_summary_snapshots` | Platform | active |  |  | 248 kB |  |  |
| table | `security.data_quality_overview_snapshots` | Platform | active |  |  | 216 kB |  |  |
| table | `security.roles` | Platform | active |  |  | 48 kB |  |  |
| table | `security.service_permissions` | Platform | active |  |  | 24 kB |  |  |
| table | `security.user_access_events` | Platform | active |  |  | 64 kB |  |  |
| table | `security.user_roles` | Platform | active |  |  | 64 kB |  |  |
| table | `workflow.export_jobs` | Platform | active |  |  | 24 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_admin_access_guard_delete, public.svc_layer1_reset_au_uat, public.svc_layer1_reset_database; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `workflow.handover_events` | Platform | active |  |  | 48 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_admin_access_guard_delete, public.svc_layer1_reset_au_uat, public.svc_layer1_reset_database; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `workflow.import_errors` | Platform | retired |  |  | 32 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_layer1_reset_au_uat, public.svc_layer1_reset_database; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `workflow.import_jobs` | Platform | active |  |  | 24 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_admin_access_guard_delete, public.svc_layer1_reset_au_uat, public.svc_layer1_reset_database; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| table | `workflow.import_rows` | Platform | retired |  |  | 48 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_layer1_reset_au_uat, public.svc_layer1_reset_database; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `workflow.migration_entity_map` | Platform | retired |  |  | 112 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_layer1_reset_au_uat, public.svc_layer1_reset_database; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `workflow.migration_runs` | Platform | retired |  |  | 32 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_layer1_reset_au_uat, public.svc_layer1_reset_database; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `workflow.reconciliation_checks` | Platform | retired |  |  | 24 kB | nothing: idle (usage audit D11) | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.svc_layer1_reset_au_uat, public.svc_layer1_reset_database; dropped 20 Oct 2026 by paste file (D11; 14-day wait waived by the Platform Admin; rows in Storage: archive/cf247-d11-drop-34-2026-10-20/39405000377) |
| table | `workflow.suggestions` | Platform | active |  |  | 48 kB |  | D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: public.admin_fee_rules_read, public.svc_admin_access_guard_delete, public.svc_layer1_reset_au_uat, public.svc_layer1_reset_database, security.admin_pipeline_ops_read, security.provider_onboarding_step_v1; kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use |
| view | `pipeline.evidence_acquisition_provenance_v1` | Platform | active |  |  |  |  |  |
| view | `public.catalogue_stats` | Platform | active |  |  |  |  |  |
| view | `public.course_completeness_v2` | Platform | active |  |  |  |  |  |
| view | `public.evidence_artifacts` | Platform | active |  |  |  |  |  |
| view | `public.field_values` | Platform | active |  |  |  |  |  |
| view | `public.ingest_jobs` | Platform | active |  |  |  |  |  |
| view | `public.pim_attribute_definitions` | Platform | active |  |  |  |  |  |
| view | `public.providers` | Platform | active |  |  |  |  |  |
| view | `security.provider_hidden_v1` | Platform | active |  |  |  |  |  |
| function | `security.nz_resolution_measures_v1` | Reporting | active | Daily measure per NZ review resolution |  |  |  |  |
| function | `security.provider_field_daily_record_v1` | Reporting | active | Writes a day of field counts per provider |  |  |  |  |
| function | `security.toolset_use_daily_record_v1` | Reporting | active | Writes a day of toolset use per provider |  |  |  |  |
| job | `provider-field-daily` | Reporting | active | Daily field counts per provider: Daily at 6:55 am Melbourne (daylight time): records each provider's courses, the courses holding each field and the provider fi |  |  |  |  |
| job | `toolset-use-daily` | Reporting | active | Daily toolset use per provider: Daily at 6:58 am Melbourne (daylight time): records the day before's use of each tool per provider (course search, page reads, A |  |  |  |  |
| table | `pipeline.provider_field_daily` | Reporting | active | CF-247 21 Oct 2026: one row a day (Melbourne date) per provider with active courses: courses, the number of courses holding each course field (course_filled) an |  | 15 MB |  |  |
| table | `pipeline.toolset_use_daily` | Reporting | active | CF-247 22 Oct 2026 (Platform Admin "keep the stat how much of toolset we used used successfully and failed"): one row a Melbourne day per provider and tool: tim |  | 4064 kB |  |  |
| function | `public.svc_scholarship_recheck_next` | Scholarships | active | Held scholarship pages: next to re-check |  |  |  |  |
| function | `public.svc_scholarship_recheck_record` | Scholarships | active | Held scholarship pages: re-check result |  |  |  |  |
| function | `security.scholarship_recheck_fire_v1` | Scholarships | active | Starts the re-check run while held pages are queued |  |  |  |  |
| job | `scholarship-recheck` | Scholarships | active | Re-check held scholarship pages: Every 2 minutes while held pages are queued: the first model of the scholarship chain answers who may apply and the value, each |  |  |  |  |
| function | `security.entry_course_payload_v1` | Search and API | active | Track C Step B (B2): course payload entry object |  |  |  |  |
| function | `security.entry_matrix_payload_v1` | Search and API | active | Track C Step B (B2): provider payload entry_matrix |  |  |  |  |
| edge_function | `website-api-v2` | Website API | active | Website API v2 at its own URL (CF-247, 16 Oct 2026). Platform Admin 09:55: "I want a separate URL for each API version going forward. Lets | 2026-10-31 |  |  |  |
| edge_function | `wix-course-api` | Website API | active | CF-CHG-20260915-247 WP3c: this function previously existed only in the live | 2026-10-14 |  |  |  |
| edge_function | `zoho-course-api` | Website API | active |  | 2026-10-30 |  |  |  |
| function | `public.website_v2_sync(text,boolean,text[],integer)` | Website API | active | Website sync: serves the items the change check stored |  |  |  |  |
| function | `search.refresh_course_documents_v2(boolean)` | Website API | retiring | Old projection refresh; no caller and no job since search.refresh_course_base_v3 |  |  | search.refresh_course_base_v3(boolean) |  |
| job | `campus-regional-class-refresh` | Website API | active | Campus regional category: Updates each campus's metro or regional category. |  |  |  |  |
| job | `consumer-reference-bundle-refresh` | Website API | active | Rebuild API reference data: Rebuilds the reference data the website API serves (providers, groups, fields). |  |  |  |  |
| job | `search-refresh-requested` | Website API | active | Refresh search for changed courses: Updates search and the API for courses whose facts changed. |  |  |  |  |
| job | `website-reference-cache` | Website API | active | Website reference: build the copy: Every 15 minutes: builds the website API reference (vocabularies with counts) so the reference action answers at once. |  |  |  |  |
| job | `website-sync-check` | Website API | active | Website sync: change check: Every minute: builds website API items in a rolling pass and numbers each new, changed or removed item (and each logo whose link is  |  |  |  |  |
| table | `private.zoho_integration_credentials` | Website API | active |  |  | 32 kB |  |  |
| table | `private.zoho_integration_rate_windows` | Website API | active |  |  | 128 kB |  |  |
| table | `search.course_documents` | Website API | active |  |  | 232 MB |  |  |
| table | `search.course_embeddings` | Website API | active |  |  | 40 kB |  |  |
| table | `search.embedding_jobs` | Website API | active |  |  | 40 kB |  |  |
| table | `search.intent_aliases` | Website API | retired |  |  | 48 kB |  | Usage audit 15 Oct 2026, decision D10 (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914) |
| table | `search.profiles` | Website API | active |  |  | 64 kB |  |  |
| table | `search.projection_country_gates` | Website API | active |  |  | 48 kB |  |  |
| table | `search.projection_state` | Website API | active |  |  | 416 kB |  |  |
| table | `search.query_embedding_cache` | Website API | active |  |  | 24 kB |  |  |
| table | `search.refresh_requests` | Website API | active |  |  | 1280 kB |  |  |
| edge_function | `zoho-api-v2` | Zoho API | active | Zoho API v2 (CF-247, 16 Oct 2026). Platform Admin 09:43: "create separate API URL and Key for Zoho V2 API and keep it separate from | 2026-10-30 |  |  |  |
| function | `public.zoho_v2_export_page(text, integer)` | Zoho API | active | Zoho v2 CSV export, one page |  |  |  |  |
| function | `public.zoho_v2_export(text)` | Zoho API | retiring | Zoho v2 CSV export, whole file (timed out for courses) |  |  | public.zoho_v2_export_page(text, integer) | The whole-file export timed out for courses (16 Oct 2026); the edge function calls the paged export from 20261016040000 |
| function | `public.zoho_v2_report` | Zoho API | active | Counsellor report on a course, institute, campus or contact (Zoho API v2 report) |  |  |  |  |
| function | `public.zoho_v2_report_status` | Zoho API | active | Outcome of counsellor reports (Zoho API v2 report_status) |  |  |  |  |
| job | `zoho-sync-check` | Zoho API | active | Zoho sync: change check: Every minute: builds Zoho API v2 items (providers, campuses, contacts, courses of the countries in Zoho API settings) in a rolling pass |  |  |  |  |
| table | `pipeline.zoho_sync_items` | Zoho API | active | CF-247 16 Oct 2026 (Zoho API v2): the Zoho change stream. One row per provider, campus, contact and course of the countries in zoho.sync_countries, numbered (se |  | 75 MB |  |  |
| table | `pipeline.zoho_sync_scan` | Zoho API | active | CF-247 16 Oct 2026 (Zoho API v2): where the Zoho change check has got to in its rolling pass, per entity, and when it last finished a pass. |  | 32 kB |  |  |

