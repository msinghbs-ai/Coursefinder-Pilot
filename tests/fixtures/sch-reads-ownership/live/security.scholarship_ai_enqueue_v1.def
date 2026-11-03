CREATE OR REPLACE FUNCTION security.scholarship_ai_enqueue_v1(p_run_kind text, p_provider_ids uuid[], p_job uuid DEFAULT NULL::uuid, p_known boolean DEFAULT true)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a record; v_n int := 0; v_k int;
begin
  select * into a from security.scholarship_ai_active_v1();
  if a.model_code is null then return 0; end if;
  insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, candidate_id, provider_id, url)
  select a.model_code, a.prompt_version, p_run_kind, p_job, c.id, c.provider_id, coalesce(c.final_url, c.url)
    from pipeline.scholarship_page_candidates c
   where c.provider_id = any (p_provider_ids) and c.source <> 'register' and c.admitted_scholarship_id is null and c.matched_scholarship_id is null
     and coalesce(c.admit_status, '') not in ('skipped', 'duplicate', 'admitted', 'matched_held')
     and not exists (select 1 from pipeline.scholarship_ai_extractions e where e.candidate_id = c.id and e.model_code = a.model_code and e.prompt_version = a.prompt_version and e.error is null)
     and not exists (select 1 from pipeline.scholarship_ai_queue q where q.candidate_id = c.id and q.state in ('queued', 'leased'));
  get diagnostics v_k = row_count; v_n := v_n + v_k;
  if p_known then
    insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, scholarship_id, provider_id, url)
    select a.model_code, a.prompt_version, 'reread', p_job, s.id, s.provider_id, coalesce(sp.final_url, sp.url)
      from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
     where s.provider_id = any (p_provider_ids) and s.lifecycle_status = 'active'
       and not exists (select 1 from pipeline.scholarship_ai_extractions e where e.scholarship_id = s.id and e.model_code = a.model_code and e.prompt_version = a.prompt_version and e.error is null)
       and not exists (select 1 from pipeline.scholarship_ai_queue q where q.scholarship_id = s.id and q.state in ('queued', 'leased'));
    get diagnostics v_k = row_count; v_n := v_n + v_k;
  end if;
  perform security.scholarship_ai_fire_v1();
  return v_n;
end $function$
