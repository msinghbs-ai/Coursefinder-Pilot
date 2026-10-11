-- CF-247 (11 Oct 2026, found in the live check of 20261011009400): the central page search could not save its results
-- ("column reference found is ambiguous": FOUND is also a PL/pgSQL variable). The column is now named through its table alias.
-- The providers left half-way are put back in the queue with their attempts reset. md5-checked before and after. Nothing is deleted.
do $guard$
declare v_expected jsonb := '{"public.svc_central_find_record(uuid,jsonb,jsonb)": "0b921c804243ef259ea627cf09f411c4"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

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
  update pipeline.provider_central_search s
     set state = case when p_evidence ? 'error' then (case when attempts >= 3 then 'failed' else 'queued' end) else 'done' end,
         found = case when p_evidence ? 'error' then s.found else p_found end, evidence = p_evidence, leased_until = null,
         searched_at = case when p_evidence ? 'error' then searched_at else now() end,
         requested_at = case when p_evidence ? 'error' then requested_at end, updated_at = now()
   where provider_id = p_provider_id;
end $function$;

update pipeline.provider_central_search set state = 'queued', leased_until = null, attempts = 0, updated_at = now() where state = 'leased' and searched_at is null;

do $post$
declare v_expected jsonb := '{"public.svc_central_find_record(uuid,jsonb,jsonb)": "b94f89ea42d76e305ceba7c356454c65"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
