-- CF-247 (21 Oct 2026). Platform Admin 17:30: "Pick b, and proceed with task 2 and 3" (after the first automatic enrichment plans ran:
-- B = leave automatic plans at 10 an hour; task 2 = label automatic tasks, show plans that need a person, ease the search refresh).
--   1 Tasks an enrichment plan starts carry the plan in their args (plan_run, plan_mode) and say so in their reason, so Task manager shows
--     "Enrichment plan (automatic)" instead of only the Platform Admin the automatic steps run as. Tasks already running are labelled too.
--   2 pipeline.enrich_plan_runs.needs_person: when a plan finishes with a step that stopped, failed, timed out, was cancelled or skipped
--     (for example the adapter built but no field passed its check), or with an adapter ready to admit, the plan is still "done" but says
--     what a person has to do. security.enrich_plan_needs_person_v1 writes it; Layer 2/3 › Enrichment plan lists these first. Plans already
--     finished are filled in.
--   3 security.search_refresh_requested_v1: when every waiting request comes from an Enrich fields task or an enrichment plan, the full
--     search comparison (about 45 seconds while many values change) runs at most once every search.refresh_min_gap_minutes (30). Requests
--     from anything else (a correction, auto-publish) still go through on the next run.
-- Replaces: security.enrich_plan_tick_v1 (labels its tasks, writes needs_person); public.admin_enrich_plan (needs_person in overview and
--   list); security.search_refresh_requested_v1 (gap for plan and Enrich fields requests). All md5-guarded edits.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266): the search documents and how they are built are unchanged; only how
-- often the comparison runs for automatic requests.

do $guard$
declare v_expected jsonb := '{"security.enrich_plan_tick_v1(uuid)": "4fc5fce9b5e49765a136ca2dea10bfb9",
                              "public.admin_enrich_plan(text,jsonb)": "972f201bf06898280cf6b8f6648a0e9c",
                              "security.search_refresh_requested_v1()": "73215774ec2dad1bcb4bd0d8d3db7965"}'::jsonb;
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

-- Setting --------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'search.refresh_min_gap_minutes', 'Search refresh for automatic changes at most every',
  'When the only waiting refresh requests come from Enrich fields tasks or enrichment plans, the full search comparison runs at most this often. Requests from corrections or publishing are not held back.',
  'number', to_jsonb(30), 10, 240, 'minutes', 330, 'CF-247, Platform Admin 21 Oct 2026 17:30 "proceed with task 2" (database busier while plans run)', 'Website API', 'job search-refresh-requested')
on conflict do nothing;

-- 2 Plans that need a person -----------------------------------------------------------------------------------------------------------
alter table pipeline.enrich_plan_runs add column if not exists needs_person text;
comment on column pipeline.enrich_plan_runs.needs_person is 'CF-247 21 Oct 2026: what a person has to do after the plan finished (a step stopped, failed, timed out, was cancelled or skipped, or an adapter is ready to admit); null when nothing. Shown first on Layer 2/3 › Enrichment plan.';

create or replace function security.enrich_plan_needs_person_v1(p_run uuid)
 returns text
 language sql
 stable security definer
 set search_path to ''
as $function$
  select nullif(string_agg(z.m, '; ' order by z.o), '')
    from (
      select e.o, case
        when e.s->>'status' = 'stopped' and e.s->>'step' = 'adapter' then
          'Adapter: ' || case ob.stop_reason
            when 'nothing_ready' then 'built, but no field passed its check'
                 || coalesce(' (' || (select string_agg(k || ' ' || v, ', ' order by k) from jsonb_each_text(ob.result->'held') x(k, v)) || ')', '')
            when 'too_few_pages' then 'too few course pages found to build it'
            when 'no_website' then 'no website on record'
            when 'approve_central' then 'shared pages (fees, entry) waiting for approval'
            else 'stopped' || coalesce(' (' || ob.stop_reason || ')', '') end
        when e.s->>'status' in ('failed', 'cancelled', 'timed_out', 'skipped') then
          coalesce(e.s->>'label', e.s->>'step') || ': ' || replace(e.s->>'status', '_', ' ') || coalesce(', ' || nullif(e.s->>'note', ''), '')
        when e.s->>'status' = 'person' and exists (select 1 from pipeline.provider_onboarding o2 where o2.provider_id = r.provider_id and o2.status = 'waiting_admit') then
          'Adapter ready to admit (Layer 2/3 › Universities)'
        end m
        from pipeline.enrich_plan_runs r
        cross join lateral jsonb_array_elements(r.steps) with ordinality e(s, o)
        left join pipeline.provider_onboarding ob on e.s->'ref'->>'kind' = 'onboarding' and ob.id = nullif(e.s->'ref'->>'id', '')::uuid
       where r.id = p_run) z
   where z.m is not null
$function$;
revoke execute on function security.enrich_plan_needs_person_v1(uuid) from public, anon, authenticated;

