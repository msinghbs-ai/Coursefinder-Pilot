-- CF-247 s1210 (S2-Build; Platform Admin briefs 26 Nov 2026 07:01 and 07:37 AEDT, "Portal Release 2 Backend ... Matching Live Frontend"):
-- the StudySearch Portal's proposal layer, matching the live Release 2 screens (Pilot #1645, s1200 to s1202) one to one.
-- Contract: admin docs/platform/2026-11-25-studysearch-portal-design-decisions-and-plan.md, "Release 2 contract: student proposals", and Pilot
-- portal/src/lib/proposalApi.js and proposals.js. Platform Admin decisions, 26 Nov 2026 07:30 (question answers):
--   * the contract's functions (list, get, save, refresh with one p_args jsonb) on the brief's pipeline tables, row level security, append-only
--     versions and archive audit; archive, activity and preference functions kept;
--   * the student record keeps identity minimal (student_ref, given_name, family_initial) and also holds the academic facts the screens send
--     (country of education, qualification, result, English result, destination, preferred intake, budget); no family name, contact,
--     passport or date of birth is held;
--   * a save based on an older version than the current one writes nothing unless forced, and answers saved_after_other_edit with who saved,
--     when and what changed; a forced save is marked saved_after_other_edit on its version;
--   * statuses draft, ready, sent, accepted, archived.
-- Retention: expires_at is the last save plus portal setting proposal_retention_months (12). Nothing is deleted automatically; removal of
-- expired or privacy-requested proposals is a Platform Admin paste file (nothing is deleted by an applied migration).
-- The server builds and owns every course snapshot (fee, length, delivery, place, next intake, entry, English, scholarship) from live rows.
-- Access: every function checks the person's own role through security.portal_rank_v1 (s1143): Counsellor (rank 2) and above for every
-- portal_proposal_* function; Viewer (rank 1) and above for activity and preferences (own rows only); anon has no execute. Tables are reached only
-- through these security definer functions; row level security is on with matching read policies and no table privilege is granted.
-- G1: no job. G2: every limit and the soft-lock window are portal settings, returned to the screens by portal_proposal_get_v1. G3: nothing the
-- website, Zoho or the Admin app reads is touched; checked before and after. Manual locks and active cron jobs checked unchanged. Nothing dropped
-- or deleted. No AI or Firecrawl call. The portal calls with each person's own sign-in, so no API key is issued (s935 covers key-signed consumers).
-- Replaces: nothing (new tables and functions).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the new objects

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'pipeline' and table_name in ('portal_proposals', 'portal_proposal_versions', 'portal_activity', 'portal_user_prefs'))
     or exists (select 1 from pg_proc where proname like 'portal_proposal%' or proname in ('portal_activity_touch_v1', 'portal_activity_list_v1', 'portal_prefs_save_v1')) then
    raise exception 'pre-check: a portal proposal table or function already exists';
  end if;
end $pre$;
create temp table s1210_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

-- 1. Settings (G2), in the portal toolset (s1143). portal_proposal_get_v1 returns the limits and defaults to the screens; none is in the code.
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
 ('portal', 'proposal_max_courses', 'Proposals: most courses in one proposal', 'The most courses one student proposal can hold.',
  'number', '12'::jsonb, 1, 50, 'courses', 6110, 'Portal', 'public.portal_proposal_save_v1, public.portal_proposal_get_v1 (limits.courses_max)', 'CF-247 s1210: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'proposal_message_max_chars', 'Proposals: longest message to the student', 'The longest message to the student (printed on the sheet).',
  'number', '3000'::jsonb, 200, 20000, 'characters', 6111, 'Portal', 'public.portal_proposal_save_v1, public.portal_proposal_get_v1 (limits.message_max_chars)', 'CF-247 s1210: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'proposal_note_max_chars', 'Proposals: longest counsellor note', 'The longest counsellor note (never printed).',
  'number', '2000'::jsonb, 200, 20000, 'characters', 6112, 'Portal', 'public.portal_proposal_save_v1, public.portal_proposal_get_v1 (limits.note_max_chars)', 'CF-247 s1210: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'proposal_why_max_chars', 'Proposals: longest "why this course" line', 'The longest "why this course" line for one course.',
  'number', '300'::jsonb, 50, 2000, 'characters', 6113, 'Portal', 'public.portal_proposal_save_v1, public.portal_proposal_get_v1 (limits.why_max_chars)', 'CF-247 s1210: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'edit_lock_minutes', 'Proposals: how long an open is shown to colleagues', 'Colleagues who opened a proposal this recently are named on it. It never blocks a save.',
  'number', '15'::jsonb, 1, 120, 'minutes', 6120, 'Portal', 'public.portal_proposal_get_v1 (others_recent, soft_lock_minutes)', 'CF-247 s1210: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'proposals_page_size', 'Proposals: proposals per page', 'How many proposal cards the Proposals list shows before "Show more".',
  'number', '20'::jsonb, 5, 100, 'proposals', 6130, 'Portal', 'public.portal_proposal_list_v1', 'CF-247 s1210: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'proposal_retention_months', 'Proposals: months kept after the last save', 'A proposal is due for review this many months after its last save (expires_at). Nothing is removed automatically.',
  'number', '12'::jsonb, 1, 120, 'months', 6135, 'Portal', 'public.portal_proposal_save_v1 (expires_at)', 'CF-247 s1210: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'resume_items_shown', 'Dashboard: resume items shown', 'How many of a person''s own recent searches and opened items the Dashboard resume cards list.',
  'number', '6'::jsonb, 1, 20, 'items', 6140, 'Portal', 'public.portal_activity_list_v1', 'CF-247 s1210: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'themes', 'Portal: colour themes a person can choose', 'The colour themes offered in the portal. A theme not in this list is refused.',
  'list', '["indigo", "ocean", "forest", "plum", "graphite"]'::jsonb, null, null, 'themes', 6150, 'Portal', 'public.portal_prefs_save_v1', 'CF-247 s1210: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'proposal_default_steps', 'Proposals: next steps a new proposal starts with', 'The next steps a new proposal starts with (the counsellor edits, removes or adds steps).',
  'list', '[{"key": "submit_applications", "title": "Submit applications", "detail": "", "owner": "counsellor", "due_label": "", "due_date": null, "included": true},
            {"key": "accept_offer", "title": "Accept your offer and pay the deposit", "detail": "", "owner": "student", "due_label": "", "due_date": null, "included": true},
            {"key": "apply_visa", "title": "Apply for your student visa", "detail": "", "owner": "student", "due_label": "", "due_date": null, "included": true},
            {"key": "health_cover", "title": "Arrange health cover and accommodation", "detail": "", "owner": "student", "due_label": "", "due_date": null, "included": true}]'::jsonb,
  null, null, 'steps', 6160, 'Portal', 'public.portal_proposal_get_v1 (defaults.steps)', 'CF-247 s1210: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'proposal_default_documents', 'Proposals: documents a new proposal asks for', 'The documents a new proposal lists for the student (the counsellor edits the list).',
  'list', '["Passport", "Academic transcripts and certificates", "English test result", "Statement of purpose", "CV"]'::jsonb,
  null, null, 'documents', 6170, 'Portal', 'public.portal_proposal_get_v1 (defaults.documents)', 'CF-247 s1210: Portal Release 2 (Platform Admin 26 Nov 2026)')
on conflict do nothing;

-- 2. Proposals: one row per proposal, holding the current content summary; every saved content is a version.
create sequence if not exists pipeline.portal_student_ref_seq;
comment on sequence pipeline.portal_student_ref_seq is 'CF-247 s1210: numbers the portal student reference (SS-000001).';

