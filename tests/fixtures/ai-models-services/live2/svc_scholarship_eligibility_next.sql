CREATE OR REPLACE FUNCTION public.svc_scholarship_eligibility_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- F-SCH.01: leases due reads for worker mode scholarship_eligibility with the pinned first model of the scholarship chain (the same model as the
-- re-check reader); held while sch_elig.on is 0 or the AI guards refuse (credit floor, daily ceiling, lane guard scholarship_ai).
declare v jsonb; v_model text; v_why text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('sch_elig.on', 0) < 1 then return jsonb_build_object('items', '[]'::jsonb, 'held', 'sch_elig.on is 0'); end if;
  v_why := security.ai_use_refusal_v1('scholarship_ai');
  if v_why is not null then return jsonb_build_object('items', '[]'::jsonb, 'held', v_why); end if;
  select m.model_identifier into v_model from pipeline.scholarship_ai_extract_settings s join pipeline.scholarship_ai_models m on m.code = s.chain[1] where s.id = 1;
  if v_model is null then return jsonb_build_object('items', '[]'::jsonb, 'held', 'no pinned model (scholarship_ai_extract_settings.chain)'); end if;
  with pick as (
    select e.candidate_id from pipeline.scholarship_eligibility_reads e
     where (e.state = 'queued' and coalesce(e.next_try_at, '-infinity') <= now()) or (e.state = 'leased' and e.leased_until < now())
     order by e.queued_at, e.candidate_id limit greatest(1, least(coalesce(p_limit, 10), 40))  -- fixed: the worker's upper bound per call
     for update skip locked),
  upd as (update pipeline.scholarship_eligibility_reads e set state = 'leased', leased_until = now() + interval '15 minutes', tries = e.tries + 1, updated_at = now()  -- fixed: lease timer
            from pick where e.candidate_id = pick.candidate_id returning e.candidate_id)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'url', coalesce(c.final_url, c.url), 'storage_path', c.storage_path, 'provider_id', c.provider_id,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = c.provider_id),
           'country', security.coverage_country(c.provider_id),
           'name', coalesce(nullif(btrim(c.facts->'admission'->>'name'), ''), nullif(btrim(c.facts->'ai'->>'name'), ''), c.title, ''),
           'model', v_model,
           'link_follow', security.pipeline_num_v1('sch_elig.link_follow_on', 1) >= 1,
           'links_max', security.pipeline_num_v1('sch_elig.links_max', 1)::int)), '[]'::jsonb)
    into v from upd u join pipeline.scholarship_page_candidates c on c.id = u.candidate_id;
  return jsonb_build_object('items', v);
end $function$
