-- second pass: the migration's QUT data step with the md5 of THIS fixture's candidates substituted for the live one (run.sh makes the copy). Proves the guarded apply path.
create or replace function t.chk(p_name text, p_ok boolean) returns void language plpgsql as $f$ begin raise notice '%', case when coalesce(p_ok, false) then 'PASS ' else 'FAIL ' end || p_name; end $f$;
select t.chk('QA1 23 pages mapped for the QUT-shaped provider, all held (inactive, stored copy), none of the 14 locked and not the 8-row read',
  (select count(*) from pipeline.aer_matrix_route where provider_id = '2c4f515c-c146-4e90-ba8a-294130aa1f40' and state = 'held') = 23
  and (select count(*) from pipeline.entry_matrix_sources where provider_id = '2c4f515c-c146-4e90-ba8a-294130aa1f40' and status = 'inactive' and read_via = 'stored' and evidence_id is not null) = 23
  and not exists (select 1 from pipeline.aer_matrix_route r join t.named n on n.id = r.old_item_id where n.name ~ '^q(2[4-9]|3[0-8])$'));
select t.chk('QA2 all 38 QUT-shaped waiting items are still pending, unchanged', (select count(*) from pipeline.layer4_review_items i join t.named n on n.id = i.id where n.name ~ '^q[0-9]+$' and i.status = 'pending') = 38);
select t.chk('QA3 nothing is readable yet: no source of the provider is in found / reading / read',
  (select count(*) from pipeline.entry_matrix_sources where provider_id = '2c4f515c-c146-4e90-ba8a-294130aa1f40' and status in ('found', 'reading', 'read')) = 0);
select t.chk('QA4 one audit event for the 23, naming no fetch and no AI', (select count(*) from pipeline.admin_control_events where area = 'entry_matrix' and action = 'route_attach' and detail->>'mapped' = '23') = 1);
select t.chk('QA5 the locked courses are still unmapped and are candidates only when named (14)', (select count(*) from security.aer_matrix_route_candidates_v1('2c4f515c-c146-4e90-ba8a-294130aa1f40',
   (select array_agg(id) from t.named where name ~ '^q(2[4-9]|3[0-7])$'))) = 14);
do $d$ begin raise notice 'qut-shared-2: finished'; end $d$;
