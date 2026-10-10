CREATE OR REPLACE FUNCTION security.firecrawl_backlog_v1(p_use_case text)
 RETURNS TABLE(course_id uuid, provider_id uuid, country text, url text, input jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    from security.firecrawl_targets_fast() t
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
    from security.firecrawl_targets_fast() t
    join catalogue.courses c on c.provider_id = t.provider_id
    left join pipeline.coverage_course_pages pg on pg.course_id = c.id
    where t.included and t.domain is not null and c.lifecycle_status = 'active'
      and (pg.course_id is null or pg.status not in ('bound', 'ambiguous')
           or (pg.read_status = any(v_statuses) and pg.evidence_id is null and (pg.url !~* v_like or (v_skip is not null and pg.url ~* v_skip))))
      and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field = 'official_url')
      and (pg.read_status is not distinct from 'refused_host'
           or not exists (select 1 from pipeline.search_pass_links l where l.course_id = c.id and (l.state in ('found', 'verified') or (l.state = 'none' and not v_retry))));
  end if;
end $function$
