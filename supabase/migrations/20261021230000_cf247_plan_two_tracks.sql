-- CF-247 (21 Oct 2026). Platform Admin 18:36: "Lets speed up course data for each provider, [Firecrawl] as a separate parallel job?"
-- Choice: "Two tracks + more credits" (two parallel tracks, New Zealand first, plus larger daily Firecrawl shares and more plans an hour).
--   1 Two tracks per plan: Fill missing fields (stored pages and AI) no longer waits behind the website, course-page, adapter and
--     scholarship steps; job enrich-plan-run starts the next step of each track on every run. Before this, a plan reached the fields
--     step only after its adapter step, and an adapter that stopped held the fields back for hours.
--   2 New Zealand first: automatic plans take providers in the countries in plans.priority_countries (["NZ"]) first, then most missing
--     values, then world ranking.
--   3 More credits and plans (Firecrawl billing period ends 2 Nov 2026 with 366,796 of 500,000 credits left on 21 Oct, about 30,000 a day;
--     on 21 Oct course-page search used its whole 6,000 share and the rest used under 100):
--     firecrawl.daily_budget_total 15,000 -> 25,000; daily_share_course_search 6,000 -> 13,000; daily_share_reads 3,000 -> 5,000;
--     daily_share_central 1,500 -> 2,500 (scholarships 3,500 and other 1,000 unchanged; shares sum to 25,000);
--     plans.auto_per_run 10 -> 20; plans.auto_open_max 20 -> 40. Each change is logged with the reason and can be changed back on
--     Models & services › Toolsets & limits and Settings › Pipeline settings.
-- Replaces: security.enrich_plan_tick_v1 (one step at a time -> one step per track); security.enrich_plan_auto_v1 (priority countries)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
declare v_expected jsonb := '{"security.enrich_plan_tick_v1(uuid)": "c279a72edf76e97bd305b029aca3ca41",
                              "security.enrich_plan_auto_v1()": "805329f3d360029c68c32b2c7afa094e"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
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

-- 2 Priority countries ---------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'plans.priority_countries', 'Automatic enrichment plans: countries first',
  'Country codes (AU, NZ, CA) whose providers automatic plans take first; then most missing values, then world ranking. Empty: no country first.',
  'list', '["NZ"]'::jsonb, null, null, 'countries', 124, 'CF-247, Platform Admin 21 Oct 2026 18:36 "Two tracks + more credits" (NZ first)', 'Onboarding', 'job enrich-plan-auto')
on conflict (toolset_key, key) do nothing;

-- 3 More credits and plans (logged) --------------------------------------------------------------------------------------------------
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'settings', 'change', s.toolset_key || '.' || s.key,
       jsonb_build_object('from', s.value, 'to', v.val, 'reason', 'CF-247, Platform Admin 21 Oct 2026 18:36 "Two tracks + more credits"'), null
  from pipeline.platform_toolset_settings s
  join (values ('firecrawl', 'daily_budget_total', 25000), ('firecrawl', 'daily_share_course_search', 13000), ('firecrawl', 'daily_share_reads', 5000),
               ('firecrawl', 'daily_share_central', 2500), ('pipeline', 'plans.auto_per_run', 20), ('pipeline', 'plans.auto_open_max', 40)) v(tk, k, val)
    on v.tk = s.toolset_key and v.k = s.key
 where (s.value #>> '{}')::numeric < v.val;

update pipeline.platform_toolset_settings s set value = to_jsonb(v.val),
       reason = 'CF-247, Platform Admin 21 Oct 2026 18:36 "Two tracks + more credits"'
  from (values ('firecrawl', 'daily_budget_total', 25000), ('firecrawl', 'daily_share_course_search', 13000), ('firecrawl', 'daily_share_reads', 5000),
               ('firecrawl', 'daily_share_central', 2500), ('pipeline', 'plans.auto_per_run', 20), ('pipeline', 'plans.auto_open_max', 40)) v(tk, k, val)
 where v.tk = s.toolset_key and v.k = s.key and (s.value #>> '{}')::numeric < v.val;

-- 1 Two tracks ------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.enrich_plan_tick_v1(uuid)', 'c279a72edf76e97bd305b029aca3ca41', array[
  [$o$v_room numeric; v_note text;$o$, $n$v_room numeric; v_note text; v_track text;$n$],
  [$o$    i := (select min(o - 1) from jsonb_array_elements(r.steps) with ordinality e(x, o) where x->>'status' in ('pending', 'waiting', 'running'));
    if i is null then$o$,
   $n$    if not exists (select 1 from jsonb_array_elements(r.steps) x where x->>'status' in ('pending', 'waiting', 'running')) then$n$],
  [$o$      v_done := v_done + 1; continue;
    end if;
    s := r.steps->i;$o$,
   $n$      v_done := v_done + 1; continue;
    end if;
    -- v2.15.308 (Platform Admin 21 Oct 2026 "Two tracks + more credits"): Fill missing fields (stored pages and AI) runs on its own track,
    -- beside the website, course-page, adapter and scholarship steps; each run starts or checks the next step of each track.
    foreach v_track in array array['ai', 'fc'] loop
    i := (select min(o - 1) from jsonb_array_elements(r.steps) with ordinality e(x, o)
           where x->>'status' in ('pending', 'waiting', 'running') and case when x->>'step' = 'fields' then 'ai' else 'fc' end = v_track);
    continue when i is null;
    s := r.steps->i;$n$],
  [$o$      end if;
    end if;
  end loop;
  return jsonb_build_object('finished', v_done, 'started', v_started);$o$,
   $n$      end if;
    end if;
    end loop;  -- tracks
  end loop;
  return jsonb_build_object('finished', v_done, 'started', v_started);$n$]]);

select pg_temp.edit_once('security.enrich_plan_auto_v1()', '805329f3d360029c68c32b2c7afa094e', array[
  [$o$            order by x.missing desc, x.best_rank nulls last limit v_room * 3 loop$o$,
   $n$            order by (x.country in (select jsonb_array_elements_text(coalesce(s.value, '[]'::jsonb)) from pipeline.platform_toolset_settings s
                                     where s.toolset_key = 'pipeline' and s.key = 'plans.priority_countries')) desc,
                     x.missing desc, x.best_rank nulls last limit v_room * 3 loop$n$]]);
