-- CF-247 Course Catalogue: customisable columns, per-user layouts and data freshness.
-- Platform Admin mandate 5 Nov 2026 17:31 (admin docs/platform/2026-11-05-course-catalogue-columns-freshness-1731.md); allocated to agent C by the
-- Platform Admin decision 5 Nov 2026 19:14 §3. Contract and compatibility record: docs/course-catalogue-columns.md (this repository).
-- What:
--   1. Six settings (toolset pipeline, section "Course catalogue"): four bound a saved table layout (size, columns, narrowest and widest column);
--      two are recovery switches (server layouts on or off; the two new sorts offered or not). Both start on; switching off deletes nothing.
--   2. pipeline.admin_table_columns: the column registry a saved layout is checked against (the Course catalogue's 40 columns).
--   3. pipeline.admin_table_layouts: one saved layout per person and screen (visible columns, order, widths, sort, direction), with the layout
--      before the last save or reset kept for "Restore last saved". RLS on, no grants: read and written only by public.admin_table_layout, which
--      always acts on the caller's own row (user_id = auth.uid()); any assigned role (Viewer and above) may save its own layout.
--   4. courses_page, additive: every page gets the course's Adapter status, Last modified, Last data admitted (with the field, source, evidence,
--      before and after), campus cities with state and country, stored page, field states, open Layer 4 items and enrichment counts, read by one
--      set-based query over the page's ids (security.course_list_extras_v1), the course's intakes as the website builds them (month, year,
--      start date, deadline), and when its item last changed in the website and Zoho feeds (pipeline.website_sync_items, zoho_sync_items;
--      read only). Two new sort keys over the whole filtered set: admitted, adapter.
--      Existing fields, sort keys, filters, paging and totals are unchanged.
--   5. The two new sorts run set-based over the filtered set (one aggregate of the admission ledgers, one join of the adapter tables), never
--      per course; four indexes on pipeline ledgers keep the page's own lookups indexed.
-- Last data admitted comes only from rows that record a value reaching the catalogue (field_enrich_items filled and not retracted; adapter overwrites
-- that changed the value; Layer 2 admissions that changed the canonical value; Layer 4 approvals confirmed admitted; intake dates filled; manual
-- official page or tuition set). Scheduled reads, proposals, review items, skipped or failed items, search refreshes and coverage builds are never
-- admissions. With no such row the value is null and the screen shows Unknown.
-- Live definitions edited here (read read-only 5 Nov 2026 19:17 AEDT): security.admin_course_page_fast(jsonb) md5 2dc6ee8ba523afeec04d862f3a2ced8a,
-- security.admin_course_page_fast_base(jsonb) md5 afbef16111a09e3680061547bbb1329a. Each is edited by exact text replacements that must apply the
-- stated number of times; a second run finds the edits already in place and changes nothing. public.admin_read is not edited (md5
-- 6b1bb9d569bd13390f76803f9a710053): it already routes courses_page to admin_course_page_fast.
-- Consumer API (G3): not touched. No website_*, zoho_*, api.* function, consumer edge function or consumer table column is created, altered or
-- dropped; the new objects are admin-only and the indexes are on pipeline ledgers.
-- Background automation, admission authority and manual locks are unchanged: nothing here writes a catalogue or pipeline ledger table.
-- Replaces: nothing (the browser-only layout in localStorage stays as the offline fallback; no table-view mechanism is switched off)
-- Retires: nothing
-- Nothing dropped, deleted or renamed by this migration.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'catalogue_layout.max_bytes', 'Saved table layout: largest size',
  'The largest layout a person can save for a list (visible columns, order, widths and sort). A bigger layout is refused with the reason.', 'number',
  to_jsonb(16000), 2000, 64000, 'bytes', 1500, 'Course catalogue', 'public.admin_table_layout (save); Course catalogue › Columns',
  'CF-247 Course Catalogue columns (Platform Admin mandate 5 Nov 2026 17:31 §5): per-user layouts, size-capped'),
 ('pipeline', 'catalogue_layout.max_columns', 'Saved table layout: most columns shown',
  'The most columns a saved layout may show at once. The column picker stops ticking more at this number.', 'number',
  to_jsonb(60), 5, 100, 'columns', 1501, 'Course catalogue', 'public.admin_table_layout (save, read); Course catalogue › Columns',
  'CF-247 Course Catalogue columns (Platform Admin mandate 5 Nov 2026 17:31 §5, §6)'),
 ('pipeline', 'catalogue_layout.width_min_px', 'Saved table layout: narrowest column',
  'No column can be made narrower than this (a column''s own minimum can be wider), so values stay readable.', 'number',
  to_jsonb(64), 40, 200, 'pixels', 1502, 'Course catalogue', 'public.admin_table_layout (save, read); Course catalogue table resizing',
  'CF-247 Course Catalogue columns (Platform Admin mandate 5 Nov 2026 17:31 §6: minimum readable column widths)'),
 ('pipeline', 'catalogue_layout.width_max_px', 'Saved table layout: widest column',
  'No column can be made wider than this.', 'number',
  to_jsonb(1200), 300, 2400, 'pixels', 1503, 'Course catalogue', 'public.admin_table_layout (save, read); Course catalogue table resizing',
  'CF-247 Course Catalogue columns (Platform Admin mandate 5 Nov 2026 17:31 §6)'),
 ('pipeline', 'catalogue_layout.server_layouts_on', 'Saved table layouts: keep layouts on the server',
  '1 = each person''s Course catalogue layout is saved to their account and follows them to other devices. 0 = recovery switch: the server neither reads nor saves layouts (nothing is deleted) and the screen keeps each layout in that browser only.', 'number',
  to_jsonb(1), 0, 1, 'on (1) / off (0)', 1504, 'Course catalogue', 'public.admin_table_layout (read, save, reset, restore); Course catalogue › Columns',
  'CF-247 Course Catalogue columns forward recovery (independent validation 5 Nov 2026)'),
 ('pipeline', 'catalogue_layout.new_sorts_on', 'Course catalogue: offer the Last data admitted and Adapter status sorts',
  '1 = the two sorts added with the customisable columns are offered. 0 = recovery switch: the screen stops offering them (the columns stay; a saved sort on either falls back to Course).', 'number',
  to_jsonb(1), 0, 1, 'on (1) / off (0)', 1505, 'Course catalogue', 'public.admin_table_layout (read); Course catalogue sort headings',
  'CF-247 Course Catalogue columns forward recovery (independent validation 5 Nov 2026)')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.admin_table_columns (
  screen text not null,
  key text not null,
  grp text not null check (grp in ('Identity', 'Course information', 'Pipeline and enrichment', 'Lifecycle and timestamps')),
  label text not null,
  sort integer not null,
  sort_key text,
  default_visible boolean not null default false,
  default_width integer not null check (default_width > 0),
  min_width integer not null check (min_width > 0),
  always_visible boolean not null default false,
  active boolean not null default true,
  primary key (screen, key)
);
comment on table pipeline.admin_table_columns is 'CF-247 Course Catalogue columns (Platform Admin mandate 5 Nov 2026 17:31): the column registry of an admin list (screen courses: the Course catalogue''s 36 columns in four groups), with its server sort key, default visibility and width, minimum width and whether it is always shown. A saved layout (pipeline.admin_table_layouts) may name only these columns; the screen''s own registry (src/catalogue-columns.js) is checked equal by its spec. Read by public.admin_table_layout. Never read by the consumer API.';
alter table pipeline.admin_table_columns enable row level security;
revoke all on table pipeline.admin_table_columns from anon, authenticated;

