-- CF-247 AER review queue fixtures: what the review packet reads, on top of ../aer-throughput/seed.sql (production-shaped: 605 waiting items,
-- RMIT 303, gate classes in live proportion, 83 corrections refused at 02:13). Shapes as live (4 Nov 2026 11:19 AEDT). Fixture data only.

-- countries, qualifications, publication, stored copies
insert into ref.countries(id, iso_alpha2) select distinct country_id, case when canonical_name ~* '(auckland|wellington|lincoln|manukau|eastern institute)' then 'NZ' else 'AU' end
  from catalogue.providers on conflict do nothing;
insert into ref.study_levels(id, code, name) values ('aaaaaaaa-0000-0000-0000-000000000001', 'BA', 'Bachelor'), ('aaaaaaaa-0000-0000-0000-000000000002', 'MC', 'Masters (Coursework)');
update catalogue.courses set study_level_id = case when right(stable_key, 1) in ('1', '3', '5', '7', '9') then 'aaaaaaaa-0000-0000-0000-000000000001'::uuid else 'aaaaaaaa-0000-0000-0000-000000000002'::uuid end,
       publication_status = 'published', course_code = 'C' || substr(stable_key, 2);
insert into pipeline.evidence_artifacts(id, source_url, captured_at)
select i.evidence_id, i.proposed_value->>'url', now() - interval '2 days' from pipeline.layer4_review_items i where i.evidence_id is not null;

-- proposed rows: three a course read (international minimum grade, a prerequisite, an English note on row-level holds)
insert into catalogue.course_entry_requirements(course_id, kind, audience, quote, min_entry_score, min_entry_score_basis, status, provenance, confidence)
select i.entity_id, k.kind, k.aud, k.quote || ' (course ' || i.entity_id || ')', k.score, k.basis, 'proposed', jsonb_build_object('review_item_id', i.id::text, 'reader', 'enrich_ai'), 0.9
  from pipeline.layer4_review_items i
  cross join (values ('minimum_grade', 'international', 'A minimum GPA of 5.0 on a 7-point scale', 5.0, 'GPA (7-point)'),
                     ('subject_prerequisite', 'all', 'Prerequisite: Mathematics Methods (Units 3 and 4)', null, null),
                     ('general_note', 'all', 'This program is designed for graduates', null, null)) k(kind, aud, quote, score, basis)
 where i.status = 'pending' and i.field_code = 'course_entry_first_read';
-- row-level holds name a real row to leave out (the general note)
update fx.gate f set g = jsonb_set(f.g, '{not_requirement}', (select jsonb_agg(jsonb_build_object('id', x.id)) from catalogue.course_entry_requirements x
                                                              where x.provenance->>'review_item_id' = f.item_id::text and x.kind = 'general_note'))
 where fx.cls(f.g) = 'row_level' and f.g->>'rule' = 'E13';
-- one complete RMIT course already has two active rows from an earlier read (approval supersedes them); another has a manual lock
create temp table pick as select i.id, i.entity_id, row_number() over (order by i.created_at) n from pipeline.layer4_review_items i join fx.gate f on f.item_id = i.id
  join catalogue.courses c on c.id = i.entity_id where fx.cls(f.g) = 'complete' and c.provider_id = '8e1adb6c-e069-43db-9584-bd054255e702';
insert into catalogue.course_entry_requirements(course_id, kind, audience, quote, status, provenance)
select entity_id, 'minimum_grade', 'international', 'An earlier read: GPA 4.5', 'active', '{"reader": "enrich_ai"}'::jsonb from pick, generate_series(1, 2) where n = 1;
insert into pipeline.manual_locks(entity, entity_id, field, mode) select 'course', entity_id, 'entry_requirements', 'keep' from pick where n = 2;

-- matrix runs: a source and a run for each
insert into pipeline.entry_matrix_sources(id, provider_id, status, url) select gen_random_uuid(), i.entity_id, 'read', 'https://matrix.example/' || i.entity_id
  from pipeline.layer4_review_items i where i.field_code = 'entry_matrix_first_run' group by i.entity_id;
insert into pipeline.entry_matrix_runs(id, provider_id, source_id, review_item_id, rows_admitted, rows_dropped, created_at)
select gen_random_uuid(), i.entity_id, (select s.id from pipeline.entry_matrix_sources s where s.provider_id = i.entity_id limit 1), i.id, 12, 0, i.created_at
  from pipeline.layer4_review_items i where i.field_code = 'entry_matrix_first_run';
insert into catalogue.provider_entry_matrix(provider_id, run_id, country_code, level_label, qualification_name, min_grade, grade_scale, audience, quote)
select m.provider_id, m.id, c, 'Undergraduate', 'National Senior Certificate', '70', 'percentage', 'international', c || ': 70%' from pipeline.entry_matrix_runs m, unnest(array['IN', 'CN', 'NP']) c;
-- as live 11:16: 2 runs complete, 17 held for dropped published rows (or unscaled values), 22 held only for rows to leave out
create temp table mo as select i.id, row_number() over (order by i.created_at, i.id) n from pipeline.layer4_review_items i where i.field_code = 'entry_matrix_first_run';
update fx.gate f set g = case when mo.n <= 2 then '{"rule": "D-R3", "complete": true, "reasons": []}'::jsonb
                              when mo.n <= 19 then '{"rule": "D-R3", "complete": false, "reasons": ["the reader dropped 4 published row(s) that no admitted row covers (countries left with no row: VN)"]}'::jsonb
                              else '{"rule": "D-R3", "complete": false, "reasons": ["1 group(s) of waiting rows share one identity (2 rows): leave them out with Approve except, or reject the run"]}'::jsonb end
  from mo where mo.id = f.item_id;
update pipeline.layer4_item_readiness x set gate = f.g, gate_checked_at = now() from fx.gate f where f.item_id = x.item_id;

-- the ChatGPT browser reviewer owns Monash's course entry review
insert into pipeline.layer4_review_owners(provider_id, field_code, owner, scope, basis)
select id, 'course_entry_first_read', 'chatgpt', 'university review', 'ownership register 3 Nov 2026 19:10' from catalogue.providers where canonical_name = 'Monash University';

-- the reviewer (Pipeline Operator) and E13 recovery off, as live
update fx.caller set uid = '22222222-2222-2222-2222-222222222222', rank = 4;
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values ('pipeline', 'coverage.aer_priority_providers', 'list',
  '["6f5cb7f7-7c70-4c06-970f-f368c3a786e2", "551383f9-7732-4588-a843-dd2b97c13f6f", "fa0e0d13-838a-42ff-b6a3-9cea84bd80b2", "fec52f92-a8a3-4de8-a862-06f355e4e2f7", "030992c3-72c6-452d-8a3b-10ceb0fd77f2", "f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6", "c5c5d225-3d4c-4e41-8275-78eddd261073", "fe6af182-f5ca-4a3c-bfb4-b0773ff1b113", "8e1adb6c-e069-43db-9584-bd054255e702", "9109fe0c-9f44-4e2d-a136-eb00dec24701"]')
on conflict (toolset_key, key) do update set value = excluded.value;
