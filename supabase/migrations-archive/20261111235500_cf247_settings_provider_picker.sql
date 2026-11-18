-- CF-247 F-OPS: Settings > Pipeline settings chooses providers by name (Platform Admin 11 Nov 2026 14:38 AEDT "RMIT added, there has to be better way in UI
-- rather that using the provider's ID, can you fix it?").
-- A list setting of provider ids (intake_dates.nearest_start_providers, coverage.aer_priority_providers, entry.course_read_providers and others) was typed as
-- comma-separated UUIDs. The screen now shows each chosen provider by name and finds providers to add by name. It needs one read:
--   public.admin_provider_pick_v1(p_query, p_ids): the names of the given provider ids, and up to 20 active providers whose name matches the search.
-- The value saved is unchanged: the same list of provider ids, written through admin_toolsets_write with a reason as before.
-- Guards: G1 (no job), G2 (no operational value: the 20 is a display page, marked fixed), G3 (no consumer API object: a new admin read), G4 (cf-247-s535).
-- Replaces: nothing.
-- Retires: nothing.
-- Reversal: drop the function by paste file.

create or replace function public.admin_provider_pick_v1(p_query text default null, p_ids uuid[] default null)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare v_rank int := security.current_role_rank();
        v_q text := nullif(btrim(coalesce(p_query, '')), '');
        v_like text;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  v_like := '%' || replace(replace(replace(coalesce(v_q, ''), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return jsonb_build_object(
    -- the providers already in the list, by name (archived ones too, so a stale id is still named)
    'named', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'country', c.iso_alpha2,
                                                           'archived', p.lifecycle_status = 'archived') order by coalesce(p.display_name, p.canonical_name)), '[]'::jsonb)
                from catalogue.providers p left join ref.countries c on c.id = p.country_id
               where p.id = any (coalesce(p_ids, '{}'))),
    -- providers to add: active, name or short name contains the search (two characters or more)
    'found', case when length(coalesce(v_q, '')) < 2 then '[]'::jsonb else
             (select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'name', z.name, 'country', z.country) order by z.rk, z.name), '[]'::jsonb)
                from (select p.id, coalesce(p.display_name, p.canonical_name) as name, c.iso_alpha2 as country,
                             case when lower(coalesce(p.short_name, '')) = lower(v_q) then 0
                                  when lower(coalesce(p.display_name, p.canonical_name)) like lower(v_q) || '%' then 1 else 2 end as rk
                        from catalogue.providers p left join ref.countries c on c.id = p.country_id
                       where p.lifecycle_status = 'active'
                         and (coalesce(p.display_name, p.canonical_name) ilike v_like escape '\' or p.canonical_name ilike v_like escape '\'
                              or coalesce(p.short_name, '') ilike v_like escape '\')
                       order by 4, 2
                       limit 20) z) end);  -- fixed: one display page of search results
end $function$;

comment on function public.admin_provider_pick_v1(text, uuid[]) is 'CF-247 F-OPS (11 Nov 2026): Settings > Pipeline settings provider picker. Names the provider ids of a list setting and finds active providers by name. Read only; role rank 3 or more.';
revoke all on function public.admin_provider_pick_v1(text, uuid[]) from public, anon;
grant execute on function public.admin_provider_pick_v1(text, uuid[]) to authenticated, service_role;

do $post$ begin
  if to_regprocedure('public.admin_provider_pick_v1(text,uuid[])') is null then raise exception 'post-check: admin_provider_pick_v1 missing'; end if;
end $post$;
