create or replace function public.admin_layer1_schedule(p_source_id uuid, p_schedule text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_days int; v_auto boolean; v_before jsonb; v_after jsonb;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select case p_schedule when 'daily' then 1 when 'weekly' then 7 when 'monthly' then 30 when 'quarterly' then 91 when 'yearly' then 365 when 'manual' then 30 end,
         p_schedule <> 'manual' into v_days, v_auto;
  if v_days is null then raise exception 'schedule must be daily, weekly, monthly, quarterly, yearly or manual'; end if;
  select jsonb_build_object('verification_cadence_days', verification_cadence_days, 'ingestion_cadence_days', ingestion_cadence_days, 'auto_ingest', auto_ingest)
    into v_before from pipeline.layer1_source_operations where source_id = p_source_id for update;
  if v_before is null then raise exception 'not a Layer 1 source'; end if;
  update pipeline.layer1_source_operations
     set verification_cadence_days = v_days, ingestion_cadence_days = case when p_schedule = 'manual' then ingestion_cadence_days else v_days end,
         auto_ingest = v_auto, next_verification_at = least(coalesce(next_verification_at, now() + make_interval(days => v_days)), now() + make_interval(days => v_days)),
         change_reason = left(p_reason, 500), updated_by = auth.uid(), updated_at = now()
   where source_id = p_source_id
  returning jsonb_build_object('verification_cadence_days', verification_cadence_days, 'ingestion_cadence_days', ingestion_cadence_days, 'auto_ingest', auto_ingest) into v_after;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'layer1_schedule_set', p_source_id::text, jsonb_build_object('schedule', p_schedule, 'before', v_before, 'after', v_after, 'reason', left(p_reason, 500)), auth.uid());
  return jsonb_build_object('ok', true, 'schedule', p_schedule) || v_after;
end $f$;
