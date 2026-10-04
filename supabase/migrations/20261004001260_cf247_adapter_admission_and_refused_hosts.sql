-- CF-247 Decision 253 amended (Platform Admin, 4 Oct 2026 17:19): "Admit from adapter rule but I need to test it or ask
-- for improvements on it, step 2, yes refuse".
--   1. Adapter identities may be admitted. The country admission rules now list adapter_code and adapter_title for
--      official links, English and intakes (not tuition) in AU, NZ and CA. Each adapter also has its own "admit"
--      switch, off by default: nothing an adapter confirms is admitted until the Platform Admin has tested that
--      adapter (preview, and the list of what it would admit) and switched it on. The admission gate checks both.
--   2. Requests for improvement. The Platform Admin can write a request against an adapter. Requests are listed with
--      the adapter (open or done) for whoever improves it next.
--   3. Archived and test sites are refused. A setting holds the pattern of host names never used (archive, dev, test,
--      staging, uat and the pre-2025 UTS handbook). A page on such a host is never bound or read as a course's page.
--      Pages already bound there are refused and sent to Find pages. Values admitted automatically from those pages
--      are taken out of use (links deprecated, English and intakes withdrawn). Values entered by hand are not touched.
--      Every change is logged in pipeline.refused_host_changes.
-- No text value in this file contains a semicolon.

alter table pipeline.uni_adapters add column if not exists admit boolean not null default false;
alter table pipeline.uni_adapters add column if not exists admit_reason text;
alter table pipeline.uni_adapters add column if not exists admit_changed_at timestamptz;

create table if not exists pipeline.uni_adapter_requests (
  id bigserial primary key,
  provider_id uuid not null,
  request text not null,
  status text not null default 'open' check (status in ('open', 'done', 'declined')),
  answer text,
  requested_by uuid,
  requested_at timestamptz not null default now(),
  answered_at timestamptz
);
alter table pipeline.uni_adapter_requests enable row level security;
revoke all on pipeline.uni_adapter_requests from anon, authenticated;

create table if not exists pipeline.refused_host_changes (
  id bigserial primary key,
  course_id uuid,
  entity text not null,
  entity_id uuid,
  url text,
  before_status text,
  after_status text,
  at timestamptz not null default now()
);
alter table pipeline.refused_host_changes enable row level security;
revoke all on pipeline.refused_host_changes from anon, authenticated;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section) values
  ('firecrawl', 'refused_host_pattern', 'Sites never used (archived and test)', 'A pattern (regular expression, any case) of host names. A page on such a host is never bound or read as a course page, for any provider.', 'text', '"^(archive|archive-dev|archive-test|test|dev|staging|uat)[.-]|handbookpre[0-9]{4}|[.-](dev|test|staging|uat)[.-]"', null, null, null, 105, 'Decision 253, Platform Admin 17:19', 'Target universities')
on conflict (toolset_key, key) do nothing;

