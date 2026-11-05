# Course Catalogue: customisable columns, per-user layouts and data freshness

| Item | Value |
|---|---|
| Mandate | Platform Admin, 5 Nov 2026 17:31 (admin `docs/platform/2026-11-05-course-catalogue-columns-freshness-1731.md`, verbatim) |
| Allocation | Platform Admin decision 5 Nov 2026 19:14 §3 (agent C, Course Catalogue UI) |
| Work package | admin `docs/platform/work-packages/2026-11-05-course-catalogue-columns-codex.md` |
| Branch | `cf247-course-catalogue-columns`, cut from `main` at cf77ef78 (v2.15.485) |
| Migration versions | `20261106300000`–`20261106399999` (this change uses `20261106300000`) |
| Release | none until integration; engineering hold in force |

This file is the CC-1 audit and contract, the automation compatibility record and the test record. It is updated as each milestone lands.

## 1. Audit (mandate §1), verified 5 Nov 2026 19:17–19:35 AEDT

All production facts below were read read-only from project `fxcwkweaxjtknorudmwp` with catalogue reads (no heavy reads).

### 1.1 Work package §2 starting facts

| Work package fact | Verified | Correction or detail |
|---|---|---|
| Catalogue is `src/mature-main.jsx`, page `courses`, fixed 11 columns from `columns('course', …)` | Confirmed | `Catalogue` (line 656) renders `DataTable` (a wrapper of the shared `src/DataTable.jsx`) with `columns(type)` (line 768). |
| Data comes from `admin_read('courses_page')`, last replaced by `20261030190000` (page-first) | Confirmed, with detail | `public.admin_read` (live md5 `6b1bb9d569bd13390f76803f9a710053`) routes `courses_page` to `security.admin_course_page_fast(jsonb)` (live md5 `2dc6ee8ba523afeec04d862f3a2ced8a`). That function sends the plain first page (no filter, sort `course` ascending) to `security.admin_course_page_unfiltered_fast(jsonb)` (`5db669272a3fa612b1268ef8502a9b7c`) and everything else to `security.admin_course_page_fast_base(jsonb)` (`afbef16111a09e3680061547bbb1329a`; this is the definition as left by W34). `fee` and `completeness` sorts go on to the legacy `public.ui_courses_decision_page` through `security.admin_course_page_search_state(jsonb)` (`9d323993cdaca3297efef09e72b0f440`). |
| Existing sort keys: course, provider, city, field, intl_fee, fee, completeness, verified | Corrected | `modified` (on `catalogue.courses.updated_at`) also exists in `fast_base`; the UI has no column for it. |
| Saved state: `useRememberedState` (localStorage, per user) and `useColumnWidths` (`cf-colw:<table>`) | Confirmed | Key `coursefinder:pim:screen-state:v1:<user>:course` (query, filters, filter labels, advanced, sort, direction); widths in `cf-colw:course`. Browser only. |
| No server-side per-user preference store | Confirmed | No table in any schema matches a per-user preference, view, layout or saved state. |
| Provider list Adapter cell from `admin_adapter_autobuild('states')` | Confirmed | Provider-level, rank 5 and above (live md5 `e65b54a01d66ba1247bed20f6e80c4bb`), built on `security.adapter_autobuild_state_v1(uuid)`: `pipeline.uni_adapters` (enabled, admit) and `pipeline.adapter_autobuilds` (no rows today). There is no course-level equivalent; this change adds one inside the page projection. |
| City from `city_names` with sort key `city` | Confirmed: campuses, not the provider headquarters | `string_agg(distinct ca.city)` over `catalogue.course_campuses` → `catalogue.campuses`. The provider's `primary_city` is never read. State/region falls back to the provider's subdivision only for the State column (`region_source = 'provider'`), never for City. |

### 1.2 Search, filters, paging and sorting

- Search (title, display title, provider, course code, stable key, StudySearch code), 18 filters, `limit`/`offset` paging (page size 50 in the UI), and sorting run inside `fast_base` on the whole filtered set, then the page's 50 ids are read in full ("page first", W34).
- The UI passes `lifecycle_status = 'active'` unless Status is chosen, so the unfiltered path is used only when "any status" and no other filter is chosen.

### 1.3 Field values and field-state definitions