create table pipeline.portal_proposals (
  id                 uuid        primary key default gen_random_uuid(),
  student_ref        text        not null check (student_ref ~ '^[A-Z0-9-]{3,20}$'),
  given_name         text        not null check (length(btrim(given_name)) between 1 and 40),  -- fixed: a given name, not free text
  family_initial     text        not null default '' check (family_initial ~ '^[A-Z]?$'),
  source_country     text        check (source_country is null or source_country ~ '^[A-Z]{2}$'),
  qualification      text        not null default '' check (length(qualification) <= 120),     -- fixed: a short academic fact
  result_text        text        not null default '' check (length(result_text) <= 120),
  english_text       text        not null default '' check (length(english_text) <= 120),
  destination        text        check (destination is null or destination ~ '^[A-Z]{2}$'),
  preferred_intake   text        not null default '' check (length(preferred_intake) <= 60),
  budget_per_year    numeric     check (budget_per_year is null or budget_per_year > 0),
  budget_currency    text        check (budget_currency is null or budget_currency ~ '^[A-Z]{3}$'),
  title              text        not null default '' check (length(title) <= 200),             -- fixed: a short heading
  status             text        not null default 'draft' check (status in ('draft', 'ready', 'sent', 'accepted', 'archived')),
  owner_id           uuid        not null references auth.users (id),
  last_editor_id     uuid        not null references auth.users (id),
  current_version    integer     not null default 1 check (current_version >= 1),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  expires_at         timestamptz not null,
  details_checked_at timestamptz,
  kept_live_hash     text,
  archived_at        timestamptz,
  archived_by        uuid        references auth.users (id),
  archived_reason    text        check (archived_reason is null or length(btrim(archived_reason)) between 1 and 500),  -- fixed: a short reason
  check ((status = 'archived') = (archived_at is not null and archived_by is not null and archived_reason is not null))
);
comment on table pipeline.portal_proposals is 'StudySearch Portal (CF-247 s1210): one row per student proposal. The student is a reference, a given name and a family initial plus academic facts (country of education, qualification, result, English result, destination, preferred intake, budget); no family name, contact, passport or birth date. Any Counsellor or above lists, opens and saves any proposal; Viewers cannot. Archived with who, when and why; expires_at for retention review; never deleted by the portal. Reached only through the public.portal_proposal_* functions.';
create index portal_proposals_student_ref_idx on pipeline.portal_proposals (student_ref);
create index portal_proposals_updated_idx on pipeline.portal_proposals (updated_at desc);
create index portal_proposals_owner_idx on pipeline.portal_proposals (owner_id, updated_at desc);

-- 3. Versions: every save is a new row naming its editor; append only.
create table pipeline.portal_proposal_versions (
  proposal_id            uuid        not null references pipeline.portal_proposals (id),
  version                integer     not null check (version >= 1),
  last_editor_id         uuid        not null references auth.users (id),
  edited_at              timestamptz not null default now(),
  note                   text        not null default '' check (length(note) <= 200),  -- fixed: a short version note
  status                 text        not null check (status in ('draft', 'ready', 'sent', 'accepted', 'archived')),
  title                  text        not null default '',
  student                jsonb       not null default '{}'::jsonb check (jsonb_typeof(student) = 'object'),
  courses                jsonb       not null default '[]'::jsonb check (jsonb_typeof(courses) = 'array'),
  steps                  jsonb       not null default '[]'::jsonb check (jsonb_typeof(steps) = 'array'),
  documents              jsonb       not null default '[]'::jsonb check (jsonb_typeof(documents) = 'array'),
  message_to_student     text        not null default '',
  internal_note          text        not null default '',
  refreshed_from         integer,
  saved_after_other_edit boolean     not null default false,
  primary key (proposal_id, version)
);
comment on table pipeline.portal_proposal_versions is 'StudySearch Portal (CF-247 s1210): every saved version of a proposal, append only (update and delete are refused): the student facts, the course snapshots built from live rows at save time, next steps, documents, the message to the student, the internal counsellor note, the editor (last_editor_id), a short note, and whether it was saved over a colleague''s newer save (saved_after_other_edit).';

create or replace function pipeline.portal_proposal_versions_append_only_v1()
returns trigger language plpgsql set search_path = '' as $function$
begin
  raise exception 'proposal versions are append only: a saved version is never changed or removed' using errcode = '42501';
end $function$;
create trigger portal_proposal_versions_append_only
  before update or delete on pipeline.portal_proposal_versions
  for each row execute function pipeline.portal_proposal_versions_append_only_v1();

-- 4. What each person did last (Dashboard resume cards, and who has a proposal open); own rows only.
create table pipeline.portal_activity (
  user_id uuid        not null references auth.users (id),
  kind    text        not null check (kind in ('courses_search', 'proposal', 'provider', 'scholarship')),
  ref     text        not null check (length(ref) between 1 and 200),    -- fixed: an id or a short search key
  label   text        not null check (length(label) between 1 and 200),  -- fixed: a short label
  state   jsonb       not null default '{}'::jsonb check (jsonb_typeof(state) = 'object' and pg_column_size(state) <= 8192),  -- fixed: a search's filters, not a document
  seen_at timestamptz not null default now(),
  primary key (user_id, kind, ref)
);
comment on table pipeline.portal_activity is 'StudySearch Portal (CF-247 s1210): each person''s own recent searches and opened items (Dashboard resume cards), and who opened a proposal (the colleagues note). Own rows only; written by public.portal_activity_touch_v1 and public.portal_proposal_get_v1.';
create index portal_activity_user_seen_idx on pipeline.portal_activity (user_id, seen_at desc);
create index portal_activity_proposal_idx on pipeline.portal_activity (ref, seen_at desc) where kind = 'proposal';

-- 5. Each person's own preferences: colour theme, and the counsellor details printed on the student sheet.
create table pipeline.portal_user_prefs (
  user_id    uuid        primary key references auth.users (id),
  theme      text        check (theme is null or theme ~ '^[a-z]{2,20}$'),
  title      text        not null default '' check (length(title) <= 80),   -- fixed: a job title
  phone      text        not null default '' check (length(phone) <= 40),   -- fixed: a work phone
  office     text        not null default '' check (length(office) <= 120), -- fixed: an office name
  updated_at timestamptz not null default now()
);
comment on table pipeline.portal_user_prefs is 'StudySearch Portal (CF-247 s1210): each person''s own colour theme (one of the portal setting "themes") and the work title, phone and office printed as "your counsellor" on the student sheet. Own row only; written by public.portal_prefs_save_v1.';

-- 6. Row level security: Counsellor (rank 2) or above reads proposals and versions; a person reads only their own activity and preferences.
alter table pipeline.portal_proposals enable row level security;
alter table pipeline.portal_proposal_versions enable row level security;
alter table pipeline.portal_activity enable row level security;
alter table pipeline.portal_user_prefs enable row level security;
create policy portal_proposals_read on pipeline.portal_proposals for select to authenticated using (coalesce(security.current_role_rank(), 0) >= 2);
create policy portal_proposal_versions_read on pipeline.portal_proposal_versions for select to authenticated using (coalesce(security.current_role_rank(), 0) >= 2);
create policy portal_activity_own on pipeline.portal_activity for select to authenticated using (user_id = auth.uid() and coalesce(security.current_role_rank(), 0) >= 1);
create policy portal_user_prefs_own on pipeline.portal_user_prefs for select to authenticated using (user_id = auth.uid() and coalesce(security.current_role_rank(), 0) >= 1);
revoke all on pipeline.portal_proposals, pipeline.portal_proposal_versions, pipeline.portal_activity, pipeline.portal_user_prefs from public, anon, authenticated;
revoke all on sequence pipeline.portal_student_ref_seq from public, anon, authenticated;
revoke all on function pipeline.portal_proposal_versions_append_only_v1() from public, anon, authenticated;

-- 7. Internal helpers (granted to nobody).
create or replace function pipeline.portal_user_label_v1(p_user uuid)
returns text language sql stable security definer set search_path = '' as $function$
  select coalesce(nullif(btrim(u.raw_user_meta_data->>'full_name'), ''), nullif(btrim(u.raw_user_meta_data->>'name'), ''), split_part(u.email, '@', 1), 'A colleague')
    from auth.users u where u.id = p_user
$function$;
comment on function pipeline.portal_user_label_v1(uuid) is 'CF-247 s1210: the name the portal shows for a colleague (full name, name, or the part of the email before @).';

create or replace function pipeline.portal_money_text_v1(p_amount numeric, p_currency text)
returns text language sql immutable set search_path = '' as $function$
  select case when p_amount is null or p_amount <= 0 then null else coalesce(nullif(p_currency, ''), '') || ' ' || to_char(round(p_amount), 'FM999,999,999,990') end
$function$;
comment on function pipeline.portal_money_text_v1(numeric, text) is 'CF-247 s1210: an amount as the portal reads it (AUD 39,672).';

