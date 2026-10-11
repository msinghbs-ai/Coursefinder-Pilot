CREATE OR REPLACE FUNCTION public.scholarship_ai_item_finish_service(p_item_id uuid, p_status text, p_result_status text, p_interpretation_id uuid, p_error_text text, p_api_calls integer, p_input_tokens integer, p_output_tokens integer, p_cost_usd numeric, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
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
end $function$
