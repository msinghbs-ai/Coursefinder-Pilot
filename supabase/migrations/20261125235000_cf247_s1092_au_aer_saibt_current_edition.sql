-- CF-247 s1092 — AU AER Steps 1-2: SAIBT source defect (S1-RM-Design, Platform Admin 24 Nov 2026 23:15; AER-FU-04).
-- The s1091 SAIBT v12.0 PDF now answers 404 (gone); the college publishes v12.1 at the same location.
-- Registers the current edition through pipeline.entry_matrix_sources; the existing entry-matrix-read job fetches it. No reader, rule, cron or setting change.
-- Replaces: none. Retires: none.
with rows(provider_id, url, title) as (
 values ('c001e5eb-bb39-4bf9-8284-ad13b7dd912f'::uuid,'https://saibt.sa.edu.au/wp-content/uploads/admissions-entry-criteria-v12.1_public.pdf','SAIBT academic entry criteria by country (v12.1)')
)
insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
select r.provider_id, r.url, r.title, 1, 'manual' from rows r
join catalogue.providers p on p.id = r.provider_id
join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
on conflict (provider_id, url) do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'aer', 'au_source_defect_saibt_v121', 'pipeline.entry_matrix_sources',
       jsonb_build_object('spec', 's1092', 'reason', 'AER-FU-04: v12.0 URL gone (404); current edition v12.1 registered; no extraction or admission change'),
       auth.uid()
where not exists (select 1 from pipeline.admin_control_events e where e.area='aer' and e.action='au_source_defect_saibt_v121' and e.detail->>'spec'='s1092');
