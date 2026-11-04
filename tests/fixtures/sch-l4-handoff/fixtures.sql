-- Cases after 20261104480000. Each raises on failure and prints NOTICE "ok ..." on success.
create or replace function pg_temp.ok(p boolean, p_msg text) returns void language plpgsql as $$
begin if p is not true then raise exception 'FAILED: %', p_msg; end if; raise notice 'ok %', p_msg; end $$;
create or replace function pg_temp.st(p_sid text) returns text language sql as $$ select state from pipeline.scholarship_coverage_items where item_key = 'sch:' || p_sid and present $$;
create or replace function pg_temp.iv(p_sid text) returns pipeline.layer4_interventions language sql as $$
  select * from pipeline.layer4_interventions where lane = 'sch_value' and entity like '%|sch:' || p_sid $$;
create or replace function pg_temp.set(p_key text, p_v numeric) returns void language sql as $$
  update pipeline.platform_toolset_settings set value = to_jsonb(p_v) where toolset_key = 'pipeline' and key = p_key $$;

-- 1 switches and contract
select pg_temp.ok((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where key = 'har.generate_sch_value_on') = 1
                  and (select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where key = 'sch_cov.value_apply_on') = 1, 'switches: value interventions on; a reviewer''s value applies');
select pg_temp.ok(exists (select 1 from pipeline.layer4_intervention_handlers where lane = 'sch_value') and (select lane from pipeline.layer4_intervention_classes where code = 'sch_value_missing') = 'sch_value',
                  'lane sch_value has its own handler and class (its own open limit)');

-- 2 classification: failing checks recorded; decided refusals resolved
select security.scholarship_coverage_classify_v1(array['40000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000003']::uuid[]);
select pg_temp.ok(pg_temp.st('50000000-0000-0000-0000-000000000001') = 'admitted_not_published'
                  and (select reason from pipeline.scholarship_coverage_items where item_key = 'sch:50000000-0000-0000-0000-000000000001') = 'publishing checks: no stated award value'
                  and (select evidence->'missing' from pipeline.scholarship_coverage_items where item_key = 'sch:50000000-0000-0000-0000-000000000001') = '["no stated award value"]',
                  'S1: the failing publishing check is on the case');
select pg_temp.ok(pg_temp.st('50000000-0000-0000-0000-000000000002') = 'rejected_correctly'
                  and (select reason from pipeline.scholarship_coverage_items where item_key = 'sch:50000000-0000-0000-0000-000000000002') like 'Refused in Layer 4%',
                  'S2: refused by a person in Layer 4 is rejected correctly, with the decision as its reason');
select pg_temp.ok(pg_temp.st('50000000-0000-0000-0000-000000000003') = 'published_verified' and pg_temp.st('50000000-0000-0000-0000-000000000004') = 'awaiting_layer4',
                  'S3 published and consumer-verified; S4 awaits its Layer 4 decision');
select pg_temp.ok((select evidence->'missing' from pipeline.scholarship_coverage_items where item_key = 'sch:50000000-0000-0000-0000-000000000007') @> '["not for international students", "no stated award value"]',
                  'S7: two failing checks recorded (not a value-only case)');

-- 3 the hand-off: eligible value-only cases become one intervention each; nothing else is asked
create or replace function pg_temp.boom() returns trigger language plpgsql as $$
begin if new.provider_id = '40000000-0000-0000-0000-000000000002' then raise exception 'fixture: this provider''s intervention write fails'; end if; return new; end $$;
create trigger fx_boom before insert on pipeline.layer4_interventions for each row execute function pg_temp.boom();
update pipeline.scholarship_coverage_items set first_seen = now() - interval '2 days' where provider_id = '40000000-0000-0000-0000-000000000002';
do $$
declare v jsonb := security.layer4_interventions_tick_v1();
begin
  perform pg_temp.ok((v->'generated'->'sch_value'->>'errors')::int = 1 and (v->'generated'->'sch_value'->>'raised_or_changed')::int = 2,
                     'a failing provider (Southern Cross, first in order) is counted and the others still progress: ' || (v->'generated'->'sch_value')::text);
