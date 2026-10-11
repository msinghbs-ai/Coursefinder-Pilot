CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_record(p_candidate_id bigint, p_read_status text, p_http_status integer, p_fetched_via text, p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare r jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_read_status='deferred' then -- out of time in this run: back to the queue unchanged
    update pipeline.scholarship_page_candidates set leased_until=null, attempts=greatest(0,attempts-1) where id=p_candidate_id;
    return jsonb_build_object('admitted',false,'deferred',true);
  end if;
  update pipeline.scholarship_page_candidates set read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, storage_path=coalesce(p_storage_path,storage_path), content_hash=coalesce(p_sha256,content_hash), facts=coalesce(p_facts,facts),
         next_read_at=case when p_read_status in ('read','robots_disallowed','gone') then now()+interval '90 days' else now()+interval '6 hours' end,
         admit_status=case when p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true then 'rejected' else admit_status end,
         admit_reasons=case when p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true
                            then array(select jsonb_array_elements_text(coalesce(p_facts->'admission'->'reasons','[]'))) else admit_reasons end
   where id=p_candidate_id;
  if p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) then r:=security.scholarship_admit_from_provider_page_v1(p_candidate_id); end if;
  return coalesce(r, jsonb_build_object('admitted',false));
end $function$
