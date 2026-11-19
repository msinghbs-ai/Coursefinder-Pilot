-- CF-247 S1-RM-Design (Platform Admin 19 Nov 2026 16:18, s767): Layer 4 Review › Grid filters by Country and Provider type as well as kind and reason.
-- public.admin_layer4_grid_read_v1 takes two more optional arguments, both read only and both off when absent (the grid is unchanged without them):
--   country        an ISO country code of a provider (AU, NZ, CA); checked against ref.countries
--   provider_type  one of the four groups the screen offers: university (university, university_college, wananga), hei (higher_education_institute),
--                  vet_college (tafe_polytechnic, private_vet), school (school). The retired types and the register type "other" belong to no group;
--                  they show under All.
-- The rows and the total both follow the filters (the filter runs before the page is cut). An item that has no provider (a platform item) is left out
-- when either filter is set. Nothing else in the function changes. Not the consumer API (G3 stays 75 functions and 48 tables; no table or function is added).
-- The live definition was read on 19 Nov 2026 (md5 below); a changed definition stops this migration.
-- Replaces: the argument list and the provider join filter inside public.admin_layer4_grid_read_v1 (identical when neither filter is sent)
-- Retires: nothing
set local lock_timeout = '5s';
do $r$
declare v_def text; v_new text; v_n int;
        a1 constant text := 'v_q text := nullif(btrim(a->>''q''), '''');';
        a2 constant text := 'if length(coalesce(v_why, '''')) > 80 or length(coalesce(v_q, '''')) > 80 then';
        a3 constant text := 'where v_q is null or i.subject ilike ''%'' || v_q || ''%'' or coalesce(p.display_name, p.canonical_name, '''') ilike ''%'' || v_q || ''%''),';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'admin_layer4_grid_read_v1';
  if md5(v_def) is distinct from '3bbc37e32eb9ae7fe5e63cd7ea216c16' then raise exception 'guard: public.admin_layer4_grid_read_v1 is not the definition this change was written against'; end if;
  foreach v_n in array array[(length(v_def) - length(replace(v_def, a1, ''))) / length(a1), (length(v_def) - length(replace(v_def, a2, ''))) / length(a2), (length(v_def) - length(replace(v_def, a3, ''))) / length(a3)] loop
    if v_n <> 1 then raise exception 'guard: an anchor of the grid function is not found exactly once'; end if;
  end loop;
  v_new := replace(v_def, a1, a1 || E'\n        v_cty text := nullif(upper(btrim(a->>''country'')), ''''); v_pt text := nullif(btrim(a->>''provider_type''), '''');');
  v_new := replace(v_new, a2, 'if v_cty is not null and not exists (select 1 from ref.countries c where c.iso_alpha2::text = v_cty) then raise exception ''country must be a country code such as AU, NZ or CA'' using errcode = ''22023''; end if;
  if v_pt is not null and v_pt <> all (array[''university'', ''hei'', ''vet_college'', ''school'']) then raise exception ''provider_type must be university, hei, vet_college or school'' using errcode = ''22023''; end if; -- fixed: the four groups the screen offers
  ' || a2);
  v_new := replace(v_new, a3, 'where (v_q is null or i.subject ilike ''%'' || v_q || ''%'' or coalesce(p.display_name, p.canonical_name, '''') ilike ''%'' || v_q || ''%'')
                  and (v_cty is null or k.iso_alpha2::text = v_cty)
                  and (v_pt is null or exists (select 1 from ref.provider_types t where t.id = p.provider_type_id and t.code = any(case v_pt
                         when ''university'' then array[''university'', ''university_college'', ''wananga'']
                         when ''hei'' then array[''higher_education_institute'']
                         when ''vet_college'' then array[''tafe_polytechnic'', ''private_vet'']
                         else array[''school''] end)))), '); -- fixed: the four groups as the register types classify them (Decision 258)
  execute v_new;
end $r$;
comment on function public.admin_layer4_grid_read_v1(jsonb) is 'CF-247 Phase 5 (18 Nov 2026), s767 (19 Nov 2026): one built-in Layer 4 kind as grid rows, paged on the server (layer4.inbox_page_size), with reason filter, search, country and provider type filters and sort; a CSV export reads up to layer4.grid_export_max_rows. Read only. Curator and above.';
do $c$
declare v_def text := pg_get_functiondef('public.admin_layer4_grid_read_v1(jsonb)'::regprocedure);
begin
  if v_def not like '%v_cty text%' or v_def not like '%k.iso_alpha2::text = v_cty%' or v_def not like '%v_pt <> all%' or v_def not like '%''tafe_polytechnic'', ''private_vet''%' then raise exception 'post-check: the grid function does not carry the two filters'; end if;
  if v_def not like '%offset v_off%' or v_def not like '%security.layer4_inbox_items_v2(v_prov, v_kind, null, false)%' then raise exception 'post-check: the grid function lost its paging or its item source'; end if;
  if not exists (select 1 from ref.provider_types where code in ('university', 'university_college', 'wananga', 'higher_education_institute', 'tafe_polytechnic', 'private_vet', 'school') having count(*) = 7) then raise exception 'post-check: a register type named by the groups is missing'; end if;
end $c$;