-- 1 and 2: the runner labels its tasks and writes needs_person ----------------------------------------------------------------------------
select pg_temp.edit_once('security.enrich_plan_tick_v1(uuid)', '4fc5fce9b5e49765a136ca2dea10bfb9', array[
  [$o$      update pipeline.enrich_plan_runs set state = 'done', finished_at = now(), updated_at = now(), fields_after = security.enrich_provider_fields_v1(r.provider_id),$o$,
   $n$      update pipeline.enrich_plan_runs set state = 'done', finished_at = now(), updated_at = now(), fields_after = security.enrich_provider_fields_v1(r.provider_id),
             needs_person = security.enrich_plan_needs_person_v1(r.id),$n$],
  [$o$          v_ref := security.enrich_plan_start_step_v1(r.id, s->>'step');
          v_state := 'running'; v_started := v_started + 1;$o$,
   $n$          v_ref := security.enrich_plan_start_step_v1(r.id, s->>'step');
          v_state := 'running'; v_started := v_started + 1;
          -- v2.15.307: the task says it belongs to this plan (Task manager shows "Enrichment plan (automatic)")
          if v_ref->>'kind' = 'job' and nullif(v_ref->>'id', '') is not null then
            update pipeline.admin_jobs set args = args || jsonb_build_object('plan_run', r.id, 'plan_mode', r.mode),
                   reason = 'Enrichment plan (' || case r.mode when 'auto' then 'automatic' else 'Run now' end || '): ' || coalesce(reason, '')
             where id = (v_ref->>'id')::uuid;
          end if;$n$]]);

select pg_temp.edit_once('public.admin_enrich_plan(text,jsonb)', '972f201bf06898280cf6b8f6648a0e9c', array[
  [$o$      'unit_costs', security.enrich_unit_costs_v1(), 'can_run', v_rank >= 4, 'can_manage', v_rank >= 6);$o$,
   $n$      'needs_person', (select coalesce(jsonb_agg(jsonb_build_object('run', r.id, 'provider_id', r.provider_id, 'name', coalesce(p.display_name, p.canonical_name),
                                  'mode', r.mode, 'note', r.needs_person, 'finished_at', r.finished_at) order by r.finished_at desc), '[]'::jsonb)
                         from pipeline.enrich_plan_runs r join catalogue.providers p on p.id = r.provider_id
                        where r.state = 'done' and r.needs_person is not null
                          and not exists (select 1 from pipeline.enrich_plan_runs r2 where r2.provider_id = r.provider_id and r2.created_at > r.created_at)),
      'unit_costs', security.enrich_unit_costs_v1(), 'can_run', v_rank >= 4, 'can_manage', v_rank >= 6);$n$],
  [$o$'finished_at', r.finished_at,$o$, $n$'finished_at', r.finished_at, 'needs_person', r.needs_person,$n$]]);

-- 3 Search refresh: a gap for automatic requests ------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.search_refresh_requested_v1()', '73215774ec2dad1bcb4bd0d8d3db7965', array[
  [$o$  if v_ids is null then return jsonb_build_object('pending',0); end if;$o$,
   $n$  if v_ids is null then return jsonb_build_object('pending',0); end if;
  -- v2.15.307: requests from Enrich fields tasks and enrichment plans only: at most one full comparison every search.refresh_min_gap_minutes
  if not exists (select 1 from search.refresh_requests q where q.id = any(v_ids) and q.requested_by !~ '^(enrich fields task|enrichment plan) ')
     and exists (select 1 from search.refresh_requests q where q.processed_at > now() - make_interval(mins => security.pipeline_num_v1('search.refresh_min_gap_minutes', 30)::int)) then
    return jsonb_build_object('pending', cardinality(v_ids), 'held', 'automatic requests wait for the refresh gap');
  end if;$n$]]);

-- Backfill: tasks already started by plans, and plans already finished --------------------------------------------------------------------
update pipeline.admin_jobs j set args = j.args || jsonb_build_object('plan_run', x.run_id, 'plan_mode', x.mode),
       reason = 'Enrichment plan (' || case x.mode when 'auto' then 'automatic' else 'Run now' end || '): ' || coalesce(j.reason, '')
  from (select r.id run_id, r.mode, (e.s->'ref'->>'id')::uuid job_id
          from pipeline.enrich_plan_runs r cross join lateral jsonb_array_elements(r.steps) e(s)
         where e.s->'ref'->>'kind' = 'job' and nullif(e.s->'ref'->>'id', '') is not null) x
 where j.id = x.job_id and not (j.args ? 'plan_run');

update pipeline.enrich_plan_runs set needs_person = security.enrich_plan_needs_person_v1(id) where state = 'done' and needs_person is null;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.enrich_plan_needs_person_v1', 'Layer 2', 'What a person has to do after an enrichment plan finished', 'active', '20261021190000')
on conflict (kind, name) do nothing;
