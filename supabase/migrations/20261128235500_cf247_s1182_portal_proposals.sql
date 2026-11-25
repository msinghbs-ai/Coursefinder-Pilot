-- CF-247 s1182 (S2-Build; Platform Admin brief 26 Nov 2026 07:01 AEDT, "Portal Release 2 Backend"): the StudySearch Portal's proposal layer.
-- Design: admin docs/platform/2026-11-25-studysearch-portal-design-decisions-and-plan.md (decisions 25 Nov 10:37 and 10:45) and the reference draft
-- M3 > Portal > DRAFT-portal-proposals-schema.sql, with these changes from the draft:
--   * the student lives on the proposal row (student_ref, given_name, family_initial only; no full name, contact, passport or country is held);
--     a later proposal for the same student reuses the reference;
--   * the course snapshot is built on the server from live rows (pipeline.portal_course_snapshot_v1), so save and refresh compare like with like
--     and nothing the browser sends is trusted as a fee, intake or title;
--   * versions are append only (a trigger refuses update and delete); every version names its editor and records saved_after_other_edit;
--   * archived_at, archived_by and archived_reason on the proposal; archiving never deletes;
--   * limits are settings in the existing portal toolset (s1143), read with security.portal_setting_v1; the themes list is a setting too (s930);
--   * public.portal_activity_list_v1 (the person's own resume items) is added so the Dashboard can read what portal_activity_touch_v1 writes.
-- Access: every function checks the person's own role through security.portal_rank_v1 (s1143). Viewer (rank 1) and above: activity and preferences
-- (own rows only). Counsellor (rank 2) and above: every proposal function. Tables are reached only through these security definer functions;
-- row level security is on with matching read policies, and no table privilege is granted to anon or authenticated.
-- Not in this change (named in the draft): public.portal_dashboard_v1 and the server PDF cap (portal Worker lane); a Platform Admin privacy
-- deletion, which will be a paste file because nothing is deleted by an applied migration. The portal calls with each person's own sign-in,
-- so no API key is issued (s935 applies to key-signed consumers).
-- G1: no job. G2: five settings below, each with a label, range, unit and used_by. G3: nothing the website, Zoho or the Admin app reads is
-- touched; new objects only, checked before and after. Manual locks and active cron jobs are checked unchanged. Nothing dropped or deleted.
-- No AI or Firecrawl call.
-- Replaces: nothing (new tables and functions).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the new objects

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'pipeline' and table_name in ('portal_proposals', 'portal_proposal_versions', 'portal_activity', 'portal_user_prefs')) then
    raise exception 'pre-check: a portal proposal table already exists';
  end if;
end $pre$;
create temp table s1182_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

-- 1. Settings (G2), in the portal toolset from s1143. They show on Settings › Toolsets & limits.
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
 ('portal', 'proposal_max_courses', 'Proposals: most courses in one proposal', 'The most courses one student proposal can hold. A larger selection is refused with a plain message.',
  'number', '12'::jsonb, 1, 50, 'courses', 6110, 'Portal', 'public.portal_proposal_save_v1', 'CF-247 s1182: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'edit_lock_minutes', 'Proposals: how long an open or a save is shown to others', 'While someone has a proposal open, or saved it this recently, others see a note. It never blocks a save.',
  'number', '15'::jsonb, 1, 120, 'minutes', 6120, 'Portal', 'public.portal_proposal_open_v1, public.portal_proposal_save_v1', 'CF-247 s1182: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'proposals_page_size', 'Proposals: most found in one search', 'The most proposals the Proposals list returns at once, newest first.',
  'number', '50'::jsonb, 10, 200, 'proposals', 6130, 'Portal', 'public.portal_proposal_find_v1', 'CF-247 s1182: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'resume_items_shown', 'Dashboard: resume items shown', 'How many of a person''s own recent searches and opened items the Dashboard resume cards list.',
  'number', '6'::jsonb, 1, 20, 'items', 6140, 'Portal', 'public.portal_activity_list_v1', 'CF-247 s1182: Portal Release 2 (Platform Admin 26 Nov 2026)'),
 ('portal', 'themes', 'Portal: colour themes a person can choose', 'The colour themes offered in the portal. A theme not in this list is refused.',
  'list', '["indigo", "ocean", "forest", "plum", "graphite"]'::jsonb, null, null, 'themes', 6150, 'Portal', 'public.portal_prefs_save_v1', 'CF-247 s1182: Portal Release 2 (Platform Admin 26 Nov 2026)')
on conflict do nothing;