-- the course snapshot a proposal keeps, built from live rows in the order given; p_country is the student's country of education
create or replace function pipeline.portal_course_snapshot_v1(p_ids uuid[], p_country text default null)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'course_id', c.id,
      'title', coalesce(nullif(c.display_title, ''), c.canonical_title),
      'provider_id', p.id,
      'provider_name', coalesce(nullif(p.display_name, ''), p.canonical_name),
      'level', sl.name,
      'country_code', d.country_code,
      'state_code', coalesce(cam.state_code, ps.code),
      'city', coalesce(cam.city, p.primary_city),
      'duration_value', c.duration_value, 'duration_unit', c.duration_unit,
      'delivery_mode', case when cardinality(coalesce(d.delivery_modes, '{}')) = 0 then null
                            when cardinality(d.delivery_modes) = 1 then d.delivery_modes[1]
                            when d.delivery_modes @> array['on_campus', 'online'] then 'on_campus_and_online'
                            else d.delivery_modes[1] end,
      'fee', case when d.provider_annual_tuition_amount is not null then jsonb_build_object('per_year', d.provider_annual_tuition_amount, 'currency', d.provider_annual_tuition_currency) end,
      'next_intake', (select jsonb_build_object('label', i.intake_label, 'start_date', i.start_date) from catalogue.course_intakes i
                       where i.course_id = c.id and i.status = 'active' and (i.start_date is null or i.start_date >= (now() at time zone 'Australia/Melbourne')::date)  -- fixed: Melbourne day
                       order by i.start_date nulls last, i.id limit 1),
      'entry', (select jsonb_build_object('text', coalesce(nullif(r.min_entry_score_basis, ''), nullif(r.description, ''), r.quote))
                  from catalogue.course_entry_requirements r left join ref.countries rc on rc.id = r.country_id
                 where r.course_id = c.id and r.status = 'active' and coalesce(nullif(r.min_entry_score_basis, ''), nullif(r.description, ''), r.quote) is not null
                 order by (rc.iso_alpha2 is not distinct from p_country and p_country is not null) desc, (r.audience = 'international') desc, (r.country_id is null) desc, r.as_at desc nulls last, r.id
                 limit 1),
      'english', (select jsonb_build_object('text', concat_ws(' ', coalesce(e->>'test_name', e->>'test_code'), to_char((e->>'overall_score')::numeric, 'FM990.0') || ' overall',
                                                               '(no band below ' || to_char((select min(v::numeric) from jsonb_each_text(coalesce(e->'component_scores', '{}'::jsonb)) z(k, v) where v ~ '^[0-9.]+$'), 'FM990.0') || ')'))
                    from jsonb_array_elements(coalesce(d.english_requirement_options, '[]'::jsonb)) e
                   where e->>'overall_score' ~ '^[0-9.]+$'
                   order by (e->>'test_code' = 'IELTS') desc limit 1),
      'scholarship', (select jsonb_build_object('text', min(s->>'name') || case when count(*) > 1 then ' and ' || (count(*) - 1) || ' more' else '' end)
                        from jsonb_array_elements(coalesce(d.scholarship_options, '[]'::jsonb)) s
                       where coalesce(s->>'audience', 'international') in ('international', 'all', 'both') and s->>'name' is not null
                      having count(*) > 0),
      'available', c.lifecycle_status = 'active' and p.lifecycle_status = 'active',
      'course_url', coalesce(d.official_course_url, c.course_url),
      'provisional', false,
      'snapshot_at', now())
    order by x.ord), '[]'::jsonb)
  from unnest(p_ids) with ordinality x(id, ord)
  join catalogue.courses c on c.id = x.id
  join catalogue.providers p on p.id = c.provider_id
  left join search.course_documents d on d.course_id = c.id
  left join ref.study_levels sl on sl.id = c.study_level_id
  left join ref.subdivisions ps on ps.id = p.subdivision_id
  left join lateral (select ca.city, s.code state_code from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id left join ref.subdivisions s on s.id = ca.subdivision_id
                      where cc.course_id = c.id order by cc.is_primary desc nulls last, ca.city limit 1) cam on true
$function$;
comment on function pipeline.portal_course_snapshot_v1(uuid[], text) is 'CF-247 s1210: the course snapshot a proposal keeps: title, provider, level, place, length, delivery, fee, next intake, entry (preferring the student''s country), English, international scholarships, availability, link. Built from live rows; used by save and refresh.';

-- the differences between a version's saved snapshots and live rows; p_watch_only keeps fee, intake and availability (needs_refresh)
create or replace function pipeline.portal_proposal_changes_v1(p_courses jsonb, p_country text, p_watch_only boolean default false)
returns jsonb language sql stable security definer set search_path = '' as $function$
  with saved as (select s, o from jsonb_array_elements(coalesce(p_courses, '[]'::jsonb)) with ordinality z(s, o)),
       live as (select l from jsonb_array_elements(pipeline.portal_course_snapshot_v1(array(select (s->>'course_id')::uuid from saved order by o), p_country)) l),
       pairs as (select saved.o, saved.s->'snapshot' sv, coalesce(saved.s->'snapshot'->>'title', saved.s->>'course_id') ttl, saved.s->>'course_id' cid,
                        (select l from live where l->>'course_id' = saved.s->>'course_id') lv from saved)
  select coalesce(jsonb_agg(jsonb_build_object('course_id', cid, 'course_title', ttl, 'provider_name', coalesce(sv->>'provider_name', lv->>'provider_name'),
                                               'field', f.field, 'label', f.label, 'from_text', coalesce(f.from_text, 'Not recorded'), 'to_text', coalesce(f.to_text, 'Not recorded'))
                            order by o, f.n), '[]'::jsonb)
    from pairs cross join lateral (values
      (1, 'availability', 'Availability', case when coalesce((sv->>'available')::boolean, true) then 'Open' else 'No longer offered' end,
                                          case when coalesce((lv->>'available')::boolean, false) then 'Open' else 'No longer offered' end, true),
      (2, 'fee', 'Tuition fee', pipeline.portal_money_text_v1((sv->'fee'->>'per_year')::numeric, sv->'fee'->>'currency'),
                                pipeline.portal_money_text_v1((lv->'fee'->>'per_year')::numeric, lv->'fee'->>'currency'), true),
      (3, 'next_intake', 'Next intake', coalesce(sv->'next_intake'->>'label', sv->'next_intake'->>'start_date'), coalesce(lv->'next_intake'->>'label', lv->'next_intake'->>'start_date'), true),
      (4, 'entry', 'Entry requirement', sv->'entry'->>'text', lv->'entry'->>'text', false),
      (5, 'english', 'English requirement', sv->'english'->>'text', lv->'english'->>'text', false),
      (6, 'scholarship', 'Scholarship', sv->'scholarship'->>'text', lv->'scholarship'->>'text', false),
      (7, 'title', 'Course name', sv->>'title', lv->>'title', false)) f(n, field, label, from_text, to_text, watched)
   where (not p_watch_only or f.watched) and f.from_text is distinct from f.to_text
$function$;
comment on function pipeline.portal_proposal_changes_v1(jsonb, text, boolean) is 'CF-247 s1210: what moved between saved course snapshots and live rows, one row per course and field, in plain text. Fee, intake and availability are the watched fields (needs_refresh).';

