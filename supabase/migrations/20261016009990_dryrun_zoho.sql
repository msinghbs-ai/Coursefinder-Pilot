-- CF-247 (22 Oct 2026). Platform Admin 22:55 "Start on task 2. Remeber for university of Montreal its admission.montreal.ca" and 23:09
-- "Proceed with all steps, keep iterating through the gaps found and apply the fixes": courses from the university's own programme list.
-- Finding: the only Quebec course source (Quebec MES "university programmes >20 credits (non-degree)") holds no bachelor, master or
-- doctoral degree at all (686 certificates, 154 DESS, 100 minors, 55 majors, 3 Juris Doctor across 14 universities, every one inactive),
-- so Université de Montréal, McGill, Laval, Concordia, UQAM and the rest show no degrees. The universities list them on their own sites.
-- 1 pipeline.programme_sources: a university's programme site map or list page and the address pattern of its programme pages (added
--   by a person, like a course list page). Worker mode programme_discover (job programme-discover) reads it and records each programme
--   page address in pipeline.programme_candidates.
-- 2 Worker mode programme_read (job programme-read) reads each programme page directly (the scraper only when blocked) for its heading;
--   the database maps the credential the heading names (Baccalauréat, Maîtrise, Doctorat, D.E.S.S., Microprogramme de 2e cycle,
--   Certificat, and the English names) to a study level with pipeline.credential_level_map. A heading naming no level is skipped.
-- 3 security.programme_create_v1 (job programme-create): a programme whose level is in the country's scope becomes a course, or is
--   matched to the university's existing course with the same page or the same title (which takes the level when it has none). New
--   courses are created INACTIVE and unpublished, with the programme page bound (basis programme_list) so the course page reader reads
--   fees, intakes and English from it.
-- 4 Activation is a separate, deliberate step (a passing check never switches anything on by itself): the country scope gate shows a
--   course whose page came from a programme list only when a person has approved that university's programme list
--   (public.admin_programme_lists 'approve', logged). md5-guarded edit to security.country_scope_gate_v1.
-- 5 pipeline.credential_level_map gains the French university credentials for Canada.
-- Replaces: nothing (security.country_scope_gate_v1 edited in place, md5-guarded)
-- Retires: nothing

-- settings ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.programme_discover', 'Programme lists read per run', 'Each run of the programme-discover job reads this many university programme site maps or list pages.', 'number', to_jsonb(4), 1, 20, 'lists', 910, 'CF-247 22 Oct 2026 (courses from the university''s own programme list)', 'Enrichment', 'job programme-discover; coverage-sweep programme_discover'),
 ('pipeline', 'batch.programme_read', 'Programme pages read per run', 'Each run of the programme-read job reads this many programme pages for their heading and credential.', 'number', to_jsonb(40), 1, 100, 'pages', 911, 'CF-247 22 Oct 2026 (courses from the university''s own programme list)', 'Enrichment', 'job programme-read; coverage-sweep programme_read'),
 ('pipeline', 'batch.programme_create', 'Programmes made into courses per run', 'Each run of the programme-create job creates or matches at most this many courses.', 'number', to_jsonb(500), 10, 5000, 'programmes', 912, 'CF-247 22 Oct 2026 (courses from the university''s own programme list)', 'Enrichment', 'security.programme_create_v1'),
 ('pipeline', 'programme.reread_days', 'Programme list read again after', 'A programme site map or list page is read again after this many days (new programmes are added; none is removed by this).', 'number', to_jsonb(30), 1, 365, 'days', 913, 'CF-247 22 Oct 2026 (courses from the university''s own programme list)', 'Enrichment', 'public.svc_programme_source_record'),
 ('pipeline', 'programme.max_urls', 'Programme pages kept per list', 'At most this many programme page addresses are kept from one site map or list page.', 'number', to_jsonb(3000), 50, 20000, 'pages', 914, 'CF-247 22 Oct 2026 (courses from the university''s own programme list)', 'Enrichment', 'public.svc_programme_source_next'),
 ('pipeline', 'programme.read_attempts', 'Programme page read attempts', 'A programme page that cannot be read is tried this many times.', 'number', to_jsonb(3), 1, 10, 'tries', 915, 'CF-247 22 Oct 2026 (courses from the university''s own programme list)', 'Enrichment', 'public.svc_programme_next')
