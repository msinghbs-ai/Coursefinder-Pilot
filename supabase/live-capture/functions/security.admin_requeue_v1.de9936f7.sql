CREATE OR REPLACE FUNCTION security.admin_requeue_v1(p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_field text:=p_args->>'field'; v_reason text:=p_args->>'reason'; v_task text:=p_args->>'task'; v_n int:=0; v_tuition uuid; v_pin uuid; v_code text:=nullif(btrim(coalesce(p_args->>'profile','')),'');
begin
  if auth.uid() is null or security.current_role_rank()<5 then raise exception 'Platform Admin role required' using errcode='42501'; end if;
  if p_action='send_back' then
    if v_field not in ('course_intake','course_english','provider_current_tuition_validation') then raise exception 'unsupported field'; end if;
    select id into v_tuition from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused and retired_at is null
       and coalesce((quality_benchmark->>'pass')::boolean,false) order by updated_at desc limit 1;
    -- optional: one named Layer 3 model for these items (any model in the task's cascade, on or off; for tuition a qualified tuition model)
    if v_code is not null then
      if v_field='provider_current_tuition_validation' then
        select id into v_pin from pipeline.layer3_model_profiles where code=v_code and 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused
           and retired_at is null and coalesce((quality_benchmark->>'pass')::boolean,false);
        v_tuition:=v_pin;
      else
        select p.id into v_pin from pipeline.layer3_route_tiers t join pipeline.layer3_model_profiles p on p.id=t.profile_id
         where t.task_class=case v_field when 'course_intake' then 'provider_intake_validation' else 'provider_english_validation' end
           and p.code=v_code and p.enabled and not p.paused and p.retired_at is null;
      end if;
      if v_pin is null then raise exception 'choose a model from the list for this field'; end if;
    end if;
    with l4 as (
      update pipeline.layer4_review_items l set status='superseded', decided_at=now(),
             escalation_reason='Superseded: sent back to Layer 3 to be retried (Admin control).'
       where l.status='pending' and l.layer3_interpretation_id is not null and l.before_value is null and l.field_code=v_field
         and (v_reason is null or security.review_reason_key(l.escalation_reason)=v_reason)
      returning l.layer3_interpretation_id),
    fact as (
      update pipeline.layer3_work_items w set status='failed', updated_at=now(), last_error='released: sent back to Layer 3 (Admin control)'
        from l4 where v_field<>'provider_current_tuition_validation' and w.interpretation_id=l4.layer3_interpretation_id and w.status='layer4_required'
      returning w.id),
    hand as (update pipeline.layer3_fact_handoffs h set work_item_id=null, attempts=0, pinned_profile_id=v_pin from fact where h.work_item_id=fact.id returning h.id),
    tui as (
      update pipeline.layer3_work_items w set status='pending', profile_id=v_tuition, reserved_at=null, reserved_by=null, interpretation_id=null, available_at=now(), updated_at=now(),
             last_error='requeued: sent back to Layer 3 (Admin control)'
        from l4 where v_field='provider_current_tuition_validation' and v_tuition is not null and w.interpretation_id=l4.layer3_interpretation_id and w.status='layer4_required'
      returning w.id)
    select (select count(*) from l4) into v_n;
  elsif p_action='retry_failed' then
    if v_task in ('provider_intake_validation','provider_english_validation') then
      update pipeline.layer3_fact_handoffs h set attempts=0 where h.task_class=v_task and h.work_item_id is null and h.attempts>0;
      get diagnostics v_n = row_count;
    elsif v_task='provider_current_tuition_validation' then
      select id into v_tuition from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused and retired_at is null
         and coalesce((quality_benchmark->>'pass')::boolean,false) order by updated_at desc limit 1;
      update pipeline.layer3_work_items set status='pending', profile_id=v_tuition, reserved_at=null, reserved_by=null, interpretation_id=null, available_at=now(), updated_at=now(),
             last_error='requeued: retry failed (Admin control)'
       where task_class=v_task and status in ('failed','parked') and v_tuition is not null
         and security.tuition_chase_enabled((select c.provider_id from catalogue.courses c where c.id=entity_id));
      get diagnostics v_n = row_count;
    else raise exception 'unknown task'; end if;
  else raise exception 'unknown action'; end if;
  insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('requeue',p_action,coalesce(v_field,v_task),p_args||jsonb_build_object('moved',v_n),auth.uid());
  return security.admin_requeue_read_v1()||jsonb_build_object('moved',v_n);
end $function$
