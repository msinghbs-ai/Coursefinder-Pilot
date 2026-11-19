create or replace function public.ui_provider_filter_options(p_country_code text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, ref, catalogue, auth
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  return jsonb_build_object(
    'countries', (
      select coalesce(jsonb_agg(jsonb_build_object('code', c.iso_alpha2::text, 'name', c.name) order by c.name), '[]'::jsonb)
      from ref.countries c
      where exists (select 1 from catalogue.providers p where p.country_id = c.id)
    ),
    'subdivisions', (
      select coalesce(jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name, 'type', s.subdivision_type) order by s.name), '[]'::jsonb)
      from ref.subdivisions s
      join ref.countries c on c.id = s.country_id
      where (nullif(trim(coalesce(p_country_code,'')),'') is null or c.iso_alpha2::text = upper(trim(p_country_code)))
        and exists (
          select 1 from catalogue.providers p where p.subdivision_id = s.id
        )
    )
  );
end;
$$;
revoke all on function public.ui_provider_filter_options(text) from public, anon;
grant execute on function public.ui_provider_filter_options(text) to authenticated;