create table if not exists pipeline.admin_table_layouts (
  user_id uuid not null references auth.users(id) on delete cascade,
  screen text not null check (screen ~ '^[a-z][a-z0-9_]*$'),
  layout jsonb check (layout is null or jsonb_typeof(layout) = 'object'),
  previous jsonb check (previous is null or jsonb_typeof(previous) = 'object'),
  saved_at timestamptz,
  reset_at timestamptz,
  save_count integer not null default 0,
  primary key (user_id, screen)
);
comment on table pipeline.admin_table_layouts is 'CF-247 Course Catalogue columns (Platform Admin mandate 5 Nov 2026 17:31 §5): one saved table layout per person and screen (visible columns, order, widths, sort field and direction), so a person''s layout follows them to another device or browser. layout null = the default layout (after Reset); previous = the layout before the last save or reset (Restore last saved). Written and read only by public.admin_table_layout, always for the caller''s own row (auth.uid()); no grants. Never read by the consumer API.';
alter table pipeline.admin_table_layouts enable row level security;
revoke all on table pipeline.admin_table_layouts from anon, authenticated;

insert into pipeline.admin_table_columns(screen, key, grp, label, sort, sort_key, default_visible, default_width, min_width, always_visible) values
 ('courses', 'canonical_title', 'Identity', 'Course', 10, 'course', true, 310, 160, true),
 ('courses', 'course_code', 'Identity', 'Course code / CRICOS', 20, null, true, 155, 96, false),
 ('courses', 'provider_name', 'Identity', 'Provider', 30, 'provider', true, 240, 120, false),
 ('courses', 'country_name', 'Identity', 'Country', 40, null, false, 130, 90, false),
 ('courses', 'subdivision_name', 'Identity', 'State / Region', 50, null, true, 150, 96, false),
 ('courses', 'city_names', 'Identity', 'City', 60, 'city', true, 150, 96, false),
 ('courses', 'campus_count', 'Identity', 'Campus', 70, null, false, 170, 96, false),
 ('courses', 'level_name', 'Identity', 'Study level', 80, null, true, 150, 96, false),
 ('courses', 'field_of_study', 'Identity', 'Study area', 90, 'field', true, 190, 110, false),
 ('courses', 'duration', 'Course information', 'Duration', 100, null, false, 130, 90, false),
 ('courses', 'delivery_mode', 'Course information', 'Delivery mode', 110, null, false, 140, 90, false),
 ('courses', 'intl_fee_amount', 'Course information', 'International fee', 120, 'intl_fee', true, 190, 110, false),
 ('courses', 'fee_amount', 'Course information', 'Tuition (registered, CRICOS)', 130, 'fee', true, 150, 100, false),
 ('courses', 'intl_fee_year', 'Course information', 'Fee year', 140, null, false, 100, 80, false),
 ('courses', 'intakes', 'Course information', 'Intakes', 150, null, false, 160, 100, false),
 ('courses', 'intake_month', 'Course information', 'Intake month', 152, null, false, 130, 90, false),
 ('courses', 'intake_year', 'Course information', 'Intake year', 154, null, false, 110, 80, false),
 ('courses', 'commencement_date', 'Course information', 'Exact commencement date', 156, null, false, 170, 110, false),
 ('courses', 'deadline', 'Course information', 'Application deadline', 160, null, false, 160, 100, false),
 ('courses', 'english', 'Course information', 'English requirements', 170, null, false, 160, 100, false),
 ('courses', 'academic_entry', 'Course information', 'Academic entry requirements', 180, null, false, 170, 100, false),
 ('courses', 'has_scholarship', 'Course information', 'Scholarships', 190, null, false, 120, 90, false),
 ('courses', 'description', 'Course information', 'Course description', 200, null, false, 160, 100, false),
 ('courses', 'official_url', 'Course information', 'Official course URL', 210, null, false, 180, 110, false),
 ('courses', 'completeness_score_v2', 'Course information', 'Completeness', 220, 'completeness', true, 120, 90, false),
 ('courses', 'adapter_state', 'Pipeline and enrichment', 'Adapter status', 230, 'adapter', true, 160, 110, false),
 ('courses', 'adapter_last_read_at', 'Pipeline and enrichment', 'Adapter last read', 240, null, false, 160, 110, false),
 ('courses', 'adapter_result', 'Pipeline and enrichment', 'Adapter result', 250, null, false, 200, 110, false),
 ('courses', 'page_stored', 'Pipeline and enrichment', 'Stored course page', 260, null, false, 140, 100, false),
 ('courses', 'source_identity', 'Pipeline and enrichment', 'Source identity', 270, null, false, 160, 100, false),
 ('courses', 'last_verified_at', 'Pipeline and enrichment', 'Evidence last verified', 280, 'verified', true, 145, 110, false),
 ('courses', 'layer4_status', 'Pipeline and enrichment', 'Layer 4', 290, null, false, 130, 90, false),
 ('courses', 'enrichment_status', 'Pipeline and enrichment', 'Enrichment', 300, null, false, 170, 110, false),
 ('courses', 'last_admitted_field', 'Pipeline and enrichment', 'Last successful field admission', 310, null, false, 220, 130, false),
 ('courses', 'created_at', 'Lifecycle and timestamps', 'Created', 320, null, false, 140, 100, false),
 ('courses', 'last_modified_at', 'Lifecycle and timestamps', 'Course record updated (as recorded)', 330, 'modified', true, 150, 110, false),
 ('courses', 'last_admitted_at', 'Lifecycle and timestamps', 'Last data admitted', 340, 'admitted', true, 160, 110, false),
 ('courses', 'last_published_at', 'Lifecycle and timestamps', 'Last published (website feed)', 345, null, false, 170, 110, false),
 ('courses', 'lifecycle_status', 'Lifecycle and timestamps', 'Lifecycle status', 350, null, false, 130, 90, false),
 ('courses', 'publication_status', 'Lifecycle and timestamps', 'Publication', 360, null, false, 130, 90, false)
