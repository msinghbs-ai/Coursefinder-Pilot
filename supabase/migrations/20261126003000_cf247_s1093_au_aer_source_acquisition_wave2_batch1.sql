-- CF-247 s1093 — AU AER Steps 1-2, Wave 2 Batch 1 (S1-RM-Design, Platform Admin 24 Nov 2026 23:31; AER-FU-04).
-- Registers one official by-country academic entry source (Kent Institute Australia, "Academic Entry Equivalences (Country Specific)" PDF)
-- through pipeline.entry_matrix_sources; the existing entry-matrix-read job fetches and stores it. No reader, rule, cron, setting or admission change.
-- Replaces: none. Retires: none.
with rows(provider_id, url, title) as (
 values ('b3d3ae78-318c-4061-b19a-a734b86c9f85'::uuid,'https://kent.edu.au/wp-content/uploads/DOC-Academic-Entry-Equivalences.pdf','Kent academic entry equivalences by country (PDF)')
)
insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
select r.provider_id, r.url, r.title, 1, 'manual' from rows r
join catalogue.providers p on p.id = r.provider_id
join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
on conflict (provider_id, url) do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'aer', 'au_source_wave2_batch1_register', 'pipeline.entry_matrix_sources',
       jsonb_build_object('spec', 's1093', 'providers_attempted', 15, 'sources_registered', 1,
         'reason', 'AER-FU-04: AU source acquisition; no extraction, admission or rule change'),
       auth.uid()
where not exists (select 1 from pipeline.admin_control_events e where e.area='aer' and e.action='au_source_wave2_batch1_register' and e.detail->>'spec'='s1093');