-- the full proposal as the screens read it
create or replace function pipeline.portal_proposal_json_v1(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_p pipeline.portal_proposals%rowtype; v_v pipeline.portal_proposal_versions%rowtype; v_watch jsonb; v_hash text;
begin
  select * into v_p from pipeline.portal_proposals where id = p_id;
  if not found then return null; end if;
  select * into v_v from pipeline.portal_proposal_versions where proposal_id = v_p.id and version = v_p.current_version;
  v_watch := pipeline.portal_proposal_changes_v1(v_v.courses, v_p.source_country, true);
  v_hash := md5(v_watch::text);
  return jsonb_build_object(
    'id', v_p.id, 'version', v_p.current_version, 'status', v_p.status, 'title', v_p.title,
    'student', jsonb_build_object('ref', v_p.student_ref, 'given_name', v_p.given_name, 'family_initial', v_p.family_initial,
                                  'source_country', coalesce(v_p.source_country, ''), 'source_country_name', coalesce((select co.name from ref.countries co where co.iso_alpha2 = v_p.source_country), ''),
                                  'qualification', v_p.qualification, 'result_text', v_p.result_text, 'english_text', v_p.english_text,
                                  'destination', coalesce(v_p.destination, ''), 'preferred_intake', v_p.preferred_intake,
                                  'budget_per_year', coalesce(v_p.budget_per_year::text, ''), 'budget_currency', coalesce(v_p.budget_currency, '')),
    'courses', v_v.courses, 'steps', v_v.steps, 'documents', v_v.documents,
    'message_to_student', v_v.message_to_student, 'internal_note', v_v.internal_note,
    'needs_refresh', v_p.status <> 'archived' and jsonb_array_length(v_watch) > 0 and v_hash is distinct from v_p.kept_live_hash,
    'details_checked_at', coalesce(v_p.details_checked_at, v_v.edited_at),
    'built_at', v_v.edited_at,
    'created_at', v_p.created_at, 'updated_at', v_p.updated_at, 'expires_at', v_p.expires_at,
    'owner_id', v_p.owner_id, 'owner_name', pipeline.portal_user_label_v1(v_p.owner_id),
    'updated_by_name', pipeline.portal_user_label_v1(v_p.last_editor_id), 'updated_by_me', v_p.last_editor_id = auth.uid(),
    'last_editor_id', v_p.last_editor_id,
    'archived_at', v_p.archived_at, 'archived_by_name', case when v_p.archived_by is not null then pipeline.portal_user_label_v1(v_p.archived_by) end, 'archived_reason', v_p.archived_reason,
    'last_pdf_version', (select max(x.version) from pipeline.portal_proposal_versions x where x.proposal_id = v_p.id and x.status = 'sent'),
    'versions', coalesce((select jsonb_agg(jsonb_build_object('version', x.version, 'at', x.edited_at, 'by_name', pipeline.portal_user_label_v1(x.last_editor_id),
                                                              'note', x.note, 'status', x.status, 'saved_after_other_edit', x.saved_after_other_edit) order by x.version desc)
                            from pipeline.portal_proposal_versions x where x.proposal_id = v_p.id), '[]'::jsonb));
end $function$;
comment on function pipeline.portal_proposal_json_v1(uuid) is 'CF-247 s1210: one proposal as the portal screens read it (student, courses with snapshots, steps, documents, message, internal note, needs_refresh, versions, who saved last).';

-- the counsellor printed on the sheet (the proposal's owner, or the caller for a new proposal)
create or replace function pipeline.portal_counsellor_json_v1(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select jsonb_build_object('name', pipeline.portal_user_label_v1(u.id), 'title', coalesce(pr.title, ''), 'email', coalesce(u.email, ''),
                            'phone', coalesce(pr.phone, ''), 'office', coalesce(pr.office, ''))
    from auth.users u left join pipeline.portal_user_prefs pr on pr.user_id = u.id where u.id = p_user
$function$;
comment on function pipeline.portal_counsellor_json_v1(uuid) is 'CF-247 s1210: the counsellor details the student sheet prints (name, work title, email, work phone, office).';

-- the plain labels of what differs between two versions (the clash notice)
create or replace function pipeline.portal_version_diff_labels_v1(p_id uuid, p_from integer, p_to integer)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select coalesce(jsonb_agg(jsonb_build_object('label', f.label) order by f.n), '[]'::jsonb)
    from pipeline.portal_proposal_versions a join pipeline.portal_proposal_versions b on b.proposal_id = a.proposal_id
    cross join lateral (values
      (1, 'Status', a.status is distinct from b.status), (2, 'Title', a.title is distinct from b.title),
      (3, 'Student details', a.student is distinct from b.student),
      (4, 'Courses', (select jsonb_agg(x->>'course_id' order by o) from jsonb_array_elements(a.courses) with ordinality z(x, o)) is distinct from (select jsonb_agg(x->>'course_id' order by o) from jsonb_array_elements(b.courses) with ordinality z(x, o))),
      (5, '"Why this course" lines', (select jsonb_agg(x->>'why' order by o) from jsonb_array_elements(a.courses) with ordinality z(x, o)) is distinct from (select jsonb_agg(x->>'why' order by o) from jsonb_array_elements(b.courses) with ordinality z(x, o))),
      (6, 'Next steps', a.steps is distinct from b.steps), (7, 'Documents', a.documents is distinct from b.documents),
      (8, 'Message to the student', a.message_to_student is distinct from b.message_to_student),
      (9, 'Counsellor notes', a.internal_note is distinct from b.internal_note)) f(n, label, changed)
   where a.proposal_id = p_id and a.version = p_from and b.version = p_to and f.changed
$function$;
comment on function pipeline.portal_version_diff_labels_v1(uuid, integer, integer) is 'CF-247 s1210: which parts of a proposal differ between two versions, as plain labels.';

revoke all on function pipeline.portal_user_label_v1(uuid), pipeline.portal_money_text_v1(numeric, text), pipeline.portal_course_snapshot_v1(uuid[], text),
                       pipeline.portal_proposal_changes_v1(jsonb, text, boolean), pipeline.portal_proposal_json_v1(uuid), pipeline.portal_counsellor_json_v1(uuid),
                       pipeline.portal_version_diff_labels_v1(uuid, integer, integer) from public, anon, authenticated;

-- 8. List: Mine or Whole team, a status filter (with "needs_refresh"), a search by student name, reference or title, paged on the server.
create or replace function public.portal_proposal_list_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$  -- volatile: it fills a temporary working table
declare
  v_uid uuid := auth.uid();
  v_a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}'::jsonb end;
  v_scope text := case when v_a->>'scope' = 'team' then 'team' else 'mine' end;
  v_status text := lower(btrim(coalesce(v_a->>'status', '')));
  v_q text := nullif(btrim(regexp_replace(coalesce(v_a->>'q', ''), '\s+', ' ', 'g')), '');
  v_size integer := greatest(coalesce(security.portal_setting_v1('proposals_page_size'), 20), 1);  -- fixed: the setting's own default
  v_page integer := greatest(coalesce(case when v_a->>'page' ~ '^[0-9]{1,6}$' then (v_a->>'page')::int end, 1), 1);  -- fixed: a page number, not a limit
  v_items jsonb; v_total integer; v_needing integer;
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above
  create temp table if not exists portal_proposal_rows (id uuid primary key, updated_at timestamptz, mine boolean, status text, needs_refresh boolean) on commit drop;
  truncate pg_temp.portal_proposal_rows;
  insert into pg_temp.portal_proposal_rows
  select p.id, p.updated_at, p.owner_id = v_uid, p.status,
         p.status <> 'archived' and exists (select 1 from pipeline.portal_proposal_versions v where v.proposal_id = p.id and v.version = p.current_version
                                             and jsonb_array_length(pipeline.portal_proposal_changes_v1(v.courses, p.source_country, true)) > 0
                                             and md5(pipeline.portal_proposal_changes_v1(v.courses, p.source_country, true)::text) is distinct from p.kept_live_hash)
    from pipeline.portal_proposals p
   where (v_q is null or p.student_ref ilike security.portal_like_v1(v_q) or p.given_name ilike security.portal_like_v1(v_q) or p.title ilike security.portal_like_v1(v_q));

  select count(*) filter (where status <> 'archived' and (v_scope = 'team' or mine) and needs_refresh) into v_needing from pg_temp.portal_proposal_rows;
  select count(*) into v_total from pg_temp.portal_proposal_rows r
   where (v_scope = 'team' or r.mine)
     and case v_status when '' then r.status <> 'archived' when 'needs_refresh' then r.needs_refresh when 'all' then true else r.status = v_status end;
  v_items := coalesce((select jsonb_agg(x.j order by x.updated_at desc, x.id) from (
      select r.id, r.updated_at, jsonb_build_object(
               'id', p.id, 'title', p.title, 'status', p.status, 'needs_refresh', r.needs_refresh, 'version', p.current_version,
               'student', jsonb_build_object('ref', p.student_ref, 'given_name', p.given_name, 'family_initial', p.family_initial,
                                             'source_country_name', coalesce((select co.name from ref.countries co where co.iso_alpha2 = p.source_country), ''),
                                             'qualification', p.qualification, 'result_text', p.result_text, 'english_text', p.english_text, 'preferred_intake', p.preferred_intake),
               'courses', coalesce((select jsonb_agg(jsonb_build_object('course_id', c->>'course_id', 'title', c->'snapshot'->>'title', 'provider_name', c->'snapshot'->>'provider_name') order by o)
                                      from pipeline.portal_proposal_versions v, jsonb_array_elements(v.courses) with ordinality z(c, o)
                                     where v.proposal_id = p.id and v.version = p.current_version), '[]'::jsonb),
               'change_note', (select v.note from pipeline.portal_proposal_versions v where v.proposal_id = p.id and v.version = p.current_version),
               'updated_at', p.updated_at, 'updated_by_name', pipeline.portal_user_label_v1(p.last_editor_id), 'updated_by_me', p.last_editor_id = v_uid,
               'details_checked_at', coalesce(p.details_checked_at, (select v.edited_at from pipeline.portal_proposal_versions v where v.proposal_id = p.id and v.version = p.current_version)),
               'last_pdf_version', (select max(v.version) from pipeline.portal_proposal_versions v where v.proposal_id = p.id and v.status = 'sent'),
               'expires_at', p.expires_at) j
        from pg_temp.portal_proposal_rows r join pipeline.portal_proposals p on p.id = r.id
       where (v_scope = 'team' or r.mine)
         and case v_status when '' then r.status <> 'archived' when 'needs_refresh' then r.needs_refresh when 'all' then true else r.status = v_status end
       order by r.updated_at desc, r.id
       limit v_size offset (v_page - 1) * v_size) x), '[]'::jsonb);
  return jsonb_build_object('items', v_items, 'total', v_total, 'page', v_page, 'page_size', v_size,
    'facets', jsonb_build_object('counts', jsonb_build_object('mine', (select count(*) from pg_temp.portal_proposal_rows where mine and status <> 'archived'),
                                                              'team', (select count(*) from pg_temp.portal_proposal_rows where status <> 'archived')),
                                 'needs_refresh_count', v_needing));
end $function$;
comment on function public.portal_proposal_list_v1(jsonb) is 'CF-247 s1210 (Release 2 contract): proposals for the Proposals screen: scope mine or team, status (draft, ready, sent, accepted, archived, needs_refresh, or blank for all not archived), q (student name, reference or title), page. Counsellor and above.';

-- 9. Get: one proposal (or what a new one starts with), the limits, colleagues who opened it recently, and the counsellor for the sheet.
create or replace function public.portal_proposal_get_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid();
  v_a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}'::jsonb end;
  v_id uuid := case when v_a->>'id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (v_a->>'id')::uuid end;
  v_lock integer := greatest(coalesce(security.portal_setting_v1('edit_lock_minutes'), 15), 1);  -- fixed: the setting's own default
  v_p pipeline.portal_proposals%rowtype; v_others jsonb := '[]'::jsonb;
  v_limits jsonb := jsonb_build_object(
    'courses_max', coalesce(security.portal_setting_v1('proposal_max_courses'), 12), 'message_max_chars', coalesce(security.portal_setting_v1('proposal_message_max_chars'), 3000),
    'note_max_chars', coalesce(security.portal_setting_v1('proposal_note_max_chars'), 2000), 'why_max_chars', coalesce(security.portal_setting_v1('proposal_why_max_chars'), 300));  -- fixed: the settings' own defaults
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above
  if v_id is null then
    if nullif(btrim(coalesce(v_a->>'id', '')), '') is not null then raise exception 'proposal not found' using errcode = 'P0002'; end if;
    return jsonb_build_object('proposal', null,
      'defaults', jsonb_build_object(
        'steps', coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'portal' and s.key = 'proposal_default_steps'), '[]'::jsonb),
        'documents', coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'portal' and s.key = 'proposal_default_documents'), '[]'::jsonb)),
      'limits', v_limits, 'others_recent', '[]'::jsonb, 'soft_lock_minutes', v_lock, 'counsellor', pipeline.portal_counsellor_json_v1(v_uid));
  end if;
  select * into v_p from pipeline.portal_proposals where id = v_id;
  if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
  -- colleagues who opened it within the soft-lock window (read before this open is recorded)
  v_others := coalesce((select jsonb_agg(jsonb_build_object('name', pipeline.portal_user_label_v1(a.user_id), 'opened_at', a.seen_at) order by a.seen_at desc)
                          from pipeline.portal_activity a
                         where a.kind = 'proposal' and a.ref = v_p.id::text and a.user_id <> v_uid and a.seen_at > now() - make_interval(mins => v_lock)), '[]'::jsonb);
  insert into pipeline.portal_activity (user_id, kind, ref, label, state, seen_at)
  values (v_uid, 'proposal', v_p.id::text, left(v_p.student_ref || ' ' || v_p.given_name || case when v_p.family_initial <> '' then ' ' || v_p.family_initial || '.' else '' end, 200), '{}'::jsonb, now())
  on conflict (user_id, kind, ref) do update set label = excluded.label, seen_at = excluded.seen_at;
  return jsonb_build_object('proposal', pipeline.portal_proposal_json_v1(v_p.id), 'limits', v_limits, 'others_recent', v_others,
                            'soft_lock_minutes', v_lock, 'counsellor', pipeline.portal_counsellor_json_v1(v_p.owner_id));
