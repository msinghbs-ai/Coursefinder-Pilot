-- Guards: P-DESC lane E (8 Nov 2026): the whole-catalogue funnel is read only, role gated, and tells why the next run will or will not queue.
\set ON_ERROR_STOP on
create or replace function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is not true then raise exception 'FAILED: %', p_what; end if; raise notice 'ok: %', p_what; end $f$;
begin;
create temp table before_state as select (select count(*) from pipeline.provider_description_reads) reads, (select count(*) from pipeline.layer4_review_items) items,
  (select count(*) from catalogue.providers where nullif(btrim(description), '') is not null) described, (select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings) settings;
-- a caller without a sign-in, or below curator, is refused; a curator is served
set local fx.uid = '';
do $$ begin begin perform public.admin_provider_description_funnel_v1(); raise exception 'FAILED: an unauthenticated caller was served'; exception when insufficient_privilege then null; end; end $$;
set local fx.uid = '90000000-0000-0000-0000-000000000002';
do $$ begin begin perform public.admin_provider_description_funnel_v1(); raise exception 'FAILED: a viewer was served'; exception when insufficient_privilege then null; end; end $$;
set local fx.uid = '90000000-0000-0000-0000-000000000003';
do $$
declare f jsonb := public.admin_provider_description_funnel_v1(); s jsonb;
begin
  s := (select jsonb_object_agg(x->>'key', (x->>'n')::int) from jsonb_array_elements(f->'stages') x);
  perform pg_temp.ok(f->>'contract' = 'provider-description-funnel-v1', 'the contract is named');
  perform pg_temp.ok((s->>'registry')::int >= (s->>'live')::int and (s->>'live')::int >= (s->>'website')::int, 'registry >= live >= website');
  perform pg_temp.ok((s->>'policy_scope')::int >= (s->>'run_scope')::int and (s->>'run_scope')::int >= 1, 'policy scope >= run scope (the pinned providers)');
  perform pg_temp.ok((s->>'policy_scope')::int = (select count(*) from catalogue.providers p join ref.countries k on k.id = p.country_id join ref.provider_types t on t.id = p.provider_type_id
        where p.lifecycle_status = 'active' and p.publication_status = 'published' and security.toolset_setting('pipeline', 'pdesc.countries') ? k.iso_alpha2::text and security.toolset_setting('pipeline', 'pdesc.provider_types') ? t.code
          and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)), 'the policy scope count equals an independent count');
  perform pg_temp.ok((s->>'proposed')::int = (select count(*) from catalogue.providers p where exists (select 1 from pipeline.provider_description_reads r where r.provider_id = p.id and r.state = 'proposed'
        and r.id = (select r2.id from pipeline.provider_description_reads r2 where r2.provider_id = p.id order by r2.created_at desc, r2.id desc limit 1))), 'proposed equals the providers whose latest read is proposed');
  perform pg_temp.ok((f->'layer4'->>'pending')::int = (select count(*) from pipeline.layer4_review_items where field_code = 'provider_description' and status = 'pending'), 'Layer 4 pending equals the Inbox rows');
  perform pg_temp.ok(f ? 'stall' and f->'next_run' ? 'exclusions' and f ? 'held_reasons' and f ? 'job' and f ? 'spend', 'stall reason, next-run exclusions, held reasons, job and spend are present');
  perform pg_temp.ok(f->>'stall' in ('reader_off', 'job_paused', 'review_full', 'next_run_will_queue', 'run_scope_limited_by_pdesc_provider_keys', 'waiting_for_reviewers', 'no_eligible_provider_in_scope'), 'the stall reason is one of the named reasons: ' || (f->>'stall'));
end $$;
-- the stall reason follows the settings: reader off; scope limited
update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'pipeline' and key = 'pdesc.enabled';
select pg_temp.ok(public.admin_provider_description_funnel_v1()->>'stall' = 'reader_off', 'reader off is reported');
update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'pdesc.enabled';
-- nothing was written, decided or published
select pg_temp.ok((select reads = (select count(*) from pipeline.provider_description_reads) and items = (select count(*) from pipeline.layer4_review_items)
                          and described = (select count(*) from catalogue.providers where nullif(btrim(description), '') is not null) from before_state), 'no read, item or description was written');
select pg_temp.ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'admin_provider_description_funnel_v1' and p.provolatile <> 's'), 'the function is STABLE (read only)');
select pg_temp.ok(has_function_privilege('authenticated', 'public.admin_provider_description_funnel_v1()', 'EXECUTE') and not has_function_privilege('anon', 'public.admin_provider_description_funnel_v1()', 'EXECUTE'), 'authenticated may execute, anon may not');
-- the live shape: the run scope pinned to a few providers that all have a read, four proposals waiting for people, the rest of the policy scope outside the run scope
do $$
declare f jsonb; pr record; it uuid;
begin
  update pipeline.platform_toolset_settings set value = '["fixture:provider:1","fixture:provider:2","fixture:provider:3","fixture:provider:4","fixture:provider:5"]'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.provider_keys';
  for pr in select id, stable_key from catalogue.providers where stable_key in ('fixture:provider:1','fixture:provider:2','fixture:provider:3','fixture:provider:4') loop
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, proposed_value, status) values ('provider', pr.id, 'provider_description', '{"sentences":[]}', 'pending') returning id into it;
    insert into pipeline.provider_description_reads(provider_id, state, review_item_id, content_hash, source_url) values (pr.id, 'proposed', it, (select a.content_hash from pipeline.evidence_artifacts a where a.id = security.provider_description_stored_v1(pr.id)), 'https://x.example.edu/about');
  end loop;
  insert into pipeline.provider_description_reads(provider_id, state, rule, content_hash, source_url, updated_at)
    select p.id, 'held', 'quote_not_on_page', a.content_hash, 'https://p5.example.edu/about', now() - interval '1 day' from catalogue.providers p join pipeline.evidence_artifacts a on a.id = security.provider_description_stored_v1(p.id) where p.stable_key = 'fixture:provider:5';
  f := public.admin_provider_description_funnel_v1();
  perform pg_temp.ok(f->>'stall' = 'run_scope_limited_by_pdesc_provider_keys', 'the live shape reports the run scope as the limit: ' || (f->>'stall'));
  perform pg_temp.ok((f->>'policy_scope_outside_run_scope')::int > 0 and (f->'layer4'->>'pending')::int = 4, 'policy scope outside the run scope and the four waiting proposals are reported');
  perform pg_temp.ok((f->'next_run'->>'eligible')::int = 0, 'nothing is eligible for the next run');
  perform pg_temp.ok(exists (select 1 from jsonb_array_elements(f->'held_reasons') x where x->>'rule' = 'quote_not_on_page' and (x->>'n')::int = 1), 'the held reason is counted');
  perform pg_temp.ok(exists (select 1 from jsonb_array_elements(f->'next_run'->'exclusions') x where x->>'reason' = 'existing_work' and (x->>'n')::int = 4), 'four providers are excluded as existing work');
  update pipeline.platform_toolset_settings set value = '[]'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.provider_keys';
  perform pg_temp.ok(public.admin_provider_description_funnel_v1()->>'stall' = 'next_run_will_queue', 'clearing the pin makes the next run queue (a setting, not code)');
end $$;
rollback;
select 'pdesc-retry-funnel fixtures: passed';