on conflict do nothing;

-- 1 tables ---------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.programme_sources (
  id bigserial primary key,
  provider_id uuid not null references catalogue.providers(id),
  url text not null,
  kind text not null check (kind in ('sitemap', 'list')),
  url_pattern text not null,
  child_pattern text,
  status text not null default 'due' check (status in ('due', 'read', 'blocked', 'gone', 'failed', 'stopped')),
  http_status int, fetched_via text,
  found int, found_new int,
  read_at timestamptz, next_read_at timestamptz not null default now(), leased_until timestamptz,
  source_id uuid references pipeline.sources(id),
  approved_at timestamptz, approved_by uuid, approved_reason text,
  reason text not null, added_by uuid,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (provider_id, url)
);
comment on table pipeline.programme_sources is 'CF-247 22 Oct 2026: a university''s own programme site map (kind sitemap; child_pattern picks the files of a site map index) or list page (kind list), and the address pattern (url_pattern, JavaScript regular expression, case-insensitive) of its programme pages. approved_at: a person approved showing the courses made from it (the country scope gate waits for it).';

create table if not exists pipeline.programme_candidates (
  id bigserial primary key,
  provider_id uuid not null references catalogue.providers(id),
  programme_source_id bigint references pipeline.programme_sources(id),
  url text not null,
  link_title text,
  state text not null default 'found' check (state in ('found', 'read', 'failed', 'gone', 'created', 'matched', 'skipped')),
  heading text, page_title text, final_url text,
  study_level_code text references ref.study_levels(code),
  http_status int, fetched_via text,
  read_at timestamptz, read_attempts int not null default 0, next_read_at timestamptz not null default now(), leased_until timestamptz,
  course_id uuid references catalogue.courses(id),
  outcome text,
  found_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (provider_id, url)
);
create index if not exists programme_candidates_state_idx on pipeline.programme_candidates(state, next_read_at);
comment on table pipeline.programme_candidates is 'CF-247 22 Oct 2026: each programme page found on a university''s programme list, its heading and the study level the heading names, and what became of it (created: a new inactive course; matched: an existing course; skipped: no level or a level out of scope, in outcome).';

-- 5 French university credentials (Canada) ------------------------------------------------------------------------------------------
insert into pipeline.credential_level_map(country_code, sort, match_regex, study_level_code, note) values
 ('CA', 25, $r$dipl[ôo]me d.[ée]tudes sup[ée]rieures sp[ée]cialis|(^|[^a-z])d\.?\s?e\.?\s?s\.?\s?s\.?([^a-z]|$)$r$, 'graduate_diploma', 'Quebec D.E.S.S. (2nd cycle, 30 credits); 22 Oct 2026 programme lists'),
 ('CA', 35, $r$microprogramme\s+(de\s+)?(2e|3e|deuxi[eè]me|troisi[eè]me|cycles?\s+sup)$r$, 'graduate_certificate', 'Quebec microprogramme of the 2nd or 3rd cycle; a 1st-cycle microprogramme names no level'),
 ('CA', 55, $r$baccalaur[ée]at$r$, 'bachelor', 'Quebec baccalauréat'),
 ('CA', 65, $r$ma[îi]trise$r$, 'masters', 'Quebec maîtrise'),
 ('CA', 66, $r$doctorat|ph\.?\s?d([^a-z]|$)|doctor of$r$, 'doctorate', 'Doctorat, Ph. D., Doctor of'),
 ('CA', 85, $r$(^|[^a-z])certificat([^a-z]|$)$r$, 'certificate', 'Quebec university certificat (1st cycle, 30 credits)')
on conflict do nothing;

-- helpers ----------------------------------------------------------------------------------------------------------------------------
create or replace function security.programme_norm_v1(p text)
returns text language sql immutable set search_path = '' as $function$
  select btrim(regexp_replace(lower(translate(coalesce(p, ''), 'ÀÂÄÁÃÇÉÈÊËÎÏÍÌÔÖÓÒÛÜÚÙŸàâäáãçéèêëîïíìôöóòûüúùÿ’''', 'AAAAACEEEEIIIIOOOOUUUUYaaaaaceeeeiiiioooouuuuy  ')), '[^a-z0-9]+', ' ', 'g'))