end $function$;
comment on function public.portal_proposal_get_v1(jsonb) is 'CF-247 s1210 (Release 2 contract): one proposal, or defaults for a new one (id null), with limits, colleagues who opened it within edit_lock_minutes, and the counsellor for the sheet. Records the open. Counsellor and above.';

-- 10. Save: create, duplicate, or save a new version. A save based on an older version than the current one writes nothing unless forced.
create or replace function public.portal_proposal_save_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid();
  v_a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}'::jsonb end;
  v_in jsonb := case when jsonb_typeof(p_args->'proposal') = 'object' then p_args->'proposal' else '{}'::jsonb end;
  v_id uuid := case when v_a->>'id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (v_a->>'id')::uuid end;
  v_dup uuid := case when v_a->>'duplicate_of' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (v_a->>'duplicate_of')::uuid end;
  v_base integer := case when v_a->>'base_version' ~ '^[0-9]{1,9}$' then (v_a->>'base_version')::int end;
  v_force boolean := coalesce(case when jsonb_typeof(v_a->'force') = 'boolean' then (v_a->>'force')::boolean end, false);
  v_note text := left(btrim(regexp_replace(coalesce(v_a->>'note', ''), '\s+', ' ', 'g')), 200);  -- fixed: the column's own limit
  v_max integer := greatest(coalesce(security.portal_setting_v1('proposal_max_courses'), 12), 1);  -- fixed: the settings' own defaults
  v_msg_max integer := greatest(coalesce(security.portal_setting_v1('proposal_message_max_chars'), 3000), 1);
  v_note_max integer := greatest(coalesce(security.portal_setting_v1('proposal_note_max_chars'), 2000), 1);
  v_why_max integer := greatest(coalesce(security.portal_setting_v1('proposal_why_max_chars'), 300), 1);
  v_keep integer := greatest(coalesce(security.portal_setting_v1('proposal_retention_months'), 12), 1);
  v_p pipeline.portal_proposals%rowtype; v_src pipeline.portal_proposal_versions%rowtype;
  v_st jsonb; v_status text; v_given text; v_initial text; v_ref text; v_country text; v_dest text; v_budget numeric; v_bcur text;
  v_courses jsonb; v_ids uuid[]; v_snap jsonb; v_steps jsonb; v_docs jsonb; v_msg text; v_inote text; v_title text;
  v_ver integer; v_forced boolean := false; v_prev_status text;
  v_live boolean := coalesce(case when jsonb_typeof(p_args->'live_snapshots') = 'boolean' then (p_args->>'live_snapshots')::boolean end, false);
  v_old jsonb := '{}'::jsonb;
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above; Viewers cannot save or see proposals

  -- a duplicate copies the source's current version into a new draft for the same student
  if v_dup is not null and v_id is null then
    select * into v_p from pipeline.portal_proposals where id = v_dup;
    if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
    select * into v_src from pipeline.portal_proposal_versions where proposal_id = v_p.id and version = v_p.current_version;
    v_in := jsonb_build_object('title', left(case when v_p.title = '' then 'Study options' else v_p.title end || ' (copy)', 200), 'status', 'draft',
                               'student', v_src.student, 'courses', v_src.courses, 'steps', v_src.steps, 'documents', v_src.documents,
                               'message_to_student', v_src.message_to_student, 'internal_note', v_src.internal_note);
    if v_note = '' then v_note := 'copy of ' || v_p.student_ref || ' v' || v_p.current_version; end if;
    v_p := null;
  end if;

  -- what was sent, checked and limited (the screens check the same limits, which they read from portal_proposal_get_v1)
  v_st := case when jsonb_typeof(v_in->'student') = 'object' then v_in->'student' else '{}'::jsonb end;
  v_status := lower(btrim(coalesce(v_in->>'status', '')));
  if v_status = '' then v_status := null; end if;
  if v_status is not null and v_status not in ('draft', 'ready', 'sent', 'accepted', 'archived') then
    raise exception 'a proposal status is draft, ready, sent, accepted or archived' using errcode = '22023';
  end if;
  v_given := left(btrim(regexp_replace(coalesce(v_st->>'given_name', ''), '\s+', ' ', 'g')), 40);  -- fixed: the column's own limit
  v_initial := upper(left(regexp_replace(coalesce(v_st->>'family_initial', ''), '[^A-Za-z]', '', 'g'), 1));
  if length(regexp_replace(coalesce(v_st->>'family_initial', ''), '[^A-Za-z]', '', 'g')) > 1 then
    raise exception 'the family name initial is one letter only; no full family name is stored' using errcode = '22023';
  end if;
  v_country := case when upper(btrim(coalesce(v_st->>'source_country', ''))) ~ '^[A-Z]{2}$' then upper(btrim(v_st->>'source_country')) end;
  v_dest := case when upper(btrim(coalesce(v_st->>'destination', ''))) ~ '^[A-Z]{2}$' then upper(btrim(v_st->>'destination')) end;
  v_budget := case when btrim(coalesce(v_st->>'budget_per_year', '')) ~ '^[0-9]{1,9}(\.[0-9]{1,2})?$' and (v_st->>'budget_per_year')::numeric > 0 then (v_st->>'budget_per_year')::numeric end;
  v_bcur := case when v_budget is not null and upper(btrim(coalesce(v_st->>'budget_currency', ''))) ~ '^[A-Z]{3}$' then upper(btrim(v_st->>'budget_currency')) end;
  v_title := left(btrim(regexp_replace(coalesce(v_in->>'title', ''), '\s+', ' ', 'g')), 200);  -- fixed: the column's own limit
  v_msg := coalesce(v_in->>'message_to_student', '');
  v_inote := coalesce(v_in->>'internal_note', '');
  if length(v_msg) > v_msg_max then raise exception 'the message to the student is longer than % characters', v_msg_max using errcode = '22023'; end if;
  if length(v_inote) > v_note_max then raise exception 'the counsellor notes are longer than % characters', v_note_max using errcode = '22023'; end if;
  v_steps := coalesce((select jsonb_agg(jsonb_build_object('key', nullif(left(s->>'key', 60), ''), 'title', left(coalesce(s->>'title', ''), 200), 'detail', left(coalesce(s->>'detail', ''), 1000),  -- fixed: short step text
                                                           'owner', case when s->>'owner' = 'student' then 'student' else 'counsellor' end, 'due_label', left(coalesce(s->>'due_label', ''), 60),
                                                           'due_date', case when s->>'due_date' ~ '^\d{4}-\d{2}-\d{2}$' then s->>'due_date' end,
                                                           'included', coalesce(case when jsonb_typeof(s->'included') = 'boolean' then (s->>'included')::boolean end, true)) order by o)
                         from jsonb_array_elements(case when jsonb_typeof(v_in->'steps') = 'array' then v_in->'steps' else '[]'::jsonb end) with ordinality z(s, o)
                        where jsonb_typeof(s) = 'object' and btrim(coalesce(s->>'title', '')) <> ''), '[]'::jsonb);
  v_docs := coalesce((select jsonb_agg(left(btrim(d #>> '{}'), 200) order by o)  -- fixed: a short document name
                        from jsonb_array_elements(case when jsonb_typeof(v_in->'documents') = 'array' then v_in->'documents' else '[]'::jsonb end) with ordinality z(d, o)
                       where jsonb_typeof(d) = 'string' and btrim(d #>> '{}') <> ''), '[]'::jsonb);
  -- the courses: ids in position order, each once; anything that is not a live course id is dropped
  with raw as (
    select o, case when jsonb_typeof(c) = 'object' then c->>'course_id' when jsonb_typeof(c) = 'string' then c #>> '{}' end id_text,
           case when jsonb_typeof(c) = 'object' and c->>'position' ~ '^[0-9]{1,4}$' then (c->>'position')::int end pos,
           case when jsonb_typeof(c) = 'object' then btrim(coalesce(c->>'why', '')) else '' end why
      from jsonb_array_elements(case when jsonb_typeof(v_in->'courses') = 'array' then v_in->'courses' else '[]'::jsonb end) with ordinality z(c, o)),
  typed as (select o, coalesce(pos, 100000 + o) pos, why, case when id_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then id_text::uuid end id from raw),
  firsts as (select distinct on (t.id) t.* from typed t join catalogue.courses c on c.id = t.id order by t.id, t.pos, t.o)
  select jsonb_agg(jsonb_build_object('course_id', id, 'why', why) order by pos, o) into v_courses from firsts;
  v_courses := coalesce(v_courses, '[]'::jsonb);
  if jsonb_array_length(v_courses) > v_max then
    raise exception 'a proposal holds up to % courses (% chosen)', v_max, jsonb_array_length(v_courses) using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(v_courses) c where length(c->>'why') > v_why_max) then
    raise exception 'a "why this course" line is longer than % characters', v_why_max using errcode = '22023';
  end if;

  -- an existing proposal: the clash check comes first; nothing is written when someone saved after base_version, unless forced
  if v_id is not null then
    select * into v_p from pipeline.portal_proposals where id = v_id for update;
    if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
    if v_base is not null and v_base <> v_p.current_version then
      if not v_force then
        return jsonb_build_object('status', 'saved_after_other_edit', 'current_version', v_p.current_version,
                                  'by_name', pipeline.portal_user_label_v1(v_p.last_editor_id), 'saved_at', v_p.updated_at,
                                  'changes', case when v_base between 1 and v_p.current_version then pipeline.portal_version_diff_labels_v1(v_p.id, v_base, v_p.current_version) else '[]'::jsonb end,
                                  'proposal', pipeline.portal_proposal_json_v1(v_p.id));
      end if;
      v_forced := true;
    end if;
    if v_given = '' then v_given := v_p.given_name; end if;
    -- the snapshots already held are kept on an ordinary save (a refresh never happens on its own); only refresh accept rebuilds them
    select coalesce(jsonb_object_agg(c->>'course_id', c->'snapshot'), '{}'::jsonb) into v_old
      from pipeline.portal_proposal_versions v, jsonb_array_elements(v.courses) c
     where v.proposal_id = v_p.id and v.version = v_p.current_version and c ? 'snapshot';
  end if;
  if v_given = '' then raise exception 'add the student''s given name' using errcode = '22023'; end if;

  -- a course already in the proposal keeps its snapshot unless live values were accepted; a newly added course is snapshotted from live rows now
  v_snap := (select coalesce(jsonb_agg(jsonb_build_object('course_id', c->>'course_id', 'position', o, 'why', c->>'why',
                                                         'snapshot', case when not v_live and v_old ? (c->>'course_id') then v_old->(c->>'course_id') else q.s end) order by o), '[]'::jsonb)
               from jsonb_array_elements(v_courses) with ordinality z(c, o)
               left join lateral (select x s from jsonb_array_elements(pipeline.portal_course_snapshot_v1(array[(c->>'course_id')::uuid], v_country)) x) q on true);

  if v_p.id is null then
    v_ref := upper(btrim(coalesce(v_st->>'ref', v_st->>'student_ref', '')));
    if v_ref = '' or v_ref !~ '^[A-Z0-9-]{3,20}$' or not exists (select 1 from pipeline.portal_proposals where student_ref = v_ref) then
      v_ref := 'SS-' || lpad(nextval('pipeline.portal_student_ref_seq')::text, 6, '0');  -- fixed: the reference format
    end if;
    v_status := coalesce(v_status, 'draft');
    insert into pipeline.portal_proposals (student_ref, given_name, family_initial, source_country, qualification, result_text, english_text, destination,
                                           preferred_intake, budget_per_year, budget_currency, title, status, owner_id, last_editor_id, current_version,
                                           expires_at, details_checked_at, archived_at, archived_by, archived_reason)
    values (v_ref, v_given, v_initial, v_country, left(btrim(coalesce(v_st->>'qualification', '')), 120), left(btrim(coalesce(v_st->>'result_text', '')), 120),
            left(btrim(coalesce(v_st->>'english_text', '')), 120), v_dest, left(btrim(coalesce(v_st->>'preferred_intake', '')), 60), v_budget, v_bcur,
            v_title, v_status, v_uid, v_uid, 1, now() + make_interval(months => v_keep), now(),
            case when v_status = 'archived' then now() end, case when v_status = 'archived' then v_uid end,
            case when v_status = 'archived' then coalesce(nullif(v_note, ''), 'Archived in the proposal editor') end)
    returning * into v_p;
    v_ver := 1;
    if v_note = '' then v_note := 'created'; end if;
  else
    v_prev_status := v_p.status;
    v_status := coalesce(v_status, v_p.status);
    v_ver := v_p.current_version + 1;
    if v_note = '' then
      v_note := case when v_status = 'archived' and v_prev_status <> 'archived' then 'archived'
                     when v_prev_status = 'archived' and v_status <> 'archived' then 'restored'
                     when v_status <> v_prev_status then 'marked ' || v_status
                     when v_forced then 'saved over a newer version' else '' end;
    end if;
    update pipeline.portal_proposals set
      given_name = v_given, family_initial = v_initial, source_country = v_country,
      qualification = left(btrim(coalesce(v_st->>'qualification', '')), 120), result_text = left(btrim(coalesce(v_st->>'result_text', '')), 120),
      english_text = left(btrim(coalesce(v_st->>'english_text', '')), 120), destination = v_dest, preferred_intake = left(btrim(coalesce(v_st->>'preferred_intake', '')), 60),
      budget_per_year = v_budget, budget_currency = v_bcur, title = v_title, status = v_status,
      last_editor_id = v_uid, current_version = v_ver, updated_at = now(), expires_at = now() + make_interval(months => v_keep),
      details_checked_at = case when v_live then now() else details_checked_at end, kept_live_hash = case when v_live then null else kept_live_hash end,
      archived_at = case when v_status = 'archived' then coalesce(archived_at, now()) end,
      archived_by = case when v_status = 'archived' then coalesce(archived_by, v_uid) end,
      archived_reason = case when v_status = 'archived' then coalesce(archived_reason, nullif(v_a->>'note', ''), 'Archived in the proposal editor') end
     where id = v_p.id
     returning * into v_p;
  end if;

  insert into pipeline.portal_proposal_versions (proposal_id, version, last_editor_id, note, status, title, student, courses, steps, documents,
                                                 message_to_student, internal_note, refreshed_from, saved_after_other_edit)
  values (v_p.id, v_ver, v_uid, v_note, v_p.status, v_p.title,
          jsonb_build_object('ref', v_p.student_ref, 'given_name', v_p.given_name, 'family_initial', v_p.family_initial, 'source_country', coalesce(v_p.source_country, ''),
                             'qualification', v_p.qualification, 'result_text', v_p.result_text, 'english_text', v_p.english_text, 'destination', coalesce(v_p.destination, ''),
                             'preferred_intake', v_p.preferred_intake, 'budget_per_year', coalesce(v_p.budget_per_year::text, ''), 'budget_currency', coalesce(v_p.budget_currency, '')),
          v_snap, v_steps, v_docs, v_msg, v_inote,
          case when v_a->>'refreshed_from' ~ '^[0-9]{1,9}$' and (v_a->>'refreshed_from')::int between 1 and v_ver - 1 then (v_a->>'refreshed_from')::int end, v_forced);

  insert into pipeline.portal_activity (user_id, kind, ref, label, state, seen_at)
  values (v_uid, 'proposal', v_p.id::text, left(v_p.student_ref || ' ' || v_p.given_name || case when v_p.family_initial <> '' then ' ' || v_p.family_initial || '.' else '' end, 200), '{}'::jsonb, now())
  on conflict (user_id, kind, ref) do update set label = excluded.label, seen_at = excluded.seen_at;

  return jsonb_build_object('status', 'saved', 'id', v_p.id, 'version', v_ver, 'saved_after_other_edit', v_forced, 'proposal', pipeline.portal_proposal_json_v1(v_p.id));
end $function$;
comment on function public.portal_proposal_save_v1(jsonb) is 'CF-247 s1210 (Release 2 contract): creates (id null), duplicates (duplicate_of) or saves a new version; status changes include ready, archived (with a reason) and restore. A save on an older base_version writes nothing unless force, answering saved_after_other_edit with who, when and what changed. Course snapshots are built from live rows. Counsellor and above.';

-- 11. Refresh: compare the saved snapshots with live rows. No decision: the differences only. accept: a new version with the live values.
--     keep: no new version; the needs-refresh notice is cleared until the live values move again.
create or replace function public.portal_proposal_refresh_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}'::jsonb end;
  v_id uuid := case when v_a->>'id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (v_a->>'id')::uuid end;
  v_decision text := lower(btrim(coalesce(v_a->>'decision', '')));
  v_p pipeline.portal_proposals%rowtype; v_v pipeline.portal_proposal_versions%rowtype; v_res jsonb;
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above
  select * into v_p from pipeline.portal_proposals where id = v_id;
  if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
  select * into v_v from pipeline.portal_proposal_versions where proposal_id = v_p.id and version = v_p.current_version;
  if v_decision = '' then
    return jsonb_build_object('checked_at', now(), 'built_at', v_v.edited_at, 'changes', pipeline.portal_proposal_changes_v1(v_v.courses, v_p.source_country, false));
  elsif v_decision = 'keep' then
    update pipeline.portal_proposals set kept_live_hash = md5(pipeline.portal_proposal_changes_v1(v_v.courses, v_p.source_country, true)::text), details_checked_at = now()
     where id = v_p.id;
    return jsonb_build_object('status', 'kept', 'checked_at', now());
  elsif v_decision = 'accept' then
    -- the same save, from the current version's content, with base_version guarding the clash
    v_res := public.portal_proposal_save_v1(jsonb_build_object('id', v_p.id, 'base_version', v_a->'base_version', 'force', false, 'note', 'live details accepted', 'live_snapshots', true,
               'refreshed_from', v_p.current_version,
               'proposal', jsonb_build_object('title', v_p.title, 'status', v_p.status, 'student', v_v.student, 'courses', v_v.courses, 'steps', v_v.steps,
                                              'documents', v_v.documents, 'message_to_student', v_v.message_to_student, 'internal_note', v_v.internal_note)));
    return v_res;
  end if;
  raise exception 'decision is accept, keep, or left out' using errcode = '22023';
end $function$;
comment on function public.portal_proposal_refresh_v1(jsonb) is 'CF-247 s1210 (Release 2 contract): compares saved course snapshots with live rows (availability, fee, next intake, entry, English, scholarship, name). No decision: differences only. accept: a new version with live values (clash-guarded). keep: clears the notice until values move again. Counsellor and above.';

-- 12. Archive with a reason (the editor also archives through save with status archived). Never a delete.
create or replace function public.portal_proposal_archive_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}'::jsonb end;
  v_id uuid := case when v_a->>'id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (v_a->>'id')::uuid end;
  v_reason text := left(btrim(regexp_replace(coalesce(v_a->>'reason', ''), '\s+', ' ', 'g')), 200);  -- fixed: the version note's own limit
  v_p pipeline.portal_proposals%rowtype; v_v pipeline.portal_proposal_versions%rowtype;
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above
  if v_reason = '' then raise exception 'archiving needs a reason' using errcode = '22023'; end if;
  select * into v_p from pipeline.portal_proposals where id = v_id;
  if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
  if v_p.status = 'archived' then return jsonb_build_object('status', 'saved', 'id', v_p.id, 'version', v_p.current_version, 'proposal', pipeline.portal_proposal_json_v1(v_p.id)); end if;
  select * into v_v from pipeline.portal_proposal_versions where proposal_id = v_p.id and version = v_p.current_version;
  return public.portal_proposal_save_v1(jsonb_build_object('id', v_p.id, 'base_version', v_p.current_version, 'note', v_reason,
           'proposal', jsonb_build_object('title', v_p.title, 'status', 'archived', 'student', v_v.student, 'courses', v_v.courses, 'steps', v_v.steps,
                                          'documents', v_v.documents, 'message_to_student', v_v.message_to_student, 'internal_note', v_v.internal_note)));
end $function$;
comment on function public.portal_proposal_archive_v1(jsonb) is 'CF-247 s1210: archives a proposal with a reason (id, reason), as a new version; who, when and why are kept; restoring is a save with another status. Never deletes. Counsellor and above.';

-- 13. Activity (own rows): Viewer and above; proposal items need Counsellor and above.
create or replace function public.portal_activity_touch_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid(); v_rank smallint;
  v_a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}'::jsonb end;
  v_kind text := lower(btrim(coalesce(v_a->>'kind', '')));
  v_ref text := left(btrim(coalesce(v_a->>'ref', '')), 200);  -- fixed: the column's own limit
  v_label text := left(btrim(regexp_replace(coalesce(v_a->>'label', ''), '\s+', ' ', 'g')), 200);
  v_state jsonb := case when jsonb_typeof(v_a->'state') = 'object' and pg_column_size(v_a->'state') <= 8192 then v_a->'state' else '{}'::jsonb end;  -- fixed: the column's own limit
begin
  v_rank := security.portal_rank_v1(1);  -- fixed: Viewer and above
  if v_kind not in ('courses_search', 'proposal', 'provider', 'scholarship') then
    raise exception 'activity kind is courses_search, proposal, provider or scholarship' using errcode = '22023';
  end if;
  if v_kind = 'proposal' and v_rank < 2 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;  -- fixed: proposals are Counsellor and above
  if v_ref = '' then raise exception 'activity needs a reference' using errcode = '22023'; end if;
  if v_label = '' then v_label := v_ref; end if;
  insert into pipeline.portal_activity (user_id, kind, ref, label, state, seen_at) values (v_uid, v_kind, v_ref, v_label, v_state, now())
  on conflict (user_id, kind, ref) do update set label = excluded.label, state = excluded.state, seen_at = excluded.seen_at;
  return jsonb_build_object('kind', v_kind, 'ref', v_ref, 'label', v_label, 'state', v_state, 'seen_at', now());
end $function$;
comment on function public.portal_activity_touch_v1(jsonb) is 'CF-247 s1210: records the person''s own recent search or opened item (kind, ref, label, state) for the Dashboard resume cards. Viewer and above; proposal items Counsellor and above.';

create or replace function public.portal_activity_list_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_rank smallint; v_cap integer := greatest(coalesce(security.portal_setting_v1('resume_items_shown'), 6), 1);  -- fixed: the setting's own default
  v_a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}'::jsonb end;
  v_lim integer := case when v_a->>'limit' ~ '^[0-9]{1,4}$' then (v_a->>'limit')::int end;
begin
  v_rank := security.portal_rank_v1(1);  -- fixed: Viewer and above
  return jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('kind', a.kind, 'ref', a.ref, 'label', a.label, 'state', a.state, 'seen_at', a.seen_at) order by a.seen_at desc)
    from (select * from pipeline.portal_activity a where a.user_id = auth.uid() and (a.kind <> 'proposal' or v_rank >= 2)  -- fixed: proposals are Counsellor and above
           order by a.seen_at desc limit least(greatest(coalesce(v_lim, v_cap), 1), v_cap)) a), '[]'::jsonb));
