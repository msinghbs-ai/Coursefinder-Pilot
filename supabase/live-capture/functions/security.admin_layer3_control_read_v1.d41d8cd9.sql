CREATE OR REPLACE FUNCTION security.admin_layer3_control_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'cron', 'security'
AS $function$
declare v jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  select jsonb_build_object(
    'generated_at', now(),
    'can_control', security.current_role_rank()>=5,
    'credit', (select jsonb_build_object('remaining_usd',round(remaining_usd,2),'observed_at',observed_at) from pipeline.layer3_openrouter_observations where kind='credits' order by observed_at desc limit 1),
    'tasks', (select jsonb_agg(jsonb_build_object(
        'task_class', b.task_class,
        'label', case b.task_class when 'provider_intake_validation' then 'Intakes' when 'provider_english_validation' then 'English requirements' else 'Tuition' end,
        'running', coalesce((select j.active from cron.job j where j.jobname=security.layer3_task_job(b.task_class)),false),
        'cascade', b.route_mode='ladder',
        'daily_usd', b.daily_usd_max,
        'spent_today_usd', round(coalesce((select sum(i.estimated_cost_usd) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC'),0),4),
        'last_24h', (select jsonb_build_object('admitted',count(*) filter (where w.status='admitted'),'to_review',count(*) filter (where w.status='layer4_required'),
                       'not_stated',count(*) filter (where w.status='no_candidate'),'retrying',count(*) filter (where w.status in ('failed','pending')))
                       from pipeline.layer3_work_items w where w.task_class=b.task_class and w.updated_at>=now()-interval '24 hours'),
        'in_review', (select count(*) from pipeline.layer4_review_items l where l.status='pending' and l.layer3_interpretation_id is not null
                        and l.field_code=case b.task_class when 'provider_intake_validation' then 'course_intake' when 'provider_english_validation' then 'course_english' else 'provider_current_tuition_validation' end),
        'tiers', case when b.route_mode='ladder' then (select coalesce(jsonb_agg(jsonb_build_object(
              'tier', t.tier_no, 'active', t.active, 'final', t.is_final, 'profile', p.code, 'model', p.model_identifier,
              'cost_per_1000_usd', round(t.cost_per_call_usd*1000,2), 'test_right_pct', round(t.h1_success_rate*100,1), 'test_wrong', t.h1_wrong_admitted,
              'answered_24h', (select count(*) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=t.profile_id and i.created_at>=now()-interval '24 hours' and i.status in ('validated','no_candidate')),
              'passed_up_24h', (select count(*) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=t.profile_id and i.created_at>=now()-interval '24 hours' and i.status='escalated'),
              'cost_24h_usd', (select round(coalesce(sum(i.estimated_cost_usd),0),4) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=t.profile_id and i.created_at>=now()-interval '24 hours'),
              'audits', (select jsonb_build_object('checked',count(*),'disagreed',count(*) filter (where not a.agree)) from pipeline.layer3_tier_audits a where a.profile_id=t.profile_id and a.task_class=b.task_class)
            ) order by t.tier_no),'[]'::jsonb) from pipeline.layer3_route_tiers t join pipeline.layer3_model_profiles p on p.id=t.profile_id where t.task_class=b.task_class and p.enabled and not p.paused and p.retired_at is null)
          else (select coalesce(jsonb_agg(jsonb_build_object('tier',1,'active',true,'final',true,'profile',p.code,'model',p.model_identifier,
              'cost_per_1000_usd', round(coalesce((security.layer3_tier_evidence(b.task_class,p.id)->>'cost_per_call_usd')::numeric,0)*1000,2),
              'test_right_pct', (security.layer3_tier_evidence(b.task_class,p.id)->>'right_pct')::numeric, 'test_wrong', (security.layer3_tier_evidence(b.task_class,p.id)->>'wrong')::int,
              'answered_24h', (select count(*) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=p.id and i.created_at>=now()-interval '24 hours'),
              'passed_up_24h', 0, 'cost_24h_usd', (select round(coalesce(sum(i.estimated_cost_usd),0),4) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=p.id and i.created_at>=now()-interval '24 hours'))),'[]'::jsonb)
              from pipeline.layer3_model_profiles p where b.task_class=any(p.allowed_task_classes) and p.enabled and not p.paused and p.retired_at is null
               and coalesce((p.quality_benchmark->>'pass')::boolean,false)) end,
        'addable', case when b.route_mode='ladder' then (select coalesce(jsonb_agg(jsonb_build_object('profile',p.code,'model',p.model_identifier,
              'test_right_pct',(e->>'right_pct')::numeric,'test_wrong',(e->>'wrong')::int,'cost_per_1000_usd',round((e->>'cost_per_call_usd')::numeric*1000,2)) order by (e->>'cost_per_call_usd')::numeric),'[]'::jsonb)
            from pipeline.layer3_model_profiles p cross join lateral (select security.layer3_tier_evidence(b.task_class,p.id) e) x
           where b.task_class=any(p.allowed_task_classes) and coalesce((e->>'eligible')::boolean,false)
             and not exists (select 1 from pipeline.layer3_route_tiers t where t.task_class=b.task_class and t.profile_id=p.id)) else '[]'::jsonb end
      ) order by case b.task_class when 'provider_intake_validation' then 1 when 'provider_english_validation' then 2 else 3 end)
      from pipeline.layer3_route_budget b),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'kind',e.kind,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                 from (select * from pipeline.layer3_route_events order by created_at desc limit 12) e)
  ) into v;
  return v;
end $function$