$function$;
revoke all on function security.programme_norm_v1(text) from public, anon, authenticated;

create or replace function security.programme_provider_approved_v1(p_provider_id uuid)
returns boolean language sql stable security definer set search_path = '' as $function$
  select exists (select 1 from pipeline.programme_sources s where s.provider_id = p_provider_id and s.approved_at is not null)
$function$;
revoke all on function security.programme_provider_approved_v1(uuid) from public, anon, authenticated;

-- 1 discover -------------------------------------------------------------------------------------------------------------------------
create or replace function public.svc_programme_source_next(p_limit integer default 4)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (select s.id from pipeline.programme_sources s
                 where s.status <> 'stopped' and s.next_read_at <= now() and coalesce(s.leased_until, '-infinity') < now()
                 order by s.next_read_at limit greatest(1, least(coalesce(p_limit, 4), 20))  -- fixed: per-call safety cap; the run size is batch.programme_discover
                 for update skip locked),
       upd as (update pipeline.programme_sources s set leased_until = now() + interval '10 minutes', updated_at = now()  -- fixed: lease for one call
                 from pick where s.id = pick.id returning s.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'url', u.url, 'kind', u.kind, 'url_pattern', u.url_pattern,
           'child_pattern', u.child_pattern, 'max_urls', security.pipeline_num_v1('programme.max_urls', 3000)::int)), '[]'::jsonb) into v from upd u;
  return v;
end $function$;
revoke all on function public.svc_programme_source_next(integer) from public, anon, authenticated;
grant execute on function public.svc_programme_source_next(integer) to service_role;

create or replace function public.svc_programme_source_record(p_id bigint, p_status text, p_http integer, p_via text, p_urls jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_s pipeline.programme_sources; v_found int := 0; v_new int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_s from pipeline.programme_sources where id = p_id;
  if v_s.id is null then return jsonb_build_object('error', 'unknown source'); end if;
  if p_status = 'read' and jsonb_typeof(p_urls) = 'array' then
    with u as (select distinct on (x->>'url') x->>'url' url, nullif(left(x->>'title', 300), '') title
                 from jsonb_array_elements(p_urls) x where x->>'url' ~* '^https?://' and x->>'url' ~* v_s.url_pattern),
         ins as (insert into pipeline.programme_candidates(provider_id, programme_source_id, url, link_title)
                 select v_s.provider_id, v_s.id, u.url, u.title from u on conflict (provider_id, url) do nothing returning 1)
    select (select count(*) from u), (select count(*) from ins) into v_found, v_new;
  end if;
  update pipeline.programme_sources set status = case when p_status in ('read', 'blocked', 'gone') then p_status else 'failed' end,
         http_status = p_http, fetched_via = p_via, found = case when p_status = 'read' then v_found else found end,
         found_new = case when p_status = 'read' then v_new else found_new end, read_at = now(), leased_until = null, updated_at = now(),
         next_read_at = now() + make_interval(days => case when p_status = 'read' then security.pipeline_num_v1('programme.reread_days', 30)::int else 1 end)  -- fixed: a failed read is tried the next day
   where id = p_id;
  return jsonb_build_object('found', v_found, 'new', v_new);
end $function$;
revoke all on function public.svc_programme_source_record(bigint, text, integer, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_programme_source_record(bigint, text, integer, text, jsonb) to service_role;

-- 2 read -----------------------------------------------------------------------------------------------------------------------------
create or replace function public.svc_programme_next(p_limit integer default 40)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v jsonb; v_max int := security.pipeline_num_v1('programme.read_attempts', 3)::int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (select c.id from pipeline.programme_candidates c
                 where c.state in ('found', 'failed') and c.read_attempts < v_max and c.next_read_at <= now() and coalesce(c.leased_until, '-infinity') < now()
                 order by c.state = 'failed', c.found_at limit greatest(1, least(coalesce(p_limit, 40), 100))  -- fixed: per-call safety cap; the run size is batch.programme_read
                 for update skip locked),
       upd as (update pipeline.programme_candidates c set leased_until = now() + interval '10 minutes', read_attempts = c.read_attempts + 1, updated_at = now()  -- fixed: lease for one call
                 from pick where c.id = pick.id returning c.id, c.provider_id, c.url)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'url', u.url)), '[]'::jsonb) into v from upd u;
  return v;
