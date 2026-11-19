-- CF-247: 137 New Zealand provider websites were stored as "https://https://www..." (the NZ register load rewrote a
-- leading "http://" to "https://" on links that already carried "https://"), so their sites could not be mapped and
-- course-page discovery failed with "no course-like pages found". This removes the repeated
-- scheme from catalogue.providers.website and from the discovery queue's copy, and returns those NZ providers to the
-- queue as pending with their attempts reset. No website was locked by a person (pipeline.manual_locks has none for
-- these providers), so nothing entered by hand is changed. The loader itself is fixed separately (layer1-nz-live).

update catalogue.providers p
   set website = regexp_replace(p.website, '^(https?://)+', 'https://', 'i'), updated_at = now()
  from ref.countries k
 where k.id = p.country_id and k.iso_alpha2 = 'NZ' and p.website ~* '^https?://https?://'
   and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field = 'website');

update pipeline.coverage_provider_discovery d
   set website = p.website,
       status = case when d.status in ('failed','pending') then 'pending' else d.status end,
       attempts = case when d.status in ('failed','pending') then 0 else d.attempts end,
       last_error = case when d.status in ('failed','pending') then null else d.last_error end,
       leased_until = null, next_due_at = null, updated_at = now()
  from catalogue.providers p join ref.countries k on k.id = p.country_id
 where p.id = d.provider_id and k.iso_alpha2 = 'NZ'
   and (d.website ~* '^https?://https?://' or (d.status = 'failed' and d.last_error = 'no course-like pages found' and d.website is distinct from p.website));