- Values: `catalogue.courses` and its child tables (`course_fees`, `course_intakes`, `course_english_requirements`, `course_entry_requirements`, `course_links`, `course_campuses`, `course_registrations`, `course_identifiers`), already projected by `fast_base`.
- Field states: `pipeline.course_attribute_coverage` (primary key `course_id, attribute`; built by the hourly coverage build) gives each course attribute a pipeline state (`admitted`, `candidate`, `in_review`, `awaiting_l3`, `in_queue`, `not_on_page`, `blocked`, `page_found`, `site_known`, `no_website`, `missing_l1`, `no_reader`) and an absence class from `pipeline.field_absence_classes`. Attributes: official_url, provider_tuition, registered_tuition, fee, english, intakes, deadline, academic_entry, description, duration, level, delivery, field_of_study, campus, campus_city, international. These are the definitions Coverage › Courses already shows (`src/course-coverage.jsx`).
- Held by validation: `pipeline.enrichment_flags` rows for the course (`entity = 'course'`, `entity_key = course id`, `state = 'raised'`).

### 1.4 Adapter lifecycle and results

- Provider adapter: `pipeline.uni_adapters` (1,191 rows: 827 admitting, 361 testing, 3 switched off).
- Course page and its read: `pipeline.coverage_course_pages` (primary key `course_id`; `status` bound/ambiguous/mismatch, `read_status`, `read_at`, `leased_until`, `evidence_id`, `identity_basis`).
- Adapter result per course: `pipeline.uni_adapter_results` (21,869 rows; index `course_id, at desc`; `before_read_status`, `identity`, `how`, `fields`).

### 1.5 Admission and audit records (the authoritative "admitted" events)

Each is written only when a value actually reached the catalogue (read from the live writer functions):

| Source | Admission row | Timestamp | Why it is an admission |
|---|---|---|---|
| Enrich fields / AI reader / adapter / rules | `pipeline.field_enrich_items` with `state = 'filled'` | `updated_at` | `security.enrich_apply_v1` and the record functions set `filled` only when the catalogue write changed a row (`get diagnostics row_count > 0`); otherwise `skipped` ("already filled", "locked by hand"). Items later retracted (`pipeline.enrich_value_retractions`, `cleared`) are excluded. |
| Adapter overwrite | `pipeline.adapter_overwrite_changes` where `before` differs from `after` | `at` | Written by `security.adapter_overwrite_v1`, `exit_awards_apply_v1/_v2`, `provider_credit_fee_apply_v1` when an adapter value replaced a held one. |
| Layer 2 field admission | `pipeline.layer2_field_admissions` with `status = 'admitted'` and `canonical_changed` | `decided_at` | `unchanged` rows (149) are excluded. |
| Layer 4 approvals | `pipeline.layer4_admission_checks` with `entity_type = 'course'` and `admitted` | `decided_at` | The check confirms the approved value is in the catalogue. |
| Intake dates | `pipeline.course_intake_date_events` with `outcome = 'filled'` | `run_at` | `skipped` and `withdrawn` are not admissions. |
| Authorised manual values | `pipeline.manual_edit_log` with `entity = 'course'` and `action` `set_official_url` or `set_tuition` | `at` | A person set the value; archive, release and removals are not admissions. |

Not used: scheduled reads (`coverage_course_pages.read_at`, `uni_adapter_results.at`), proposals and review items, `skipped`/`failed`/`review` items, retracted values, search projection refreshes (`search.course_documents.updated_at`), and the hourly coverage build (`computed_at`).

### 1.6 Last modified ("Course record updated (as recorded)")

`catalogue.courses.updated_at`, shown as "Course record updated (as recorded)" with a tooltip saying it is the course record itself as its writers recorded it. There is no trigger on `catalogue.courses` that stamps it (only `manual_lock_guard`), so it depends on each writer setting it. None is added: Zoho and website consumers may filter on `updated_at`, and changing its meaning would touch the frozen consumer API (Integration Controller, CC-3 review).

Measured read-only on production (5 Nov 2026 20:16 AEDT). For every course whose fields held on the course record itself were admitted, the latest admission per course and field was compared with `updated_at`:

| Admitted field (writer) | Courses | `updated_at` at or after the admission | Older than the admission |
|---|---|---|---|
| Delivery (adapter overwrite) | 12,170 | 12,170 | 0 |
| Field of study (Enrich fields) | 11,218 | 11,218 | 0 |
| Delivery (Enrich fields) | 10,922 | 10,922 | 0 |
| International (Enrich fields) | 7,964 | 7,964 | 0 |
| Duration (Enrich fields) | 4,071 | 4,071 | 0 |
| Level (Enrich fields) | 400 | 400 | 0 |