end $function$;
revoke all on function public.svc_programme_next(integer) from public, anon, authenticated;
grant execute on function public.svc_programme_next(integer) to service_role;

create or replace function public.svc_programme_record(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_c pipeline.programme_candidates; v_country text; v_heading text; v_title text; v_level text; v_status text := coalesce(p_result->>'status', 'failed');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_c from pipeline.programme_candidates where id = p_id;
  if v_c.id is null then return jsonb_build_object('error', 'unknown candidate'); end if;
  v_country := security.coverage_country(v_c.provider_id);
  v_heading := nullif(btrim(replace(left(p_result->>'heading', 300), chr(0), '')), '');
  v_title := nullif(btrim(replace(left(coalesce(p_result->>'og_title', p_result->>'title'), 300), chr(0), '')), '');
  if v_status in ('read', 'too_thin') and coalesce(v_heading, v_title) is not null then
    v_level := coalesce(security.credential_level_v1(v_country, v_heading), security.credential_level_v1(v_country, v_title));
    update pipeline.programme_candidates set state = 'read', heading = coalesce(v_heading, v_title), page_title = v_title, final_url = p_result->>'final_url',
           study_level_code = v_level, http_status = (p_result->>'http')::int, fetched_via = p_result->>'via', read_at = now(), leased_until = null, updated_at = now(),
           outcome = case when v_level is null then 'no_level' end
     where id = p_id;
  else
    update pipeline.programme_candidates set state = case when v_status = 'gone' then 'gone' else 'failed' end, http_status = (p_result->>'http')::int,
           fetched_via = p_result->>'via', read_at = now(), leased_until = null, updated_at = now(), outcome = v_status,
           next_read_at = now() + interval '1 day'  -- fixed: a failed page is tried again the next day
     where id = p_id;
  end if;
  return jsonb_build_object('level', v_level);
end $function$;
revoke all on function public.svc_programme_record(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.svc_programme_record(bigint, jsonb) to service_role;

-- 3 create or match ------------------------------------------------------------------------------------------------------------------
create or replace function security.programme_create_v1(p_apply boolean default true, p_provider_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' set statement_timeout to '120s' as $function$
declare
  v_cap int := security.pipeline_num_v1('batch.programme_create', 500)::int;
  v_family uuid := (select f.id from pim.attribute_families f where f.entity_type = 'course' and f.status = 'active' order by case when f.code = 'course_default' then 0 else 1 end limit 1);
  r record; v_course uuid; v_key text; v_src uuid; v_created int := 0; v_matched int := 0; v_skipped int := 0; v_n int := 0;
begin
  for r in
    select c.*, security.coverage_country(c.provider_id) cc, p.display_name pname, sl.id level_id,
           exists (select 1 from pipeline.country_scope_levels s where s.country_code = security.coverage_country(c.provider_id) and s.study_level_code = c.study_level_code) in_scope
      from pipeline.programme_candidates c
      join catalogue.providers p on p.id = c.provider_id
      left join ref.study_levels sl on sl.code = c.study_level_code
     where c.state = 'read' and (p_provider_id is null or c.provider_id = p_provider_id)
     order by c.provider_id, c.id
     limit v_cap
  loop
    v_n := v_n + 1;
    if r.study_level_code is null or not r.in_scope then
      if p_apply then update pipeline.programme_candidates set state = 'skipped', outcome = case when r.study_level_code is null then 'no_level' else 'level_out_of_scope' end, updated_at = now() where id = r.id; end if;
      v_skipped := v_skipped + 1; continue;
    end if;
    -- the university's existing course with this page, or with the same title
    select co.id into v_course from catalogue.courses co
      left join pipeline.coverage_course_pages pg on pg.course_id = co.id
     where co.provider_id = r.provider_id
       and (rtrim(pg.url, '/') = rtrim(r.url, '/') or rtrim(co.course_url, '/') = rtrim(r.url, '/')
            or security.programme_norm_v1(co.canonical_title) = security.programme_norm_v1(r.heading))
     order by (rtrim(pg.url, '/') = rtrim(r.url, '/')) desc nulls last, (co.lifecycle_status = 'active') desc, co.created_at
     limit 1;
    if v_course is not null then
      if p_apply then
        update catalogue.courses co set study_level_id = r.level_id, updated_at = now()
         where co.id = v_course and co.study_level_id is null
           and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = co.id and l.field = 'study_level_id');
        insert into pipeline.coverage_course_pages(course_id, provider_id, url, score, basis, status, identity_basis, next_read_at)
        values (v_course, r.provider_id, r.url, 1, 'programme_list', 'bound', 'exact_title', now())
        on conflict (course_id) do update set url = excluded.url, score = 1, basis = 'programme_list', status = 'bound', bound_at = now(), read_attempts = 0, next_read_at = now()
         where pipeline.coverage_course_pages.status <> 'bound';
        update pipeline.programme_candidates set state = 'matched', course_id = v_course, outcome = 'existing_course', updated_at = now() where id = r.id;
      end if;
      v_matched := v_matched + 1; continue;
    end if;
    if p_apply then
      select s.source_id into v_src from pipeline.programme_sources s where s.id = r.programme_source_id;
      if v_src is null then
        insert into pipeline.sources(source_type, provider_id, url, label, trust_rank, metadata)
        values ('institutional_catalogue', r.provider_id, (select s.url from pipeline.programme_sources s where s.id = r.programme_source_id),
                r.pname || ' programme list (university''s own site)', 50,
                jsonb_build_object('layer', '1', 'country', r.cc, 'coverage_role', 'first_party_programme_list', 'course_identity_scheme', 'programme_page_url', 'introduced', '20261022043000'))
        returning id into v_src;
        update pipeline.programme_sources set source_id = v_src where id = r.programme_source_id;
      end if;
      v_key := 'course:' || lower(r.cc) || ':programme_list:' || r.provider_id::text || ':' || md5(rtrim(r.url, '/'));
      insert into pim.entity_registry(entity_type, stable_key, family_id) values ('course', v_key, v_family)
      on conflict (stable_key) do nothing returning id into v_course;
      if v_course is null then v_skipped := v_skipped + 1; continue; end if;
      insert into catalogue.courses(id, stable_key, provider_id, canonical_title, display_title, course_url, study_level_id, lifecycle_status, publication_status, canonical_source_id, last_verified_at)
      values (v_course, v_key, r.provider_id, r.heading, r.heading, r.url, r.level_id, 'inactive', 'unpublished', v_src, now());
      insert into pipeline.coverage_course_pages(course_id, provider_id, url, score, basis, status, identity_basis, next_read_at)
      values (v_course, r.provider_id, r.url, 1, 'programme_list', 'bound', 'exact_title', now());
      update pipeline.programme_candidates set state = 'created', course_id = v_course, outcome = 'new_course', updated_at = now() where id = r.id;
    end if;
    v_created := v_created + 1;
  end loop;
  if p_apply and v_n > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail)
    values ('programme_lists', 'create', coalesce(p_provider_id::text, 'all'), jsonb_build_object('created', v_created, 'matched', v_matched, 'skipped', v_skipped, 'note', 'created inactive; shown only after the programme list is approved'));
  end if;
  return jsonb_build_object('looked_at', v_n, 'created', v_created, 'matched', v_matched, 'skipped', v_skipped, 'applied', p_apply);
end $function$;
revoke all on function security.programme_create_v1(boolean, uuid) from public, anon, authenticated;

-- 4 approval, and the scope gate waits for it ----------------------------------------------------------------------------------------
do $do$
declare v_def text := pg_get_functiondef('security.country_scope_gate_v1'::regproc);
  v_old text := $o$join pipeline.coverage_course_pages pg on pg.course_id = c.id and pg.read_status = 'read' and pg.status = 'bound' and pg.read_at > now() - v_fresh$o$;
  v_new text := $n$join pipeline.coverage_course_pages pg on pg.course_id = c.id and pg.read_status = 'read' and pg.status = 'bound' and pg.read_at > now() - v_fresh
                     and (pg.basis is distinct from 'programme_list' or security.programme_provider_approved_v1(c.provider_id))  -- 22 Oct 2026: a programme list course waits for a person's approval$n$;
begin
  if md5(v_def) <> 'f9cbbac000ea0dca8cf967d77cbbd9cc' then raise exception 'security.country_scope_gate_v1 is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'gate: expected one show join'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

create or replace function public.admin_programme_lists(p_action text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_rank int := security.current_role_rank(); v_pid uuid; v_reason text; v_n int;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action = 'list' then
    return jsonb_build_object('sources', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'provider_id', s.provider_id, 'provider', p.display_name, 'url', s.url, 'kind', s.kind,
              'status', s.status, 'read_at', s.read_at, 'found', s.found, 'approved_at', s.approved_at, 'approved_reason', s.approved_reason,
              'states', (select coalesce(jsonb_object_agg(z.state, z.n), '{}'::jsonb) from (select c.state, count(*) n from pipeline.programme_candidates c where c.programme_source_id = s.id group by 1) z),
              'levels', (select coalesce(jsonb_object_agg(z.l, z.n), '{}'::jsonb) from (select coalesce(c.study_level_code, 'none') l, count(*) n from pipeline.programme_candidates c where c.programme_source_id = s.id and c.state in ('created', 'matched') group by 1) z))
              order by p.display_name), '[]'::jsonb)
           from pipeline.programme_sources s join catalogue.providers p on p.id = s.provider_id));
  elsif p_action = 'approve' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    v_pid := (p_args->>'provider_id')::uuid; v_reason := nullif(btrim(p_args->>'reason'), '');
    if v_pid is null or v_reason is null then raise exception 'provider_id and reason required'; end if;
    update pipeline.programme_sources set approved_at = now(), approved_by = auth.uid(), approved_reason = v_reason, updated_at = now() where provider_id = v_pid and approved_at is null;
    get diagnostics v_n = row_count;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('programme_lists', 'approve', v_pid::text, jsonb_build_object('sources', v_n, 'reason', v_reason), auth.uid());
    return jsonb_build_object('approved', v_n);
  end if;
  raise exception 'unknown action %', p_action;
