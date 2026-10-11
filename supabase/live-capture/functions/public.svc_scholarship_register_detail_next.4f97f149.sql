CREATE OR REPLACE FUNCTION public.svc_scholarship_register_detail_next(p_register text, p_limit integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then null else
  jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', x.listing_id, 'url', x.url, 'provider_ref', x.provider_ref,
                 'known_cricos', (select max(o.provider_cricos) from scholarship.register_listings o
                                   where o.register_code = x.register_code and o.provider_ref = x.provider_ref and o.provider_cricos is not null)))
               from (select l.* from scholarship.register_listings l
                      where l.register_code = p_register and l.departed_at is null
                        and (l.detail_read_at is null or l.detail_hash is distinct from l.content_hash)
                      order by (l.scholarship_id is not null), l.first_seen_at, l.listing_id
                      limit greatest(1, least(coalesce(p_limit, 40), 100))) x), '[]'::jsonb),
    'remaining', (select count(*) from scholarship.register_listings l
                   where l.register_code = p_register and l.departed_at is null
                     and (l.detail_read_at is null or l.detail_hash is distinct from l.content_hash))) end
$function$
