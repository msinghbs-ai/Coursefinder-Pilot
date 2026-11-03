-- AER missing-university cases after 20261104090000 (applied twice). Each block raises 'FAIL: ...' on the first broken expectation.

-- M1 the inventory: eight universities, exact verified URLs only, no URL for a blocked site, attachment only for verified readable pages
do $$
begin
  perform fx.ok((select count(distinct provider_id) from pipeline.aer_source_inventory) = 8, 'M1 eight universities');
  perform fx.ok((select url from pipeline.aer_source_inventory where provider_id = 'c5c5d225-3d4c-4e41-8275-78eddd261073') is null
                and (select outcome from pipeline.aer_source_inventory where provider_id = 'c5c5d225-3d4c-4e41-8275-78eddd261073') = 'blocked_site', 'M1 Deakin: blocked, no URL invented');
  perform fx.ok((select array_agg(provider_id::text order by provider_id) from pipeline.aer_source_inventory where attach) =
                array['551383f9-7732-4588-a843-dd2b97c13f6f','6f5cb7f7-7c70-4c06-970f-f368c3a786e2','fa0e0d13-838a-42ff-b6a3-9cea84bd80b2','fec52f92-a8a3-4de8-a862-06f355e4e2f7'], 'M1 attach CDU, UniSQ, UNE, Torrens');
  perform fx.ok(not exists (select 1 from pipeline.aer_source_inventory where attach and outcome not in ('verified_attachable', 'verified_general_only')), 'M1 rendered-only and unverified are never attached');
  perform fx.ok((select outcome from pipeline.aer_source_inventory where provider_id = 'fe6af182-f5ca-4a3c-bfb4-b0773ff1b113') = 'verified_rendered_only'
                and (select boundary from pipeline.aer_source_inventory where provider_id = 'fe6af182-f5ca-4a3c-bfb4-b0773ff1b113') like '%Singapore%', 'M1 JCU: rendered only, Singapore boundary kept');
  perform fx.ok(not exists (select 1 from pipeline.aer_source_inventory where url is not null and url !~ '^https://(www\.)?(cdu|deakin|une|torrens|acu|jcu|cqu|unisq)\.edu\.au/'), 'M1 every URL is on the university''s own domain');
  raise notice 'M1 inventory: 8 universities; 4 to attach (CDU, UniSQ, UNE, Torrens); Deakin blocked with no URL; ACU and CQU unverified links; JCU rendered only';
end $$;

-- M2 report classes (never status values) and the ledger: source fingerprint, inventory, class; incremental pick-up of a new inventory row
do $$
declare s record; v jsonb;
begin
  perform fx.ok(security.aer_source_class_v1('6f5cb7f7-7c70-4c06-970f-f368c3a786e2') = 'source_found', 'M2 CDU: source_found before attachment');
  perform fx.ok(security.aer_source_class_v1('c5c5d225-3d4c-4e41-8275-78eddd261073') = 'no_source', 'M2 Deakin: no_source');
  perform fx.ok(security.aer_source_class_v1('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113') = 'source_found', 'M2 JCU: a verified (rendered-only) page is source_found');
  perform fx.ok(security.aer_source_class_v1('030992c3-72c6-452d-8a3b-10ceb0fd77f2') = 'no_source', 'M2 ACU: an unverified link is not a found source');
  select * into s from security.aer_coverage_v1(array['6f5cb7f7-7c70-4c06-970f-f368c3a786e2'::uuid]);
  perform fx.ok(s.measures->>'aer_class' = 'source_found' and s.measures->'inventory' = '{"verified_attachable": 1}'::jsonb and s.measures->'source_fingerprint' = 'null'::jsonb, 'M2 ledger measures: ' || s.measures::text);
  select * into s from security.aer_coverage_v1(array['d0000000-0000-0000-0000-000000000002'::uuid]);
  perform fx.ok(length(s.measures->>'source_fingerprint') = 32, 'M2 a provider with a source has a fingerprint');
  v := security.coverage_reconcile_v1('aer');
  perform fx.ok((v->'aer'->>'looked_at')::int >= 8, 'M2 the eight new providers are picked up: ' || v::text);
  perform fx.ok(not exists (select 1 from pg_constraint c where c.conrelid = 'pipeline.entry_matrix_sources'::regclass and pg_get_constraintdef(c.oid) like '%source_found%'), 'M2 no new status value');
  raise notice 'M2 report classes and ledger: CDU source_found, Deakin no_source, fingerprint and inventory on the ledger';
end $$;

-- M3 verify of the attachment remedy fails before the paste file; root causes and remedies registered with the right authority
do $$
begin
  perform fx.ok(not (security.aer_source_inventory_verify_v1(0)->>'passed')::boolean and (security.aer_source_inventory_verify_v1(0)->'measure'->>'to_attach')::int = 4, 'M3 verify fails before attachment');
  perform fx.ok((select authority from pipeline.ops_remedies where code = 'aer_source_attach') = 'release' and (select action_fn from pipeline.ops_remedies where code = 'aer_source_attach') is null, 'M3 attachment is a release step, never automatic');
  perform fx.ok((select authority from pipeline.ops_remedies where code = 'aer_source_discovery') = 'admin', 'M3 blocked sources need a person or a permitted read');
  perform fx.ok((select count(*) from pipeline.ops_root_causes where code in ('aer_source_unverified', 'aer_source_rendered_only', 'aer_source_not_attached', 'aer_reader_value_not_printed', 'aer_subject_rows_one_identity')) = 5, 'M3 five root causes');
  perform fx.ok((select count(*) from pipeline.entry_matrix_sources where found_via = 'manual' and provider_id in (select provider_id from pipeline.aer_source_inventory)) = 0, 'M3 the migration attaches nothing');
  raise notice 'M3 nothing attached by the migration; attachment is a release step with a verify; blocked sources are admin';
end $$;
