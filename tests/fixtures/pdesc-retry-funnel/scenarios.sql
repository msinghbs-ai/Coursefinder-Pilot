-- Guards: P-DESC lane E (8 Nov 2026): a held read, or a person's rejection on a source the page rule now refuses, is selected again once a different official copy is stored.
-- Fixture data only (the provider-description-autonomy seed). Prints "<scenario>|<eligibility_reason>" for each scenario and rolls everything back.
\set ON_ERROR_STOP on
begin;
update pipeline.platform_toolset_settings set value = (select jsonb_agg(stable_key) from catalogue.providers where stable_key like 'fixture:provider:%') where toolset_key = 'pipeline' and key = 'pdesc.provider_keys';
create temp table sc(n int, label text);
create or replace function pg_temp.mk(p_n int, p_label text, p_state text, p_rule text, p_hash text, p_url text, p_age interval) returns void language plpgsql as $f$
declare p uuid;
begin
  select id into p from catalogue.providers where stable_key = 'fixture:provider:' || p_n;
  delete from pipeline.provider_description_reads where provider_id = p;
  insert into pipeline.provider_description_reads(provider_id, state, rule, content_hash, source_url, created_at, updated_at, tries)
    values (p, p_state, p_rule, p_hash, p_url, now() - p_age - interval '1 hour', now() - p_age, 1);
  insert into sc values (p_n, p_label);
end $f$;
select pg_temp.mk(1, 'held_new_copy',                 'held',     'quote_not_on_page', 'aa', 'https://p1.example.edu/about', interval '2 days');
select pg_temp.mk(2, 'held_same_copy',                'held',     'quote_not_on_page', '0202020202020202020202020202020202020202020202020202020202020202', 'https://p2.example.edu/about', interval '2 days');
select pg_temp.mk(3, 'held_new_copy_just_now',        'held',     'quote_not_on_page', 'aa', 'https://p3.example.edu/about', interval '5 minutes');
select pg_temp.mk(4, 'rejected_source_now_refused',   'rejected', 'layer4_rejected',   'aa', 'https://p4.example.edu/news/about-the-research-centre', interval '2 days');
select pg_temp.mk(5, 'rejected_source_still_valid',   'rejected', 'layer4_rejected',   'aa', 'https://p5.example.edu/about', interval '2 days');
select pg_temp.mk(6, 'held_never_fetched',            'held',     'no_about_page',     null, null, interval '2 days');
select pg_temp.mk(8, 'held_past_recheck',             'held',     'quote_not_on_page', 'aa', 'https://p8.example.edu/about', interval '200 days');
select pg_temp.mk(9, 'rejected_no_source_recorded',   'rejected', 'layer4_rejected',   'aa', null, interval '2 days');
select pg_temp.mk(10, 'proposed_open',                'proposed', 'missing',           'aa', 'https://p10.example.edu/about', interval '2 days');
select pg_temp.mk(7, 'held_new_copy_manual_lock',     'held',     'quote_not_on_page', 'aa', 'https://p7.example.edu/about', interval '2 days');
insert into pipeline.manual_locks(entity, entity_id, field, mode) select 'provider', id, 'description', 'value' from catalogue.providers where stable_key = 'fixture:provider:7';
select sc.label || '|' || (x->>'eligibility_reason') from sc join catalogue.providers p on p.stable_key = 'fixture:provider:' || sc.n
  cross join lateral jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'size', 1, 'mode', 'stored', 'provider_id', p.id))->'providers') x order by sc.n;
rollback;
