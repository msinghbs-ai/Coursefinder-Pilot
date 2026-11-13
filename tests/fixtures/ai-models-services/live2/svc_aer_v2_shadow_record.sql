CREATE OR REPLACE FUNCTION public.svc_aer_v2_shadow_record(p_course_id uuid, p_prompt_version text, p_model text, p_evidence_id uuid, p_content_hash text, p_records jsonb, p_checks jsonb, p_seen_not_mapped jsonb, p_cost_usd numeric, p_error text, p_worker text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_model text; v_prov uuid; v_pass int; v_fail int; v_id bigint;
        v_checks jsonb := case when jsonb_typeof(p_checks) = 'array' then p_checks else '[]'::jsonb end;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select x.model into v_model from pipeline.aer_prompt_versions x where x.version = p_prompt_version;
  if v_model is null then raise exception 'unknown AER prompt version %', p_prompt_version; end if;
  if p_model is distinct from v_model then raise exception 'model % is not the pinned model of %', p_model, p_prompt_version; end if;  -- pinned: no other model's answer is kept
  select c.provider_id into v_prov from catalogue.courses c where c.id = p_course_id;
  if v_prov is null then raise exception 'course % not found', p_course_id; end if;
  select count(*) filter (where coalesce((x->>'pass')::boolean, false)), count(*) filter (where not coalesce((x->>'pass')::boolean, false))
    into v_pass, v_fail from jsonb_array_elements(v_checks) x;
  -- shadow only: the result is kept here and nowhere else (no catalogue table, no Layer 4 item)
  insert into pipeline.aer_v2_shadow_results(prompt_version, model, course_id, provider_id, evidence_id, content_hash, records, checks, seen_not_mapped, passed, failed, cost_usd, error, worker)
  values (p_prompt_version, p_model, p_course_id, v_prov, p_evidence_id, p_content_hash,
          case when jsonb_typeof(p_records) = 'array' then p_records else '[]'::jsonb end, v_checks,
          case when jsonb_typeof(p_seen_not_mapped) = 'array' then p_seen_not_mapped else '[]'::jsonb end,
          v_pass, v_fail, greatest(coalesce(p_cost_usd, 0), 0), left(p_error, 400), left(p_worker, 40))  -- fixed: column display lengths
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'passed', v_pass, 'failed', v_fail);
end $function$