-- 2. Proposals: one row per proposal; the student is kept to a reference, a given name and a family initial.
create sequence if not exists pipeline.portal_student_ref_seq;
comment on sequence pipeline.portal_student_ref_seq is 'CF-247 s1182: numbers the portal student reference (SS-000001).';

create table pipeline.portal_proposals (
  id              uuid        primary key default gen_random_uuid(),
  student_ref     text        not null,
  given_name      text        not null check (length(btrim(given_name)) between 1 and 40),  -- fixed: a given name, not a free text field
  family_initial  text        not null check (family_initial ~ '^[A-Z]$'),
  title           text        not null default '' check (length(title) <= 200),  -- fixed: a short heading
  status          text        not null default 'draft' check (status in ('draft', 'sent', 'accepted', 'archived')),
  owner_id        uuid        not null references auth.users (id),
  last_editor_id  uuid        not null references auth.users (id),
  current_version integer     not null default 1 check (current_version >= 1),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  archived_at     timestamptz,
  archived_by     uuid        references auth.users (id),
  archived_reason text        check (archived_reason is null or length(btrim(archived_reason)) between 1 and 500),  -- fixed: a short reason
  check ((status = 'archived') = (archived_at is not null and archived_by is not null and archived_reason is not null))
);
comment on table pipeline.portal_proposals is 'StudySearch Portal (CF-247 s1182): one row per student proposal. The student is held as a reference, a given name and a family initial only. Any Counsellor or above finds, opens and saves any proposal; Viewers cannot. Archived with who, when and why; never deleted. Reached only through the public.portal_proposal_* functions.';
create index portal_proposals_student_ref_idx on pipeline.portal_proposals (student_ref);
create index portal_proposals_updated_idx on pipeline.portal_proposals (updated_at desc);
create index portal_proposals_owner_idx on pipeline.portal_proposals (owner_id, updated_at desc);

-- 3. Versions: every save is a new row naming its editor; append only.
create table pipeline.portal_proposal_versions (
  proposal_id            uuid        not null references pipeline.portal_proposals (id),
  version                integer     not null check (version >= 1),
  edited_by              uuid        not null references auth.users (id),
  edited_at              timestamptz not null default now(),
  status                 text        not null check (status in ('draft', 'sent', 'accepted')),
  courses                jsonb       not null default '[]'::jsonb check (jsonb_typeof(courses) = 'array'),
  next_steps             jsonb       not null default '[]'::jsonb check (jsonb_typeof(next_steps) = 'array'),
  notes                  text        not null default '' check (length(notes) <= 8000),      -- fixed: shown to the student in the PDF
  team_note              text        not null default '' check (length(team_note) <= 8000),  -- fixed: internal only, never in the PDF
  refreshed_from         integer,
  saved_after_other_edit boolean     not null default false,
  primary key (proposal_id, version)
);
comment on table pipeline.portal_proposal_versions is 'StudySearch Portal (CF-247 s1182): every saved version of a proposal, append only (update and delete are refused). Holds the course snapshot built from live rows at save time, next steps, student-facing notes, an internal team note, the editor, and whether the save came after someone else''s edit.';

create or replace function pipeline.portal_proposal_versions_append_only_v1()
returns trigger language plpgsql set search_path = '' as $function$
begin
  raise exception 'proposal versions are append only: a saved version is never changed or removed' using errcode = '42501';
end $function$;
create trigger portal_proposal_versions_append_only
  before update or delete on pipeline.portal_proposal_versions
  for each row execute function pipeline.portal_proposal_versions_append_only_v1();

-- 4. What each person did last (Dashboard resume cards); own rows only.
create table pipeline.portal_activity (
  user_id uuid        not null references auth.users (id),
  kind    text        not null check (kind in ('courses_search', 'proposal', 'provider', 'scholarship')),
  ref     text        not null check (length(ref) between 1 and 200),    -- fixed: an id or a short search key
  label   text        not null check (length(label) between 1 and 200),  -- fixed: a short label
  state   jsonb       not null default '{}'::jsonb check (jsonb_typeof(state) = 'object' and pg_column_size(state) <= 8192),  -- fixed: filters of a search, not a document
  seen_at timestamptz not null default now(),
  primary key (user_id, kind, ref)
);
comment on table pipeline.portal_activity is 'StudySearch Portal (CF-247 s1182): each person''s own recent searches and opened items, for the Dashboard resume cards, and who has a proposal open (the soft note). Own rows only; written by public.portal_activity_touch_v1 and public.portal_proposal_open_v1.';
create index portal_activity_user_seen_idx on pipeline.portal_activity (user_id, seen_at desc);
create index portal_activity_proposal_idx on pipeline.portal_activity (ref, seen_at desc) where kind = 'proposal';

