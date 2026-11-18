-- CF-247 (16 Oct 2026): Zoho API v2 CSV export in pages. Platform Admin decision 16 Oct 2026 "CSV seed + sync feed" (Dhivya, Zoho CRM:
-- "if the supabase database can be shared in CSV file (Australia only for now)"). The live check of the course file (26,103 rows, 7.7 MB)
-- answered 503: building it takes longer than the 8-second statement limit of the API. The export is now paged: each page is a complete
-- CSV file with the header, up to zoho.export_page_rows rows (3,000, about 0.9 MB), with page, pages, total_rows and has_more.
-- Replaces: public.zoho_v2_export(text) (whole file in one answer) with public.zoho_v2_export_page(text, integer); the edge function calls
--   the new one from this change
-- Retires: public.zoho_v2_export(text) (marked retiring; dropped by paste file after hygiene.retire_after_days)
-- Nothing dropped or deleted.

-- 1 Setting
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'zoho.export_page_rows', 'Zoho CSV export rows a page', 'Each export page is a complete CSV file with up to this many rows; larger entities come in several pages (page, pages, has_more). Kept so a page builds within the API time limit.', 'number', to_jsonb(3000), 500, 10000, 'rows', 809, 'CF-247 16 Oct 2026: the 26,103-row course file timed out in one answer', 'Zoho API', 'public.zoho_v2_export_page')
on conflict (toolset_key, key) do nothing;

