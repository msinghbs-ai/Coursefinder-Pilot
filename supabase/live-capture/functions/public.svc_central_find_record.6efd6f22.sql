CREATE OR REPLACE FUNCTION public.svc_central_find_record(p_provider_id uuid, p_found jsonb, p_evidence jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_found is null then  -- no credit to spend: back in the queue, unchanged
    update pipeline.provider_central_search set state = 'queued', leased_until = null, attempts = greatest(attempts - 1, 0), evidence = p_evidence, updated_at = now() where provider_id = p_provider_id;
    return;
  end if;
  update pipeline.provider_central_search
     set state = case when p_evidence ? 'error' then (case when attempts >= 3 then 'failed' else 'queued' end) else 'done' end,
         found = case when p_evidence ? 'error' then found else p_found end, evidence = p_evidence, leased_until = null,
         searched_at = case when p_evidence ? 'error' then searched_at else now() end,
         requested_at = case when p_evidence ? 'error' then requested_at end, updated_at = now()
   where provider_id = p_provider_id;
end $function$