create or replace function security.refused_host(p_url text) returns boolean
language sql stable security definer set search_path = '' as $f$
  select coalesce(substring(coalesce(p_url, '') from '^https?://([^/?#]+)') ~* nullif(btrim(coalesce(security.firecrawl_setting('refused_host_pattern') #>> '{}', '')), ''), false)
$f$;
revoke all on function security.refused_host(text) from public, anon, authenticated;

-- One gate for every way a page is bound: a page on a refused host is never the course's page.
create or replace function security.coverage_page_refused_host_guard() returns trigger
language plpgsql security definer set search_path = '' as $f$
begin
  if new.status in ('bound', 'ambiguous') and security.refused_host(new.url)
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = new.course_id and k.field = 'official_url') then
    new.status := 'mismatch'; new.read_status := 'refused_host'; new.identity_basis := null; new.next_read_at := null;
  end if;
  return new;
end $f$;
revoke all on function security.coverage_page_refused_host_guard() from public, anon, authenticated;
create trigger coverage_page_refused_host before insert or update of url, status on pipeline.coverage_course_pages
  for each row execute function security.coverage_page_refused_host_guard();

-- The admission gate: an adapter identity counts only when the country rule lists it AND that adapter's admit switch
-- is on (md5-guarded replacement of the whole function, it is one statement).
do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'security.coverage_identity_allowed(uuid,text,text)'::regprocedure) is distinct from 'e780e135bc2e801de598b6d4234c5ae8' then
    raise exception 'coverage_identity_allowed changed, not replacing'; end if;
end $g$;
create or replace function security.coverage_identity_allowed(p_provider_id uuid, p_basis text, p_attr text) returns boolean
language sql stable security definer set search_path = '' as $function$
  select case when p_basis in ('adapter_code', 'adapter_title')
                   and not exists (select 1 from pipeline.uni_adapters u where u.provider_id = p_provider_id and u.enabled and u.admit) then false
         else coalesce((
    select case when p_attr is null
                then exists (select 1 from jsonb_each(a.identities) e, jsonb_array_elements_text(e.value) b where b = p_basis)
                else coalesce(a.identities->p_attr ? p_basis, false) end
      from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
     where p.id = p_provider_id), false) end
$function$;

-- The country rules list the adapter identities (added to what is there, nothing taken out). Logged.
do $c$ declare r record; v_new jsonb; k text;
begin
  for r in select a.country_id, a.identities from pipeline.coverage_admission_countries a join ref.countries c on c.id = a.country_id where c.iso_alpha2 in ('AU', 'NZ', 'CA') loop
    v_new := r.identities;
    foreach k in array array['official_url', 'english', 'intakes'] loop
      v_new := jsonb_set(v_new, array[k], (select coalesce(jsonb_agg(distinct x), '[]'::jsonb) from (select jsonb_array_elements_text(coalesce(v_new->k, '[]'::jsonb)) x union select 'adapter_code' union select 'adapter_title') z));
    end loop;
    update pipeline.coverage_admission_countries set identities = v_new, approved_ref = approved_ref || '. Decision 253 (adapter identities, each adapter admits only when its own admit switch is on, Platform Admin 4 Oct 2026 17:19)', updated_at = now() where country_id = r.country_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('pipeline_settings', 'identity.attribute', r.country_id::text, jsonb_build_object('before', r.identities, 'after', v_new, 'reason', 'Decision 253, Platform Admin 17:19: admit from adapter rule'), null);
  end loop;
end $c$;

-- Find pages takes the courses whose page was on a refused host, whatever an earlier search found.
create or replace function security.firecrawl_backlog_v1(p_use_case text) returns table (course_id uuid, provider_id uuid, country text, url text, input jsonb)
language plpgsql stable security definer set search_path = '' as $f$
declare v_statuses text[]; v_retry boolean; v_like text; v_skip text;
begin
  select coalesce(array_agg(e), '{}') into v_statuses from jsonb_array_elements_text(coalesce(security.firecrawl_setting('read_statuses'), '[]'::jsonb)) e;
  v_retry := coalesce((security.firecrawl_setting('find_retry_refused') #>> '{}')::boolean, false);
  v_like := coalesce(nullif(btrim(security.firecrawl_setting('read_url_pattern') #>> '{}'), ''), '.');
  v_skip := nullif(btrim(coalesce(security.firecrawl_setting('read_skip_url_pattern') #>> '{}', '')), '');
  if p_use_case = 'read_page' then
    return query
    select pg.course_id, pg.provider_id, t.country, pg.url,
           jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'page_status', pg.status, 'earlier_read', pg.read_status, 'earlier_http', pg.http_status)
    from security.firecrawl_targets_v1() t
    join pipeline.coverage_course_pages pg on pg.provider_id = t.provider_id
    join catalogue.courses c on c.id = pg.course_id
    where t.included and c.lifecycle_status = 'active' and pg.status in ('bound', 'ambiguous') and pg.read_status = any(v_statuses)
      and pg.url is not null and coalesce(pg.http_status, 0) not in (404, 410) and pg.evidence_id is null
      and pg.url ~* v_like and (v_skip is null or pg.url !~* v_skip);
  elsif p_use_case = 'find_page' then
    return query
    select c.id, t.provider_id, t.country, null::text,
           jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'provider', t.name, 'domain', t.domain,
                              'earlier_url', pg.url, 'earlier_status', pg.status,
                              'refind', coalesce(pg.status in ('bound', 'ambiguous'), false))
    from security.firecrawl_targets_v1() t
    join catalogue.courses c on c.provider_id = t.provider_id
    left join pipeline.coverage_course_pages pg on pg.course_id = c.id
    where t.included and t.domain is not null and c.lifecycle_status = 'active'
      and (pg.course_id is null or pg.status not in ('bound', 'ambiguous')
           or (pg.read_status = any(v_statuses) and pg.evidence_id is null and (pg.url !~* v_like or (v_skip is not null and pg.url ~* v_skip))))
      and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field = 'official_url')
      and (pg.read_status is not distinct from 'refused_host'
           or not exists (select 1 from pipeline.search_pass_links l where l.course_id = c.id and (l.state in ('found', 'verified') or (l.state = 'none' and not v_retry))));
  end if;
end $f$;
revoke all on function security.firecrawl_backlog_v1(text) from public, anon, authenticated;

-- Refuse pages already bound on archived and test hosts, and take out of use what was admitted automatically from them.
do $r$ declare r record;
begin
  for r in select pg.course_id, pg.url, pg.evidence_id, pg.status, pg.read_status from pipeline.coverage_course_pages pg where security.refused_host(pg.url) and pg.read_status is distinct from 'refused_host'
             and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = pg.course_id and k.field = 'official_url') loop
    insert into pipeline.refused_host_changes(course_id, entity, url, before_status, after_status) values (r.course_id, 'course_page', r.url, r.status || ' ' || coalesce(r.read_status, ''), 'mismatch refused_host');
    update pipeline.coverage_course_pages set status = 'mismatch', read_status = 'refused_host', identity_basis = null, next_read_at = null where course_id = r.course_id;
    update pipeline.search_pass_links set state = 'none', updated_at = now() where course_id = r.course_id and bound_url = r.url;
    insert into pipeline.refused_host_changes(course_id, entity, entity_id, url, before_status, after_status)
      select cl.course_id, 'course_link', cl.id, cl.url, cl.status, 'deprecated' from catalogue.course_links cl left join pipeline.sources s on s.id = cl.source_id
      where cl.course_id = r.course_id and cl.url = r.url and cl.status = 'active' and coalesce(s.source_type, '') <> 'manual_entry';
    update catalogue.course_links cl set status = 'deprecated', updated_at = now() where cl.course_id = r.course_id and cl.url = r.url and cl.status = 'active' and not exists (select 1 from pipeline.sources s where s.id = cl.source_id and s.source_type = 'manual_entry');
    if r.evidence_id is not null then
      insert into pipeline.refused_host_changes(course_id, entity, entity_id, url, before_status, after_status)
        select e.course_id, 'english', e.id, r.url, e.status, 'withdrawn' from catalogue.course_english_requirements e left join pipeline.sources s on s.id = e.source_id
        where e.evidence_id = r.evidence_id and e.course_id = r.course_id and coalesce(e.status, 'active') = 'active' and coalesce(s.source_type, '') <> 'manual_entry'
        union all
        select i.course_id, 'intake', i.id, r.url, i.status, 'withdrawn' from catalogue.course_intakes i left join pipeline.sources s on s.id = i.source_id
        where i.evidence_id = r.evidence_id and i.course_id = r.course_id and coalesce(i.status, 'active') = 'active' and coalesce(s.source_type, '') <> 'manual_entry';
      update catalogue.course_english_requirements e set status = 'withdrawn' where e.evidence_id = r.evidence_id and e.course_id = r.course_id and coalesce(e.status, 'active') = 'active' and not exists (select 1 from pipeline.sources s where s.id = e.source_id and s.source_type = 'manual_entry');
      update catalogue.course_intakes i set status = 'withdrawn' where i.evidence_id = r.evidence_id and i.course_id = r.course_id and coalesce(i.status, 'active') = 'active' and not exists (select 1 from pipeline.sources s where s.id = i.source_id and s.source_type = 'manual_entry');
    end if;
  end loop;
end $r$;

-- The adapter of one university now also shows its admit switch, what it would admit (to test it) and the requests
-- for improvement.
create or replace function public.admin_uni_adapter_review(p_provider_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'admit', (select jsonb_build_object('on', u.admit, 'reason', u.admit_reason, 'changed_at', u.admit_changed_at) from pipeline.uni_adapters u where u.provider_id = p_provider_id),
    'confirmed', coalesce((select jsonb_agg(x) from (
        select jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'url', pg.url, 'identity', pg.identity_basis,
                                  'intakes', pg.candidates->'intakes', 'ielts', pg.candidates->'english'->'ielts_overall', 'english_context', left(pg.candidates->'english'->>'context', 160),
                                  'link_admitted', exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.url = pg.url and l.status = 'active'),
                                  'english_admitted', exists (select 1 from catalogue.course_english_requirements e where e.course_id = c.id and e.evidence_id = pg.evidence_id and coalesce(e.status, 'active') = 'active')) x
        from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id
        where pg.provider_id = p_provider_id and pg.identity_basis in ('adapter_code', 'adapter_title') and pg.read_status = 'read'
        order by pg.read_at desc nulls last limit 40) q), '[]'::jsonb),
    'confirmed_total', (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = p_provider_id and pg.identity_basis in ('adapter_code', 'adapter_title') and pg.read_status = 'read'),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'request', r.request, 'status', r.status, 'answer', r.answer, 'requested_at', r.requested_at, 'answered_at', r.answered_at) order by r.requested_at desc) from pipeline.uni_adapter_requests r where r.provider_id = p_provider_id), '[]'::jsonb)
  );
