-- IQ-00116 after the migration: the check, the apply path, the remedy and its verification.
\i tests/fixtures/tuition-publication/helpers.sql
do $$
declare v jsonb; r jsonb; n int;
begin
  -- the check classifies the live set
  v := security.tuition_publication_check_v1(true);
  perform pg_temp.ok((v->>'approvals')::int = 3 and (v->>'published')::int = 1 and (v->>'failing')::int = 2 and (v->'by_cause'->>'source_gate_closed')::int = 2 and not (v->>'passed')::boolean,
                     'check: 3 approvals, 1 published, 2 failing for a closed source gate: ' || (v - 'rule_differs' - 'failing_rows' - 'wide')::text);
  perform pg_temp.ok((v->>'rule_agrees')::int = 3, 'check: the fee rule Zoho reads agrees with all 3 approved fees (amount and year)');
  perform pg_temp.ok((v->'wide'->>'missing_in_projection')::int = 3 and (v->'wide'->>'missing_layer4')::int = 2 and (v->'wide'->'by_cause'->>'source_gate_closed')::int = 3,
                     'check (wide): 3 page fees the rule uses are missing from the projection, 2 of them Layer 4 approvals, all a closed gate: ' || ((v->'wide') - 'courses')::text);
  perform pg_temp.ok(not (security.layer4_tuition_publication_verify_v1(116)->>'passed')::boolean, 'verify: fails before the repair');

  -- the fixed apply path: a new approval on a source never opened is published at once
  perform pg_temp.course('nz new', 'NZ', 'newsrc');
  r := pg_temp.approve('nz new', '{"amount": 12000, "currency_code": "NZD", "basis": "annual", "fee_year": 2027}', interval '3 hours');
  perform pg_temp.ok(r->>'source_gate' = 'opened' and pg_temp.has_fee('nz new') and pg_temp.check_of('nz new') = 'admitted_published:', 'apply: opens the source and the approval is on the projection: ' || r::text);
  perform pg_temp.ok((select approval_ref from search.enrichment_source_gates where source_id = pg_temp.u('src newsrc')) like 'CF-CHG-20260915-247; Layer 4 human decision (review item %', 'apply: the gate names the review item');
  -- a second approval on the same source finds it open
  perform pg_temp.course('nz new2', 'NZ', 'newsrc');
  r := pg_temp.approve('nz new2', '{"amount": 12500, "currency_code": "NZD", "basis": "indicative_annual", "fee_year": 2027}', interval '3 hours');
  perform pg_temp.ok(r->>'source_gate' = 'already_open' and pg_temp.has_fee('nz new2'), 'apply: an open source stays as it is');
  -- a blocked source is never opened
  insert into pipeline.sources(id, source_type, label) values (pg_temp.u('src blk'), 'provider_course_page_sweep', 'blocked pages');
  insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref) values ('courses', 'provider_current_tuition', pg_temp.u('src blk'), 'blocked', 'withdrawn by a person');
  perform pg_temp.course('au blk', 'AU', 'blk');
  r := pg_temp.approve('au blk', '{"amount": 25000, "currency_code": "AUD", "basis": "annual", "fee_year": 2026}', interval '3 hours');
  perform pg_temp.ok(r->>'source_gate' = 'gate_blocked' and not pg_temp.has_fee('au blk') and (select gate_status from search.enrichment_source_gates where source_id = pg_temp.u('src blk')) = 'blocked',
                     'apply: a blocked gate is kept and the fee stays off the projection');
  perform pg_temp.ok(pg_temp.cause('au blk') = 'source_gate_blocked', 'check: cause source_gate_blocked');
  -- a source holding an unreviewed fee is not opened (nothing unreviewed is published with an approval)
  perform pg_temp.course('au mix other', 'AU', 'mixsrc');
  insert into catalogue.course_fees(course_id, status, fee_type, audience, amount, fee_year, currency_code, basis, source_id, notes)
  values (pg_temp.u('au mix other'), 'active', 'provider_current_tuition', 'international', 99000, 2026, 'AUD', 'annual', pg_temp.u('src mixsrc'), 'read by a sweep, not reviewed');
  perform pg_temp.course('au mix', 'AU', 'mixsrc');
  r := pg_temp.approve('au mix', '{"amount": 26000, "currency_code": "AUD", "basis": "annual", "fee_year": 2026}', interval '3 hours');
  perform search.refresh_course_enrichment_scoped_v1(array[pg_temp.u('au mix other')], true);
  perform pg_temp.ok(r->>'source_gate' = 'mixed_source' and not pg_temp.has_fee('au mix') and not pg_temp.has_fee('au mix other'),
                     'apply: a source with an unreviewed fee stays closed; neither fee is published');
  -- the other causes the check names
  insert into catalogue.course_fees(course_id, status, fee_type, audience, amount, fee_year, currency_code, basis, source_id, notes, updated_at)
  select pg_temp.u('au gated'), 'active', 'provider_current_tuition', 'international', 31000, 2027, 'AUD', 'annual', pg_temp.u('src gated'),
         'CF-247 Layer 4 human decision; review item ' || pg_temp.u('item au stale') || '; [fixture] written, projection not yet refreshed', now() + interval '1 second';
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) values (pg_temp.u('item au stale'), 'course', pg_temp.u('au gated'), 'provider_current_tuition_validation', 'approved');
  insert into pipeline.layer4_decisions(id, review_item_id, action, created_at) values (pg_temp.u('dec au stale'), pg_temp.u('item au stale'), 'approve', now() - interval '1 day');
  perform pg_temp.ok((select count(*) from security.tuition_publication_rows_v1(array[pg_temp.u('au gated')]) x where x.cause = 'refresh_pending') = 1, 'check: cause refresh_pending (gate open, projection older than the fee)');
  perform pg_temp.course('au window', 'AU', 'gated');
  insert into catalogue.course_fees(course_id, status, fee_type, audience, amount, fee_year, currency_code, basis, source_id, notes, valid_to)
  values (pg_temp.u('au window'), 'active', 'provider_current_tuition', 'international', 20000, 2025, 'AUD', 'annual', pg_temp.u('src gated'),
          'CF-247 Layer 4 human decision; review item ' || pg_temp.u('item au window') || '; [fixture]', current_date - 1);
  insert into pipeline.layer4_decisions(id, review_item_id, action, created_at) values (pg_temp.u('dec au window'), pg_temp.u('item au window'), 'approve', now() - interval '1 day');
  perform pg_temp.ok(pg_temp.cause('au window') = 'outside_validity', 'check: cause outside_validity');
  update catalogue.course_fees set status = 'inactive' where course_id = pg_temp.u('au window');
  -- a young approval waits (layer4.verify_wait_minutes) before it counts as failing
  perform pg_temp.course('nz young', 'NZ', 'youngsrc');
  insert into catalogue.course_fees(course_id, status, fee_type, audience, amount, fee_year, currency_code, basis, source_id, notes)
  values (pg_temp.u('nz young'), 'active', 'provider_current_tuition', 'international', 9000, 2026, 'NZD', 'annual', pg_temp.u('src youngsrc'),
          'CF-247 Layer 4 human decision; review item ' || pg_temp.u('item nz young') || '; [fixture] saved by the unfixed apply');
  insert into pipeline.layer4_decisions(id, review_item_id, action, created_at) values (pg_temp.u('dec nz young'), pg_temp.u('item nz young'), 'approve', now() - interval '10 minutes');
  perform pg_temp.ok(pg_temp.cause('nz young') = 'waiting', 'check: a 10-minute-old approval is waiting');
  update pipeline.layer4_decisions set created_at = now() - interval '1 day' where id = pg_temp.u('dec nz young');
  perform pg_temp.ok(pg_temp.cause('nz young') = 'source_gate_closed', 'check: the same approval a day old is source_gate_closed');

  -- the remedy
  r := security.layer4_tuition_publication_repair_v1(116);
  perform pg_temp.ok((r->>'ok')::boolean and (r->>'changed')::boolean and (r->'evidence'->'gates'->>'opened')::int = 3 and (r->'evidence'->'gates'->>'mixed_source')::int = 1,
                     'repair: opens 3 closed sources (acts, ef, young), keeps the mixed one: ' || ((r->'evidence') - 'check')::text);
  perform pg_temp.ok(pg_temp.has_fee('nz acts') and pg_temp.has_fee('nz ef') and pg_temp.has_fee('nz young'), 'repair: the three approvals are on the projection');
  perform pg_temp.ok((select provider_annual_tuition_amount from search.course_documents where course_id = pg_temp.u('nz acts')) = 7500
                     and (select provider_annual_tuition_amount from search.course_documents where course_id = pg_temp.u('au gated')) = 31000,
                     'repair: projection amounts follow the fee rule (latest year), the stale course refreshed');
  perform pg_temp.ok(pg_temp.check_of('nz acts') = 'admitted_published:' and pg_temp.check_of('nz ef') = 'admitted_published:', 'repair: the admission checks now read admitted_published');
  perform pg_temp.ok(not pg_temp.has_fee('au fed') and not pg_temp.has_fee('au mix other'), 'repair: nothing without a Layer 4 approval is published (Layer 2 and unreviewed fees stay off)');
  perform pg_temp.ok(not exists (select 1 from search.enrichment_source_gates where source_id in (pg_temp.u('src fed'), pg_temp.u('src mixsrc'))), 'repair: no gate on the Layer 2 or mixed source');
  v := security.layer4_tuition_publication_verify_v1(116);
  perform pg_temp.ok(not (v->>'passed')::boolean and (v->'measure'->>'failing')::int = 2, 'verify: still fails while the blocked and mixed approvals stay unpublished (a person decides): ' || (v->>'evidence'));
  -- once a person withdraws those two fees (a later decision) and the readiness job checks the approvals again, the verification passes
  update catalogue.course_fees set status = 'superseded' where course_id in (pg_temp.u('au blk'), pg_temp.u('au mix'));
  perform security.layer4_admission_record_v1(pg_temp.u('dec au blk')), security.layer4_admission_record_v1(pg_temp.u('dec au mix'));
  v := security.layer4_tuition_publication_verify_v1(116);
  perform pg_temp.ok((v->>'passed')::boolean and (v->'measure'->>'condition_cleared')::boolean, 'verify: passes with every approval published: ' || (v->>'evidence'));
  -- a second run changes nothing
  select count(*) into n from search.enrichment_source_gates;
  r := security.layer4_tuition_publication_repair_v1(116);
  perform pg_temp.ok(not (r->>'changed')::boolean and (select count(*) from search.enrichment_source_gates) = n, 'repair: a second run changes nothing');
  -- registered through the operations contract
  perform pg_temp.ok(exists (select 1 from pipeline.ops_remedies where code = 'layer4_tuition_publication_repair' and authority = 'auto' and active
                               and action_fn = 'security.layer4_tuition_publication_repair_v1(bigint)'::regprocedure and verify_fn = 'security.layer4_tuition_publication_verify_v1(bigint)'::regprocedure
                               and treats = array['layer4_tuition_source_gate_closed']), 'contract: remedy registered (auto, action and verify)');
  perform pg_temp.ok((select (detect->>'priority')::int from pipeline.ops_root_causes where code = 'layer4_tuition_source_gate_closed') = 47, 'contract: root cause registered ahead of the generic layer4_approval_not_published (50)');
end $$;
