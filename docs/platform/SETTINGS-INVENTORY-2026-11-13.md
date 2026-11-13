# Settings inventory, 13 November 2026

Read-only inventory of every row of `pipeline.platform_toolset_settings` on the live project, asked for by the Platform Admin (13 Nov 2026 19:23): which settings are still read, which belong on Models & services, and which nothing reads. **Nothing is deleted, hidden or marked retiring by this document or by the change it ships with.** The lists below are for the Platform Admin to decide on.

## How it was measured

- Live read 13 Nov 2026 about 19:40 AEDT: 1,414 settings in 7 toolsets.
- A key counts as read when its quoted name appears in a live function body (`pg_proc.prosrc`), in a scheduled job command (`cron.job`), in the worker (`supabase/functions`) or in the admin app (`src/`).
- A key that is not named in full is still counted as read when live code builds it from parts (for example `'guard_' || lane`, `'har.' || case || '.max_attempts'`) or when a row of `pipeline.ops_remedies` or `pipeline.work_recovery_policies` names it.
- Limits of the method: a match in the worker or `src/` is a plain text match, so a short key (`find_results`, `render_js`) can match by accident; a function that reads a key may itself no longer be called. Section 4 lists the cases where that matters.

## 1. Summary

| Class | Settings | Meaning |
|---|---:|---|
| in_use | 1322 | read by live code, a job, the worker or the admin app |
| ai (moves to Models & services) | 88 | about an AI model, prompt, cap, switch or the OpenRouter credit; marked `home = models_services` by migration 20261113380000 and returned by `admin_ai_overview_v1` under its service |
| not_read_anywhere | 4 | nothing reads it: retire candidate |


## 2. Not read anywhere (retire candidates)

| Toolset | Key | Section | Label | Last change | Note |
|---|---|---|---|---|---|
| pipeline | `api.v2_r23_r24_approved` | Website API | Website API v2 R23/R24 consumer change: approved | 2026-11-09 | An approval record read once by migration 20261109160000; keep as the record or retire with the Platform Admin's word |
| pipeline | `batch.evidence_purge_check` | Storage & retention | Evidence checked per run (removal of replaced snapshots) | 2026-10-18 | Its job (evidence-purge-prepare) no longer passes it; the purge of 19 Oct 2026 is done |
| pipeline | `entry.course_read_providers` | Entry requirements | Course entry requirements: providers read | 2026-10-29 | used_by names two functions that no longer read it |
| pipeline | `progress.keep_observations_days` | First-run verification and progress | Progress contract: readings kept for trends | 2026-11-03 | used_by names security.self_sustainability_v1, which does not read it |

## 3. Moves to Models & services (ai)

Grouped as the new page will show them. Saving stays with the existing audited write `public.admin_toolsets_write('setting', {toolset, key, value, reason})`.


**adapter_builder** (6)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| firecrawl | `builder_ai_daily_usd` | AI allowance a day | 5 | 1 function(s) |
| firecrawl | `builder_model` | Model that proposes adapters | "qwen/qwen3-30b-a3b-instruct-2507" | 4 function(s); src |
| firecrawl | `builder_model_profile` | Its Models and services profile | "openrouter-intake-l3c-qwen3-30b-a3b-2507-v1" | 2 function(s) |
| firecrawl | `builder_proposals_per_day` | Proposals a day | 1000 | 1 function(s) |
| pipeline | `reading.answer_tokens.adapter_proposal` | AI answer length: adapter proposal | 4000 | worker |
| pipeline | `reading.answer_tokens.adapter_proposal_retry` | AI answer length: adapter proposal asked again | 8000 | worker |

**calendar_reading** (3)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `reading.calendar_answer_tokens` | Calendar reader: AI answer length | 4000 | worker |
| pipeline | `reading.calendar_max_slices` | Calendar reader: most slices a document | 4 | worker |
| pipeline | `reading.calendar_slice_chars` | Calendar reader: characters an AI call reads | 24000 | worker |

**central_english_policy** (1)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `reading.answer_tokens.central_page` | AI answer length: central pages | 1500 | worker |

**course_description** (2)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `enrich.course_text_items_per_day` | Course description and deadline: standing items a day | 8000 | 8 function(s) |
| pipeline | `reading.answer_tokens.course_text` | AI answer length: course description and deadline | 1500 | worker |

**course_entry_requirements** (8)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `enrich.course_entry_max_slices` | Course entry requirements: slices a page | 19 | worker |
| pipeline | `enrich.course_entry_max_tokens` | Course entry requirements: answer length | 8000 | worker |
| pipeline | `enrich.course_entry_quote_chars` | Course entry requirements: longest quote kept | 300 | worker |
| pipeline | `enrich.course_entry_slice_chars` | Course entry requirements: characters a slice | 12000 | worker |
| pipeline | `enrich.course_entry_slice_concurrency` | Course entry requirements: slices read at once | 4 | worker |
| pipeline | `enrich.course_entry_slice_overlap_chars` | Course entry requirements: overlap between slices | 600 | worker |
| pipeline | `entry.course_page_chars` | Course entry requirements: page text read | 205000 | 1 function(s); worker |
| pipeline | `entry.course_read_cost_usd` | Course entry requirements: estimated cost a course | 0.005 | 1 function(s) |

**course_matching** (4)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `ai_match.min_candidates` | AI page match: fewest candidates | 2 | 1 function(s) |
| pipeline | `batch.ai_match` | AI course-page matching | 80 | 2 function(s); cron command |
| pipeline | `concurrency.ai_match` | AI course-page matching: calls at once | 12 | 2 function(s); cron command |
| pipeline | `reading.answer_tokens.course_page_match` | AI answer length: course page match | 300 | worker |

**course_other_fields** (8)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `enrich.ai_calls_at_once` | Enrich fields: AI calls at once | 16 | 2 function(s) |
| pipeline | `enrich.ai_items_per_call` | Enrich fields: items in one AI call | 30 | 2 function(s) |
| pipeline | `enrich.ai_pages_at_once` | Enrich fields: AI pages at once | 12 | 1 function(s); worker |
| pipeline | `reading.answer_tokens.campus_lists` | AI answer length: campus lists | 2000 | worker |
| pipeline | `reading.answer_tokens.campus_regions` | AI answer length: campus regions | 2000 | worker |
| pipeline | `reading.answer_tokens.course_fields` | AI answer length: course page fields | 2000 | worker |
| pipeline | `reading.answer_tokens.course_titles` | AI answer length: field of study and level from titles | 2000 | worker |
| pipeline | `reading.answer_tokens.provider_address` | AI answer length: provider address | 2000 | worker |

**entry_matrices** (7)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `entry.matrix_attempts` | Entry matrices: tries a page | 3 | 6 function(s); worker |
| pipeline | `entry.matrix_enabled` | Entry matrices: reader on | 0 | 8 function(s); worker |
| pipeline | `entry.matrix_max_rows_per_page` | Entry matrices: rows a slice | 400 | 1 function(s) |
| pipeline | `entry.matrix_max_tokens` | Entry matrices: answer length | 16000 | 1 function(s); worker |
| pipeline | `entry.matrix_model` | Entry matrices: pinned model | "openai/gpt-4.1-mini" | 2 function(s); worker |
| pipeline | `entry.matrix_slice_chars` | Entry matrices: characters a slice | 8000 | 1 function(s); worker |
| pipeline | `entry.matrix_slice_concurrency` | Entry matrices: slices read at once | 6 | 1 function(s); worker |

**entry_requirements_v2_shadow** (6)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `aer.v2_shadow_budget_usd` | Entry requirements v2: shadow trial budget | 20 | 1 function(s) |
| pipeline | `aer.v2_shadow_daily_usd` | Entry requirements v2: shadow spend a day | 10 | 1 function(s) |
| pipeline | `aer.v2_shadow_on` | Entry requirements v2: shadow course-page reader | 0 | 2 function(s); worker |
| pipeline | `reading.aer_v2_concurrency` | Entry requirements v2: course pages read at once | 4 | worker |
| pipeline | `reading.aer_v2_max_tokens` | Entry requirements v2: answer limit of one course page | 6000 | worker |
| pipeline | `reading.aer_v2_page_chars` | Entry requirements v2: longest course page read | 60000 | worker |

**fee_reader** (2)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `fees.findings_in_prompt` | Fee reader: past problems given to the AI | 10 | 1 function(s) |
| pipeline | `reading.answer_tokens.fee_page` | AI answer length: fee pages | 32000 | worker |

**openrouter** (15)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| openrouter | `balance_stale_minutes` | Warn when the balance has not been read for | 30 | 1 function(s) |
| openrouter | `credit_floor_usd` | Credit floor | 0.5 | 12 function(s); src |
| openrouter | `guard_adapter_builder` | Daily guard: adapter proposals | 5 | built key: 'guard_' \|\| lane |
| openrouter | `guard_central_ai` | Daily guard: central pages with AI | 5 | built key: 'guard_' \|\| lane |
| openrouter | `guard_course_match` | Daily guard: AI course-page matching | 5 | built key: 'guard_' \|\| lane |
| openrouter | `guard_enrich_fields` | Daily guard: Enrich fields with AI | 50 | 2 function(s) |
| openrouter | `guard_entry_matrix` | Daily guard: entry matrices with AI | 20 | built key: 'guard_' \|\| lane |
| openrouter | `guard_fee_ai` | Fee reader with AI | 5 | built key: 'guard_' \|\| lane |
| openrouter | `guard_provider_description` | Daily guard: provider descriptions with AI | 1 | 3 function(s) |
| openrouter | `guard_scholarship_ai` | Daily guard: read scholarship pages with AI | 20 | 1 function(s) |
| openrouter | `low_balance_warn_usd` | Warn when the balance is below | 10 | 2 function(s); src |
| openrouter | `notice_window_hours` | Look back for refusals over | 24 | 1 function(s) |
| openrouter | `ondemand_usd_per_day` | On-demand allowance (Run now) | 10 | 1 function(s) |
| pipeline | `budgets.ai_daily_ceiling_usd` | AI spend: daily ceiling | 14 | 7 function(s) |
| pipeline | `targets.ai_credit_min_usd` | Target T2: lowest OpenRouter credit | 10 | 1 function(s) |

**ops_diagnosis** (11)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `har.ai_escalate_on` | Human-assisted recovery: one stronger-model attempt before asking a person | 0 | 5 function(s) |
| pipeline | `har.ai_escalation_model` | Human-assisted recovery: pinned escalation model | "" | 3 function(s) |
| pipeline | `har.ai_min_confidence` | Human-assisted recovery: lowest AI confidence offered as a suggestion | 0.7 | 1 function(s) |
| pipeline | `har.ai_requests_per_day` | Human-assisted recovery: stronger-model requests a day | 10 | 1 function(s) |
| pipeline | `har.ai_wait_hours` | Human-assisted recovery: longest wait for the stronger model | 6 | 1 function(s) |
| pipeline | `ops.ai_diagnosis_model` | Operations controller: pinned AI diagnosis model | "openai/gpt-4.1-mini" | 2 function(s) |
| pipeline | `ops.ai_diagnosis_on` | Operations controller: AI-assisted diagnosis | 0 | 6 function(s); cron command; worker |
| pipeline | `ops.ai_diagnosis_usd_per_day` | Operations controller: AI diagnosis spend a day | 0.5 | 1 function(s); worker |
| pipeline | `ops.ai_min_confidence` | Operations controller: confidence below which AI is asked | 0.5 | 2 function(s); worker |
| pipeline | `ops.ai_requests_per_day` | Operations controller: AI diagnoses a day | 20 | 1 function(s) |
| pipeline | `reading.answer_tokens.ops_diagnosis` | AI answer length: issue diagnosis | 800 | worker |