on conflict (screen, key) do nothing;

-- the Last data admitted column and detail: one indexed lookup per ledger and page course. Each build holds its table's write lock while it runs
-- (measured on production-volume fixtures: 24 ms for field_enrich_items, 171,004 rows; under 25 ms for the others). The builds wait for writers
-- already holding the table; the lock wait is bounded so a busy minute fails the migration cleanly instead of queueing the pipeline behind it.
set local lock_timeout = '5s'; -- fixed: deploy-time safety, not a pipeline control (a busy minute fails cleanly; apply again in a quiet minute)
create index if not exists field_enrich_items_course_filled_idx on pipeline.field_enrich_items (course_id, updated_at desc) where state = 'filled';
create index if not exists adapter_overwrite_changes_course_at_idx on pipeline.adapter_overwrite_changes (course_id, at desc);
create index if not exists layer4_admission_checks_entity_admitted_idx on pipeline.layer4_admission_checks (entity_id, decided_at desc) where admitted;
create index if not exists course_intake_date_events_course_filled_idx on pipeline.course_intake_date_events (course_id, run_at desc) where outcome = 'filled';

-- Every admission of a course value: the one definition Last data admitted is read from (the page column, its detail and the sort).
-- Only rows that record a value reaching the catalogue; a read, proposal, review item, skip, failure, retraction, refresh or build is never here.
CREATE OR REPLACE FUNCTION security.course_admissions_v1()
 RETURNS TABLE(course_id uuid, at timestamp with time zone, field text, source text, evidence_id uuid, before jsonb, after jsonb, rule text)
 LANGUAGE sql
 STABLE
AS $function$
  select i.course_id, i.updated_at, i.field, coalesce(i.source, 'enrich_fields'), i.evidence_id, null::jsonb,
         case when jsonb_typeof(i.value) = 'object' then i.value - 'text' - 'check' else i.value end, 'Enrich fields'::text
    from pipeline.field_enrich_items i
   where i.state = 'filled' and i.course_id is not null and not exists (select 1 from pipeline.enrich_value_retractions x where x.item_id = i.id)
  union all
  select a.course_id, a.at, a.field, 'adapter_overwrite', a.evidence_id, a.before, a.after, 'Adapter overwrite'
    from pipeline.adapter_overwrite_changes a where a.before is distinct from a.after
  union all
  select l.course_id, l.decided_at, l.field_key, 'layer2_admission', l.evidence_id, null, l.candidate_payload, l.change_control_ref
    from pipeline.layer2_field_admissions l where l.status = 'admitted' and l.canonical_changed
  union all
  select k.entity_id, k.decided_at, k.field_code, 'layer4_approval', null, null, null, 'Layer 4 decision ' || k.decision_id::text
    from pipeline.layer4_admission_checks k where k.entity_type = 'course' and k.admitted
  union all
  select e.course_id, e.run_at, 'intakes', 'intake_dates', e.calendar_evidence_id, e.before_value, e.after_value, coalesce(e.rule, 'Intake dates')
    from pipeline.course_intake_date_events e where e.outcome = 'filled'
  union all
  select m.entity_id, m.at, coalesce(m.field, m.action), 'manual', null, m.before, m.after, coalesce(m.reason, 'Set by hand')
    from pipeline.manual_edit_log m where m.entity = 'course' and m.action in ('set_official_url', 'set_tuition')
