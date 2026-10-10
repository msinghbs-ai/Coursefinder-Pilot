# Changelog

## 0.1.169 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.242** (scholarships read through the scraper, S7; Platform Admin request 11 Oct 2026). Scholarship pages and provider listing pages are read through Firecrawl first (rendered page), for every provider, within the scholarship credit cap; a direct read is the fallback. New Layer 2 setting "Read scholarship pages through the scraper" (on/off switch on Scholarships › Coverage › Settings and jobs). Database: `20261011008200` (setting; svc_scholarship_fc_budget passes it to the worker; credit cap 6,000 to 12,000; every active scholarship page and listing page queued to be read again), applied by the Database apply migration workflow. Worker coverage-sweep v0.17.40. On/off scholarship settings show as switches.

## 0.1.168 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.241** (rename to StudySearch, S6; customer request 11 Oct 2026). App text, mark, titles and guide renamed. Database: `20261011007700` (82 functions: the word CourseFinder in messages and labels becomes StudySearch; md5-guarded), applied by the Database apply migration workflow. Repositories, web address, Wix/Zoho contract names, saved screen settings and reader user agents unchanged until production.

## 0.1.167 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.240** (scholarship coverage check, S3; bulk restore, S5). Database: `20261011007300` (listing pages, coverage checks, watch list of 27, coverage read/provider/write RPCs, scholarship-listing job and settings, bulk restore), applied by the Database apply migration workflow. Worker coverage-sweep v0.17.37 (mode scholarship_listing). Scholarships › Coverage screen; Providers › Archived bulk restore; scholarship settings and jobs without reason prompts.

## 0.1.166 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.239** (scholarship completeness, S1, S2 and S4; Platform Admin decisions of 11 Oct 2026). Database: `20261011007100` (scholarship APIs published only) and `20261011007200` (course links when the page names no restriction or an unmatched faculty; editions held; hourly auto-publish; values read again), applied by the new Database apply migration workflow. Worker coverage-sweep v0.17.36 (scholarship reader v0.6.3: academic-result percentages ignored; whole-sentence value text).

## 0.1.165 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.238** (Platform Admin bug list of 10 Oct 2026, R5: Features 5, 6 and 7; decision "New 'archived' status"). Database: `20261010007000` (md5-guarded): pipeline.provider_archives; archive and restore clean-up workflow with a checklist (status archived, unpublished, adapter and course link search off, waiting reviews superseded; restored exactly); Layer 1 departures archive and restore providers automatically; admin_archive_read; course archive by hand rebuilds search; non-active courses blocked from consumer APIs. Providers › Archived screen; lists show active records by default.

## 0.1.164 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.237** (Platform Admin bug list of 10 Oct 2026, R4 part 2: Feature 4, pause work). Database: `20261010006900` (md5-guarded): 20 automatic pickers skip providers in security.provider_hidden_v1 (unpublished or not active); hand-started admin work is not blocked; wrong public contact emails cleared and re-read. Worker coverage-sweep v0.17.35: contact emails must be on the provider's own domain (registrable name) and library, vet hospital, ethics, philanthropy, partnership, facilities and research mailboxes are skipped.

## 0.1.163 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.236** (Platform Admin bug list of 10 Oct 2026, R4 part 1: Feature 4, Published switch). Database: `20261010006800` (md5-guarded): security.provider_hidden_v1 joins the Layer 4 search-block views; every active provider published and new providers published by default; admin_provider_publish; course index build, Wix/website providers, single course, scholarships, rankings and Zoho scholarships gated. Provider list: Published switch, unpublished rows greyed.

## 0.1.162 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.235** (contact quality after the first R3 runs). Worker coverage-sweep v0.17.34: contact_page skips media/security/feedback and similar mailboxes and prefers the main contact page; cricos_peo reads the CRICOS institution page by provider code (no search). Database: `20261010006700` (md5-guarded): earlier automated values are replaced on re-read; checks re-queued; schedules back on.

## 0.1.161 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.234** (Platform Admin bug list of 10 Oct 2026, R3: Fix 2; decisions "Both, kept separate", "Fill automatically", CRICOS contacts "All at once"). Database: `20261010006600` (md5-guarded; additive): pipeline.provider_contact_points and provider_contact_checks; worker functions; provider read returns the contact source and, for PIM Operators and above, the internal regulatory contact; schedules provider-contact-page and cricos-peo. Worker coverage-sweep v0.17.33: modes contact_page and cricos_peo.

## 0.1.160 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.233** (Platform Admin bug list of 10 Oct 2026, R2: Fix 1, Feature 1, Feature 3; Hotcourses kept for logos only). Database: `20261010006500` (md5-guarded; no drops or deletes): twelve course directories join the third-party list; security.third_party_host_v1 and provider_site_verdict_v1; third-party sites refused as website, course finder or course page; directory site hints retired; third-party course finders cleared, their pages refused and facts read from them withdrawn; own sites found by the search copied to Website. Worker coverage-sweep v0.17.32: an AU site needs the CRICOS code on its home page, or on a deeper page of an address that fits the name.

## 0.1.159 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.232** (Platform Admin bug list of 10 Oct 2026, R1: Fix 3, Fix 4, Fix 5, Feature 2). Database: `20261010006400` (md5-guarded changes to admin_provider_edit, svc_coverage_site_record, admin_firecrawl_write and admin_adapter_builder). A course finder address entered by hand is locked and kept; the adapter builder asks for the provider's own website when none is recorded, starts page finding for one provider, takes a course page entered by hand (own site only) as a sample, and no longer asks for reasons.

## 0.1.158 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.231** (Platform Admin: load course insights on More; simple logo list). Database: `20261010006300` (md5-guarded admin_read change, applied through the connector: course_detail no longer returns related insights, ranking context, taxonomy or state summaries; new course_insights operation; about 85 KB to 21.5 KB). Providers › Logos & assets is a simple has-logo / no-logo list.

## 0.1.157 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.230** (UI stage 3: Rankings, Reference data, Settings, Models and services, Go-live checklist, remaining admin pages). Settings rows, Go-live and Capacity headers and the environment panels use the standard text sizes. The look-and-feel rollout across the app is complete.

## 0.1.156 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.229** (UI stage 2: Layer 1 register, Layer 2, Coverage, Sources, Platform health). Boxed filter selects keep their box under the standard control style (fixes the Sources/Jobs overflow from v2.15.227); Sources and Jobs headers slimmed; plain wording on Layer 1 manual batch runs and alerts; adapter names and tick labels sized consistently.

## 0.1.155 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.228** (Platform Admin: check usage, retire unused; remove the Reset database button and function). Clean-up batch 7: database `20261009006200` (6 functions of the old scale-qualification chain, md5-guarded, no CASCADE; 8 run-token rows) and 8 edge functions retired (coursefacts-au-qut/rmit/uq, layer2-scale-qualify-scheduled, layer2-screenshot-backfill-scheduled, layer3-source-pattern-benchmark, layer1-au-completeness, pilot-reset). The Go-live checklist no longer offers Reset database.

## 0.1.154 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.227** (Platform Admin: same look on every page, in stages; stage 1 — Dashboard, Layer 3, Layer 4 review, Scheduled jobs, Evidence). Every table resizes like the catalogue lists (shared helper, widths kept per page in the browser); dropdowns and inputs share one style; Evidence and Jobs lose their repeated headers; Layer 4 More button and dashboard tiles aligned.

## 0.1.153 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.226** (Platform Admin: slim the provider read). Database: `20261009006000` (md5-guarded admin_read change: provider_detail no longer returns the course, evidence, source and history lists or the scholarship, ranking and logo context; new provider_insights operation for related insights; about 385 KB to 4.4 KB for RMIT). The provider panel loads related insights only when More is opened.

## 0.1.152 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.225** (Platform Admin: lists fill the page width with resizable columns; course and provider panels as coloured pills and fact cards, with unnecessary evidence, regulatory and operational text removed; same look for other record panels). Bug fix: a long nationality list no longer pushes scholarship columns off screen.

