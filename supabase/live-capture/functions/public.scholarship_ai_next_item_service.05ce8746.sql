CREATE OR REPLACE FUNCTION public.scholarship_ai_next_item_service(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v_i pipeline.scholarship_ai_run_items%rowtype; v_r pipeline.scholarship_ai_runs%rowtype; v_e pipeline.evidence_artifacts%rowtype; v_c pipeline.layer2_scholarship_discovery_candidates%rowtype;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into v_r from pipeline.scholarship_ai_runs where id=p_run_id for update;
 if not found then raise exception 'run not found'; end if;
 if v_r.status in ('completed','completed_with_errors','failed','cancelled') then return jsonb_build_object('done',true,'status',v_r.status,'country_code',v_r.country_code); end if;
 select * into v_i from pipeline.scholarship_ai_run_items where run_id=p_run_id and status='queued' order by created_at,id limit 1 for update skip locked;
 if not found then update pipeline.scholarship_ai_runs set status=case when failed_items>0 then 'completed_with_errors' else 'completed' end,completed_at=now() where id=p_run_id; return jsonb_build_object('done',true,'status',case when v_r.failed_items>0 then 'completed_with_errors' else 'completed' end,'country_code',v_r.country_code); end if;
 update pipeline.scholarship_ai_run_items set status='running',started_at=now() where id=v_i.id;
 update pipeline.scholarship_ai_runs set status='running',started_at=coalesce(started_at,now()) where id=p_run_id;
 select * into v_e from pipeline.evidence_artifacts where id=v_i.evidence_id;
 select * into v_c from pipeline.layer2_scholarship_discovery_candidates where id=v_i.candidate_id;
 return jsonb_build_object('done',false,'item_id',v_i.id,'candidate_id',v_i.candidate_id,'evidence_id',v_i.evidence_id,'evidence_hash',v_i.evidence_hash,'storage_path',v_e.storage_path,'mime_type',v_e.mime_type,'source_url',v_e.source_url,'task_class',v_r.task_class,'profile_id',v_r.profile_id,'trigger_mode',v_r.trigger_mode,'requested_by',v_r.requested_by,'country_code',v_r.country_code,'observed_title',v_c.observed_title,'scholarship_url',v_c.scholarship_url,'classification',v_c.classification);
end $function$
