-- Guards: F-PDESC (Platform Admin data population mandate 9 Nov 2026): a provider with no description is selected again even within pdesc.recheck_days of an admitted read (migration 20261109010000).
-- Fixture data only (the provider-description-autonomy seed). Prints "<scenario>|<eligibility_reason>" for each scenario, then the providers the enqueue step queues, and rolls everything back.
\set ON_ERROR_STOP on
begin;
update pipeline.platform_toolset_settings set value = (select jsonb_agg(stable_key) from catalogue.providers where stable_key like 'fixture:provider:%') where toolset_key = 'pipeline' and key = 'pdesc.provider_keys';
create temp table sc(n int, label text);
-- a read for fixture provider n: its latest state, how long ago it was verified, an optional hash (the stored copy of provider n has the hash repeat(lpad(to_hex(n),2,'0'),32))
create or replace function pg_temp.mk(p_n int, p_label text, p_state text, p_age interval, p_hash text default null) returns void language plpgsql as $f$
declare p uuid;
begin
  select id into p from catalogue.providers where stable_key = 'fixture:provider:' || p_n;
  delete from pipeline.provider_description_reads where provider_id = p;
  insert into pipeline.provider_description_reads(provider_id, state, rule, content_hash, source_url, created_at, updated_at, last_verified_at, tries)
    values (p, p_state, 'missing', coalesce(p_hash, repeat(lpad(to_hex(p_n), 2, '0'), 32)), 'https://p' || p_n || '.example.edu/about', now() - p_age - interval '1 hour', now() - p_age, now() - p_age, 1);
  insert into sc values (p_n, p_label);
end $f$;
-- no description, admitted or verified read within the 180 days: the case this change is about
select pg_temp.mk(1, 'lost_admitted',               'admitted', interval '2 days');
select pg_temp.mk(2, 'lost_verified',               'verified', interval '2 days');
-- no description, last verified past pdesc.recheck_days: selected before and after (eligible then, description_lost now)
select pg_temp.mk(5, 'lost_past_recheck',           'admitted', interval '200 days');
-- every earlier guard still wins over description_lost
select pg_temp.mk(3, 'lost_manual_lock',            'admitted', interval '2 days');
insert into pipeline.manual_locks(entity, entity_id, field, mode) select 'provider', id, 'description', 'value' from catalogue.providers where stable_key = 'fixture:provider:3';
select pg_temp.mk(4, 'lost_then_rejected',          'rejected', interval '5 minutes', 'bb');
select pg_temp.mk(8, 'lost_open_work',              'queued',   interval '5 minutes');
select pg_temp.mk(7, 'lost_identity_finding',       'admitted', interval '2 days');
insert into pipeline.provider_identity_findings(provider_id, check_code, state, reason) select id, 'identity_unconfirmed', 'open', 'fixture' from catalogue.providers where stable_key = 'fixture:provider:7';
-- a provider that still holds its approved description stays current
select pg_temp.mk(6, 'described_current',           'admitted', interval '2 days');
do $$
declare p uuid; i uuid; e uuid; t text := 'Fixture approved description that the provider still holds, entirely as it was approved by a person.';
begin
  select id into p from catalogue.providers where stable_key = 'fixture:provider:6';
  select id into e from pipeline.evidence_artifacts where source_url = 'https://p6.example.edu/about' limit 1;
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status)
    values ('provider', p, 'provider_description', e, jsonb_build_object('description', null), jsonb_build_object('description', t), 'approved') returning id into i;
  update pipeline.provider_description_reads set review_item_id = i, proposal = jsonb_build_object('description', t) where provider_id = p;
  update catalogue.providers set description = t where id = p;
end $$;
select sc.label || '|' || (x->>'eligibility_reason') from sc join catalogue.providers p on p.stable_key = 'fixture:provider:' || sc.n
  cross join lateral jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'size', 1, 'mode', 'stored', 'provider_id', p.id))->'providers') x order by sc.n;
-- the enqueue step queues exactly the eligible ones among them (a fresh read for each)
create temp table pre as select provider_id, id from pipeline.provider_description_reads;
select security.provider_description_enqueue_v1() > 0 as queued_something \gset
select 'enqueued|' || coalesce(string_agg(sc.label, ',' order by sc.n), '') from sc join catalogue.providers p on p.stable_key = 'fixture:provider:' || sc.n
  where exists (select 1 from pipeline.provider_description_reads r where r.provider_id = p.id and r.state = 'queued' and r.id not in (select id from pre) );
rollback;
