\set ON_ERROR_STOP on
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
do $$ declare d jsonb; begin
  d := security.data_delivery_v1();
  -- the live defect: the aer lane lists aer.replay_on = 1, aer.source_stored_find_on = 1 and aer.e13_recover_on = 0 (the E13 pilot, off on purpose), and one switch off turns the whole stream off
  perform pg_temp.ok((select s->'recovery'->>'state' from jsonb_array_elements(d->'streams') s where s->>'stream' = 'aer') = 'off', 'before: Data Delivery shows the aer recovery as off while two of its three switches are on (the live defect, reproduced)');
  perform pg_temp.ok(not (select s->'aer_sources' ? 'reviewer' from jsonb_array_elements(d->'streams') s where s->>'stream' = 'aer'), 'before: the aer stream has no reviewer key');
  perform pg_temp.ok(to_regprocedure('security.aer_course_population_v1(uuid)') is null, 'before: the eligibility rules cannot be asked for one provider');
  perform pg_temp.ok(not (security.layer4_aer_review_detail_v1('42000000-0000-0000-0000-000000000001')->'sections' @> '[{"key": "facts"}]'), 'before: the reviewer detail has no facts section (country, scale and year are not checked)');
end $$;
-- the old answer, kept for the additive-keys check
create table pipeline.fx_dd_before as select security.data_delivery_aer_v1() a;
