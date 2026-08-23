-- Live migration: m2_1_completeness_trial_control_sampling
create or replace function public.layer2_completeness_trial_create(p_country_code text,p_provider_id uuid,p_batch_size integer default 10)
returns jsonb language plpgsql security definer set search_path=public,pipeline,catalogue,ref as $$
declare v_country uuid; v_profile uuid; v_trial uuid; v_batch integer:=greatest(1,least(coalesce(p_batch_size,10),100)); v_controls integer;
begin
 if auth.role()<>'service_role' then raise exception 'service_role required'; end if;
 select id into v_country from ref.countries where trim(iso_alpha2)=upper(trim(p_country_code)) limit 1;
 if v_country is null then raise exception 'country not found'; end if;
 if not exists(select 1 from catalogue.providers p where p.id=p_provider_id and p.country_id=v_country) then raise exception 'provider not in requested country'; end if;
 select id into v_profile from pipeline.layer2_country_completeness_profiles where country_id=v_country and active order by version_no desc limit 1;
 if v_profile is null then raise exception 'no active completeness profile'; end if;
 v_controls:=case when v_batch>=10 then 2 when v_batch>=5 then 1 else 0 end;
 insert into pipeline.layer2_completeness_trials(country_id,completeness_profile_id,provider_id,requested_batch_size,status,started_at) values(v_country,v_profile,p_provider_id,v_batch,'running',now()) returning id into v_trial;
 with scored as (
  select c.id,c.provider_id,c.stable_key,((pipeline.layer2_course_factual_snapshot(c.id)->>'course_url'<>'present')::int+(pipeline.layer2_course_factual_snapshot(c.id)->>'provider_current_tuition'<>'present')::int+(pipeline.layer2_course_factual_snapshot(c.id)->>'intakes'<>'present')::int+(pipeline.layer2_course_factual_snapshot(c.id)->>'english_requirements'<>'present')::int+(pipeline.layer2_course_factual_snapshot(c.id)->>'description'<>'present')::int) miss from catalogue.courses c where c.provider_id=p_provider_id),
 controls as (select *,'control_known_coverage'::text reason from scored order by miss asc,stable_key limit v_controls),
 gaps as (select s.*,'gap_learning_sample'::text reason from scored s where not exists(select 1 from controls x where x.id=s.id) order by miss desc,stable_key limit greatest(0,v_batch-v_controls)),
 chosen as (select * from controls union all select * from gaps), ranked as (select *,row_number() over(order by case reason when 'control_known_coverage' then 0 else 1 end,miss asc,stable_key) sample_rank from chosen)
 insert into pipeline.layer2_completeness_trial_courses(trial_id,course_id,provider_id,sample_rank,selection_reason,baseline_factual,baseline_context)
 select v_trial,id,provider_id,sample_rank,reason,pipeline.layer2_course_factual_snapshot(id),pipeline.layer2_course_decision_context_snapshot(id) from ranked order by sample_rank;
 update pipeline.layer2_completeness_trials t set baseline_summary=(select jsonb_build_object('selected_courses',count(*),'batch_size',v_batch,'control_courses',count(*) filter(where selection_reason='control_known_coverage'),'gap_courses',count(*) filter(where selection_reason='gap_learning_sample')) from pipeline.layer2_completeness_trial_courses tc where tc.trial_id=v_trial) where t.id=v_trial;
 return jsonb_build_object('trial_id',v_trial,'country_code',upper(trim(p_country_code)),'provider_id',p_provider_id,'selected_courses',(select count(*) from pipeline.layer2_completeness_trial_courses where trial_id=v_trial),'sampling','controls_plus_gap_learning');
end$$;
revoke all on function public.layer2_completeness_trial_create(text,uuid,integer) from public,anon,authenticated;
grant execute on function public.layer2_completeness_trial_create(text,uuid,integer) to service_role;