46,745 of 46,745 (100%): every recorded writer of the course record stamps it. Limits that stay: a write with no admission record cannot be checked this way; bulk real writes count (for example the 3 Nov 2026 description admission, 11,149 courses in one minute); values held in other tables (fees, intakes, English) never move it. 1,911 active courses have an admission after their record's last update for that reason, so Last data admitted is the column for "what changed recently".

### 1.7 Mobile and performance constraints

- The Course catalogue list is an `s121` phone screen: no sideways page scroll; the table scrolls in its own frame (`.m-table-wrap`).
- `courses_page` budget: 3,000 ms under load (W34); production volume: 35,668 courses matched in W34, `catalogue.courses` estimate 44,391 rows.

## 2. Contract (CC-1)

### 2.1 Database (migration `20261106300000_cf247_course_catalogue_columns.sql`)

Additive only, beside the consumer API (G3): new tables and functions in `pipeline`, `security` and `public.admin_*`; partial indexes on four `pipeline` ledgers; two `security` functions edited by exact, md5-guarded text edits. Nothing dropped, deleted or renamed.

**Settings** (toolset `pipeline`, section "Course catalogue", read with `security.pipeline_num_v1`):

| Key | Label | Default | Range | Unit |
|---|---|---|---|---|
| `catalogue_layout.max_bytes` | Saved table layout: largest size | 16000 | 2000–64000 | bytes |
| `catalogue_layout.max_columns` | Saved table layout: most columns shown | 60 | 5–100 | columns |
| `catalogue_layout.width_min_px` | Saved table layout: narrowest column | 64 | 40–200 | pixels |
| `catalogue_layout.width_max_px` | Saved table layout: widest column | 1200 | 300–2400 | pixels |

**Tables**

- `pipeline.admin_table_columns` — the column registry: `screen`, `key`, `grp`, `label`, `sort` (order), `sort_key` (server sort key or null), `default_visible`, `default_width`, `min_width`, `always_visible`, `active`. Primary key (`screen`, `key`). The UI registry (`src/catalogue-columns.js`) must equal it (spec-checked).
- `pipeline.admin_table_layouts` — one saved layout per person and screen: `user_id uuid` (= `auth.uid()`, foreign key to `auth.users`), `screen`, `layout jsonb` (null after Reset), `previous jsonb` (the layout before the last save or reset, for "Restore last saved"), `saved_at`, `reset_at`, `save_count`. Primary key (`user_id`, `screen`). RLS on; a select policy for the owner only; no grants to `anon`; writes only through the RPC.

**RPC** `public.admin_table_layout(p_action text, p_args jsonb) returns jsonb`, SECURITY DEFINER, `search_path` set, executable by `authenticated` only:

| Action | Args | Effect |
|---|---|---|
| `read` | `screen` | The caller's layout, previous layout, saved time, the registry and the four limits |
| `save` | `screen`, `layout` | Validates, keeps the old layout as `previous`, stores the new one; returns `saved_at` |
| `reset` | `screen` | Keeps the layout as `previous`, sets the layout to null (the default applies) |
| `restore` | `screen` | Swaps the layout and `previous` (Restore last saved) |

Every action needs `auth.uid()` and an assigned role (rank 1, Viewer, or above). The row is always the caller's own (`user_id = auth.uid()`): no argument names a user. A Viewer can save only their own layout; nothing else changes.