end $f$;
revoke all on function public.admin_uni_adapter_review(uuid) from public, anon;
grant execute on function public.admin_uni_adapter_review(uuid) to authenticated;

-- Switch admission on or off for one adapter, or write a request for improvement (Platform Admin, with a reason).
create or replace function public.admin_uni_adapter_control(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid := (p_args->>'provider_id')::uuid; v_id bigint;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'admit' then
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if not exists (select 1 from pipeline.uni_adapters u where u.provider_id = v_pid and u.enabled) then raise exception 'save the adapter switched on first'; end if;
    update pipeline.uni_adapters set admit = coalesce((p_args->>'admit')::boolean, false), admit_reason = v_reason, admit_changed_at = now() where provider_id = v_pid;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_admit', v_pid::text, jsonb_build_object('admit', p_args->'admit', 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  elsif p_action = 'request' then
    if length(btrim(coalesce(p_args->>'request', ''))) < 4 then raise exception 'write the improvement you want'; end if;
    if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
    insert into pipeline.uni_adapter_requests(provider_id, request, requested_by) values (v_pid, btrim(p_args->>'request'), auth.uid()) returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_request', v_pid::text, jsonb_build_object('request_id', v_id, 'request', p_args->>'request'), auth.uid());
    return jsonb_build_object('ok', true, 'id', v_id);
  elsif p_action = 'answer' then
    if p_args->>'status' not in ('done', 'declined', 'open') then raise exception 'status must be done, declined or open'; end if;
    update pipeline.uni_adapter_requests set status = p_args->>'status', answer = nullif(btrim(coalesce(p_args->>'answer', '')), ''), answered_at = now() where id = (p_args->>'id')::bigint;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_request_answer', p_args->>'id', jsonb_build_object('status', p_args->>'status', 'answer', p_args->>'answer'), auth.uid());
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $f$;
revoke all on function public.admin_uni_adapter_control(text, jsonb) from public, anon;
grant execute on function public.admin_uni_adapter_control(text, jsonb) to authenticated;
