-- CF-247 (Platform Admin, 1 Oct 2026 16:54 AEST): "schedule jobs to refresh it across unis (all countries or country
-- specific). There will be more countries added." Decision 201.
--
-- pipeline.link_refresh_policies says how often each kind of course link is re-checked, for every country (country
-- blank), one country, or one provider. The most specific active policy wins for a course. Seeded for every country:
-- official course page every 30 days, handbook and admission centre listings every 90 days, regulator listings every
-- 90 days. A new country is covered by the all-countries policies the day its courses arrive.
--
-- security.link_refresh_tick_v1 (job link-refresh, every 10 minutes, listed in Automations) does, within its batch:
--   1. Official pages due for a re-check are re-read by the existing course-page reader (next_read_at = now).
--   2. Courses whose page search found nothing (or failed) are searched again once their policy period has passed.
--   3. The result of each read is carried to the catalogue link: a page read again and still showing the course's code
--      keeps its link and gets a new last-verified date; a page that is gone (404/410 on two reads) is marked
--      'unverified' (no longer counted as the course's page) and the course is queued for a new search; a page that
--      still loads but no longer shows the course's code keeps its link and the course is searched again (at most once
--      per policy period). Links set by a person or confirmed in Layer 4 are never changed.
--   4. Regulator listings: NZ courses that gained an NZQA code get their NZQA page.
-- Nothing here admits a new value; it only re-checks and re-queues.
--
-- pipeline.link_portals lists third-party and regulatory portals that can supply course links, per country, for the
-- portal harvest worker (coverage-sweep mode "portal"): NZQA (regulator, per-programme page, live through the regulator
-- listings above), UAC, VTAC, QTAC, SATAC and TISC (admission centres) and Study Australia (government portal). Portals
-- start switched off except NZQA; each is switched on in Automations once its reader is verified.

create table if not exists pipeline.link_refresh_policies (
  id uuid primary key default gen_random_uuid(),
  country_id uuid references ref.countries(id),
  provider_id uuid references catalogue.providers(id),
  link_type text not null references ref.course_link_types(code),
  every_days int not null check (every_days between 1 and 365),
  active boolean not null default true,
  notes text,
  last_run_at timestamptz,
  last_result jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  constraint link_refresh_policies_scope_key unique nulls not distinct (country_id, provider_id, link_type)
);
alter table pipeline.link_refresh_policies enable row level security;

insert into pipeline.link_refresh_policies(country_id, provider_id, link_type, every_days, notes) values
  (null, null, 'official_course', 30, 'All countries: re-read each official course page every 30 days'),
  (null, null, 'handbook', 90, 'All countries'),
  (null, null, 'admission_centre', 90, 'All countries'),
  (null, null, 'regulator_listing', 90, 'All countries')
on conflict on constraint link_refresh_policies_scope_key do nothing;

create table if not exists pipeline.link_portals (
  code text primary key,
  label text not null,
  country_id uuid references ref.countries(id),
  kind text not null check (kind in ('regulator','admission_centre','government_portal','aggregator')),
  link_type text not null references ref.course_link_types(code),
  base_url text not null,
  course_url_pattern text,
  applicant text not null default 'any' check (applicant in ('any','international','domestic')),
  active boolean not null default false,
  every_days int not null default 30 check (every_days between 1 and 365),
  last_run_at timestamptz,
  last_result jsonb,
  notes text,
  updated_at timestamptz not null default now()
);
alter table pipeline.link_portals enable row level security;

