-- CF-247 (20 Oct 2026). D11 second step. Platform Admin 21:29: "proceed with task 1" (move the readers off the 24 retiring tables); then,
-- on the cross-check, choice "Drop the 9, keep the 15 (Recommended)":
--   The 9 tables nothing needs any more stop being read here; a paste file exports and drops them with 31 dead functions:
--     pipeline.layer2_scale_qualification_items, layer2_provider_trial_results, layer2_scale_qualification_runs (Layer 2 scale trials,
--     2026-09), coverage_identity_results (page identity benchmark), layer3_quality_benchmark_runs (Layer 3 benchmarks), layer2_tuning_events,
--     scholarship_ai_runs and scholarship_ai_settings (the old scholarship AI pipeline, never run), pim_source_candidates (manual candidates,
--     never used; its panel leaves the Layer 4 drawer in v2.15.302).
--   The 15 that hold something still in use go back to active (D11 reversed for them): the Layer 3 holdout tables (the qualification
--     record of the pinned models), the AI key audit trail, the scholarship job list, ETL schedules and source qualification (Layer 2/3 ›
--     Scholarships), the Scholarships › Coverage "mark checked" table, the Canadian register course-scope keys, and six empty
--     workflow tables that 18 live screens still read.
-- Edits (each md5-guarded against the live definition; nothing else in each function changes):
--   security.retention_estimate_v1 / retention_tick_v1: the retired Layer 2 category no longer lists the two trial tables.
--   security.layer2_wave_parent_stamp: a wave request is its own parent (no scale qualification runs to look up).
--   security.admin_running_now_v1: no "Page identity checks" AI line.
--   security.platform_health_check_v1: OpenRouter 24-hour spend without the retired benchmark and scholarship AI runs; their two
--     ceiling checks removed. security.platform_resource_observe_v1: AI calls and cost from the hourly totals only.
--   security.admin_platform_health_cf221: active scholarship AI runs 0. public.admin_scholarship_layer_read: Layer 3 'ai' list empty.
--   security.admin_layer2_dispatcher_tuning_read_v1: no recent tuning list. security.scholarship_ai_control_read_impl: answers that the old
--     scholarship AI pipeline is retired (nothing calls it; the shared admin read still names it).
-- Replaces: the nine functions above (only the lines named)
-- Retires: nothing new (the 9 tables were marked retiring on 20 Oct; the drop is a paste file)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

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

select pg_temp.edit_once('security.retention_estimate_v1(text)', '67188cf89e76c7b48725cfdb7982bb0d', array[
  array[$x$unnest(array['pipeline.layer2_provider_trial_results', 'pipeline.layer2_course_discovery_candidates', 'pipeline.layer2_provider_attempts',
                        'pipeline.layer2_scale_qualification_items']) t;$x$,
        $x$unnest(array['pipeline.layer2_course_discovery_candidates', 'pipeline.layer2_provider_attempts']) t;$x$],
  array[$x$v_rows := (select count(*) from pipeline.layer2_provider_trial_results) + (select count(*) from pipeline.layer2_course_discovery_candidates)
            + (select count(*) from pipeline.layer2_provider_attempts) + (select count(*) from pipeline.layer2_scale_qualification_items);$x$,
        $x$v_rows := (select count(*) from pipeline.layer2_course_discovery_candidates) + (select count(*) from pipeline.layer2_provider_attempts);$x$],
  array[$x$'trial_results', (select count(*) from pipeline.layer2_provider_trial_results),$x$,
        $x$'trial_results', 0,$x$],
  array[$x$'scale_qualification_items', (select count(*) from pipeline.layer2_scale_qualification_items),$x$,
        $x$'scale_qualification_items', 0,$x$]
]);

select pg_temp.edit_once('security.retention_tick_v1()', 'f07532088b71cade49c48ddd2aa07943', array[
  array[$x$foreach v_t in array array['pipeline.layer2_provider_trial_results', 'pipeline.layer2_course_discovery_candidates', 'pipeline.layer2_provider_attempts',
                                 'pipeline.layer2_scale_qualification_items'] loop$x$,
        $x$foreach v_t in array array['pipeline.layer2_course_discovery_candidates', 'pipeline.layer2_provider_attempts'] loop$x$]
]);

