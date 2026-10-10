-- CF-247 Decision 253 (4 Oct 2026), after the first 39 pages of the Read pages pilot: most pages that could not be read
-- are not course pages (staff profiles, research archives, theses as PDFs of up to 174 pages at 1 credit a page). Read
-- pages now takes only addresses that look like course pages (a setting) and skips research archives, profiles and PDFs
-- (a setting). The other unreadable pages go to Find pages, which looks for the course's real page and may replace an
-- unreadable page that has never been read. A confirmed page or a link entered by hand is still never replaced.
-- No text value in this file contains a semicolon.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section) values
  ('firecrawl', 'read_url_pattern', 'What a course page address looks like', 'A pattern (regular expression, any case). Only pages whose address matches it are read. The others are sent to Find pages for a better page.', 'text', '"/(course|courses|program|programs|programme|programmes|qualification|qualifications|study|degree|degrees|handbook|undergraduate|postgraduate|majors?)|preview_program|calendar[.]"', null, null, null, 112, 'Decision 253 pilot', 'Read pages'),
  ('firecrawl', 'read_skip_url_pattern', 'Addresses never read', 'A pattern (regular expression, any case). Research archives, staff profiles and PDFs are not read (a PDF costs 1 credit a page).', 'text', '"[.]pdf($|[?])|/bitstreams?/|/handle/|researcharchive|research(ers|commons|online)|ourarchive|/esploro/|viewcontent|/profiles?/|//profiles[.]|//dro[.]|//researchers[.]"', null, null, null, 114, 'Decision 253 pilot', 'Read pages')
on conflict (toolset_key, key) do nothing;

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
      and not exists (select 1 from pipeline.search_pass_links l where l.course_id = c.id and (l.state in ('found', 'verified') or (l.state = 'none' and not v_retry)));
  end if;
end $f$;
revoke all on function security.firecrawl_backlog_v1(text) from public, anon, authenticated;

create or replace function public.svc_fc_find_bind(p_item_id uuid, p_candidates jsonb) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_i pipeline.firecrawl_run_items%rowtype; v_c jsonb := coalesce(p_candidates, '[]'::jsonb); v_url text; v_pg pipeline.coverage_course_pages%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_i from pipeline.firecrawl_run_items where id = p_item_id;
  if v_i.id is null or v_i.course_id is null then return 'no_course'; end if;
  if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) = 0 then return 'no_candidate'; end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = v_i.course_id and k.field = 'official_url') then return 'entered_by_hand'; end if;
  select * into v_pg from pipeline.coverage_course_pages where course_id = v_i.course_id;
  if v_pg.course_id is not null and v_pg.status in ('bound', 'ambiguous') and not (v_pg.evidence_id is null and v_pg.read_status in ('needs_render', 'blocked', 'fetch_failed', 'too_thin') and coalesce((v_i.input->>'refind')::boolean, false)) then return 'page_already_bound'; end if;
  v_url := v_c->>0;
  if v_pg.course_id is not null and v_pg.url = v_url then
    if jsonb_array_length(v_c) < 2 then return 'already_refused'; end if;
    v_url := v_c->>1;
  end if;
  insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason, run_id)
    values (v_i.course_id, v_i.provider_id, v_pg.url, v_url, case when coalesce((v_i.input->>'refind')::boolean, false) then 'firecrawl search: better page for an unreadable one' else 'firecrawl search: page found' end, v_i.run_id);
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
    values (v_i.course_id, v_i.provider_id, v_url, 'firecrawl_search', 'bound', now(), now(), 0)
  on conflict (course_id) do update set url = excluded.url, basis = excluded.basis, status = 'bound', bound_at = now(), score = null, runner_up = null, read_status = null, read_at = null, http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, candidates = null, leased_until = null, read_attempts = 0, next_read_at = now() where pipeline.coverage_course_pages.status not in ('bound', 'ambiguous') or (pipeline.coverage_course_pages.evidence_id is null and pipeline.coverage_course_pages.read_status in ('needs_render', 'blocked', 'fetch_failed', 'too_thin'));
  insert into pipeline.search_pass_links(course_id, provider_id, run_id, candidates, cand_idx, bound_url, refind, state, updated_at, engine)
    values (v_i.course_id, v_i.provider_id, v_i.run_id, v_c, case when v_url = v_c->>0 then 1 else 2 end, v_url, coalesce((v_i.input->>'refind')::boolean, false), 'found', now(), 'firecrawl')
  on conflict (course_id) do update set run_id = excluded.run_id, candidates = excluded.candidates, cand_idx = excluded.cand_idx, bound_url = excluded.bound_url, refind = excluded.refind, state = 'found', updated_at = now(), engine = 'firecrawl' where pipeline.search_pass_links.course_id = excluded.course_id;
  return 'bound';
end $f$;
revoke all on function public.svc_fc_find_bind(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_fc_find_bind(uuid, jsonb) to service_role;