Layout validation: an object with only `version`, `columns`, `widths`, `sort`, `direction`; `columns` distinct registry keys of the screen, at most `max_columns`, always containing the always-visible keys; `widths` registry keys mapped to whole pixels within the width limits (and not below the column's own minimum); `sort` a registry sort key or null; `direction` `asc`/`desc`; the whole layout at most `max_bytes`. A refused layout raises `22023` with the reason.

**`courses_page`, additive** (`security.admin_course_page_fast` and `security.admin_course_page_fast_base`, edited by exact text edits after their live md5s are confirmed):

- New sort keys `admitted` (Last data admitted) and `adapter` (Adapter status) in `fast_base`'s ordered id list, beside the existing ones. `modified` keeps sorting on `updated_at`. Unknown timestamps sort last in both directions. Existing keys and their order are unchanged.
- Every page (unfiltered, filtered, and the `fee`/`completeness` path) gets its items merged with `security.course_list_extras_v1(uuid[])`: one set-based read over the page's ids (at most the page limit), never per course from the browser.
- New item fields: `last_modified_at`, `last_admitted` (`at`, `field`, `source`, `evidence_id`, `before`, `after`, `rule`), `last_admitted_at`, `adapter` (`state`, `reason`, `last_read_at`, `result`, `provider_adapter`), `cities` (array of `campus`, `city`, `subdivision_code`, `subdivision_name`, `country_code`), `page` (`stored`, `status`, `read_status`, `identity`, `read_at`, `evidence_id`), `field_states` (attribute → `state`, `raw`, `reason`), `layer4_open`, `enrichment` (filled, review, failed counts), `duration_unit`. Existing fields are unchanged.
- One definition each, used by the shown value and by the sort, so the order always matches what is shown: `security.course_admissions_v1()` (every admission row from the ledgers in §1.5) and `security.course_adapter_state_from_v1(...)` (the status rule from its inputs). The page reads them for its own ids; the sort reads them set-based over the whole filtered set (one aggregate of the admission ledgers, one join of the adapter tables), never once per course. This replaced a first per-course version after CI on PostgreSQL 17 measured 2.5 s for that sort.

**Adapter status (course)**, in this order:

| Status | Rule |
|---|---|
| Not configured | The provider has no `pipeline.uni_adapters` row |
| Processing | The course page is being read now (`coverage_course_pages.leased_until` in the future) |
| Held | The adapter is switched off or testing (not admitting), or the course has no bound course page to read |
| Failed | The latest adapter result or the page read did not read (`before_read_status` / `read_status` other than `read`, e.g. identity mismatch, fetch failed, blocked) |
| Completed | An adapter result exists for this course and the page read succeeded |
| Ready | Admitting adapter, bound page, no result yet |

Completed is never inferred from an adapter existing: it needs a result row for the course. Sorting by Adapter orders Failed, Held, Processing, Ready, Completed, Not configured (attention first) ascending.

**Indexes** (pipeline ledgers, so the page's own admission lookups stay indexed): `adapter_overwrite_changes (course_id, at desc)`, `course_intake_date_events (course_id, run_at desc) where outcome = 'filled'`, `layer4_admission_checks (entity_id, decided_at desc) where admitted`, `field_enrich_items (course_id, updated_at desc) where state = 'filled'`.

### 2.2 Column registry (screen `courses`)

Default layout = the 11 columns shown today, in today's order, keys and headings (so widths a person set in this browser still apply and existing tests keep passing), with Adapter status before Verified, then Last modified and Last data admitted. The picker shows the mandate's names; the table keeps today's headings where they differ.

| Group | Key | Label | Server sort | Default |
|---|---|---|---|---|
| Identity | `canonical_title` | Course (always shown) | course | yes |
| Identity | `course_code` | Course code / CRICOS (heading: Course code) | – | yes |
| Identity | `provider_name` | Provider | provider | yes |
| Identity | `country_name` | Country | – | |
| Identity | `subdivision_name` | State / Region | – | yes |
| Identity | `city_names` | City | city | yes |
| Identity | `campus_count` | Campus | – | |
| Identity | `level_name` | Study level | – | yes |
| Identity | `field_of_study` | Study area (heading: Field) | field | yes |
| Course information | `duration` | Duration | – | |
| Course information | `delivery_mode` | Delivery mode | – | |
| Course information | `intl_fee_amount` | International fee | intl_fee | yes |
| Course information | `fee_amount` | Tuition (registered, CRICOS) (heading: Tuition Only; Australian lists only, as today) | fee | yes |
| Course information | `intl_fee_year` | Fee year | – | |
| Course information | `intakes` | Intakes ("Feb 2027 +1", expands to every intake with its start and deadline) | – | |
| Course information | `intake_month` | Intake month | – | |
| Course information | `intake_year` | Intake year | – | |
| Course information | `commencement_date` | Exact commencement date | – | |
| Course information | `deadline` | Application deadline (dates held, else Rolling, else the field state) | – | |
| Course information | `english` | English requirements | – | |
| Course information | `academic_entry` | Academic entry requirements | – | |
| Course information | `has_scholarship` | Scholarships | – | |
| Course information | `description` | Course description | – | |
| Course information | `official_url` | Official course URL | – | |
| Course information | `completeness_score_v2` | Completeness | completeness | yes |
| Pipeline and enrichment | `adapter_state` | Adapter status | adapter | yes |
| Pipeline and enrichment | `adapter_last_read_at` | Adapter last read | – | |
| Pipeline and enrichment | `adapter_result` | Adapter result | – | |
| Pipeline and enrichment | `page_stored` | Stored course page | – | |
| Pipeline and enrichment | `source_identity` | Source identity | – | |
| Pipeline and enrichment | `last_verified_at` | Evidence last verified (heading: Verified) | verified | yes |
| Pipeline and enrichment | `layer4_status` | Layer 4 | – | |
| Pipeline and enrichment | `enrichment_status` | Enrichment | – | |
| Pipeline and enrichment | `last_admitted_field` | Last successful field admission | – | |
| Lifecycle and timestamps | `created_at` | Created | – | |
| Lifecycle and timestamps | `last_modified_at` | Course record updated (as recorded) | modified | yes |
| Lifecycle and timestamps | `last_admitted_at` | Last data admitted | admitted | yes |
| Lifecycle and timestamps | `last_published_at` | Last published (website feed) | – | |
| Lifecycle and timestamps | `lifecycle_status` | Lifecycle status | – | |
| Lifecycle and timestamps | `publication_status` | Publication | – | |

Intakes (Integration Controller CC-3 review, 5 Nov 2026): the four intake columns read the active `catalogue.course_intakes` rows, which are the rows the website's `intake_options` are built from (`api.website_v2_course_item` returns label, month, year, start date and deadline). The month is taken from the start date, else from the label by the website's own rule (`api.website_v2_label_month`, read only), so the screen and the website name the same month. Start dates are held only where the intake-dates job read an exact day (`pipeline.course_intake_dates.start_precision = 'day'` for every filled start in production: 523 of 31,828 active intakes). A rolling deadline shows "Rolling" from that job's record. Nothing is filled in: no month, year or date shows "Not held"; a course with no intake shows its field state. Production, read only: 31,828 active intakes; 1,185 with a year, 523 with a start date, 782 with a deadline.

Last published: `pipeline.website_sync_items` (and `zoho_sync_items`) keep one item per course in each feed, and `seq_at` moves only when the item is new, its content hash changed or it was withdrawn (`security.website_sync_check_v1`; an unchanged re-check and the freshness timestamps do not count). That is a truthful "last published change", so the column shows the website feed's time and the tooltip the Zoho feed's; "Withdrawn" when the item was removed; "Not in the website feed" when there is none. Read only, by one aggregate over the page's ids. `pipeline.course_intake_date_events.publication_state` was considered and not used: it records whether one intake value reached the search projection, not when the course was published.

Not offered (mandate §2 "expose only fields supported by existing verified data contracts"):

- **Last source update.** No record says when a source page's content changed: a read time is not a source update.

### 2.3 Field-state display (mandate §7)

From `course_attribute_coverage` and `enrichment_flags`, computed in the projection:

| Shown | Rule |
|---|---|
| Populated | coverage state `admitted` |
| Held by validation | an open (`raised`) flag on the course field |
| Waiting for review | `in_review` |
| Pending extraction | `candidate`, `awaiting_l3`, `in_queue`, `page_found` |
| Failed | `blocked` |
| Not applicable | absence class `not_applicable` |
| Missing | any other state (`not_on_page`, `site_known`, `no_website`, `missing_l1`, `no_reader`), with the existing label as the reason |
| Unknown | no coverage row for the course and attribute (never shown as zero or "No") |

### 2.4 Frontend

- A Columns control above the table: search, the four groups with a count ("14 of 36"), tick to show and untick to hide, Move left / Move right buttons for order (keyboard: Tab and Enter; focus stays on the moved column), Reset to default, Restore last saved, and an acknowledgement ("Layout saved to your account at 19:45", or "Saved in this browser only" when the server cannot be reached).
- `DataTable` gains optional, backward-compatible props: an external widths source, a per-column minimum width, keyboard resizing (arrow keys on the resize handle), a sticky header and a visible active-sort indicator. Other lists are unchanged (the defaults keep today's behaviour).
- Layout source order: the server layout when it loads; otherwise the existing localStorage (`cf-colw:course`, `useRememberedState`) as the offline fallback. localStorage is read and still written, never cleared or overwritten with a server value of another person.
- Row click, search, filters, paging and the CRICOS fee rule are unchanged.

## 3. Automation compatibility record

| | Assessment |
|---|---|
| **Reuses** | `admin_read('courses_page')` and its page-first functions; `DataTable`, `useRememberedState`, `useColumnWidths`, `StatusChip`, `Pager`; the coverage field states (`course_attribute_coverage`, `field_absence_classes`); the adapter tables (`uni_adapters`, `uni_adapter_results`, `coverage_course_pages`); the admission ledgers in §1.5; `security.current_role_rank`, `security.pipeline_num_v1`; the existing adapter detail route (Layer 2 › Adapter builder). |
| **Changes** | `security.admin_course_page_fast` (merges the page extras into every path) and `security.admin_course_page_fast_base` (two new sort keys), each by exact text edits after its live md5 is confirmed; `src/mature-main.jsx` course list; `src/DataTable.jsx` (optional props only). |
| **Replaces** | Nothing. The browser-only layout stays as the fallback. |
| **Retires** | Nothing. |
| **Conflicts** | None found. No other agent owns these functions or files (ownership table 19:14). No scheduler, reader, controller or dashboard is added. |
| **Protects** | Course lifecycle processing, adapters and enrichment (read only: nothing written to their tables); search and index refresh (not touched); manual locks and admission controls (not read for writing, never changed); filters and paging (same arguments, same rows, same order for existing sort keys); existing personal settings (localStorage never removed or overwritten); the consumer API (no `website_*`, `zoho_*`, `api.*` function, edge function or consumer table column is touched; the new objects are admin-only; `api.website_v2_label_month`, `pipeline.website_sync_items` and `zoho_sync_items` are only read, and no index is added to them; `catalogue.courses.updated_at` keeps its meaning, no trigger is added). Background automation plans and admission authority are unchanged. |
| **Validates** | §4 below. |

## 4. Tests and evidence (CC-2)

### 4.1 Isolated PostgreSQL fixture (`tests/fixtures/course-catalogue-columns/run.sh`, workflow `course-catalogue-columns-test.yml`)

| Step | Result (local run 5 Nov 2026, PostgreSQL 16) |
|---|---|
| Production-schema parity: 42 tables (columns and types, not-null, constraints, every foreign key, indexes, triggers, RLS, policies, grants) fingerprinted with `parity.sql` and compared with `production-parity.txt` (read from production 19:30 AEDT) | identical, table by table |
| The 9 live definitions the change reads or edits rebuilt byte for byte (with the website's month rule) | md5 = production for all 9 |
| Production-volume data through the production constraints | 35,712 courses, 1,203 providers, 171,004 field items, 34,000 overwrites, 214,206 field states |
| Migration applied, then applied again | second run reports both edits already applied; definitions and rows unchanged |
| Backward compatibility: 13 argument sets the screen sends, before and after (same rows, same order, every existing field equal, same total and metadata) | 13 PASS |
| Database cases (layouts, roles, refusals, cities, adapter status, timestamps, intakes, feeds, field states, server-side sort across pages) | 56 PASS |
| Index builds, each timed and rolled back before the migration, at production volume | `field_enrich_items` (171,004 rows) 24–28 ms; `adapter_overwrite_changes` (34,001) 17–23 ms; `layer4_admission_checks` 3 ms; `course_intake_date_events` 2 ms |
| Benchmark, as a signed-in person, three runs each (middle shown) | course 77 ms; Last data admitted 124 ms (offset 17,000: 143 ms; 200 rows: 176 ms); Adapter 242 ms; Last modified 68 ms; Provider 72 ms; City 1,881 ms (existing sort, unchanged); with the Victoria state filter: Last data admitted 2,234 ms against 1,927 ms for today's course sort with the same filter (the state filter is today's cost). All under the 3,000 ms budget. The first, per-course version measured 891 ms locally and 2,488 ms in CI (PostgreSQL 17); it was replaced by the set-based sort. |

### 4.2 Browser to PostgreSQL (`tests/integration/course-columns-postgres.spec.mjs`, real Admin UI, desktop and phone)

| Mandate §10 case | Test | Result |
|---|---|---|
| 1 show and hide, 2 persist, 3 restore after sign-out and sign-in, 5 reorder and resize | show, hide, keyboard reorder and keyboard resize saved; a new browser context (no local storage) for the same person gets the same layout and width back | PASS |
| 4 reset to default | Reset, then Restore last saved | PASS |
| 6 server-side sort across pages, 9, 10 | Last data admitted oldest first and newest first over 34,832 active courses; page 2 continues page 1; sort kept with the layout | PASS |
| 7 multiple cities, 8 adapter status, 9 modified versus admitted, 10 no fabricated timestamps | Melbourne (VIC) +2 expanding to Richmond (NSW) and Richmond (VIC), no Geelong; Processing, Completed, Failed, Ready, Held, Not configured; 4 Nov record update against 1 Oct admitted; Unknown; intakes "Feb 2027 +1" expanding with start and deadline, month, year, exact start, deadline; Last published from the website feed, Withdrawn, Not in the website feed | PASS |
| 12 read-only roles and permission boundaries | a Viewer saves its own layout; the Platform Admin's layout is untouched and the other way round | PASS |
| 11 search, filters, paging, 15 backward compatibility | 697 pages, Next and Previous, CRICOS code search, provider sort, row click opens the course | PASS |
| 14 performance with many columns | all 36 columns shown, Last data admitted sort round trip under 3,000 ms, 50 rows | PASS |
| 13 desktop and phone | phone (412 px): Columns panel inside the screen, the table scrolls in its own frame, no sideways page scroll, course title at least 160 px | PASS |

Database refusals proven in 4.1: unknown column, hidden course title, width under the column minimum, duplicate column, unknown sort, layout over the size setting, extra keys, unknown screen, no role (42501), no session (42501), anon cannot execute, the table cannot be read directly.

### 4.3 Repository specs (local, `pw-5291.config.mjs`)

- New `tests/uat/cf-247-course-catalogue-columns-contract.spec.mjs` (Guards: the mandate): registry equals the migration's, default layout, layout normalising, Columns control, saved acknowledgement, server-unavailable fallback, and an `@responsive` phone test. 7 PASS.
- Governance: `s32`, `s42`, `s57`, `s120`, `s121` PASS.
- Course-list specs that could be affected (`s87`, `s91`, `s96`, `s103`, record editing, NZ coverage, fee views, UI standard stage 1 and contract, `s121`): 93 PASS.
- `vite build` passes.

### 4.4 Production read-only preview (5 Nov 2026, inside the heavy-read window)

Both rules run read-only on production, each a single SELECT in the heavy-read window. No production object or session setting was created or changed.

- Adapter status over 35,690 active courses: Completed 18,756, Failed 7,186, Held 4,360, Not configured 3,527, Ready 1,861 (no course was processing at that minute).
- Last data admitted (20:06 AEDT): 27,242 active courses have an admission record and 8,448 show Unknown. Admissions run from 4 Oct 2026 to 5 Nov 2026 08:26 UTC. 1,911 courses were admitted after their course record last changed: admissions to fees, intakes or English write the child tables, not `catalogue.courses`. The two timestamps are different facts, as the mandate requires.

## 5. Open points for the Integration Controller

- `docs/platform/TEST-REGISTER.md` was regenerated from a partial local run (agents do not run the full suite), so statuses outside this change read "not run"; the Controller regenerates it after the full run at integration, as the ownership rules say.
- At release: re-read the two edited functions' md5s (`2dc6ee8ba523afeec04d862f3a2ced8a`, `afbef16111a09e3680061547bbb1329a`); the migration refuses to apply if either changed.
- Index locks: each build holds its table's write lock only while it runs; measured above at under 30 ms, so `CREATE INDEX CONCURRENTLY` (a separate paste file run before the migration) is not needed. The real risk is waiting for a writer already holding the table, so the migration sets `lock_timeout` to 5 s (marked `-- fixed:`): a busy minute fails the migration cleanly and it is applied again. Deploy window: the writers of these tables run at :00/:05 (enrich-plan-run), :x3 (coverage-admit), :x5 (coverage-admit-intakes), :x9 (adapter-overwrite), :23 (field-gap-queue), :24/:54 (ops-controller), :26 (intake-dates-apply) and :41 (enrich-plan-auto); apply at :11–:12 or :31–:32, never at :26 or the :x6 heavy minutes.
- Last modified is `catalogue.courses.updated_at`, the course record itself; a value written only to a child table (fee, intake, English) shows in Last data admitted, not in Last modified. There is no change history for the course record, so it shows the record's own persisted stamp: bulk real writes (for example the 3 Nov 2026 description admission on 11,149 courses) show as modifications.
