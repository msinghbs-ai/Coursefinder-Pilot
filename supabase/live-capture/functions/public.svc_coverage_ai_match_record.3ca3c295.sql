CREATE OR REPLACE FUNCTION public.svc_coverage_ai_match_record(p_id bigint, p_url text, p_answer jsonb, p_model text, p_cost numeric, p_error text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare q pipeline.coverage_ai_match%rowtype; v_state text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.coverage_ai_match where id = p_id for update;
  if q.id is null or q.state <> 'leased' then return 'not_leased'; end if;
  if p_error ~ '^HTTP (401|402|403|429)\M' or p_error = 'time budget' then
    update pipeline.coverage_ai_match set state = 'ready', leased_until = null where id = p_id;
    return 'released';
  end if;
  if p_error is not null then
    v_state := 'error';
  elsif p_url is null then
    v_state := 'none';
  elsif not exists (select 1 from jsonb_array_elements(q.candidates) x where x->>'url' = p_url) then
    v_state := 'error'; p_answer := coalesce(p_answer, '{}'::jsonb) || jsonb_build_object('refused', 'chosen address is not one of the candidates');
  else
    v_state := 'chosen';
    insert into pipeline.coverage_course_pages(course_id, provider_id, url, score, runner_up, basis, status, bound_at, next_read_at, read_attempts)
    values (q.course_id, q.provider_id, p_url, null, null, 'ai_match', 'bound', now(), now(), 0)
    on conflict (course_id) do update set url = excluded.url, score = null, runner_up = null, basis = 'ai_match', status = 'bound', bound_at = now(),
           next_read_at = now(), read_attempts = 0, read_status = null, identity_basis = null, leased_until = null
     where (pipeline.coverage_course_pages.status = 'mismatch' or pipeline.coverage_course_pages.basis = 'ai_match')
       and coalesce(pipeline.coverage_course_pages.basis, '') <> 'manual';
  end if;
  update pipeline.coverage_ai_match set state = v_state, chosen_url = case when v_state = 'chosen' then p_url end, answer = coalesce(p_answer, '{}'::jsonb) || case when p_error is not null then jsonb_build_object('error', left(p_error, 300)) else '{}'::jsonb end,
         model = p_model, cost_usd = p_cost, decided_at = now(), leased_until = null
   where id = p_id;
  return v_state;
end $function$