-- 5. Each person's own portal preferences.
create table pipeline.portal_user_prefs (
  user_id    uuid        primary key references auth.users (id),
  theme      text        not null check (theme ~ '^[a-z]{2,20}$'),
  updated_at timestamptz not null default now()
);
comment on table pipeline.portal_user_prefs is 'StudySearch Portal (CF-247 s1182): each person''s own colour theme (the allowed list is the portal setting "themes"). Own row only; written by public.portal_prefs_save_v1.';

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

-- 7. Internal helpers (not granted to anyone): a person's display label, and the course snapshot built from live rows.
create or replace function pipeline.portal_user_label_v1(p_user uuid)
returns text language sql stable security definer set search_path = '' as $function$
  select coalesce(nullif(btrim(u.raw_user_meta_data->>'full_name'), ''), nullif(btrim(u.raw_user_meta_data->>'name'), ''), split_part(u.email, '@', 1), 'a colleague')
    from auth.users u where u.id = p_user
$function$;
comment on function pipeline.portal_user_label_v1(uuid) is 'CF-247 s1182: the name the portal shows for a colleague (full name, name, or the part of the email before @).';

create or replace function pipeline.portal_course_snapshot_v1(p_ids uuid[])
returns jsonb language sql stable security definer set search_path = '' as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'course_id', c.id,
      'title', coalesce(nullif(c.display_title, ''), c.canonical_title),
      'provider_id', p.id,
      'provider_name', coalesce(nullif(p.display_name, ''), p.canonical_name),
      'level', sl.name,
      'country_code', d.country_code,
      'city', coalesce((select ca.city from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id
                         where cc.course_id = c.id order by cc.is_primary desc nulls last, ca.city limit 1), p.primary_city),
      'duration_value', c.duration_value, 'duration_unit', c.duration_unit,
      'fee', case when d.provider_annual_tuition_amount is not null then jsonb_build_object('per_year', d.provider_annual_tuition_amount, 'currency', d.provider_annual_tuition_currency) end,
      'next_intake', (select jsonb_build_object('label', i.intake_label, 'start_date', i.start_date) from catalogue.course_intakes i
                       where i.course_id = c.id and i.status = 'active' and (i.start_date is null or i.start_date >= (now() at time zone 'Australia/Melbourne')::date)  -- fixed: Melbourne day
                       order by i.start_date nulls last, i.id limit 1),
      'available', c.lifecycle_status = 'active' and p.lifecycle_status = 'active',
      'course_url', coalesce(d.official_course_url, c.course_url),
      'snapshot_at', now())
    order by x.ord), '[]'::jsonb)
  from unnest(p_ids) with ordinality x(id, ord)
  join catalogue.courses c on c.id = x.id
  join catalogue.providers p on p.id = c.provider_id
  left join search.course_documents d on d.course_id = c.id
  left join ref.study_levels sl on sl.id = c.study_level_id
$function$;
comment on function pipeline.portal_course_snapshot_v1(uuid[]) is 'CF-247 s1182: the course snapshot a proposal keeps (title, provider, level, place, duration, fee, next intake, availability, link), built from live rows in the given order. Used by save and refresh.';
revoke all on function pipeline.portal_user_label_v1(uuid), pipeline.portal_course_snapshot_v1(uuid[]) from public, anon, authenticated;