**provider_description** (8)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `pdesc.ai_usd_max` | Provider descriptions: AI spend ceiling (all reads) | 5 | 8 function(s) |
| pipeline | `pdesc.enabled` | Provider descriptions: reader on | 1 | 11 function(s) |
| pipeline | `pdesc.prompt_on` | Provider descriptions: use the prompt from Settings | 1 | 4 function(s) |
| pipeline | `pdesc.prompt_refused_words` | Provider descriptions: words a description never carries (prompt) | ["ranked", "ranking", "rankings", "rated", "qs", "times high | 3 function(s) |
| pipeline | `pdesc.prompt_reoffer_rules` | Provider descriptions: held answers read again for a new prompt | ["not_stated", "unsupported_sentence", "unsupported_claim",  | 1 function(s) |
| pipeline | `pdesc.prompt_support_min_share` | Provider descriptions: support of a sentence by its quotes (prompt) | 0.5 | 1 function(s) |
| pipeline | `pdesc.read_cost_floor_usd` | Provider descriptions: cost allowed for a read before it starts | 0.003 | 2 function(s) |
| pipeline | `reading.answer_tokens.provider_description` | AI answer length: provider description | 1500 | worker |

**scholarship_extraction** (7)

| Toolset | Key | Label | Value | Read by |
|---|---|---|---|---|
| pipeline | `batch.sch_ai_pick_scan` | Scholarship AI: items the picker checks at once | 60 | 1 function(s) |
| pipeline | `batch.scholarship_recheck` | Held scholarship pages re-checked per run | 12 | 1 function(s) |
| pipeline | `reading.answer_tokens.scholarship_page` | AI answer length: scholarship page | 4500 | worker |
| pipeline | `reading.answer_tokens.scholarship_recheck` | AI answer length: scholarship re-check | 800 | worker |
| pipeline | `reread.scholarship_ai_days` | Read a page with AI again after | 90 | 1 function(s) |
| pipeline | `retry.sch_ai_wait_minutes` | Scholarship AI reads waiting for credits: wait between tries | 30 | 1 function(s) |
| pipeline | `sch_ai.wait_max_days` | Scholarship AI reads waiting for credits: close after | 14 | 1 function(s) |

Not marked, for a decision: the AI evaluation settings (`ai_eval.*`, 17), `wc.ai_*`, `ops_cost.enforce_ai_loop_hold` and the scholarship discovery and reading settings that are not about a model, prompt or cap (`scholarship.*`, `reread.scholarship_*`, `retry.scholarship_*`). They mention AI or scholarships but control evaluation, recovery or page finding, so they stay on Settings unless the Platform Admin wants them moved.


## 4. Still read, but worth a decision

### 4a. Read only by functions already marked retiring or retired (12)

| Setting | Section | Label | Last change | Read only by |
|---|---|---|---|---|
| `pipeline.calendar.university_levels` | Enrichment | University courses filled from the academic calendar | 2026-10-18 | security.calendar_default_intakes_apply_v1 |
| `scrapingbee.sample_cases_per_country` | Sample runs | Cases per country | 2026-10-04 | public.admin_toolset_sample_write |
| `scrapingbee.sample_countries` | Sample runs | Countries sampled | 2026-10-04 | public.admin_search_pass_start, public.admin_toolset_sample_write, public.admin_toolset_samples_read |
| `scrapingbee.usd_per_1k_credits` | Key and plan limits | Price per 1,000 credits | 2026-10-04 | public.admin_toolset_samples_read |
| `serper.course_like_url` | Search pass | What a course page address looks like | 2026-10-04 | security.toolset_pass_backlog |
| `serper.pass_auto_continue` | Search pass | Carry on after each worker call | 2026-10-04 | public.svc_toolset_sample_continue |
| `serper.pass_cases_per_country` | Search pass | Courses per country in one pass | 2026-10-04 | public.admin_search_pass_start |
| `serper.pass_credits_per_run` | Search pass | Credits one pass may use | 2026-10-04 | public.admin_search_pass_start |
| `serper.pass_refind_unreadable` | Search pass | Look again for pages that could not be read | 2026-10-04 | security.toolset_pass_backlog |
| `serper.sample_cases_per_country` | Sample runs | Cases per country | 2026-10-04 | public.admin_toolset_sample_write |
| `serper.sample_countries` | Sample runs | Countries sampled | 2026-10-04 | public.admin_search_pass_start, public.admin_toolset_sample_write, public.admin_toolset_samples_read |
| `serper.usd_per_1k_credits` | Key and plan limits | Price per 1,000 credits | 2026-10-04 | public.admin_toolset_samples_read |

### 4b. Serper and ScrapingBee toolsets (39 settings)

Both vendors were dropped on 4 Oct 2026 (Firecrawl only) and their cards, the search pass and the sample runs are already marked retiring in the component register. Every setting of the two toolsets is a retire candidate once those screens go.

### 4c. The two model settings this change stops reading

`pipeline.entry.matrix_model` and `pipeline.ops.ai_diagnosis_model` (both `openai/gpt-4.1-mini`) are no longer read after migrations 20261113380000 and 20261113390000 (the fourth reader, `public.admin_provider_description_run_v1`, was found in round 4 and asks the route from 20261113390000); the model is chosen on Models & services. `pipeline.har.ai_escalation_model` is empty and its switch is off. All three are text settings the Settings screen cannot edit.

### 4d. Named only in the worker or the admin app (59)

No live function or job names these; the match is text in `supabase/functions` or `src/`. Most are read by the worker through `svc_worker_settings_v1`. Short keys can match by accident.

| Toolset | Key | Section | Seen in | Last change |
|---|---|---|---|---|
| firecrawl | `find_min_title_match` | Find pages | worker | 2026-10-04 |
| firecrawl | `find_results` | Find pages | worker | 2026-10-04 |
| firecrawl | `read_formats` | Read pages | worker | 2026-10-04 |
| firecrawl | `read_location` | Read pages | worker | 2026-10-04 |
| firecrawl | `read_timeout_ms` | Read pages | worker | 2026-10-04 |
| firecrawl | `read_wait_ms` | Read pages | worker | 2026-10-04 |
| firecrawl | `run_batch_per_call` | Runs | worker | 2026-10-04 |
| firecrawl | `run_concurrency` | Runs | worker | 2026-10-04 |
| pipeline | `enrich.course_description_claim_reach_min_words` | Course description and deadline | worker | 2026-11-11 |
| pipeline | `enrich.course_description_claim_reach_share` | Course description and deadline | worker | 2026-11-11 |
| pipeline | `enrich.course_description_min_quote_chars` | Course description and deadline | worker | 2026-11-03 |
| pipeline | `enrich.page_chars` | Job sizes | worker | 2026-10-14 |
| pipeline | `enrich.title_batch` | Job sizes | worker | 2026-10-14 |
| pipeline | `hygiene.retire_after_days` | Housekeeping | src | 2026-10-15 |
| pipeline | `reading.course_entry_fragment_min_chars` | Entry requirements | worker | 2026-11-08 |
| pipeline | `reading.course_quote_fragments_on` | Entry requirements | worker | 2026-11-08 |
| pipeline | `reading.entry_band_label_words` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_cell_min_levels` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_cell_min_lines` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_cell_reader_on` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_country_aliases` | Entry requirements | worker | 2026-11-08 |
| pipeline | `reading.entry_country_aliases_on` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_global_pages_on` | Entry requirements | worker | 2026-11-03 |
| pipeline | `reading.entry_global_phrases` | Entry requirements | worker | 2026-11-03 |
| pipeline | `reading.entry_global_qualifications` | Entry requirements | worker | 2026-11-03 |
| pipeline | `reading.entry_grid_headings` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_grid_reader_on` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_pdf_firecrawl_on` | Entry requirements | worker | 2026-11-12 |
| pipeline | `reading.entry_pdf_per_call` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_qualification_countries` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_quote_parts_on` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_quote_window_chars` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_range_lower_bound_on` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_subject_rows_on` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.entry_value_null_on` | Entry requirements | worker | 2026-11-11 |
| pipeline | `reading.link_search_share_on` | Course pages | worker | 2026-11-03 |
| pipeline | `reading.pages_at_once` | Job sizes | worker | 2026-10-23 |
| pipeline | `reading.provider_quote_fragments_on` | Provider descriptions | worker | 2026-11-09 |
| pipeline | `reading.sch_recovery_linked_chars` | Scholarship details | worker | 2026-11-13 |
| pipeline | `reading.sch_recovery_section_chars` | Scholarship details | worker | 2026-11-13 |
| pipeline | `scholarship.catalogue_render_wait_ms` | Scholarships | worker | 2026-11-02 |
| pipeline | `scholarship.listing_items_max` | Job sizes | worker | 2026-11-02 |
| pipeline | `scholarship.listing_pages_max` | Job sizes | worker | 2026-11-02 |
| pipeline | `scholarship.map_candidates_max` | Job sizes | worker | 2026-11-02 |
| pipeline | `scholarship.read_max` | Job sizes | worker | 2026-11-02 |
| pipeline | `scholarship.render_wait_ms` | Scholarships | worker | 2026-11-02 |
| scrapingbee | `premium_proxy` | How the service is used | worker | 2026-10-04 |
| scrapingbee | `render_js` | How the service is used | worker | 2026-10-04 |
| scrapingbee | `sample_concurrency` | Sample runs | worker | 2026-10-04 |
| scrapingbee | `sample_seconds_per_call` | Sample runs | worker | 2026-10-04 |
| scrapingbee | `title_match_min` | How the service is used | worker | 2026-10-04 |
| serper | `course_query` | How the service is used | worker | 2026-10-04 |
| serper | `course_site_filter` | How the service is used | worker | 2026-10-04 |
| serper | `directory_hosts` | How the service is used | worker | 2026-10-04 |
| serper | `provider_query` | How the service is used | worker | 2026-10-04 |
| serper | `results_per_query` | How the service is used | worker | 2026-10-04 |
| serper | `sample_concurrency` | Sample runs | worker | 2026-10-04 |
| serper | `sample_seconds_per_call` | Sample runs | worker | 2026-10-04 |
| serper | `title_match_min` | How the service is used | worker | 2026-10-04 |

## 5. Counts per section

| Toolset | Section | in_use | ai | not_read_anywhere | Total |
|---|---|---:|---:|---:|---:|
| edge_functions | Notices | 2 | 0 | 0 | 2 |
| firecrawl | Adapter builder | 3 | 4 | 0 | 7 |
| firecrawl | Adapter evaluation | 4 | 0 | 0 | 4 |
| firecrawl | Daily budget | 16 | 0 | 0 | 16 |
| firecrawl | Find pages | 14 | 0 | 0 | 14 |
| firecrawl | Notices | 1 | 0 | 0 | 1 |
| firecrawl | Read pages | 9 | 0 | 0 | 9 |
| firecrawl | Runs | 3 | 0 | 0 | 3 |
| firecrawl | Target universities | 7 | 0 | 0 | 7 |
| openrouter | Daily guards | 0 | 10 | 0 | 10 |
| openrouter | Notices | 0 | 3 | 0 | 3 |
| pipeline | AI answer limits | 0 | 14 | 0 | 14 |
| pipeline | AI evaluation | 18 | 0 | 0 | 18 |
| pipeline | Admission | 4 | 0 | 0 | 4 |
| pipeline | Admission checks | 13 | 0 | 0 | 13 |
| pipeline | Alerts | 16 | 0 | 0 | 16 |
| pipeline | Cost and yield | 22 | 0 | 0 | 22 |
| pipeline | Course catalogue | 6 | 0 | 0 | 6 |
| pipeline | Course description and deadline | 31 | 1 | 0 | 32 |
| pipeline | Course page search | 13 | 0 | 0 | 13 |
| pipeline | Course pages | 30 | 1 | 0 | 31 |
| pipeline | Coverage reconciliation | 25 | 0 | 0 | 25 |
| pipeline | Data delivery | 10 | 0 | 0 | 10 |
| pipeline | English policies | 6 | 0 | 0 | 6 |
| pipeline | Enrichment | 65 | 1 | 0 | 66 |
| pipeline | Enrichment lanes | 5 | 0 | 0 | 5 |
| pipeline | Entry requirements | 145 | 21 | 1 | 167 |
| pipeline | Field absence (D2, D3) | 3 | 0 | 0 | 3 |
| pipeline | First-run verification and progress | 24 | 0 | 1 | 25 |
| pipeline | Flags | 10 | 0 | 0 | 10 |
| pipeline | Gap queue | 7 | 0 | 0 | 7 |
| pipeline | Governed actions | 2 | 0 | 0 | 2 |
| pipeline | Health report | 9 | 0 | 0 | 9 |
| pipeline | Housekeeping | 13 | 0 | 0 | 13 |
| pipeline | Human-assisted recovery | 87 | 5 | 0 | 92 |
| pipeline | Intake dates | 35 | 3 | 0 | 38 |
| pipeline | Integration queue | 18 | 0 | 0 | 18 |
| pipeline | Job sizes | 73 | 6 | 0 | 79 |
| pipeline | Lane funnels | 12 | 0 | 0 | 12 |
| pipeline | Layer 4 | 28 | 0 | 0 | 28 |
| pipeline | Layer 4 readiness | 33 | 0 | 0 | 33 |
| pipeline | Logos | 4 | 0 | 0 | 4 |
| pipeline | Official link | 7 | 0 | 0 | 7 |
| pipeline | On demand | 1 | 0 | 0 | 1 |
| pipeline | Onboarding | 31 | 0 | 0 | 31 |
| pipeline | Operating targets | 6 | 1 | 0 | 7 |
| pipeline | Operations controller | 21 | 6 | 0 | 27 |
| pipeline | Platform upkeep | 82 | 1 | 0 | 83 |
| pipeline | Process results | 9 | 0 | 0 | 9 |
| pipeline | Provider descriptions | 65 | 7 | 0 | 72 |
| pipeline | Provider descriptions › built-in prompt only | 4 | 0 | 0 | 4 |
| pipeline | Re-read and retry | 31 | 1 | 0 | 32 |
| pipeline | Re-reads and retries | 4 | 0 | 0 | 4 |
| pipeline | Register | 7 | 0 | 0 | 7 |
| pipeline | Retention | 1 | 0 | 0 | 1 |
| pipeline | Run now | 7 | 0 | 0 | 7 |
| pipeline | Scholarship coverage recovery | 15 | 0 | 0 | 15 |
| pipeline | Scholarship details | 4 | 0 | 0 | 4 |
| pipeline | Scholarship discovery | 5 | 0 | 0 | 5 |
| pipeline | Scholarship eligibility reader | 13 | 0 | 0 | 13 |
| pipeline | Scholarship flow guard | 6 | 0 | 0 | 6 |
| pipeline | Scholarships | 29 | 3 | 0 | 32 |
| pipeline | Source proof | 20 | 0 | 0 | 20 |
| pipeline | Storage | 1 | 0 | 0 | 1 |
| pipeline | Storage & retention | 4 | 0 | 1 | 5 |
| pipeline | Waste rules | 11 | 0 | 0 | 11 |
| pipeline | Website API | 9 | 0 | 1 | 10 |
| pipeline | Work continuity | 36 | 0 | 0 | 36 |
| pipeline | Zero-yield pages | 13 | 0 | 0 | 13 |
| pipeline | Zoho API | 13 | 0 | 0 | 13 |
| scheduled_jobs | Notices | 2 | 0 | 0 | 2 |
| scrapingbee | How the service is used | 4 | 0 | 0 | 4 |
| scrapingbee | Key and plan limits | 7 | 0 | 0 | 7 |
| scrapingbee | Sample runs | 5 | 0 | 0 | 5 |
| serper | How the service is used | 6 | 0 | 0 | 6 |
| serper | Key and plan limits | 7 | 0 | 0 | 7 |
| serper | Sample runs | 5 | 0 | 0 | 5 |
| serper | Search pass | 5 | 0 | 0 | 5 |

## 6. Every setting

| Toolset | Key | Section | Class | Read by | Last change |
|---|---|---|---|---|---|
| edge_functions | `min_timeouts` | Notices | in_use | 1 function(s) | 2026-10-04 |
| edge_functions | `notice_window_hours` | Notices | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `autobuild_credits` | Adapter builder | in_use | 1 function(s) | 2026-10-07 |
| firecrawl | `autobuild_per_day` | Adapter builder | in_use | 1 function(s) | 2026-10-07 |
| firecrawl | `builder_ai_daily_usd` | Adapter builder | ai (adapter_builder) | 1 function(s) | 2026-10-07 |
| firecrawl | `builder_model` | Adapter builder | ai (adapter_builder) | 4 function(s); src | 2026-10-04 |
| firecrawl | `builder_model_profile` | Adapter builder | ai (adapter_builder) | 2 function(s) | 2026-10-04 |
| firecrawl | `builder_proposals_per_day` | Adapter builder | ai (adapter_builder) | 1 function(s) | 2026-10-13 |
| firecrawl | `builder_samples` | Adapter builder | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `central_refresh_days` | Daily budget | in_use | 3 function(s) | 2026-10-12 |
| firecrawl | `daily_budget_on` | Daily budget | in_use | 7 function(s) | 2026-10-12 |
| firecrawl | `daily_budget_total` | Daily budget | in_use | 7 function(s) | 2026-11-08 |
| firecrawl | `daily_share_central` | Daily budget | in_use | built key: 'daily_share_' \|\| … | 2026-11-12 |
| firecrawl | `daily_share_course_search` | Daily budget | in_use | 1 function(s) | 2026-11-08 |
| firecrawl | `daily_share_other` | Daily budget | in_use | 2 function(s) | 2026-11-08 |
| firecrawl | `daily_share_pdesc` | Daily budget | in_use | 1 function(s) | 2026-11-10 |
| firecrawl | `daily_share_reads` | Daily budget | in_use | 1 function(s) | 2026-11-08 |
| firecrawl | `daily_share_scholarships` | Daily budget | in_use | 3 function(s) | 2026-11-08 |
| firecrawl | `eval_field_share` | Adapter evaluation | in_use | 7 function(s) | 2026-10-04 |
| firecrawl | `eval_no_page_share` | Adapter evaluation | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `eval_unreadable_share` | Adapter evaluation | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `find_credits_per_run` | Find pages | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `find_min_title_match` | Find pages | in_use | worker | 2026-10-04 |
| firecrawl | `find_query` | Find pages | in_use | 1 function(s); worker | 2026-10-04 |
| firecrawl | `find_results` | Find pages | in_use | worker | 2026-10-04 |
| firecrawl | `find_retry_refused` | Find pages | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `low_balance_warn_units` | Notices | in_use | 2 function(s) | 2026-10-04 |
| firecrawl | `map_limit_central` | Find pages | in_use | 1 function(s); worker | 2026-10-13 |
| firecrawl | `map_limit_central_search` | Find pages | in_use | 1 function(s); worker | 2026-10-13 |
| firecrawl | `map_limit_course_site` | Find pages | in_use | 1 function(s); worker | 2026-10-13 |
| firecrawl | `map_limit_scholarships` | Find pages | in_use | 1 function(s); worker | 2026-10-13 |
| firecrawl | `ondemand_credits_per_day` | Daily budget | in_use | 1 function(s) | 2026-11-12 |
| firecrawl | `priority_floor_course_search` | Daily budget | in_use | 4 function(s) | 2026-11-08 |
| firecrawl | `qualify_agree_share` | Adapter evaluation | in_use | 6 function(s) | 2026-10-06 |
| firecrawl | `read_credits_per_run` | Read pages | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `read_formats` | Read pages | in_use | worker | 2026-10-04 |
| firecrawl | `read_location` | Read pages | in_use | worker | 2026-10-04 |
| firecrawl | `read_proxy` | Read pages | in_use | 1 function(s); worker | 2026-10-12 |
| firecrawl | `read_skip_url_pattern` | Read pages | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `read_statuses` | Read pages | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `read_timeout_ms` | Read pages | in_use | worker | 2026-10-04 |
| firecrawl | `read_url_pattern` | Read pages | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `read_wait_ms` | Read pages | in_use | worker | 2026-10-04 |
| firecrawl | `refused_host_pattern` | Target universities | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `run_auto_continue` | Runs | in_use | 1 function(s) | 2026-10-04 |
| firecrawl | `run_batch_per_call` | Runs | in_use | worker | 2026-10-04 |
| firecrawl | `run_concurrency` | Runs | in_use | worker | 2026-10-04 |
| firecrawl | `scholarship_cap_per_uni` | Daily budget | in_use | 3 function(s) | 2026-10-12 |
| firecrawl | `scholarship_min_courses` | Daily budget | in_use | 2 function(s) | 2026-10-12 |
| firecrawl | `scholarship_tier_courses` | Daily budget | in_use | 1 function(s) | 2026-11-02 |
| firecrawl | `search_results_cricos` | Find pages | in_use | 1 function(s); worker | 2026-10-13 |
| firecrawl | `search_results_register` | Find pages | in_use | 1 function(s); worker | 2026-10-13 |
| firecrawl | `search_results_scholarship_discover` | Find pages | in_use | 1 function(s); worker | 2026-10-13 |
| firecrawl | `search_results_scholarship_search` | Find pages | in_use | 1 function(s); worker | 2026-10-13 |
| firecrawl | `search_results_website` | Find pages | in_use | 1 function(s); worker | 2026-10-13 |
| firecrawl | `search_stop_after` | Daily budget | in_use | 4 function(s) | 2026-10-12 |
| firecrawl | `search_stop_window_days` | Daily budget | in_use | 2 function(s) | 2026-10-13 |
| firecrawl | `target_countries` | Target universities | in_use | 2 function(s) | 2026-10-04 |
| firecrawl | `target_exclude_pattern` | Target universities | in_use | 2 function(s) | 2026-10-04 |
| firecrawl | `target_min_courses` | Target universities | in_use | 2 function(s) | 2026-10-04 |
| firecrawl | `target_name_pattern` | Target universities | in_use | 5 function(s) | 2026-10-04 |
| firecrawl | `target_only` | Target universities | in_use | 7 function(s); worker | 2026-10-04 |
| firecrawl | `target_registers` | Target universities | in_use | 2 function(s) | 2026-10-04 |
| openrouter | `balance_stale_minutes` | Notices | ai (openrouter) | 1 function(s) | 2026-10-12 |
| openrouter | `credit_floor_usd` | Daily guards | ai (openrouter) | 12 function(s); src | 2026-11-12 |
| openrouter | `guard_adapter_builder` | Daily guards | ai (openrouter) | built key: 'guard_' \|\| lane | 2026-10-12 |
| openrouter | `guard_central_ai` | Daily guards | ai (openrouter) | built key: 'guard_' \|\| lane | 2026-10-12 |
| openrouter | `guard_course_match` | Daily guards | ai (openrouter) | built key: 'guard_' \|\| lane | 2026-10-12 |
| openrouter | `guard_enrich_fields` | Daily guards | ai (openrouter) | 2 function(s) | 2026-11-12 |
| openrouter | `guard_entry_matrix` | Daily guards | ai (openrouter) | built key: 'guard_' \|\| lane | 2026-11-12 |
| openrouter | `guard_fee_ai` | Daily guards | ai (openrouter) | built key: 'guard_' \|\| lane | 2026-10-21 |
| openrouter | `guard_provider_description` | Daily guards | ai (openrouter) | 3 function(s) | 2026-11-02 |
| openrouter | `guard_scholarship_ai` | Daily guards | ai (openrouter) | 1 function(s) | 2026-10-12 |
| openrouter | `low_balance_warn_usd` | Notices | ai (openrouter) | 2 function(s); src | 2026-10-12 |
| openrouter | `notice_window_hours` | Notices | ai (openrouter) | 1 function(s) | 2026-10-04 |
| openrouter | `ondemand_usd_per_day` | Daily guards | ai (openrouter) | 1 function(s) | 2026-11-12 |
| pipeline | `absence.coverage_fields` | Field absence (D2, D3) | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `absence.pending_recheck_hours` | Field absence (D2, D3) | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `absence.verified_min_confidence` | Field absence (D2, D3) | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `admit.fee_crosscheck_pct` | Admission checks | in_use | 2 function(s) | 2026-10-14 |
| pipeline | `admit.item_error_limit` | Admission | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `admit.refused_recheck_hours` | Admission | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `admit.remedy_cooldown_minutes` | Admission | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `admit.remedy_max_attempts` | Admission | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `aer.alerts_enabled` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `aer.baseline_eligible` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `aer.course_link_candidate_min_overlap` | Entry requirements | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `aer.course_link_candidates` | Entry requirements | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `aer.course_link_on` | Entry requirements | in_use | 3 function(s) | 2026-11-11 |
| pipeline | `aer.coverage_countries` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.discovery_campaign_batch` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.discovery_campaign_credit_cap` | Entry requirements | in_use | 5 function(s) | 2026-11-11 |
| pipeline | `aer.discovery_campaign_on` | Entry requirements | in_use | 2 function(s) | 2026-11-11 |
| pipeline | `aer.discovery_campaign_retry_hours` | Entry requirements | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `aer.discovery_spare_daily_max` | Entry requirements | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `aer.discovery_spare_margin_pct` | Entry requirements | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `aer.discovery_spare_window_hours` | Entry requirements | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `aer.e13_recover_daily_max` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.e13_recover_on` | Entry requirements | in_use | 3 function(s) | 2026-11-13 |
| pipeline | `aer.e13_recover_per_provider` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.e13_recover_providers` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.e13_recover_total_max` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.eligible_countries` | Entry requirements | in_use | 6 function(s) | 2026-11-02 |
| pipeline | `aer.entry_search_on` | Entry requirements | in_use | 1 function(s) | 2026-11-10 |
| pipeline | `aer.grid_machine_admission_on` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.machine_audit_pct` | Entry requirements | in_use | 1 function(s) | 2026-11-10 |
| pipeline | `aer.machine_daily_max` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.machine_except_on` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.machine_min_confidence` | Entry requirements | in_use | 2 function(s) | 2026-11-10 |
| pipeline | `aer.machine_min_quote_chars` | Entry requirements | in_use | 5 function(s) | 2026-11-10 |
| pipeline | `aer.machine_mode` | Entry requirements | in_use | 4 function(s) | 2026-11-11 |
| pipeline | `aer.machine_shadow_min_hours` | Entry requirements | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `aer.machine_suspended` | Entry requirements | in_use | 5 function(s) | 2026-11-10 |
| pipeline | `aer.matrix_machine_audit_pct` | Entry requirements | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `aer.matrix_machine_daily_max` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.matrix_machine_except_on` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.matrix_machine_min_confidence` | Entry requirements | in_use | 3 function(s) | 2026-11-11 |
| pipeline | `aer.matrix_machine_min_shadow` | Entry requirements | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `aer.matrix_machine_mode` | Entry requirements | in_use | 2 function(s) | 2026-11-11 |
| pipeline | `aer.matrix_route_activate_max` | Entry requirements | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `aer.not_applicable_provider_types` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `aer.outcome_register_every_minutes` | Platform upkeep | in_use | 2 function(s) | 2026-10-30 |
| pipeline | `aer.outcome_register_page_rows` | Platform upkeep | in_use | 1 function(s) | 2026-10-30 |
| pipeline | `aer.outcome_register_stale_after_minutes` | Platform upkeep | in_use | 1 function(s) | 2026-10-30 |
| pipeline | `aer.postgraduate_levels` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `aer.priority_provider_types` | Entry requirements | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `aer.regression_alert_providers` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `aer.replay_daily_max` | Entry requirements | in_use | 2 function(s) | 2026-11-12 |
| pipeline | `aer.replay_on` | Entry requirements | in_use | 2 function(s) | 2026-11-07 |
| pipeline | `aer.replay_per_provider` | Entry requirements | in_use | 2 function(s) | 2026-11-12 |
| pipeline | `aer.replay_scan` | Entry requirements | in_use | 1 function(s) | 2026-11-07 |
| pipeline | `aer.reread_recheck_hours` | Entry requirements | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-04 |
| pipeline | `aer.retry_now_error_pattern` | Entry requirements | in_use | 2 function(s) | 2026-11-12 |
| pipeline | `aer.review_packet_rows` | Entry requirements | in_use | 2 function(s) | 2026-11-04 |
| pipeline | `aer.row_limit_matrix_rows` | Entry requirements | in_use | 2 function(s) | 2026-11-04 |
| pipeline | `aer.schedule_correction_daily_max` | Entry requirements | in_use | 1 function(s) | 2026-11-13 |
| pipeline | `aer.schedule_countries` | Entry requirements | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `aer.schedule_countries_off` | Entry requirements | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `aer.schedule_daily_max` | Entry requirements | in_use | 3 function(s) | 2026-11-13 |
| pipeline | `aer.schedule_held_max_tries` | Entry requirements | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `aer.schedule_held_retry_days` | Entry requirements | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `aer.schedule_held_scan` | Entry requirements | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `aer.schedule_layer4_max` | Entry requirements | in_use | 6 function(s) | 2026-11-12 |
| pipeline | `aer.schedule_lock_fields` | Entry requirements | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `aer.schedule_per_provider` | Entry requirements | in_use | 2 function(s) | 2026-11-12 |
| pipeline | `aer.schedule_preview_rows` | Entry requirements | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `aer.schedule_retry_days` | Entry requirements | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `aer.source_discover_credits_per_day` | Entry requirements | in_use | 1 function(s) | 2026-11-10 |
| pipeline | `aer.source_discover_max_tries` | Entry requirements | in_use | 4 function(s) | 2026-11-10 |
| pipeline | `aer.source_discover_on` | Entry requirements | in_use | 3 function(s) | 2026-11-10 |
| pipeline | `aer.source_discover_recheck_days` | Entry requirements | in_use | 3 function(s); worker | 2026-11-10 |
| pipeline | `aer.source_stored_find_on` | Entry requirements | in_use | 3 function(s) | 2026-11-10 |
| pipeline | `aer.source_stored_find_recheck_days` | Entry requirements | in_use | 1 function(s) | 2026-11-07 |
| pipeline | `aer.stale_source_days` | Entry requirements | in_use | 3 function(s) | 2026-11-02 |
| pipeline | `aer.title_identity_bases` | Entry requirements | in_use | 2 function(s) | 2026-11-10 |
| pipeline | `aer.title_identity_min_margin` | Entry requirements | in_use | 2 function(s) | 2026-11-10 |
| pipeline | `aer.title_identity_on` | Entry requirements | in_use | 2 function(s) | 2026-11-10 |
| pipeline | `aer.v2_identity_settle_on` | Entry requirements | in_use | 1 function(s) | 2026-11-13 |
| pipeline | `aer.v2_shadow_budget_usd` | Entry requirements | ai (entry_requirements_v2_shadow) | 1 function(s) | 2026-11-12 |
| pipeline | `aer.v2_shadow_daily_usd` | Entry requirements | ai (entry_requirements_v2_shadow) | 1 function(s) | 2026-11-12 |
| pipeline | `aer.v2_shadow_on` | Entry requirements | ai (entry_requirements_v2_shadow) | 2 function(s); worker | 2026-11-13 |
| pipeline | `aer.v2_shadow_priority_providers` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.v2_shadow_sample` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.v2_shadow_tries` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `aer.weekly_email_enabled` | Entry requirements | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `aer.weekly_send_hour` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `ai_eval.auto_accept_on` | AI evaluation | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ai_eval.auto_step_max_pct` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.canary_max_items_per_day` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.canary_min_judged` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.canary_on` | AI evaluation | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ai_eval.canary_share_pct` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.max_accuracy_drop_pts` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.max_cost_rise_pct` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.max_coverage_drop_pts` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.max_error_rate_rise_pts` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.max_fp_rate_rise_pts` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.min_benefit_pts` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.min_person_examples` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.min_source_integrity_pct` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.offline_runs_on` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.refresh_on` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_eval.set_max_examples` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ai_match.min_candidates` | Course pages | ai (course_matching) | 1 function(s) | 2026-10-21 |
| pipeline | `alerts.collect_within_minutes` | Alerts | in_use | 2 function(s); src | 2026-10-31 |
| pipeline | `alerts.confirm_minutes` | Alerts | in_use | 2 function(s); src | 2026-10-31 |
| pipeline | `alerts.cooldown_minutes` | Alerts | in_use | 2 function(s); src | 2026-10-31 |
| pipeline | `alerts.delivery_enabled` | Alerts | in_use | 6 function(s); src | 2026-10-31 |
| pipeline | `alerts.digest_max_items` | Alerts | in_use | 1 function(s) | 2026-11-07 |
| pipeline | `alerts.max_attempts` | Alerts | in_use | 5 function(s); src | 2026-10-31 |
| pipeline | `alerts.min_severity` | Alerts | in_use | 2 function(s); src | 2026-10-31 |
| pipeline | `alerts.receipt_wait_hours` | Alerts | in_use | 1 function(s) | 2026-11-07 |
| pipeline | `alerts.recovery_notice` | Alerts | in_use | 1 function(s); src | 2026-10-31 |
| pipeline | `alerts.reminder_hours` | Alerts | in_use | 2 function(s); src | 2026-10-31 |
| pipeline | `alerts.retry_minutes` | Alerts | in_use | 4 function(s); src | 2026-10-31 |
| pipeline | `alerts.test_mode` | Alerts | in_use | 2 function(s) | 2026-10-31 |
| pipeline | `alerts.watchdog_scan_runs` | Alerts | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `alerts.watchdog_stale_minutes` | Alerts | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `alerts.webhook_batch` | Alerts | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `alerts.webhook_enabled` | Alerts | in_use | 3 function(s) | 2026-10-31 |
| pipeline | `api.key_rotate_overlap_hours` | Zoho API | in_use | 2 function(s) | 2026-10-16 |
| pipeline | `api.v2_r23_r24_approved` | Website API | not_read_anywhere | nothing | 2026-11-09 |
| pipeline | `backlog.not_stated_reasons` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `backlog.rate_window_hours` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `batch.adapter_build_readiness` | Enrichment | in_use | 1 function(s) | 2026-10-18 |
| pipeline | `batch.adapter_overwrite` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.admin_jobs` | Job sizes | in_use | cron command | 2026-11-12 |
| pipeline | `batch.aer_e13_recover` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `batch.aer_machine` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `batch.aer_matrix_machine` | Job sizes | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `batch.aer_reconcile` | Job sizes | in_use | 1 function(s); cron command | 2026-11-02 |
| pipeline | `batch.aer_replay` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `batch.aer_schedule_courses` | Entry requirements | in_use | 1 function(s) | 2026-11-13 |
| pipeline | `batch.aer_schedule_held` | Entry requirements | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `batch.aer_schedule_matrix` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `batch.aer_source_stored_find` | Job sizes | in_use | 1 function(s); cron command | 2026-11-07 |
| pipeline | `batch.aer_v2_identity_settle` | Entry requirements | in_use | 1 function(s) | 2026-11-13 |
| pipeline | `batch.aer_v2_shadow` | Entry requirements | in_use | 1 function(s); worker | 2026-11-12 |
| pipeline | `batch.ai_eval_examples` | AI evaluation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `batch.ai_match` | Job sizes | ai (course_matching) | 2 function(s); cron command | 2026-10-13 |
| pipeline | `batch.ai_match_prepare_courses` | Job sizes | in_use | 2 function(s); cron command | 2026-10-13 |
| pipeline | `batch.ai_match_prepare_universities` | Job sizes | in_use | 2 function(s); cron command | 2026-10-13 |
| pipeline | `batch.calendar_qualify` | Job sizes | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `batch.calendar_qualify_refresh` | Job sizes | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `batch.calendar_qualify_withdraw` | Job sizes | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `batch.calendar_refresh` | Job sizes | in_use | 1 function(s) | 2026-11-05 |
| pipeline | `batch.calendar_reread` | Job sizes | in_use | 1 function(s); cron command; worker | 2026-11-10 |
| pipeline | `batch.central_find` | Job sizes | in_use | cron command | 2026-11-12 |
| pipeline | `batch.companion_read` | Enrichment | in_use | cron command | 2026-10-17 |
| pipeline | `batch.country_scope_gate` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `batch.course_link_reverse` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.course_link_search_queue` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.course_list_read` | Enrichment | in_use | cron command | 2026-10-22 |
| pipeline | `batch.course_relink` | Course pages | in_use | cron command | 2026-10-18 |
| pipeline | `batch.course_url_fill` | Job sizes | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `batch.coverage_admit` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.coverage_admit_intakes` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.coverage_bind` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.coverage_discover` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.coverage_discover_2` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.coverage_find_site` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.coverage_read` | Job sizes | in_use | 2 function(s); cron command; worker | 2026-10-23 |
| pipeline | `batch.coverage_reconcile` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `batch.coverage_reextract` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.coverage_reidentify` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.credential_read` | Enrichment | in_use | cron command | 2026-10-22 |
| pipeline | `batch.cricos_peo` | Job sizes | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `batch.english_search_non_university` | English policies | in_use | 1 function(s) | 2026-11-07 |
| pipeline | `batch.enrich_fields` | Job sizes | in_use | 2 function(s) | 2026-11-13 |
| pipeline | `batch.entry_matrix` | Entry requirements | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `batch.evidence_dedupe` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.evidence_link_index` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.evidence_purge_check` | Storage & retention | not_read_anywhere | nothing | 2026-10-18 |
| pipeline | `batch.fee_period_settle` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.flag_change_scan` | Flags | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `batch.flag_check` | Flags | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `batch.har_generate` | Human-assisted recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `batch.har_verify` | Human-assisted recovery | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `batch.housekeeping_rows` | Housekeeping | in_use | 1 function(s) | 2026-10-16 |
| pipeline | `batch.intake_dates_apply` | Job sizes | in_use | 7 function(s); cron command | 2026-11-13 |
| pipeline | `batch.intake_publication_check` | Job sizes | in_use | 1 function(s) | 2026-11-05 |
| pipeline | `batch.intake_rule_b_qualify` | Intake dates | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `batch.layer1_regulatory_scheduler` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.layer1_run_driver` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.layer4_groups` | Layer 4 | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `batch.link_refresh` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.link_search_worker` | Job sizes | in_use | 3 function(s); cron command | 2026-10-13 |
| pipeline | `batch.logo_find` | Logos | in_use | cron command | 2026-10-15 |
| pipeline | `batch.nz_cop` | Job sizes | in_use | 1 function(s) | 2026-10-20 |
| pipeline | `batch.onboarding_snapshot` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.ops_diagnose` | Operations controller | in_use | cron command; worker | 2026-11-03 |
| pipeline | `batch.policy_add_tests` | Enrichment | in_use | cron command | 2026-10-16 |
| pipeline | `batch.policy_reparse` | English policies | in_use | cron command; worker | 2026-11-07 |
| pipeline | `batch.programme_create` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `batch.programme_discover` | Enrichment | in_use | cron command | 2026-10-22 |
| pipeline | `batch.programme_read` | Enrichment | in_use | cron command | 2026-10-22 |
| pipeline | `batch.provider_basis_rule_admit` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.provider_contact_page` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.provider_description` | Provider descriptions | in_use | 7 function(s); worker | 2026-11-08 |
| pipeline | `batch.provider_facts_read` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.provider_facts_search` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.provider_policy_refresh` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.refresh_scheduler` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.retention_evidence` | Housekeeping | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `batch.retention_layer2_rows` | Housekeeping | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `batch.retention_rows` | Housekeeping | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `batch.sch_ai_pick_scan` | Job sizes | ai (scholarship_extraction) | 1 function(s) | 2026-11-13 |
| pipeline | `batch.sch_coverage_classify` | Scholarship coverage recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `batch.sch_coverage_recover` | Scholarship coverage recovery | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `batch.sch_detail_backfill` | Scholarships | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `batch.sch_eligibility_apply` | Scholarship eligibility reader | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `batch.sch_eligibility_enqueue` | Scholarship eligibility reader | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `batch.sch_eligibility_read` | Scholarship eligibility reader | in_use | 1 function(s); worker | 2026-11-12 |
| pipeline | `batch.scholarship_candidate_skip` | Job sizes | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `batch.scholarship_discovery_settle` | Scholarships | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `batch.scholarship_owner_check` | Scholarships | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `batch.scholarship_pilot_readmit` | Job sizes | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `batch.scholarship_recheck` | Scholarships | ai (scholarship_extraction) | 1 function(s) | 2026-10-19 |
| pipeline | `batch.scholarship_round_state` | Job sizes | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `batch.scholarship_tier_refresh` | Job sizes | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `batch.scholarship_transient_recover` | Scholarship discovery | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `batch.source_find` | Enrichment | in_use | cron command | 2026-10-22 |
| pipeline | `batch.studysearch_codes` | Job sizes | in_use | cron command | 2026-10-13 |
| pipeline | `batch.transition_recheck` | Job sizes | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `batch.website_check` | Enrichment | in_use | 1 function(s) | 2026-10-18 |
| pipeline | `batch.website_sync_check` | Job sizes | in_use | cron command | 2026-10-14 |
| pipeline | `batch.zoho_sync_check` | Zoho API | in_use | cron command | 2026-10-15 |
| pipeline | `bind.map_refresh_days` | Course page search | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `bind.match_scope_top_n` | Course page search | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `bind.no_page_after_passes` | Course page search | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `bind.no_page_first_runs_per_run` | Course page search | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `bind.no_page_on` | Course page search | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `bind.no_page_pending_max` | Course page search | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `bind.no_page_providers_per_run` | Course page search | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `bind.no_page_sample` | Course page search | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `bind.no_page_trust_pct` | Course page search | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `binding.award_page_evidence` | Course pages | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `binding.cricos_guard_sample` | Course pages | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `binding.cricos_identity_guard_on` | Course pages | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `binding.domestic_page_patterns` | Course pages | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `binding.handbook_max_age_years` | Course pages | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `binding.identity_check` | Course pages | in_use | 4 function(s) | 2026-11-01 |
| pipeline | `binding.identity_exceptions` | Course pages | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `binding.international_page_patterns` | Course pages | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `binding.level_patterns` | Course pages | in_use | 2 function(s) | 2026-11-01 |
| pipeline | `binding.name_min_tokens` | Course pages | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `binding.name_stem_chars` | Course pages | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `binding.name_stop_words` | Course pages | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `binding.provider_host_aliases` | Course pages | in_use | 6 function(s) | 2026-11-01 |
| pipeline | `binding.shared_page_min_other_courses` | Course pages | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `binding.shared_page_patterns` | Course pages | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `binding.title_identity_bases` | Course pages | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `binding.variant_markers` | Course pages | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `budgets.ai_daily_ceiling_usd` | Platform upkeep | ai (openrouter) | 7 function(s) | 2026-10-31 |
| pipeline | `build.duration_tolerance_years` | Enrichment | in_use | 1 function(s) | 2026-10-18 |
| pipeline | `calendar.countries` | Enrichment | in_use | 2 function(s) | 2026-10-21 |
| pipeline | `calendar.university_levels` | Enrichment | in_use | 1 function(s) | 2026-10-18 |
| pipeline | `catalogue_layout.max_bytes` | Course catalogue | in_use | 1 function(s) | 2026-11-05 |
| pipeline | `catalogue_layout.max_columns` | Course catalogue | in_use | 1 function(s) | 2026-11-05 |
| pipeline | `catalogue_layout.new_sorts_on` | Course catalogue | in_use | 1 function(s) | 2026-11-05 |
| pipeline | `catalogue_layout.server_layouts_on` | Course catalogue | in_use | 1 function(s) | 2026-11-05 |
| pipeline | `catalogue_layout.width_max_px` | Course catalogue | in_use | 1 function(s) | 2026-11-05 |
| pipeline | `catalogue_layout.width_min_px` | Course catalogue | in_use | 1 function(s) | 2026-11-05 |
| pipeline | `central.attach_per_kind` | Admission checks | in_use | 2 function(s) | 2026-10-23 |
| pipeline | `central.auto_approve` | Admission checks | in_use | 1 function(s) | 2026-10-14 |
| pipeline | `central.auto_approve_calendar_dates` | Admission checks | in_use | 1 function(s) | 2026-11-05 |
| pipeline | `central.auto_approve_english_all` | Admission checks | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `central.calendar_excluded_words` | Intake dates | in_use | 3 function(s) | 2026-11-05 |
| pipeline | `central.calendar_qualify_blocked_period_words` | Intake dates | in_use | 3 function(s) | 2026-11-09 |
| pipeline | `central.calendar_qualify_blocked_words` | Intake dates | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `central.calendar_qualify_main_teaching` | Intake dates | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `central.calendar_qualify_max_evidence_age_days` | Intake dates | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `central.calendar_qualify_max_families` | Intake dates | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `central.calendar_qualify_max_series` | Intake dates | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `central.calendar_qualify_min_starts` | Intake dates | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `central.calendar_qualify_required_words` | Intake dates | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `central.calendar_qualify_shared_event_words` | Intake dates | in_use | 1 function(s) | 2026-11-13 |
| pipeline | `central.calendar_qualify_teaching_start_words` | Intake dates | in_use | 1 function(s) | 2026-11-13 |
| pipeline | `central.calendar_refresh_credit_budget` | Intake dates | in_use | 3 function(s) | 2026-11-05 |
| pipeline | `central.calendar_refresh_credits_per_read` | Intake dates | in_use | 2 function(s) | 2026-11-05 |
| pipeline | `central.calendar_refresh_min_age_days` | Intake dates | in_use | 2 function(s) | 2026-11-05 |
| pipeline | `central.english_provider_types` | English policies | in_use | 2 function(s) | 2026-11-07 |
| pipeline | `central.english_search_non_university` | English policies | in_use | 3 function(s) | 2026-11-07 |
| pipeline | `central.max_disagree_pct` | Admission checks | in_use | 1 function(s) | 2026-10-14 |
| pipeline | `central.min_compare` | Admission checks | in_use | 1 function(s) | 2026-10-14 |
| pipeline | `central.min_suggest_score` | Admission checks | in_use | 7 function(s) | 2026-10-23 |
| pipeline | `central.research_days` | Admission checks | in_use | 2 function(s) | 2026-10-23 |
| pipeline | `central.research_per_run` | Job sizes | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `companion.max_attempts` | Enrichment | in_use | 2 function(s) | 2026-10-17 |
| pipeline | `companion.reread_days` | Enrichment | in_use | 1 function(s) | 2026-10-17 |
| pipeline | `companion.retry_hours` | Enrichment | in_use | 1 function(s) | 2026-10-17 |
| pipeline | `concurrency.ai_match` | Job sizes | ai (course_matching) | 2 function(s); cron command | 2026-10-13 |
| pipeline | `contact.recheck_days` | Enrichment | in_use | 2 function(s) | 2026-10-22 |
| pipeline | `country_scope.gate_countries` | Enrichment | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `country_scope.page_fresh_days` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `course_link.reactivated_list_max` | Official link | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `course_link.reactivation_guard` | Official link | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `course_list.max_attempts` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `course_list.max_pages` | Enrichment | in_use | 1 function(s); worker | 2026-10-22 |
| pipeline | `course_list.min_links` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `course_list.reread_days` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `course_list.retry_hours` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `course_url.fill_countries` | Official link | in_use | 2 function(s) | 2026-10-23 |
| pipeline | `course_url.fill_enabled` | Official link | in_use | 2 function(s) | 2026-11-04 |
| pipeline | `course_url.fill_respects_layer4` | Official link | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `course_url.max_retraction_pct` | Official link | in_use | 2 function(s) | 2026-10-23 |
| pipeline | `course_url.retraction_min_fills` | Official link | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `coverage.aer_course_min_pct` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.aer_pathways` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.aer_priority_providers` | Coverage reconciliation | in_use | 4 function(s) | 2026-11-03 |
| pipeline | `coverage.aer_reader_priority_on` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.broad_check_hours` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.deadline_min_pct` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.discrepancy_recheck_hours` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.intake_min_pct` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.investigations_on` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.investigations_per_run` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.provider_level_types` | Coverage reconciliation | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `coverage.reconcile_on` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.remedy_cooldown_minutes` | Coverage reconciliation | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `coverage.remedy_max_attempts` | Coverage reconciliation | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `coverage.sch_category_levels` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.sch_category_min_items` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.sch_category_patterns` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.sch_field_min_pct` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.sch_gap_fields` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.sch_listing_min_items` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.sch_not_applicable_types` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.sch_represented_min_pct` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.stage_consumer_course_sample` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `coverage.stage_gate_scan` | Coverage reconciliation | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `crosscheck.duration_tolerance_pct` | Re-read and retry | in_use | 1 function(s) | 2026-10-20 |
| pipeline | `data_delivery.measures_per_run` | Data delivery | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `data_delivery.net_long_hours` | Data delivery | in_use | 3 function(s) | 2026-11-09 |
| pipeline | `data_delivery.net_short_hours` | Data delivery | in_use | 3 function(s) | 2026-11-09 |
| pipeline | `data_delivery.on` | Data delivery | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `data_delivery.reasons_shown` | Data delivery | in_use | 3 function(s) | 2026-11-09 |
| pipeline | `data_delivery.refresh_minutes` | Data delivery | in_use | 2 function(s) | 2026-11-09 |
| pipeline | `data_delivery.run_budget_seconds` | Data delivery | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `data_delivery.run_history_hours` | Data delivery | in_use | 2 function(s) | 2026-11-09 |
| pipeline | `data_delivery.stale_after_minutes` | Data delivery | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `data_delivery.ui_refresh_seconds` | Data delivery | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `english.default_after_withdrawn_reading` | English policies | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `enrich.ai_calls_at_once` | Job sizes | ai (course_other_fields) | 2 function(s) | 2026-11-12 |
| pipeline | `enrich.ai_items_per_call` | Job sizes | ai (course_other_fields) | 2 function(s) | 2026-11-03 |
| pipeline | `enrich.ai_pages_at_once` | Job sizes | ai (course_other_fields) | 1 function(s); worker | 2026-11-12 |
| pipeline | `enrich.campus_min_pages` | Onboarding | in_use | 2 function(s) | 2026-10-14 |
| pipeline | `enrich.course_description_claim_reach_min_words` | Course description and deadline | in_use | worker | 2026-11-11 |
| pipeline | `enrich.course_description_claim_reach_share` | Course description and deadline | in_use | worker | 2026-11-11 |
| pipeline | `enrich.course_description_claim_words` | Course description and deadline | in_use | 6 function(s) | 2026-11-11 |
| pipeline | `enrich.course_description_copy_run_words` | Course description and deadline | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `enrich.course_description_duplicate_window` | Course description and deadline | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `enrich.course_description_examples` | Course description and deadline | in_use | 1 function(s) | 2026-11-07 |
| pipeline | `enrich.course_description_generic_phrases` | Course description and deadline | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `enrich.course_description_held_days` | Course description and deadline | in_use | 2 function(s) | 2026-11-07 |
| pipeline | `enrich.course_description_learner_words` | Course description and deadline | in_use | 2 function(s) | 2026-11-10 |
| pipeline | `enrich.course_description_machine_on` | Course description and deadline | in_use | 11 function(s) | 2026-11-09 |
| pipeline | `enrich.course_description_marketing_words` | Course description and deadline | in_use | 3 function(s) | 2026-11-07 |
| pipeline | `enrich.course_description_max_chars` | Course description and deadline | in_use | 3 function(s); worker | 2026-11-03 |
| pipeline | `enrich.course_description_max_sentences` | Course description and deadline | in_use | 3 function(s); worker | 2026-11-03 |
| pipeline | `enrich.course_description_min_chars` | Course description and deadline | in_use | 2 function(s); worker | 2026-11-03 |
| pipeline | `enrich.course_description_min_quote_chars` | Course description and deadline | in_use | worker | 2026-11-03 |
| pipeline | `enrich.course_description_min_sentences` | Course description and deadline | in_use | 3 function(s); worker | 2026-11-03 |
| pipeline | `enrich.course_description_pending_global_max` | Course description and deadline | in_use | 3 function(s) | 2026-11-11 |
| pipeline | `enrich.course_description_pending_max` | Course description and deadline | in_use | 3 function(s) | 2026-11-12 |
| pipeline | `enrich.course_description_promote_held_on` | Course description and deadline | in_use | 1 function(s) | 2026-11-07 |
| pipeline | `enrich.course_description_reask_max` | Course description and deadline | in_use | 2 function(s); worker | 2026-11-07 |
| pipeline | `enrich.course_description_report_max` | Course description and deadline | in_use | 4 function(s) | 2026-11-07 |
| pipeline | `enrich.course_description_review_first` | Course description and deadline | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `enrich.course_description_sample_au` | Course description and deadline | in_use | built key: like 'enrich.%' | 2026-11-07 |
| pipeline | `enrich.course_description_sample_ca` | Course description and deadline | in_use | built key: like 'enrich.%' | 2026-11-07 |
| pipeline | `enrich.course_description_sample_countries` | Course description and deadline | in_use | 2 function(s) | 2026-11-07 |
| pipeline | `enrich.course_description_sample_nz` | Course description and deadline | in_use | built key: like 'enrich.%' | 2026-11-07 |
| pipeline | `enrich.course_description_stale_supersede_on` | Course description and deadline | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `enrich.course_description_supported_words` | Course description and deadline | in_use | 1 function(s) | 2026-11-10 |
| pipeline | `enrich.course_entry_max_slices` | Entry requirements | ai (course_entry_requirements) | worker | 2026-10-29 |
| pipeline | `enrich.course_entry_max_tokens` | Entry requirements | ai (course_entry_requirements) | worker | 2026-10-29 |
| pipeline | `enrich.course_entry_quote_chars` | Entry requirements | ai (course_entry_requirements) | worker | 2026-11-08 |
| pipeline | `enrich.course_entry_slice_chars` | Entry requirements | ai (course_entry_requirements) | worker | 2026-10-29 |
| pipeline | `enrich.course_entry_slice_concurrency` | Entry requirements | ai (course_entry_requirements) | worker | 2026-10-29 |
| pipeline | `enrich.course_entry_slice_overlap_chars` | Entry requirements | ai (course_entry_requirements) | worker | 2026-10-29 |
| pipeline | `enrich.course_text_items_per_day` | Course description and deadline | ai (course_description) | 8 function(s) | 2026-11-12 |
| pipeline | `enrich.export_page_rows` | Job sizes | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `enrich.focus_countries` | Course page search | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `enrich.focus_top_n` | Waste rules | in_use | 3 function(s) | 2026-10-14 |
| pipeline | `enrich.multi_field_fields` | Course description and deadline | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `enrich.multi_field_max_per_page` | Course description and deadline | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `enrich.multi_field_on` | Course description and deadline | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `enrich.page_chars` | Job sizes | in_use | worker | 2026-10-14 |
| pipeline | `enrich.retry_items_max` | Job sizes | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `enrich.title_batch` | Job sizes | in_use | worker | 2026-10-14 |
| pipeline | `enrich.wait_page_hours` | Re-read and retry | in_use | 2 function(s) | 2026-10-14 |
| pipeline | `entry.attach_per_provider` | Entry requirements | in_use | 3 function(s) | 2026-11-12 |
| pipeline | `entry.award_abbreviations` | Entry requirements | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `entry.completeness_providers` | Entry requirements | in_use | 1 function(s); worker | 2026-10-26 |
| pipeline | `entry.countries` | Entry requirements | in_use | 2 function(s) | 2026-10-25 |
| pipeline | `entry.course_batch_size` | Entry requirements | in_use | 2 function(s) | 2026-10-29 |
| pipeline | `entry.course_page_chars` | Entry requirements | ai (course_entry_requirements) | 1 function(s); worker | 2026-10-29 |
| pipeline | `entry.course_read_cost_usd` | Entry requirements | ai (course_entry_requirements) | 1 function(s) | 2026-10-28 |
| pipeline | `entry.course_read_countries` | Entry requirements | in_use | 3 function(s) | 2026-10-29 |
| pipeline | `entry.course_read_providers` | Entry requirements | not_read_anywhere | nothing | 2026-10-29 |
| pipeline | `entry.domestic_audience_words` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `entry.gate_cover_chars` | Entry requirements | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `entry.gate_cover_min_chars` | Entry requirements | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `entry.gate_hold_reasons` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `entry.joined_condition_kinds` | Entry requirements | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `entry.joined_condition_words` | Entry requirements | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `entry.level_equivalents` | Entry requirements | in_use | 4 function(s) | 2026-10-28 |
| pipeline | `entry.matrix_attempts` | Entry requirements | ai (entry_matrices) | 6 function(s); worker | 2026-10-25 |
| pipeline | `entry.matrix_enabled` | Entry requirements | ai (entry_matrices) | 8 function(s); worker | 2026-11-13 |
| pipeline | `entry.matrix_first_run_review` | Entry requirements | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `entry.matrix_gate` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `entry.matrix_gate_ignore_reasons` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `entry.matrix_max_rows_per_page` | Entry requirements | ai (entry_matrices) | 1 function(s) | 2026-10-25 |
| pipeline | `entry.matrix_max_tokens` | Entry requirements | ai (entry_matrices) | 1 function(s); worker | 2026-10-28 |
| pipeline | `entry.matrix_min_confidence` | Entry requirements | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `entry.matrix_model` | Entry requirements | ai (entry_matrices) | 2 function(s); worker | 2026-10-25 |
| pipeline | `entry.matrix_rank_words` | Entry requirements | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `entry.matrix_refresh_days` | Entry requirements | in_use | 6 function(s) | 2026-10-25 |
| pipeline | `entry.matrix_score_words` | Entry requirements | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `entry.matrix_slice_chars` | Entry requirements | ai (entry_matrices) | 1 function(s); worker | 2026-10-28 |
| pipeline | `entry.matrix_slice_concurrency` | Entry requirements | ai (entry_matrices) | 1 function(s); worker | 2026-10-28 |
| pipeline | `entry.max_rows_by_provider` | Entry requirements | in_use | 1 function(s) | 2026-11-10 |
| pipeline | `entry.max_rows_per_course` | Entry requirements | in_use | 2 function(s) | 2026-11-12 |
| pipeline | `entry.min_confidence` | Entry requirements | in_use | 2 function(s) | 2026-10-28 |
| pipeline | `entry.nonrequirement_patterns` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `entry.pdf_enabled` | Entry requirements | in_use | 3 function(s) | 2026-10-28 |
| pipeline | `entry.pdf_max_bytes` | Entry requirements | in_use | 2 function(s); worker | 2026-10-28 |
| pipeline | `entry.pdf_max_pages` | Entry requirements | in_use | 1 function(s) | 2026-10-28 |
| pipeline | `entry.providers` | Entry requirements | in_use | 5 function(s) | 2026-10-28 |
| pipeline | `entry.render_hosts` | Entry requirements | in_use | 3 function(s); worker | 2026-10-28 |
| pipeline | `entry.render_wait_ms` | Entry requirements | in_use | 1 function(s); worker | 2026-10-28 |
| pipeline | `entry.shared_page_count_statuses` | Entry requirements | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `entry.shared_page_hold` | Entry requirements | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `entry.shared_page_own_bases` | Entry requirements | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `entry.supersede_claim_minutes` | Entry requirements | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `entry.supersede_lock_fields` | Entry requirements | in_use | 4 function(s) | 2026-11-02 |
| pipeline | `entry.variant_check` | Entry requirements | in_use | 2 function(s) | 2026-11-01 |
| pipeline | `entry.variant_check_off_providers` | Entry requirements | in_use | 2 function(s) | 2026-11-01 |
| pipeline | `evidence.reuse_unchanged_pages` | Storage & retention | in_use | 2 function(s) | 2026-10-19 |
| pipeline | `fees.auto_admit_confidence` | Enrichment | in_use | 2 function(s) | 2026-10-21 |
| pipeline | `fees.concurrency` | Job sizes | in_use | 1 function(s); worker | 2026-10-23 |
| pipeline | `fees.countries` | Enrichment | in_use | 4 function(s) | 2026-10-26 |
| pipeline | `fees.course_pages` | Enrichment | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `fees.course_pages_per_tick` | Job sizes | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `fees.decision_memory_days` | Enrichment | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `fees.decision_same_pct` | Enrichment | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `fees.findings_in_prompt` | Enrichment | ai (fee_reader) | 1 function(s) | 2026-10-21 |
| pipeline | `fees.guard_on` | Enrichment | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `fees.guard_sample` | Enrichment | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `fees.guard_total_match_pct` | Enrichment | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `fees.guard_total_min_years` | Enrichment | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `fees.guard_year_ahead` | Enrichment | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `fees.guard_year_max` | Enrichment | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `fees.guard_year_min` | Enrichment | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `fees.guard_year_old_gap` | Enrichment | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `fees.identity_gate_on` | Admission checks | in_use | 1 function(s) | 2026-10-26 |
| pipeline | `fees.integrity_cooldown_minutes` | Enrichment | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `fees.integrity_max_attempts` | Enrichment | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `fees.max_pages_per_provider` | Enrichment | in_use | 2 function(s) | 2026-10-21 |
| pipeline | `fees.min_suggest_score` | Enrichment | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `fees.min_title_similarity` | Enrichment | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `fees.outlier_ratio` | Enrichment | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `fees.page_chars` | Enrichment | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `fees.pages_per_run` | Job sizes | in_use | 2 function(s); worker | 2026-10-22 |
| pipeline | `fees.provider_types` | Enrichment | in_use | 2 function(s) | 2026-10-26 |
| pipeline | `fees.recheck_keep_withdraws_on` | Enrichment | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `fees.respect_all_exclusions_on` | Enrichment | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `fees.respect_decisions_on` | Enrichment | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `fees.respect_holds_on` | Enrichment | in_use | 2 function(s); worker | 2026-11-03 |
| pipeline | `fees.run_every_minutes` | Job sizes | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `fees.units_agreement_pct` | Enrichment | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `fees.units_load_fix_on` | Enrichment | in_use | 1 function(s); worker | 2026-11-03 |
| pipeline | `flag.answer_wait_seconds` | Flags | in_use | 1 function(s) | 2026-11-01 |
| pipeline | `flag.course_pages_release_min_rank` | Flags | in_use | 1 function(s) | 2026-10-19 |
| pipeline | `flag.empty_calls_to_pause` | Flags | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `flag.job_recheck_hours` | Flags | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `flag.manage_min_rank` | Flags | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `flag.never_pause_modes` | Flags | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `flag.recheck_days` | Flags | in_use | 2 function(s) | 2026-10-15 |
| pipeline | `flag.soft_tries` | Flags | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `frv.expected_min_output` | First-run verification and progress | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `frv.grace_minutes` | First-run verification and progress | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `frv.next_run_search_hours` | First-run verification and progress | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `frv.on` | First-run verification and progress | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `frv.runs_scan` | First-run verification and progress | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `frv.verify_deadline_hours` | First-run verification and progress | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `gaps.advance_minutes` | Gap queue | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `gaps.cause_keep_days` | Enrichment | in_use | 2 function(s) | 2026-10-22 |
| pipeline | `gaps.causes_stale_after_minutes` | Enrichment | in_use | 1 function(s); src | 2026-10-29 |
| pipeline | `gaps.idle_rerun_minutes` | Gap queue | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `gaps.items_per_run` | Re-read and retry | in_use | 2 function(s) | 2026-10-20 |
| pipeline | `gaps.page_free_sources` | Gap queue | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `gaps.page_proof_on` | Gap queue | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `gaps.proof_recheck_days` | Gap queue | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `gaps.recheck_days` | Re-read and retry | in_use | 12 function(s) | 2026-10-20 |
| pipeline | `gaps.scan_courses_per_slice` | Gap queue | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `gaps.scan_seconds` | Gap queue | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `gaps.scraper_reads_per_day` | Re-read and retry | in_use | 2 function(s) | 2026-10-20 |
| pipeline | `governed.approval_minutes` | Governed actions | in_use | 1 function(s) | 2026-10-27 |
| pipeline | `governed.max_attempts` | Governed actions | in_use | 1 function(s) | 2026-10-27 |
| pipeline | `har.aer_case_items_max` | Human-assisted recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `har.aer_course_identity.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_course_identity.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_course_identity.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_course_identity.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_course_identity.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_document_unverified.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_document_unverified.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_document_unverified.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_document_unverified.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_document_unverified.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_empty_read_lookback_hours` | Human-assisted recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `har.aer_empty_read.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_empty_read.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_empty_read.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_empty_read.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_empty_read.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_evidence.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_evidence.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_evidence.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_evidence.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_evidence.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_held.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_held.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_held.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_held.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_held.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_rows_missing.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_rows_missing.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_rows_missing.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_rows_missing.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_read_rows_missing.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_rendered_only.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_rendered_only.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_rendered_only.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_rendered_only.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_rendered_only.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_source_missing.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_source_missing.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_source_missing.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_source_missing.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.aer_source_missing.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.ai_escalate_on` | Human-assisted recovery | ai (ops_diagnosis) | 5 function(s) | 2026-11-03 |
| pipeline | `har.ai_escalation_model` | Human-assisted recovery | ai (ops_diagnosis) | 3 function(s) | 2026-11-03 |
| pipeline | `har.ai_min_confidence` | Human-assisted recovery | ai (ops_diagnosis) | 1 function(s) | 2026-11-03 |
| pipeline | `har.ai_requests_per_day` | Human-assisted recovery | ai (ops_diagnosis) | 1 function(s) | 2026-11-03 |
| pipeline | `har.ai_wait_hours` | Human-assisted recovery | ai (ops_diagnosis) | 1 function(s) | 2026-11-03 |
| pipeline | `har.evidence_items_max` | Human-assisted recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `har.fee_evidence_conflict.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.fee_evidence_conflict.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.fee_evidence_conflict.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.fee_evidence_conflict.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.fee_evidence_conflict.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.generate_aer_item_on` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-04 |
| pipeline | `har.generate_aer_on` | Human-assisted recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `har.generate_per_provider_max` | Human-assisted recovery | in_use | 4 function(s) | 2026-11-03 |
| pipeline | `har.generate_sch_on` | Human-assisted recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `har.generate_sch_value_on` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-04 |
| pipeline | `har.history_items` | Human-assisted recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `har.intake_incomplete.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.intake_incomplete.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.intake_incomplete.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.intake_incomplete.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.intake_incomplete.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.on` | Human-assisted recovery | in_use | 4 function(s) | 2026-11-03 |
| pipeline | `har.open_max_per_lane` | Human-assisted recovery | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `har.quote_min_chars` | Human-assisted recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `har.resume_on` | Human-assisted recovery | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `har.sch_international_unresolved.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_international_unresolved.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_international_unresolved.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_international_unresolved.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_international_unresolved.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_ownership_conflict.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_ownership_conflict.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_ownership_conflict.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_ownership_conflict.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_ownership_conflict.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_source_missing.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_source_missing.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_source_missing.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_source_missing.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_source_missing.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-03 |
| pipeline | `har.sch_value_missing.assigned_to` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-04 |
| pipeline | `har.sch_value_missing.deadline_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-04 |
| pipeline | `har.sch_value_missing.escalate_after_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-04 |
| pipeline | `har.sch_value_missing.max_attempts` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-04 |
| pipeline | `har.sch_value_missing.recheck_hours` | Human-assisted recovery | in_use | built key: 'har.' \|\| case \|\| … | 2026-11-04 |
| pipeline | `har.value_year_window` | Human-assisted recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `har.verify_after_hours` | Human-assisted recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `health.binding_drop_pct` | Health report | in_use | 1 function(s) | 2026-10-24 |
| pipeline | `health.bound_empty_hours` | Health report | in_use | 1 function(s) | 2026-10-24 |
| pipeline | `health.burn_warn_pct` | Health report | in_use | 1 function(s) | 2026-10-24 |
| pipeline | `health.growth_pct` | Health report | in_use | 1 function(s) | 2026-10-24 |
| pipeline | `health.headline_target` | Health report | in_use | 1 function(s) | 2026-10-24 |
| pipeline | `health.job_failure_critical_consecutive` | Platform upkeep | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `health.job_failure_repeat_count` | Platform upkeep | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `health.job_failure_window_hours` | Platform upkeep | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `health.search_refresh_slow_minutes` | Platform upkeep | in_use | 2 function(s) | 2026-10-31 |
| pipeline | `health.search_refresh_stalled_minutes` | Platform upkeep | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `health.stuck_hours` | Health report | in_use | 1 function(s) | 2026-10-24 |
| pipeline | `hygiene.idle_days` | Housekeeping | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `hygiene.retire_after_days` | Housekeeping | in_use | src | 2026-10-15 |
| pipeline | `identity.adapter_title_countries` | Admission checks | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `identity.candidate_check_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `identity.candidate_checks_per_run` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `identity.check_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `identity.investigate_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `identity.issue_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `identity.max_providers` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `identity.name_stopwords` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `identity.name_token_min_chars` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `identity.parked_markers` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `identity.remedy_cooldown_minutes` | Platform upkeep | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `identity.remedy_max_attempts` | Platform upkeep | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `intake_dates.apply_enabled` | Intake dates | in_use | 6 function(s) | 2026-11-02 |
| pipeline | `intake_dates.deadline_max_days_before` | Intake dates | in_use | 4 function(s) | 2026-11-03 |
| pipeline | `intake_dates.max_months_ahead` | Intake dates | in_use | 4 function(s) | 2026-11-08 |
| pipeline | `intake_dates.month_unique_match` | Intake dates | in_use | 2 function(s) | 2026-11-05 |
| pipeline | `intake_dates.name_period_lists` | Intake dates | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `intake_dates.nearest_start_days` | Intake dates | in_use | 2 function(s) | 2026-11-10 |
| pipeline | `intake_dates.nearest_start_hold_levels` | Intake dates | in_use | 2 function(s) | 2026-11-11 |
| pipeline | `intake_dates.nearest_start_providers` | Intake dates | in_use | 4 function(s); src | 2026-11-12 |
| pipeline | `intake_dates.next_cycle_period_providers` | Intake dates | in_use | 1 function(s) | 2026-11-13 |
| pipeline | `intake_dates.page_date_admit` | Intake dates | in_use | 2 function(s) | 2026-11-09 |
| pipeline | `intake_dates.pilot_batch_share` | Intake dates | in_use | 2 function(s) | 2026-11-05 |
| pipeline | `intake_dates.provider_share` | Intake dates | in_use | 2 function(s) | 2026-11-05 |
| pipeline | `intake_dates.revisit_days` | Intake dates | in_use | 4 function(s) | 2026-11-05 |
| pipeline | `intake_dates.revisit_stored_inputs` | Intake dates | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `intake_dates.rule_b_auto_pause` | Intake dates | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `intake_dates.rule_b_qualify_min_rows` | Intake dates | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `intake_dates.rule_b_qualify_row_limit` | Intake dates | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `intake_dates.rule_b_requalify_hours` | Intake dates | in_use | 3 function(s) | 2026-11-11 |
| pipeline | `intake_progress.failure_rows` | Process results | in_use | 1 function(s) | 2026-11-06 |
| pipeline | `intake_progress.monopoly_runs` | Process results | in_use | 1 function(s) | 2026-11-06 |
| pipeline | `intake_progress.monopoly_share_pct` | Process results | in_use | 1 function(s) | 2026-11-06 |
| pipeline | `intake_progress.runs_listed` | Process results | in_use | 1 function(s) | 2026-11-06 |
| pipeline | `intake_progress.stall_minutes` | Process results | in_use | 1 function(s) | 2026-11-06 |
| pipeline | `intake_progress.university_rows` | Process results | in_use | 1 function(s) | 2026-11-06 |
| pipeline | `integration.bucket_keep_hours` | Integration queue | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `integration.draft_stuck_hours` | Integration queue | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `integration.entity_ids_max` | Integration queue | in_use | 3 function(s) | 2026-11-02 |
| pipeline | `integration.failed_runs_scan` | Integration queue | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `integration.first_run_lookback_hours` | Integration queue | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `integration.hidden_error_min_failures` | Integration queue | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `integration.hidden_error_min_share` | Integration queue | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `integration.hidden_error_window_minutes` | Integration queue | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `integration.inactive_courses_max` | Integration queue | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `integration.l4_pending_max` | Integration queue | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `integration.lease_stale_minutes` | Integration queue | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `integration.provider_failed_attempts_min` | Integration queue | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `integration.provider_failed_pages_min` | Integration queue | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `integration.watched_mode_min_failures` | Integration queue | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `integration.watched_modes` | Integration queue | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `integration.yield_window_hours` | Integration queue | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `integration.zero_yield_hours` | Integration queue | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `integration.zero_yield_min_calls` | Integration queue | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `jobs.held_off` | Enrichment lanes | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `jobs.per_lane_per_tick` | Job sizes | in_use | 2 function(s) | 2026-10-23 |
| pipeline | `jobs.transient_retry_max` | Platform upkeep | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `lane_funnel.firecrawl_days` | Lane funnels | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `lane_funnel.gain_window_hours` | Lane funnels | in_use | 4 function(s) | 2026-11-08 |
| pipeline | `lane_funnel.history_minutes` | Lane funnels | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `lane_funnel.job_runs_refresh_seconds` | Lane funnels | in_use | 2 function(s) | 2026-11-09 |
| pipeline | `lane_funnel.job_runs_stale_minutes` | Lane funnels | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `lane_funnel.keep_days` | Lane funnels | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `lane_funnel.on` | Lane funnels | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `lane_funnel.refresh_minutes` | Lane funnels | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `lane_funnel.run_history_hours` | Lane funnels | in_use | 2 function(s) | 2026-11-08 |
| pipeline | `lane_funnel.settings_shown_max` | Lane funnels | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `lane_funnel.stage_timeout_seconds` | Lane funnels | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `lane_funnel.stale_after_minutes` | Lane funnels | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `lanes.hold_note_minutes` | Enrichment lanes | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `lanes.skip_held_paid_calls` | Enrichment lanes | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `lanes.status_window_minutes` | Enrichment lanes | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `lanes.stored_first_on` | Enrichment lanes | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `layer1.register_end_dates_min_share` | Register | in_use | 1 function(s) | 2026-10-26 |
| pipeline | `layer1.register_end_dates_on` | Register | in_use | 1 function(s) | 2026-10-26 |
| pipeline | `layer23.universities_page_size` | Onboarding | in_use | 1 function(s) | 2026-10-29 |
| pipeline | `layer23.universities_tick_max` | Onboarding | in_use | 1 function(s) | 2026-10-29 |
| pipeline | `layer4.arrival_guard_on` | Layer 4 readiness | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `layer4.auto_admit_list_days` | Layer 4 | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `layer4.auto_admit_list_recall` | Layer 4 | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `layer4.auto_admit_match_share` | Layer 4 | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `layer4.auto_admit_min_bound` | Layer 4 | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `layer4.auto_admit_min_sample` | Layer 4 | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `layer4.auto_admit_on` | Layer 4 | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `layer4.auto_admit_sample_pct` | Layer 4 | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `layer4.auto_admit_sample_rate` | Layer 4 | in_use | 1 function(s) | 2026-10-25 |
| pipeline | `layer4.course_link_reconcile_batch` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `layer4.duplicate_decision_seconds` | Layer 4 | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `layer4.evidence_backfill_batch` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.evidence_link_kinds` | Layer 4 readiness | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `layer4.evidence_link_on` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.gate_batch` | Layer 4 readiness | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `layer4.group_by_kind` | Layer 4 | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `layer4.groups_course_link_router_on` | Layer 4 | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `layer4.groups_fill_seconds` | Layer 4 | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `layer4.inbox_detail_parallel` | Layer 4 | in_use | 1 function(s); src | 2026-11-03 |
| pipeline | `layer4.inbox_hooks_on` | Layer 4 | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.inbox_page_size` | Layer 4 | in_use | 5 function(s); src | 2026-11-03 |
| pipeline | `layer4.inbox_universities_page_size` | Layer 4 | in_use | 1 function(s); src | 2026-11-03 |
| pipeline | `layer4.lifecycle_batch_max` | Layer 4 | in_use | 2 function(s) | 2026-11-04 |
| pipeline | `layer4.lifecycle_history_max` | Layer 4 | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `layer4.lifecycle_poll_max` | Layer 4 | in_use | 1 function(s); src | 2026-11-04 |
| pipeline | `layer4.lifecycle_poll_seconds` | Layer 4 | in_use | 1 function(s); src | 2026-11-04 |
| pipeline | `layer4.lifecycle_report_days` | Layer 4 | in_use | 4 function(s) | 2026-11-04 |
| pipeline | `layer4.once_only_choices` | Layer 4 | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `layer4.pace_default_minutes` | Layer 4 readiness | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `layer4.pace_gap_minutes` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.pace_min_decisions` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.pace_min_gap_seconds` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.pace_window_days` | Layer 4 readiness | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `layer4.page_needed_convert_batch` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.page_needed_on` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.page_needed_search_max` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.platform_kinds` | Layer 4 readiness | in_use | 7 function(s) | 2026-11-03 |
| pipeline | `layer4.reader_revision` | Layer 4 | in_use | 1 function(s) | 2026-09-30 |
| pipeline | `layer4.readiness_batch` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.readiness_on` | Layer 4 readiness | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `layer4.readiness_recheck_minutes` | Layer 4 readiness | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `layer4.reconcile_batch` | Layer 4 readiness | in_use | 4 function(s) | 2026-11-03 |
| pipeline | `layer4.reconcile_supersede_on` | Layer 4 readiness | in_use | 6 function(s) | 2026-11-03 |
| pipeline | `layer4.refusal_lane_purposes` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.remedy_cooldown_minutes` | Layer 4 readiness | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `layer4.remedy_max_attempts` | Layer 4 readiness | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `layer4.reread_change_keys` | Layer 4 | in_use | 2 function(s) | 2026-09-30 |
| pipeline | `layer4.reread_transient_refusals` | Layer 4 | in_use | 1 function(s) | 2026-09-30 |
| pipeline | `layer4.rule_evidence_max_age_days` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.rule_execute_batch` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.rule_execute_time_budget_s` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.same_page_new_copy_settles` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.site_down_days` | Layer 4 | in_use | 1 function(s) | 2026-10-19 |
| pipeline | `layer4.target_days` | Layer 4 | in_use | 5 function(s) | 2026-10-19 |
| pipeline | `layer4.tuition_publication_batch` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.verify_batch` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.verify_lookback_days` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.verify_on` | Layer 4 readiness | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `layer4.verify_recheck_hours` | Layer 4 readiness | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `layer4.verify_wait_minutes` | Layer 4 readiness | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `learn.gate_on` | First-run verification and progress | in_use | 2 function(s) | 2026-11-04 |
| pipeline | `learn.min_success_pct` | First-run verification and progress | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `learn.no_yield_max` | First-run verification and progress | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `learn.not_remedy_fingerprints` | First-run verification and progress | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `learn.on` | First-run verification and progress | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `learn.rate_min_outcomes` | First-run verification and progress | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `learn.reading_minutes` | First-run verification and progress | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `lifecycle.cascade_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `lifecycle.plan_max_age_hours` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `lifecycle.propose_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `lifecycle.unavailable_review_days` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `logo.min_pixels` | Logos | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `logo.retry_after_days` | Logos | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `logo.upload_min_rank` | Logos | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `nz.cop_min_signatories` | Admission checks | in_use | 1 function(s) | 2026-10-20 |
| pipeline | `nz.cop_window_days` | Admission checks | in_use | 1 function(s) | 2026-10-20 |
| pipeline | `onboarding.course_search_wait_hours` | Onboarding | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `onboarding.proposal_attempts` | Onboarding | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `onboarding.provider_fill_valid_days` | Onboarding | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `onboarding.sample_courses` | Onboarding | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `onboarding.scholarship_admit_max_days` | Onboarding | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `onboarding.universities_per_minute` | Onboarding | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `onboarding.waiting_check_minutes` | Onboarding | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `onboarding.waiting_courses_check_hours` | Onboarding | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `onboarding.website_check_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ondemand.window_hours` | On demand | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `ops_cost.enforce_ai_loop_hold` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops_cost.enforce_ineligible` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops_cost.enforce_repeat_search` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops_cost.enforce_stored_page` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops_cost.fc_usd_per_credit` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops_cost.guard_window_hours` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops_cost.history_days` | Cost and yield | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops_cost.hold_per_run` | Cost and yield | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops_cost.ineligible_min_credits` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops_cost.likely_high_pct` | Cost and yield | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops_cost.lookback_days` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops_cost.loop_min_reads` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops_cost.measure_keep_days` | Cost and yield | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops_cost.measure_on` | Cost and yield | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops_cost.min_sample` | Cost and yield | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops_cost.remedy_cooldown_hours` | Cost and yield | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `ops_cost.remedy_max_attempts` | Cost and yield | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `ops_cost.repeat_search_hours` | Cost and yield | in_use | 3 function(s); worker | 2026-11-03 |
| pipeline | `ops_cost.samples` | Cost and yield | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops_cost.stored_page_fresh_hours` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops_cost.trip_min_events` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops_cost.trip_min_share` | Cost and yield | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops.ai_diagnosis_model` | Operations controller | ai (ops_diagnosis) | 2 function(s) | 2026-11-03 |
| pipeline | `ops.ai_diagnosis_on` | Operations controller | ai (ops_diagnosis) | 6 function(s); cron command; worker | 2026-11-03 |
| pipeline | `ops.ai_diagnosis_usd_per_day` | Operations controller | ai (ops_diagnosis) | 1 function(s); worker | 2026-11-03 |
| pipeline | `ops.ai_min_confidence` | Operations controller | ai (ops_diagnosis) | 2 function(s); worker | 2026-11-03 |
| pipeline | `ops.ai_requests_per_day` | Operations controller | ai (ops_diagnosis) | 1 function(s) | 2026-11-03 |
| pipeline | `ops.answer_replay_batch` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.answer_replay_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.answer_settle_minutes` | Platform upkeep | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops.capacity_max_checks` | Operations controller | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `ops.capacity_recheck_minutes` | Operations controller | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `ops.checkpoint_minutes` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.checkpoint_on` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.controller_on` | Operations controller | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops.cooldown_minutes` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.daily_summary_hour` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.evidence_hold_codes` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.heal_batch` | Platform upkeep | in_use | 4 function(s) | 2026-11-03 |
| pipeline | `ops.heal_cooldown_minutes` | Platform upkeep | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `ops.heal_max_attempts` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.interrupted_minutes` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.issues_per_run` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.job_runs_examined` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.lane_orphan_release_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.lease_attempts_max` | Platform upkeep | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops.lease_grace_minutes` | Platform upkeep | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops.lease_orphan_close_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.max_attempts` | Operations controller | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops.no_movement_min` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.no_movement_window_hours` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.outcome_on` | Platform upkeep | in_use | 4 function(s) | 2026-11-03 |
| pipeline | `ops.outcome_reconcile_batch` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.permanent_after_runs` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.policy_hold_codes` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.recheck_hours` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.regression_window_hours` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.report_items_scan` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.retry_cost_max_usd` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.retry_cost_pause_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.retry_cost_window_hours` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.retry_loop_runs` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.retryable_errors` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.runs_scan` | Operations controller | in_use | 5 function(s) | 2026-11-03 |
| pipeline | `ops.source_recovery_cooldown_hours` | Source proof | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `ops.source_recovery_max_attempts` | Source proof | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `ops.stale_clear_hours` | Operations controller | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `ops.task_dedupe_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ops.transient_share_max` | Operations controller | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `pages.not_course_patterns` | Course pages | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `pages.render_countries` | Course pages | in_use | 2 function(s); worker | 2026-10-23 |
| pipeline | `pdesc.about_max_segments` | Provider descriptions | in_use | 3 function(s); worker | 2026-11-02 |
| pipeline | `pdesc.about_patterns` | Provider descriptions | in_use | 4 function(s) | 2026-11-02 |
| pipeline | `pdesc.about_prefixes` | Provider descriptions | in_use | 4 function(s); worker | 2026-11-02 |
| pipeline | `pdesc.acquire_direct` | Provider descriptions | in_use | 5 function(s) | 2026-11-02 |
| pipeline | `pdesc.acquire_firecrawl` | Provider descriptions | in_use | 3 function(s) | 2026-11-02 |
| pipeline | `pdesc.ai_usd_max` | Provider descriptions | ai (provider_description) | 8 function(s) | 2026-11-10 |
| pipeline | `pdesc.backlog_hours` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.city_min_chars` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.claim_words` | Provider descriptions › built-in prompt only | in_use | 11 function(s) | 2026-11-11 |
| pipeline | `pdesc.concurrency_max` | Provider descriptions | in_use | 1 function(s) | 2026-11-10 |
| pipeline | `pdesc.countries` | Provider descriptions | in_use | 3 function(s) | 2026-11-08 |
| pipeline | `pdesc.dispatch_max` | Provider descriptions | in_use | 2 function(s) | 2026-11-10 |
| pipeline | `pdesc.duplicate_share` | Provider descriptions | in_use | 5 function(s) | 2026-11-03 |
| pipeline | `pdesc.enabled` | Provider descriptions | ai (provider_description) | 11 function(s) | 2026-11-08 |
| pipeline | `pdesc.every_minutes` | Provider descriptions | in_use | 4 function(s) | 2026-11-10 |
| pipeline | `pdesc.evidence_claim_words` | Provider descriptions › built-in prompt only | in_use | 5 function(s) | 2026-11-11 |
| pipeline | `pdesc.fill_max_per_click` | Provider descriptions | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `pdesc.firecrawl_per_call` | Provider descriptions | in_use | 1 function(s) | 2026-11-10 |
| pipeline | `pdesc.firecrawl_reads_max` | Provider descriptions | in_use | 5 function(s); worker | 2026-11-10 |
| pipeline | `pdesc.firecrawl_window_hours` | Provider descriptions | in_use | 3 function(s) | 2026-11-10 |
| pipeline | `pdesc.founded_year_min` | Provider descriptions | in_use | 3 function(s) | 2026-11-08 |
| pipeline | `pdesc.funnel_detail_max` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.identity_reeval_rules` | Provider descriptions | in_use | 2 function(s) | 2026-11-09 |
| pipeline | `pdesc.machine_admit_on` | Provider descriptions | in_use | 12 function(s) | 2026-11-08 |
| pipeline | `pdesc.machine_neutral_words` | Provider descriptions | in_use | 3 function(s) | 2026-11-09 |
| pipeline | `pdesc.machine_numbers_allowed` | Provider descriptions | in_use | 3 function(s) | 2026-11-11 |
| pipeline | `pdesc.machine_pending_max` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.machine_refused_words` | Provider descriptions | in_use | 3 function(s) | 2026-11-11 |
| pipeline | `pdesc.machine_refused_words_fr` | Provider descriptions | in_use | 3 function(s) | 2026-11-08 |
| pipeline | `pdesc.machine_settle_per_run` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.max_chars` | Provider descriptions | in_use | 5 function(s) | 2026-11-02 |
| pipeline | `pdesc.max_sentences` | Provider descriptions | in_use | 5 function(s) | 2026-11-02 |
| pipeline | `pdesc.min_chars` | Provider descriptions | in_use | 5 function(s) | 2026-11-02 |
| pipeline | `pdesc.min_quote_chars` | Provider descriptions | in_use | 2 function(s); worker | 2026-11-02 |
| pipeline | `pdesc.min_sentences` | Provider descriptions | in_use | 6 function(s); worker | 2026-11-02 |
| pipeline | `pdesc.name_min_chars` | Provider descriptions | in_use | 2 function(s) | 2026-11-08 |
| pipeline | `pdesc.on_demand_minutes` | Provider descriptions | in_use | 1 function(s) | 2026-11-11 |
| pipeline | `pdesc.page_chars` | Provider descriptions | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `pdesc.pending_max` | Provider descriptions | in_use | 10 function(s) | 2026-11-09 |
| pipeline | `pdesc.placeholder_names` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.prompt_on` | Provider descriptions | ai (provider_description) | 4 function(s) | 2026-11-11 |
| pipeline | `pdesc.prompt_refused_words` | Provider descriptions | ai (provider_description) | 3 function(s) | 2026-11-11 |
| pipeline | `pdesc.prompt_reoffer_rules` | Provider descriptions | ai (provider_description) | 1 function(s) | 2026-11-11 |
| pipeline | `pdesc.prompt_support_min_share` | Provider descriptions | ai (provider_description) | 1 function(s) | 2026-11-11 |
| pipeline | `pdesc.provider_keys` | Provider descriptions | in_use | 3 function(s); src | 2026-11-08 |
| pipeline | `pdesc.provider_types` | Provider descriptions | in_use | 3 function(s) | 2026-11-08 |
| pipeline | `pdesc.queue_cap` | Provider descriptions | in_use | 6 function(s) | 2026-11-10 |
| pipeline | `pdesc.queue_floor_runs` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.queue_per_run` | Provider descriptions | in_use | 7 function(s) | 2026-11-02 |
| pipeline | `pdesc.rate_window_hours` | Provider descriptions | in_use | 3 function(s) | 2026-11-08 |
| pipeline | `pdesc.read_cost_floor_usd` | Provider descriptions | ai (provider_description) | 2 function(s) | 2026-11-10 |
| pipeline | `pdesc.reason_min_chars` | Provider descriptions | in_use | 1 function(s) | 2026-11-06 |
| pipeline | `pdesc.recheck_days` | Provider descriptions | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `pdesc.refused_host_labels` | Provider descriptions | in_use | 2 function(s); worker | 2026-11-02 |
| pipeline | `pdesc.refused_path_words` | Provider descriptions | in_use | 2 function(s); worker | 2026-11-08 |
| pipeline | `pdesc.registry_after_rules` | Provider descriptions | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `pdesc.registry_factual_on` | Provider descriptions | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `pdesc.registry_min_facts` | Provider descriptions | in_use | 2 function(s) | 2026-11-09 |
| pipeline | `pdesc.registry_offerings_max` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.registry_per_run` | Provider descriptions | in_use | 1 function(s) | 2026-11-09 |
| pipeline | `pdesc.registry_upgrade_on` | Provider descriptions | in_use | 6 function(s) | 2026-11-09 |
| pipeline | `pdesc.report_detail` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.retry_minutes` | Provider descriptions | in_use | 3 function(s) | 2026-11-02 |
| pipeline | `pdesc.scan_factor` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.scan_max` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.self_heal_per_run` | Provider descriptions | in_use | 1 function(s) | 2026-11-10 |
| pipeline | `pdesc.self_heal_requeue_per_run` | Provider descriptions | in_use | 1 function(s) | 2026-11-10 |
| pipeline | `pdesc.source_max_age_days` | Provider descriptions | in_use | 6 function(s) | 2026-11-02 |
| pipeline | `pdesc.superlatives` | Provider descriptions | in_use | 8 function(s) | 2026-11-11 |
| pipeline | `pdesc.support_min_share` | Provider descriptions › built-in prompt only | in_use | 5 function(s) | 2026-11-11 |
| pipeline | `pdesc.target_hours` | Provider descriptions | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `pdesc.tries` | Provider descriptions | in_use | 4 function(s) | 2026-11-02 |
| pipeline | `pdesc.ui_preview_minutes` | Provider descriptions | in_use | 1 function(s) | 2026-11-06 |
| pipeline | `pdesc.verbatim_span_max_chars` | Provider descriptions › built-in prompt only | in_use | 3 function(s); worker | 2026-11-11 |
| pipeline | `plans.auto_open_max` | Onboarding | in_use | 2 function(s) | 2026-10-21 |
| pipeline | `plans.auto_per_run` | Onboarding | in_use | 2 function(s) | 2026-10-21 |
| pipeline | `plans.empty_cycles_max` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `plans.empty_cycles_quiet_days` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `plans.export_days` | Onboarding | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `plans.export_runs_per_page` | Onboarding | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `plans.fair_order` | Onboarding | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `plans.lane_backlog_wait_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `plans.noop_wait_hours` | Onboarding | in_use | 1 function(s) | 2026-11-10 |
| pipeline | `plans.orphan_lookback_days` | Onboarding | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `plans.outcome_window_hours` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `plans.priority_countries` | Onboarding | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `plans.redo_days` | Onboarding | in_use | 3 function(s) | 2026-10-21 |
| pipeline | `plans.replan_min_days` | Onboarding | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `plans.replan_min_new_gaps` | Onboarding | in_use | 3 function(s) | 2026-11-02 |
| pipeline | `plans.replan_on_evidence` | Onboarding | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `plans.replan_on_retry` | Onboarding | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `plans.replan_per_hour` | Onboarding | in_use | 2 function(s); src | 2026-11-02 |
| pipeline | `plans.retry_after_hours` | Onboarding | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `plans.retry_ignores_min_days` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `plans.retry_waits_for_change` | Onboarding | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `plans.run_now_supersedes_auto` | Onboarding | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `plans.stalled_onboarding_hold` | Platform upkeep | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `plans.stalled_onboarding_quiet_days` | Platform upkeep | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `plans.step_dependency_on` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `plans.step_max_hours` | Onboarding | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `plans.step_needs_work_on` | Platform upkeep | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `plans.step_retry_max` | Onboarding | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `plans.step_wait_hours` | Onboarding | in_use | 2 function(s) | 2026-10-21 |
| pipeline | `process_results.history_rows` | Process results | in_use | 2 function(s) | 2026-11-05 |
| pipeline | `process_results.validation_rows` | Process results | in_use | 1 function(s) | 2026-11-05 |
| pipeline | `process_results.window_days` | Process results | in_use | 3 function(s) | 2026-11-05 |
| pipeline | `programme.max_urls` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `programme.read_attempts` | Enrichment | in_use | 2 function(s) | 2026-10-22 |
| pipeline | `programme.reread_days` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `progress.intake_chain_on` | First-run verification and progress | in_use | 1 function(s) | 2026-11-06 |
| pipeline | `progress.keep_observations_days` | First-run verification and progress | not_read_anywhere | nothing | 2026-11-03 |
| pipeline | `progress.on` | First-run verification and progress | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `progress.stall_hours` | First-run verification and progress | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `progress.window_hours` | First-run verification and progress | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `proof.absence_input_classes` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `proof.absence_input_on` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `proof.feed_per_run` | Source proof | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `proof.max_attempts` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `proof.request_hold_days` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `proof.scan_per_run` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `proof.search_per_run` | Source proof | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `publish.eligible_min_current_courses` | Register | in_use | 1 function(s) | 2026-10-26 |
| pipeline | `publish.eligible_min_site_pages` | Register | in_use | 1 function(s) | 2026-10-26 |
| pipeline | `queue_watch.alert_repeat_hours` | Platform upkeep | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `queue_watch.fail_min` | Platform upkeep | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `queue_watch.fail_percent` | Platform upkeep | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `queue_watch.report_hours` | Platform upkeep | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `queue_watch.retry_after_hours` | Platform upkeep | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `queue_watch.retry_batch` | Platform upkeep | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `queue_watch.retry_days` | Platform upkeep | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `queue_watch.stuck_minutes` | Platform upkeep | in_use | 2 function(s) | 2026-10-22 |
| pipeline | `queue_watch.window_minutes` | Platform upkeep | in_use | 2 function(s) | 2026-10-22 |
| pipeline | `ranking.edition_calendar` | Register | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ranking.edition_grace_days` | Register | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `ranking.import_max_age_days` | Register | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `reading.aer_v2_concurrency` | Entry requirements | ai (entry_requirements_v2_shadow) | worker | 2026-11-12 |
| pipeline | `reading.aer_v2_max_tokens` | Entry requirements | ai (entry_requirements_v2_shadow) | worker | 2026-11-12 |
| pipeline | `reading.aer_v2_page_chars` | Entry requirements | ai (entry_requirements_v2_shadow) | worker | 2026-11-12 |
| pipeline | `reading.answer_tokens.adapter_proposal` | AI answer limits | ai (adapter_builder) | worker | 2026-10-29 |
| pipeline | `reading.answer_tokens.adapter_proposal_retry` | AI answer limits | ai (adapter_builder) | worker | 2026-10-29 |
| pipeline | `reading.answer_tokens.campus_lists` | AI answer limits | ai (course_other_fields) | worker | 2026-10-29 |
| pipeline | `reading.answer_tokens.campus_regions` | AI answer limits | ai (course_other_fields) | worker | 2026-10-29 |
| pipeline | `reading.answer_tokens.central_page` | AI answer limits | ai (central_english_policy) | worker | 2026-10-29 |
| pipeline | `reading.answer_tokens.course_fields` | AI answer limits | ai (course_other_fields) | worker | 2026-10-29 |
| pipeline | `reading.answer_tokens.course_page_match` | AI answer limits | ai (course_matching) | worker | 2026-10-29 |
| pipeline | `reading.answer_tokens.course_text` | AI answer limits | ai (course_description) | worker | 2026-11-03 |
| pipeline | `reading.answer_tokens.course_titles` | AI answer limits | ai (course_other_fields) | worker | 2026-10-29 |
| pipeline | `reading.answer_tokens.fee_page` | AI answer limits | ai (fee_reader) | worker | 2026-10-29 |
| pipeline | `reading.answer_tokens.ops_diagnosis` | Operations controller | ai (ops_diagnosis) | worker | 2026-11-03 |
| pipeline | `reading.answer_tokens.provider_address` | AI answer limits | ai (course_other_fields) | worker | 2026-10-29 |
| pipeline | `reading.answer_tokens.provider_description` | AI answer limits | ai (provider_description) | worker | 2026-11-02 |
| pipeline | `reading.answer_tokens.scholarship_page` | AI answer limits | ai (scholarship_extraction) | worker | 2026-11-12 |
| pipeline | `reading.answer_tokens.scholarship_recheck` | AI answer limits | ai (scholarship_extraction) | worker | 2026-10-29 |
| pipeline | `reading.calendar_answer_tokens` | Intake dates | ai (calendar_reading) | worker | 2026-11-12 |
| pipeline | `reading.calendar_max_slices` | Intake dates | ai (calendar_reading) | worker | 2026-11-12 |
| pipeline | `reading.calendar_notes_max` | Intake dates | in_use | 1 function(s) | 2026-11-05 |
| pipeline | `reading.calendar_slice_chars` | Intake dates | ai (calendar_reading) | worker | 2026-11-05 |
| pipeline | `reading.course_entry_fragment_min_chars` | Entry requirements | in_use | worker | 2026-11-08 |
| pipeline | `reading.course_quote_fragments_on` | Entry requirements | in_use | worker | 2026-11-08 |
| pipeline | `reading.entry_band_label_words` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_cell_min_levels` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_cell_min_lines` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_cell_reader_on` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_country_aliases` | Entry requirements | in_use | worker | 2026-11-08 |
| pipeline | `reading.entry_country_aliases_on` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_global_pages_on` | Entry requirements | in_use | worker | 2026-11-03 |
| pipeline | `reading.entry_global_phrases` | Entry requirements | in_use | worker | 2026-11-03 |
| pipeline | `reading.entry_global_qualifications` | Entry requirements | in_use | worker | 2026-11-03 |
| pipeline | `reading.entry_global_scope_tokens` | Entry requirements | in_use | 1 function(s); worker | 2026-11-11 |
| pipeline | `reading.entry_grid_headings` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_grid_reader_on` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_pdf_firecrawl_on` | Entry requirements | in_use | worker | 2026-11-12 |
| pipeline | `reading.entry_pdf_per_call` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_qualification_countries` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_qualification_first_on` | Entry requirements | in_use | 2 function(s) | 2026-11-11 |
| pipeline | `reading.entry_quote_parts_on` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_quote_window_chars` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_range_lower_bound_on` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_subject_rows_on` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.entry_value_null_on` | Entry requirements | in_use | worker | 2026-11-11 |
| pipeline | `reading.link_search_share_on` | Course pages | in_use | worker | 2026-11-03 |
| pipeline | `reading.pages_at_once` | Job sizes | in_use | worker | 2026-10-23 |
| pipeline | `reading.provider_quote_fragments_on` | Provider descriptions | in_use | worker | 2026-11-09 |
| pipeline | `reading.sch_recovery_linked_chars` | Scholarship details | in_use | worker | 2026-11-13 |
| pipeline | `reading.sch_recovery_section_chars` | Scholarship details | in_use | worker | 2026-11-13 |
| pipeline | `recheck.cricos_contact_days` | Re-read and retry | in_use | 2 function(s) | 2026-10-13 |
| pipeline | `recovery.close_on_verified_on` | First-run verification and progress | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `recovery.cohort_refresh_per_run` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `recovery.d1_history_days` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `recovery.d1_read_credits` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `recovery.engineering_checkpoint_hours` | First-run verification and progress | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `recovery.gap_sample` | First-run verification and progress | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `recovery.issues_per_run` | First-run verification and progress | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `recovery.link_on` | First-run verification and progress | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `recovery.read_blocked_statuses` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `recovery.read_tries` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `recovery.route_on` | First-run verification and progress | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `recovery.severity_reason_min_chars` | First-run verification and progress | in_use | 2 function(s) | 2026-11-04 |
| pipeline | `relink.pattern_min_pages` | Course pages | in_use | 1 function(s) | 2026-10-18 |
| pipeline | `relink.pattern_min_share` | Course pages | in_use | 1 function(s) | 2026-10-18 |
| pipeline | `relink.slug_variants_on` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `relink.statuses` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `relink.stored_search_reuse_on` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `relink.url_pattern_countries` | Course pages | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `relink.urls_per_university` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `relink.year_current_on` | Source proof | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `remap.site_days` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `remediation.max_batch_courses` | Platform upkeep | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `reports.resolve_min_rank` | Zoho API | in_use | 1 function(s) | 2026-10-19 |
| pipeline | `reports.status_batch_max` | Zoho API | in_use | 1 function(s) | 2026-10-19 |
| pipeline | `reread.course_page_default_days` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `reread.pilot_daily_max` | Re-read and retry | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `reread.pilot_enabled` | Re-read and retry | in_use | 2 function(s) | 2026-10-31 |
| pipeline | `reread.pilot_min_days` | Re-read and retry | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `reread.scholarship_ai_days` | Re-read and retry | ai (scholarship_extraction) | 1 function(s) | 2026-10-13 |
| pipeline | `reread.scholarship_candidate_days` | Re-read and retry | in_use | 2 function(s) | 2026-10-13 |
| pipeline | `reread.scholarship_discovery_days` | Re-reads and retries | in_use | 3 function(s) | 2026-11-02 |
| pipeline | `reread.scholarship_listing_days` | Re-read and retry | in_use | 2 function(s) | 2026-10-13 |
| pipeline | `reread.scholarship_listing_unchanged_days` | Scholarship discovery | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `reread.scholarship_page_days` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `retention.estimate_refresh_hours` | Housekeeping | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `retention.health_snapshots_days` | Platform upkeep | in_use | 1 function(s) | 2026-10-24 |
| pipeline | `retention.job_log_keep_days` | Housekeeping | in_use | 3 function(s) | 2026-10-16 |
| pipeline | `retention.mode_outcome_ledger_days` | Platform upkeep | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `retention.nonce_keep_days` | Housekeeping | in_use | 1 function(s) | 2026-10-16 |
| pipeline | `retention.provider_field_daily_days` | Storage & retention | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `retention.resource_observations_days` | Housekeeping | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `retention.screenshot_keep_days` | Housekeeping | in_use | 2 function(s) | 2026-10-15 |
| pipeline | `retention.screenshot_open_build_days` | Housekeeping | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `retention.settings_backup_days` | Storage & retention | in_use | 2 function(s) | 2026-10-21 |
| pipeline | `retention.toolset_use_daily_days` | Storage & retention | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `retention.ui_error_log_days` | Platform upkeep | in_use | 1 function(s) | 2026-10-24 |
| pipeline | `retention.zero_yield_snapshots_days` | Retention | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `retry.course_page_failed_hours` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `retry.course_page_http_failed_days` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `retry.course_page_render_hours` | Re-read and retry | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `retry.intake_publication_checks` | Intake dates | in_use | 2 function(s) | 2026-11-05 |
| pipeline | `retry.no_website_days` | Re-read and retry | in_use | 3 function(s) | 2026-10-13 |
| pipeline | `retry.provider_facts_attempts` | Re-read and retry | in_use | 2 function(s) | 2026-10-13 |
| pipeline | `retry.provider_facts_refusal_hours` | English policies | in_use | 1 function(s) | 2026-11-07 |
| pipeline | `retry.sch_ai_wait_minutes` | Scholarships | ai (scholarship_extraction) | 1 function(s) | 2026-11-07 |
| pipeline | `retry.sch_eligibility_hours` | Scholarship eligibility reader | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `retry.scholarship_blocked_days` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `retry.scholarship_candidate_failed_hours` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `retry.scholarship_discovery_deferred_hours` | Re-reads and retries | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `retry.scholarship_discovery_held_hours` | Re-reads and retries | in_use | 2 function(s) | 2026-11-02 |
| pipeline | `retry.scholarship_failed_hours` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `retry.scholarship_listing_failed_days` | Re-read and retry | in_use | 2 function(s) | 2026-10-13 |
| pipeline | `retry.scholarship_listing_partial_hours` | Re-reads and retries | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `retry.scholarship_name_mismatch_days` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `retry.scholarship_transient_cycles_max` | Scholarship discovery | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `retry.scholarship_transient_park_hours` | Scholarship discovery | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `retry.scholarship_transient_recover_on` | Scholarship discovery | in_use | 2 function(s) | 2026-11-12 |
| pipeline | `retry.scholarship_waiting_scraper_hours` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `retry.site_map_failed_hours` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `retry.website_after_budget_days` | Re-read and retry | in_use | 1 function(s) | 2026-10-13 |
| pipeline | `run_now.cohort_scan_rows` | Run now | in_use | 2 function(s) | 2026-11-04 |
| pipeline | `run_now.cohort_top_au_universities` | Run now | in_use | 3 function(s) | 2026-11-04 |
| pipeline | `run_now.history_rows` | Run now | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `run_now.jobs` | Run now | in_use | 3 function(s) | 2026-11-09 |
| pipeline | `run_now.pilot_cap` | Run now | in_use | 12 function(s) | 2026-11-04 |
| pipeline | `run_now.preview_rows_per_university` | Run now | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `run_now.preview_seconds` | Run now | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `sch_ai.wait_max_days` | Scholarships | ai (scholarship_extraction) | 1 function(s) | 2026-11-07 |
| pipeline | `sch_cov.classify_on` | Scholarship coverage recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `sch_cov.escalate_after_hours` | Scholarship coverage recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `sch_cov.legal_name_identity_on` | Scholarship coverage recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `sch_cov.policy_disposition_on` | Scholarship coverage recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `sch_cov.recheck_hours` | Scholarship coverage recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `sch_cov.reclassify_hours` | Scholarship coverage recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `sch_cov.recover_listings_on` | Scholarship coverage recovery | in_use | 4 function(s) | 2026-11-12 |
| pipeline | `sch_cov.recover_per_provider_max` | Scholarship coverage recovery | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `sch_cov.recover_register_pages_on` | Scholarship coverage recovery | in_use | 3 function(s) | 2026-11-12 |
| pipeline | `sch_cov.recover_stored_reads_on` | Scholarship coverage recovery | in_use | 3 function(s) | 2026-11-12 |
| pipeline | `sch_cov.scope_states_on` | Scholarship coverage recovery | in_use | 1 function(s) | 2026-11-08 |
| pipeline | `sch_cov.value_apply_on` | Scholarship coverage recovery | in_use | 1 function(s) | 2026-11-04 |
| pipeline | `sch_cov.verify_after_hours` | Scholarship coverage recovery | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `sch_detail.on` | Scholarships | in_use | 2 function(s) | 2026-11-12 |
| pipeline | `sch_detail.recovery_on` | Scholarship details | in_use | 1 function(s) | 2026-11-13 |
| pipeline | `sch_detail.source_stale_days` | Scholarship details | in_use | 1 function(s) | 2026-11-13 |
| pipeline | `sch_elig.apply_on` | Scholarship eligibility reader | in_use | 1 function(s); worker | 2026-11-12 |
| pipeline | `sch_elig.link_follow_on` | Scholarship eligibility reader | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `sch_elig.links_max` | Scholarship eligibility reader | in_use | 1 function(s); worker | 2026-11-12 |
| pipeline | `sch_elig.max_tries` | Scholarship eligibility reader | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `sch_elig.on` | Scholarship eligibility reader | in_use | 4 function(s) | 2026-11-12 |
| pipeline | `sch_elig.policy_refused_too` | Scholarship eligibility reader | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `sch_elig.readmit_on` | Scholarship eligibility reader | in_use | 1 function(s) | 2026-11-13 |
| pipeline | `sch_elig.readmit_round_stale_days` | Scholarship eligibility reader | in_use | 2 function(s) | 2026-11-13 |
| pipeline | `sch_elig.silent_resolves` | Scholarship eligibility reader | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `sch_flow.aged_days` | Scholarship flow guard | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `sch_flow.decline_min_daily` | Scholarship flow guard | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `sch_flow.decline_pct` | Scholarship flow guard | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `sch_flow.decline_window_days` | Scholarship flow guard | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `sch_flow.on` | Scholarship flow guard | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `sch_flow.stall_hours` | Scholarship flow guard | in_use | 1 function(s) | 2026-11-12 |
| pipeline | `scholarship.candidate_pick_window` | Job sizes | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.candidates_max` | Job sizes | in_use | 1 function(s); worker | 2026-11-02 |
| pipeline | `scholarship.catalogue_render_wait_ms` | Scholarships | in_use | worker | 2026-11-02 |
| pipeline | `scholarship.discover_pick_window` | Job sizes | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.discover_providers_max` | Job sizes | in_use | 1 function(s); worker | 2026-11-02 |
| pipeline | `scholarship.discovery_settle_on` | Scholarships | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `scholarship.enqueue_directory_gate_on` | Scholarships | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `scholarship.external_award_patterns` | Scholarships | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.legitimacy_checks_on` | Scholarships | in_use | 3 function(s) | 2026-11-02 |
| pipeline | `scholarship.legitimacy_min_courses` | Scholarships | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.lifetime_cap_on` | Scholarships | in_use | 1 function(s); worker | 2026-11-02 |
| pipeline | `scholarship.listing_fanout_on` | Scholarships | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.listing_items_max` | Job sizes | in_use | worker | 2026-11-02 |
| pipeline | `scholarship.listing_max` | Job sizes | in_use | 1 function(s); worker | 2026-11-02 |
| pipeline | `scholarship.listing_pages_max` | Job sizes | in_use | worker | 2026-11-02 |
| pipeline | `scholarship.map_candidates_max` | Job sizes | in_use | worker | 2026-11-02 |
| pipeline | `scholarship.non_university_admission` | Scholarships | in_use | 3 function(s) | 2026-11-02 |
| pipeline | `scholarship.non_university_types` | Scholarships | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.pilot_only` | Scholarships | in_use | 2 function(s) | 2026-11-12 |
| pipeline | `scholarship.pilot_provider_ids` | Scholarships | in_use | 3 function(s) | 2026-11-02 |
| pipeline | `scholarship.pilot_stop_ai_share_pct` | Scholarships | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.pilot_stop_failed_pct` | Scholarships | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.pilot_stop_fc_share_pct` | Scholarships | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.pilot_stop_min_reads` | Scholarships | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.pilot_stop_unsupported_max` | Scholarships | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.pilot_stop_wrong_provider_max` | Scholarships | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `scholarship.read_max` | Job sizes | in_use | worker | 2026-11-02 |
| pipeline | `scholarship.refill_open_countries` | Scholarships | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `scholarship.refill_priority_countries` | Scholarships | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `scholarship.refill_priority_focus` | Scholarships | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `scholarship.refill_priority_other` | Scholarships | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `scholarship.render_wait_ms` | Scholarships | in_use | worker | 2026-11-02 |
| pipeline | `scholarship.single_read_daily_max` | Scholarships | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `scholarship.sources_per_provider_max` | Job sizes | in_use | 1 function(s); worker | 2026-11-02 |
| pipeline | `scholarship.umbrella_sections_on` | Scholarships | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `search.daily_picked_cap` | Course page search | in_use | 5 function(s); src | 2026-10-25 |
| pipeline | `search.min_site_course_pages` | Course pages | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `search.person_task_bypass` | Course page search | in_use | 6 function(s) | 2026-10-24 |
| pipeline | `search.priority_countries` | Course pages | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `search.refresh_min_gap_minutes` | Website API | in_use | 2 function(s) | 2026-10-31 |
| pipeline | `search.region_from_provider_countries` | Website API | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `search.site_check_countries` | Course pages | in_use | 2 function(s) | 2026-10-21 |
| pipeline | `search.site_list_first_types` | Course pages | in_use | 1 function(s) | 2026-10-21 |
| pipeline | `search.skip_providers` | Course pages | in_use | 5 function(s) | 2026-10-21 |
| pipeline | `search.stop_per_course_after` | Course page search | in_use | 2 function(s) | 2026-10-24 |
| pipeline | `search.wrong_in_row_stop` | Course pages | in_use | 2 function(s) | 2026-10-21 |
| pipeline | `snapshot.course_coverage_min_interval_minutes` | Platform upkeep | in_use | 1 function(s) | 2026-10-29 |
| pipeline | `snapshot.course_coverage_stale_minutes` | Platform upkeep | in_use | 1 function(s) | 2026-10-29 |
| pipeline | `snapshots.field_coverage_every_minutes` | Platform upkeep | in_use | 1 function(s) | 2026-10-29 |
| pipeline | `snapshots.platform_notices_every_minutes` | Platform upkeep | in_use | 1 function(s) | 2026-10-29 |
| pipeline | `snapshots.scholarship_publishability_every_minutes` | Platform upkeep | in_use | 1 function(s) | 2026-10-29 |
| pipeline | `snapshots.stale_after_minutes` | Platform upkeep | in_use | 1 function(s); src | 2026-10-29 |
| pipeline | `source_find.max_files` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `source_find.max_list_tries` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `source_find.max_locs` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `source_find.min_links` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `source_find.min_recall` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `source_find.page_share_below` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `source_find.programme_below` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `source_find.retry_days` | Enrichment | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `stall.country_gap_points` | Re-read and retry | in_use | 2 function(s) | 2026-10-20 |
| pipeline | `stall.days` | Re-read and retry | in_use | 2 function(s) | 2026-10-20 |
| pipeline | `stall.min_points` | Re-read and retry | in_use | 2 function(s) | 2026-10-20 |
| pipeline | `stall.queue_hours` | Re-read and retry | in_use | 1 function(s) | 2026-10-20 |
| pipeline | `stats.countries` | Health report | in_use | cron command | 2026-10-24 |
| pipeline | `stats.flat_field_hours` | Platform upkeep | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `stats.slow_call_seconds` | Platform upkeep | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `stats.task_wait_minutes` | Platform upkeep | in_use | 1 function(s) | 2026-10-22 |
| pipeline | `stats.trend_hours` | Platform upkeep | in_use | 1 function(s); src | 2026-10-22 |
| pipeline | `storage.size_keep_days` | Storage | in_use | 1 function(s); src | 2026-10-16 |
| pipeline | `targets.ai_credit_min_usd` | Operating targets | ai (openrouter) | 1 function(s) | 2026-10-31 |
| pipeline | `targets.api_search_p95_ms` | Operating targets | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `targets.api_search_page_size` | Operating targets | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `targets.futile_items_per_day` | Operating targets | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `targets.job_failures_per_day` | Operating targets | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `targets.reference_bundle_hours` | Operating targets | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `targets.review_oldest_days` | Operating targets | in_use | 1 function(s) | 2026-10-31 |
| pipeline | `tasks.hold_kinds` | Platform upkeep | in_use | 4 function(s) | 2026-11-03 |
| pipeline | `tasks.lane_hold_max_hours` | Platform upkeep | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `tasks.lane_hold_on` | Platform upkeep | in_use | 3 function(s) | 2026-11-03 |
| pipeline | `tasks.stall_seconds` | Platform upkeep | in_use | 2 function(s); src | 2026-10-24 |
| pipeline | `tasks.unfinished_lookback_days` | Platform upkeep | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `tick.backoff_max_minutes` | Waste rules | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `transition.recheck_days` | Job sizes | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `usage.screen_window_days` | Housekeeping | in_use | 1 function(s); src | 2026-10-20 |
| pipeline | `waste.admit_full_check_hours` | Waste rules | in_use | 2 function(s) | 2026-10-14 |
| pipeline | `waste.flipflop_max_changes` | Waste rules | in_use | 1 function(s) | 2026-10-14 |
| pipeline | `waste.flipflop_window_days` | Waste rules | in_use | 2 function(s) | 2026-10-14 |
| pipeline | `waste.idle_pause_hours` | Waste rules | in_use | 1 function(s) | 2026-10-14 |
| pipeline | `waste.page_reuse_hours` | Waste rules | in_use | 2 function(s) | 2026-10-14 |
| pipeline | `waste.retry_max_attempts` | Waste rules | in_use | 2 function(s) | 2026-10-14 |
| pipeline | `waste.retry_min_sample` | Waste rules | in_use | 1 function(s) | 2026-10-14 |
| pipeline | `waste.retry_min_yield_pct` | Waste rules | in_use | 2 function(s) | 2026-10-14 |
| pipeline | `waste.retry_window_days` | Waste rules | in_use | 1 function(s) | 2026-10-14 |
| pipeline | `wc.aer_candidate_factor` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.aer_fair_on` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.aer_new_provider_reserve_pct` | Work continuity | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `wc.aer_provider_share_pct` | Work continuity | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `wc.aer_tech_max_attempts` | Work continuity | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `wc.ai_max_attempts` | Work continuity | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `wc.ai_recovery_on` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.backoff_base_minutes` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.backoff_max_minutes` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.budget_recheck_minutes` | Work continuity | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `wc.escalate_on` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.evidence_keep` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.fee_item_claims_on` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.fee_live_leases_max` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.link_search_continuity_on` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.link_search_max_attempts` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.link_search_resend_minutes` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.on` | Work continuity | in_use | 7 function(s) | 2026-11-03 |
| pipeline | `wc.page_find_never_codes` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.page_find_never_end_on` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.page_find_park_on` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.page_find_release_on` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.recover_by_hours` | Work continuity | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `wc.reflect_lookback_items` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.reflect_scan_ids` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.relink_fair_on` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.relink_run_seconds` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.relink_university_seconds` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.repeat_min` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.report_window_hours` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.review_full_recheck_minutes` | Work continuity | in_use | 1 function(s) | 2026-11-03 |
| pipeline | `wc.site_max_rechecks` | Work continuity | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `wc.site_recheck_hours` | Work continuity | in_use | named in pipeline.ops_remedies / work_recovery_policies rows | 2026-11-03 |
| pipeline | `wc.tick_batch` | Work continuity | in_use | 5 function(s) | 2026-11-03 |
| pipeline | `wc.transient_max_attempts` | Work continuity | in_use | 2 function(s) | 2026-11-03 |
| pipeline | `website.logo_link_days` | Website API | in_use | 3 function(s); worker | 2026-10-14 |
| pipeline | `website.logo_renew_before_days` | Website API | in_use | 2 function(s) | 2026-10-14 |
| pipeline | `website.logos_display_approved` | Website API | in_use | built key: 'website.' \|\| … \|\| '_display_approved' | 2026-10-14 |
| pipeline | `website.rankings_display_approved` | Website API | in_use | built key: 'website.' \|\| … \|\| '_display_approved' | 2026-10-14 |
| pipeline | `website.rate_per_minute` | Website API | in_use | 2 function(s) | 2026-10-16 |
| pipeline | `website.sync_item_unit_bytes` | Website API | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `website.sync_page_max` | Website API | in_use | 2 function(s) | 2026-10-16 |
| pipeline | `worker.outcome_failed_runs` | Health report | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `worker.outcome_window_hours` | Health report | in_use | 1 function(s) | 2026-11-02 |
| pipeline | `zero_yield.auto_reset` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zero_yield.candidate_overlap_min` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zero_yield.detect_providers_per_run` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zero_yield.flag_rate_pct` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zero_yield.level_words` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zero_yield.listing_url_pattern` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zero_yield.min_bound` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zero_yield.not_found_pattern` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zero_yield.off_pattern_share_max` | Zero-yield pages | in_use | 2 function(s) | 2026-10-23 |
| pipeline | `zero_yield.providers_per_run` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zero_yield.reset_per_provider` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zero_yield.title_overlap_min` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zero_yield.urls_max_age_days` | Zero-yield pages | in_use | 1 function(s) | 2026-10-23 |
| pipeline | `zoho.export_page_rows` | Zoho API | in_use | 1 function(s) | 2026-10-16 |
| pipeline | `zoho.log_keep_days` | Zoho API | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `zoho.logo_link_days` | Zoho API | in_use | 2 function(s); worker | 2026-10-15 |
| pipeline | `zoho.logo_renew_before_days` | Zoho API | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `zoho.page_max` | Zoho API | in_use | 8 function(s) | 2026-10-15 |
| pipeline | `zoho.rate_per_minute` | Zoho API | in_use | 2 function(s) | 2026-10-15 |
| pipeline | `zoho.sync_countries` | Zoho API | in_use | 6 function(s) | 2026-10-15 |
| pipeline | `zoho.sync_item_unit_bytes` | Zoho API | in_use | 1 function(s) | 2026-10-15 |
| pipeline | `zoho.sync_page_max` | Zoho API | in_use | 1 function(s) | 2026-10-15 |
| scheduled_jobs | `min_failures` | Notices | in_use | 1 function(s) | 2026-10-04 |
| scheduled_jobs | `notice_window_hours` | Notices | in_use | 1 function(s) | 2026-10-04 |
| scrapingbee | `plan_counted_from` | Key and plan limits | in_use | 1 function(s) | 2026-10-04 |
| scrapingbee | `plan_credits` | Key and plan limits | in_use | 6 function(s); src | 2026-10-04 |
| scrapingbee | `plan_max_concurrency` | Key and plan limits | in_use | 1 function(s); worker | 2026-10-04 |
| scrapingbee | `plan_name` | Key and plan limits | in_use | 2 function(s) | 2026-10-04 |
| scrapingbee | `plan_renews_monthly` | Key and plan limits | in_use | 1 function(s) | 2026-10-04 |
| scrapingbee | `plan_reserve` | Key and plan limits | in_use | 1 function(s); worker | 2026-10-04 |
| scrapingbee | `premium_proxy` | How the service is used | in_use | worker | 2026-10-04 |
| scrapingbee | `render_js` | How the service is used | in_use | worker | 2026-10-04 |
| scrapingbee | `sample_cases_per_country` | Sample runs | in_use | 1 function(s) | 2026-10-04 |
| scrapingbee | `sample_concurrency` | Sample runs | in_use | worker | 2026-10-04 |
| scrapingbee | `sample_countries` | Sample runs | in_use | 3 function(s) | 2026-10-04 |
| scrapingbee | `sample_credits_per_run` | Sample runs | in_use | 3 function(s) | 2026-10-04 |
| scrapingbee | `sample_seconds_per_call` | Sample runs | in_use | worker | 2026-10-04 |
| scrapingbee | `title_match_min` | How the service is used | in_use | worker | 2026-10-04 |
| scrapingbee | `usd_per_1k_credits` | Key and plan limits | in_use | 1 function(s) | 2026-10-04 |
| scrapingbee | `wait_ms` | How the service is used | in_use | 1 function(s); worker; src | 2026-10-04 |
| serper | `course_like_url` | Search pass | in_use | 1 function(s) | 2026-10-04 |
| serper | `course_query` | How the service is used | in_use | worker | 2026-10-04 |
| serper | `course_site_filter` | How the service is used | in_use | worker | 2026-10-04 |
| serper | `directory_hosts` | How the service is used | in_use | worker | 2026-10-04 |
| serper | `pass_auto_continue` | Search pass | in_use | 1 function(s) | 2026-10-04 |
| serper | `pass_cases_per_country` | Search pass | in_use | 1 function(s) | 2026-10-04 |
| serper | `pass_credits_per_run` | Search pass | in_use | 1 function(s) | 2026-10-04 |
| serper | `pass_refind_unreadable` | Search pass | in_use | 1 function(s) | 2026-10-04 |
| serper | `plan_counted_from` | Key and plan limits | in_use | 1 function(s) | 2026-10-04 |
| serper | `plan_credits` | Key and plan limits | in_use | 6 function(s); src | 2026-10-04 |
| serper | `plan_max_concurrency` | Key and plan limits | in_use | 1 function(s); worker | 2026-10-04 |
| serper | `plan_name` | Key and plan limits | in_use | 2 function(s) | 2026-10-04 |
| serper | `plan_renews_monthly` | Key and plan limits | in_use | 1 function(s) | 2026-10-04 |
| serper | `plan_reserve` | Key and plan limits | in_use | 1 function(s); worker | 2026-10-04 |
| serper | `provider_query` | How the service is used | in_use | worker | 2026-10-04 |
| serper | `results_per_query` | How the service is used | in_use | worker | 2026-10-04 |
| serper | `sample_cases_per_country` | Sample runs | in_use | 1 function(s) | 2026-10-04 |
| serper | `sample_concurrency` | Sample runs | in_use | worker | 2026-10-04 |
| serper | `sample_countries` | Sample runs | in_use | 3 function(s) | 2026-10-04 |
| serper | `sample_credits_per_run` | Sample runs | in_use | 3 function(s) | 2026-10-04 |
| serper | `sample_seconds_per_call` | Sample runs | in_use | worker | 2026-10-04 |
| serper | `title_match_min` | How the service is used | in_use | worker | 2026-10-04 |
| serper | `usd_per_1k_credits` | Key and plan limits | in_use | 1 function(s) | 2026-10-04 |

## 7. Evidence and proposed home, per section (round 4)

Asked for by the Platform Admin's review of 13 Nov 2026 22:10 (item 9). One row for each of the 78 (toolset, section) pairs of the live settings. **Nothing is moved, hidden or retired by this PR**: the last two columns are a proposal for the Platform Admin.

Evidence class of a setting (each setting is counted once, in the first class that applies):

- **direct read**: its full name is quoted in a live function, in a scheduled job command or in the worker.
- **dynamic read**: its name is not quoted in full, but live code builds it from parts or a policy row names it. Searched for on purpose: `'har.' || case || …` (72 settings), `'guard_' || lane` (5), `like 'enrich.%'` (3), `'website.' || … || '_display_approved'` (2), `'daily_share_' || …` (1), and names held in rows of `pipeline.ops_remedies` and `pipeline.work_recovery_policies` (22).
- **display only**: named only in the admin app (`src/`) or in a script: shown, but no reader found.
- **none found**: no reader of any kind.

Totals: direct read 1304, dynamic read 105, display only 1, none found 4 (1,414 settings). The method is a text search, with the limits stated under "How it was measured".

Proposed home: `operator` (stays on Settings for the people who run the pipeline), `models_services` (shown on Models & services), `engineering_default` (kept, shown under an engineering heading or read-only), `retire_review` (a decision to retire is due; nothing is retired here). Proposed sections per home: engineering_default 36, models_services 3, operator 32, retire_review 7. The split between `operator` and `engineering_default` is a first proposal by section name and content; it was not reviewed with the people who use the screen.

| Toolset | Section | Settings | direct read | dynamic read | display only | none found | Proposed home | Why, and exceptions |
|---|---|---:|---:|---:|---:|---:|---|---|
| `edge_functions` | Notices | 2 | 2 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `firecrawl` | Adapter builder | 7 | 7 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation; 4 to models_services |
| `firecrawl` | Adapter evaluation | 4 | 4 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `firecrawl` | Daily budget | 16 | 15 | 1 | 0 | 0 | operator | limits, switches and targets a person sets |
| `firecrawl` | Find pages | 14 | 14 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `firecrawl` | Notices | 1 | 1 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `firecrawl` | Read pages | 9 | 9 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `firecrawl` | Runs | 3 | 3 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `firecrawl` | Target universities | 7 | 7 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `openrouter` | Daily guards | 10 | 5 | 5 | 0 | 0 | models_services | every setting is about AI |
| `openrouter` | Notices | 3 | 3 | 0 | 0 | 0 | models_services | every setting is about AI |
| `pipeline` | AI answer limits | 14 | 14 | 0 | 0 | 0 | models_services | every setting is about AI |
| `pipeline` | AI evaluation | 18 | 18 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Admission | 4 | 2 | 2 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Admission checks | 13 | 13 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Alerts | 16 | 16 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Cost and yield | 22 | 20 | 2 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Course catalogue | 6 | 6 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Course description and deadline | 32 | 29 | 3 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation; 1 to models_services |
| `pipeline` | Course page search | 13 | 13 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Course pages | 31 | 31 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation; 1 to models_services |
| `pipeline` | Coverage reconciliation | 25 | 23 | 2 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Data delivery | 10 | 10 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | English policies | 6 | 6 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Enrichment | 66 | 64 | 2 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation; 1 to models_services |
| `pipeline` | Enrichment lanes | 5 | 5 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Entry requirements | 167 | 165 | 1 | 0 | 1 | engineering_default | reader tuning; changed with a release or an investigation; 21 to models_services, 1 to retire_review |
| `pipeline` | Field absence (D2, D3) | 3 | 3 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | First-run verification and progress | 25 | 24 | 0 | 0 | 1 | engineering_default | reader tuning; changed with a release or an investigation; 1 to retire_review |
| `pipeline` | Flags | 10 | 10 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Gap queue | 7 | 7 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Governed actions | 2 | 2 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Health report | 9 | 9 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Housekeeping | 13 | 12 | 0 | 1 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Human-assisted recovery | 92 | 20 | 72 | 0 | 0 | operator | limits, switches and targets a person sets; 5 to models_services |
| `pipeline` | Intake dates | 38 | 38 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation; 3 to models_services |
| `pipeline` | Integration queue | 18 | 18 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Job sizes | 79 | 79 | 0 | 0 | 0 | operator | limits, switches and targets a person sets; 6 to models_services |
| `pipeline` | Lane funnels | 12 | 12 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Layer 4 | 28 | 28 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Layer 4 readiness | 33 | 31 | 2 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Logos | 4 | 4 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Official link | 7 | 7 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | On demand | 1 | 1 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Onboarding | 31 | 31 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Operating targets | 7 | 7 | 0 | 0 | 0 | operator | limits, switches and targets a person sets; 1 to models_services |
| `pipeline` | Operations controller | 27 | 25 | 2 | 0 | 0 | operator | limits, switches and targets a person sets; 6 to models_services |
| `pipeline` | Platform upkeep | 83 | 80 | 3 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation; 1 to models_services |
| `pipeline` | Process results | 9 | 9 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Provider descriptions | 72 | 72 | 0 | 0 | 0 | operator | limits, switches and targets a person sets; 7 to models_services |
| `pipeline` | Provider descriptions › built-in prompt only | 4 | 4 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Re-read and retry | 32 | 32 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation; 1 to models_services |
| `pipeline` | Re-reads and retries | 4 | 4 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Register | 7 | 7 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Retention | 1 | 1 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Run now | 7 | 7 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Scholarship coverage recovery | 15 | 15 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Scholarship details | 4 | 4 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Scholarship discovery | 5 | 5 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Scholarship eligibility reader | 13 | 13 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Scholarship flow guard | 6 | 6 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Scholarships | 32 | 32 | 0 | 0 | 0 | operator | limits, switches and targets a person sets; 3 to models_services |
| `pipeline` | Source proof | 20 | 18 | 2 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Storage | 1 | 1 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `pipeline` | Storage & retention | 5 | 4 | 0 | 0 | 1 | operator | limits, switches and targets a person sets; 1 to retire_review |
| `pipeline` | Waste rules | 11 | 11 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Website API | 10 | 7 | 2 | 0 | 1 | operator | limits, switches and targets a person sets; 1 to retire_review |
| `pipeline` | Work continuity | 36 | 32 | 4 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Zero-yield pages | 13 | 13 | 0 | 0 | 0 | engineering_default | reader tuning; changed with a release or an investigation |
| `pipeline` | Zoho API | 13 | 13 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `scheduled_jobs` | Notices | 2 | 2 | 0 | 0 | 0 | operator | limits, switches and targets a person sets |
| `scrapingbee` | How the service is used | 4 | 4 | 0 | 0 | 0 | retire_review | vendor dropped 4 Oct 2026; screens already retiring |
| `scrapingbee` | Key and plan limits | 7 | 7 | 0 | 0 | 0 | retire_review | vendor dropped 4 Oct 2026; screens already retiring |
| `scrapingbee` | Sample runs | 5 | 5 | 0 | 0 | 0 | retire_review | vendor dropped 4 Oct 2026; screens already retiring |
| `serper` | How the service is used | 6 | 6 | 0 | 0 | 0 | retire_review | vendor dropped 4 Oct 2026; screens already retiring |
| `serper` | Key and plan limits | 7 | 7 | 0 | 0 | 0 | retire_review | vendor dropped 4 Oct 2026; screens already retiring |
| `serper` | Sample runs | 5 | 5 | 0 | 0 | 0 | retire_review | vendor dropped 4 Oct 2026; screens already retiring |
| `serper` | Search pass | 5 | 5 | 0 | 0 | 0 | retire_review | vendor dropped 4 Oct 2026; screens already retiring |

### The existing `control_class` column

`pipeline.platform_toolset_settings.control_class` exists already (live: 1,335 empty, 54 `automatic`, 25 `human`; one reader, `admin_settings_register_read`). Its check allows only `human`, `automatic` and `retiring`. This PR does **not** reuse it for the home of a setting: the four homes above do not fit the three values, and widening the check means dropping and re-adding a constraint on a table every job reads (a drop goes to the Platform Admin as a paste file). `home` and `home_group` (migration 20261113378000) stay beside it. The two are consistent in meaning and can be brought together in one later, approved change: `operator` is `human`, `engineering_default` is `automatic`, `retire_review` is `retiring`, and `models_services` is a place, not a class (its settings are `human`).