-- 2 The paged export
CREATE OR REPLACE FUNCTION public.zoho_v2_export_page(p_entity text, p_page integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare q text := '"'; v_head text; v_csv text; v_n bigint;
        v_at bigint := (select coalesce(max(z.seq), 0) from pipeline.zoho_sync_items z);
        v_lim int := greatest(security.pipeline_num_v1('zoho.export_page_rows', 3000)::int, 1);
        v_off bigint; v_total bigint;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if coalesce(p_entity, '') not in ('provider', 'campus', 'contact', 'course') then raise exception 'INVALID_INPUT: entity must be provider, campus, contact or course' using errcode = '22023'; end if;
  if coalesce(p_page, 1) < 1 then raise exception 'INVALID_INPUT: page must be 1 or more' using errcode = '22023'; end if;
  v_off := (coalesce(p_page, 1) - 1)::bigint * v_lim;
  select count(*) into v_total from pipeline.zoho_sync_items z where z.entity = p_entity and z.removed_at is null and z.item is not null;
  if p_entity = 'provider' then
    v_head := 'provider_id,cricos_provider_code,name,legal_name,institution_type,country_code,state,city,postcode,website,phone,email,course_count,campus_count,contact_count,qs_rank,the_rank,updated_at';
    select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'provider_id'), security.zoho_v2_csv_v1(i->>'cricos_provider_code'), security.zoho_v2_csv_v1(i->>'name'),
             security.zoho_v2_csv_v1(i->>'legal_name'), security.zoho_v2_csv_v1(i->'institution_type'->>'name'), security.zoho_v2_csv_v1(i->>'country_code'), security.zoho_v2_csv_v1(i->>'subdivision_code'),
             security.zoho_v2_csv_v1(i->>'city'), security.zoho_v2_csv_v1(i->>'postcode'), security.zoho_v2_csv_v1(i->>'website'), security.zoho_v2_csv_v1(i->>'phone'), security.zoho_v2_csv_v1(i->>'email'),
             security.zoho_v2_csv_v1(i->>'course_count'), security.zoho_v2_csv_v1(i->>'campus_count'), security.zoho_v2_csv_v1(i->>'contact_count'),
             security.zoho_v2_csv_v1(i->'ranking_summary'->'qs_wur'->>'rank_display'), security.zoho_v2_csv_v1(i->'ranking_summary'->'the_wur'->>'rank_display'), security.zoho_v2_csv_v1(i->>'updated_at')), E'\n' order by i->>'name', k)
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'provider' and z.removed_at is null and z.item is not null
             order by z.item->>'name', z.item_key limit v_lim offset v_off) x;
  elsif p_entity = 'campus' then
    v_head := 'campus_id,provider_id,cricos_provider_code,provider_name,name,address_line1,address_line2,city,state,postcode,country_code,latitude,longitude,metro_area,regional_category,course_count';
    select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'campus_id'), security.zoho_v2_csv_v1(i->>'provider_id'), security.zoho_v2_csv_v1(i->>'cricos_provider_code'),
             security.zoho_v2_csv_v1(i->>'provider_name'), security.zoho_v2_csv_v1(i->>'name'), security.zoho_v2_csv_v1(i->>'address_line1'), security.zoho_v2_csv_v1(i->>'address_line2'),
             security.zoho_v2_csv_v1(i->>'city'), security.zoho_v2_csv_v1(i->>'subdivision_code'), security.zoho_v2_csv_v1(i->>'postcode'), security.zoho_v2_csv_v1(i->>'country_code'),
             security.zoho_v2_csv_v1(i->>'latitude'), security.zoho_v2_csv_v1(i->>'longitude'), security.zoho_v2_csv_v1(i->>'metro_area'), security.zoho_v2_csv_v1(i->>'regional_category'),
             security.zoho_v2_csv_v1(i->>'course_count')), E'\n' order by i->>'provider_name', i->>'name', k)
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'campus' and z.removed_at is null and z.item is not null
             order by z.item->>'provider_name', z.item->>'name', z.item_key limit v_lim offset v_off) x;
  elsif p_entity = 'contact' then
    v_head := 'contact_id,provider_id,cricos_provider_code,provider_name,type,name,title,team,email,phone,source,source_url,checked_at';
    select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'contact_id'), security.zoho_v2_csv_v1(i->>'provider_id'), security.zoho_v2_csv_v1(i->>'cricos_provider_code'),
             security.zoho_v2_csv_v1(i->>'provider_name'), security.zoho_v2_csv_v1(i->>'type'), security.zoho_v2_csv_v1(i->>'name'), security.zoho_v2_csv_v1(i->>'title'), security.zoho_v2_csv_v1(i->>'team'),
             security.zoho_v2_csv_v1(i->>'email'), security.zoho_v2_csv_v1(i->>'phone'), security.zoho_v2_csv_v1(i->>'source'), security.zoho_v2_csv_v1(i->>'source_url'), security.zoho_v2_csv_v1(i->>'checked_at')), E'\n' order by i->>'provider_name', i->>'type', k)
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'contact' and z.removed_at is null and z.item is not null
             order by z.item->>'provider_name', z.item->>'type', z.item_key limit v_lim offset v_off) x;
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
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'course' and z.removed_at is null and z.item is not null
             order by z.item->'provider'->>'name', z.item->>'title', z.item_key limit v_lim offset v_off) x;
  end if;
  return jsonb_build_object('api_version', 'zoho-v2', 'entity', p_entity, 'rows', coalesce(v_n, 0),
    'page', coalesce(p_page, 1), 'pages', greatest(ceil(v_total::numeric / v_lim), 1)::int, 'total_rows', v_total,
    'has_more', v_off + coalesce(v_n, 0) < v_total,
    'countries', coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb),
    'complete', (select s.last_cycle_at is not null from pipeline.zoho_sync_scan s where s.entity = p_entity),
    'sync_cursor', rtrim(translate(replace(encode(convert_to(jsonb_build_object('v', 1, 'm', 'delta', 'a', v_at,
                     'e', jsonb_build_array('provider', 'campus', 'contact', 'course'))::text, 'utf8'), 'base64'), E'\n', ''), '+/', '-_'), '='),
    'csv', v_head || E'\n' || coalesce(v_csv || E'\n', ''));
end $function$;;


revoke execute on function public.zoho_v2_export_page(text, integer) from public, anon, authenticated;

-- 3 Register
insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.zoho_v2_export_page(text, integer)', 'Zoho API', 'Zoho v2 CSV export, one page', 'active', '20261016040000'),
 ('function', 'public.zoho_v2_export(text)', 'Zoho API', 'Zoho v2 CSV export, whole file (timed out for courses)', 'active', '20261016020000')
on conflict (kind, name) do nothing;
update pipeline.component_register
   set status = 'retiring', replaced_by = 'public.zoho_v2_export_page(text, integer)', retire_after = current_date + 14, updated_at = now(),
       note = 'The whole-file export timed out for courses (16 Oct 2026); the edge function calls the paged export from 20261016040000'
 where kind = 'function' and name = 'public.zoho_v2_export(text)';

do $post$
begin
  if md5(replace(pg_get_functiondef('public.zoho_v2_export_page(text, integer)'::regprocedure), E'\r', '')) <> '96f8553017813c9329193aadc01279a8' then
    raise exception 'zoho export page post-check: definition not as intended (%)', md5(replace(pg_get_functiondef('public.zoho_v2_export_page(text, integer)'::regprocedure), E'\r', ''));
  end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'zoho.export_page_rows') then
    raise exception 'zoho export page post-check: setting missing';
  end if;
end $post$;
