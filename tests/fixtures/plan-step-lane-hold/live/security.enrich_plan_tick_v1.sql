CREATE OR REPLACE FUNCTION security.enrich_plan_tick_v1(p_run uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.enrich_plan_runs%rowtype; s jsonb; i int; v_ref jsonb; v_state text; v_done int := 0; v_started int := 0; v_room numeric; v_note text; v_track text;
        v_wait int := security.pipeline_num_v1('plans.step_wait_hours', 48)::int; v_max int := security.pipeline_num_v1('plans.step_max_hours', 24)::int;
begin
  for r in select * from pipeline.enrich_plan_runs where state in ('queued', 'running') and (p_run is null or id = p_run)
              and (mode <> 'auto' or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pipeline.enrich_plan_runs.provider_id))  -- 22 Oct 2026 (Platform Admin 11:42): automatic plans of unpublished providers wait; Run now plans carry on
            order by created_at for update skip locked loop
    if r.state = 'queued' then
      update pipeline.enrich_plan_runs set state = 'running', started_at = now(), updated_at = now(), fields_before = security.enrich_provider_fields_v1(r.provider_id) where id = r.id;
      r.state := 'running';
    end if;
    -- the first step not finished
    if not exists (select 1 from jsonb_array_elements(r.steps) x where x->>'status' in ('pending', 'waiting', 'running')) then
      update pipeline.enrich_plan_runs set state = 'done', finished_at = now(), updated_at = now(), fields_after = security.enrich_provider_fields_v1(r.provider_id),
             needs_person = security.enrich_plan_needs_person_v1(r.id),
             actual = jsonb_build_object(
               'credits', (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.provider_id = r.provider_id and x.at between r.started_at and now()),
               'credits_on_demand', (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.on_demand_run = r.id),
               'usd', round(coalesce((select sum(e.cost_usd) from pipeline.field_enrich_items e where e.provider_id = r.provider_id and e.updated_at between r.started_at and now()), 0)
                          + coalesce((select sum(d.cost_usd) from pipeline.uni_adapter_drafts d where d.provider_id = r.provider_id and d.created_at between r.started_at and now()), 0)
                          + coalesce((select sum(x.cost_usd) from pipeline.scholarship_ai_extractions x where x.provider_id = r.provider_id and x.at between r.started_at and now()), 0), 4))
       where id = r.id;
      insert into search.refresh_requests(requested_by) values ('enrichment plan ' || left(r.id::text, 8) || ' finished');
      v_done := v_done + 1; continue;
    end if;
    -- v2.15.308 (Platform Admin 21 Oct 2026 "Two tracks + more credits"): Fill missing fields (stored pages and AI) runs on its own track,
    -- beside the website, course-page, adapter and scholarship steps; each run starts or checks the next step of each track.
    foreach v_track in array array['ai', 'fc'] loop
    i := (select min(o - 1) from jsonb_array_elements(r.steps) with ordinality e(x, o)
           where x->>'status' in ('pending', 'waiting', 'running') and case when x->>'step' = 'fields' then 'ai' else 'fc' end = v_track);
    continue when i is null;
    s := r.steps->i;
    if s->>'status' in ('pending', 'waiting') then
      v_note := null;
      if (s->>'person')::boolean then
        v_state := 'person';  -- a person's step: shown, not waited for
      elsif (select x.state from pipeline.enrich_plan_runs x where x.id = r.id) not in ('queued', 'running') then
        v_state := 'cancelled'; v_note := 'the run is no longer open; the step was not started';  -- 3 Nov 2026 (P0 mandate 10:44 §3 Agent A)
      elsif nullif(s->>'blocked', '') is not null and exists (select 1 from catalogue.providers p where p.id = r.provider_id and nullif(btrim(p.website), '') is null) then
        v_state := 'skipped'; v_note := s->>'blocked';
      elsif r.mode = 'auto' and s->>'group' not in ('none') and coalesce((s->>'est_credits')::numeric, 0) > 0
            and security.fc_budget_left_v1(case s->>'group' when 'course_search' then 'course_link_search' when 'scholarships' then 'sch_scrape' when 'reads' then 'scrape' when 'central' then 'central_map' else 'other' end)
                < least((s->>'est_credits')::numeric, security.fc_setting_num_v1('daily_share_' || (s->>'group'), 0)) then
        -- automatic: wait for room in the toolset share
        v_state := case when coalesce((s->>'waiting_since')::timestamptz, now()) < now() - make_interval(hours => v_wait) then 'skipped' else 'waiting' end;
        v_note := case when v_state = 'skipped' then 'no room in the ' || (s->>'group') || ' share for ' || v_wait || ' hours' else 'waiting for room in the ' || (s->>'group') || ' share' end;
      else
        begin
          v_ref := security.enrich_plan_start_step_v1(r.id, s->>'step');
          v_state := 'running'; v_started := v_started + 1;
          -- v2.15.307: the task says it belongs to this plan (Task manager shows "Enrichment plan (automatic)")
          if v_ref->>'kind' = 'job' and nullif(v_ref->>'id', '') is not null then
            update pipeline.admin_jobs set args = args || jsonb_build_object('plan_run', r.id, 'plan_mode', r.mode),
                   reason = 'Enrichment plan (' || case r.mode when 'auto' then 'automatic' else 'Run now' end || '): ' || coalesce(reason, '')
             where id = (v_ref->>'id')::uuid;
          end if;
        exception when others then
          v_state := 'failed'; v_note := left(sqlerrm, 300);
        end;
      end if;
      update pipeline.enrich_plan_runs set updated_at = now(),
             steps = jsonb_set(steps, array[i::text], (steps->i) || jsonb_build_object('status', v_state, 'note', v_note)
                       || case when v_state = 'running' then jsonb_build_object('ref', v_ref, 'started_at', now()) else '{}'::jsonb end
                       || case when v_state = 'waiting' and not (steps->i ? 'waiting_since') then jsonb_build_object('waiting_since', now()) else '{}'::jsonb end
                       || case when v_state in ('person', 'skipped', 'failed') then jsonb_build_object('finished_at', now()) else '{}'::jsonb end)
       where id = r.id;
    elsif s->>'status' = 'running' then
      v_state := case
        when s->'ref'->>'kind' = 'job' then (select case when j.state in ('done') then 'done' when j.state in ('failed', 'cancelled') then j.state end
                                               from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid)
        when s->'ref'->>'kind' = 'onboarding' then (select case when o.status in ('waiting_admit', 'done', 'scholarships') then 'done' when o.status = 'stopped' then 'stopped' when o.status = 'cancelled' then 'cancelled' end
                                                      from pipeline.provider_onboarding o where o.id = (s->'ref'->>'id')::uuid) end;
      if v_state is null and (s->>'started_at')::timestamptz < now() - make_interval(hours => v_max) then v_state := 'timed_out'; end if;
      if v_state is not null then
        update pipeline.enrich_plan_runs set updated_at = now(),
               steps = jsonb_set(steps, array[i::text], (steps->i) || jsonb_build_object('status', v_state, 'finished_at', now(),
                         'note', case v_state when 'stopped' then 'onboarding stopped: ' || coalesce((select o.stop_reason from pipeline.provider_onboarding o where o.id = (s->'ref'->>'id')::uuid), '')
                                              when 'timed_out' then 'still running after ' || v_max || ' hours; the task carries on' end))
         where id = r.id;
      end if;
    end if;
    end loop;  -- tracks
  end loop;
  return jsonb_build_object('finished', v_done, 'started', v_started);
end $function$

