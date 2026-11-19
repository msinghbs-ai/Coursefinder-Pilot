create or replace function public.scholarship_ai_next_item_service(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path='pg_catalog','pipeline' as $$
declare v_i pipeline.scholarship_ai_run_items%rowtype; v_r pipeline.scholarship_ai_runs%rowtype; v_e pipeline.evidence_artifacts%rowtype; v_c pipeline.layer2_scholarship_discovery_candidates%rowtype;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into v_r from pipeline.scholarship_ai_runs where id=p_run_id for update;
 if not found then raise exception 'run not found'; end if;
 if v_r.status in ('completed','completed_with_errors','failed','cancelled') then return jsonb_build_object('done',true,'status',v_r.status); end if;
 select * into v_i from pipeline.scholarship_ai_run_items where run_id=p_run_id and status='queued' order by created_at,id limit 1 for update skip locked;
 if not found then
   update pipeline.scholarship_ai_runs set status=case when failed_items>0 then 'completed_with_errors' else 'completed' end,completed_at=now() where id=p_run_id;
   return jsonb_build_object('done',true,'status',case when v_r.failed_items>0 then 'completed_with_errors' else 'completed' end);
 end if;
 update pipeline.scholarship_ai_run_items set status='running',started_at=now() where id=v_i.id;
 update pipeline.scholarship_ai_runs set status='running',started_at=coalesce(started_at,now()) where id=p_run_id;
 select * into v_e from pipeline.evidence_artifacts where id=v_i.evidence_id;
 select * into v_c from pipeline.layer2_scholarship_discovery_candidates where id=v_i.candidate_id;
 return jsonb_build_object('done',false,'item_id',v_i.id,'candidate_id',v_i.candidate_id,'evidence_id',v_i.evidence_id,'evidence_hash',v_i.evidence_hash,'storage_path',v_e.storage_path,'mime_type',v_e.mime_type,'source_url',v_e.source_url,'task_class',v_r.task_class,'profile_id',v_r.profile_id,'trigger_mode',v_r.trigger_mode,'requested_by',v_r.requested_by,'observed_title',v_c.observed_title,'scholarship_url',v_c.scholarship_url,'classification',v_c.classification);
end $$;
revoke all on function public.scholarship_ai_next_item_service(uuid) from public,anon,authenticated;
grant execute on function public.scholarship_ai_next_item_service(uuid) to service_role;

create or replace function public.scholarship_ai_profile_service(p_profile_id uuid,p_allow_benchmark_pending boolean default false)
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','pipeline' as $$
declare p pipeline.layer3_model_profiles%rowtype;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into p from pipeline.layer3_model_profiles where id=p_profile_id;
 if not found then raise exception 'profile not found'; end if;
 if not p.enabled then raise exception 'profile disabled'; end if;
 if not p_allow_benchmark_pending and (p.paused or coalesce((p.quality_benchmark->>'pass')::boolean,false) is not true) then raise exception 'profile not qualified'; end if;
 return jsonb_build_object('id',p.id,'code',p.code,'aggregator_provider',p.aggregator_provider,'base_url',p.base_url,'model_identifier',p.model_identifier,'secret_env_key',p.secret_env_key,'prompt_profile_version',p.prompt_profile_version,'prompt_system',p.prompt_system,'validators',p.deterministic_validators,'max_input_tokens',p.max_input_tokens,'max_output_tokens',p.max_output_tokens,'retry_ceiling',p.retry_ceiling,'timeout_ms',p.timeout_ms,'cost_ceiling_usd',p.cost_ceiling_usd,'benchmark_pass',coalesce((p.quality_benchmark->>'pass')::boolean,false),'paused',p.paused);
end $$;
revoke all on function public.scholarship_ai_profile_service(uuid,boolean) from public,anon,authenticated;
grant execute on function public.scholarship_ai_profile_service(uuid,boolean) to service_role;

create or replace function public.scholarship_ai_item_finish_service(p_item_id uuid,p_status text,p_result_status text,p_interpretation_id uuid,p_error_text text,p_api_calls integer,p_input_tokens integer,p_output_tokens integer,p_cost_usd numeric,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='pg_catalog','pipeline' as $$
declare v_run uuid; v_final text;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 if p_status not in ('validated','needs_review','no_candidate','failed','skipped_unchanged','cancelled') then raise exception 'invalid item status'; end if;
 update pipeline.scholarship_ai_run_items set status=p_status,result_status=p_result_status,interpretation_id=p_interpretation_id,error_text=p_error_text,api_calls=greatest(coalesce(p_api_calls,0),0),input_tokens=greatest(coalesce(p_input_tokens,0),0),output_tokens=greatest(coalesce(p_output_tokens,0),0),cost_usd=greatest(coalesce(p_cost_usd,0),0),completed_at=now(),metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb) where id=p_item_id returning run_id into v_run;
 if v_run is null then raise exception 'item not found'; end if;
 update pipeline.scholarship_ai_runs r set
   processed_items=(select count(*) from pipeline.scholarship_ai_run_items i where i.run_id=v_run and i.status not in ('queued','running')),
   validated_items=(select count(*) from pipeline.scholarship_ai_run_items i where i.run_id=v_run and i.status='validated'),
   review_items=(select count(*) from pipeline.scholarship_ai_run_items i where i.run_id=v_run and i.status='needs_review'),
   no_candidate_items=(select count(*) from pipeline.scholarship_ai_run_items i where i.run_id=v_run and i.status='no_candidate'),
   failed_items=(select count(*) from pipeline.scholarship_ai_run_items i where i.run_id=v_run and i.status='failed'),
   skipped_unchanged_items=(select count(*) from pipeline.scholarship_ai_run_items i where i.run_id=v_run and i.status='skipped_unchanged'),
   api_calls=(select coalesce(sum(i.api_calls),0) from pipeline.scholarship_ai_run_items i where i.run_id=v_run),
   input_tokens=(select coalesce(sum(i.input_tokens),0) from pipeline.scholarship_ai_run_items i where i.run_id=v_run),
   output_tokens=(select coalesce(sum(i.output_tokens),0) from pipeline.scholarship_ai_run_items i where i.run_id=v_run),
   cost_usd=(select coalesce(sum(i.cost_usd),0) from pipeline.scholarship_ai_run_items i where i.run_id=v_run)
 where r.id=v_run;
 if not exists(select 1 from pipeline.scholarship_ai_run_items where run_id=v_run and status in ('queued','running')) then
   update pipeline.scholarship_ai_runs set status=case when failed_items>0 then 'completed_with_errors' else 'completed' end,completed_at=now() where id=v_run;
 end if;
 select status into v_final from pipeline.scholarship_ai_runs where id=v_run;
 return jsonb_build_object('ok',true,'run_id',v_run,'run_status',v_final);
end $$;
revoke all on function public.scholarship_ai_item_finish_service(uuid,text,text,uuid,text,integer,integer,integer,numeric,jsonb) from public,anon,authenticated;
grant execute on function public.scholarship_ai_item_finish_service(uuid,text,text,uuid,text,integer,integer,integer,numeric,jsonb) to service_role;

create or replace function public.scholarship_ai_settings_write(p_country_code text,p_patch jsonb)
returns jsonb language plpgsql security definer set search_path='pg_catalog','pipeline','security' as $$
declare v_rank int:=security.scholarship_ai_role_rank(); v_actor uuid:=auth.uid(); v_country text:=upper(p_country_code); v_p uuid; v_row pipeline.scholarship_ai_settings%rowtype;
begin
 if v_rank<5 then raise exception 'PIM Admin role required' using errcode='42501'; end if;
 if p_patch ? 'default_profile_id' then v_p:=nullif(p_patch->>'default_profile_id','')::uuid; end if;
 insert into pipeline.scholarship_ai_settings(country_code) values(v_country) on conflict do nothing;
 update pipeline.scholarship_ai_settings set
   enabled=case when p_patch?'enabled' then (p_patch->>'enabled')::boolean else enabled end,
   schedule_on_change=case when p_patch?'schedule_on_change' then (p_patch->>'schedule_on_change')::boolean else schedule_on_change end,
   default_task_class=coalesce(nullif(p_patch->>'default_task_class',''),default_task_class),
   default_profile_id=case when p_patch?'default_profile_id' then v_p else default_profile_id end,
   max_records_per_run=case when p_patch?'max_records_per_run' then least(greatest((p_patch->>'max_records_per_run')::int,1),200) else max_records_per_run end,
   daily_budget_usd=case when p_patch?'daily_budget_usd' then greatest((p_patch->>'daily_budget_usd')::numeric,0) else daily_budget_usd end,
   schedule_actor=case when coalesce((p_patch->>'schedule_on_change')::boolean,schedule_on_change) then v_actor else null end,
   updated_by=v_actor,updated_at=now(),metadata=metadata||jsonb_build_object('change_control_ref','CF-CHG-20260906-221')
 where country_code=v_country returning * into v_row;
 return to_jsonb(v_row)-'schedule_actor'-'updated_by';
end $$;
revoke all on function public.scholarship_ai_settings_write(text,jsonb) from public;
grant execute on function public.scholarship_ai_settings_write(text,jsonb) to authenticated;

create or replace function security.scholarship_ai_scheduler_tick_impl(p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path='pg_catalog','pipeline','security' as $$
declare s pipeline.scholarship_ai_settings%rowtype; v_runs int:=0; v_changed int; v_profile pipeline.layer3_model_profiles%rowtype; v_run uuid;
begin
 for s in select * from pipeline.scholarship_ai_settings where enabled and schedule_on_change and schedule_actor is not null loop
   select * into v_profile from pipeline.layer3_model_profiles where id=s.default_profile_id and enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false) is true;
   if not found then continue; end if;
   select count(*) into v_changed
   from pipeline.layer2_scholarship_discovery_candidates c join pipeline.evidence_artifacts e on e.id=c.evidence_id and e.content_hash is not null and e.storage_path is not null
   where c.evidence_id is not null and (c.classification is null or c.classification='needs_review')
     and not exists(select 1 from pipeline.scholarship_ai_run_items i join pipeline.scholarship_ai_runs r on r.id=i.run_id where i.candidate_id=c.id and r.task_class=s.default_task_class and i.evidence_hash=e.content_hash and i.status in ('validated','needs_review','no_candidate'));
   if v_changed=0 then continue; end if;
   if exists(select 1 from pipeline.scholarship_ai_runs r where r.country_code=s.country_code and r.trigger_mode='scheduled' and r.status in ('queued','running')) then continue; end if;
   insert into pipeline.scholarship_ai_runs(country_code,task_class,profile_id,trigger_mode,changes_only,requested_limit,requested_by,status,started_at,metadata)
   values(s.country_code,s.default_task_class,s.default_profile_id,'scheduled',true,least(s.max_records_per_run,v_changed),s.schedule_actor,'queued',p_now,jsonb_build_object('scheduled_on_change',true,'detected_changes',v_changed,'change_control_ref','CF-CHG-20260906-221')) returning id into v_run;
   insert into pipeline.scholarship_ai_run_items(run_id,candidate_id,evidence_id,evidence_hash,metadata)
   select v_run,c.id,c.evidence_id,e.content_hash,jsonb_build_object('scheduled_on_change',true)
   from pipeline.layer2_scholarship_discovery_candidates c join pipeline.evidence_artifacts e on e.id=c.evidence_id and e.content_hash is not null and e.storage_path is not null
   where c.evidence_id is not null and (c.classification is null or c.classification='needs_review')
     and not exists(select 1 from pipeline.scholarship_ai_run_items i join pipeline.scholarship_ai_runs r on r.id=i.run_id where i.candidate_id=c.id and r.task_class=s.default_task_class and i.evidence_hash=e.content_hash and i.status in ('validated','needs_review','no_candidate'))
   order by c.created_at asc limit s.max_records_per_run;
   update pipeline.scholarship_ai_runs set total_items=(select count(*) from pipeline.scholarship_ai_run_items where run_id=v_run) where id=v_run;
   v_runs:=v_runs+1;
 end loop;
 return jsonb_build_object('ok',true,'scheduled_runs',v_runs,'observed_at',p_now);
end $$;
revoke all on function security.scholarship_ai_scheduler_tick_impl(timestamptz) from public,anon,authenticated;
grant execute on function security.scholarship_ai_scheduler_tick_impl(timestamptz) to service_role;

select cron.unschedule(jobid) from cron.job where jobname='coursefinder-scholarship-ai-change-scheduler';
select cron.schedule('coursefinder-scholarship-ai-change-scheduler','17 */6 * * *','select security.scholarship_ai_scheduler_tick_impl(now());');