## 0.1.151 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.224** (Platform Admin: modern, readable UI with coloured pills; clean up the old system's UI). Scholarships list: status pills for type, who it is for, linked courses and closing date (open, closing within 30 days, closed), using the shared StatusChip tones; names and values wrap to two lines. Clean-up batch 3 (screens): the old onboarding cases panel removed from Providers › Onboarding (no case was ever opened; RPCs onboarding_cases_* now have no screen), two orphaned stylesheets removed (layer2-operations.css, enrichment-operations.css), Live activity wording updated. Kept after a live check: Search pass (used by adapters), Sample runs (service test tool), Refresh schedules (Layer 1).
- Phase 3 shadow run, round 3 (Platform Admin: try one escalation step). Database: `20261008005700` (md5-guarded: the adapter's own model reads first; only when it finds nothing and the page clearly shows the field is MiMo v2.6 Pro asked, once; each read records whether it escalated; nothing admitted). Worker layer3-model-routing shadow v1.2.0. Round 2 result (e60): no field met the retire rule.
- Clean-up of the old system, batch 4 (database; Platform Admin: prepare it now). Database: `20261008005600` (15 functions of the old Layer 2 schedulers, wave and scope services, the Layer 3 enqueue, the scholarship settings wrapper and the onboarding-case RPCs dropped behind md5 guards, no CASCADE; the Layer 2 branch removed from the pilot edge-execution trigger; run-token rows for retired functions removed; no table, data or history dropped). Four dormant edge functions retired (layer2-extract-v2, layer2-course-fact-extract-v2, layer2-scholarship-extract, layer2-scholarship-catalogue-enumerate). Kept for a later decision: the provider-asset functions (page fan-out, asset promote, hotcourses directory parse), layer2-acquire-v2, layer2-scope-discover-scheduled, and 11 old functions still reached from admin_read or the scheduler workflow bridges.
- Phase 3 closes (Platform Admin: keep Layer 3, stop shadow). The shadow run is switched off (admin_adapter_shadow, logged). Database: `20261008005800` (the three shadow jobs removed; refused while the run is on; tables, functions and reads kept as the record). Layer 3 keeps intakes, English and tuition.
- Clean-up of the old system, batch 5 (database; Platform Admin: proceed with next step). Database: `20261008005900` (md5-guarded, 32 guards checked read-only first; no CASCADE): 31 functions dropped — the one-off run builder's scheduler-workflow chain, the Layer 2 operator, scope-batch, background and wave dispatch chain, and the old scholarship scope and runtime chain with pipeline.svc_pilot_invoke_layer2; dead admin_read operations removed (scholarship_runtime, scholarship_runtime_uat, layer2_profiles, layer2_profile_detail, layer2_provider_routes). No table, data or history dropped. Kept: scheduler_workflow_profile_binding_snapshot_v1, _queueable_url_allowed_v1 and _https_host_v1 (still used by Layer 2 discovery and provider attempts).

## 0.1.150 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.223** (Scholarships list: one sortable column per fact, fitted to the screen; release of the clean-up batch 2 screen removals and the Adapter builder link on Providers › Onboarding).

## 0.1.149 — 8 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.222** (Layer 1 schedule choice per source; ranking edition years from two years ahead back to 2010).
- Database: `20261008002700` (`admin_layer1_schedule`, Platform Admin only, logged; no source's schedule changed).
- Database: `20261008002800` (NZQA register adapter `nz_nzqa`, switched off; replay runs may list several stored files; `svc_register_replay_next_v3`; three NZQA replay runs) and `20261008002900` (replay driver started again). Worker coverage-sweep v0.17.21 (register_replay reads registers published as web pages, three stored batch files a call; reference is the layer1-nz-live v1.2.1 code).
- Database: `20261008003000` (PRISMS SA4 and QILT GOS, SES, GOS-L and ESS register adapters, switched off; six replay runs on the stored workbooks). Worker coverage-sweep v0.17.22 (register_replay reads statistics workbooks; references are prisms-au-etl v0.2.0 and qilt-au-etl v0.3.0).
- Layer 1 fix: qilt-au-etl v0.3.1 stores the confidence interval upper bound (v0.3.0 read `cell.h`, always empty). Database: `20261008003100` (refills the upper bound of 3,103 existing QILT rows from the published cell kept with each row; refused unless values and lower bounds read back unchanged). Worker coverage-sweep v0.17.23 (QILT reference follows v0.3.1).
- Database: `20261008003200` (QILT workbooks replayed again after the fix) and `20261008003300` (`admin_register_adapter_switch`, Platform Admin only, logged, switches on only after a passing replay with the spec unchanged since; `svc_register_adapter_reader`). Register engines moved to `supabase/functions/_shared/cf247-register-*.ts`. layer1-nz-live v1.3.0 and prisms-au-etl v0.3.0 read with their register adapter when it is switched on.
- Database: `20261008003400` (NZQA and PRISMS replayed again before switch-on), `20261008003500` (a replay run is leased to one call; `svc_register_replay_release`), `20261008003600` (PRISMS pre-switch replay re-run). Worker coverage-sweep v0.17.24 (releases the lease when a call ends).
- CRICOS register adapter version 2 (`20261008003700`, applied after the worker deploy): provider postal address and the campus and course location sets; engine adds `adapterSelect`, `adapterSets` and `adapterFingerprints`. layer1-au-depth v1.8.0 and layer1-au-cricos-facts v1.3.0 read with the adapter when it is switched on (local checks: fingerprints and every batch structure identical to the Layer 1 scans; plan fingerprints cost the same CPU as Layer 1). Worker coverage-sweep v0.17.25 (CRICOS replays compare the address fields and both location sets).
- Database: `20261008003800` (CRICOS v2 replays started), `20261008003900` (17 Canadian register adapters, format text_items, switched off: 16 Ontario college catalogues and IRCC DLI; replay runs on every stored August copy) and `20261008004000` (replay driver started). Engine `_shared/cf247-register-items.ts`; references `_shared/cf247-register-ca-ref.ts` (verbatim copies of the Layer 1 readers, checked by a contract test). Worker coverage-sweep v0.17.26.
- Worker coverage-sweep v0.17.27: a key repeated within one replay call is saved as key#2, key#3 (the CRICOS v2 location sets repeat some locations); `20261008004000` also replays the three CRICOS archives again.
- Canadian Layer 1 readers that kept only parsed output now also store the raw pages they fetch as a `-raw.json` evidence bundle beside their evidence (centennial, cna, fanshawe, firstparty-catalogues, mb, northern, ns-sk, on-college, sault, sk, stlawrence), so their parsing can be replayed after their next run. Nothing they parse or apply changes.
- Worker coverage-sweep v0.17.28: text_items fields are read in dependency order (a spec stored as jsonb loses key order; the Conestoga replay read 0 records).
- Database: `20261008004100` (four Canadian replays run again after the field-order fix) and `20261008004200` (ALIS and EducationPlannerBC register adapters, switched off; replays on the newest stored bundle per school and institution). Worker coverage-sweep v0.17.29 (text_items reads bundles of stored pages, lists, lookups and nested objects).
- Worker coverage-sweep v0.17.30: the CRICOS adapter joins and reads only the records of each replay slice (version 2 ran out of worker resources). Database: `20261008004300` (a replay run stops with an error after three calls end without saving at the same position; a leased run no longer holds up the others).
- Worker coverage-sweep v0.17.31: CRICOS v2 replays read each location set in a call of its own after the records. Database: `20261008004400` (the 11 Aug archive replay resumes).
- Scholarships central register (Platform Admin decisions: central register, country tagged; record for government, index for provider; AU then NZ then CA, monthly). Database: `20261008004500` (`scholarship.registers` AU, NZ, CA; `scholarship.register_listings`; Study Australia and DFAT Australia Awards registered as Layer 1 sources, source_system SCHOLARSHIP_REGISTER, no schedule switched on; the old hourly feeds for the same sources switched off; listings matched to held scholarships and unmatched provider pages handed to the provider page reader; `admin_scholarship_registers`). Workers: scholarships-au-etl v0.2.0 (whole Study Australia listing read, raw pages kept, stable count and hash; detail reads in batches for the provider page link and CRICOS), layer1-operations-control v1.7.0 and layer1-operations-scheduled v1.3.0 (verify and run the scholarship registers).
- Fix: `20261008004600` (provider page candidates accept the source `register`; the first Study Australia detail batch had failed on the old three-value check and rolled back).
- Fix: `20261008004700` (a provider page that several listings point at is handed to the page reader once; the second detail batch had failed and rolled back).
- Scholarships New Zealand register (Platform Admin: take recommended decisions). Database: `20261008004800` (Manaaki New Zealand Scholarships as a Layer 1 source, register `nz_mfat_manaaki` live, no schedule switched on). Workers: scholarships-au-etl v0.3.0 (feed nz_manaaki: eligible countries by region and destination, levels, approved institutions with their official sites, application rounds and criteria read from the pages; stops if countries or institutions are not found), layer1-operations-control v1.7.1 and layer1-operations-scheduled v1.3.1 (dispatch the New Zealand register).
- Government awards reach courses through approved institutions (Platform Admin: publish the government records; link to approved institutions). Database: `20261008004900` (11 nationality terms added and 2 extended; register record profile sets nationalities from the register's country lists, audience international, and course links at the approved institutions for bachelor, master's, doctorate and postgraduate diploma/certificate courses; `admin_scholarship_register_institutions` for a Platform Admin to pick institutions; the audience and nationality wording jobs no longer overwrite a register record; a register record with full tuition coverage counts as having a stated value; md5-guarded patches; nothing published). Worker scholarships-au-etl v0.3.1 (records where each institution's site redirects; runs the profile after each government register read).
- Scholarship countries (Platform Admin: AU, NZ and CA only for now; plan in place as countries join). Database: `20261008005000` (country switch off for DE, GB, IE and US, which have no courses; `scholarship.country_onboarding` with each country's status, domestic-student wording and government registers; planned registers Chevening, Commonwealth Scholarships, Fulbright; `security.scholarship_country_readiness_v1`; daily job scholarship-country-watch raises a platform issue when a country has courses but scholarships are off or not ready, and resolves it itself; `admin_scholarship_country` (Platform Admin, only when ready, queues the country's universities for discovery); `admin_scholarship_countries`; the university test and the audience reader no longer hard-wire NZ and CA (md5-guarded; behaviour for AU, NZ and CA unchanged)).
- Canadian catalogue and register sources on Layer 1, phase A (Platform Admin: Canada Layer 1 schedule). Database: `20261008005100` (26 sources name their reader, source_system CA_READER: 23 college and provincial catalogues, Aurora and Yukon through the first-party reader, and the IRCC Designated Learning Institutions register; Layer 1 operations rows with verification due now and no schedule switched on; 15 readers added to the run-token allow-list). Workers: layer1-operations-control v1.8.0 and layer1-operations-scheduled v1.4.0 (verify and run Canadian readers; IRCC applied in slices of 200), layer1-ca-live v1.2.0 (accepts the Layer 1 service key; added to the deploy list). layer1-ca-seneca-catalogue: the deployed v0.3.1 is now checked in (git held v0.1.0).
- Clean-up of the old system, batch 1 (Platform Admin: clean up the old system as we go). 24 unused edge functions retired (one-off QS ranking probes and recoveries, Layer 1 UAT gates and inspectors, the Layer 2 trial and discovery prototypes, layer3-benchmark-go5, layer4-course-resolve, scholarship-course-fill-control, search-vector-gate): no repository, database or cron reference; source removed and added to the deploy workflow's retired list for deletion from the live project. Database: `20261008005200` (eight cron jobs switched off on 2 Oct removed: seven of the old Layer 2 pipeline and the old Layer 3 tuition enqueue; refused if any is switched on; functions and history kept; definitions recorded in the file). Canadian probes left in place (Canada parked).
- Phase 3 of the adapter design: merged reading step run side by side with Layer 3 (Platform Admin: US$15/day, ~1,000 courses/day; retire a field at 95%+ agreement and at least as many found). Database: `20261008005300` (`pipeline.adapter_shadow_settings` and `pipeline.adapter_shadow_reads`; `svc_adapter_shadow_claim` and `svc_adapter_shadow_complete`, service role; `security.adapter_shadow_summary_v1` with the retire test, reported only; `admin_adapter_shadow` summary, providers and settings, Platform Admin, logged; jobs adapter-shadow-intake and adapter-shadow-english every 2 minutes). Worker layer3-model-routing shadow mode (`cf247-adapter-shadow-v1.0.0`; routing version and binding hashes unchanged): the adapter's own model (pinned) reads finished Layer 3 courses on the adapter's input for the field (JSON path, heading section, else the whole page) with the same task contract and checks; nothing is admitted. `_shared/cf247-adapter-shadow.ts`.
- Phase 3 shadow run: tuition added and capacity raised (Platform Admin: add tuition or any other attribute as required; finish in about 4 hours). Database: `20261008005400` (md5-guarded: task tuition; tuition read under the tuition task's own prompt, checks and input length with the adapter's pinned model; a pick counts as found and agrees on amount to the dollar, fee year and audience; 1,500 reads a day, 500 a field; courses finished in the last 30 days; 6 reads a field every 2 minutes; job adapter-shadow-tuition). Worker layer3-model-routing shadow v1.1.0. Layer 3 reads only these three fields, so all are now compared.
- Clean-up of the old system, batch 2 (Platform Admin, 9 Oct 2026: retire the old data-admission system). Removed screens: Scrapers › Source profiles (with per-source fetchers and Test fetch one page), Layer 2 workload defaults, Layer 2 automation, dispatcher tuning and scholarship runtime settings on Scrapers & fetchers, the one-off run builder (Run acquisition + deterministic Layer 2) on Automations, the Current Layer 2 wave panel, the Layer 3 course-page pattern requests panel, and code that never showed on screen. Providers › Onboarding now explains that new providers are onboarded through the guided Adapter builder, with a button to open it. Kept: Refresh schedules (Layer 1 still uses them) and the provider registry and keys on Scrapers & fetchers. 11 edge functions retired (layer2-extract, layer2-course-fact-extract, layer3-interpret, layer2-v2-diagnostic, layer2-sync-control, layer2-config-control, layer2-acquire, layer2-batch-runner, layer2-scholarship-extract-v2, scholarship-scope-job-execute, scholarship-runtime-control): source removed and added to the deploy workflow's retired list. Old workflows and tests for these removed. No database change in this batch; the visible release is unchanged.
- Phase 3 shadow run, round 2 (Platform Admin: stronger adapter model). Database: `20261008005500` (md5-guarded: shadow settings gain round and a model override; round 2 reads with Xiaomi MiMo v2.6 Pro as the single pinned adapter model for intakes, English and tuition; same contracts, checks and retire rule; round 1 kept and reported beside it; no adapter's own model choice changed; nothing admitted). Round 1 result (e58): no field met the retire rule (agreement held; the single Qwen3 30B model found fewer values than the Layer 3 ladder).

## 0.1.148 — 8 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.221** (Storage & retention: Unreferenced evidence purge, Platform Admin only, re-checked per batch).
- Database: `20261008001200` (file queue, skip log, category, estimate, worker handshake; applied through the connector) and `20261008001300` (run category widened; background worker purges in batches of 500; pasted in the SQL editor). Worker coverage-sweep v0.17.17 (retention_files removes files from the bucket each file names).
- Database: `20261008001400` (Unreferenced evidence estimate counts each file once and only files no kept record uses; the first purge removed 2,280 records and 541 MB against an estimate of 1,686 MB).
- Database: `20261008001500` (Rule 4: adapter fields with low agreement admitted daily, page wins; Canadian fees and the hold list excepted; schedule `l4-rule-low-agreement` 03:37 UTC) and `20261008001600` (new scheduled jobs listed by layer).
- Database: `20261008001700` (Rule 5: where the held value is the Layer 3 model's reading and the adapter's patterns read differently, the adapter reading replaces it in the 10-minute adapter-overwrite job, no review).
- Database: `20261008001800` (Rule 6 measurement: courses bound to a page named for another course, 140 listed). Worker coverage-sweep v0.17.18 (mode page_codes reads stored pages for CRICOS-shaped codes).
- Database: `20261008001900` (Rule 6: 71 courses whose page is named for another course and lacks their CRICOS code unbound, blocked from rebinding to that page, page values withdrawn and sent back to page finding; 15 hand-chosen pages and 54 with the code kept).
- Phase 2: `20261008002000` (CRICOS register adapter stored, switched off; side-by-side replay of the last three register archives with today's Layer 1 code) and `20261008002100` (register files never purged as unreferenced evidence). Worker coverage-sweep v0.17.19 (mode register_replay).
- `20261008002200` and worker v0.17.20: the replay reads 4,000 records a call (a whole archive in one call hit the edge resource limit).
- `20261008002300`: schedule `register-replay` drives the replay one slice a minute and stops itself when done.
- `20261008002400`: the job-log purge cuts off at 7 days before the run started, so it can finish (it previously kept finding newly aged records).
- `20261008002500`: the course-directory purge selects its batch by (provider_id, url); the first run failed on a missing id column and removed nothing.
- `20261008002600`: replay comparison converts durations and fees only when they are numbers. Phase 2 replay result: all three CRICOS archives identical under the adapter and today's Layer 1 code; the newest matches Layer 1's recorded fingerprints for all 25,540 courses.

## 0.1.147 — 8 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.220** (Rule 2: the provider's own course page fee with captured evidence is used over the CRICOS registered fee, whatever year it names; no review raised).
- Database: `20261008000900` (`security.course_fee_used_v1` and `admin_fee_rules_report` replaced behind md5 guards; `security.l4_shared_hosts_v1`, `security.fee_evidence_own_site_v1`). No stored fee written.
- Database: `20261008001000` (Rule 3: a provider page fee with no year whose evidence was captured this year is aligned to this year without review; daily at 03:27 UTC as `l4-rule-fee-year-align`; first run aligned 144 fees and closed their 144 Layer 4 items; 71 held where the course already has a different fee for this year), and `20261008001100` (those conflicts: newest evidence wins, the other fee superseded; 59 year-less readings won, 12 dated fees kept; no review items left).

## 0.1.146 — 8 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.219** (Platform settings › Storage & retention, Platform Admin only: size, rule, preview and purge per category, background batches, run log).
- Database: `20261008000400` (values from third-party course directories to Layer 4 review: 39 intake, 13 English, 160 course-page items), `20261008000500` (retention runs, estimates, `admin_retention`), `20261008000600` (estimates and worker), `20261008000700` (schedule `retention-worker`). Worker coverage-sweep v0.17.16 (mode retention_files removes screenshots through Storage).
- v2.15.79 remains the accepted recovery release.

## 0.1.145 — 8 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.218** (adapter builder: 6 spread samples, Use as sample on any course page (up to 10), the proposal reads every sample and lists attributes not found per sample; Platform Admin model choice per adapter from qualified intake models).
- Database: `20261008000100` (per-adapter model table and builder actions model and add_sample; 6 samples spread across course types), `20261008000200` (Use as sample by page address; samples setting 6), `20261008000300` (stored pages listed for picking). Worker coverage-sweep v0.17.15 (keeps captured pages when a sample is added; proposal reads all samples).
- v2.15.79 remains the accepted recovery release.

## 0.1.144 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.217** (code split: 41 page-only screens load on demand; React, Supabase and icon libraries in separate long-cached files; first load about 0.93 MB instead of 1.71 MB (257 kB instead of 461 kB compressed); a stale screen file after a deploy reloads the page once).
- No database change.
- v2.15.79 remains the accepted recovery release.

## 0.1.143 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.216** (Layer 2 › Adapters is visible again to Pipeline Operators, read only, as the server allows; v2.15.211 had raised it to PIM Admin by mistake. Seven contract specs that checked code from screens redesigned since late September were rewritten to the current screens, keeping their intent).
- No database change.
- v2.15.79 remains the accepted recovery release.

## 0.1.142 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.215** (guided adapter build in Layer 2 › Adapter builder: six buttoned steps run by the Platform Admin (find pages, capture samples, model proposal, save in testing and apply, qualify, admit the fields ready to admit); an Adapter column on the Providers list for Platform Admins that opens the builder with the provider loaded, or Create adapter).
- Database: `20261007001900` (builder AI allowance US$1.50 and 60 proposals a day) and `20261007001901` (`admin_adapter_autobuild` states, read by the Providers-list column). No scheduled build: each step uses the existing functions and their own checks.
- v2.15.79 remains the accepted recovery release.

## 0.1.141 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.214** (retired Layer 2 screens `layer2-operations-entry.jsx` and `EnrichmentOperations.jsx` deleted; their contract checks removed or rewritten; Adapter builder opens the visual builder in step 4 and uses only shared colour tokens; a mocked browser check of the builder was added).
- No database change.
- v2.15.79 remains the accepted recovery release.

## 0.1.140 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.213** (operator screens cleaned up: raw JSON settings under Advanced (Platform Admin), Adapters list first, Firecrawl credits shown once on Models & services, Environment & integrations links renamed Settings, two unused ranking scripts removed).
- No database change.
- v2.15.79 remains the accepted recovery release.

## 0.1.139 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.212** (role guides aligned with server permission checks; Your role section in the Platform guide; Automations wording).
- No database change.
- v2.15.79 remains the accepted recovery release.

## 0.1.138 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.211** (Layer 2 › Adapter builder: provider, basics, central pages, recognise attributes, validate and admit, on one screen).
- Database: migration 20261007001600 (`public.admin_adapter_builder_basics`, read only, rank 5; `admin_provider_central_page` also accepts `fee_schedule`, patched behind an md5 guard).
- v2.15.79 remains the accepted recovery release.

## 0.1.137 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.210** (Coverage › Attributes opens with a per-field 80% target panel for intakes, English and fees, split by who supplied the value).
- Database: migrations 1880 to 1884 (`pipeline.course_field_source` snapshot, its build, prune and hourly schedule at :55, and `course_coverage` returning `field_sources`). Read only for operators.
- v2.15.79 remains the accepted recovery release.

## 0.1.136 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.209** (the admin course blade's Scholarships context lists only the course's own provider's scholarships).
- Database: migration 1840 (`security.admin_contextual_insights` patched behind an md5 guard so study-level and field scopes count only for the scholarship's own provider). Read only.
- v2.15.79 remains the accepted recovery release.

## 0.1.135 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.208** (unscoped Canada and NZ scholarships queued for review; no links created).
- Database: migration 1830 (insert into `scholarship.course_mapping_candidates`, status needs review, for 19 Canadian and 38 NZ scholarships with no scope, against their own provider's active courses; `on conflict do nothing`).
- v2.15.79 remains the accepted recovery release.

## 0.1.134 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.207** (Canada and NZ scholarship runtime settings added, switched off).
- Database: migration 1820 (two `pipeline.scholarship_runtime_settings` rows, CA and NZ, `enabled` false, `auto_dispatch` false, publication not authorised; insert only, `on conflict do nothing`).
- v2.15.79 remains the accepted recovery release.

## 0.1.133 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.206** (course scholarship lists only include the course's own provider's scholarships; fixes Australian scholarships showing on Canadian courses).
- Database: migration 1810 (`security.scholarship_selection_for_course_impl` patched behind an md5 guard so study-level and field scopes match only the scholarship's own provider). No stored data changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.132 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.205** (suspected half-year page fees held back in the fee-rules dry run, Decision 255).
- Database: migration 1800 (`public.admin_fee_rules_report` adds `suspected_half` and `suspected_half_sample`, and excludes those rows from `would_change`; guarded by the live definition's md5). Read only; no stored fee is changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.131 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.204** (fee used: courses under a year compare against the whole-course CRICOS fee, Decision 255 correction).
- Database: migration 1790 (`public.admin_fee_rules_report` and `security.course_fee_used_v1` divide the CRICOS total by the course length only when it is a year or more). Read only; no stored fee is changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.130 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.203** (fee_used added to the Zoho, Wix and website course APIs, Decision 255; deployed Layer 2 checks rewritten for Adapters).
- Database: migration 1780 (`api.zoho_course_lookup_v1` and `api.zoho_course_search_v2` each gain an added `fee_used` key, behind md5 guards). No stored fee is changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.129 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.202** (course drawer Fees › Fee used: which fee the course uses and why, Decision 255).
- Database: migration 1770 (`security.course_fee_used_v1`, read only, and a `fee_used` key on the drawer's fee summary behind an md5 guard). No stored fee is changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.128 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.201** (Layer 2 › Adapters › Page fees against CRICOS, a read-only dry run for Decision 255).
- Database: migration 1760 (`admin_fee_rules_report`, read only). Nothing is written or changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.127 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.200** (Layer 2 Adapters lifecycle workspace, collapsed cards remembered per session, list-only Task manager; Coverage › Universities and four Layer 2 tabs retired).
- Database: migration 1750 (adapter read cycle column, admin_adapters list/detail/set_on/set_cycle, per-adapter Admit from its own latest Qualify). No adapter was switched and nothing was admitted.
- v2.15.79 remains the accepted recovery release.

## 0.1.126 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.199** (Read pages again, Firecrawl runs, adapter Apply and central pages run as tasks; old progress panels retired).
- Database: migration 1740 (four watcher task kinds; the admin_jobs.kind check constraint widened under the Platform Admin's 13:55 exception).
- v2.15.79 remains the accepted recovery release.

## 0.1.125 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.198** (Task manager shows only live tasks; finished tasks in Jobs; JobButton; old operations console retired).
- Database: migration 1730 (finished tasks written to the Jobs history, live-only Task manager read, task scope).
- v2.15.79 remains the accepted recovery release.

## 0.1.124 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.197** (Task manager: Qualify adapters and Admit the passing fields; adapter Reading options).
- Database: migrations 1700 (adapter reading options), 1710 (adapters read inactive courses), 1720 (admin jobs, dispatcher, qualifications). Worker v0.17.13.
- v2.15.79 remains the accepted recovery release.

## 0.1.123 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.196** (Read pages again shows Sending… and any error inside the panel).
- No database change
- v2.15.79 remains the accepted recovery release.

## 0.1.122 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.195** (Read pages again for many universities runs in the background).
- Migration 20261005001630 (read pages again in the background)
- v2.15.79 remains the accepted recovery release.

## 0.1.121 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.194** (Coverage › Universities: read pages again for one university or for the universities ticked).
- Migration 20261005001620 (read pages again)
- v2.15.79 remains the accepted recovery release.

## 0.1.120 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.193** (Central English rules applied again for every university, pages bound by hand admitted, online courses show Online as location).
- Migration 20261005001610; worker v0.17.10
- v2.15.79 remains the accepted recovery release.

## 0.1.119 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.192** (Coverage › Universities: hosted courses — exit and nested awards with a register check, shared pages, double degrees and pages that are gone).
- Migrations 20261005001580–20261005001600 (award links and host pages, year-aware register check with tolerances as settings, apply fix where fees are not admitted)
- v2.15.79 remains the accepted recovery release.

## 0.1.118 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.191** (Coverage › Universities: indicative whole-course fees per university, published per university).
- Migrations 20261005001560–20261005001570 (delivery from location, other requirements, whole-course fee range); worker v0.17.9
- v2.15.79 remains the accepted recovery release.

## 0.1.117 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.190** (Coverage › Universities: location, delivery and entry requirement; delivery and exit awards admitted; international view setting).
- Migrations 20261005001490–20261005001550 (delivery, international view, fees per credit, exit awards, exclusions withdraw values); worker v0.17.8
- v2.15.79 remains the accepted recovery release.

## 0.1.116 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.189** (Coverage › Universities tab and central pages).
- Database: central pages and the universities view (migrations 20261005001420 to 20261005001450).
- v2.15.79 remains the accepted recovery release.

## 0.1.115 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.188** (admission by field and course exclusions).
- Database: admission by field and course exclusions (migrations 20261005001400 and 20261005001410).
- v2.15.79 remains the accepted recovery release.

## 0.1.114 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.187** (adapter term names to months, wave 1 and 2 fixes).
- Migrations 20261005001370 and 20261005001380 (stale adapter readings cleared, refused pages sent back once and only for page-data adapters, term_months); coverage-sweep worker v0.17.3.
- v2.15.79 remains the accepted recovery release.

## 0.1.113 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.186** (visual adapter builder (screenshots, text blocks, page data, marks, pinned model proposal), international fees admitted from admitting adapters, Firecrawl search results kept in the bucket).
- Migration 20261004001340 (adapter fees, builder drafts, bucket adapter-captures, builder settings); coverage-sweep worker v0.17.0.
- v2.15.79 remains the accepted recovery release.

## 0.1.112 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.185** (admitting adapters shown collapsed with their switches, adapter readings replace held values except hand-entered ones, every target university evaluated for its next step).
- Migrations 20261004001310 (adapter readings replace held values, better pages with Firecrawl) and 20261004001320 (adapter evaluation, three settings).
- v2.15.79 remains the accepted recovery release.

## 0.1.111 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.184** (adapter Apply works through large pages within the edge time limit, unsafe adapter patterns refused).
- Migrations 20261004001290 (adapter pattern safety) and 20261004001300 (adapter apply carries on); coverage-sweep worker v0.16.2.
- v2.15.79 remains the accepted recovery release.

## 0.1.110 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.183** (university adapters read page text patterns, extra fields shown for testing, intakes admitted from the adapter's own reading only after the admit switch).
- Migration 20261004001280 (adapter patterns, pick, adapter readings marked, admission plan gate for adapter intakes and English, schedule coverage-admit-intakes); coverage-sweep worker v0.16.0.
- v2.15.79 remains the accepted recovery release.

## 0.1.109 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.182** (University adapters easy to find and the Firecrawl panel loads at once).
- Migration 20261004001270 applied and checked: the Firecrawl panel figures are kept by scheduled jobs (7 seconds down to 0.2).
- v2.15.79 remains the accepted recovery release.

## 0.1.108 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.181** (Decision 253 amended: admit from university adapters after testing, refuse archived and test sites).
- Migration 20261004001260 applied and checked. 380 pages on archived or test sites refused, 317 links, 96 English and 42 intake values from them taken out of use (logged).
- v2.15.79 remains the accepted recovery release.

## 0.1.107 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.180** (Decision 253: Firecrawl by use case for target universities, call log and support report).
- Migrations 20261004001200, 001210 and 001220 applied. coverage-sweep worker v0.14.0 deployed and checked byte for byte.
- v2.15.79 remains the accepted recovery release.

## 0.1.106 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.179** (Decision 252 steps 1-2: Serper search pass into the identity check; page addresses repaired).
- Migrations 20261004001000 and 20261004001100 applied and verified; toolset-runner v1.3.0.
- v2.15.79 remains the accepted recovery release.

## 0.1.105 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.178** (Decision 252 amended: no trial wording; Serper and ScrapingBee keys carry plan limits set in the UI; sample runs).
- Migration 20261004000900 applied and verified; worker toolset-runner replaces toolset-trial.
- v2.15.79 remains the accepted recovery release.

## 0.1.104 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.177** (Decision 252: toolsets and limits, layer notices, OpenRouter observe only, Serper and ScrapingBee trials).
- Migrations 20261004000600 to 20261004000800 applied and verified against the live project; layer3-model-routing reads its credit policy; new toolset-trial worker.
- v2.15.79 remains the accepted recovery release.

## 0.1.103 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.176** (Scholarship job times follow Melbourne daylight saving; fixed clock times removed from screens and guide).
- 20261004000500_cf247_scholarship_job_text_dst
- v2.15.79 remains the accepted recovery release.

## 0.1.102 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.175** (Course decision support retired with Course links (only reachable from that screen); the course record's scholarship cards cover it).
- none
- v2.15.79 remains the accepted recovery release.

## 0.1.101 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.174** (Scholarships: Course links tab retired with its code; list heading removed (count on the search row); Firecrawl credit cap and reserve are Layer 2 settings shown with credits used).
- 20261004000400_cf247_scholarship_firecrawl_cap_setting
- v2.15.79 remains the accepted recovery release.

## 0.1.100 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.173** (Scholarships at each layer: sources per country and their use (Layer 1), discovery and reading results with per-run limits and job switches (Layer 2), AI check by country (Layer 3), jobs after publishing (Layer 4) — Decision 251).
- 20261004000300_cf247_scholarship_layer_settings
- v2.15.79 remains the accepted recovery release.

## 0.1.99 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.172** (Scholarships module lists published scholarships only (no status pills or status filters); record lists its courses; New Zealand and Canadian university scholarships (Decision 250)).
- 20261004000100_cf247_scholarships_nz_ca
- v2.15.79 remains the accepted recovery release.

## 0.1.98 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.171** (Scholarship screens follow the mockup: list status pills and columns, record drawer with source and hand edits, publishing tiles and reasons, course scholarship cards).
- 20261003003000_cf247_scholarships_page_status; 20261003003100_cf247_scholarship_screens_to_mockup
- v2.15.79 remains the accepted recovery release.

## 0.1.97 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.170** (Platform guide reviewed for the scholarship module).
- v2.15.79 remains the accepted recovery release.

## 0.1.96 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.169** (Scholarship publishing in Layer 4; course search; clean values; course attribute with savings (Decisions 247-249)).
- Migrations 20261003002500-002800; jobs scholarship-course-attribute (15 min) and -full (06:51 AEST).
- v2.15.79 remains the accepted recovery release.

## 0.1.95 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.168** (Scholarship award tiers and nationality from wording; Zoho scholarships action (Decisions 245, 246)).
- Migrations 20261003002100–002400; jobs scholarship-nationality (hourly).
- v2.15.79 remains the accepted recovery release.

## 0.1.94 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.167** (Scholarship audience read from wording (Decision 244)).
- Migration 20261003002000 scholarship_audience_from_wording; job scholarship-audience hourly.
- v2.15.79 remains the accepted recovery release.

## 0.1.93 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.166** (Academic calendars: Start months by hand folded into the one list; calendar parser v0.2.2 reads section-row layouts (Curtin)).
- Worker coverage-sweep v0.13.5 (calendar parser provider-policy-v0.2.2); 392 stored calendar pages re-parsed, 68 proposals.
- Provider drawer edited inline in priority order; Scholarships Audience filter (migration 20261003001900) and clipped Award column; course tuition field named against the CRICOS cost.
- v2.15.79 remains the accepted recovery release.

## 0.1.92 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.165** (Academic calendars: internal and external links on each row; months set by hand win; Not an intake no longer holds a course).
- Migration 20261003001700 applied.
- v2.15.79 remains the accepted recovery release.

## 0.1.91 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.164** (Academic calendars: Intake 1 and 2 pre-filled from Trimester or Semester 1 and 2, raw value beside them).
- v2.15.79 remains the accepted recovery release.

## 0.1.90 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.163** (Academic calendars: Intake 1, 2 … columns; a later intake can be left as Not an intake).
- v2.15.79 remains the accepted recovery release.

## 0.1.89 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.162** (Academic calendars: one column per study period with the suggested month as an input; Approve applies what is shown).
- v2.15.79 remains the accepted recovery release.

## 0.1.88 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.161** (start months by hand on Layer 4 › Attributes › Academic calendars; the calendar step is live).
- Migrations 20261003001500–001520 (Decision 228 parts 2 and 3) applied.
- v2.15.79 remains the accepted recovery release.

## 0.1.87 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.160** (Settings page: every throttle, budget and page-identity proof editable in one place, by pipeline step).
- Migration 20261003001200 adds admin_pipeline_settings_read/write.
- v2.15.79 remains the accepted recovery release.

## 0.1.86 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.159** (course drawer opens on its values, each with its Change button; the foldable editor and the comparison strip are gone).
- v2.15.79 remains the accepted recovery release.

## 0.1.85 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.158** (Fee schedules open on Waiting; Academic calendars explained).
- v2.15.79 remains the accepted recovery release.

## 0.1.84 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.157** (Fee schedules, English policies and Academic calendars moved from Coverage › Attributes to a new Layer 4 Review › Attributes tab).
- v2.15.79 remains the accepted recovery release.

## 0.1.83 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.156** (Course-page search budget moved to the top of Jobs › Priority queue).
- v2.15.79 remains the accepted recovery release.

## 0.1.82 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.155** (English policies: bulk approval and one approved document per university; course-page search budget on the Priority queue screen; overnight admission rules for Australia, Canada and New Zealand, Decisions 233-236).
- Database: reference sources and website hints; Australian English by exact title; English policy flag rule; Canada and New Zealand pinned first; Canadian search by title words; Canadian field + award and New Zealand degree-name page rules; bulk policy decisions; search cap setting.
- v2.15.79 remains the accepted recovery release.

## 0.1.81 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.154** (English policies applied for 11 universities, faster policy counts, intake cascade step 2, intake check v1.3.0 contract (not qualified)).
- Database: English policy plan counts kept and refreshed every 10 minutes; group-1 English policies approved; semester month helpers; intake step 2 (Claude Haiku 4.5) switched on and quoting failures sent back once; paused v1.3.0 intake profiles.
- v2.15.79 remains the accepted recovery release.

## 0.1.80 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.153** (Decisions 226-227: quote failures re-run; English from each university's policy).
- Database: migrations 20261002182700-20261002183200 (quote-failure re-run, reading English policies and calendars, policy proposals, English plan/approval/apply, agreement gate); coverage-sweep worker v0.9.5 (parser provider-policy-v0.2.1).
- v2.15.79 remains the accepted recovery release.

## 0.1.79 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.152** (Australian tuition from CRICOS only).
- Migration 20261002182600 (applied): Australian tuition from CRICOS; provider-page tuition chased only where the regulator publishes none.
- v2.15.79 remains the accepted recovery release.

## 0.1.78 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.151** (tuition reviews settled against the page's international view).
- Migrations 20261002182400 and 182500 (applied): review pages re-read first; tuition reviews settled every 10 minutes (job layer4-tuition-settle).
- v2.15.79 remains the accepted recovery release.

## 0.1.77 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.150** (fees follow the page's domestic or international view; answered tuition reviews closed).
- Migrations 20261002182100-182300 (applied): answered tuition reviews closed, retired fee feed paused, re-extraction in each country's currency.
- v2.15.79 remains the accepted recovery release.

## 0.1.76 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.149** (Fetch an area on the course-page sweep; Websites to find; worker errors say what to do).
- Migration 20261002182000 (applied): admin_coverage_fetch_area, Websites to find, 5-minute wait for the AI tuition check, faster tuition hand-off.
- v2.15.79 remains the accepted recovery release.

## 0.1.75 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.148** (Layer 3 cascade never falls back to a switched-off model; pending cascade claims labelled).
- Migration 20261002181900 (applied): Recent results hides the placeholder profile of an unanswered cascade claim.
- v2.15.79 remains the accepted recovery release.

## 0.1.74 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.147** (old Layer 2 pipeline retired; actionable Layer 2 overview; daily progress by country; Canada admission).
- Migration 20261002181800 (applied): 7 old Layer 2 jobs paused; Canada admission rule (CAD) and discovery queue; site finder returns country and DLI.
- v2.15.79 remains the accepted recovery release.

## 0.1.73 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.146** (Decision 219: New Zealand regions and country-named state filter; bulk flagged values).
- Database: migration 20261002181700 applied to fxcwkweaxjtknorudmwp.
- v2.15.79 remains the accepted recovery release.

## 0.1.72 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.145** (Decision 218: fee periods settled automatically; Live activity names the job behind each error).
- Database: migration 20261002181600 applied to fxcwkweaxjtknorudmwp; evidence-link-index lighter.
- v2.15.79 remains the accepted recovery release.

## 0.1.71 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.144** (Decision 217: New Zealand course pages, search and tuition; fee schedules follow the country).
- Database: migrations 20261002181300 and 20261002181400 applied to fxcwkweaxjtknorudmwp; coverage-sweep v42 (reader v0.9.1).
- v2.15.79 remains the accepted recovery release.

## 0.1.70 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.143** (Decision 216: every background function signs in with one-time run passes).
- Database: migration 20261002181200 applied to fxcwkweaxjtknorudmwp; 28 edge functions redeployed from CI.
- v2.15.79 remains the accepted recovery release.

## 0.1.69 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.142** (Decision 215: evidence link indexing fixed; Live activity shows worker errors).
- Database: migrations 20261002180900, 20261002181000 and 20261002181100 applied to fxcwkweaxjtknorudmwp; edge function evidence-link-index v4.
- v2.15.79 remains the accepted recovery release.

## 0.1.68 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.141** (Live activity; scholarship discovery refill; release check fixed).
- Migrations 20261002180600-180800 (Decision 214).
- v2.15.79 remains the accepted recovery release.

## 0.1.67 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.140** (coverage by country and university; fee schedule bulk approval; course-page pattern requests retired).
- Migration 20261002180500_cf247_coverage_countries_fee_review_patterns (Decision 213).
- v2.15.79 remains the accepted recovery release.

## 0.1.66 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.139** (scholarship publishing rules: domestic only, up-to values, savings per year).
- Migration 20261002180400_cf247_scholarship_publishing_rules (Decision 212); scholarship reader v0.5.4.
- v2.15.79 remains the accepted recovery release.

## 0.1.65 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.138** (scholarship eligibility and award scope from provider pages).
- Migration 20261002180300_cf247_scholarship_criteria_and_scope (Decision 211); coverage-sweep worker v0.9.0, scholarship reader v0.5.3.
- v2.15.79 remains the accepted recovery release.

## 0.1.64 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.137** (fee schedules settle flagged fees).
- Migration 20261001180200 (fee schedule settles flagged fees) applied live; stored md5 matches the file.
- v2.15.79 remains the accepted recovery release.

## 0.1.63 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.136** (Platform guide in the menu).
- v2.15.79 remains the accepted recovery release.

## 0.1.62 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.135** (QS and THE filters by country, state and provider; ranked universities linked to providers).
- Migration 20261001180000 (ranking links and filters) applied live; stored md5 matches the file.
- v2.15.79 remains the accepted recovery release.

## 0.1.61 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.134** (fee schedules for approval; Layer 3 claim fixes).
- Migrations 20261001179000 (Layer 3 stale claim), 179100 (Layer 3 claim speed) and 179200 (fee schedule proposals) applied live; stored md5 matches each file.
- v2.15.79 remains the accepted recovery release.

## 0.1.60 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.133** (course links of every kind, who can apply, link refresh schedules, country admission rules).
- Migrations 20261001170000, 171000, 172000, 173000 and 174000 applied to fxcwkweaxjtknorudmwp; each stored statement's md5 equals its file.
- v2.15.79 remains the accepted recovery release.

## 0.1.59 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.132** (Older screens in the compact style).
- v2.15.79 remains the accepted recovery release.

## 0.1.58 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.131** (Melbourne time, plain wording, clear counts and tidy-ups).
- v2.15.79 remains the accepted recovery release.

## 0.1.57 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.130** (Edit in list for tuition, intakes, English, campuses and scholarships).
- Database (applied live): 20261001140000 (list read for tuition, intakes, English) and 20261001150000 (campus and scholarship edits with the manual lock guard).
- v2.15.79 remains the accepted recovery release.

## 0.1.56 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.129** (Layer 4 review queue tidy-up).
- v2.15.79 remains the accepted recovery release.

## 0.1.55 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.128** (Layer 2 split into Overview, Fetch an area, History and Source profiles).
- v2.15.79 remains the accepted recovery release.

## 0.1.54 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.127** (Layer 3 Work queue and Layer 2 Source profiles in the compact style).
- v2.15.79 remains the accepted recovery release.

## 0.1.53 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.126** (Fee rules, Flagged values, Send back and Layer 3 Control tidy-up).
- v2.15.79 remains the accepted recovery release.

## 0.1.52 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.125** (Dashboard: Waiting for you first).
- Database (applied live): 20261001130000 (admin_waiting_read).
- v2.15.79 remains the accepted recovery release.

## 0.1.51 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.124** (Schedules folded into Automations; Readiness by area into Attributes; Sources moved to Operations).
- v2.15.79 remains the accepted recovery release.

## 0.1.50 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.123** (Duplicate screens merged: Regulatory settings into Layer 1, Go-live checklist, flat Capacity, Layer 4 Blocks).
- v2.15.79 remains the accepted recovery release.

## 0.1.49 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.122** (One home per setting: Models & services is the only on/off place; Environment holds keys only).
- Database (applied live): 20261001120000 (switching a model on needs a passed test; adding to a cascade no longer switches a model on).
- v2.15.79 remains the accepted recovery release.

## 0.1.48 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.121** (Reference data: Reference sources control how third-party sites are used; Key dates edited in place).
- Database (applied live): 20261001110000, 20261001111000 (reference sources), 20261001112000 (key dates). Edge function: coverage-sweep reads the list.
- v2.15.79 remains the accepted recovery release.

## 0.1.47 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.120** (Courses and Providers: Edit in list — change fields in place in the list; pages no longer run off the right edge).
- Database (applied live): 20260930180000 (admin_catalogue_edit_rows).
- v2.15.79 remains the accepted recovery release.

## 0.1.46 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.119** (Parse.bot removed completely; ranking imports are file upload only).
- Database (applied live): 20260930170000 (Parse.bot provider, 2,098 routes and stored key deleted; two functions edited behind md5 guards).
- Edge functions: ranking-publisher-url-import, ranking-qs-url-import and ranking-the-url-import retired; layer2-provider-control, layer2-acquire-v2, layer2-scope-discover-scheduled and ranking-layer1-etl no longer mention Parse.bot.
- v2.15.79 remains the accepted recovery release.

## 0.1.45 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.118** (Platform settings › Models & services: on/off switch for every AI model and page-fetching service; anything off is greyed and not offered in operation screens).
- Database (applied live): 20260930160000 (admin_services_read, admin_services_control; Layer 3 Control hides steps whose model is off).
- v2.15.79 remains the accepted recovery release.

## 0.1.44 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.117** (Batch rules: approve fixed, preview in one compact panel, errors shown in place).
- Database (applied live): 20260930150000 (layer4_mass_operations accepts course_tuition run logs).
- v2.15.79 remains the accepted recovery release.

## 0.1.43 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.116** (Layer 4 › Batch rules: fee wording rules with preview, found wordings, draft → approve & run, hourly runs, pause; values entered by hand never changed).
- Database (applied live): 20260930140000 (fee_wording_rules, fee_rule_admissions, admin_fee_rules_read / admin_fee_rule_preview / admin_fee_rule_control, hourly fee-wording-rules job).
- v2.15.79 remains the accepted recovery release.

## 0.1.42 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.115** (Scholarships › Course links: one decision per scholarship, all / matching / none, with live preview, suggestion from the name, history; decisions govern the automatic sweep).
- Database (applied live): 20260930130000 to 20260930133000 (scholarship scope decisions, admin_scholarship_links_read/detail/decide, hourly scholarship-scope-apply job, sweep guard trigger).
- v2.15.79 remains the accepted recovery release.

## 0.1.41 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.114** (Edit this course / Edit this provider panels; Add course and Add provider; values entered by hand always win over automation; history of hand changes).
- Database (applied live): 20260930120000 (manual locks with guard triggers on course facts, courses and providers; manual entry source; admin_course_edit_read/edit/create, admin_provider_edit_read/edit/create; hand-entered official pages trusted by the page reader). Also 20260930110000 to 114000 (course link recipes, link search and reverse match for the top 10 universities; backend only).
- v2.15.79 remains the accepted recovery release.

## 0.1.40 — 30 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.113** (Scheduled jobs › Priority queue: pin universities, states, countries or single courses to the front, reorder, remove; current order with pages matched and waiting).
- Database (applied live): 20260930090000 and 20260930091000 (provider ranking; Layer 3 and page reading take the largest providers first; Firecrawl for their blocked pages), 20260930100000 and 20260930101000 (priority pins, course priority, admin_priority_read/search/control; claim and page reader take pinned work first).
- v2.15.79 remains the accepted recovery release.

## 0.1.39 — 30 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.112** (Provider contacts under Catalogue; new Catalogue › Reference data with Ranking imports, Key dates and Key links; Onboarding under Providers; Coverage & completeness tabs Courses, Attributes, Readiness by area).
- Database (applied live): migration 20260930070000_system_identity_auth_list_fix — NULL token columns on the system automation identity set to empty strings, so the Auth admin user list works again (Users & roles).
- v2.15.79 remains the accepted recovery release.

## 0.1.38 — 30 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.111** (Layer 3 without Sonnet: model choice per field on Layer 4 Review › Send back to AI, including models whose cascade step is off).
- Live changes: Claude Sonnet 4.6 switched off in the intake and English cascades (logged admin control); intake and English routes every minute, 40 pages, 8 in parallel.
- Database (applied live): 20260930060000 (four cheaper intake candidates; none met the 80%-right, zero-wrong bar on the frozen holdout), 20260930061000 (pinned model from Layer 4: handoff column, claim and completion edited in place behind checksums, send_back model choice).
- Edge function layer3-model-routing: cascade v1.1.0 (a pinned page goes to its named model only).
- v2.15.79 remains the accepted recovery release.

## 0.1.37 — 30 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.110** (UI control sweep: Scheduled jobs > Automations for all 58 scheduled jobs with pause or resume per job or area, run now, frequency and batch size; Layer 4 Review > Send back to AI and a Send back to AI button on each Layer 3 task; Scholarships > Publishing with publish batch, hold and release).
- Database (applied live): migrations 20260930050000–20260930052000 — pipeline.automation_catalogue, pipeline.admin_control_events, public.admin_automations_read and public.admin_automation_control, public.admin_requeue_read and public.admin_requeue, public.admin_scholarship_publishing_read and public.admin_scholarship_publishing (reads rank >= 3, changes Platform Admin; three upkeep jobs top admin only); reason groups without amounts and failed counts that exclude released work (checksum-guarded).
- v2.15.79 remains the accepted recovery release.

## 0.1.36 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.109** (Layer 4 Review tabs: Review queue and Flagged values; operators confirm, edit or remove tuition recorded as per year when the page states no period).
- Database (applied live): migrations 20260930040000–20260930043000 — tuition per-year rule at admission with flags (pipeline.data_flags), public.admin_data_flags_read and public.admin_data_flag_resolve (rank >= 4 to change), period-word and reject-term exclusions, English daily limit US$10.
- v2.15.79 remains the accepted recovery release.

## 0.1.35 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.108** (Layer 3 control: Control, Models and Work queue tabs; per-task run or pause, daily limit and the model cascade with reorder, switch on or off, add qualified model and remove; logged changes).
- Database (applied live): migration 20260930030000_cf247_l3_control_and_requeue — public.admin_layer3_control_read and public.admin_layer3_control (Platform Admin); parked Layer 3 and Layer 4 work returned to Layer 3.
- v2.15.79 remains the accepted recovery release.

## 0.1.34 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.107** (admin simplification: five-section menu with old links redirected, one standard page layout in the shared kit, Coverage & completeness inside the app shell, new Platform health page and top-bar status dot, Layer 3 AI validation tabs, sources side by side on scholarship and course detail, Environment & integrations overview).
- Database (applied live): migration 20260930000000_cf247_admin_ui_reads — new read-only public.admin_layer3_operations and public.admin_source_comparison (with security-definer implementations); no existing function replaced.
- Removed src/layer2-navigation-restore.js (menu reordering by page scripting); the menu now comes from src/nav-map.js.
- v2.15.79 remains the accepted recovery release.

## 0.1.33 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.106** (B2 UI uniformity release with R12: one token set, one component kit, en-AU formats, "Layer N" wording; completeness states and the course completeness score on Course coverage).
- Database (applied live): migration 20260929190000_cf247_coverage_completeness_states — new helper security.coverage_completeness_state; checksum-guarded replacement of security.admin_course_coverage_read adding completeness states, the completeness score and a completeness-state course list (existing keys unchanged).
- Removed unreachable source files (legacy src/main.jsx and its stylesheets, and unmounted entry scripts).
- v2.15.79 remains the accepted recovery release.

## 0.1.32 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.105** (University group filter on Courses and Providers; university group shown on provider detail).
- Database (applied live): migration 20260929171000_cf247_admin_university_group_filter — checksum-guarded patches of the admin course and provider page functions, the catalogue filter options (new kind university_group) and provider detail; new helper security.university_group_provider_ids.
- v2.15.79 remains the accepted recovery release.

## 0.1.31 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.104** (complete-coverage sweep, website discovery, document change checks, Layer 3 throughput).
- Database (applied live): coverage sweep tables and services (discover, bind v2 one-to-one, read, find_site), coverage states candidate/blocked/page_found from the sweep, Firecrawl budget guard counts sweep usage, provider document checks, Layer 3 profile 15,000/day; schedules coverage-discover, coverage-bind, coverage-read, coverage-find-site, provider-document-check-monthly/-weekly-q4.
- Edge functions: coverage-sweep v0.4.0 (new), fee-schedule-etl v0.8.0.
- v2.15.79 remains the accepted recovery release.

## 0.1.30 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.103** (complete-coverage statistics; UQ English requirements in Search).
- Database (applied live): pipeline.course_attribute_coverage and pipeline.course_coverage_daily, security.course_coverage_build_v1 (hourly), admin_read operations course_coverage and course_coverage_courses; UQ English Search gate; double-degree higher-component rule.
- Data Quality: new "Course coverage" view (#course-coverage).
- v2.15.79 remains the accepted recovery release.

## 0.1.29 — 28 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.102** (Decision 162 step 1: badges from stored provenance; Decisions 161 and 162 cadence; Layer 2 discovery carry-forward).
- Database (applied live): security.admin_course_field_states reads stored provenance (Layer 3 admitted work items, Layer 4 resolutions, CRICOS sources) and provider-scoped Layer 2 sources; Layer 2 discovered URLs carried forward across settings-only profile versions; UQ and RMIT course-page refresh every 90 days; RMIT refresh re-enabled.
- Course page: new states "CRICOS tuition applies" and "Not collected"; badge tooltips show what resolved each value.
- v2.15.79 remains the accepted recovery release.

## 0.1.28 — 28 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.101** (Compare datasets on by default; Decision 160 Layer 3 activation; QILT SES 2025 applied; QS parser v1.4.0).
- Database (applied live): Layer 3 safe-abstention qualification and open-item move to the qualified profile; QILT apply guard accepts a verified institution's equivalent providers; Compare course mode falls back to state-level PRISMS context.
- Edge functions: ranking-qs-official-etl v1.4.0 (deploy allow-list updated).
- Compare: datasets on by default, never disabled before a selection; course-mode labels.
- v2.15.79 remains the accepted recovery release.

## 0.1.27 — 28 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.100** (Layer 1 closure, Decision 159; R5, R6, R14, R22, R25; Decision 149 identifiers; R23/R26 evidence).
- Database (applied live): NZQA seen tracking with departures and reactivation; 30-day re-verification of register rows; active counts in run summaries; provider departures review (Layer 4); GLOBAL country for ranking runs and scheduled checks; statistics edition rules, candidates and monthly discovery (Decision 134); country-scoped register identifiers (Decision 149); Layer 2 capture reuses identical files; ranking clean-up (THE 2016–2024 applied, THE "2015" withdrawn, QS 2025 restored).
- Edge functions: layer1-operations-scheduled v1.2.1, layer1-operations-control v1.6.0, ranking-publisher-control (internal apply of validated uploads), ranking-layer1-etl v1.6.1, qilt-au-etl v0.3.0, prisms-au-etl v0.2.0, statistics-edition-discovery v1.0.0 (new); allow-list updated.
- Layer 1 card: QILT family with survey tabs; new editions with Apply. Layer 4: Provider departures tab.
- v2.15.79 remains the accepted recovery release.

## 0.1.26 — 28 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.99** (Package 10: Decision 155 steps 2, 5, 6 and 7; R18–R21).
- Database (applied live): per-provider discovery links (evidence link index 188 MB emptied; candidates proven identical for all 648 providers); register fingerprints and run plans (change-based apply; bootstrap from the accepted file); automatic departures with a 2% hold and Platform Admin approval, reactivation and provider review list; duplicate register evidence clean-up (746 copies, 1.7 GB, sample verified byte for byte); automatic ingestion within the pass band (layer1-auto-ingest, CRICOS and NZQA).
- Edge functions: layer1-operations-control v1.5.0, layer1-au-depth v1.7.0, layer1-au-cricos-facts v1.2.0, evidence-storage-dedupe v1.0.0 (new); allow-list updated.
- Layer 1 card: register breakdown, departures and approval, automatic ingestion setting.
- v2.15.79 remains the accepted recovery release.

## 0.1.25 — 27 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.98** (Package 9b: Layer 1 background runs and live progress; Decision 155 part 1).
- Database (applied live): run lease and background driver (layer1-run-driver, every minute); automatic retry of temporary source errors (1, 2, 4, 8, 15 minutes); evidence reuse by content hash; system-queued runs; retirement of the 809 Australian courses no longer in CRICOS (audited in pipeline.layer1_course_retirements).
- Edge functions: layer1-operations-control v1.3.0, layer1-nz-live v1.2.0 (now in the repository), layer1-register-etl v1.5.0, layer1-au-depth v1.6.1; added to the deploy allow-list.
- Layer 1 card: live progress, retry and failure states, resume from the stopped item.
- Ranking family cards use the newest ingested edition and show its year in the title; newer editions without data show as pending (fixes CF-068 deployed UAT).
- v2.15.79 remains the accepted recovery release.

## 0.1.24 — 26 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.97** (Package 8: efficient, observable platform; Decisions 146 refined, 150, 152, 153).
- Platform resources and cost panel (Environment & Migration): hourly observations (size vs memory, cache hit, jobs, overlaps, acquisition and AI usage, largest tables), alerts, 30-day trends, cost model, admission lifecycle.
- Database (applied live): narrow evidence link index; Micro workload schedule; system automation identity; Layer 1 write-only-when-changed; capacity observation fix; hourly resource recorder and cost model; admission lifecycle policy (3,057 Layer 2 profiles aligned).
- v2.15.79 remains the accepted recovery release.

## 0.1.23 — 26 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.96** (Package 7, part 2: evidence-first onboarding, Decisions 146 and 147).
- Evidence link index: edge function evidence-link-index reads stored evidence (bucket "evidence") and records links; runs every minute, prioritised by providers waiting for onboarding; allow-listed in the deploy workflow (verify_jwt false, own authentication).
- Candidate ranking from the link index (security.layer2_catalogue_candidates_v1); automatic discovery job every 5 minutes within Platform Admin limits; attempts audited; submissions record origin person or automatic.
- Onboarding snapshot refreshed every 10 minutes: queue read 25.8 s to 1.2 s; discovery job 0.4 s.
- Panel: candidates with View evidence, automatic status, Qualified and Needs a person states. v2.15.79 remains the accepted recovery release.

## 0.1.22 — 26 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.95** (Package 7a: Layer 2 provider onboarding, Decision 141).
- New Layer 2 panel: provider onboarding queue (largest first, state per provider) with per-provider catalogue page submission: Check (dry run) then Validate & qualify (Pipeline Operator); three-course identity check 3 of 3 decides qualification.
- Database (already live): layer2_provider_onboarding_queue_v1, layer2_provider_catalogue_submit_v1 (audited), pipeline.layer2_provider_catalogue_submissions.
- Layer 2 automation settings (Decisions 141, 146): pipeline.layer2_auto_discovery_settings with audit; read (Curator+) and save (Platform Admin, reason required, providers in flight capped at Firecrawl concurrency); card in Scraper Config above dispatcher tuning. Automation off by default.
- Contract test cf-247-layer2-provider-onboarding (onboarding panel and automation card). v2.15.79 remains the accepted recovery release.

## 0.1.21 — 26 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.94** (Package 5, P3 screen review: Operations group).
- Decision 133 supersedes A24 (CF-CHG-20260830-048): Layer headers no longer repeat the page title (embedded Layer 1 and 2 keep a title only in pop-up mode; Layer 1 embedded region gets aria-label); slim light header style; a24 test rewritten to one title per screen; a21, layer2-operations-maturity and openLayer2 check the page title.
- Jobs (J1-J4): count columns only when present, UNSPECIFIED mode hidden, SUCCEEDED shown as Completed, compact table width; "Operational console" label removed.
- Layer 4 (L2-L4): queue scrolls in its column with a sticky decision panel; neutral Suggested reject wording; batch history loads only its summary until opened.
- Layer 3 (T1): paused notice while no model is qualified.
- A2/A3: developer eyebrow and CF build labels replaced with plain titles.
- Database (already live): provider rule fee-explanation pattern (Decision 131); one current provider tuition per course (Decision 132). v2.15.79 remains the accepted recovery release.

## 0.1.20 — 26 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.93** (P3 item 1).
- Regression fix: Jobs and Scheduled Tasks added to HIDDEN_ROUTES and a refresh-scheduling alias added, so #jobs, #scheduled-tasks and #refresh-scheduling resolve again after the v2.15.91 menu merge.
- Stale live-site test sweep (Decision 127): 430 literal UI expectations checked statically; stale ones updated to current wording (Schedule Configuration, Latest Refresh Queue, Profile routing, contact reconciliation, eligibility inference); drifting counts checked by pattern; every remaining expectation classified (database data, dynamic text, test input, or must-not-appear). v2.15.79 remains the accepted recovery release.

## 0.1.19 — 25 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.92** (Package 3).
- Deterministic provider-rule admission (Decisions 106, 124): security.provider_rule_admit_v1 with proof and apply modes, pipeline.provider_rule_admissions audit, review items marked superseded; scheduled every 15 minutes. First run admitted 160 UQ items (89 courses).
- Layer 3 status (Decision 125): enqueue runs; AI dispatch and admission stay paused until a model passes two clean runs.
- Administration: layer2-navigation-restore.js no longer injects Layer 1-4 buttons into the Administration tab row (Decision 116); cf-142-143 contract now asserts it does not.
- Notes include Packages 2b-2d (visible-text quotes, year selectors, fair benchmark, shared OpenRouter key). v2.15.79 remains the accepted recovery release.

## 0.1.18 — 25 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.91** (Package 2).
- Menu: Jobs and Scheduled Tasks merged into "Jobs & Schedules" (tabs); single pages kept as routes; test helper clickPrimaryNav maps the old labels to the tabs.
- Provider fee profiles: pipeline.provider_fee_profiles, security.apply_provider_fee_profiles_v1 (every 5 minutes), first rule uq-program-page-indicative-annual-v1; targets stamped basis_source provider_fee_rule:<code>.
- Layer 3 (binding change, requires re-qualification): validator accepts "annual" where an approved provider rule set "indicative_annual" (provider_rule_basis flag); interpreter records the rule's basis; benchmark case production_provider_rule_indicative_annual; manifest regenerated.
- P5a: pipeline.evidence_acquisition_provenance_v1 (tool, adapter, attempt per Evidence item).
- Scheduled Tasks: Layer 1-3 shortcut row removed; replay-safety sentence restored. Dashboard "Open Review Queue" relabelled "Open Layer 4".
- Stale tests fixed: cf-092 (terminalJob, menu), m2-5-platform-maturity-admin (Open PIM, version pin), admin-navigation order. v2.15.79 remains the accepted recovery release.

## 0.1.17 — 25 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.90** (Package 1: queue relief, Jobs simplification, release history).
- Layer 3: shared quoteComparable / evidenceQuotePresent in cf247-tuition-validation.ts (visible-text comparison: link targets, JSON escapes and formatting removed on both sides); used by layer3-work-interpret and the tuition benchmark; new production-shaped benchmark case production_markdown_link_annual; binding manifest regenerated (validator_source_sha256 9667690c...). Requires deploy and re-qualification before it runs.
- Layer 4: Send back to Layer 3 re-queues the tuition work item (trigger on layer4_decisions); gated "Send back" suggestion; official course link suggestion rules.
- Jobs: MiniCounts shows only recorded, non-zero counts.
- Release history: scripts/build-release-history.mjs (prebuild) generates public/release-history.json from legacy history, docs/release-notes and the manifest; public/release-history.html; the release overlay fills in missing releases and links to the history.
- .github/workflows/deploy-edge-functions.yml: guarded manual deployment. v2.15.79 remains the accepted recovery release.

## 0.1.16 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.89**: Layer 4 decision forms for official course links and scholarship scope.
- Backend: security.layer4_course_link_apply_impl records reviewer links in catalogue.course_links (https only; search, social and listing sites refused) and refreshes search; security.layer4_scholarship_scope_close_impl allows Mark as done only when no candidate courses need review; decisions routed by category; desk read adds per-category can_approve (never empty), scope_pending and provider_domain.
- New source "Layer 4 human review" (source_type layer4_human_review), approved for official_course_url in search (programme owner decision 24 Sep 2026, option A).
- Stale tests: cf-205, cf-208 and cf-142-143 updated to current names and the release-manifest authority; m245-release-currentness-ranking-fix-contract and m245-release-dialog-history-contract retired (superseded by m245-release-history-v21575-persistence-contract). v2.15.79 remains the accepted recovery release.

## 0.1.15 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.88**: Layer 4 team and forecast (L4-D: public.layer4_team_forecast_v1, read-only; managers rank 5+ see everyone, others their own row), plus Layer 4 task chips show waiting counts; tuition items without a proposed fee keep Edit and approve (main action).
- Notes include backend fixes merged without a version change: PERF-5 provider rankings index path (course detail timeouts) and the scoped search refresh WHERE clause required by pg_safeupdate for app-path approvals. v2.15.79 remains the accepted recovery release.

## 0.1.14 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.87**: Layer 4 approvals fixed.
- security.layer4_tuition_apply_impl: tuition Approve / Edit and approve record catalogue.course_fees with the Layer 3 admission key convention and refresh the course in search; strict value checks. layer4_review_decide_impl routes tuition decisions to it (previously refused as "field is not enabled for scalar Layer 4 editing").
- Desk read: approve suggestion and can_approve require a proposed fee already marked per year.
- Layer 4 screen: edit form carries its own note (no pop-up), errors shown in the panel, main actions hidden while editing. Floating OpenRouter key launcher removed from the shell. v2.15.79 remains the accepted recovery release.

## 0.1.13 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.86**: Layer 4 team working (L4-B).
- Claims: pipeline.layer4_review_items.claimed_at; public.layer4_claim_v1 (claim on open, 30-minute idle lapse, release); desk read adds claim fields; batch decisions refuse items actively claimed by another reviewer.
- Layer 4 screen: claim on open, "In review" marking with reviewer, All / Mine / Unassigned filter (remembered), keyboard keys R/A/E/N, tuition Edit and approve form, scholarship tools collapsed in Batches. v2.15.79 remains the accepted recovery release.

## 0.1.12 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.85**: Layer 4 batches (L4-C).
- New reads/actions: public.layer4_review_batches_v1 (groups by task and rule-based suggestion) and public.layer4_batch_decide_v1 (Pipeline Operator+, 2-100 previewed items of one kind, typed confirmation, no bulk edit, each item decided through layer4_review_decide_impl, batch logged as review_batch, all or nothing). pipeline.layer4_mass_operations accepts target_kind review_batch.
- Desk read: scholarship scope items named, plain reason, can_approve flag.
- Layer 4 screen: Review one by one / Batches switch (remembered); batch preview with untick, reason and confirmation; scholarship scope tools embedded in the Batches view. The mass-operations script no longer self-mounts via MutationObserver. v2.15.79 remains the accepted recovery release.

## 0.1.11 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.84**: the Layer 4 mass-operations panel mounts below the review desk and is collapsed by default (heading and count cards visible; "Open batch work" reveals the cohorts). Interim step before L4-C folds it into a Batches tab. v2.15.79 remains the accepted recovery release.

## 0.1.10 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.83**: Layer 4 review desk (L4-A).
- New read public.layer4_review_desk_v1 (additive; the existing queue is unchanged): course and provider names, plain task label, age, plain reason, recorded value, AI suggestion as text, cleaned page quote, links and web search, rule-based suggestion, queue summary; raw values under technical.
- Layer 4 screen: queue plus one decision panel, suggestion-led primary action, pre-filled decision note, More menu, collapsed technical detail, remembered status and task filters, next item after each decision. Provider-contact reconciliation actions unchanged.
- PERF-4 (no screen change of its own): Evidence filter options served from a background snapshot. v2.15.79 remains the accepted recovery release.
- m2-3-intelligence-deployed: stale placeholder assertion replaced with a Status filter check.

## 0.1.9 — 23 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.82**: Layer 4 review clarity and remembered filters (UI-5 batch 1), shared UI kit (UI-2), and the PERF-2 scoped search refresh fix.
- Layer 4: plain-English reason on every item, remembered status/field filters per reviewer with reset, plain status labels plus "All statuses", summarised automatic checks with technical detail behind a disclosure, queue limit raised from 100 to 250.
- Shared UI kit src/ui-kit.jsx: common components and one Pager (three copies removed, each screen keeps its look); useRememberedState generalises the Catalogue's saved state with the same storage key.
- PERF-2 (no screen change): admission refreshes only the courses it changes. v2.15.79 remains the accepted recovery release.

## 0.1.8 — 23 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.81** (PERF-1): Dashboard and layer-status summaries are pre-calculated every 2 minutes by a background job and served from a snapshot, with a live fallback if the snapshot is over 10 minutes old.
- Fixed intermittent Dashboard HTTP 500s caused by summary reads exceeding the 8-second statement limit.
- Open reviews and recent review activity now use Layer 4 review items instead of the retired, empty review queue.
- The Dashboard shows when its figures were last updated. v2.15.79 remains the accepted recovery release.

## 0.1.7 — 23 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.80**: first automated Layer 3 tuition admission, plain-English Layer 4 reasons and navigation clean-up (CF-247).
- Layer 3 validates Layer 2 tuition candidates on a schedule; confirmed fees are admitted to the catalogue, refresh the consumer projection and appear in search and the website API. The first run admitted fees with no wrong admissions.
- Added governed Layer 3 profile activation and pause (administrator only, reason required, append-only audit) and live Layer 3 queue status.
- Layer 4 reasons are plain English; admission holds now open a Layer 4 review; validated fees no longer open one.
- Navigation: Quality & Insights group; Review Queue retired with its address redirected to Layer 4; Dashboard review links fixed.
- Website API adds course and scholarship search. v2.15.79 remains the accepted recovery release until v2.15.80 is accepted.

## 0.1.6 — 14 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.79** for governed dispatcher tuning and recent-run decision metrics.
- Added Administration → Scraper Config dispatcher controls for batch size, run concurrency, stale recovery and paid-attempt limits while keeping vendor concurrency/rate/timeout/quota separate.
- Added sanitized comparable-run metrics for throughput, acquisition/extraction latency, retries, Evidence, field resolution and Layer 2/Layer 3/blocked outcomes, plus provider 24-hour performance.
- Added auditable tuning history with actor-bound governance reason and before/after policy; in-flight batches retain immutable policy snapshots.
- Retained the PR #84 transport safety cap of four ordinary items per invocation and two for scraper-first, with no change to Layer 1 identity, Layer 3 Evidence/model gating, Layer 4 authority or Search/Publication boundaries.

## 0.1.5 — 11 Sep 2026

- Published visible PIM Admin release **v2.15.78** for the accepted CF-093 governed Scheduled Tasks target-builder slice.
- Added server-authorised AU Course Facts Country/State/University preview and acquisition-only dispatch with exact-target preview receipts, profile/policy qualification and cross-operator idempotency.
- Retained v2.15.77 and earlier release history; generic Layer 3/Layer 4 orchestration, Evidence reprocessing and recurring scope construction remain separately gated.
- Reconciled the deployed-ranking UAT currentness assertion so it compares the deployed version against the maintained release-currentness source instead of the historical v2.15.74 literal.

## 0.1.4 — 11 Sep 2026

- Published visible PIM Admin release **v2.15.77** after CF-093 functional merge/deployed acceptance; retained v2.15.76 as canonical prior release history and left the separate target-builder/processing-mode/run-preview scope explicitly open.
- Began CF-093 Scheduled Workflow Orchestrator on top of the accepted v2.15.76 scheduler baseline.
- Added human-readable scheduled-task/source labels while retaining policy/source/profile UUIDs as secondary technical identifiers.
- Added task search across dataset, country, target, creator, owner and technical identifiers.
- Added per-user browser-local column visibility and ordering preferences with reset-to-default controls; UI preference state remains separate from governed execution policy.
- Added durable creator/action identity snapshots so historical scheduler attribution remains intelligible after a user is disabled or removed; browser task reads expose display attribution, not stored email snapshots.
- Added creator/owner status semantics for active, former, unassigned and system/legacy schedules without manufacturing a human creator for historical/system-created policies.
- Fixed Codex review findings so scheduler search treats `%` and `_` as literal operator text, profile identity stays visible when a source is also present, successful on-demand runs immediately refresh queue/Jobs panels, and independent supporting-read failures are surfaced without blocking policy search.
- Added request-generation sequencing to independent queue/context/Jobs panel refreshes so an older overlapping refresh cannot overwrite newer operational state.
- Aligned scheduler search with the humanised dataset labels presented by the UI, so values such as `course_facts` are searchable as `Course Facts` while preserving literal wildcard handling.
- Reconciled CF-093 migration history to deployed Pilot truth by retaining already-applied `20260910213556` and `20260910215546` identities and removing the duplicate later entity-label migration; no `--include-all` deployment bypass is used.
- Fixed the Codex-identified stale-search race by sequencing scheduler loads so superseded responses cannot replace newer policy/search results or clear/set busy/error state.
- Preserved rank-gated SECURITY INVOKER browser wrappers, exact bounded execution, Layer 3 Evidence/profile governance, Jobs/Evidence lineage and existing CF-092 schedule/run semantics.

## 0.1.3 — 10 Sep 2026

- Published visible PIM Admin release **v2.15.76** for the accepted Scheduled Tasks configuration and governed run-control change, while retaining v2.15.75 in canonical release history.
- Added a primary Scheduled Tasks workspace immediately before Evidence, with operator-friendly schedule columns, schedule editing, paged policy visibility, and direct Jobs/Evidence follow-through; removed the duplicate Scheduling entry from Administration.
- Added narrow authenticated scheduler action contracts. Public wrappers remain SECURITY INVOKER and delegate to independently rank-gated non-exposed security bridges.
- Direct Run on demand is limited to exact bounded Layer 1–2 policies and queues a `manual_governed` refresh request without changing recurring cadence or next-run time, while Layer 3 remains Evidence/profile/model-governed through its native workspace.
- Added durable scheduler action audit events recording operator, governance reason, before/after state, Change Control and associated refresh request; schedule edits also use optimistic concurrency to reject stale policy snapshots.
- Corrected whole-day PostgreSQL interval handling and browser-local `datetime-local` formatting, enforced cadence bounds, surfaced governed Jobs-read failures and avoided showing non-terminal jobs as completed.
- Browser Job reads remain on `public.admin_read`; historical Jobs are never replayed/reset by Scheduled Tasks.
- Reconciled canonical navigation UAT so acceptance follows the primary Scheduled Tasks route, current Layer 2 labels and no longer references the removed Administration Scheduling tab.

## 0.1.2 — 10 Sep 2026

- Preserved PIM Admin v2.15.75 inside the maintained `RELEASES` history rather than relying on the temporary currentness overlay.
- Synchronized the canonical `VERSION`, `UI_VERSION`, and HTML title at v2.15.75 so the Admin shell, release pill and retained release history report the same release.
- Added a regression contract for release-history persistence and cross-surface version synchronization.

## 0.1.1 — 10 Sep 2026

- Published PIM Admin v2.15.75 release-currentness metadata for the QS ranking corrective recovery.
- Added the QS ranking duplicate-edition cleanup and 2026/2027 acquisition correction to the release-notes pill under **Bug / UI fixes**.
- Recorded RLS remediation as pending security task #60 rather than changing access controls in the ranking bug-fix release.
