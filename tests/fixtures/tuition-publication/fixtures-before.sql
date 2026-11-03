-- IQ-00116 reproduced on the live definitions (before the migration): two Layer 4 tuition approvals on coverage-sweep sources that no fee
-- writer had opened (as ACTS 2772 and Employment Focus 2540 on 30 Oct 2026) reach the catalogue and the fee rule Zoho reads, but not the
-- projection the website reads; an approval on an already-open source is published (control).
\i tests/fixtures/tuition-publication/helpers.sql
insert into pipeline.sources(id, source_type, label) values (pg_temp.u('src gated'), 'provider_course_page_sweep', 'gated course pages');
insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref) values ('courses', 'provider_current_tuition', pg_temp.u('src gated'), 'approved', 'AI fee reader');
select pg_temp.course('nz acts', 'NZ', 'acts'), pg_temp.course('nz ef', 'NZ', 'ef'), pg_temp.course('au gated', 'AU', 'gated');
select pg_temp.approve('nz acts', '{"amount": 7500, "currency_code": "NZD", "basis": "annual", "fee_year": 2026}', interval '5 days');
select pg_temp.approve('nz ef', '{"amount": 14000, "currency_code": "NZD", "basis": "annual", "fee_year": 2024}', interval '5 days');
select pg_temp.approve('au gated', '{"amount": 30000, "currency_code": "AUD", "basis": "annual", "fee_year": 2026}', interval '5 days');
-- a Layer 2 page fee (no Layer 4 approval) on a source never opened, as Federation University 119893C (the rule Zoho reads uses it; the website does not)
select pg_temp.course('au fed', 'AU', 'fed');
insert into catalogue.course_fees(course_id, status, fee_type, audience, amount, fee_year, currency_code, basis, source_id, evidence_id, notes)
values (pg_temp.u('au fed'), 'active', 'provider_current_tuition', 'international', 38900, 2026, 'AUD', 'current indicative annual international tuition', pg_temp.u('src fed'),
        pg_temp.u('ev au fed'), 'Applied only after Layer 2 deterministic fee safety guard');
select search.refresh_course_enrichment_scoped_v1(array[pg_temp.u('au fed')], true);

do $$ begin
  perform pg_temp.ok(exists (select 1 from catalogue.course_fees where course_id = pg_temp.u('nz acts') and status = 'active' and amount = 7500), 'live: the approved fee is in the catalogue (ACTS-like)');
  perform pg_temp.ok(security.course_fee_used_v1(pg_temp.u('nz acts'))->>'source' = 'page' and (security.course_fee_used_v1(pg_temp.u('nz acts'))->>'per_year')::numeric = 7500,
                     'live: the fee rule Zoho reads uses it (page, 7,500)');
  perform pg_temp.ok(not pg_temp.has_fee('nz acts') and not pg_temp.has_fee('nz ef'), 'live: the projection the website reads has no fee for either approval (the mismatch)');
  perform pg_temp.ok((select generated_at from search.course_documents where course_id = pg_temp.u('nz acts')) is not null, 'live: the projection row was rebuilt by the apply (not stale)');
  perform pg_temp.ok(pg_temp.check_of('nz acts') = 'admitted_not_published:projection_has_no_fee' and pg_temp.check_of('nz ef') = 'admitted_not_published:projection_has_no_fee',
                     'live: the admission check records admitted_not_published / projection_has_no_fee (IQ-00116 fingerprint)');
  perform pg_temp.ok(not exists (select 1 from search.enrichment_source_gates where source_id in (pg_temp.u('src acts'), pg_temp.u('src ef'))), 'live: the apply opened no source gate');
  perform pg_temp.ok(pg_temp.has_fee('au gated') and pg_temp.check_of('au gated') = 'admitted_published:', 'live: an approval on an open source is published (control)');
  perform pg_temp.ok(not pg_temp.has_fee('au fed') and security.course_fee_used_v1(pg_temp.u('au fed'))->>'source' = 'page', 'live: the Layer 2 fee on a closed source is in Zoho''s rule only');
end $$;
