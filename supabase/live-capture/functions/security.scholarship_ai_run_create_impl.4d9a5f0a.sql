CREATE OR REPLACE FUNCTION security.scholarship_ai_run_create_impl(p_country_code text, p_task_class text, p_profile_id uuid, p_limit integer, p_trigger_mode text DEFAULT 'manual'::text, p_changes_only boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_rank int:=security.scholarship_ai_role_rank(); v_actor uuid:=auth.uid(); v_profile pipeline.layer3_model_profiles%rowtype; v_run uuid; v_count int:=0; v_limit int:=least(greatest(coalesce(p_limit,10),1),100); v_benchmark boolean:=coalesce(p_trigger_mode,'manual')='benchmark';
begin
 if v_rank<4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
 select * into v_profile from pipeline.layer3_model_profiles where id=p_profile_id and p_task_class=any(allowed_task_classes);
 if not found then raise exception 'Scholarship AI model profile/task mismatch'; end if;
 if not v_benchmark and (not v_profile.enabled or v_profile.paused or coalesce((v_profile.quality_benchmark->>'pass')::boolean,false) is not true) then raise exception 'model profile benchmark must pass before governed execution'; end if;
 if v_benchmark and v_rank<5 then raise exception 'PIM Admin role required for model benchmark'; end if;
 if v_benchmark then v_limit:=least(v_limit,5); end if;
 insert into pipeline.scholarship_ai_runs(country_code,task_class,profile_id,trigger_mode,changes_only,requested_limit,requested_by,status,started_at,metadata)
 values(upper(p_country_code),p_task_class,p_profile_id,case when v_benchmark then 'benchmark' else coalesce(p_trigger_mode,'manual') end,p_changes_only,v_limit,v_actor,'queued',now(),jsonb_build_object('change_control_ref','CF-CHG-20260906-221')) returning id into v_run;
 with eligible as (
   select c.id candidate_id,c.evidence_id,e.content_hash,c.classification,c.created_at
   from pipeline.layer2_scholarship_discovery_candidates c
   join pipeline.evidence_artifacts e on e.id=c.evidence_id and e.content_hash is not null and e.storage_path is not null
   where c.evidence_id is not null
     and ((p_task_class='scholarship_page_classification' and (c.classification is null or c.classification='needs_review'))
       or (p_task_class='scholarship_detail_extract' and c.classification in ('detail_ready','needs_review')))
     and (not p_changes_only or not exists(
       select 1 from pipeline.scholarship_ai_run_items oldi
       join pipeline.scholarship_ai_runs oldr on oldr.id=oldi.run_id
       where oldi.candidate_id=c.id and oldr.task_class=p_task_class and oldi.evidence_hash=e.content_hash
         and oldi.status in ('validated','needs_review','no_candidate')
         and ((v_benchmark and oldr.trigger_mode='benchmark' and oldr.profile_id=p_profile_id)
              or (not v_benchmark and oldr.trigger_mode<>'benchmark'))
     ))
   order by case when c.classification='needs_review' then 0 when c.classification is null then 1 else 2 end,c.created_at asc,c.id
   limit v_limit
 )
 insert into pipeline.scholarship_ai_run_items(run_id,candidate_id,evidence_id,evidence_hash,metadata)
 select v_run,candidate_id,evidence_id,content_hash,jsonb_build_object('classification_at_queue',classification,'benchmark_isolated',v_benchmark) from eligible;
 get diagnostics v_count=row_count;
 update pipeline.scholarship_ai_runs set total_items=v_count,status=case when v_count=0 then 'completed' else 'queued' end,completed_at=case when v_count=0 then now() else null end where id=v_run;
 return jsonb_build_object('ok',true,'run_id',v_run,'total_items',v_count,'trigger_mode',case when v_benchmark then 'benchmark' else coalesce(p_trigger_mode,'manual') end,'changes_only',p_changes_only);
end $function$
