-- CF-247 (18 Oct 2026) Platform Admin 18:53 "First close the easier steps 1, 2, 5, 7"; choices "Split by group (Recommended)" for the 136
-- fees held by the admit cross-check and "Yes, from their own pages (Recommended)" for the six Torrens professional doctorates.
-- This change only creates Layer 4 review items, so each value is written by the Layer 4 decision a person makes (with its reason, audit
-- row, lock and the usual apply route); nothing is written to the catalogue here.
-- 1 Fees whose page prints the whole-course fee (the amount equals the CRICOS registered course total within 5%): one item each, proposed
--   annual fee = registered total / course years (basis indicative_annual, international, AUD), evidence = the stored course page.
-- 2 Torrens University: the six professional doctorates whose own page (matched by CRICOS code) prints IELTS 7.0 and that hold no English
--   requirement: one item each, proposed IELTS overall 7.0, evidence = the stored course page.
-- Layer 4 sends a new course item to the university's adapter when that adapter admits the field (trigger layer4_review_items_reroute).
-- Here the adapter is the source that may not write these values (the fee is excluded after the cross-check; research English is a
-- person's decision), so the 14 items created here are put back to pending, with that reason, right after they arrive.
-- The other held fees (per term, about half, discounted or above the total) and those whose page shows no fee now are settled through
-- the flags, not here.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API is not touched.

insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
select 'course', h.course_id, 'provider_current_tuition_validation', h.evidence_id, jsonb_build_object('page_fee', h.fee, 'registered_total', h.reg, 'weeks', h.weeks),
       jsonb_build_object('amount', round(h.reg / (h.weeks / 52.0), 2), 'currency_code', 'AUD', 'basis', 'indicative_annual', 'audience', 'international'),  -- fixed: 52 weeks a year
       jsonb_build_object('page', h.url, 'source', 'coverage sweep', 'rule', 'the page prints the whole-course fee (equal to the CRICOS registered total)'),
       '{}'::jsonb, 'pending', 'Fee held by the admit cross-check: the page prints the whole-course fee; annual = registered total / course years (Platform Admin 18 Oct 2026 18:53)',
       'CF-CHG-20260915-247'
  from (select f.entity_key::uuid course_id, pg.evidence_id, pg.url, nullif(regexp_replace(pg.candidates->'fee'->>'value', '[^0-9.]', '', 'g'), '')::numeric fee,
               d.regulatory_tuition_amount reg, co.duration_value weeks
          from pipeline.enrichment_flags f
          join pipeline.coverage_course_pages pg on pg.course_id = f.entity_key::uuid
          join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active' and co.duration_unit = 'weeks' and co.duration_value >= 26
          join search.course_documents d on d.course_id = pg.course_id and d.regulatory_tuition_amount > 0
         where f.reason_code = 'fee_crosscheck' and f.state = 'raised' and pg.evidence_id is not null) h
 where h.fee is not null and abs(h.fee - h.reg) <= 0.05 * h.reg  -- fixed: "equal to the registered total" within rounding on the page
   and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = h.course_id and i.field_code = 'provider_current_tuition_validation' and i.status = 'pending');

insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
select 'course', c.id, 'course_english', pg.evidence_id, '{}'::jsonb,
       jsonb_build_object('english_requirements', jsonb_build_array(jsonb_build_object('test_code', 'IELTS', 'overall_score', (pg.candidates->'english'->>'ielts_overall')::numeric))),
       jsonb_build_object('page', pg.url, 'source', 'coverage sweep', 'identity', pg.identity_basis),
       '{}'::jsonb, 'pending', 'Research degree: the course page prints its own IELTS score (Platform Admin 18 Oct 2026 18:53, "Yes, from their own pages")',
       'CF-CHG-20260915-247'
  from catalogue.courses c
  join catalogue.providers p on p.id = c.provider_id and p.canonical_name ilike 'Torrens University%'
  join pipeline.coverage_course_pages pg on pg.course_id = c.id and pg.read_status = 'read' and pg.identity_basis = 'cricos_code' and pg.evidence_id is not null
 where c.lifecycle_status = 'active' and c.canonical_title ~* '^Professional Doctorate'
   and (pg.candidates->'english'->>'ielts_overall') ~ '^[0-9](\.[0-9])?$'
   and not exists (select 1 from catalogue.course_english_requirements e where e.course_id = c.id and e.status = 'active')
   and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = c.id and i.field_code = 'course_english' and i.status = 'pending');

update pipeline.layer4_review_items i
   set status = 'pending', decided_at = null,
       change_control_ref = i.change_control_ref || '; kept for the Platform Admin''s decision (the adapter may not write this value), 18 Oct 2026'
 where i.status = 'superseded' and i.created_at >= now() - interval '10 minutes'  -- fixed: only the items this change created
   and (i.escalation_reason like 'Fee held by the admit cross-check: the page prints the whole-course fee%'
        or i.escalation_reason like 'Research degree: the course page prints its own IELTS score%');

do $post$ declare a int; t int; begin
  select count(*) into a from pipeline.layer4_review_items where status = 'pending' and field_code = 'provider_current_tuition_validation' and escalation_reason like 'Fee held by the admit cross-check: the page prints the whole-course fee%';
  select count(*) into t from pipeline.layer4_review_items where status = 'pending' and field_code = 'course_english' and escalation_reason like 'Research degree: the course page prints its own IELTS score%';
  if a <> 8 then raise exception 'post-check: % whole-course fee items, expected 8', a; end if;
  if t <> 6 then raise exception 'post-check: % Torrens items, expected 6', t; end if;
end $post$;