end $function$;
revoke all on function public.admin_programme_lists(text, jsonb) from public, anon;
grant execute on function public.admin_programme_lists(text, jsonb) to authenticated;

-- jobs -------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.queue_watch(key, label, area, purpose, jobnames, tools, pending_sql, progress_sql, done_sql, failed_sql, exhausted_sql, exhausted_label, fix_at, sort) values
('programme_read', 'Programme pages from university lists', 'Enrichment', 'Reads each programme page found on a university''s own programme list for its heading and credential.',
 '{programme-discover,programme-read}', '{}',
 $q$select count(*) from pipeline.programme_candidates where state in ('found', 'failed') and read_attempts < security.pipeline_num_v1('programme.read_attempts', 3)::int$q$,
 $q$select max(read_at) from pipeline.programme_candidates$q$,
 $q$select count(*) from pipeline.programme_candidates where read_at >= $1 and state not in ('failed', 'found')$q$,
 $q$select count(*) from pipeline.programme_candidates where read_at >= $1 and state = 'failed'$q$,
 $q$select count(*) from pipeline.programme_candidates where state = 'failed' and read_attempts >= security.pipeline_num_v1('programme.read_attempts', 3)::int$q$,
 'Programme pages that could not be read', '#layer-2-discovery?tab=operations', 160)
