CREATE OR REPLACE FUNCTION admin_api.scholarship_ai_run_status(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_rank int:=security.scholarship_ai_role_rank(); v_actor uuid:=auth.uid(); v_r pipeline.scholarship_ai_runs%rowtype;
begin
 if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 select * into v_r from pipeline.scholarship_ai_runs where id=p_run_id;
 if not found then raise exception 'run not found'; end if;
 return jsonb_build_object('id',v_r.id,'status',v_r.status,'total_items',v_r.total_items,'processed_items',v_r.processed_items,'validated_items',v_r.validated_items,'review_items',v_r.review_items,'no_candidate_items',v_r.no_candidate_items,'failed_items',v_r.failed_items,'api_calls',case when v_rank>=4 then v_r.api_calls else null end,'input_tokens',case when v_rank>=4 then v_r.input_tokens else null end,'output_tokens',case when v_rank>=4 then v_r.output_tokens else null end,'cost_usd',case when v_rank>=4 then v_r.cost_usd else null end,'created_at',v_r.created_at,'started_at',v_r.started_at,'completed_at',v_r.completed_at);
end $function$
