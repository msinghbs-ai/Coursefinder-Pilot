-- CF-247 UI control sweep, fix 2: intake and English work that failed is released and its page goes back to the waiting
-- pool automatically, so counting those rows as "failed" (512) overstated what needs a retry. "Failed" now counts only work
-- that was not released; "waiting" shows pages queued for the AI check. Replaces the read only if it is still exactly as
-- 20260930051000 left it.

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid='security.admin_requeue_read_v1()'::regprocedure)<>'efd0bf3fb2468382aa45d0f194bed300' then
    raise exception 'cf247_ui_control_sweep_fix2: admin_requeue_read_v1 changed since 20260930051000; review before replacing';
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
    'layer3_failed',(select jsonb_object_agg(task_class,n) from (select task_class,count(*) n from pipeline.layer3_work_items where status in ('failed','parked') and coalesce(last_error,'') not like 'released:%' group by 1) y),
    'layer3_waiting',(select jsonb_object_agg(task_class,n) from (select task_class,count(*) n from (
         select task_class from pipeline.layer3_fact_handoffs where work_item_id is null
         union all select task_class from pipeline.layer3_work_items where status='pending') z group by 1) y),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='requeue' order by created_at desc limit 10) e));
end $f$;
revoke all on function security.admin_requeue_read_v1() from public, anon;
grant execute on function security.admin_requeue_read_v1() to authenticated;
create or replace function public.admin_requeue_read() returns jsonb language sql stable security invoker as $f$ select security.admin_requeue_read_v1() $f$;
revoke all on function public.admin_requeue_read() from public, anon;
grant execute on function public.admin_requeue_read() to authenticated;
