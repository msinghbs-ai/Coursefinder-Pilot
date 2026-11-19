CREATE OR REPLACE FUNCTION security.provider_description_selection_multi_v1(p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ids uuid[]; v_cap int := security.provider_description_cohort_cap_v1(); v_fill text := coalesce(nullif(p_args->>'fill_mode', ''), 'missing'); v_id uuid;
  v_rows jsonb := '[]'::jsonb; v_one jsonb; v_f record; v_name text;
  -- the refresh of a basic profile is a Platform Admin policy switch (pdesc.registry_upgrade_on with machine admission); read here, never created here
  v_up_on boolean := security.pipeline_num_v1('pdesc.registry_upgrade_on', 0) >= 1 and security.pipeline_num_v1('pdesc.machine_admit_on', 0) >= 1;
begin
  if jsonb_typeof(p_args->'provider_ids') is distinct from 'array' then return security.provider_description_selection_v1(p_args); end if;
  select coalesce(array_agg(distinct e::uuid), array[]::uuid[]) into v_ids from jsonb_array_elements_text(p_args->'provider_ids') e;
  if cardinality(v_ids) < 1 or cardinality(v_ids) > v_cap then raise exception 'cohort size must be between 1 and %', v_cap using errcode = '22023'; end if;
  if v_fill not in ('missing', 'upgrade_basic') then raise exception 'unsupported fill mode' using errcode = '22023'; end if;
  for v_id in select unnest(v_ids) loop
    select f.description_filled, f.admission_state, f.source_tier into v_f from security.provider_catalogue_facts_v1(array[v_id], false) f;
    select coalesce(pp.display_name, pp.canonical_name) into v_name from catalogue.providers pp where pp.id = v_id;
    if v_name is null then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', null, 'name', null, 'eligible', false, 'eligibility_reason', 'unknown_provider', 'state', 'missing'));
    elsif exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = v_id and l.field in ('description', 'p_description', 'all')) then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', v_name, 'name', v_name, 'eligible', false, 'eligibility_reason', 'manual_lock', 'state', case when coalesce(v_f.description_filled, false) then 'admitted' else 'missing' end));
    elsif v_fill = 'missing' and coalesce(v_f.description_filled, false) then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', v_name, 'name', v_name, 'eligible', false, 'eligibility_reason', 'description_already_present', 'state', 'admitted'));
    elsif v_fill = 'upgrade_basic' and not (coalesce(v_f.description_filled, false) and v_f.admission_state = 'admitted' and v_f.source_tier = 'registry_factual') then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', v_name, 'name', v_name, 'eligible', false, 'eligibility_reason', 'not_a_basic_registry_profile', 'state', case when coalesce(v_f.description_filled, false) then 'admitted' else 'missing' end));
    elsif v_fill = 'upgrade_basic' and not v_up_on then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', v_name, 'name', v_name, 'eligible', false, 'eligibility_reason', 'upgrade_switched_off', 'state', 'admitted'));
    else
      v_one := security.provider_description_selection_v1((p_args - 'provider_ids' - 'fill_mode') || jsonb_build_object('provider_id', v_id, 'size', 1,
                 'description_state', case when v_fill = 'upgrade_basic' then 'stale' else 'missing' end, 'upgrade', v_fill = 'upgrade_basic'));
      if jsonb_array_length(coalesce(v_one->'providers', '[]'::jsonb)) = 0 then
        v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', v_name, 'name', v_name, 'eligible', false, 'eligibility_reason', 'not_selected_by_governed_policy', 'state', 'missing'));
      else
        v_rows := v_rows || (v_one->'providers');
      end if;
    end if;
  end loop;
  return jsonb_build_object('providers', v_rows, 'selected', (select count(*) from jsonb_array_elements(v_rows) x where (x->>'eligible')::boolean),
    'eligible', (select count(*) from jsonb_array_elements(v_rows) x where (x->>'eligible')::boolean), 'bounded', true, 'size', cardinality(v_ids), 'as_at', now(), 'fill_mode', v_fill,
    'exclusions', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', x->>'provider_id', 'provider', x->>'provider', 'reason', x->>'eligibility_reason')), '[]'::jsonb) from jsonb_array_elements(v_rows) x where not (x->>'eligible')::boolean));
end
$function$
