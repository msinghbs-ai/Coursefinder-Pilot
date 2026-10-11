CREATE OR REPLACE FUNCTION public.scholarship_candidate_mark_catalogue(p_job_id uuid, p_reason text DEFAULT 'catalogue_enumeration_required'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline'
AS $function$
declare v_candidate uuid;v_count integer:=0;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501';end if;
 select nullif(payload->>'candidate_id','')::uuid into v_candidate from pipeline.jobs where id=p_job_id and domain='scholarship';
 if v_candidate is null then return jsonb_build_object('ok',false,'reason','candidate_missing');end if;
 update pipeline.layer2_scholarship_discovery_candidates
 set classification='catalogue_or_filter',classification_reason=coalesce(p_reason,'catalogue_enumeration_required')||'; retained as catalogue Evidence, not individual Scholarship',classified_at=now()
 where id=v_candidate;
 get diagnostics v_count=row_count;
 return jsonb_build_object('ok',true,'candidate_id',v_candidate,'updated',v_count);
end
$function$