end $$;
drop trigger fx_boom on pipeline.layer4_interventions;
select pg_temp.ok((pg_temp.iv('50000000-0000-0000-0000-000000000001')).status = 'awaiting_input'
                  and (pg_temp.iv('50000000-0000-0000-0000-000000000001')).recommended->'suggested'->>'value_text' like 'equivalent to the University of Sydney RTP%'
                  and (pg_temp.iv('50000000-0000-0000-0000-000000000001')).evidence->'official_links'->>0 = 'https://www.sydney.edu.au/scholarships/research/cs-stipend',
                  'S1: one "Human input needed" item, with the page wording and the official page');
select pg_temp.ok((select stage from pipeline.work_items where lane = 'sch_value' and entity = '40000000-0000-0000-0000-000000000001|sch:50000000-0000-0000-0000-000000000001') = 'awaiting_review',
                  'S1: its work item waits for review (no lease, no spend)');
select pg_temp.ok((pg_temp.iv('50000000-0000-0000-0000-000000000004')).id is null and (pg_temp.iv('50000000-0000-0000-0000-000000000005')).id is null
                  and (pg_temp.iv('50000000-0000-0000-0000-000000000006')).id is null and (pg_temp.iv('50000000-0000-0000-0000-000000000007')).id is null
                  and (pg_temp.iv('50000000-0000-0000-0000-000000000009')).id is null and (pg_temp.iv('50000000-0000-0000-0000-000000000002')).id is null,
                  'not asked: a decision already waiting (S4), a person''s lock (S5), page not read (S6), two checks (S7), policy-refused provider (S9), refused (S2)');
select pg_temp.ok((select reason from pipeline.scholarship_coverage_items where item_key = 'sch:50000000-0000-0000-0000-000000000009') = 'publishing checks: no stated award value',
                  'S9 (TAFE Queensland, outside the admission policy) keeps an explicit, evidence-backed disposition');
do $$
declare n0 int := (select count(*) from pipeline.layer4_interventions); v jsonb;
begin
  v := security.layer4_interventions_tick_v1();
  perform pg_temp.ok((select count(*) from pipeline.layer4_interventions) = n0 + 1 and (pg_temp.iv('50000000-0000-0000-0000-000000000008')).id is not null,
                     'the next tick raises the provider that failed (S8); nothing already open is raised again');
  v := security.layer4_interventions_tick_v1();
  perform pg_temp.ok((select count(*) from pipeline.layer4_interventions) = n0 + 1, 'a further tick creates nothing: no duplicate');
end $$;

-- 4 a reviewer's value: validated, applied as the reviewer's locked edit; the next stage publishes; publication is verified
set request.jwt.claim.sub = '63ba56cb-48d4-4169-98c2-7c4d1f72925b';
set fx.rank = 4;
do $$
declare v jsonb; i bigint := (pg_temp.iv('50000000-0000-0000-0000-000000000001')).id;
begin
  v := security.layer4_intervention_resolve_v1(i, 'enter_value', jsonb_build_object('value', '37000', 'reason', 'RTP stipend 2026'));
  perform pg_temp.ok((v->>'ok')::boolean = false and (pg_temp.iv('50000000-0000-0000-0000-000000000001')).status = 'awaiting_input', 'a value without the page''s sentence is asked for again');
  v := security.layer4_intervention_resolve_v1(i, 'enter_value', jsonb_build_object('value', '{"amount": "37000", "quote": "The Scholarship will provide a stipend allowance equivalent to the RTP Stipend rate ($37,000 in 2026)"}',
                                                                                    'reason', 'RTP stipend rate for 2026 stated on the page'));
  perform pg_temp.ok((v->>'ok')::boolean and (v->'resume'->>'scheduled')::boolean, 'a valid value is taken and applied');
  perform pg_temp.ok((select award_value_type = 'fixed_amount' and award_amount = 37000 and publication_status = 'unpublished' from scholarship.scholarships where id = '50000000-0000-0000-0000-000000000001')
                     and exists (select 1 from pipeline.manual_locks where entity_id = '50000000-0000-0000-0000-000000000001' and field = 'award_amount')
                     and (select actor from pipeline.manual_edit_log where entity_id = '50000000-0000-0000-0000-000000000001') = '63ba56cb-48d4-4169-98c2-7c4d1f72925b',
                     'the value is the reviewer''s own locked edit (logged with the reviewer); nothing is published by the decision itself');
  v := security.layer4_interventions_tick_v1();
  perform pg_temp.ok((pg_temp.iv('50000000-0000-0000-0000-000000000001')).status = 'resuming', 'before the publishing run the intervention waits for its result');
  perform public.fx_auto_publish();  -- the hourly scholarship-auto-publish run (unattended, already on)
  v := security.layer4_interventions_tick_v1();
  perform pg_temp.ok((pg_temp.iv('50000000-0000-0000-0000-000000000001')).status = 'resolved' and (pg_temp.iv('50000000-0000-0000-0000-000000000001')).published_at is not null
                     and (pg_temp.iv('50000000-0000-0000-0000-000000000001')).verified_outcome = 'published_consumer_verified',
                     'the next stage ran unattended: published, read back through the consumer API, verified');
  perform security.scholarship_coverage_classify_v1(array['40000000-0000-0000-0000-000000000001']::uuid[]);
  perform pg_temp.ok(pg_temp.st('50000000-0000-0000-0000-000000000001') = 'published_verified', 'S1 is now published and consumer-verified in the coverage states');
