-- CF-247 Layer 3 without Sonnet, part 2 (Platform Admin, 30 Sep 2026 01:31 IST): "we should only pass it via layer 4 to
-- specific ai layer 3 model or edit at layer 4". Expensive models run only when a person sends Layer 4 items to them.
-- 1. pipeline.layer3_fact_handoffs.pinned_profile_id: a page sent back from Layer 4 to one named model.
-- 2. layer3_fact_claim_service hands the pinned model to the worker; layer3_fact_complete_ladder_service accepts the
--    pinned model's answer even when that model's cascade step is switched off (for example Claude Sonnet 4.6).
--    Both are edited in place from their live definitions (text replacement, checked), only if unchanged (md5).
-- 3. admin_requeue send_back takes an optional model ('profile' code): any model in the task's cascade, on or off, or
--    a qualified tuition model; admin_requeue_read lists the choices.

alter table pipeline.layer3_fact_handoffs add column if not exists pinned_profile_id uuid references pipeline.layer3_model_profiles(id);

do $g$
declare d text; n text;
begin
  if (select md5(prosrc) from pg_proc where oid='public.layer3_fact_claim_service(text,integer,text,text)'::regprocedure)<>'8e8733c8f2318d2614e1d77ad4b88400'
     or (select md5(prosrc) from pg_proc where oid='public.layer3_fact_complete_ladder_service(uuid,uuid,jsonb,jsonb)'::regprocedure)<>'f4f00fc0e7b957e9bd3d4b42c3fbb96d'
     or (select md5(prosrc) from pg_proc where oid='security.admin_requeue_v1(text,jsonb)'::regprocedure)<>'c4dcc9d359df86b056d9b3c95c81c069'
     or (select md5(prosrc) from pg_proc where oid='security.admin_requeue_read_v1()'::regprocedure)<>'d8dbce9d17164f6e6351cd372079bb08' then
    raise exception 'cf247_l3_pinned_model: a function changed since it was reviewed; review before replacing';
  end if;
  d:=pg_get_functiondef('public.layer3_fact_claim_service(text,integer,text,text)'::regprocedure);
  n:=replace(d,'co.course_code, h.id handoff_id','co.course_code, h.id handoff_id, h.pinned_profile_id');
  n:=replace(n,$s$'evidence_id',r.evidence_id,'url',r.url);$s$,$s$'evidence_id',r.evidence_id,'url',r.url,'pinned_profile_id',r.pinned_profile_id);$s$);
  if n=d or length(n)-length(d)<>length(', h.pinned_profile_id')+length($s$,'pinned_profile_id',r.pinned_profile_id$s$) then raise exception 'claim edit did not apply exactly'; end if;
  execute n;
  d:=pg_get_functiondef('public.layer3_fact_complete_ladder_service(uuid,uuid,jsonb,jsonb)'::regprocedure);
  n:=replace(d,E'v_disagree int;\nbegin',E'v_disagree int; v_pin uuid;\nbegin');
  n:=replace(n,E'select * into base from pipeline.layer3_interpretations where id=p_interpretation_id;\n',
               E'select * into base from pipeline.layer3_interpretations where id=p_interpretation_id;\n  select h.pinned_profile_id into v_pin from pipeline.layer3_fact_handoffs h where h.work_item_id=w.id limit 1;\n');
  n:=replace(n,'where t.task_class=w.task_class and t.active and t.profile_id=','where t.task_class=w.task_class and (t.active or t.profile_id=v_pin) and t.profile_id=');
  if (length(n)-length(replace(n,'(t.active or t.profile_id=v_pin)','')))/length('(t.active or t.profile_id=v_pin)')<>2 or position('v_pin uuid;' in n)=0
     or position('select h.pinned_profile_id into v_pin' in n)=0 then raise exception 'complete edit did not apply exactly'; end if;
  execute n;
end $g$;

create or replace function security.admin_requeue_v1(p_action text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
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
    'layer3_failed',(select jsonb_object_agg(task_class,n) from (select task_class,count(*) n from pipeline.layer3_work_items where status in ('failed','parked') and coalesce(last_error,'') not like 'released:%' group by 1) y),
    'layer3_waiting',(select jsonb_object_agg(task_class,n) from (select task_class,count(*) n from (
         select task_class from pipeline.layer3_fact_handoffs where work_item_id is null
         union all select task_class from pipeline.layer3_work_items where status='pending') z group by 1) y),
    'models',jsonb_build_object(
       'course_intake',(select coalesce(jsonb_agg(jsonb_build_object('profile',p.code,'model',p.model_identifier,'in_cascade',t.active,'cost_per_1000_usd',round(t.cost_per_call_usd*1000,2)) order by t.tier_no),'[]'::jsonb)
          from pipeline.layer3_route_tiers t join pipeline.layer3_model_profiles p on p.id=t.profile_id where t.task_class='provider_intake_validation' and p.enabled and not p.paused and p.retired_at is null),
       'course_english',(select coalesce(jsonb_agg(jsonb_build_object('profile',p.code,'model',p.model_identifier,'in_cascade',t.active,'cost_per_1000_usd',round(t.cost_per_call_usd*1000,2)) order by t.tier_no),'[]'::jsonb)
          from pipeline.layer3_route_tiers t join pipeline.layer3_model_profiles p on p.id=t.profile_id where t.task_class='provider_english_validation' and p.enabled and not p.paused and p.retired_at is null),
       'provider_current_tuition_validation',(select coalesce(jsonb_agg(jsonb_build_object('profile',p.code,'model',p.model_identifier,'in_cascade',true,'cost_per_1000_usd',null)),'[]'::jsonb)
          from pipeline.layer3_model_profiles p where 'provider_current_tuition_validation'=any(p.allowed_task_classes) and p.enabled and not p.paused and p.retired_at is null
           and coalesce((p.quality_benchmark->>'pass')::boolean,false))),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='requeue' order by created_at desc limit 10) e));
end $f$;
revoke all on function security.admin_requeue_read_v1() from public, anon;
grant execute on function security.admin_requeue_read_v1() to authenticated;
create or replace function public.admin_requeue_read() returns jsonb language sql stable security invoker as $f$ select security.admin_requeue_read_v1() $f$;
revoke all on function public.admin_requeue_read() from public, anon;
grant execute on function public.admin_requeue_read() to authenticated;

do $v$ begin
  if position('pinned_profile_id' in (select prosrc from pg_proc where oid='public.layer3_fact_claim_service(text,integer,text,text)'::regprocedure))=0
     or position('v_pin' in (select prosrc from pg_proc where oid='public.layer3_fact_complete_ladder_service(uuid,uuid,jsonb,jsonb)'::regprocedure))=0 then
    raise exception 'pinned model edits missing';
  end if;
end $v$;
