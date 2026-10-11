CREATE OR REPLACE FUNCTION security.scholarship_coverage_row_v1(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with m as (select * from security.scholarship_listing_match_v1(p_provider_id)),
  recs as (select s.id, s.publication_status, s.source_url from scholarship.scholarships s where s.provider_id = p_provider_id and s.lifecycle_status = 'active'),
  lp as (select * from pipeline.scholarship_listing_pages l where l.provider_id = p_provider_id and l.active),
  chk as (select c.* from pipeline.scholarship_coverage_checks c where c.provider_id = p_provider_id),
  h as (select md5(coalesce(string_agg(lower(item_name), '|' order by lower(item_name)), '')) v from m)
  select jsonb_build_object(
    'provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'country', (select k.iso_alpha2 from ref.countries k where k.id = p.country_id),
    'watch', exists (select 1 from pipeline.scholarship_watch w where w.provider_id = p.id and w.active),
    'listing_pages', (select count(*) from lp where lp.source <> 'suggested'),
    'suggested_pages', (select count(*) from lp where lp.source = 'suggested'),
    'listing_read_at', (select max(lp.read_at) from lp where lp.source <> 'suggested'),
    'listed', (select count(*) from m),
    'found', (select count(*) from m where m.scholarship_id is not null),
    'published', (select count(*) from m join recs r on r.id = m.scholarship_id where r.publication_status = 'published'),
    'missing', (select count(*) from m where m.scholarship_id is null),
    'records', (select count(*) from recs),
    'records_published', (select count(*) from recs where publication_status = 'published'),
    'extra', (select count(*) from recs r where not exists (select 1 from m where m.scholarship_id = r.id)),
    'study_australia', (select count(*) from recs r where security.reference_url_has_use(coalesce(r.source_url, ''), 'scholarship_placeholder')),
    'checked_at', (select checked_at from chk), 'checked_by', (select u.email from chk join auth.users u on u.id = chk.checked_by),
    'state', case when not exists (select 1 from lp where lp.source <> 'suggested') then 'no_listing'
                  when not exists (select 1 from lp where lp.status = 'read') then 'waiting'
                  when not exists (select 1 from chk) then 'to_check'
                  when (select item_hash from chk) is distinct from (select v from h) then 'changed'
                  else 'checked' end)
  from catalogue.providers p where p.id = p_provider_id
$function$