select pg_temp.edit_once('security.layer2_wave_parent_stamp()', 'c68e64ae11399205dbaa25b54fa211ba', array[
  array[$x$  select q.id into v_terminal
  from pipeline.layer2_scale_qualification_runs q
  join ref.countries c on c.id=q.country_id
  where q.requested_by=new.requested_by
    and c.iso_alpha2::text=upper(new.country_code)
    and q.scope_type=new.scope_type
    and q.scope_id is not distinct from new.scope_id
    and q.status in('completed','partial')
    and coalesce((q.result_summary->>'auto_progress_scope')::boolean,false)
  order by
    case when not coalesce((q.result_summary->>'auto_progress_processed')::boolean,false) then 0 else 1 end,
    q.completed_at desc nulls last,q.created_at desc
  limit 1;
$x$,
        $x$  v_terminal := null;  -- CF-247 20 Oct 2026 (D11): Layer 2 scale qualification runs retired; a wave request is its own parent
$x$]
]);

select pg_temp.edit_once('security.admin_running_now_v1()', '420627ee07ef97a4dd34f6687b0c90a5', array[
  array[$x$
                 union all select 'Page identity checks', count(*), sum(coalesce(cost_usd, 0)) from pipeline.coverage_identity_results where created_at > now() - interval '15 minutes'$x$,
        $x$$x$]
]);

select pg_temp.edit_once('security.platform_health_check_v1(boolean)', 'a7efe398a915525bce8c926e10d367f7', array[
  array[$x$
           + coalesce((select sum(estimated_cost_usd) from pipeline.layer3_quality_benchmark_runs where created_at>=now()-interval '24 hours'),0)  -- fixed: health check observation window
           + coalesce((select sum(cost_usd) from pipeline.scholarship_ai_runs where created_at>=now()-interval '24 hours'),0) into v_num;  -- fixed: health check observation window$x$,
        $x$
           into v_num;  -- CF-247 20 Oct 2026 (D11): retired benchmark and scholarship AI run tables no longer counted$x$],
  array[$x$      for r in select p.code, count(*) n, max(b.estimated_cost_usd) mx, p.cost_ceiling_usd ceil
                 from pipeline.layer3_quality_benchmark_runs b join pipeline.layer3_model_profiles p on p.id=b.profile_id
                where b.created_at>=now()-interval '24 hours' and p.cost_ceiling_usd is not null and b.estimated_cost_usd>p.cost_ceiling_usd*greatest(coalesce(b.external_call_count,1),1)  -- fixed: health check observation window
                group by p.code, p.cost_ceiling_usd loop
        v_found:=v_found||security.platform_health_issue_v1('budgets:benchmark_ceiling:'||r.code,'warning','budgets',
          r.n||' benchmark run(s) on "'||r.code||'" cost more than the per-call ceiling allows in 24 hours',jsonb_build_object('profile',r.code,'runs',r.n,'max_cost_usd',r.mx,'ceiling_usd_per_call',r.ceil));
      end loop;
$x$,
        $x$$x$],
  array[$x$      for r in select s.country_code, s.daily_budget_usd, coalesce(sum(x.cost_usd),0) spent from pipeline.scholarship_ai_settings s
                 left join pipeline.scholarship_ai_runs x on x.country_code=s.country_code and x.created_at>=now()-interval '24 hours'  -- fixed: health check observation window
                group by s.country_code, s.daily_budget_usd having coalesce(sum(x.cost_usd),0)>s.daily_budget_usd loop
        v_found:=v_found||security.platform_health_issue_v1('budgets:scholarship_ai:'||r.country_code,'warning','budgets',
          'Scholarship AI spend for '||r.country_code||' is US$'||round(r.spent,2)||' in 24 hours, over its US$'||r.daily_budget_usd||' daily budget',jsonb_build_object('spent_usd',r.spent,'budget_usd',r.daily_budget_usd));
      end loop;
$x$,
        $x$$x$]
]);

select pg_temp.edit_once('security.platform_resource_observe_v1()', 'a35a7eb5678ab8dd35a2bb5f145e2a37', array[
  array[$x$
          union all select 1, coalesce(input_tokens,0)+coalesce(output_tokens,0), coalesce(estimated_cost_usd,0) from pipeline.layer3_quality_benchmark_runs where completed_at >= h0 and completed_at < h$x$,
        $x$$x$],
  array[$x$
          union all select estimated_cost_usd from pipeline.layer3_quality_benchmark_runs where completed_at >= m$x$,
        $x$$x$]
]);

