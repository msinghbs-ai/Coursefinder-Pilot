CREATE OR REPLACE FUNCTION security.firecrawl_panel_refresh_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n int;
begin
  with c as (
    select t.provider_id, jsonb_build_object('courses', count(*),
           'confirmed', count(*) filter (where pg.status = 'bound' and pg.read_status = 'read' and pg.identity_basis is not null),
           'unreadable', count(*) filter (where pg.status in ('bound', 'ambiguous') and pg.read_status in ('needs_render', 'blocked', 'fetch_failed', 'too_thin', 'robots_disallowed')),
           'no_page', count(*) filter (where pg.course_id is null or pg.status not in ('bound', 'ambiguous')),
           'adapter_confirmed', count(*) filter (where pg.read_status = 'read' and pg.identity_basis in ('adapter_code', 'adapter_title')),
           'waiting_read', count(*) filter (where pg.status = 'bound' and (pg.read_status is null or pg.read_status = 'needs_render')),
           'intakes', count(*) filter (where exists (select 1 from catalogue.course_intakes i where i.course_id = cc.id and coalesce(i.status, 'active') = 'active')),
           'english', count(*) filter (where exists (select 1 from catalogue.course_english_requirements e where e.course_id = cc.id and coalesce(e.status, 'active') = 'active')),
           'any_fee', count(*) filter (where exists (select 1 from catalogue.course_fees f where f.course_id = cc.id and coalesce(f.audience, '') ~* 'int'))) s
    from pipeline.firecrawl_target_cache t join catalogue.courses cc on cc.provider_id = t.provider_id and cc.lifecycle_status = 'active'
    left join pipeline.coverage_course_pages pg on pg.course_id = cc.id
    where t.name is not null
    group by t.provider_id
  )
  update pipeline.firecrawl_target_cache t set stats = c.s, stats_at = now() from c where c.provider_id = t.provider_id;
  get diagnostics n = row_count;
  insert into pipeline.firecrawl_panel_figures(id, backlog, refreshed_at)
    values (1, jsonb_build_object('read_page', (select count(*) from security.firecrawl_backlog_v1('read_page')), 'find_page', (select count(*) from security.firecrawl_backlog_v1('find_page'))), now())
  on conflict (id) do update set backlog = excluded.backlog, refreshed_at = now() where pipeline.firecrawl_panel_figures.id = 1;
  return n;
end $function$