insert into pipeline.link_portals(code, label, country_id, kind, link_type, base_url, course_url_pattern, applicant, active, every_days, notes)
select v.code, v.label, (select id from ref.countries where iso_alpha2 = v.cc), v.kind, v.link_type, v.base_url, v.pat, v.applicant, v.active, v.days, v.notes
  from (values
    ('nzqa', 'NZQA qualification search', 'NZ', 'regulator', 'regulator_listing', 'https://www.nzqa.govt.nz/nzqf/search/',
     '^https://www\.nzqa\.govt\.nz/nzqf/search/viewQualification\.do\?selectedItemKey=[A-Z0-9]+$', 'any', true, 90,
     'Per-programme page from the NZQA code; links to the provider and the Tahatu outcomes page'),
    ('uac', 'UAC course search (NSW, ACT)', 'AU', 'admission_centre', 'admission_centre', 'https://uac.edu.au/course-search/',
     '^https://uac\.edu\.au/course-search/search/(undergraduate|postgraduate)/course/[0-9]+$', 'domestic', false, 90,
     'Course pages link to the institution''s course page'),
    ('vtac', 'VTAC course search (VIC)', 'AU', 'admission_centre', 'admission_centre', 'https://vtac.edu.au/',
     null, 'domestic', false, 90, 'Institution pages list courses; course pages carry a Further information link'),
    ('qtac', 'QTAC course search (QLD)', 'AU', 'admission_centre', 'admission_centre', 'https://www.qtac.edu.au/', null, 'domestic', false, 90, null),
    ('satac', 'SATAC course search (SA, NT)', 'AU', 'admission_centre', 'admission_centre', 'https://www.satac.edu.au/', null, 'domestic', false, 90, null),
    ('tisc', 'TISC course search (WA)', 'AU', 'admission_centre', 'admission_centre', 'https://www.tisc.edu.au/', null, 'domestic', false, 90, null),
    ('study_australia', 'Study Australia course search', 'AU', 'government_portal', 'official_course', 'https://www.studyaustralia.gov.au/',
     null, 'international', false, 30, 'Government portal for international students; results link to institution pages')
  ) v(code, label, cc, kind, link_type, base_url, pat, applicant, active, days, notes)
on conflict (code) do nothing;

create or replace function security.link_refresh_policy_days(p_course_id uuid, p_link_type text) returns int
language sql stable security definer set search_path = '' as $fn$
  select r.every_days from pipeline.link_refresh_policies r
    join catalogue.courses c on c.id = p_course_id join catalogue.providers p on p.id = c.provider_id
   where r.active and r.link_type = p_link_type
     and (r.provider_id is null or r.provider_id = c.provider_id)
     and (r.country_id is null or r.country_id = p.country_id)
   order by (r.provider_id is not null) desc, (r.country_id is not null) desc
   limit 1
$fn$;