$function$;
comment on function security.course_admissions_v1() is 'CF-247 Course Catalogue columns (mandate 5 Nov 2026 17:31 §4): every admission of a course value from the admission ledgers (field items filled and not retracted, adapter overwrites that changed the value, Layer 2 admissions that changed the canonical value, Layer 4 approvals confirmed admitted, intake dates filled, official page or tuition set by hand). The one definition of Last data admitted: its column, its detail and its sort.';

-- Last data admitted of one course (null = Unknown)
CREATE OR REPLACE FUNCTION security.course_last_admitted_at_v1(p_course_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
AS $function$
  select max(a.at) from security.course_admissions_v1() a where a.course_id = p_course_id
$function$;
comment on function security.course_last_admitted_at_v1(uuid) is 'CF-247 Course Catalogue columns (mandate 5 Nov 2026 17:31 §4): when a value was last admitted to this course (security.course_admissions_v1); null = Unknown.';

-- Adapter status from its inputs: one rule for the page column and the sort. Completed needs a result row for the course: never inferred.
CREATE OR REPLACE FUNCTION security.course_adapter_state_from_v1(p_has_adapter boolean, p_enabled boolean, p_admit boolean, p_leased boolean,
  p_page_status text, p_read_status text, p_last_result text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when not coalesce(p_has_adapter, false) then 'not_configured'
    when coalesce(p_leased, false) then 'processing'
    when not (coalesce(p_enabled, false) and coalesce(p_admit, false)) then 'held'
    when p_last_result is not null and p_last_result <> 'read' then 'failed'
    when p_read_status is not null and p_read_status <> 'read' then 'failed'
    when p_last_result is not null then 'completed'
    when p_page_status is distinct from 'bound' then 'held'
    else 'ready' end
$function$;
comment on function security.course_adapter_state_from_v1(boolean, boolean, boolean, boolean, text, text, text) is 'CF-247 Course Catalogue columns (mandate 5 Nov 2026 17:31 §3): a course''s adapter status from the provider adapter (exists, enabled, admitting), its course page (being read, bound, read status) and its latest adapter result: not_configured, processing, held, failed, completed, ready. Completed is never inferred from an adapter existing.';

-- Adapter status of one course
CREATE OR REPLACE FUNCTION security.course_adapter_state_v1(p_course_id uuid, p_provider_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select security.course_adapter_state_from_v1(u.provider_id is not null, u.enabled, u.admit, p.leased_until > now(), p.status, p.read_status,
           (select r.before_read_status from pipeline.uni_adapter_results r where r.course_id = p_course_id order by r.at desc, r.id desc limit 1))
    from (select 1) one
    left join pipeline.uni_adapters u on u.provider_id = p_provider_id
    left join pipeline.coverage_course_pages p on p.course_id = p_course_id
$function$;
comment on function security.course_adapter_state_v1(uuid, uuid) is 'CF-247 Course Catalogue columns (mandate 5 Nov 2026 17:31 §3): a course''s adapter status (security.course_adapter_state_from_v1) read from the adapter tables.';

-- Sort order for Adapter status, attention first
CREATE OR REPLACE FUNCTION security.course_adapter_rank_v1(p_state text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select array_position(array['failed', 'held', 'processing', 'ready', 'completed', 'not_configured'], p_state)
$function$;

-- The page extras: one set-based read over the page's course ids (never per course from the browser)
CREATE OR REPLACE FUNCTION security.course_list_extras_v1(p_ids uuid[])
 RETURNS TABLE(course_id uuid, extras jsonb)
 LANGUAGE sql
 STABLE
AS $function$
  select c.id, jsonb_build_object(
    'last_modified_at', c.updated_at,
    'last_admitted_at', la.at,
    'last_admitted', case when la.at is null then null else jsonb_build_object('at', la.at, 'field', la.field, 'source', la.source, 'evidence_id', la.evidence_id,
      'before', la.before, 'after', la.after, 'rule', la.rule) end,
    'duration_unit', c.duration_unit,
    'cities', coalesce(ct.cities, '[]'::jsonb),
    'adapter', jsonb_build_object('state', st.state, 'reason', case st.state
        when 'not_configured' then 'The provider has no adapter'
        when 'processing' then 'The course page is being read now'
        when 'held' then case when u.provider_id is not null and not u.enabled then 'The adapter is switched off'
                              when u.provider_id is not null and not u.admit then 'The adapter is testing: its values are not admitted'
                              else 'No confirmed course page to read' end
        when 'failed' then 'Last read: ' || coalesce(nullif(r.before_read_status, 'read'), p.read_status, 'did not read')
        when 'completed' then 'Read by the adapter'
        else 'Waiting for its first read' end,
      'last_read_at', r.at, 'result', r.how, 'identity', r.identity,
      'provider_adapter', case when u.provider_id is null then null when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end),
    'page', case when p.course_id is null then null else jsonb_build_object('stored', p.evidence_id is not null, 'status', p.status, 'read_status', p.read_status,
      'identity', p.identity_basis, 'read_at', p.read_at, 'evidence_id', p.evidence_id) end,
    'field_states', coalesce(fs.states, '{}'::jsonb),
    'layer4_open', l4.n,
    'enrichment', en.counts,
    'intakes', coalesce(ik.intakes, '[]'::jsonb),
    'published', pb.published)
  from unnest(p_ids) ids(id)
  join catalogue.courses c on c.id = ids.id
  left join pipeline.uni_adapters u on u.provider_id = c.provider_id
  left join pipeline.coverage_course_pages p on p.course_id = c.id
  left join lateral (select r.at, r.how, r.identity, r.before_read_status from pipeline.uni_adapter_results r where r.course_id = c.id order by r.at desc, r.id desc limit 1) r on true
  cross join lateral (select security.course_adapter_state_v1(c.id, c.provider_id) state) st
  left join lateral (
    select jsonb_agg(jsonb_build_object('campus', x.name, 'city', x.city, 'subdivision_code', x.sd_code, 'subdivision_name', x.sd_name, 'country_code', x.country_code)
             order by lower(coalesce(x.city, '')), x.name) cities
    from (select distinct on (ca.id) ca.name, nullif(btrim(ca.city), '') city, sd.code sd_code, sd.name sd_name, co.iso_alpha2::text country_code
            from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id
            left join ref.subdivisions sd on sd.id = ca.subdivision_id left join ref.countries co on co.id = ca.country_id
           where cc.course_id = c.id order by ca.id) x) ct on true
  left join lateral (select a.at, a.field, a.source, a.evidence_id, a.before, a.after, a.rule from security.course_admissions_v1() a
     where a.course_id = c.id order by a.at desc limit 1) la on true
  left join lateral (
    select jsonb_object_agg(a.attribute, jsonb_build_object('state', case
        when a.state = 'admitted' then 'populated'
        when f.reason_code is not null then 'held'
        when a.state = 'in_review' then 'review'
        when a.state in ('candidate', 'awaiting_l3', 'in_queue', 'page_found') then 'pending'
        when a.state = 'blocked' then 'failed'
        when a.absence_class = 'not_applicable' then 'not_applicable'
        else 'missing' end, 'raw', a.state, 'reason', coalesce(ac.label, a.state), 'flag', f.reason_code)) states
      from pipeline.course_attribute_coverage a
      left join pipeline.field_absence_classes ac on ac.code = a.absence_class
      left join lateral (select fl.reason_code from pipeline.enrichment_flags fl where fl.entity = 'course' and fl.entity_key = c.id::text and fl.field = a.attribute and fl.state = 'raised' order by fl.id limit 1) f on true
     where a.course_id = c.id) fs on true
  left join lateral (select count(*)::int n from pipeline.layer4_interventions li where li.course_id = c.id and li.status in ('ai_pending', 'awaiting_input', 'resuming')) l4 on true
  -- intakes as the website builds them (active course_intakes; month read from the label with the website's own rule), with how precise the
  -- start is and the deadline kind where the intake-dates job recorded them; nothing is filled in
  left join lateral (
    select jsonb_agg(jsonb_build_object('label', i.intake_label, 'year', i.intake_year,
             'month', coalesce(extract(month from i.start_date)::int, api.website_v2_label_month(i.intake_label)),
             'start_date', i.start_date, 'application_deadline', i.application_deadline,
             'start_precision', d.start_precision, 'deadline_kind', d.deadline_kind, 'deadline_text', d.deadline_text)
           order by i.intake_year nulls last, coalesce(extract(month from i.start_date)::int, api.website_v2_label_month(i.intake_label)) nulls last, i.start_date nulls last, i.intake_label) intakes
      from catalogue.course_intakes i left join pipeline.course_intake_dates d on d.intake_id = i.id
     where i.course_id = c.id and i.status = 'active') ik on true
  left join (
    -- the last change of the course's item in the website and Zoho feeds (a new, changed or removed item; an unchanged re-check is not a change)
    select x.ref_id, jsonb_build_object(
             'website_at', max(x.seq_at) filter (where x.feed = 'website'), 'website_removed', bool_or(x.removed_at is not null) filter (where x.feed = 'website'),
             'zoho_at', max(x.seq_at) filter (where x.feed = 'zoho'), 'zoho_removed', bool_or(x.removed_at is not null) filter (where x.feed = 'zoho')) published
      from (select 'website' feed, w.ref_id, w.seq_at, w.removed_at from pipeline.website_sync_items w where w.entity = 'course' and w.ref_id = any(p_ids)
            union all
            select 'zoho', z.ref_id, z.seq_at, z.removed_at from pipeline.zoho_sync_items z where z.entity = 'course' and z.ref_id = any(p_ids)) x
     group by x.ref_id) pb on pb.ref_id = c.id
  left join lateral (select jsonb_build_object('filled', count(*) filter (where e.state = 'filled'), 'review', count(*) filter (where e.state = 'review'),
      'failed', count(*) filter (where e.state = 'failed'), 'pending', count(*) filter (where e.state in ('queued', 'waiting', 'ai', 'leased'))) counts
      from pipeline.field_enrich_items e where e.course_id = c.id) en on true
$function$;
comment on function security.course_list_extras_v1(uuid[]) is 'CF-247 Course Catalogue columns (mandate 5 Nov 2026 17:31): the extra Course catalogue columns for one page of course ids, read set-based: Last modified, Last data admitted with its field, source, evidence, before and after, Adapter status and its reason, campus cities with state and country, stored page and identity, field states (coverage states with flags), open Layer 4 items, enrichment counts. Called only by security.course_list_with_extras_v1.';

CREATE OR REPLACE FUNCTION security.course_list_with_extras_v1(p_page jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select case when jsonb_typeof(p_page -> 'items') is distinct from 'array' then p_page else
    p_page || jsonb_build_object('items', coalesce((
      select jsonb_agg(it.v || coalesce(x.extras, '{}'::jsonb) order by it.o)
        from jsonb_array_elements(p_page -> 'items') with ordinality it(v, o)
        left join security.course_list_extras_v1(array(select nullif(coalesce(j ->> 'id', j ->> 'course_id'), '')::uuid from jsonb_array_elements(p_page -> 'items') j)) x
          on x.course_id = nullif(coalesce(it.v ->> 'id', it.v ->> 'course_id'), '')::uuid), '[]'::jsonb),
      'columns_profile', 'course_columns_v1') end
$function$;
comment on function security.course_list_with_extras_v1(jsonb) is 'CF-247 Course Catalogue columns (mandate 5 Nov 2026 17:31): merges security.course_list_extras_v1 into each item of a courses_page result, keeping the items'' order and every existing field.';

revoke all on function security.course_admissions_v1(), security.course_last_admitted_at_v1(uuid), security.course_adapter_state_from_v1(boolean, boolean, boolean, boolean, text, text, text),
  security.course_adapter_state_v1(uuid, uuid), security.course_adapter_rank_v1(text),
  security.course_list_extras_v1(uuid[]), security.course_list_with_extras_v1(jsonb) from public, anon, authenticated;

-- The saved layout: read, save, reset, restore. Always the caller's own row.
CREATE OR REPLACE FUNCTION public.admin_table_layout(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_screen text := nullif(btrim(coalesce(p_args ->> 'screen', '')), '');
  v_layout jsonb := p_args -> 'layout';
  v_max_bytes integer := security.pipeline_num_v1('catalogue_layout.max_bytes', 16000)::integer;
  v_max_cols integer := security.pipeline_num_v1('catalogue_layout.max_columns', 60)::integer;
  v_wmin integer := security.pipeline_num_v1('catalogue_layout.width_min_px', 64)::integer;
  v_wmax integer := security.pipeline_num_v1('catalogue_layout.width_max_px', 1200)::integer;
  v_server boolean := security.pipeline_num_v1('catalogue_layout.server_layouts_on', 1) >= 1;
  v_sorts boolean := security.pipeline_num_v1('catalogue_layout.new_sorts_on', 1) >= 1;
  v_row pipeline.admin_table_layouts%rowtype;
  v_cols text[];
  v_bad text;
  v_k text; v_v jsonb; v_min integer;
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if v_screen is null or not exists (select 1 from pipeline.admin_table_columns c where c.screen = v_screen and c.active) then
    raise exception 'unknown screen: %', coalesce(v_screen, '(none)') using errcode = '22023';
  end if;
  -- recovery switch off: nothing is read or written on the server (rows are kept); the screen keeps the layout in its browser
  if not v_server and p_action in ('save', 'reset', 'restore') then
    return jsonb_build_object('saved', false, 'reset', false, 'restored', false, 'screen', v_screen, 'server_layouts', false);
  end if;
  if p_action = 'save' then
    if v_layout is null or jsonb_typeof(v_layout) <> 'object' then raise exception 'layout must be an object' using errcode = '22023'; end if;
    if octet_length(v_layout::text) > v_max_bytes then raise exception 'layout is % bytes; the most is % (Saved table layout: largest size)', octet_length(v_layout::text), v_max_bytes using errcode = '22023'; end if;
    select string_agg(k, ', ') into v_bad from jsonb_object_keys(v_layout) k where k not in ('version', 'columns', 'widths', 'sort', 'direction');
    if v_bad is not null then raise exception 'layout has unknown keys: %', v_bad using errcode = '22023'; end if;
    if jsonb_typeof(v_layout -> 'columns') is distinct from 'array' or jsonb_array_length(v_layout -> 'columns') = 0 then raise exception 'layout.columns must list at least one column' using errcode = '22023'; end if;
    if exists (select 1 from jsonb_array_elements(v_layout -> 'columns') e where jsonb_typeof(e) <> 'string') then raise exception 'layout.columns must be column keys' using errcode = '22023'; end if;
    select array_agg(e #>> '{}' order by o) into v_cols from jsonb_array_elements(v_layout -> 'columns') with ordinality x(e, o);
    if cardinality(v_cols) > v_max_cols then raise exception 'layout shows % columns; the most is % (Saved table layout: most columns shown)', cardinality(v_cols), v_max_cols using errcode = '22023'; end if;
    if cardinality(v_cols) <> (select count(distinct x) from unnest(v_cols) x) then raise exception 'layout.columns names a column twice' using errcode = '22023'; end if;
    select string_agg(x, ', ') into v_bad from unnest(v_cols) x where not exists (select 1 from pipeline.admin_table_columns c where c.screen = v_screen and c.key = x and c.active);
    if v_bad is not null then raise exception 'unknown columns for %: %', v_screen, v_bad using errcode = '22023'; end if;
    select string_agg(c.key, ', ') into v_bad from pipeline.admin_table_columns c where c.screen = v_screen and c.active and c.always_visible and not (c.key = any(v_cols));
    if v_bad is not null then raise exception 'these columns are always shown: %', v_bad using errcode = '22023'; end if;
    if v_layout ? 'widths' and v_layout -> 'widths' <> 'null'::jsonb then
      if jsonb_typeof(v_layout -> 'widths') <> 'object' then raise exception 'layout.widths must be an object' using errcode = '22023'; end if;
      for v_k, v_v in select * from jsonb_each(v_layout -> 'widths') loop
        select c.min_width into v_min from pipeline.admin_table_columns c where c.screen = v_screen and c.key = v_k and c.active;
        if not found then raise exception 'unknown column in widths: %', v_k using errcode = '22023'; end if;
        if jsonb_typeof(v_v) <> 'number' or (v_v #>> '{}')::numeric <> trunc((v_v #>> '{}')::numeric) then raise exception 'width of % must be whole pixels', v_k using errcode = '22023'; end if;
        if (v_v #>> '{}')::numeric < greatest(v_wmin, v_min) or (v_v #>> '{}')::numeric > v_wmax then
          raise exception 'width of % must be between % and % pixels', v_k, greatest(v_wmin, v_min), v_wmax using errcode = '22023';
        end if;
      end loop;
    end if;
    if v_layout ? 'sort' and v_layout -> 'sort' <> 'null'::jsonb and not exists (select 1 from pipeline.admin_table_columns c where c.screen = v_screen and c.active and c.sort_key = v_layout ->> 'sort') then
      raise exception 'layout.sort is not a sort of this list: %', v_layout ->> 'sort' using errcode = '22023';
    end if;
    if v_layout ? 'direction' and v_layout -> 'direction' <> 'null'::jsonb and coalesce(v_layout ->> 'direction', '') not in ('asc', 'desc') then
      raise exception 'layout.direction must be asc or desc' using errcode = '22023';
    end if;
    insert into pipeline.admin_table_layouts as t (user_id, screen, layout, previous, saved_at, save_count)
    values (v_uid, v_screen, v_layout, null, now(), 1)
    on conflict (user_id, screen) do update set previous = case when t.layout is distinct from excluded.layout then t.layout else t.previous end,
      layout = excluded.layout, saved_at = now(), save_count = t.save_count + 1
    returning * into v_row;
    return jsonb_build_object('saved', true, 'screen', v_screen, 'layout', v_row.layout, 'saved_at', v_row.saved_at, 'has_previous', v_row.previous is not null);
  elsif p_action = 'reset' then
    insert into pipeline.admin_table_layouts as t (user_id, screen, layout, previous, reset_at)
    values (v_uid, v_screen, null, null, now())
    on conflict (user_id, screen) do update set previous = coalesce(t.layout, t.previous), layout = null, reset_at = now()
    returning * into v_row;
    return jsonb_build_object('reset', true, 'screen', v_screen, 'layout', null, 'reset_at', v_row.reset_at, 'has_previous', v_row.previous is not null);
  elsif p_action = 'restore' then
    update pipeline.admin_table_layouts t set layout = t.previous, previous = t.layout, saved_at = now(), save_count = t.save_count + 1
     where t.user_id = v_uid and t.screen = v_screen and t.previous is not null
    returning * into v_row;
    if not found then raise exception 'there is no earlier saved layout to restore' using errcode = '22023'; end if;
    return jsonb_build_object('restored', true, 'screen', v_screen, 'layout', v_row.layout, 'saved_at', v_row.saved_at, 'has_previous', v_row.previous is not null);
  elsif p_action = 'read' then
    if v_server then select * into v_row from pipeline.admin_table_layouts t where t.user_id = v_uid and t.screen = v_screen; end if;
    return jsonb_build_object('screen', v_screen, 'server_layouts', v_server, 'new_sorts', v_sorts, 'layout', v_row.layout, 'saved_at', v_row.saved_at, 'reset_at', v_row.reset_at,
      'has_previous', v_row.previous is not null, 'save_count', coalesce(v_row.save_count, 0),
      'limits', jsonb_build_object('max_bytes', v_max_bytes, 'max_columns', v_max_cols, 'width_min_px', v_wmin, 'width_max_px', v_wmax),
      'registry', (select jsonb_agg(jsonb_build_object('key', c.key, 'group', c.grp, 'label', c.label, 'sort_key', c.sort_key, 'default_visible', c.default_visible,
                     'default_width', c.default_width, 'min_width', greatest(c.min_width, v_wmin), 'always_visible', c.always_visible) order by c.sort)
                   from pipeline.admin_table_columns c where c.screen = v_screen and c.active));
  end if;
  raise exception 'unknown action: %', coalesce(p_action, '(none)') using errcode = '22023';
end $function$;
comment on function public.admin_table_layout(text, jsonb) is 'CF-247 Course Catalogue columns (mandate 5 Nov 2026 17:31 §5): the caller''s own saved table layout for a screen: read (with the column registry and limits), save (checked against the registry and the catalogue_layout.* settings), reset (default layout; the old one kept for restore) and restore (the last saved layout). Any assigned role; never another person''s row.';
revoke all on function public.admin_table_layout(text, jsonb) from public, anon;
grant execute on function public.admin_table_layout(text, jsonb) to authenticated;

-- courses_page: the page extras on every path, and the two new sort keys (exact edits on the live definitions)
CREATE OR REPLACE FUNCTION pg_temp.ccol_edit(p_sig text, p_md5 text, p_marker text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if position(p_marker in v_def) > 0 then raise notice 'Course Catalogue columns: % already applied', p_sig; return; end if;
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.ccol_edit('security.admin_course_page_fast(jsonb)', '2dc6ee8ba523afeec04d862f3a2ced8a', 'security.course_list_with_extras_v1(', array[
  array['    return security.admin_course_page_unfiltered_fast(p_args);',
        '    -- CF-247 Course Catalogue columns (mandate 5 Nov 2026 17:31): every page carries the extra columns, read set-based over its ids
    return security.course_list_with_extras_v1(security.admin_course_page_unfiltered_fast(p_args));'],
  array[$o$    return security.admin_course_page_fast_base(p_args||jsonb_build_object('provider_id',v_provider_id::text));$o$,
        $n$    return security.course_list_with_extras_v1(security.admin_course_page_fast_base(p_args||jsonb_build_object('provider_id',v_provider_id::text)));$n$],
  array['  return security.admin_course_page_fast_base(p_args);',
        '  return security.course_list_with_extras_v1(security.admin_course_page_fast_base(p_args));']
], array[1, 1, 1]);

select pg_temp.ccol_edit('security.admin_course_page_fast_base(jsonb)', 'afbef16111a09e3680061547bbb1329a', 'security.course_admissions_v1()', array[
  array['    select b.id,b.canonical_title,b.provider_name,b.field_of_study,b.updated_at,b.last_verified_at from base b',
        '    select b.id,b.canonical_title,b.provider_name,b.field_of_study,b.updated_at,b.last_verified_at,b.provider_id from base b'],
  array[$o$  ), numbered as (
    -- CF-247 W34$o$,
        $n$  ), adm as materialized (
    -- CF-247 Course Catalogue columns (mandate 5 Nov 2026 17:31 §8): the Last data admitted and Adapter status sorts run set-based over the
    -- whole filtered set (one aggregate of the admission ledgers; one join of the adapter tables). Each is built only for its own sort.
    select a.course_id,max(a.at) at from security.course_admissions_v1() a where v_sort='admitted' group by a.course_id
  ), ads as materialized (
    select m.id course_id,security.course_adapter_rank_v1(security.course_adapter_state_from_v1(u.provider_id is not null,u.enabled,u.admit,
             p.leased_until>now(),p.status,p.read_status,r.before_read_status)) rank
    from matched m
    left join pipeline.uni_adapters u on u.provider_id=m.provider_id
    left join pipeline.coverage_course_pages p on p.course_id=m.id
    left join (select distinct on (x.course_id) x.course_id,x.before_read_status from pipeline.uni_adapter_results x
               where v_sort='adapter' order by x.course_id,x.at desc,x.id desc) r on r.course_id=m.id
    where v_sort='adapter'
  ), numbered as (
    -- CF-247 W34$n$],
  array['    from unnest(array(select numbered.id from matched numbered order by',
        '    from unnest(array(select numbered.id from matched numbered left join adm on adm.course_id=numbered.id left join ads on ads.course_id=numbered.id order by'],
  array[$o$      case when v_sort='course' and v_dir='asc' then lower(canonical_title) end asc,$o$,
        $n$      case when v_sort='admitted' and v_dir='asc' then adm.at end asc nulls last,
      case when v_sort='admitted' and v_dir='desc' then adm.at end desc nulls last,
      case when v_sort='adapter' and v_dir='asc' then ads.rank end asc nulls last,
      case when v_sort='adapter' and v_dir='desc' then ads.rank end desc nulls last,
      case when v_sort='course' and v_dir='asc' then lower(canonical_title) end asc,$n$]
], array[1, 1, 1, 1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.admin_table_columns', 'Platform', 'Course catalogue columns: the column registry saved layouts are checked against', 'active', '{}', '20261106300000'),
 ('table', 'pipeline.admin_table_layouts', 'Platform', 'Course catalogue columns: one saved table layout per person and screen', 'active', '{}', '20261106300000'),
 ('function', 'public.admin_table_layout', 'Platform', 'Course catalogue columns: read, save, reset and restore the caller''s own table layout', 'active', '{}', '20261106300000'),
 ('function', 'security.course_list_extras_v1', 'Platform', 'Course catalogue columns: the extra columns of one courses_page page, set-based', 'active', '{}', '20261106300000'),
 ('function', 'security.course_list_with_extras_v1', 'Platform', 'Course catalogue columns: merges the extra columns into a courses_page result', 'active', '{}', '20261106300000'),
 ('function', 'security.course_admissions_v1', 'Platform', 'Course catalogue columns: every admission of a course value (the one definition of Last data admitted)', 'active', '{}', '20261106300000'),
 ('function', 'security.course_last_admitted_at_v1', 'Platform', 'Course catalogue columns: Last data admitted of one course', 'active', '{}', '20261106300000'),
 ('function', 'security.course_adapter_state_from_v1', 'Platform', 'Course catalogue columns: the adapter status rule from its inputs', 'active', '{}', '20261106300000'),
 ('function', 'security.course_adapter_state_v1', 'Platform', 'Course catalogue columns: a course''s adapter status from the adapter lifecycle and results', 'active', '{}', '20261106300000'),
 ('function', 'security.course_adapter_rank_v1', 'Platform', 'Course catalogue columns: Adapter status sort order', 'active', '{}', '20261106300000')
on conflict do nothing;

-- post-check
do $$
declare v text;
begin
  v := pg_get_functiondef('security.admin_course_page_fast(jsonb)'::regprocedure);
  if (length(v) - length(replace(v, 'security.course_list_with_extras_v1(', ''))) / length('security.course_list_with_extras_v1(') <> 3 then raise exception 'Course Catalogue columns post-check: courses_page paths without the extras'; end if;
  v := pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure);
  if position($p$v_sort='admitted' and v_dir='desc' then adm.at$p$ in v) = 0 or position($p$v_sort='adapter' and v_dir='asc'$p$ in v) = 0 or position('b.last_verified_at,b.provider_id from base b' in v) = 0 then raise exception 'Course Catalogue columns post-check: sort keys missing'; end if;
  if position($p$v_sort='modified' and v_dir='desc' then updated_at end desc$p$ in v) = 0 or position('matched as materialized' in v) = 0 or position('lower(canonical_title),id' in v) = 0 then raise exception 'Course Catalogue columns post-check: existing sort or page-first changed'; end if;
  if (select count(*) from pipeline.admin_table_columns where screen = 'courses') <> 40 then raise exception 'Course Catalogue columns post-check: registry incomplete'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'catalogue_layout.%') <> 6 then raise exception 'Course Catalogue columns post-check: settings missing'; end if;
  if has_table_privilege('authenticated', 'pipeline.admin_table_layouts', 'select') or has_table_privilege('anon', 'pipeline.admin_table_layouts', 'select') then raise exception 'Course Catalogue columns post-check: layouts readable directly'; end if;
  if has_function_privilege('anon', 'public.admin_table_layout(text,jsonb)', 'execute') then raise exception 'Course Catalogue columns post-check: anon can call the layout RPC'; end if;
end $$;
