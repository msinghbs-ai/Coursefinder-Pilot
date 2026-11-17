-- CF-247 UI audit, new API v3 fields (Platform Admin 17 Nov 2026 23:05, chat S1-RM-Design): read-only, searchable views of two reference tables
-- on Reference data: the API field dictionary (ref.api_field_dictionary) and the grade scale conversions (ref.grade_scale_conversions).
-- One read function for Curator and above. It reads the two tables and changes nothing; no consumer API object is altered.
-- Replaces: nothing
-- Retires: nothing

do $pre$ begin
  if to_regclass('ref.api_field_dictionary') is null or to_regclass('ref.grade_scale_conversions') is null or to_regclass('ref.countries') is null
     or to_regclass('pipeline.platform_toolset_settings') is null or to_regprocedure('security.pipeline_num_v1(text,numeric)') is null
     or to_regprocedure('security.current_role_rank()') is null then
    raise exception 'an object this change builds on is missing';
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'admin.reference_table_page_rows', 'Reference data: rows per page',
  'How many rows the API field dictionary and Grade scale conversions lists show at a time.',
  'number', to_jsonb(50), 10, 200, 'rows', 3270, 'Reference tables on Reference data (Platform Admin 17 Nov 2026 23:05)', 'Reference data', 'public.admin_reference_table_read')
on conflict (toolset_key, key) do nothing;

create or replace function public.admin_reference_table_read(p_kind text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a jsonb := coalesce(p_args, '{}'::jsonb); v_q text := nullif(btrim(coalesce(a->>'query', '')), ''); v_like text;
        v_page int := greatest(1, security.pipeline_num_v1('admin.reference_table_page_rows', 50)::int);
        v_off int := greatest(0, coalesce(nullif(a->>'offset', '')::int, 0));
        v_surface text := nullif(a->>'surface', ''); v_version text := nullif(a->>'version', ''); v_country text := upper(nullif(a->>'country', '')); v_active text := nullif(a->>'active', '');
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator (rank 3) or above is needed for Reference data' using errcode = '42501'; end if; -- fixed: who opens Reference data
  if length(v_q) > 120 then raise exception 'the search text is too long (120 characters at most)' using errcode = '22023'; end if; -- fixed: input-safety bound
  -- what was typed is matched as text: % and _ are not wildcards
  v_like := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  if p_kind = 'api_fields' then
    return (
      with f as (select d.* from ref.api_field_dictionary d
                  where (v_surface is null or d.api_surface = v_surface) and (v_version is null or d.version = v_version)
                    and (v_q is null or d.field_path ilike v_like or d.endpoint ilike v_like or d.description ilike v_like or d.source_table ilike v_like
                         or d.source_column ilike v_like or array_to_string(d.req_ids, ' ') ilike v_like))
      select jsonb_build_object('kind', 'api_fields', 'total', (select count(*) from f), 'all_rows', (select count(*) from ref.api_field_dictionary), 'page_rows', v_page, 'offset', v_off,
        'filters', jsonb_build_object(
          'surfaces', (select coalesce(jsonb_agg(s order by s), '[]'::jsonb) from (select distinct d.api_surface s from ref.api_field_dictionary d where d.api_surface is not null) x),
          'versions', (select coalesce(jsonb_agg(s order by s), '[]'::jsonb) from (select distinct d.version s from ref.api_field_dictionary d where d.version is not null) x)),
        'rows', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
           select f.api_surface, f.version, f.endpoint, f.field_path, f.data_type, f.is_nullable, f.allowed_values, f.req_ids, f.source_table, f.source_column, f.description,
                  f.example_value, f.introduced_in, f.deprecated_in, f.updated_at
             from f order by f.api_surface, f.version, f.endpoint, f.field_path limit v_page offset v_off) x)));
  elsif p_kind = 'grade_scales' then
    return (
      with f as (select g.*, c.iso_alpha2 country_code, c.name country_name from ref.grade_scale_conversions g left join ref.countries c on c.id = g.country_id
                  where (v_country is null or c.iso_alpha2 = v_country) and (v_active is null or g.is_active = (v_active = 'true'))
                    and (v_q is null or g.qualification_name ilike v_like or g.qualification_code ilike v_like or g.board_or_stream ilike v_like or g.scale_code ilike v_like
                         or g.raw_grade_label ilike v_like or c.name ilike v_like))
      select jsonb_build_object('kind', 'grade_scales', 'total', (select count(*) from f), 'all_rows', (select count(*) from ref.grade_scale_conversions), 'page_rows', v_page, 'offset', v_off,
        'filters', jsonb_build_object(
          'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', x.code, 'name', x.name) order by x.name), '[]'::jsonb)
                          from (select distinct c.iso_alpha2 code, c.name from ref.grade_scale_conversions g join ref.countries c on c.id = g.country_id) x)),
        'rows', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
           select f.country_code, f.country_name, f.qualification_code, f.qualification_name, f.board_or_stream, f.scale_code, f.raw_min_value, f.raw_max_value, f.raw_grade_label,
                  f.normalized_0_100, f.is_active, f.source_url, f.notes, f.updated_at
             from f order by f.country_name nulls last, f.qualification_name, f.board_or_stream nulls first, f.raw_max_value desc nulls last limit v_page offset v_off) x)));
  end if;
  raise exception 'unknown reference table %', coalesce(p_kind, '(none)') using errcode = '22023';
end $$;
comment on function public.admin_reference_table_read(text, jsonb) is 'Reference data: read-only, searchable pages of the API field dictionary (api_fields) and the grade scale conversions (grade_scales). Curator and above. Changes nothing.';
revoke all on function public.admin_reference_table_read(text, jsonb) from public, anon;
grant execute on function public.admin_reference_table_read(text, jsonb) to authenticated;

do $post$ begin
  if has_function_privilege('anon', 'public.admin_reference_table_read(text, jsonb)', 'execute') then raise exception 'post-check: anon can run the reference table read'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'admin.reference_table_page_rows') then raise exception 'post-check: the page size setting is missing'; end if;
end $post$;