-- 8. Save: create a proposal or save a new version. Counsellor and above; any Counsellor may save any proposal; every save is a new version.
--    p_courses: course ids, or objects with "course_id" (and an optional "note" kept with that course). Unknown or repeated ids are skipped and listed.
--    p_base_version: the version the editor opened. saved_after_other_edit is true when someone saved after that, or, when no base is given,
--    when someone else saved within edit_lock_minutes. It never blocks the save.
create or replace function public.portal_proposal_save_v1(
  p_proposal_id uuid, p_student jsonb, p_courses jsonb, p_next_steps jsonb, p_notes text, p_team_note text,
  p_base_version integer default null, p_status text default null, p_title text default null, p_refreshed_from integer default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid();
  v_max integer := greatest(coalesce(security.portal_setting_v1('proposal_max_courses'), 12), 1);  -- fixed: the setting's own default
  v_lock integer := greatest(coalesce(security.portal_setting_v1('edit_lock_minutes'), 15), 1);    -- fixed: the setting's own default
  v_p pipeline.portal_proposals%rowtype;
  v_in jsonb := case when jsonb_typeof(p_courses) = 'array' then p_courses else '[]'::jsonb end;
  v_ids uuid[]; v_notes jsonb; v_skipped jsonb; v_snap jsonb; v_ver integer; v_conflict boolean := false;
  v_status text := nullif(lower(btrim(coalesce(p_status, ''))), '');
  v_given text; v_initial text; v_ref text;
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above; Viewers cannot save or see proposals
  if v_status is not null and v_status not in ('draft', 'sent', 'accepted') then
    raise exception 'a proposal status is draft, sent or accepted (archive it with portal_proposal_archive_v1)' using errcode = '22023';
  end if;

  -- the courses: ids in the order given, each once; anything that is not a live course id is skipped and reported
  with raw as (
    select ord, case when jsonb_typeof(e) = 'string' then e #>> '{}' when jsonb_typeof(e) = 'object' then e->>'course_id' end as id_text,
           case when jsonb_typeof(e) = 'object' and jsonb_typeof(e->'note') = 'string' then left(e->>'note', 1000) end as note  -- fixed: a short per-course note
      from jsonb_array_elements(v_in) with ordinality a(e, ord)),
  typed as (select ord, id_text, note, case when id_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then id_text::uuid end as id from raw),
  firsts as (select distinct on (id) ord, id, note from typed where id is not null order by id, ord),
  live as (select f.* from firsts f join catalogue.courses c on c.id = f.id)
  select array(select id from live order by ord),
         coalesce((select jsonb_object_agg(id::text, note) from live where note is not null), '{}'::jsonb),
         coalesce((select jsonb_agg(coalesce(t.id_text, '(not a course id)') order by t.ord) from typed t where t.id is null or not exists (select 1 from live l where l.id = t.id and l.ord = t.ord)), '[]'::jsonb)
    into v_ids, v_notes, v_skipped;
  if cardinality(v_ids) > v_max then
    raise exception 'a proposal holds at most % courses (% chosen)', v_max, cardinality(v_ids) using errcode = '22023';
  end if;
  v_snap := (select coalesce(jsonb_agg(case when v_notes ? (s->>'course_id') then s || jsonb_build_object('note', v_notes->>(s->>'course_id')) else s end order by o), '[]'::jsonb)
               from jsonb_array_elements(pipeline.portal_course_snapshot_v1(v_ids)) with ordinality z(s, o));

  if p_proposal_id is null then
    -- a new proposal: the student by reference (an existing reference is reused) and given name with family initial only
    v_given := left(btrim(regexp_replace(coalesce(p_student->>'given_name', ''), '\s+', ' ', 'g')), 40);  -- fixed: the column's own limit
    v_initial := upper(left(regexp_replace(coalesce(p_student->>'family_initial', ''), '[^A-Za-z]', '', 'g'), 1));
    if v_given = '' or v_initial = '' then
      raise exception 'a new proposal needs the student''s given name and family initial' using errcode = '22023';
    end if;
    v_ref := upper(btrim(coalesce(p_student->>'student_ref', '')));
    if v_ref = '' or not exists (select 1 from pipeline.portal_proposals where student_ref = v_ref) then
      v_ref := 'SS-' || lpad(nextval('pipeline.portal_student_ref_seq')::text, 6, '0');  -- fixed: the reference format
    end if;
    insert into pipeline.portal_proposals (student_ref, given_name, family_initial, title, status, owner_id, last_editor_id, current_version)
    values (v_ref, v_given, v_initial, left(btrim(coalesce(p_title, '')), 200), coalesce(v_status, 'draft'), v_uid, v_uid, 1)
    returning * into v_p;
    v_ver := 1;
  else
    select * into v_p from pipeline.portal_proposals where id = p_proposal_id for update;
    if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
    if v_p.status = 'archived' then raise exception 'this proposal is archived and is kept as it was' using errcode = '22023'; end if;
    v_conflict := (p_base_version is not null and p_base_version <> v_p.current_version)
               or (p_base_version is null and v_p.last_editor_id <> v_uid and v_p.updated_at > now() - make_interval(mins => v_lock));
    v_ver := v_p.current_version + 1;
    update pipeline.portal_proposals
       set current_version = v_ver, last_editor_id = v_uid, updated_at = now(),
           status = coalesce(v_status, status), title = case when p_title is null then title else left(btrim(p_title), 200) end
     where id = v_p.id
     returning * into v_p;
  end if;

  insert into pipeline.portal_proposal_versions (proposal_id, version, edited_by, status, courses, next_steps, notes, team_note, refreshed_from, saved_after_other_edit)
  values (v_p.id, v_ver, v_uid, v_p.status, v_snap,
          case when jsonb_typeof(p_next_steps) = 'array' then p_next_steps else '[]'::jsonb end,
          left(coalesce(p_notes, ''), 8000), left(coalesce(p_team_note, ''), 8000),  -- fixed: the columns' own limits
          case when p_refreshed_from between 1 and v_ver - 1 then p_refreshed_from end, v_conflict);

  insert into pipeline.portal_activity (user_id, kind, ref, label, state, seen_at)
  values (v_uid, 'proposal', v_p.id::text, left(v_p.student_ref || ' ' || v_p.given_name || ' ' || v_p.family_initial || '.', 200), '{}'::jsonb, now())
  on conflict (user_id, kind, ref) do update set label = excluded.label, seen_at = excluded.seen_at;

  return jsonb_build_object('proposal_id', v_p.id, 'student_ref', v_p.student_ref, 'version', v_ver, 'status', v_p.status,
                            'courses', jsonb_array_length(v_snap), 'skipped', v_skipped,
                            'saved_after_other_edit', v_conflict, 'last_editor_id', v_uid);
end $function$;
comment on function public.portal_proposal_save_v1(uuid, jsonb, jsonb, jsonb, text, text, integer, text, text, integer) is 'CF-247 s1182: creates a proposal or saves a new version. Counsellor and above. Courses are snapshotted from live rows; saved_after_other_edit warns, never blocks.';

-- 9. Find: the whole team's proposals (or only the person's own), newest first, by student reference, given name or title.
create or replace function public.portal_proposal_find_v1(p_query text default null, p_scope text default 'team', p_limit integer default 50, p_status text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_cap integer := greatest(coalesce(security.portal_setting_v1('proposals_page_size'), 50), 1);  -- fixed: the setting's own default
  v_q text := nullif(btrim(regexp_replace(coalesce(p_query, ''), '\s+', ' ', 'g')), '');
  v_status text := nullif(lower(btrim(coalesce(p_status, ''))), '');
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above
  return coalesce((select jsonb_agg(r order by r.updated_at desc, r.id) from (
    select p.id, p.student_ref, p.given_name || ' ' || p.family_initial || '.' as student, p.title, p.status, p.current_version,
           p.owner_id, pipeline.portal_user_label_v1(p.owner_id) as owner_name,
           p.last_editor_id, pipeline.portal_user_label_v1(p.last_editor_id) as last_editor_name, p.updated_at, p.archived_at,
           (select jsonb_array_length(v.courses) from pipeline.portal_proposal_versions v where v.proposal_id = p.id and v.version = p.current_version) as courses
      from pipeline.portal_proposals p
     where (coalesce(p_scope, 'team') <> 'mine' or p.owner_id = auth.uid())
       and (case when v_status is null then p.status <> 'archived' when v_status = 'all' then true else p.status = v_status end)
       and (v_q is null or p.student_ref ilike security.portal_like_v1(v_q) or p.given_name ilike security.portal_like_v1(v_q)
            or p.title ilike security.portal_like_v1(v_q))
     order by p.updated_at desc, p.id
     limit least(greatest(coalesce(p_limit, v_cap), 1), v_cap)) r), '[]'::jsonb);
end $function$;
comment on function public.portal_proposal_find_v1(text, text, integer, text) is 'CF-247 s1182: finds proposals by student reference, given name or title; whole team or own; archived only when asked. Counsellor and above.';

-- 10. Open: one proposal, its current version, the list of versions, and the soft note (who else has it open or saved it recently).
create or replace function public.portal_proposal_open_v1(p_proposal_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid();
  v_lock integer := greatest(coalesce(security.portal_setting_v1('edit_lock_minutes'), 15), 1);  -- fixed: the setting's own default
  v_p pipeline.portal_proposals%rowtype; v_cur pipeline.portal_proposal_versions%rowtype; v_others jsonb;
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above
  select * into v_p from pipeline.portal_proposals where id = p_proposal_id;
  if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
  select * into v_cur from pipeline.portal_proposal_versions where proposal_id = v_p.id and version = v_p.current_version;

  -- who else opened it, or saved it, within edit_lock_minutes (read before this open is recorded)
  v_others := coalesce((select jsonb_agg(jsonb_build_object('user_id', o.user_id, 'name', pipeline.portal_user_label_v1(o.user_id), 'action', o.action, 'at', o.at) order by o.at desc)
    from (select distinct on (x.user_id) x.user_id, x.action, x.at from (
            select a.user_id, 'opened' as action, a.seen_at as at from pipeline.portal_activity a
             where a.kind = 'proposal' and a.ref = v_p.id::text and a.user_id <> v_uid and a.seen_at > now() - make_interval(mins => v_lock)
            union all
            select v.edited_by, 'saved', v.edited_at from pipeline.portal_proposal_versions v
             where v.proposal_id = v_p.id and v.edited_by <> v_uid and v.edited_at > now() - make_interval(mins => v_lock)) x
          order by x.user_id, x.at desc) o), '[]'::jsonb);

  insert into pipeline.portal_activity (user_id, kind, ref, label, state, seen_at)
  values (v_uid, 'proposal', v_p.id::text, left(v_p.student_ref || ' ' || v_p.given_name || ' ' || v_p.family_initial || '.', 200), '{}'::jsonb, now())
  on conflict (user_id, kind, ref) do update set label = excluded.label, seen_at = excluded.seen_at;

  return jsonb_build_object(
    'proposal', jsonb_build_object('id', v_p.id, 'student_ref', v_p.student_ref, 'given_name', v_p.given_name, 'family_initial', v_p.family_initial,
                                   'title', v_p.title, 'status', v_p.status, 'owner_id', v_p.owner_id, 'owner_name', pipeline.portal_user_label_v1(v_p.owner_id),
                                   'last_editor_id', v_p.last_editor_id, 'last_editor_name', pipeline.portal_user_label_v1(v_p.last_editor_id),
                                   'current_version', v_p.current_version, 'created_at', v_p.created_at, 'updated_at', v_p.updated_at,
                                   'archived_at', v_p.archived_at, 'archived_by', v_p.archived_by,
                                   'archived_by_name', case when v_p.archived_by is not null then pipeline.portal_user_label_v1(v_p.archived_by) end,
                                   'archived_reason', v_p.archived_reason),
    'base_version', v_p.current_version,
    'current', jsonb_build_object('version', v_cur.version, 'edited_by', v_cur.edited_by, 'edited_by_name', pipeline.portal_user_label_v1(v_cur.edited_by),
                                  'edited_at', v_cur.edited_at, 'status', v_cur.status, 'courses', v_cur.courses, 'next_steps', v_cur.next_steps,
                                  'notes', v_cur.notes, 'team_note', v_cur.team_note, 'refreshed_from', v_cur.refreshed_from,
                                  'saved_after_other_edit', v_cur.saved_after_other_edit),
    'versions', coalesce((select jsonb_agg(jsonb_build_object('version', v.version, 'edited_by', v.edited_by, 'edited_by_name', pipeline.portal_user_label_v1(v.edited_by),
                                                              'edited_at', v.edited_at, 'status', v.status, 'courses', jsonb_array_length(v.courses),
                                                              'refreshed_from', v.refreshed_from, 'saved_after_other_edit', v.saved_after_other_edit) order by v.version desc)
                            from pipeline.portal_proposal_versions v where v.proposal_id = v_p.id), '[]'::jsonb),
    'soft_lock', jsonb_build_object('minutes', v_lock, 'others', v_others, 'note',
                 case when jsonb_array_length(v_others) > 0 then
                   (select string_agg(e->>'name', ', ') from jsonb_array_elements(v_others) e) || ' had this proposal open or saved it in the last ' || v_lock || ' minutes. Saving still works; the save is marked.' end));
end $function$;
comment on function public.portal_proposal_open_v1(uuid) is 'CF-247 s1182: one proposal with its current version, versions list and the soft note (others who opened or saved it within edit_lock_minutes). Records the open. Counsellor and above.';

-- 11. Refresh: compare each saved course with the live catalogue. It never changes the proposal; "Accept all" saves courses_live as a new version.
create or replace function public.portal_proposal_refresh_v1(p_proposal_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_p pipeline.portal_proposals%rowtype; v_saved jsonb; v_live jsonb; v_ids uuid[];
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above
  select * into v_p from pipeline.portal_proposals where id = p_proposal_id;
  if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
  select v.courses into v_saved from pipeline.portal_proposal_versions v where v.proposal_id = v_p.id and v.version = v_p.current_version;
  v_saved := coalesce(v_saved, '[]'::jsonb);
  v_ids := array(select (s->>'course_id')::uuid from jsonb_array_elements(v_saved) with ordinality z(s, o) where s->>'course_id' is not null order by o);
  v_live := (select coalesce(jsonb_agg(case when s ? 'note' then l || jsonb_build_object('note', s->'note') else l end order by o), '[]'::jsonb)
               from jsonb_array_elements(v_saved) with ordinality z(s, o)
               join lateral (select x from jsonb_array_elements(pipeline.portal_course_snapshot_v1(v_ids)) x where x->>'course_id' = s->>'course_id') q(l) on true);
  return jsonb_build_object(
    'proposal_id', v_p.id, 'version', v_p.current_version, 'checked_at', now(),
    'changes', coalesce((select jsonb_agg(jsonb_build_object('course_id', s->>'course_id', 'title', s->>'title', 'field', f.field, 'saved', f.saved, 'live', f.live) order by o, f.n)
        from jsonb_array_elements(v_saved) with ordinality z(s, o)
        left join lateral (select x from jsonb_array_elements(v_live) x where x->>'course_id' = s->>'course_id') q(l) on true
        cross join lateral (values
          (1, 'availability', to_jsonb(coalesce((s->>'available')::boolean, true)), coalesce(l->'available', 'false'::jsonb)),
          (2, 'title', s->'title', l->'title'),
          (3, 'provider', s->'provider_name', l->'provider_name'),
          (4, 'fee', s->'fee', l->'fee'),
          (5, 'next_intake', s->'next_intake', l->'next_intake'),
          (6, 'level', s->'level', l->'level'),
          (7, 'city', s->'city', l->'city')) f(n, field, saved, live)
       where (l is null and f.n = 1) or (l is not null and coalesce(f.saved, 'null'::jsonb) is distinct from coalesce(f.live, 'null'::jsonb))), '[]'::jsonb),
    'unavailable', coalesce((select jsonb_agg(s->>'course_id' order by o) from jsonb_array_elements(v_saved) with ordinality z(s, o)
                              where not exists (select 1 from jsonb_array_elements(v_live) x where x->>'course_id' = s->>'course_id' and (x->>'available')::boolean)), '[]'::jsonb),
    'courses_live', v_live);
end $function$;
comment on function public.portal_proposal_refresh_v1(uuid) is 'CF-247 s1182: compares the current version''s course snapshot with live rows (availability, title, provider, fee, next intake, level, city) and returns the differences and the refreshed snapshot. Never changes the proposal. Counsellor and above.';

-- 12. Archive: never a delete; who, when and why are kept. Archiving an archived proposal returns it unchanged.
create or replace function public.portal_proposal_archive_v1(p_proposal_id uuid, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid(); v_reason text := left(btrim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g')), 500);  -- fixed: the column's own limit
  v_p pipeline.portal_proposals%rowtype;
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above
  if v_reason = '' then raise exception 'archiving needs a reason' using errcode = '22023'; end if;
  select * into v_p from pipeline.portal_proposals where id = p_proposal_id for update;
  if not found then raise exception 'proposal not found' using errcode = 'P0002'; end if;
  if v_p.status <> 'archived' then
    update pipeline.portal_proposals set status = 'archived', archived_at = now(), archived_by = v_uid, archived_reason = v_reason, updated_at = now()
     where id = v_p.id returning * into v_p;
  end if;
  return jsonb_build_object('proposal_id', v_p.id, 'status', v_p.status, 'archived_at', v_p.archived_at, 'archived_by', v_p.archived_by,
                            'archived_by_name', pipeline.portal_user_label_v1(v_p.archived_by), 'archived_reason', v_p.archived_reason);
end $function$;
comment on function public.portal_proposal_archive_v1(uuid, text) is 'CF-247 s1182: archives a proposal with a reason, keeping who and when. Never deletes; versions stay. Counsellor and above.';

-- 13. Activity: the person's own recent searches and opened items. Viewer and above; proposal items need Counsellor and above.
create or replace function public.portal_activity_touch_v1(p_kind text, p_ref text, p_label text, p_state jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid(); v_rank smallint; v_kind text := lower(btrim(coalesce(p_kind, '')));
  v_ref text := left(btrim(coalesce(p_ref, '')), 200); v_label text := left(btrim(regexp_replace(coalesce(p_label, ''), '\s+', ' ', 'g')), 200);  -- fixed: the columns' own limits
  v_state jsonb := case when jsonb_typeof(p_state) = 'object' and pg_column_size(p_state) <= 8192 then p_state else '{}'::jsonb end;  -- fixed: the column's own limit
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
  return jsonb_build_object('kind', v_kind, 'ref', v_ref, 'label', v_label, 'seen_at', now());
end $function$;
comment on function public.portal_activity_touch_v1(text, text, text, jsonb) is 'CF-247 s1182: records the person''s own recent search or opened item (Dashboard resume cards). Viewer and above; proposal items Counsellor and above.';

create or replace function public.portal_activity_list_v1(p_limit integer default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_rank smallint; v_cap integer := greatest(coalesce(security.portal_setting_v1('resume_items_shown'), 6), 1);  -- fixed: the setting's own default
begin
  v_rank := security.portal_rank_v1(1);  -- fixed: Viewer and above
  return coalesce((select jsonb_agg(jsonb_build_object('kind', a.kind, 'ref', a.ref, 'label', a.label, 'state', a.state, 'seen_at', a.seen_at) order by a.seen_at desc)
    from (select * from pipeline.portal_activity a where a.user_id = auth.uid() and (a.kind <> 'proposal' or v_rank >= 2)  -- fixed: proposals are Counsellor and above
           order by a.seen_at desc limit least(greatest(coalesce(p_limit, v_cap), 1), v_cap)) a), '[]'::jsonb);
end $function$;
comment on function public.portal_activity_list_v1(integer) is 'CF-247 s1182: the person''s own recent searches and opened items, newest first, at most resume_items_shown. Viewer and above.';

-- 14. Preferences: the person's own colour theme. Called with no theme it returns the current one (the first listed theme when none is saved).
create or replace function public.portal_prefs_save_v1(p_theme text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid(); v_theme text := nullif(lower(btrim(coalesce(p_theme, ''))), '');
  v_themes jsonb := coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'portal' and s.key = 'themes'), '[]'::jsonb);
  v_row pipeline.portal_user_prefs%rowtype;
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  if v_theme is not null then
    if not (v_themes ? v_theme) then raise exception 'that theme is not offered (see the portal setting "themes")' using errcode = '22023'; end if;
    insert into pipeline.portal_user_prefs (user_id, theme, updated_at) values (v_uid, v_theme, now())
    on conflict (user_id) do update set theme = excluded.theme, updated_at = excluded.updated_at;
  end if;
  select * into v_row from pipeline.portal_user_prefs where user_id = v_uid;
  return jsonb_build_object('theme', coalesce(v_row.theme, v_themes->>0), 'saved', v_row.user_id is not null, 'updated_at', v_row.updated_at, 'themes', v_themes);
end $function$;
comment on function public.portal_prefs_save_v1(text) is 'CF-247 s1182: saves the person''s own colour theme (one of the portal setting "themes"); with no theme, returns the current one. Viewer and above.';

-- 15. Who may call them: signed-in people only; each function checks the role itself.
revoke all on function public.portal_proposal_save_v1(uuid, jsonb, jsonb, jsonb, text, text, integer, text, text, integer),
                       public.portal_proposal_find_v1(text, text, integer, text),
                       public.portal_proposal_open_v1(uuid),
                       public.portal_proposal_refresh_v1(uuid),
                       public.portal_proposal_archive_v1(uuid, text),
                       public.portal_activity_touch_v1(text, text, text, jsonb),
                       public.portal_activity_list_v1(integer),
                       public.portal_prefs_save_v1(text) from public, anon;
grant execute on function public.portal_proposal_save_v1(uuid, jsonb, jsonb, jsonb, text, text, integer, text, text, integer),
                          public.portal_proposal_find_v1(text, text, integer, text),
                          public.portal_proposal_open_v1(uuid),
                          public.portal_proposal_refresh_v1(uuid),
                          public.portal_proposal_archive_v1(uuid, text),
                          public.portal_activity_touch_v1(text, text, text, jsonb),
                          public.portal_activity_list_v1(integer),
                          public.portal_prefs_save_v1(text) to authenticated;

do $post$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1182_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1182_guard) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'portal' and key in ('proposal_max_courses', 'edit_lock_minutes', 'proposals_page_size', 'resume_items_shown', 'themes')) <> 5 then
    raise exception 'post-check: the five s1182 settings are not all present';
  end if;
  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'pipeline' and c.relname in ('portal_proposals', 'portal_proposal_versions', 'portal_activity', 'portal_user_prefs') and c.relrowsecurity) <> 4 then
    raise exception 'post-check: row level security is not on for all four tables';
  end if;
  if has_table_privilege('authenticated', 'pipeline.portal_proposals', 'SELECT') or has_table_privilege('anon', 'pipeline.portal_proposal_versions', 'SELECT')
     or has_function_privilege('anon', 'public.portal_proposal_open_v1(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'pipeline.portal_course_snapshot_v1(uuid[])', 'EXECUTE') then
    raise exception 'post-check: a table or helper is reachable outside the portal functions';
  end if;
end $post$;
