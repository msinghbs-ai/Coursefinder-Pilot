-- CF-247 (16 Oct 2026): Zoho API v2 CSV export gives the sync cursor to continue from. Platform Admin decision 16 Oct 2026 "CSV seed + sync
-- feed": the CRM seeds from the CSV files, then keeps current with sync. Until now a CRM that seeded from CSV had no cursor except by
-- paging a full load. The export now returns sync_cursor (and the x-sync-cursor header): the change stream position when the file was read,
-- so sync from that cursor returns every change made after it.
-- Replaces: public.zoho_v2_export(text) without a cursor (now with sync_cursor; nothing else changes)
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.zoho_v2_export(text)": "079750fbebab885cfb5bc4abd43b9010"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION public.zoho_v2_export(p_entity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare q text := '"'; v_head text; v_csv text; v_n bigint;
        v_at bigint := (select coalesce(max(z.seq), 0) from pipeline.zoho_sync_items z);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if coalesce(p_entity, '') not in ('provider', 'campus', 'contact', 'course') then raise exception 'INVALID_INPUT: entity must be provider, campus, contact or course' using errcode = '22023'; end if;
  if p_entity = 'provider' then
    v_head := 'provider_id,cricos_provider_code,name,legal_name,institution_type,country_code,state,city,postcode,website,phone,email,course_count,campus_count,contact_count,qs_rank,the_rank,updated_at';
    select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'provider_id'), security.zoho_v2_csv_v1(i->>'cricos_provider_code'), security.zoho_v2_csv_v1(i->>'name'),
             security.zoho_v2_csv_v1(i->>'legal_name'), security.zoho_v2_csv_v1(i->'institution_type'->>'name'), security.zoho_v2_csv_v1(i->>'country_code'), security.zoho_v2_csv_v1(i->>'subdivision_code'),
             security.zoho_v2_csv_v1(i->>'city'), security.zoho_v2_csv_v1(i->>'postcode'), security.zoho_v2_csv_v1(i->>'website'), security.zoho_v2_csv_v1(i->>'phone'), security.zoho_v2_csv_v1(i->>'email'),
             security.zoho_v2_csv_v1(i->>'course_count'), security.zoho_v2_csv_v1(i->>'campus_count'), security.zoho_v2_csv_v1(i->>'contact_count'),
             security.zoho_v2_csv_v1(i->'ranking_summary'->'qs_wur'->>'rank_display'), security.zoho_v2_csv_v1(i->'ranking_summary'->'the_wur'->>'rank_display'), security.zoho_v2_csv_v1(i->>'updated_at')), E'\n' order by i->>'name', k)
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'provider' and z.removed_at is null and z.item is not null) x;
  elsif p_entity = 'campus' then
    v_head := 'campus_id,provider_id,cricos_provider_code,provider_name,name,address_line1,address_line2,city,state,postcode,country_code,latitude,longitude,metro_area,regional_category,course_count';
    select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'campus_id'), security.zoho_v2_csv_v1(i->>'provider_id'), security.zoho_v2_csv_v1(i->>'cricos_provider_code'),
             security.zoho_v2_csv_v1(i->>'provider_name'), security.zoho_v2_csv_v1(i->>'name'), security.zoho_v2_csv_v1(i->>'address_line1'), security.zoho_v2_csv_v1(i->>'address_line2'),
             security.zoho_v2_csv_v1(i->>'city'), security.zoho_v2_csv_v1(i->>'subdivision_code'), security.zoho_v2_csv_v1(i->>'postcode'), security.zoho_v2_csv_v1(i->>'country_code'),
             security.zoho_v2_csv_v1(i->>'latitude'), security.zoho_v2_csv_v1(i->>'longitude'), security.zoho_v2_csv_v1(i->>'metro_area'), security.zoho_v2_csv_v1(i->>'regional_category'),
             security.zoho_v2_csv_v1(i->>'course_count')), E'\n' order by i->>'provider_name', i->>'name', k)
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'campus' and z.removed_at is null and z.item is not null) x;
  elsif p_entity = 'contact' then
    v_head := 'contact_id,provider_id,cricos_provider_code,provider_name,type,name,title,team,email,phone,source,source_url,checked_at';
    select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'contact_id'), security.zoho_v2_csv_v1(i->>'provider_id'), security.zoho_v2_csv_v1(i->>'cricos_provider_code'),
             security.zoho_v2_csv_v1(i->>'provider_name'), security.zoho_v2_csv_v1(i->>'type'), security.zoho_v2_csv_v1(i->>'name'), security.zoho_v2_csv_v1(i->>'title'), security.zoho_v2_csv_v1(i->>'team'),
             security.zoho_v2_csv_v1(i->>'email'), security.zoho_v2_csv_v1(i->>'phone'), security.zoho_v2_csv_v1(i->>'source'), security.zoho_v2_csv_v1(i->>'source_url'), security.zoho_v2_csv_v1(i->>'checked_at')), E'\n' order by i->>'provider_name', i->>'type', k)
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'contact' and z.removed_at is null and z.item is not null) x;
  else
    v_head := 'course_id,cricos_course_code,title,provider_id,cricos_provider_code,provider_name,study_level,study_area,country_code,states,campus_cities,delivery_modes,duration_months,intake_months,ielts_overall,ielts_band,pte_overall,tuition_annual,tuition_currency,tuition_year,official_url,scholarship_count';
    select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'course_id'), security.zoho_v2_csv_v1(i->>'cricos_course_code'), security.zoho_v2_csv_v1(i->>'title'),
             security.zoho_v2_csv_v1(i->'provider'->>'provider_id'), security.zoho_v2_csv_v1(i->'provider'->>'cricos_provider_code'), security.zoho_v2_csv_v1(i->'provider'->>'name'),
             security.zoho_v2_csv_v1(i->'study_level'->>'name'), security.zoho_v2_csv_v1(i->'study_area'->>'name'), security.zoho_v2_csv_v1(i->>'country_code'),
             security.zoho_v2_csv_v1((select string_agg(x, '; ') from jsonb_array_elements_text(coalesce(i->'subdivision_codes', '[]'::jsonb)) x)),
             security.zoho_v2_csv_v1((select string_agg(distinct c->>'city', '; ') from jsonb_array_elements(coalesce(i->'campuses', '[]'::jsonb)) c)),
             security.zoho_v2_csv_v1((select string_agg(x, '; ') from jsonb_array_elements_text(coalesce(i->'delivery_modes', '[]'::jsonb)) x)),
             security.zoho_v2_csv_v1(i->>'duration_months'),
             security.zoho_v2_csv_v1((select string_agg(distinct coalesce(n->>'label', n->>'month'), '; ') from jsonb_array_elements(coalesce(i->'intakes', '[]'::jsonb)) n)),
             security.zoho_v2_csv_v1((select min(e->>'min_overall_score') from jsonb_array_elements(coalesce(i->'english_requirements', '[]'::jsonb)) e where e->>'test_code' = 'IELTS')),
             security.zoho_v2_csv_v1((select min(e->>'min_band_score') from jsonb_array_elements(coalesce(i->'english_requirements', '[]'::jsonb)) e where e->>'test_code' = 'IELTS')),
             security.zoho_v2_csv_v1((select min(e->>'min_overall_score') from jsonb_array_elements(coalesce(i->'english_requirements', '[]'::jsonb)) e where e->>'test_code' = 'PTE')),
             security.zoho_v2_csv_v1(i->'tuition'->>'annual_amount'), security.zoho_v2_csv_v1(i->'tuition'->>'currency'), security.zoho_v2_csv_v1(i->'tuition'->>'year'),
             security.zoho_v2_csv_v1(i->>'official_url'), security.zoho_v2_csv_v1(i->>'scholarship_count')), E'\n' order by i->'provider'->>'name', i->>'title', k)
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'course' and z.removed_at is null and z.item is not null) x;
  end if;
  return jsonb_build_object('api_version', 'zoho-v2', 'entity', p_entity, 'rows', coalesce(v_n, 0),
    'countries', coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb),
    'complete', (select s.last_cycle_at is not null from pipeline.zoho_sync_scan s where s.entity = p_entity),
    'sync_cursor', rtrim(translate(replace(encode(convert_to(jsonb_build_object('v', 1, 'm', 'delta', 'a', v_at,
                     'e', jsonb_build_array('provider', 'campus', 'contact', 'course'))::text, 'utf8'), 'base64'), E'\n', ''), '+/', '-_'), '='),
    'csv', v_head || E'\n' || coalesce(v_csv || E'\n', ''));
end $function$;

do $post$
declare v_expected jsonb := '{"public.zoho_v2_export(text)": "b25dd2caefc3828bd389b1482c094272"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'zoho export sync cursor post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