on conflict (key) do nothing;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('programme-discover', 'Enrichment', 52, 'Programme lists', 'Every 30 minutes while a list is due: reads each university''s own programme site map or list page (pipeline.programme_sources) and records its programme page addresses. Read again after programme.reread_days. Run size batch.programme_discover.', 4, true, 'pages'),
 ('programme-read', 'Enrichment', 53, 'Programme pages', 'Every 10 minutes while pages wait: reads each programme page found on a programme list for its heading; the credential it names gives the study level (pipeline.credential_level_map). Run size batch.programme_read.', 4, true, 'pages'),
 ('programme-create', 'Enrichment', 54, 'Courses from programme lists', 'Hourly: a programme whose level is in the country''s scope becomes an inactive, unpublished course with its page bound (or is matched to the university''s existing course). Shown only after a person approves the university''s programme list. Run size batch.programme_create.', 4, true, null)
on conflict (jobname) do nothing;

select cron.schedule('programme-discover', '12-59/30 * * * *',
  $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'programme_discover', 'limit', security.pipeline_num_v1('batch.programme_discover', 4)::int)) where exists (select 1 from pipeline.programme_sources s where s.status <> 'stopped' and s.next_read_at <= now())$c$);
select cron.schedule('programme-read', '8-59/10 * * * *',
  $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'programme_read', 'limit', security.pipeline_num_v1('batch.programme_read', 40)::int)) where exists (select 1 from pipeline.queue_watch_state s where s.key = 'programme_read' and s.pending > 0) or not exists (select 1 from pipeline.queue_watch_state s where s.key = 'programme_read')$c$);
