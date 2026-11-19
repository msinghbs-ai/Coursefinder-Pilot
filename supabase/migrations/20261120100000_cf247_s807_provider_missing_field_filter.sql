-- CF-247 S1-RM-Design (Platform Admin 20 Nov 2026 06:10, s807): Providers › Missing field filter (the UnoPim "find the incomplete records in one click" pattern).
-- security.admin_providers_page_v3 (behind admin_read operation providers_page) takes one more optional argument, read only and off when absent:
--   missing   a comma list of provider fields; the list keeps only providers that lack every field named. The fields are the nine that
--             security.provider_missing_fields_v1 reports: description, website, city, state_region, provider_type, phone, email, address, established_year.
-- The filter runs with the other filters on the provider's own columns, before the page is cut, so rows, total and Export CSV agree. An unknown field name
-- is refused with a plain message. Nothing else in the function changes; without the argument the result is identical. Not the consumer API (G3 stays 75
-- functions and 48 tables; no table, view or function is added, and nothing public changes).
-- The live definition was read on 20 Nov 2026 (md5 below); a changed definition stops this migration.
-- Replaces: the declare list, the filter checks and the candidate filter inside security.admin_providers_page_v3 (identical when no missing argument is sent)
-- Retires: nothing
set local lock_timeout = '5s';
do $r$
declare v_def text; v_new text; v_n int;
        a1 constant text := '  v_qset text[];';
        a2 constant text := '  if v_desc is not null and v_desc not in (''filled'',''missing'') then';
        a3 constant text := 'and (v_desc is null or (v_desc=''filled'')=(nullif(btrim(p.description),'''') is not null))';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'admin_providers_page_v3';
  if md5(v_def) is distinct from '789b1a5ceb4ee9fbcc770a9d65e31e39' then raise exception 'guard: security.admin_providers_page_v3 is not the definition this change was written against'; end if;
  foreach v_n in array array[(length(v_def) - length(replace(v_def, a1, ''))) / length(a1), (length(v_def) - length(replace(v_def, a2, ''))) / length(a2), (length(v_def) - length(replace(v_def, a3, ''))) / length(a3)] loop
    if v_n <> 1 then raise exception 'guard: an anchor of the providers page function is not found exactly once'; end if;
  end loop;
  v_new := replace(v_def, a1, a1 || E'\n  v_missing text[] := (select array_agg(distinct btrim(x)) from unnest(string_to_array(nullif(btrim(coalesce(p_args->>''missing'', '''')), ''''), '','')) x where btrim(x) <> '''');');
  v_new := replace(v_new, a2, '  if v_missing is not null and not (v_missing <@ array[''description'',''website'',''city'',''state_region'',''provider_type'',''phone'',''email'',''address'',''established_year'']) then raise exception ''unsupported missing-field filter: %'', array_to_string(v_missing, '','') using errcode = ''22023''; end if; -- fixed: the nine provider fields security.provider_missing_fields_v1 reports
' || a2);
  v_new := replace(v_new, a3, a3 || E'\n        and (v_missing is null or security.provider_missing_fields_v1(p) @> v_missing)');
  execute v_new;
end $r$;
do $c$
declare v_def text := pg_get_functiondef('security.admin_providers_page_v3(jsonb)'::regprocedure);
begin
  if v_def not like '%v_missing is null or security.provider_missing_fields_v1(p) @> v_missing%' then raise exception 'post-check: the providers page does not carry the missing-field filter'; end if;
  if v_def not like '%unsupported missing-field filter%' then raise exception 'post-check: the providers page does not refuse an unknown field'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'admin_providers_page_v3') <> 1 then raise exception 'post-check: the providers page function is not unique'; end if;
end $c$;
