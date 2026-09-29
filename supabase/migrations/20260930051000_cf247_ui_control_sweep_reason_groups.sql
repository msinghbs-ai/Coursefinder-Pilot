-- CF-247 UI control sweep, fix 1: "Send back to AI" grouped Layer 4 items by their exact reason, and each reason quotes its
-- own amount, so 296 items showed as 111 groups. Group by the reason with amounts and numbers replaced ([amount], [n]):
-- 14 groups. send_back's optional reason now matches that grouped reason. Replaces the two functions only if they are
-- still exactly as 20260930050000 left them (md5 of the function body).

create or replace function security.review_reason_key(p_reason text) returns text language sql immutable as $f$
  select regexp_replace(regexp_replace(coalesce(p_reason,''),'(A\$|AUD\s?\$?|\$)\s?[0-9][0-9,]*(\.[0-9]+)?','[amount]','g'),'\m[0-9][0-9,\.]*\M','[n]','g')
$f$;

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid='security.admin_requeue_read_v1()'::regprocedure)<>'3eb0b56824f911f29298e5755e179adc'
     or (select md5(prosrc) from pg_proc where oid='security.admin_requeue_v1(text,jsonb)'::regprocedure)<>'a2ab1e60e12e9960daf916ede0646a3f' then
    raise exception 'cf247_ui_control_sweep_fix1: the requeue functions changed since 20260930050000; review before replacing';
  end if;
end $g$;

create or replace function security.admin_requeue_read_v1()
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','pipeline','security' as $f$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return jsonb_build_object('can_control',security.current_role_rank()>=5,
    'groups',(select coalesce(jsonb_agg(jsonb_build_object('field',g.field_code,'reason',g.reason,'items',g.n,'oldest',g.oldest) order by g.n desc),'[]'::jsonb)
      from (select l.field_code, security.review_reason_key(l.escalation_reason) reason, count(*) n, min(l.created_at) oldest from pipeline.layer4_review_items l
             where l.status='pending' and l.layer3_interpretation_id is not null and l.before_value is null
               and l.field_code in ('course_intake','course_english','provider_current_tuition_validation') group by 1,2) g),
    'stays_with_person',(select jsonb_object_agg(field_code,n) from (select field_code,count(*) n from pipeline.layer4_review_items where status='pending' and (layer3_interpretation_id is null or before_value is not null) group by 1) x),
    'layer3_failed',(select jsonb_object_agg(task_class,n) from (select task_class,count(*) n from pipeline.layer3_work_items where status in ('failed','parked') group by 1) y),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='requeue' order by created_at desc limit 10) e));
end $f$;
revoke all on function security.admin_requeue_read_v1() from public, anon;
grant execute on function security.admin_requeue_read_v1() to authenticated;
create or replace function public.admin_requeue_read() returns jsonb language sql stable security invoker as $f$ select security.admin_requeue_read_v1() $f$;
revoke all on function public.admin_requeue_read() from public, anon;
grant execute on function public.admin_requeue_read() to authenticated;

create or replace function security.admin_requeue_v1(p_action text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v_field text:=p_args->>'field'; v_reason text:=p_args->>'reason'; v_task text:=p_args->>'task'; v_n int:=0; v_tuition uuid;
begin
  if auth.uid() is null or security.current_role_rank()<5 then raise exception 'Platform Admin role required' using errcode='42501'; end if;
  if p_action='send_back' then
    if v_field not in ('course_intake','course_english','provider_current_tuition_validation') then raise exception 'unsupported field'; end if;
    select id into v_tuition from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused and retired_at is null
       and coalesce((quality_benchmark->>'pass')::boolean,false) order by updated_at desc limit 1;
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
    hand as (update pipeline.layer3_fact_handoffs h set work_item_id=null, attempts=0 from fact where h.work_item_id=fact.id returning h.id),
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
       where task_class=v_task and status in ('failed','parked') and v_tuition is not null;
      get diagnostics v_n = row_count;
    else raise exception 'unknown task'; end if;
  else raise exception 'unknown action'; end if;
  insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('requeue',p_action,coalesce(v_field,v_task),p_args||jsonb_build_object('moved',v_n),auth.uid());
  return security.admin_requeue_read_v1()||jsonb_build_object('moved',v_n);
end $f$;
revoke all on function security.admin_requeue_v1(text,jsonb) from public, anon;
grant execute on function security.admin_requeue_v1(text,jsonb) to authenticated;
create or replace function public.admin_requeue(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb language sql volatile security invoker as $f$ select security.admin_requeue_v1(p_action,coalesce(p_args,'{}'::jsonb)) $f$;
revoke all on function public.admin_requeue(text,jsonb) from public, anon;
grant execute on function public.admin_requeue(text,jsonb) to authenticated;
