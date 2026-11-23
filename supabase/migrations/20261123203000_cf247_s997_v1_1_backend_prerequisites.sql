-- CF-247 s997 (S1-Build; Platform Admin 23 Nov 2026 18:55 AEDT): shared backend prerequisites for the v1.1 Counsellor and Admin UI
-- (MOCKUP-SPEC-AND-RETIREMENT-MAP v1.1 section 2 rows 1, 1b, 3b and 5, and section 5 dependencies 2, 4 and 5). Three additive parts:
-- 1. Budget cap on the Boost queue read (Dry-Lane banner). The G2 setting budgets.paid_daily_cap_usd (US$5.00 a day, the Standing Authority
--    Charter of 23 Nov 2026 18:52) is seeded if missing, and public.admin_boost_queue_read returns a budget_cap object: the live Firecrawl
--    daily budget (firecrawl.daily_budget_total, the cap the platform enforces today), whether that budget is on, the platform paid cap, the
--    AI daily ceiling, the waiting queue and dry_lane = (Firecrawl cap is 0 and the queue is not empty). The read is changed only from the
--    definition it was written against (md5 checked before and after); its other keys are unchanged.
-- 2. Saved courses (REQ-115): pipeline.saved_courses (user_id, course_id, saved_at) with row-level security to each user's own rows, the
--    toggle RPC public.saved_course_toggle_v1, the read public.saved_courses_read_v1, and is_saved on every course-list row through
--    security.course_list_extras_v1 (all list paths use it). The cap per user is a setting (saved_courses.max_per_user).
-- 3. Study Square partner contacts (REQ-116 / REQ-22, Platform Admin decision 23 Nov 2026 16:22): pipeline.partner_contacts and its event
--    log, kept beside pipeline.provider_contacts (which the frozen Zoho v2 contact feed reads), so partner records never reach a consumer
--    feed. Admin entry (public.admin_partner_contact_save_v1) and the Zoho CRM partner import (public.admin_partner_contacts_import_v1,
--    rows handed over by a person; no scraping, no web read) write it; public.provider_partner_contacts_v1 returns the rows with
--    active_count and inactive_count so the screen can say "none held" rather than "none match". Contacts are deactivated, never deleted.
-- G1: no job. G2: every limit is a setting. G3: no consumer object is touched (75/48 before and after). Manual locks and active cron jobs
-- are checked unchanged. Nothing dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the new objects and the two function replacements

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.course_list_extras_v1(uuid[])'::regprocedure)) <> 'e24c809a98956d9ad0f5c0484a22c4be' then
    raise exception 'guard: security.course_list_extras_v1 is not the definition this change was written against';
  end if;
  if md5(pg_get_functiondef('public.admin_boost_queue_read(jsonb)'::regprocedure)) <> 'e042641accd8b0e1c18abd17d5c9b429' then
    raise exception 'guard: public.admin_boost_queue_read is not the definition this change was written against';
  end if;
  if to_regclass('pipeline.saved_courses') is not null or to_regclass('pipeline.partner_contacts') is not null then
    raise exception 'guard: a table this change creates already exists';
  end if;
end $g$;
create temp table s997_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s997_cron on commit drop as select count(*) n from cron.job where active;

-- settings (G2)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'budgets.paid_daily_cap_usd', 'Paid spend: platform cap a day (Firecrawl and AI together)',
        'The most the whole platform may spend on paid services (Firecrawl fetches and pinned AI cascades) in one Melbourne day under the Standing Authority Charter. A lane that would go above it holds the batch as HELD:BUDGET_GATE. Every paid call is logged in the daily digest. The Firecrawl daily budget (credits) and the AI daily ceiling still apply on their own.',
        'number', to_jsonb(5), 0, 5, 'US$ a day', 3330, 'Budgets',
        'public.admin_boost_queue_read (budget_cap); docs/monitoring/DAILY-EXECUTIVE-STATUS.md spend log',
        'CF-247 s997: Standing Authority Charter (Platform Admin 23 Nov 2026 18:52), US$5.00 a day micro-budget')
on conflict do nothing;
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'saved_courses.max_per_user', 'Saved courses: most one user can keep',
        'How many courses one signed-in user can keep in their Saved courses list. Saving one more is refused with a plain message until one is removed.',
        'number', to_jsonb(500), 10, 5000, 'courses', 3331, 'Counsellor',
        'public.saved_course_toggle_v1, public.saved_courses_read_v1', 'CF-247 s997: REQ-115 saved courses (Platform Admin 23 Nov 2026)')