end $function$;
comment on function public.portal_activity_list_v1(jsonb) is 'CF-247 s1210: the person''s own recent searches and opened items, newest first, at most resume_items_shown. Viewer and above.';

-- 14. Preferences (own row): theme, and the work title, phone and office printed on the sheet. Called with {} it returns the current values.
create or replace function public.portal_prefs_save_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid();
  v_a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}'::jsonb end;
  v_theme text := nullif(lower(btrim(coalesce(v_a->>'theme', ''))), '');
  v_themes jsonb := coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'portal' and s.key = 'themes'), '[]'::jsonb);
  v_row pipeline.portal_user_prefs%rowtype;
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  if v_theme is not null and not (v_themes ? v_theme) then raise exception 'that theme is not offered (see the portal setting "themes")' using errcode = '22023'; end if;
  if v_theme is not null or v_a ? 'title' or v_a ? 'phone' or v_a ? 'office' then
    insert into pipeline.portal_user_prefs (user_id, theme, title, phone, office, updated_at)
    values (v_uid, v_theme, left(btrim(coalesce(v_a->>'title', '')), 80), left(btrim(coalesce(v_a->>'phone', '')), 40), left(btrim(coalesce(v_a->>'office', '')), 120), now())  -- fixed: the columns' own limits
    on conflict (user_id) do update set
      theme = coalesce(excluded.theme, pipeline.portal_user_prefs.theme),
      title = case when v_a ? 'title' then excluded.title else pipeline.portal_user_prefs.title end,
      phone = case when v_a ? 'phone' then excluded.phone else pipeline.portal_user_prefs.phone end,
      office = case when v_a ? 'office' then excluded.office else pipeline.portal_user_prefs.office end,
      updated_at = now();
  end if;
  select * into v_row from pipeline.portal_user_prefs where user_id = v_uid;
  return jsonb_build_object('theme', coalesce(v_row.theme, v_themes->>0), 'title', coalesce(v_row.title, ''), 'phone', coalesce(v_row.phone, ''),
                            'office', coalesce(v_row.office, ''), 'themes', v_themes, 'updated_at', v_row.updated_at);
