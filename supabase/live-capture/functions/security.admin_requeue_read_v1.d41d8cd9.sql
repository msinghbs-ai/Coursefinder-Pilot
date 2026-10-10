CREATE OR REPLACE FUNCTION security.admin_requeue_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
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
end $function$
