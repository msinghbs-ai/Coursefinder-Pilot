CREATE OR REPLACE FUNCTION security.scholarship_listing_match_v1(p_provider_id uuid)
 RETURNS TABLE(listing_id bigint, item_name text, item_url text, scholarship_id uuid, matched_by text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with items as (
    select distinct on (lower(btrim(e->>'name'))) l.id listing_id, btrim(e->>'name') item_name, nullif(btrim(e->>'url'), '') item_url
      from pipeline.scholarship_listing_pages l, jsonb_array_elements(l.items) e
     where l.provider_id = p_provider_id and l.active and l.source <> 'suggested' and coalesce(btrim(e->>'name'), '') <> ''
     order by lower(btrim(e->>'name')), (nullif(btrim(e->>'url'), '') is null), l.id),
  recs as (
    select s.id, s.name, s.publication_status, security.scholarship_series_key_v1(s.name) k,
           array_remove(array[security.scholarship_url_norm(s.source_url)]
             || array(select security.scholarship_url_norm(i.identifier_value) from scholarship.identifiers i where i.scholarship_id = s.id and i.scheme = 'first_party_detail_url')
             || array(select security.scholarship_url_norm(coalesce(sp.final_url, sp.url)) from pipeline.scholarship_pages sp where sp.scholarship_id = s.id)
             || array(select security.scholarship_url_norm(sp.url) from pipeline.scholarship_pages sp where sp.scholarship_id = s.id), null) urls
      from scholarship.scholarships s where s.provider_id = p_provider_id and s.lifecycle_status = 'active')
  select it.listing_id, it.item_name, it.item_url, m.id, m.how
    from items it
    cross join lateral (select security.scholarship_series_key_v1(it.item_name) ik, security.scholarship_url_norm(it.item_url) iu) x
    left join lateral (
      select r.id, case when x.iu is not null and x.iu = any(r.urls) then 'page' when r.k = x.ik then 'name' else 'similar name' end how
        from recs r
       where (x.iu is not null and x.iu = any(r.urls))
          or r.k = x.ik
          or (length(x.ik) >= 15 and length(r.k) >= 15 and (strpos(r.k, x.ik) > 0 or strpos(x.ik, r.k) > 0))
       order by (x.iu is not null and x.iu = any(r.urls)) desc, (r.k = x.ik) desc, (r.publication_status = 'published') desc, r.id
       limit 1) m on true
$function$