on conflict do nothing;
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'partner_contacts.import_max_rows', 'Partner contacts: rows in one import',
        'The most rows one Study Square partner contact import (Zoho CRM partner export, handed over by a person) may carry. A larger file is split.',
        'number', to_jsonb(1000), 1, 10000, 'rows', 3332, 'Providers',
        'public.admin_partner_contacts_import_v1', 'CF-247 s997: REQ-116 / REQ-22 partner contacts (Platform Admin decision 23 Nov 2026 16:22)')
on conflict do nothing;

-- 1. budget cap on the Boost queue read
create or replace function security.boost_budget_cap_v1(p_queued bigint)
returns jsonb language sql stable security definer set search_path = '' as $function$
  with fc as (
    select (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_total') cap,
           (select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on') cap_on,
           (select s.unit from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_total') unit)
  select jsonb_build_object(
    'firecrawl_budget_cap', fc.cap, 'firecrawl_budget_unit', fc.unit, 'firecrawl_budget_on', fc.cap_on, 'source_key', 'firecrawl.daily_budget_total',
    'paid_daily_cap_usd', security.pipeline_num_v1('budgets.paid_daily_cap_usd', 5),
    'ai_daily_ceiling_usd', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14),
    'queued', coalesce(p_queued, 0),
    'dry_lane', coalesce(fc.cap = 0, false) and coalesce(p_queued, 0) > 0)
  from fc
$function$;
comment on function security.boost_budget_cap_v1(bigint) is 'CF-247 s997: the budget cap block of the Boost queue read (Dry-Lane banner): live Firecrawl daily budget, platform paid cap, AI ceiling, waiting queue and dry_lane. Reads settings only.';
revoke all on function security.boost_budget_cap_v1(bigint) from public, anon, authenticated;

do $b$
declare v_def text := pg_get_functiondef('public.admin_boost_queue_read(jsonb)'::regprocedure);
        v_tok text := $t$'tiers', jsonb_build_object($t$;
        v_n int;
begin
  v_n := (length(v_def) - length(replace(v_def, v_tok, ''))) / length(v_tok);
  if v_n <> 1 then raise exception 'guard: the Boost queue read has % tiers keys, expected 1', v_n; end if;
  execute replace(v_def, v_tok, $t$'budget_cap', security.boost_budget_cap_v1((select count(*) from q where q.done_at is null)), 'tiers', jsonb_build_object($t$);
end $b$;

-- 2. saved courses (REQ-115)
create table pipeline.saved_courses (
  user_id uuid not null references auth.users (id) on delete cascade,
  course_id uuid not null references catalogue.courses (id) on delete cascade,
  saved_at timestamptz not null default now(),
  primary key (user_id, course_id)
);
comment on table pipeline.saved_courses is 'CF-247 s997 (REQ-115): each signed-in user''s own saved courses for the Counsellor Saved view and Compare. Row-level security limits every user to their own rows; written through public.saved_course_toggle_v1.';
create index saved_courses_user_saved_idx on pipeline.saved_courses (user_id, saved_at desc);
alter table pipeline.saved_courses enable row level security;
create policy saved_courses_own_select on pipeline.saved_courses for select to authenticated using (user_id = auth.uid());
create policy saved_courses_own_insert on pipeline.saved_courses for insert to authenticated with check (user_id = auth.uid());
create policy saved_courses_own_delete on pipeline.saved_courses for delete to authenticated using (user_id = auth.uid());
revoke all on pipeline.saved_courses from public, anon;
grant select, insert, delete on pipeline.saved_courses to authenticated;

create or replace function public.saved_course_toggle_v1(p_course_id uuid, p_saved boolean default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_uid uuid := auth.uid(); v_now boolean; v_want boolean; v_n int;
        v_max int := greatest(1, security.pipeline_num_v1('saved_courses.max_per_user', 500)::int);
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 1 then raise exception 'an assigned StudySearch role is needed to save courses' using errcode = '42501'; end if; -- fixed: any assigned role
  if p_course_id is null then raise exception 'INVALID_INPUT: course_id is required' using errcode = '22023'; end if;
  v_now := exists (select 1 from pipeline.saved_courses s where s.user_id = v_uid and s.course_id = p_course_id);
  v_want := coalesce(p_saved, not v_now);
  if v_want and not v_now then
    if not exists (select 1 from catalogue.courses c where c.id = p_course_id and c.lifecycle_status = 'active') then
      raise exception 'INVALID_INPUT: only an active course can be saved' using errcode = '22023';
    end if;
    select count(*) into v_n from pipeline.saved_courses s where s.user_id = v_uid;
    if v_n >= v_max then raise exception 'INVALID_INPUT: you can keep at most % saved courses; remove one first', v_max using errcode = '22023'; end if;
    insert into pipeline.saved_courses (user_id, course_id) values (v_uid, p_course_id) on conflict do nothing;
  elsif not v_want and v_now then
    delete from pipeline.saved_courses s where s.user_id = v_uid and s.course_id = p_course_id;
  end if;
  return jsonb_build_object('course_id', p_course_id, 'is_saved', v_want,
    'saved_at', (select s.saved_at from pipeline.saved_courses s where s.user_id = v_uid and s.course_id = p_course_id),
    'saved_count', (select count(*) from pipeline.saved_courses s where s.user_id = v_uid), 'max', v_max);
end $function$;
comment on function public.saved_course_toggle_v1(uuid, boolean) is 'CF-247 s997 (REQ-115): saves or unsaves one course for the signed-in user (toggle when p_saved is null). Own rows only; active courses only; cap is the setting saved_courses.max_per_user.';
revoke all on function public.saved_course_toggle_v1(uuid, boolean) from public, anon;
grant execute on function public.saved_course_toggle_v1(uuid, boolean) to authenticated;

create or replace function public.saved_courses_read_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 1 then raise exception 'an assigned StudySearch role is needed to read saved courses' using errcode = '42501'; end if; -- fixed: any assigned role
  return jsonb_build_object(
    'count', (select count(*) from pipeline.saved_courses s where s.user_id = v_uid),
    'max', greatest(1, security.pipeline_num_v1('saved_courses.max_per_user', 500)::int),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('course_id', s.course_id, 'saved_at', s.saved_at,
                'title', coalesce(c.display_title, c.canonical_title), 'lifecycle_status', c.lifecycle_status,
                'provider_id', c.provider_id, 'provider_name', coalesce(p.display_name, p.canonical_name)) order by s.saved_at desc, s.course_id), '[]'::jsonb)
                from pipeline.saved_courses s join catalogue.courses c on c.id = s.course_id left join catalogue.providers p on p.id = c.provider_id
               where s.user_id = v_uid));
end $function$;
comment on function public.saved_courses_read_v1() is 'CF-247 s997 (REQ-115): the signed-in user''s saved courses, newest first, with title and provider. Own rows only.';
revoke all on function public.saved_courses_read_v1() from public, anon;
grant execute on function public.saved_courses_read_v1() to authenticated;

-- is_saved on every course-list row (all list paths go through security.course_list_with_extras_v1 -> security.course_list_extras_v1)
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
    'published', pb.published,
    -- s997: the signed-in user's own saved flag (REQ-115; pipeline.saved_courses, own rows only)
    'is_saved', exists (select 1 from pipeline.saved_courses sc where sc.user_id = auth.uid() and sc.course_id = c.id))
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

-- 3. Study Square partner contacts (REQ-116 / REQ-22)
create table pipeline.partner_contacts (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers (id),
  record_type text not null default 'named_staff' check (record_type in ('named_staff', 'team_contact')),
  full_name text, team_name text, job_title text, functional_area text, region_scope text, countries_or_markets text,
  work_email text, work_phone text, staff_location text, verified_on date,
  lifecycle_status text not null default 'active' check (lifecycle_status in ('active', 'inactive')),
  source text not null check (source in ('study_square_admin', 'zoho_crm_partner')),
  external_id text,
  identity_key text not null,
  reason text,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  check (case when record_type = 'named_staff' then full_name is not null else coalesce(team_name, job_title, functional_area, work_email, work_phone) is not null end),
  check (work_email is null or work_email ~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$')
);
comment on table pipeline.partner_contacts is 'CF-247 s997 (REQ-116 / REQ-22; Platform Admin decision 23 Nov 2026 16:22): Study Square partner contacts for each provider, entered in Admin or imported from the Zoho CRM partner export. Never scraped. Kept apart from pipeline.provider_contacts so no consumer feed reads them. Deactivated, never deleted.';
create unique index partner_contacts_provider_identity_uidx on pipeline.partner_contacts (provider_id, identity_key);
create unique index partner_contacts_source_external_uidx on pipeline.partner_contacts (source, external_id) where external_id is not null;
create index partner_contacts_provider_status_idx on pipeline.partner_contacts (provider_id, lifecycle_status);
alter table pipeline.partner_contacts enable row level security;
revoke all on pipeline.partner_contacts from public, anon, authenticated;

create table pipeline.partner_contact_events (
  id bigint generated always as identity primary key,
  contact_id uuid not null references pipeline.partner_contacts (id),
  event text not null check (event in ('create', 'update', 'activate', 'deactivate', 'import_create', 'import_update')),
  actor_id uuid, reason text, before jsonb, after jsonb,
  at timestamptz not null default now()
);
comment on table pipeline.partner_contact_events is 'CF-247 s997: who changed each Study Square partner contact, when, why, and the row before and after.';
create index partner_contact_events_contact_idx on pipeline.partner_contact_events (contact_id, at desc);
alter table pipeline.partner_contact_events enable row level security;
revoke all on pipeline.partner_contact_events from public, anon, authenticated;

create or replace function security.partner_contact_upsert_v1(p_row jsonb, p_source text, p_actor uuid, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_provider uuid := nullif(p_row->>'provider_id', '')::uuid;
        v_type text := lower(coalesce(nullif(btrim(p_row->>'record_type'), ''), 'named_staff'));
        v_ext text := nullif(btrim(p_row->>'external_id'), '');
        v_status text := lower(coalesce(nullif(btrim(p_row->>'lifecycle_status'), ''), 'active'));
        v_email text := nullif(lower(btrim(p_row->>'work_email')), '');
        v_target uuid := nullif(p_row->>'contact_id', '')::uuid;
        v_key text; v_old pipeline.partner_contacts%rowtype; v_new pipeline.partner_contacts%rowtype;
begin
  if p_source not in ('study_square_admin', 'zoho_crm_partner') then raise exception 'INVALID_INPUT: unknown partner contact source' using errcode = '22023'; end if;
  if v_provider is null or not exists (select 1 from catalogue.providers p where p.id = v_provider) then raise exception 'INVALID_INPUT: a valid provider_id is required' using errcode = '22023'; end if;
  if v_type not in ('named_staff', 'team_contact') then raise exception 'INVALID_INPUT: record_type is named_staff or team_contact' using errcode = '22023'; end if;
  if v_status not in ('active', 'inactive') then raise exception 'INVALID_INPUT: lifecycle_status is active or inactive' using errcode = '22023'; end if;
  v_key := lower(v_type || '|' || coalesce(v_email, nullif(btrim(p_row->>'full_name'), ''), nullif(btrim(p_row->>'team_name'), ''), nullif(btrim(p_row->>'job_title'), ''), ''));
  if v_key = lower(v_type || '|') then raise exception 'INVALID_INPUT: a contact needs an email, a name, a team or a job title' using errcode = '22023'; end if;
  if v_target is not null then
    -- an Admin edit names its contact, so changing the email or name updates that row instead of adding one
    select * into v_old from pipeline.partner_contacts c where c.id = v_target for update;
    if not found then raise exception 'INVALID_INPUT: partner contact not found' using errcode = '22023'; end if;
  else
    select * into v_old from pipeline.partner_contacts c
     where (v_ext is not null and c.source = p_source and c.external_id = v_ext) or (c.provider_id = v_provider and c.identity_key = v_key)
     order by (c.external_id is not distinct from v_ext) desc limit 1 for update;
  end if;
  if v_old.id is null then
    insert into pipeline.partner_contacts (provider_id, record_type, full_name, team_name, job_title, functional_area, region_scope, countries_or_markets,
           work_email, work_phone, staff_location, verified_on, lifecycle_status, source, external_id, identity_key, reason, created_by, updated_by)
    values (v_provider, v_type, nullif(btrim(p_row->>'full_name'), ''), nullif(btrim(p_row->>'team_name'), ''), nullif(btrim(p_row->>'job_title'), ''),
            nullif(btrim(p_row->>'functional_area'), ''), nullif(btrim(p_row->>'region_scope'), ''), nullif(btrim(p_row->>'countries_or_markets'), ''),
            v_email, nullif(btrim(p_row->>'work_phone'), ''), nullif(btrim(p_row->>'staff_location'), ''), nullif(p_row->>'verified_on', '')::date,
            v_status, p_source, v_ext, v_key, p_reason, p_actor, p_actor)
    returning * into v_new;
    insert into pipeline.partner_contact_events (contact_id, event, actor_id, reason, after)
    values (v_new.id, case when p_source = 'zoho_crm_partner' then 'import_create' else 'create' end, p_actor, p_reason, to_jsonb(v_new));
    return jsonb_build_object('action', 'created', 'contact_id', v_new.id);
  end if;
  update pipeline.partner_contacts c set
    provider_id = v_provider, record_type = v_type,
    full_name = case when p_row ? 'full_name' then nullif(btrim(p_row->>'full_name'), '') else c.full_name end,
    team_name = case when p_row ? 'team_name' then nullif(btrim(p_row->>'team_name'), '') else c.team_name end,
    job_title = case when p_row ? 'job_title' then nullif(btrim(p_row->>'job_title'), '') else c.job_title end,
    functional_area = case when p_row ? 'functional_area' then nullif(btrim(p_row->>'functional_area'), '') else c.functional_area end,
    region_scope = case when p_row ? 'region_scope' then nullif(btrim(p_row->>'region_scope'), '') else c.region_scope end,
    countries_or_markets = case when p_row ? 'countries_or_markets' then nullif(btrim(p_row->>'countries_or_markets'), '') else c.countries_or_markets end,
    work_email = case when p_row ? 'work_email' then v_email else c.work_email end,
    work_phone = case when p_row ? 'work_phone' then nullif(btrim(p_row->>'work_phone'), '') else c.work_phone end,
    staff_location = case when p_row ? 'staff_location' then nullif(btrim(p_row->>'staff_location'), '') else c.staff_location end,
    verified_on = case when p_row ? 'verified_on' then nullif(p_row->>'verified_on', '')::date else c.verified_on end,
    lifecycle_status = case when p_row ? 'lifecycle_status' then v_status else c.lifecycle_status end,
    external_id = coalesce(v_ext, c.external_id), identity_key = v_key, reason = p_reason, updated_at = now(), updated_by = p_actor
   where c.id = v_old.id returning * into v_new;
  if (to_jsonb(v_new) - 'updated_at' - 'updated_by' - 'reason') = (to_jsonb(v_old) - 'updated_at' - 'updated_by' - 'reason') then
    return jsonb_build_object('action', 'unchanged', 'contact_id', v_new.id);
  end if;
  insert into pipeline.partner_contact_events (contact_id, event, actor_id, reason, before, after)
  values (v_new.id, case when p_source = 'zoho_crm_partner' then 'import_update' else 'update' end, p_actor, p_reason, to_jsonb(v_old), to_jsonb(v_new));
  return jsonb_build_object('action', 'updated', 'contact_id', v_new.id);
end $function$;
comment on function security.partner_contact_upsert_v1(jsonb, text, uuid, text) is 'CF-247 s997: creates or updates one Study Square partner contact (matched by source and external id, then by provider and identity) and logs the event.';
revoke all on function security.partner_contact_upsert_v1(jsonb, text, uuid, text) from public, anon, authenticated;

create or replace function public.admin_partner_contact_save_v1(p_action text, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_uid uuid := auth.uid(); v_action text := lower(btrim(coalesce(p_action, ''))); v_id uuid; v_reason text;
        v_old pipeline.partner_contacts%rowtype; v_new pipeline.partner_contacts%rowtype;
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 5 then raise exception 'PIM Operator role required for partner contacts' using errcode = '42501'; end if; -- fixed: same role as Provider Contact management
  v_reason := nullif(btrim(coalesce(p_payload->>'reason', '')), '');
  if v_action in ('create', 'update') then
    if v_action = 'update' then
      v_id := nullif(p_payload->>'contact_id', '')::uuid;
      select * into v_old from pipeline.partner_contacts c where c.id = v_id;
      if not found then raise exception 'INVALID_INPUT: partner contact not found' using errcode = '22023'; end if;
      p_payload := jsonb_build_object('provider_id', v_old.provider_id, 'record_type', v_old.record_type, 'external_id', v_old.external_id)
                   || jsonb_strip_nulls(jsonb_build_object('full_name', v_old.full_name, 'team_name', v_old.team_name, 'job_title', v_old.job_title, 'work_email', v_old.work_email))
                   || p_payload;
    end if;
    return security.partner_contact_upsert_v1(case when v_action = 'create' then p_payload - 'contact_id' else p_payload end - 'reason', 'study_square_admin', v_uid, coalesce(v_reason, 'Partner contact ' || v_action || ' in Admin'));
  elsif v_action in ('activate', 'deactivate') then
    v_id := nullif(p_payload->>'contact_id', '')::uuid;
    if v_action = 'deactivate' and v_reason is null then raise exception 'INVALID_INPUT: a reason is required to deactivate a partner contact' using errcode = '22023'; end if;
    select * into v_old from pipeline.partner_contacts c where c.id = v_id for update;
    if not found then raise exception 'INVALID_INPUT: partner contact not found' using errcode = '22023'; end if;
    update pipeline.partner_contacts c set lifecycle_status = case when v_action = 'activate' then 'active' else 'inactive' end,
           reason = coalesce(v_reason, 'Partner contact activated in Admin'), updated_at = now(), updated_by = v_uid
     where c.id = v_id returning * into v_new;
    insert into pipeline.partner_contact_events (contact_id, event, actor_id, reason, before, after)
    values (v_id, v_action, v_uid, coalesce(v_reason, 'Partner contact activated in Admin'), to_jsonb(v_old), to_jsonb(v_new));
    return jsonb_build_object('action', v_action, 'contact_id', v_id, 'lifecycle_status', v_new.lifecycle_status);
  end if;
  raise exception 'INVALID_INPUT: action is create, update, activate or deactivate' using errcode = '22023';
end $function$;
comment on function public.admin_partner_contact_save_v1(text, jsonb) is 'CF-247 s997 (REQ-116 / REQ-22): Admin entry of Study Square partner contacts (create, update, activate, deactivate with a reason). PIM Operator and above. Never deletes.';
revoke all on function public.admin_partner_contact_save_v1(text, jsonb) from public, anon;
grant execute on function public.admin_partner_contact_save_v1(text, jsonb) to authenticated;

create or replace function public.admin_partner_contacts_import_v1(p_rows jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_uid uuid := auth.uid(); v_max int := greatest(1, security.pipeline_num_v1('partner_contacts.import_max_rows', 1000)::int);
        v_row jsonb; v_i int := 0; v_r jsonb; v_created int := 0; v_updated int := 0; v_same int := 0; v_bad jsonb := '[]'::jsonb;
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 5 then raise exception 'PIM Operator role required for partner contacts' using errcode = '42501'; end if; -- fixed: same role as Provider Contact management
  if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'INVALID_INPUT: rows must be a JSON array' using errcode = '22023'; end if;
  if jsonb_array_length(p_rows) > v_max then raise exception 'INVALID_INPUT: % rows; one import takes at most % (split the file)', jsonb_array_length(p_rows), v_max using errcode = '22023'; end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'INVALID_INPUT: a reason is required for an import' using errcode = '22023'; end if;
  for v_row in select x from jsonb_array_elements(p_rows) x loop
    v_i := v_i + 1;
    begin
      v_r := security.partner_contact_upsert_v1(v_row - 'contact_id', 'zoho_crm_partner', v_uid, p_reason);
      case v_r->>'action' when 'created' then v_created := v_created + 1; when 'updated' then v_updated := v_updated + 1; else v_same := v_same + 1; end case;
    exception when others then
      v_bad := v_bad || jsonb_build_array(jsonb_build_object('row', v_i, 'external_id', v_row->>'external_id',
                 'error', case when sqlerrm like 'INVALID_INPUT:%' then sqlerrm else 'INVALID_INPUT: the row could not be read' end));
    end;
  end loop;
  return jsonb_build_object('rows', v_i, 'created', v_created, 'updated', v_updated, 'unchanged', v_same, 'rejected', jsonb_array_length(v_bad), 'rejected_rows', v_bad);
end $function$;
comment on function public.admin_partner_contacts_import_v1(jsonb, text) is 'CF-247 s997 (REQ-116 / REQ-22): imports Study Square partner contacts from the Zoho CRM partner export handed over by a person (no scraping). Upserts by Zoho record id, then provider and identity; reports rejected rows. PIM Operator and above.';
revoke all on function public.admin_partner_contacts_import_v1(jsonb, text) from public, anon;
grant execute on function public.admin_partner_contacts_import_v1(jsonb, text) to authenticated;

create or replace function public.provider_partner_contacts_v1(p_provider_id uuid, p_status text default 'active')
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_status text := lower(coalesce(nullif(btrim(p_status), ''), 'active'));
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 2 then raise exception 'Counsellor (rank 2) or above is needed for partner contacts' using errcode = '42501'; end if; -- fixed: who opens the provider Contacts tab
  if v_status not in ('active', 'inactive', 'all') then raise exception 'INVALID_INPUT: status is active, inactive or all' using errcode = '22023'; end if;
  if p_provider_id is null then raise exception 'INVALID_INPUT: provider_id is required' using errcode = '22023'; end if;
  return jsonb_build_object(
    'provider_id', p_provider_id, 'status', v_status, 'source', 'study_square_partner',
    'active_count', (select count(*) from pipeline.partner_contacts c where c.provider_id = p_provider_id and c.lifecycle_status = 'active'),
    'inactive_count', (select count(*) from pipeline.partner_contacts c where c.provider_id = p_provider_id and c.lifecycle_status = 'inactive'),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('contact_id', c.id, 'record_type', c.record_type, 'full_name', c.full_name, 'team_name', c.team_name,
               'job_title', c.job_title, 'functional_area', c.functional_area, 'region_scope', c.region_scope, 'countries_or_markets', c.countries_or_markets,
               'work_email', c.work_email, 'work_phone', c.work_phone, 'staff_location', c.staff_location, 'verified_on', c.verified_on,
               'lifecycle_status', c.lifecycle_status, 'source', c.source, 'updated_at', c.updated_at)
               order by c.lifecycle_status, c.record_type, lower(coalesce(c.full_name, c.team_name, c.job_title, '')), c.id), '[]'::jsonb)
               from pipeline.partner_contacts c where c.provider_id = p_provider_id and (v_status = 'all' or c.lifecycle_status = v_status)));
end $function$;
comment on function public.provider_partner_contacts_v1(uuid, text) is 'CF-247 s997 (REQ-116): Study Square partner contacts of one provider for the Contacts tab, with active_count and inactive_count (so the screen can say none are held). Counsellor and above.';
revoke all on function public.provider_partner_contacts_v1(uuid, text) from public, anon;
grant execute on function public.provider_partner_contacts_v1(uuid, text) to authenticated;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s997_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s997_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if position('budget_cap' in pg_get_functiondef('public.admin_boost_queue_read(jsonb)'::regprocedure)) = 0 then raise exception 'post-check: the Boost read has no budget_cap'; end if;
  if position('is_saved' in pg_get_functiondef('security.course_list_extras_v1(uuid[])'::regprocedure)) = 0 then raise exception 'post-check: the course list has no is_saved'; end if;
  if not (select relrowsecurity from pg_class where oid = 'pipeline.saved_courses'::regclass) or not (select relrowsecurity from pg_class where oid = 'pipeline.partner_contacts'::regclass) then
    raise exception 'post-check: row-level security is off on a new table';
  end if;
  if has_function_privilege('anon', 'public.saved_course_toggle_v1(uuid,boolean)', 'execute') or has_function_privilege('anon', 'public.provider_partner_contacts_v1(uuid,text)', 'execute')
     or has_function_privilege('anon', 'public.admin_partner_contacts_import_v1(jsonb,text)', 'execute') or has_table_privilege('anon', 'pipeline.saved_courses', 'select') then
    raise exception 'post-check: anon can reach a new object';
  end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('budgets.paid_daily_cap_usd', 'saved_courses.max_per_user', 'partner_contacts.import_max_rows')) <> 3 then
    raise exception 'post-check: a setting is missing';
  end if;
  if (security.boost_budget_cap_v1(0)->>'source_key') is distinct from 'firecrawl.daily_budget_total' then raise exception 'post-check: the budget cap block does not read'; end if;
  if md5(pg_get_functiondef('public.admin_boost_queue_read(jsonb)'::regprocedure)) <> 'd07d17506a3d9c9c17560413210869d5' then raise exception 'post-check: the Boost read is not the rehearsed definition'; end if;
  if md5(pg_get_functiondef('security.course_list_extras_v1(uuid[])'::regprocedure)) <> 'eb90ce361baa2bef1bdc46764c8cc74f' then raise exception 'post-check: the course list extras are not the rehearsed definition'; end if;
end $post$;