create or replace function security.link_refresh_tick_v1(p_limit int default 500) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v_lim int := greatest(1, least(coalesce(p_limit, 500), 5000)); v_reread int := 0; v_research int := 0; v_verified int := 0;
        v_unverified int := 0; v_reg int := 0; v_manual uuid; v_l4 uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select id into v_manual from pipeline.sources where source_type = 'manual_entry' limit 1;
  select id into v_l4 from pipeline.sources where source_type = 'layer4_human_review' limit 1;

  -- 1. Official pages due for a re-check: the reader reads them again.
  with due as (
    select p.course_id from pipeline.coverage_course_pages p
     where p.status = 'bound' and p.read_status = 'read' and p.identity_basis is not null
       and coalesce(p.next_read_at, now()) <= now() and coalesce(p.leased_until, '-infinity') < now()
       and p.read_at < now() - make_interval(days => coalesce(security.link_refresh_policy_days(p.course_id, 'official_course'), 30))
     order by p.read_at limit v_lim)
  update pipeline.coverage_course_pages p set next_read_at = now(), read_attempts = 0 from due where p.course_id = due.course_id;
  get diagnostics v_reread = row_count;

  -- 2. Courses whose page search found nothing are searched again after their policy period.
  with due as (
    select s.course_id from pipeline.course_link_search s
     where s.state in ('none','error')
       and coalesce(s.done_at, s.queued_at) < now() - make_interval(days => coalesce(security.link_refresh_policy_days(s.course_id, 'official_course'), 30))
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = s.course_id and k.field = 'official_url')
     order by coalesce(s.done_at, s.queued_at) limit v_lim)
  update pipeline.course_link_search s set state = 'queued', stage = 'cricos', attempts = 0, done_at = null, queued_at = now()
    from due where s.course_id = due.course_id;
  get diagnostics v_research = row_count;

  -- 3. Carry each read to the catalogue link (never a link set by a person or confirmed in Layer 4).
  update catalogue.course_links l set last_verified_at = p.read_at, updated_at = now()
    from pipeline.coverage_course_pages p
   where l.link_type = 'official_course' and l.status = 'active' and p.course_id = l.course_id
     and security.coverage_norm_url(p.url) = security.coverage_norm_url(l.url)
     and p.read_status = 'read' and p.identity_basis is not null and p.read_at > coalesce(l.last_verified_at, '-infinity')
     and l.source_id is distinct from v_manual and l.source_id is distinct from v_l4;
  get diagnostics v_verified = row_count;

  with gone as (
    select l.id, l.course_id from catalogue.course_links l
      join pipeline.coverage_course_pages p on p.course_id = l.course_id and security.coverage_norm_url(p.url) = security.coverage_norm_url(l.url)
     where l.link_type = 'official_course' and l.status = 'active'
       and l.source_id is distinct from v_manual and l.source_id is distinct from v_l4
       and p.read_at > coalesce(l.last_verified_at, l.created_at)
       and p.read_status = 'fetch_failed' and p.http_status in (404, 410) and p.read_attempts >= 2
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = l.course_id and k.field = 'official_url')
     limit v_lim),
  upd as (update catalogue.course_links l set status = 'unverified', is_primary = false, updated_at = now() from gone where l.id = gone.id returning l.course_id),
  -- a page that still loads but no longer shows the course's code keeps its link; the course is searched again, and a
  -- better page found that way reaches Layer 4 as "differs" through the normal admission path.
  doubt as (
    select l.course_id from catalogue.course_links l
      join pipeline.coverage_course_pages p on p.course_id = l.course_id and security.coverage_norm_url(p.url) = security.coverage_norm_url(l.url)
     where l.link_type = 'official_course' and l.status = 'active' and p.read_status = 'identity_mismatch'
       and p.read_at > coalesce(l.last_verified_at, l.created_at)
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = l.course_id and k.field = 'official_url')
     limit v_lim),
  ins as (
    insert into pipeline.course_link_search(course_id, provider_id)
    select distinct x.course_id, c.provider_id from (select course_id from upd union select course_id from doubt) x join catalogue.courses c on c.id = x.course_id
     where exists (select 1 from pipeline.course_link_recipes r where r.provider_id = c.provider_id and r.active)
    on conflict (course_id) do update set state = 'queued', stage = 'cricos', attempts = 0, done_at = null, queued_at = now()
     where pipeline.course_link_search.state in ('none','error')
       and coalesce(pipeline.course_link_search.done_at, pipeline.course_link_search.queued_at)
           < now() - make_interval(days => coalesce(security.link_refresh_policy_days(excluded.course_id, 'official_course'), 30))
    returning 1)
  select (select count(*) from upd) into v_unverified;

  -- 4. Regulator listings for NZ courses that gained an NZQA code.
  insert into catalogue.course_links(course_id, link_type, url, label, is_primary, status, source_id, confidence)
  select r.course_id, 'regulator_listing',
         'https://www.nzqa.govt.nz/nzqf/search/viewQualification.do?selectedItemKey=' || upper(btrim(r.registration_code)),
         'NZQA qualification listing', false, 'active',
         (select s.id from pipeline.sources s where s.url ilike 'https://www.nzqa.govt.nz/providers/%' order by s.created_at limit 1), 0.95
    from catalogue.course_registrations r join catalogue.courses c on c.id = r.course_id and c.lifecycle_status = 'active'
   where lower(r.scheme) = 'nzqa' and coalesce(r.status, 'active') = 'active' and btrim(r.registration_code) ~* '^[A-Z0-9]{3,12}$'
     and exists (select 1 from pipeline.link_portals lp where lp.code = 'nzqa' and lp.active)
     and not exists (select 1 from catalogue.course_links l where l.course_id = r.course_id and l.link_type = 'regulator_listing')
   limit v_lim
  on conflict (course_id, link_type, url) do nothing;
  get diagnostics v_reg = row_count;

  update pipeline.link_refresh_policies set last_run_at = now(),
         last_result = jsonb_build_object('reread', v_reread, 'searched_again', v_research, 'verified', v_verified, 'unverified', v_unverified, 'regulator_added', v_reg)
   where active and provider_id is null and country_id is null;
  return jsonb_build_object('reread', v_reread, 'searched_again', v_research, 'verified', v_verified, 'unverified', v_unverified, 'regulator_added', v_reg);
end $fn$;
revoke all on function security.link_refresh_tick_v1(int) from public, anon, authenticated;

