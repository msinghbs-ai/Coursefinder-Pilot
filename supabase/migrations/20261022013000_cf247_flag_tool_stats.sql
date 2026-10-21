-- CF-247 (22 Oct 2026). Platform Admin 08:12: "When we flag unis or courses for exhausting toolset reason like "Search is now off for 85 NZ
-- providers whose own sites list too few course pages." In ui will be helpful and intuitive."
-- A flag said what was decided ("No course page found after 2 AI attempt(s)") but not what had been tried and how it went. Each flag on
-- Layer 2/3 › Flags now carries the toolset used on that university or course before it was flagged, in the same terms as the daily
-- Toolset use sheet: times used, worked, did not work, credits and AI US$.
--   1 security.flag_tool_summary_v1(provider, course): for a provider, its totals from pipeline.toolset_use_daily (since the first
--     recorded day) and its site map (pages listed, course-like pages kept); for a course, its title searches, AI page match tries (and how
--     many chose the right page), its course page (how found, read or not) and its Enrich fields items.
--   2 public.admin_flags: list and events return it as tools (and the site map) with each flag. md5-guarded.
-- Replaces: public.admin_flags (list and events return the toolset used). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
begin
  if md5(pg_get_functiondef('public.admin_flags(text,jsonb)'::regprocedure)) <> '74fa8979402daf6caf1bc1cf2814e4a6' then
    raise exception 'live public.admin_flags differs from the definition this change replaces';
  end if;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

create index if not exists toolset_use_daily_provider on pipeline.toolset_use_daily(provider_id);

create or replace function security.flag_tool_summary_v1(p_provider uuid, p_course uuid default null)
 returns jsonb language sql stable security definer set search_path to ''
as $function$
  select case when p_course is null then
    jsonb_build_object(
      'scope', 'provider',
      'since', (select min(u.snapshot_date) from pipeline.toolset_use_daily u where u.provider_id = p_provider),
      'site_map', (select jsonb_build_object('status', d.status, 'pages', d.url_count, 'course_pages', d.kept_count, 'how', d.method)
                     from pipeline.coverage_provider_discovery d where d.provider_id = p_provider),
      'tools', coalesce((select jsonb_agg(jsonb_build_object('tool', z.tool, 'used', z.used, 'ok', z.ok, 'failed', z.failed, 'credits', z.credits, 'cost_usd', round(z.cost, 3))
                                          order by array_position(array['course_search','page_reads','ai_page_match','ai_field_reader','fee_reader','scholarship_ai','other_credits','flags_raised'], z.tool))
                           from (select u.tool, sum(u.used) used, sum(u.ok) ok, sum(u.failed) failed, sum(u.credits) credits, sum(u.cost_usd) cost
                                   from pipeline.toolset_use_daily u where u.provider_id = p_provider group by u.tool) z), '[]'::jsonb))
  else
    jsonb_build_object(
      'scope', 'course',
      'tools', (select coalesce(jsonb_agg(e), '[]'::jsonb) from jsonb_array_elements(jsonb_build_array(
        (select jsonb_build_object('tool', 'course_search', 'used', coalesce(s.attempts, 0), 'ok', case when s.state in ('found', 'verified') then 1 else 0 end,
                                   'failed', case when s.state = 'none' then 1 else 0 end, 'note', s.state)
           from pipeline.course_link_search s where s.course_id = p_course),
        (select jsonb_build_object('tool', 'ai_page_match', 'used', count(*),
                                   'ok', count(*) filter (where q.state = 'chosen' and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = q.course_id and g.url = q.chosen_url and g.status = 'bound' and g.read_status = 'read')),
                                   'failed', count(*) filter (where q.state in ('none', 'no_candidates', 'error')), 'cost_usd', round(coalesce(sum(q.cost_usd), 0), 4),
                                   'note', string_agg(distinct q.state, ', '))
           from pipeline.coverage_ai_match q where q.course_id = p_course having count(*) > 0),
        (select jsonb_build_object('tool', 'page_reads', 'used', g.read_attempts, 'ok', case when g.status = 'bound' and g.read_status = 'read' then 1 else 0 end,
                                   'failed', case when g.status = 'mismatch' or g.read_status in ('fetch_failed', 'blocked', 'needs_render', 'robots_disallowed') then 1 else 0 end,
                                   'note', g.basis || ' · ' || g.status || coalesce(' · ' || g.read_status, ''))
           from pipeline.coverage_course_pages g where g.course_id = p_course),
        (select jsonb_build_object('tool', 'ai_field_reader', 'used', count(*), 'ok', count(*) filter (where e.state = 'filled'),
                                   'failed', count(*) filter (where e.state in ('skipped', 'failed')), 'cost_usd', round(coalesce(sum(e.cost_usd), 0), 4))
           from pipeline.field_enrich_items e where e.course_id = p_course having count(*) > 0))) e where e <> 'null'::jsonb))
  end
$function$;
comment on function security.flag_tool_summary_v1(uuid, uuid) is 'CF-247 22 Oct 2026: the toolset used on a provider (from pipeline.toolset_use_daily, and its site map) or a course (searches, AI page match, page read, Enrich fields) before it was flagged; shown with each flag on Layer 2/3 › Flags.';
revoke all on function security.flag_tool_summary_v1(uuid, uuid) from public;

select pg_temp.edit_once('public.admin_flags(text,jsonb)', '74fa8979402daf6caf1bc1cf2814e4a6', array[
  [$o$'released_at', x.released_at, 'released_by', x.released_by, 'release_kind', x.release_kind, 'release_reason', x.release_reason) order by$o$,
   $n$'released_at', x.released_at, 'released_by', x.released_by, 'release_kind', x.release_kind, 'release_reason', x.release_reason,
        -- 22 Oct 2026 (Platform Admin 08:12): the toolset used before the flag
        'tools', case when x.entity in ('provider', 'course') and x.provider_id is not null
                      then security.flag_tool_summary_v1(x.provider_id, case when x.entity = 'course' and x.entity_key ~ '^[0-9a-f-]{36}$' then x.entity_key::uuid end) end) order by$n$],
  [$o$    return jsonb_build_object('flag', (select to_jsonb(f) from pipeline.enrichment_flags f where f.id = v_id),$o$,
   $n$    return jsonb_build_object('flag', (select to_jsonb(f) from pipeline.enrichment_flags f where f.id = v_id),
      'tools', (select security.flag_tool_summary_v1(f.provider_id, case when f.entity = 'course' and f.entity_key ~ '^[0-9a-f-]{36}$' then f.entity_key::uuid end)
                  from pipeline.enrichment_flags f where f.id = v_id and f.entity in ('provider', 'course') and f.provider_id is not null),$n$]]);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.flag_tool_summary_v1', 'Layer 2', 'Toolset used before a flag (Layer 2/3 › Flags)', 'active', '20261022013000')
on conflict (kind, name) do nothing;
