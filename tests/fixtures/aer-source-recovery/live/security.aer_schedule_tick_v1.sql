CREATE OR REPLACE FUNCTION security.aer_schedule_tick_v1(p_preview boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_batch int := security.pipeline_num_v1('batch.aer_schedule_courses', 20)::int;
        v_daymax int := security.pipeline_num_v1('aer.schedule_daily_max', 200)::int;
        v_heldmax int := security.pipeline_num_v1('batch.aer_schedule_held', 10)::int;
        v_l4max int := security.pipeline_num_v1('aer.schedule_layer4_max', 600)::int;
        v_mxmax int := security.pipeline_num_v1('batch.aer_schedule_matrix', 4)::int;
        v_cost numeric := security.course_entry_cost_v1(); v_owner uuid; v_used int; v_l4 int; v_prog int; v_bp boolean; v_room int;
        v_ai text; v_aim text; v_bal numeric; v_floor numeric; v_why text; v_reason text; v_orank int; v_orole text;
        r record; v_job uuid; v_res jsonb; v_held jsonb := '[]'::jsonb; v_new jsonb := '[]'::jsonb; v_mx jsonb := '[]'::jsonb; v_skip jsonb := '[]'::jsonb;
        v_checked jsonb := '[]'::jsonb; v_nh int := 0; v_nn int := 0; v_nm int := 0; v_fc int := 0; v_est numeric;
        v_fair boolean := security.pipeline_num_v1('wc.aer_fair_on', 0) >= 1; v_rr jsonb; v_tech jsonb;
begin
  if not p_preview and not pg_try_advisory_xact_lock(hashtext('cf247:aer-scheduled-read')) then  -- fixed: one run at a time
    return jsonb_build_object('skipped', 'another run is in progress');
  end if;
  -- run-as (mandate 13:09 D6: only the identity and role permissions the platform already defines): the job runs as the database role cron uses,
  -- through these security-definer functions; each read is asked in the name of the owner of the platform's standing enrichment
  -- (pipeline.field_gap_queue_control.owner, Coverage › Attributes, Fill the gaps; the same owner the gap queue and enrichment plans use), and only
  -- while that owner holds an active, unexpired role at the rank Read next batch requires (admin_aer course_batch). Nothing is granted here.
  select c.owner into v_owner from pipeline.field_gap_queue_control c where c.id = 1;
  select ro.rank, ro.code into v_orank, v_orole from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ur.user_id = v_owner and (ur.expires_at is null or ur.expires_at > now()) and ro.status = 'active' order by ro.rank desc limit 1;
  select coalesce(sum(x.course_reads + x.corrections), 0) into v_used from pipeline.aer_schedule_runs x
   where x.ran_at > now() - interval '1 day';  -- fixed: the daily cap is counted over the last 24 hours
  select count(*) into v_l4 from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run');
  select count(*) into v_prog from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  v_bp := v_l4 + v_prog >= v_l4max;
  -- 4 Nov 2026 (SS-021 F4, IQ-00128; wc.aer_fair_on): the same limit (aer.schedule_layer4_max, never raised or bypassed) counts distinct
  -- review-ready decisions and distinct reads in progress (security.work_review_room_v1, category aer); technically held and duplicate items
  -- are recorded for bounded technical recovery below, not counted
  if v_fair then
    v_rr := security.work_review_room_v1('aer');
    v_bp := coalesce((v_rr->>'room')::numeric, 0) <= 0;
  end if;
  v_room := greatest(0, least(v_batch, v_daymax - v_used));
  v_ai := security.ai_use_refusal_v1('enrich_fields');
  v_aim := security.ai_use_refusal_v1('entry_matrix');
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  v_why := case when v_owner is null then 'no owner to run as (Coverage › Attributes, Fill the gaps)'
                when coalesce(v_orank, 0) < 6 then 'the owner it runs as does not hold the Platform Admin role that Read next batch requires'  -- fixed: the rank admin_aer course_batch requires
                when v_ai is not null then 'AI reading is stopped (AI limits): ' || v_ai
                when v_room = 0 and v_daymax <= v_used then 'the daily cap is reached'
                when v_room = 0 then 'no course reads a run'
                when v_bal is not null and v_bal - v_room * v_cost < v_floor then 'the estimate would take the OpenRouter balance below its floor (Toolsets & limits)' end;

  if v_why is null then
    -- (b) held reads first, through D-R2: they replace the waiting item, so they also run under back-pressure
    for r in select * from security.aer_schedule_held_v1(least(v_heldmax, v_room)) loop
      v_checked := v_checked || jsonb_build_object('item_id', r.item_id, 'outcome', r.outcome);
      continue when not r.eligible;
      if p_preview then
        v_held := v_held || jsonb_build_object('item_id', r.item_id, 'course_id', r.course_id, 'provider_id', r.provider_id, 'country', r.country); v_nh := v_nh + 1;
        continue;
      end if;
      begin
        v_res := security.course_entry_correction_v1(r.item_id, v_owner,
                   'Scheduled entry reading (job aer-scheduled-read): the waiting read dropped printed requirements that no row covers; read again from the same stored page');
        v_held := v_held || jsonb_build_object('item_id', r.item_id, 'course_id', r.course_id, 'provider_id', r.provider_id, 'country', r.country, 'job_id', v_res->>'job_id');
        v_nh := v_nh + 1;
      exception when others then
        v_skip := v_skip || jsonb_build_object('item_id', r.item_id, 'why', left(sqlerrm, 300));
      end;
    end loop;
    -- (a) new course reads by eligibility rules, unless Layer 4 is full
    if not v_bp and v_room - v_nh > 0 then
      -- 4 Nov 2026 (SS-021 F4, wc.aer_fair_on): university by university within its share and the new-university reserve (security.aer_fair_courses_v1)
      for r in select * from security.aer_schedule_courses_v1((v_room - v_nh) * 2) where not v_fair  -- fixed: twice the room, so courses the item gate holds can be passed over
               union all select * from security.aer_fair_courses_v1(v_room - v_nh) where v_fair loop
        exit when v_nn >= v_room - v_nh;
        if security.enrich_item_held_v1(r.course_id, 'entry_requirements') then
          v_skip := v_skip || jsonb_build_object('course_id', r.course_id, 'why', 'held by the item gate'); continue;
        end if;
        if p_preview then
          v_new := v_new || jsonb_build_object('course_id', r.course_id, 'provider_id', r.provider_id, 'provider', r.provider_name, 'country', r.country); v_nn := v_nn + 1;
          continue;
        end if;
        begin
          v_job := security.course_entry_read_enqueue_v1(r.course_id, v_owner,
                     'Scheduled entry reading (job aer-scheduled-read): eligible course with no entry requirement held');
          v_new := v_new || jsonb_build_object('course_id', r.course_id, 'provider_id', r.provider_id, 'provider', r.provider_name, 'country', r.country, 'job_id', v_job);
          v_nn := v_nn + 1;
          if v_fair then
            perform security.work_item_report_v1('aer', r.course_id::text, 'entry_read', 'claimed', jsonb_build_object('provider_id', r.provider_id, 'field', 'entry_requirements', 'owner', 'aer-scheduled-read'));
            perform security.work_item_report_v1('aer', r.course_id::text, 'entry_read', 'succeeded', jsonb_build_object('provider_id', r.provider_id, 'field', 'entry_requirements', 'outcome', 'succeeded_with_result'));
          end if;
        exception when others then
          v_skip := v_skip || jsonb_build_object('course_id', r.course_id, 'why', left(sqlerrm, 300));
        end;
      end loop;
    end if;
  end if;

  -- (c) due entry pages fetched again (own lane and guard), unless Layer 4 is full
  -- 4 Nov 2026 (SS-021 F4, wc.aer_fair_on): a refresh is gated by the count only when its university has a matrix item waiting (a refresh that
  -- could raise or duplicate a review item); other due refreshes go ahead within batch.aer_schedule_matrix and the AI guard
  if (not v_bp or v_fair) and v_aim is null and v_mxmax > 0 then
    for r in select s.id, s.provider_id, s.read_via from pipeline.entry_matrix_sources s
              where s.status = 'read' and s.read_via <> 'stored'
                and (not v_bp or not exists (select 1 from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'entry_matrix_first_run'
                                                                                          and i.entity_id = s.provider_id))
                and s.read_at < now() - make_interval(days => security.pipeline_num_v1('entry.matrix_refresh_days', 30)::int)
                and security.entry_matrix_enabled_v1(s.provider_id)
              order by s.read_at, s.id limit v_mxmax loop
      if not p_preview then
        update pipeline.entry_matrix_sources f set status = 'found', attempts = 0, updated_at = now() where f.id = r.id and f.status = 'read';
      end if;
      v_mx := v_mx || jsonb_build_object('source_id', r.id, 'provider_id', r.provider_id, 'read_via', r.read_via);
      v_nm := v_nm + 1;
      if r.read_via = 'firecrawl' then v_fc := v_fc + 1; end if;
    end loop;
  end if;

  v_est := round((v_nh + v_nn) * v_cost, 4);
  -- 4 Nov 2026 (SS-021 F4): technically held and duplicate entry items are recorded for bounded technical recovery (records only; isolated)
  if not p_preview then
    begin
      v_tech := security.aer_technical_recovery_v1();
    exception when others then v_tech := jsonb_build_object('error', left(sqlerrm, 200));
    end;
  end if;
  if not p_preview then
    insert into pipeline.aer_schedule_checks(item_id, checked_at, outcome)
    select (c->>'item_id')::uuid, now(), c->>'outcome' from jsonb_array_elements(v_checked) c
    on conflict (item_id) do update set checked_at = excluded.checked_at, outcome = excluded.outcome;
    insert into pipeline.aer_schedule_runs(course_reads, corrections, matrix_pages, layer4_waiting, in_progress, back_pressure, used_before, room, refusal, estimate_usd, detail)
    values (v_nn, v_nh, v_nm, v_l4, v_prog, v_bp, v_used, v_room, v_why, v_est,
            jsonb_build_object('held', v_held, 'new', v_new, 'matrix', v_mx, 'skipped', v_skip, 'checked', jsonb_array_length(v_checked),
                               'fair', v_fair, 'room_ready', v_rr, 'technical', v_tech));
  end if;
  return jsonb_build_object('preview', p_preview, 'course_reads', v_nn, 'corrections', v_nh, 'matrix_pages', v_nm, 'firecrawl_credits_estimate', v_fc,
    'estimate_usd', v_est, 'cost_per_course_usd', round(v_cost, 5), 'layer4_waiting', v_l4, 'in_progress', v_prog, 'layer4_max', v_l4max, 'back_pressure', v_bp,
    'used_24h', v_used, 'daily_max', v_daymax, 'room', v_room, 'refusal', v_why, 'matrix_refusal', case when v_aim is not null then 'AI reading is stopped (AI limits): ' || v_aim end,
    'balance_usd', v_bal, 'floor_usd', v_floor, 'runs_as', jsonb_build_object('owner', v_owner, 'role', v_orole, 'rank', v_orank, 'source', 'pipeline.field_gap_queue_control.owner'),
    'checked', v_checked, 'held', v_held, 'new', v_new, 'matrix', v_mx, 'skipped', v_skip)
    || jsonb_build_object('fair', v_fair, 'room_ready', v_rr, 'technical', v_tech);
end $function$