-- Read and maintain the policies and portals (Coverage › Course pages).
create or replace function public.admin_link_refresh_read() returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_edit', v_rank >= 4,
    'policies', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'country', k.iso_alpha2, 'country_name', k.name, 'provider_id', r.provider_id,
                   'provider', coalesce(p.display_name, p.canonical_name), 'link_type', r.link_type, 'type_label', t.label, 'every_days', r.every_days,
                   'active', r.active, 'notes', r.notes, 'last_run_at', r.last_run_at, 'last_result', r.last_result)
                   order by t.sort, k.iso_alpha2 nulls first, p.canonical_name nulls first), '[]'::jsonb)
                   from pipeline.link_refresh_policies r join ref.course_link_types t on t.code = r.link_type
                   left join ref.countries k on k.id = r.country_id left join catalogue.providers p on p.id = r.provider_id),
    'portals', (select coalesce(jsonb_agg(jsonb_build_object('code', lp.code, 'label', lp.label, 'country', k.iso_alpha2, 'kind', lp.kind,
                   'link_type', lp.link_type, 'base_url', lp.base_url, 'applicant', lp.applicant, 'active', lp.active, 'every_days', lp.every_days,
                   'last_run_at', lp.last_run_at, 'last_result', lp.last_result, 'notes', lp.notes) order by k.iso_alpha2, lp.code), '[]'::jsonb)
                  from pipeline.link_portals lp left join ref.countries k on k.id = lp.country_id),
    'types', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'label', label) order by sort), '[]'::jsonb) from ref.course_link_types where status = 'active'),
    'countries', (select coalesce(jsonb_agg(distinct k.iso_alpha2), '[]'::jsonb) from catalogue.providers p join ref.countries k on k.id = p.country_id));
end $fn$;
revoke all on function public.admin_link_refresh_read() from public, anon;
grant execute on function public.admin_link_refresh_read() to authenticated;

create or replace function public.admin_link_refresh_edit(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v_rank int := security.current_role_rank(); v_country uuid; v_days int;
begin
  if auth.uid() is null or v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
  if p_action in ('save_policy') then
    v_days := nullif(p_args->>'every_days', '')::int;
    if v_days is null or v_days not between 1 and 365 then raise exception 'choose a number of days from 1 to 365'; end if;
    if not exists (select 1 from ref.course_link_types where code = p_args->>'link_type' and status = 'active') then raise exception 'choose a link type'; end if;
    if nullif(p_args->>'country', '') is not null then
      select id into v_country from ref.countries where iso_alpha2 = upper(p_args->>'country');
      if v_country is null then raise exception 'unknown country %', p_args->>'country'; end if;
    end if;
    if nullif(p_args->>'id', '') is not null then
      update pipeline.link_refresh_policies set every_days = v_days, active = coalesce((p_args->>'active')::boolean, active),
             notes = coalesce(nullif(p_args->>'notes', ''), notes), updated_at = now(), updated_by = auth.uid()
       where id = (p_args->>'id')::uuid;
    else
      insert into pipeline.link_refresh_policies(country_id, provider_id, link_type, every_days, active, notes, updated_by)
      values (v_country, nullif(p_args->>'provider_id', '')::uuid, p_args->>'link_type', v_days, coalesce((p_args->>'active')::boolean, true),
              nullif(p_args->>'notes', ''), auth.uid())
      on conflict on constraint link_refresh_policies_scope_key do update set every_days = excluded.every_days, active = excluded.active,
             notes = coalesce(excluded.notes, pipeline.link_refresh_policies.notes), updated_at = now(), updated_by = auth.uid();
    end if;
  elsif p_action = 'remove_policy' then
    delete from pipeline.link_refresh_policies where id = (p_args->>'id')::uuid and (country_id is not null or provider_id is not null);
    if not found then raise exception 'the all-countries policies stay; switch them off instead'; end if;
  elsif p_action = 'portal' then
    update pipeline.link_portals set active = coalesce((p_args->>'active')::boolean, active),
           every_days = coalesce(nullif(p_args->>'every_days', '')::int, every_days), updated_at = now()
     where code = p_args->>'code';
    if not found then raise exception 'unknown portal'; end if;
  else raise exception 'unknown action %', p_action; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('link_refresh', p_action, coalesce(p_args->>'id', p_args->>'code', p_args->>'link_type'), p_args, auth.uid());
  return public.admin_link_refresh_read();
end $fn$;
revoke all on function public.admin_link_refresh_edit(text, jsonb) from public, anon;
grant execute on function public.admin_link_refresh_edit(text, jsonb) to authenticated;

-- Job, listed in Automations.
select cron.unschedule(jobid) from cron.job where jobname = 'link-refresh';
select cron.schedule('link-refresh', '*/10 * * * *', $$select security.link_refresh_tick_v1(500)$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('link-refresh', 'Course pages', 25, 'Refresh course links',
        'Re-reads official course pages, searches again for courses with no page, and keeps link check dates current, on the schedule set per country, provider and link type.', 5, true)
on conflict (jobname) do update set area = excluded.area, sort = excluded.sort, label = excluded.label, description = excluded.description,
       control_rank = excluded.control_rank, batch_editable = excluded.batch_editable;
