CREATE OR REPLACE FUNCTION security.scholarship_ai_scheduler_tick_impl(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare s pipeline.scholarship_ai_settings%rowtype; v_runs int:=0; v_changed int; v_profile pipeline.layer3_model_profiles%rowtype; v_run uuid;
begin
 for s in select * from pipeline.scholarship_ai_settings where enabled and schedule_on_change and schedule_actor is not null loop
   select * into v_profile from pipeline.layer3_model_profiles where id=s.default_profile_id and enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false) is true;
   if not found then continue; end if;
   select count(*) into v_changed
   from pipeline.layer2_scholarship_discovery_candidates c join pipeline.evidence_artifacts e on e.id=c.evidence_id and e.content_hash is not null and e.storage_path is not null
   where c.evidence_id is not null and (c.classification is null or c.classification='needs_review')
     and not exists(select 1 from pipeline.scholarship_ai_run_items i join pipeline.scholarship_ai_runs r on r.id=i.run_id where i.candidate_id=c.id and r.task_class=s.default_task_class and r.trigger_mode<>'benchmark' and i.evidence_hash=e.content_hash and i.status in ('validated','needs_review','no_candidate'));
   if v_changed=0 then continue; end if;
   if exists(select 1 from pipeline.scholarship_ai_runs r where r.country_code=s.country_code and r.trigger_mode='scheduled' and r.status in ('queued','running')) then continue; end if;
   insert into pipeline.scholarship_ai_runs(country_code,task_class,profile_id,trigger_mode,changes_only,requested_limit,requested_by,status,started_at,metadata)
   values(s.country_code,s.default_task_class,s.default_profile_id,'scheduled',true,least(s.max_records_per_run,v_changed),s.schedule_actor,'queued',p_now,jsonb_build_object('scheduled_on_change',true,'detected_changes',v_changed,'change_control_ref','CF-CHG-20260906-221')) returning id into v_run;
   insert into pipeline.scholarship_ai_run_items(run_id,candidate_id,evidence_id,evidence_hash,metadata)
   select v_run,c.id,c.evidence_id,e.content_hash,jsonb_build_object('scheduled_on_change',true)
   from pipeline.layer2_scholarship_discovery_candidates c join pipeline.evidence_artifacts e on e.id=c.evidence_id and e.content_hash is not null and e.storage_path is not null
   where c.evidence_id is not null and (c.classification is null or c.classification='needs_review')
     and not exists(select 1 from pipeline.scholarship_ai_run_items i join pipeline.scholarship_ai_runs r on r.id=i.run_id where i.candidate_id=c.id and r.task_class=s.default_task_class and r.trigger_mode<>'benchmark' and i.evidence_hash=e.content_hash and i.status in ('validated','needs_review','no_candidate'))
   order by c.created_at asc,c.id limit s.max_records_per_run;
   update pipeline.scholarship_ai_runs set total_items=(select count(*) from pipeline.scholarship_ai_run_items where run_id=v_run) where id=v_run;
   v_runs:=v_runs+1;
 end loop;
 return jsonb_build_object('ok',true,'scheduled_runs',v_runs,'observed_at',p_now);
end $function$
