-- CF-247 (22 Oct 2026). Platform Admin 18:26: "Why is the coverage sweep job failing". After the course search pick was fixed
-- (20261022028000) the backlog of 4,041 searches started draining and "svc_fc_spend: canceling statement due to statement timeout" came up
-- about twice every 5 minutes: every Firecrawl spend for a course search worked out the stopped-search list for every provider
-- (security.fc_search_stopped_v1, 0.5 to 2 seconds) under the spend lock, so a burst of searches queued past the 8-second limit.
-- Change: security.fc_search_stopped_for_v1(provider): the same three rules (too many searches with no page read in the window, the latest
-- title-search pages all wrong, held by the Platform Admin; each until Search again) for the one provider asked about. svc_fc_spend uses it.
-- Replaces: public.svc_fc_spend (stopped check for the one provider). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

create or replace function security.fc_search_stopped_for_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path = '' as $function$
  with w as (select greatest(now() - make_interval(days => security.fc_setting_num_v1('search_stop_window_days', 7)::int),
                             coalesce((select max(r.resumed_at) from pipeline.firecrawl_search_resumes r where r.provider_id = p_provider), '-infinity'::timestamptz)) since)
  select
    -- too many searches with no page read since (search_stop_after in search_stop_window_days)
    (select count(*) from pipeline.coverage_vendor_usage x, w
      where x.provider_id = p_provider and x.purpose = 'course_link_search' and x.at > w.since and x.at < now() - interval '1 hour')  -- fixed: searches still in flight are not counted
      >= security.fc_setting_num_v1('search_stop_after', 30)
    and not exists (select 1 from pipeline.coverage_course_pages pg, w where pg.provider_id = p_provider and pg.read_at > w.since and pg.status = 'bound' and pg.read_status = 'read')
  or
    -- the latest search.wrong_in_row_stop title-search pages that were read were all the wrong page
    coalesce((select count(*) >= security.pipeline_num_v1('search.wrong_in_row_stop', 20)::int and count(*) filter (where y.status = 'bound' and y.read_status = 'read') = 0
                from (select pg.status, pg.read_status from pipeline.coverage_course_pages pg, w
                       where pg.provider_id = p_provider and pg.basis = 'title_search' and pg.read_at is not null and pg.bound_at > w.since
                       order by pg.bound_at desc limit security.pipeline_num_v1('search.wrong_in_row_stop', 20)::int) y), false)
  or
    -- held by the Platform Admin for an adapter check
    exists (select 1 from pipeline.firecrawl_search_holds h where h.provider_id = p_provider
             and not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = h.provider_id and r.resumed_at > h.held_at))
$function$;
comment on function security.fc_search_stopped_for_v1(uuid) is 'CF-247 22 Oct 2026: security.fc_search_stopped_v1 for one provider (used by every course-search spend).';
revoke all on function security.fc_search_stopped_for_v1(uuid) from public;

do $edit$
declare v_def text := pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure);
        v_old text := 'exists (select 1 from security.fc_search_stopped_v1() s where s.provider_id = p_provider_id)';
begin
  if md5(v_def) <> 'db2f642b7a70400bd62452ec282913ff' then raise exception 'live public.svc_fc_spend differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'stopped check must occur exactly once'; end if;
  execute replace(v_def, v_old, 'security.fc_search_stopped_for_v1(p_provider_id)');
end $edit$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.fc_search_stopped_for_v1', 'Layer 2', 'Course search stopped, for one provider (Firecrawl spend check)', 'active', '{}', '20261022030000')
on conflict (kind, name) do nothing;