end $function$;
comment on function public.portal_prefs_save_v1(jsonb) is 'CF-247 s1210: saves the person''s own theme (one of the portal setting "themes") and the work title, phone and office printed on the student sheet; with {} returns the current values. Viewer and above.';

-- 15. Who may call them: signed-in people only (anon has none); each function checks the role itself.
revoke all on function public.portal_proposal_list_v1(jsonb), public.portal_proposal_get_v1(jsonb), public.portal_proposal_save_v1(jsonb),
                       public.portal_proposal_refresh_v1(jsonb), public.portal_proposal_archive_v1(jsonb),
                       public.portal_activity_touch_v1(jsonb), public.portal_activity_list_v1(jsonb), public.portal_prefs_save_v1(jsonb) from public, anon;
grant execute on function public.portal_proposal_list_v1(jsonb), public.portal_proposal_get_v1(jsonb), public.portal_proposal_save_v1(jsonb),
                          public.portal_proposal_refresh_v1(jsonb), public.portal_proposal_archive_v1(jsonb),
                          public.portal_activity_touch_v1(jsonb), public.portal_activity_list_v1(jsonb), public.portal_prefs_save_v1(jsonb) to authenticated;

do $post$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1210_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1210_guard) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'portal' and key in ('proposal_max_courses', 'proposal_message_max_chars', 'proposal_note_max_chars',
        'proposal_why_max_chars', 'edit_lock_minutes', 'proposals_page_size', 'proposal_retention_months', 'resume_items_shown', 'themes', 'proposal_default_steps', 'proposal_default_documents')) <> 11 then
    raise exception 'post-check: the eleven s1210 settings are not all present';
  end if;
  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'pipeline' and c.relname in ('portal_proposals', 'portal_proposal_versions', 'portal_activity', 'portal_user_prefs') and c.relrowsecurity) <> 4 then
    raise exception 'post-check: row level security is not on for all four tables';
  end if;
  if has_table_privilege('authenticated', 'pipeline.portal_proposals', 'SELECT') or has_table_privilege('anon', 'pipeline.portal_proposal_versions', 'SELECT')
     or has_function_privilege('anon', 'public.portal_proposal_get_v1(jsonb)', 'EXECUTE') or has_function_privilege('anon', 'public.portal_prefs_save_v1(jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'pipeline.portal_course_snapshot_v1(uuid[], text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'pipeline.portal_proposal_json_v1(uuid)', 'EXECUTE') then
    raise exception 'post-check: a table or helper is reachable outside the portal functions';
  end if;
end $post$;