select pg_temp.edit_once('security.admin_platform_health_cf221()', '36399f546eeb79ace7094147b48b36b9', array[
  array[$x$select count(*) into v_active_ai from pipeline.scholarship_ai_runs where status in ('queued','running');$x$,
        $x$v_active_ai := 0;  -- CF-247 20 Oct 2026 (D11): scholarship AI runs retired$x$]
]);

select pg_temp.edit_once('public.admin_scholarship_layer_read(integer)', '37fe14a21b72ced0be006b612c1b21d4', array[
  array[$x$'ai', (select coalesce(jsonb_agg(jsonb_build_object('country', a.country_code, 'enabled', a.enabled, 'state', a.metadata->>'state', 'profile', (select p.code from pipeline.layer3_model_profiles p where p.id = a.default_profile_id),
                 'task', a.default_task_class, 'budget_usd', a.daily_budget_usd, 'max_records', a.max_records_per_run, 'on_change', a.schedule_on_change,
                 'runs', (select count(*) from pipeline.scholarship_ai_runs r where r.country_code = a.country_code)) order by a.country_code), '[]'::jsonb) from pipeline.scholarship_ai_settings a),$x$,
        $x$'ai', '[]'::jsonb,  -- CF-247 20 Oct 2026 (D11): the old scholarship AI settings and runs are retired$x$]
]);

select pg_temp.edit_once('security.admin_layer2_dispatcher_tuning_read_v1(jsonb)', 'e24a23487618d5030de36bbd6d82a677', array[
  array[$x$'recent_tuning',(select coalesce(jsonb_agg(jsonb_build_object('created_at',e.created_at,'governance_reason',e.governance_reason,'changed_fields',e.changed_fields,'before_policy',e.before_policy,'after_policy',e.after_policy) order by e.created_at desc),'[]'::jsonb) from(select * from pipeline.layer2_tuning_events where profile_id=v_profile_id order by created_at desc limit 10)e)$x$,
        $x$'recent_tuning','[]'::jsonb$x$]
]);

do $chk$ begin
  if md5(pg_get_functiondef('security.scholarship_ai_control_read_impl(text)'::regprocedure)) <> '318173742e4f9e01cda533b459882f82' then
    raise exception 'live security.scholarship_ai_control_read_impl differs from the definition this change replaces';
  end if;
end $chk$;
create or replace function security.scholarship_ai_control_read_impl(p_country_code text default 'AU')
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- CF-247 20 Oct 2026 (D11): the old scholarship AI pipeline (settings, runs) is retired; scholarships are read on Models & services › AI
  select jsonb_build_object('country_code', upper(coalesce(nullif(p_country_code, ''), 'AU')), 'retired', true,
                            'note', 'The old scholarship AI pipeline is retired (20 Oct 2026). Scholarship extraction is on Models & services › AI.')
$function$;

update pipeline.component_register set status = 'active', retire_after = null, replaced_by = null, updated_at = now(),
       note = coalesce(note || '; ', '') || 'kept 20 Oct 2026 (D11 reversed for this table, Platform Admin "Drop the 9, keep the 15"): still in use'
 where kind = 'table' and status = 'retiring' and name in (
   'pipeline.layer3_holdout_cases', 'pipeline.layer3_holdout_results', 'pipeline.layer3_holdout_sets', 'pipeline.layer3_provider_credential_audit',
   'pipeline.scholarship_jobs', 'pipeline.scholarship_etl_schedules', 'pipeline.scholarship_source_qualifications', 'pipeline.scholarship_coverage_checks',
   'pipeline.ca_course_scope_keys', 'workflow.review_queue', 'workflow.review_actions', 'workflow.suggestions', 'workflow.export_jobs',
   'workflow.import_jobs', 'workflow.handover_events');
update pipeline.component_register set updated_at = now(),
       note = coalesce(note || '; ', '') || 'readers moved off 20 Oct 2026 (migration 20261020140000); drop by paste file'
 where kind = 'table' and status = 'retiring' and name in (
   'pipeline.layer2_scale_qualification_items', 'pipeline.layer2_provider_trial_results', 'pipeline.layer2_scale_qualification_runs',
   'pipeline.coverage_identity_results', 'pipeline.layer3_quality_benchmark_runs', 'pipeline.layer2_tuning_events',
   'pipeline.scholarship_ai_runs', 'pipeline.scholarship_ai_settings', 'pipeline.pim_source_candidates');
