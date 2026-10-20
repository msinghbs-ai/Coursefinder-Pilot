CREATE OR REPLACE FUNCTION public.svc_enrich_ai_record(p_results jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb; i pipeline.field_enrich_items%rowtype; v_val jsonb; v_out jsonb := '{}'::jsonb; v_k text; v_ev uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    select * into i from pipeline.field_enrich_items where id = (r->>'item_id')::bigint for update;
    if i.id is null then continue; end if;
    v_ev := i.evidence_id;
    if r->>'storage_path' is not null then
      insert into pipeline.evidence_artifacts(source_id, evidence_type, source_url, storage_path, content_hash, mime_type, metadata, capture_version, evidence_group_key)
      values (security.coverage_sweep_source(i.provider_id), 'enrich_home_page', r->>'url', r->>'storage_path', r->>'sha256', 'application/gzip',
              jsonb_build_object('item_id', i.id, 'provider_id', i.provider_id, 'worker', 'coverage-sweep enrich_ai'), 1, 'enrich:' || i.id)
      returning id into v_ev;
    end if;
    update pipeline.field_enrich_items set cost_usd = coalesce(cost_usd, 0) + coalesce((r->>'cost')::numeric, 0), evidence_id = v_ev,
           storage_path = coalesce(r->>'storage_path', storage_path), leased_until = null, updated_at = now() where id = i.id;
    if r->>'retry' = 'true' then
      update pipeline.field_enrich_items set state = case when attempts >= 3 then 'failed' else 'ai' end, reason = left(r->>'reason', 300) where id = i.id;
      v_k := 'retry';
    elsif r->>'error' is not null then
      update pipeline.field_enrich_items set state = case when attempts >= 3 then 'failed' else 'ai' end, reason = left(r->>'error', 300) where id = i.id;
      v_k := 'error';
    elsif i.field = 'campus' then
      if nullif(btrim(r->'value'->>'campus'), '') is not null then
        update pipeline.field_enrich_items set state = 'waiting', quote = left(r->'value'->>'campus', 300) where id = i.id; v_k := 'campus_named';
      else
        update pipeline.field_enrich_items set state = 'skipped', reason = 'the page names no campus' where id = i.id; v_k := 'not_stated';
      end if;
    elsif i.field = 'campus_list' then
      update pipeline.field_enrich_items set value = jsonb_build_object('campuses', coalesce(r->'value'->'campuses', '[]'::jsonb)), quote = left(r->>'quote', 300) where id = i.id;
      v_k := 'campus_list'; perform security.enrich_campus_list_apply_v1(i.id);
    else
      v_val := case i.field
        when 'duration' then security.enrich_parse_duration_v1(r->>'quote')
        when 'delivery' then (select jsonb_build_object('mode', r->'value'->>'mode') where r->'value'->>'mode' in ('on_campus', 'online', 'blended', 'on_campus_and_online'))
        when 'level' then (select jsonb_build_object('level_id', l.id) from ref.study_levels l where l.short_code = r->'value'->>'level')
        when 'field_of_study' then (select jsonb_build_object('field_id', f.id) from ref.fields_of_study f where f.code = r->'value'->>'field' and f.code ~ '^asced-\d{4}$')
        when 'international' then (select jsonb_build_object('open', (r->'value'->>'open')::boolean) where r->'value'->>'open' in ('true', 'false'))
        when 'provider_address' then (select r->'value' where nullif(btrim(r->'value'->>'street'), '') is not null)
        when 'campus' then null end;
      if v_val is null then
        update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(nullif(r->>'reason', ''), 'the page does not state it') where id = i.id;
        v_k := 'not_stated';
      else
        update pipeline.field_enrich_items set value = v_val, quote = left(coalesce(r->>'quote', i.quote), 300) where id = i.id;
        v_k := security.enrich_apply_v1(i.id);
      end if;
    end if;
    v_out := v_out || jsonb_build_object(v_k, coalesce((v_out->>v_k)::int, 0) + 1);
  end loop;
  return v_out;
end $function$