end $$;

-- 5 a reviewer confirms the page states no award value: an explicit disposition, never asked again
set fx.rank = 5;
do $$
declare v jsonb; i bigint := (pg_temp.iv('50000000-0000-0000-0000-000000000010')).id;
begin
  v := security.layer4_intervention_resolve_v1(i, 'confirm_not_published', jsonb_build_object('value', 'https://www.sydney.edu.au/scholarships/travel-grant', 'reason', 'The page names no amount; support is case by case'));
  perform pg_temp.ok((pg_temp.iv('50000000-0000-0000-0000-000000000010')).status = 'not_published', 'confirmed: the page states no award value');
  perform security.scholarship_coverage_classify_v1(array['40000000-0000-0000-0000-000000000001']::uuid[]);
  perform pg_temp.ok(pg_temp.st('50000000-0000-0000-0000-000000000010') = 'rejected_correctly'
                     and (select reason from pipeline.scholarship_coverage_items where item_key = 'sch:50000000-0000-0000-0000-000000000010') = 'a person confirmed the page states no award value',
                     'S10 is rejected correctly, with the person''s confirmation as its reason');
  v := security.layer4_interventions_tick_v1();
  perform pg_temp.ok((select count(*) from pipeline.layer4_interventions where entity like '%50000000-0000-0000-0000-000000000010') = 1
                     and (pg_temp.iv('50000000-0000-0000-0000-000000000010')).status = 'not_published', 'never asked again');
end $$;

-- 6 with sch_cov.value_apply_on 0 a supplied value stays a proposal
do $$
declare v jsonb; i bigint := (pg_temp.iv('50000000-0000-0000-0000-000000000008')).id;
begin
  perform pg_temp.set('sch_cov.value_apply_on', 0);
  v := security.layer4_intervention_resolve_v1(i, 'enter_value', jsonb_build_object('value', '25%', 'quote', 'Successful applicants receive a 25% reduction in tuition fees for the course', 'reason', 'stated on the page'));
  perform pg_temp.ok((v->'resume'->>'scheduled')::boolean = false and (select award_value_type from scholarship.scholarships where id = '50000000-0000-0000-0000-000000000008') = 'text_only'
                     and exists (select 1 from pipeline.layer4_intervention_values where intervention_id = i and value->>'kind' = 'percentage'),
                     'switch off: the value is kept as a proposal only; the scholarship is unchanged');
  perform pg_temp.set('sch_cov.value_apply_on', 1);
end $$;

-- 7 nothing else admitted or published
select pg_temp.ok((select count(*) from scholarship.scholarships where publication_status = 'published') = 2, 'only S3 (already) and S1 (after a person''s value) are published');
select pg_temp.ok((select count(*) from pipeline.scholarship_ai_reviews where status = 'pending') = 1, 'the waiting Layer 4 decision (S4) is untouched');
