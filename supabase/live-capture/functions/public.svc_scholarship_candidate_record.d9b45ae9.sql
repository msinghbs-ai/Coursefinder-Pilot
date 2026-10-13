CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_record(p_candidate_id bigint, p_read_status text, p_http_status integer, p_fetched_via text, p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare r jsonb; c pipeline.scholarship_page_candidates%rowtype; v_ev uuid; v_ai boolean := coalesce((select s.ai_admission from pipeline.scholarship_ai_extract_settings s where s.id=1),false) and exists (select 1 from pipeline.scholarship_ai_models m where m.status='active');
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_read_status='deferred' then -- out of time in this run: back to the queue unchanged
    update pipeline.scholarship_page_candidates set leased_until=null, attempts=greatest(0,attempts-1) where id=p_candidate_id;
    return jsonb_build_object('admitted',false,'deferred',true);
  end if;
  update pipeline.scholarship_page_candidates set read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, storage_path=coalesce(p_storage_path,storage_path), content_hash=coalesce(p_sha256,content_hash), facts=coalesce(p_facts,facts),
         next_read_at=case when p_read_status in ('read','robots_disallowed','gone') then now()+interval '90 days' else now()+interval '6 hours' end,
         admit_status=case when not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true then 'rejected' else admit_status end,
         admit_reasons=case when not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true
                            then array(select jsonb_array_elements_text(coalesce(p_facts->'admission'->'reasons','[]'))) else admit_reasons end
   where id=p_candidate_id;
  if not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) then r:=security.scholarship_admit_from_provider_page_v1(p_candidate_id); end if;
  -- v2.15.249 (bugs 11/10-6): with AI admission on, the AI decides every page read (its copy is kept), not the rules
  if v_ai and p_read_status in ('read','too_thin') and p_storage_path is not null then
    insert into pipeline.scholarship_ai_queue(model_code,prompt_version,run_kind,candidate_id,provider_id,url)
    select a.model_code,a.prompt_version,'admit',p_candidate_id,(select x.provider_id from pipeline.scholarship_page_candidates x where x.id=p_candidate_id),coalesce(p_final_url,(select x.url from pipeline.scholarship_page_candidates x where x.id=p_candidate_id))
      from security.scholarship_ai_active_v1() a where not exists (select 1 from pipeline.scholarship_ai_queue q where q.candidate_id=p_candidate_id and q.state in ('queued','leased'));
    r:=jsonb_build_object('admitted',false,'ai','queued');
  end if;
  select * into c from pipeline.scholarship_page_candidates where id=p_candidate_id;
  -- v2.15.248 (Platform Admin bugs 11/10-5, Fix 2): a stored page that did not become a scholarship is kept as evidence of the decision
  if c.storage_path is not null and c.evidence_id is null and coalesce(c.admit_status,'')<>'admitted' then
    insert into pipeline.evidence_artifacts(source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key)
    values (security.coverage_sweep_source(c.provider_id),'scholarship_candidate_page',coalesce(c.final_url,c.url),c.storage_path,c.content_hash,'application/gzip',
            jsonb_build_object('candidate_id',c.id,'provider_id',c.provider_id,'read_status',c.read_status,'decision',coalesce(c.admit_status,c.read_status),'reasons',to_jsonb(coalesce(c.admit_reasons,'{}'::text[])),'worker','coverage-sweep scholarship candidates'),1,'scholarship_candidate:'||c.id)
    returning id into v_ev;
    update pipeline.scholarship_page_candidates set evidence_id=v_ev where id=c.id;
  end if;
  -- (Fix 4) a page that lists scholarships is suggested as the provider's listing page, for a person to confirm
  if coalesce(c.admit_status,'')<>'admitted' and c.read_status in ('read','too_thin')
     and (coalesce(c.facts->>'h1','')||' '||coalesce(c.title,'')||' '||coalesce(c.facts->>'page_title','') ~* '(scholarships? (finder|search|list|directory)|grants and scholarships|find (a|your) scholarship|^\s*scholarships\s*$)'
          or coalesce(c.admit_reasons,'{}') && array['listing_page'] or c.url ~* '(scholarship-finder|/scholarships?/?$|/grants-scholarships/?$)') then
    insert into pipeline.scholarship_listing_pages(provider_id,url,url_norm,source,active,status)
    values (c.provider_id,coalesce(c.final_url,c.url),security.scholarship_url_norm(coalesce(c.final_url,c.url)),'suggested',false,'suggested')
    on conflict (provider_id,url_norm) do nothing;
  end if;
  return coalesce(r, jsonb_build_object('admitted',false));
end $function$