select cron.schedule('programme-create', '44 * * * *', $c$select security.programme_create_v1(true, null) where exists (select 1 from pipeline.programme_candidates c where c.state = 'read')$c$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.programme_sources', 'Layer 1', 'University programme site maps and list pages', 'active', '{}', '20261022043000'),
 ('table', 'pipeline.programme_candidates', 'Layer 1', 'Programme pages found on university lists and what became of them', 'active', '{}', '20261022043000'),
 ('function', 'public.svc_programme_source_next', 'Layer 1', 'Programme lists due for reading', 'active', '{}', '20261022043000'),
 ('function', 'public.svc_programme_source_record', 'Layer 1', 'Records the programme pages a list gave', 'active', '{}', '20261022043000'),
 ('function', 'public.svc_programme_next', 'Layer 1', 'Programme pages due for reading', 'active', '{}', '20261022043000'),
 ('function', 'public.svc_programme_record', 'Layer 1', 'Records a programme page heading and its level', 'active', '{}', '20261022043000'),
 ('function', 'security.programme_create_v1', 'Layer 1', 'Creates inactive courses from programme lists, or matches existing ones', 'active', '{}', '20261022043000'),
 ('function', 'security.programme_provider_approved_v1', 'Layer 1', 'Whether a person approved a university''s programme list', 'active', '{}', '20261022043000'),
 ('function', 'security.programme_norm_v1', 'Layer 1', 'Title comparison form (accents and punctuation removed)', 'active', '{}', '20261022043000'),
 ('function', 'public.admin_programme_lists', 'Platform', 'Programme lists: list and approve', 'active', '{}', '20261022043000'),
 ('job', 'programme-discover', 'Layer 1', 'Reads university programme lists', 'active', '{}', '20261022043000'),
 ('job', 'programme-read', 'Layer 1', 'Reads programme pages for heading and level', 'active', '{}', '20261022043000'),
 ('job', 'programme-create', 'Layer 1', 'Courses from programme lists (inactive until approved)', 'active', '{}', '20261022043000')
on conflict (kind, name) do nothing;

-- first source: Université de Montréal (Platform Admin 22:55: programme pages are on admission.umontreal.ca)
insert into pipeline.programme_sources(provider_id, url, kind, url_pattern, child_pattern, reason)
select p.id, 'https://admission.umontreal.ca/sitemap.xml', 'sitemap', '^https://admission\.umontreal\.ca/programmes/[a-z0-9-]+/?$', 'sitemap=programmes',
       'Platform Admin 22 Oct 2026 22:55: Université de Montréal programmes are on admission.umontreal.ca'
  from catalogue.providers p where p.id = '788d79de-d55b-435a-b649-06203f9d6b76'
on conflict (provider_id, url) do nothing;

select 'programme lists ready' ok;
do $dry$ begin raise exception 'DRYRUN OK %', (select detail from pipeline.admin_control_events where area='course_intakes' order by id desc limit 1); end $dry$;
