create or replace function public.scholarship_candidate_mark_catalogue(p_job_id uuid,p_reason text default 'catalogue_enumeration_required')
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $function$
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
$function$;
revoke all on function public.scholarship_candidate_mark_catalogue(uuid,text) from public,anon,authenticated;
grant execute on function public.scholarship_candidate_mark_catalogue(uuid,text) to service_role;

-- Reconcile current CF-163 expected catalogue outcomes as successful governed skips.
with x as(
 select id,(payload->>'candidate_id')::uuid candidate_id,result->>'evidence_id' evidence_id,payload->>'target_url' target_url
 from pipeline.jobs
 where domain='scholarship' and payload->>'change_control_ref'='CF-163' and status='failed'
   and error_text like 'layer2-scholarship-extract 409: catalogue_enumeration_required%'
)
update pipeline.layer2_scholarship_discovery_candidates c
set classification='catalogue_or_filter',classification_reason='extractor confirmed catalogue_enumeration_required; retained as catalogue Evidence, not individual Scholarship',classified_at=now()
from x where c.id=x.candidate_id;

with x as(
 select id,payload->>'target_url' target_url from pipeline.jobs
 where domain='scholarship' and payload->>'change_control_ref'='CF-163' and status='failed'
   and error_text like 'layer2-scholarship-extract 409: catalogue_enumeration_required%'
)
update pipeline.jobs j
set status='succeeded',completed_at=now(),error_text=null,
 result=coalesce(j.result,'{}'::jsonb)||jsonb_build_object('extraction',jsonb_build_object('skipped',true,'reason','catalogue_enumeration_required','classification','catalogue_or_filter'),'publication_changed',false,'canonical_mutation_authorised',false)
from x where j.id=x.id;
