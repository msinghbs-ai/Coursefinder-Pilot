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

### 1.6 Last modified

`catalogue.courses.updated_at`. There is no trigger on `catalogue.courses` that stamps it; every writer read sets `updated_at = now()` in the same `update … where <value empty or different>` that writes the value, so an unchanged update does not move it. Limitation recorded: the largest single minute is 3 Nov 2026 02:23 UTC (11,149 courses), the course-description admission (`20261103110000`, a real write of empty descriptions). The record carries no history table, so Last modified is the record's own persisted stamp and nothing is inferred beyond it.

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
- `security.course_last_admitted_at_v1(uuid)` and `security.course_adapter_state_v1(uuid, uuid)`: inlinable SQL used both for the sort and the shown value, so the order always matches what is shown.

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

**Indexes** (pipeline ledgers, for the Last data admitted sort over the whole filtered set): `adapter_overwrite_changes (course_id, at desc)`, `course_intake_date_events (course_id, run_at desc) where outcome = 'filled'`, `layer4_admission_checks (entity_id, decided_at desc) where admitted`, `field_enrich_items (course_id, updated_at desc) where state = 'filled'`.

### 2.2 Column registry (screen `courses`)

Default layout = the 11 columns shown today, in today's order, then Adapter status, Last modified and Last data admitted.

| Group | Key | Label | Server sort | Default |
|---|---|---|---|---|
| Identity | `canonical_title` | Course (always shown) | course | yes |
| Identity | `display_code` | Course code / CRICOS | – | yes |
| Identity | `provider_name` | Provider | provider | yes |
| Identity | `country_name` | Country | – | |
| Identity | `subdivision_name` | State / Region | – | yes |
| Identity | `city_names` | City | city | yes |
| Identity | `campus_count` | Campus | – | |
| Identity | `level_name` | Study level | – | yes |
| Identity | `field_of_study` | Study area | field | yes |
| Course information | `duration` | Duration | – | |
| Course information | `delivery_mode` | Delivery mode | – | |
| Course information | `intl_fee_amount` | International fee | intl_fee | yes |
| Course information | `fee_amount` | Tuition (registered) | fee | yes |
| Course information | `intl_fee_year` | Fee year | – | |
| Course information | `intakes` | Intakes | – | |
| Course information | `deadline` | Application deadline | – | |
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
| Pipeline and enrichment | `last_verified_at` | Evidence last verified | verified | yes |
| Pipeline and enrichment | `layer4_status` | Layer 4 | – | |
| Pipeline and enrichment | `enrichment_status` | Enrichment | – | |
| Pipeline and enrichment | `last_admitted_field` | Last successful field admission | – | |
| Lifecycle and timestamps | `created_at` | Created | – | |
| Lifecycle and timestamps | `last_modified_at` | Last modified | modified | yes |
| Lifecycle and timestamps | `last_admitted_at` | Last data admitted | admitted | yes |
| Lifecycle and timestamps | `lifecycle_status` | Lifecycle status | – | |
| Lifecycle and timestamps | `publication_status` | Publication | – | |

Not offered (mandate §2 "expose only fields supported by existing verified data contracts"):

- **Intake month, Intake year, Exact commencement date.** The list projection has no verified per-course month, year or date contract. The Intakes column shows the field state; the dates stay on the course blade.
- **Last source update.** No record says when a source page's content changed: a read time is not a source update.
- **Last published.** `search.course_documents` is rewritten by every search refresh, so its time would show a catalogue refresh as a publication.

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

- A Columns control above the table: search, the four groups with a count ("14 of 36 shown"), tick to show and untick to hide, move up/down buttons (keyboard) for order, Reset to default, Restore last saved, and a "Saved" acknowledgement with the time.
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
| **Protects** | Course lifecycle processing, adapters and enrichment (read only: nothing written to their tables); search and index refresh (not touched); manual locks and admission controls (not read for writing, never changed); filters and paging (same arguments, same rows, same order for existing sort keys); existing personal settings (localStorage never removed or overwritten); the consumer API (no `website_*`, `zoho_*`, `api.*` function, edge function or consumer table column is touched; the new objects are admin-only). Background automation plans and admission authority are unchanged. |
| **Validates** | §4 below. |

## 4. Tests

Recorded as each milestone lands (CC-2).
