create or replace function public.ui_providers_page(
  p_limit integer default 50,
  p_offset integer default 0,
  p_query text default null
) returns jsonb
language sql
stable
security definer
set search_path = public, catalogue, ref, auth
as $function$
with filtered as (
  select
    p.id,
    p.stable_key,
    p.canonical_name,
    p.display_name,
    c.iso_alpha2::text as country_code,
    c.name as country_name,
    s.code as subdivision_code,
    s.name as subdivision_name,
    s.subdivision_type,
    p.primary_city as city,
    p.website,
    p.lifecycle_status,
    p.publication_status,
    count(cr.id)::bigint as course_count
  from catalogue.providers p
  join ref.countries c on c.id = p.country_id
  left join ref.subdivisions s on s.id = p.subdivision_id
  left join catalogue.courses cr on cr.provider_id = p.id
  where auth.uid() is not null
    and (
      nullif(trim(coalesce(p_query,'')), '') is null
      or coalesce(p.display_name,p.canonical_name,'') ilike '%' || trim(p_query) || '%'
      or coalesce(p.stable_key,'') ilike '%' || trim(p_query) || '%'
      or coalesce(p.primary_city,'') ilike '%' || trim(p_query) || '%'
      or coalesce(c.iso_alpha2::text,'') ilike '%' || trim(p_query) || '%'
      or coalesce(c.name,'') ilike '%' || trim(p_query) || '%'
      or coalesce(s.code,'') ilike '%' || trim(p_query) || '%'
      or coalesce(s.name,'') ilike '%' || trim(p_query) || '%'
    )
  group by p.id,c.iso_alpha2,c.name,s.code,s.name,s.subdivision_type
), numbered as (
  select *, count(*) over()::bigint as total_count
  from filtered
)
select jsonb_build_object(
  'items', coalesce(jsonb_agg(to_jsonb(n) - 'total_count' order by coalesce(n.display_name,n.canonical_name)), '[]'::jsonb),
  'total', coalesce(max(n.total_count),0),
  'limit', least(greatest(coalesce(p_limit,50),1),200),
  'offset', greatest(coalesce(p_offset,0),0)
)
from (
  select * from numbered
  order by coalesce(display_name,canonical_name)
  limit least(greatest(coalesce(p_limit,50),1),200)
  offset greatest(coalesce(p_offset,0),0)
) n;
$function$;
revoke all on function public.ui_providers_page(integer,integer,text) from public, anon;
grant execute on function public.ui_providers_page(integer,integer,text) to authenticated;
