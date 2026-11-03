-- CF-247 Workstream F fixtures, AFTER the 20261103140000 migration (applied twice by run.sh) on the data fixtures-before.sql seeded. Today's
-- values give today's behaviour (compared with fx.before_*); the settings change it; each hidden failure is now visible or gone.
-- Prints one NOTICE "ok: ..." per assertion; any failure raises and stops the run. Nothing here is live data.
set timezone = 'UTC';
create or replace function fx.set(p_key text, p_value jsonb) returns void language sql as
  $f$ update pipeline.platform_toolset_settings set value = p_value where toolset_key = 'pipeline' and key = p_key $f$;

-- 0. the migration: settings, jobs, catalogue, register, privileges -------------------------------------------------------------------------
do $t$ begin
  perform fx.ok((select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('enrich.focus_countries', 'scholarship.refill_priority_countries',
    'scholarship.refill_open_countries', 'scholarship.refill_priority_focus', 'scholarship.refill_priority_other', 'country_scope.gate_countries', 'integration.watched_modes',
    'integration.watched_mode_min_failures', 'ranking.edition_calendar', 'ranking.edition_grace_days', 'ranking.import_max_age_days')
    and label is not null and unit is not null and used_by is not null and section is not null) = 11, 'eleven settings, each with a label, unit, section and used_by (G2)');
  perform fx.ok((select value from pipeline.platform_toolset_settings where key = 'enrich.focus_countries') = '["AU"]' and (select value from pipeline.platform_toolset_settings where key = 'country_scope.gate_countries') = '["CA"]'
    and (select value from pipeline.platform_toolset_settings where key = 'scholarship.refill_priority_countries') = '["AU"]' and (select value from pipeline.platform_toolset_settings where key = 'scholarship.refill_open_countries') = '["AU"]',
    'country lists ship with today''s values');
  perform fx.ok((select command from cron.job where jobname = 'cricos-peo') = 'select security.cricos_peo_fire_v1()' and (select active from cron.job where jobname = 'cricos-peo'), 'cricos-peo: new command, still active, same schedule');
  perform fx.ok((select schedule from cron.job where jobname = 'cricos-peo') = '* * * * *', 'cricos-peo keeps its schedule');
  perform fx.ok((select command from cron.job where jobname = 'country-scope-gate') = 'select security.country_scope_gate_run_v1()' and (select active from cron.job where jobname = 'country-scope-gate'), 'country-scope-gate: no country in the command, still active');
  perform fx.ok((select active from cron.job where jobname = 'ranking-edition-check') is false, 'ranking-edition-check created paused');
  perform fx.ok(exists (select 1 from pipeline.automation_catalogue where jobname = 'ranking-edition-check'), 'ranking-edition-check catalogued (G1)');
  perform fx.ok((select description from pipeline.automation_catalogue where jobname = 'cricos-peo') like '%only when a provider is due%'
            and (select description from pipeline.automation_catalogue where jobname = 'country-scope-gate') like '%country_scope.gate_countries%', 'the catalogue describes the new behaviour');
  perform fx.ok((select count(*) from pipeline.component_register where introduced_in = '20261103140000') = 6, 'component register: one job, five functions');
  perform fx.ok(not has_function_privilege('authenticated', 'security.ranking_edition_check_v1()', 'execute') and not has_function_privilege('anon', 'security.pipeline_list_v1(text,jsonb)', 'execute')
            and not has_function_privilege('authenticated', 'security.cricos_peo_fire_v1()', 'execute'), 'clients cannot run the new functions');
  perform fx.ok(security.pipeline_list_v1('no.such.key', '["X"]') = array['X'] and security.pipeline_list_v1('integration.hidden_error_min_failures', '["Y"]') = array['Y'], 'the list reader falls back to its default for a missing or non-list setting');
  perform fx.ok(pg_get_functiondef('security.enrich_focus_v1(uuid)'::regprocedure) !~ '<> ''AU''' and pg_get_functiondef('security.enrich_focus_refresh_v1()'::regprocedure) !~ '= ''AU'''
            and pg_get_functiondef('security.scholarship_discovery_refill_v1(integer)'::regprocedure) !~ '(=|<>) ''AU''', 'no country comparison left in the shared orchestration');
end $t$;

-- 1. (d) focus: today's value gives today's behaviour; the setting changes it --------------------------------------------------------------------
truncate pipeline.enrich_focus_providers;
select security.enrich_focus_refresh_v1();
do $t$ begin
  perform fx.ok((select array_agg(row(stable_key, searched, in_focus, rk)::text order by stable_key) from fx.before_focus)
              = (select array_agg(row(p.stable_key, security.enrich_focus_v1(p.id), f.in_focus, f.rank)::text order by p.stable_key) from catalogue.providers p left join pipeline.enrich_focus_providers f on f.provider_id = p.id),
              'focus with ["AU"]: the same providers searched, the same focus list and ranks as before');
  perform fx.set('enrich.focus_countries', '["AU", "NZ"]');
  truncate pipeline.enrich_focus_providers; perform security.enrich_focus_refresh_v1();
  perform fx.ok((select count(*) from pipeline.enrich_focus_providers f join fx.country c using (provider_id) where c.cc = 'NZ' and f.in_focus) = 2
            and (select count(*) from pipeline.enrich_focus_providers f join fx.country c using (provider_id) where c.cc = 'AU' and f.in_focus) = 2, 'focus with ["AU", "NZ"]: the top 2 within each country');
  perform fx.set('enrich.focus_countries', '["NZ"]');
  perform fx.ok((select bool_and(security.enrich_focus_v1(p.id)) from catalogue.providers p join fx.country c on c.provider_id = p.id where c.cc = 'AU'), 'focus with ["NZ"]: every Australian provider searched');
  perform fx.set('enrich.focus_countries', '["AU"]');
  truncate pipeline.enrich_focus_providers; perform security.enrich_focus_refresh_v1();
end $t$;

-- 2. (d) scholarship refill ----------------------------------------------------------------------------------------------------------------
truncate pipeline.scholarship_discovery_providers;
select security.scholarship_discovery_refill_v1(30);
do $t$ begin
  perform fx.ok((select array_agg(row(stable_key, priority, reason, status)::text order by stable_key) from fx.before_refill)
              = (select array_agg(row(p.stable_key, d.priority, d.reason, d.status)::text order by p.stable_key) from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id),
              'refill with today''s values: the same providers, priorities and reasons as before');
  truncate pipeline.scholarship_discovery_providers;
  perform fx.set('scholarship.refill_priority_countries', '["NZ"]'); perform fx.set('scholarship.refill_open_countries', '["AU", "CA"]');
  perform security.scholarship_discovery_refill_v1(30);
  perform fx.ok((select array_agg(p.stable_key || ':' || d.priority || ':' || d.reason order by p.stable_key) from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id)
              = array['a1:1:university_au', 'a2:1:university_au', 'a3:1:university_au', 'c1:1:university_ca', 'n1:4:largest_unsearched'],
              'refill with NZ first and AU, CA open: NZ priority 4; CA queued; NZ still only through the admission rule');
  perform fx.set('scholarship.refill_priority_focus', '7');
  truncate pipeline.scholarship_discovery_providers; perform security.scholarship_discovery_refill_v1(30);
  perform fx.ok((select d.priority from pipeline.scholarship_discovery_providers d where d.provider_id = '00000000-0000-0000-0000-0000000000b1') = 7, 'the priority is a setting');
  perform fx.set('scholarship.refill_priority_countries', '["AU"]'); perform fx.set('scholarship.refill_open_countries', '["AU"]'); perform fx.set('scholarship.refill_priority_focus', '4');
end $t$;

-- 3. (d) country scope gate: the countries come from the setting ---------------------------------------------------------------------------------
truncate fx.fired;
do $t$ declare v jsonb; begin
  execute (select command from cron.job where jobname = 'country-scope-gate') into v;
  perform fx.ok((select array_agg(body->>'country') from fx.fired where what = 'country_scope_gate') = array['CA'] and v ? 'CA', 'country-scope-gate with ["CA"]: Canada, as before');
  truncate fx.fired; perform fx.set('country_scope.gate_countries', '["CA", "NZ"]');
  execute (select command from cron.job where jobname = 'country-scope-gate') into v;
  perform fx.ok((select array_agg(body->>'country' order by id) from fx.fired where what = 'country_scope_gate') = array['CA', 'NZ'], 'country-scope-gate with ["CA", "NZ"]: both, one call each');
  perform fx.set('country_scope.gate_countries', '["CA"]');
end $t$;

-- 4. (c) cricos-peo: no call while nothing is due; a due provider is called with the batch setting ---------------------------------------------
truncate fx.fired;
do $t$ declare v int; begin
  execute (select command from cron.job where jobname = 'cricos-peo') into v;
  perform fx.ok(v = 0 and not exists (select 1 from fx.fired), 'cricos-peo with nothing due: the worker is not called');
  update pipeline.provider_contact_checks set checked_at = now() - interval '200 days' where provider_id = '00000000-0000-0000-0000-0000000000a2';
  execute (select command from cron.job where jobname = 'cricos-peo') into v;
  perform fx.ok(v = 1 and (select body from fx.fired where what = 'coverage-sweep') = '{"mode": "cricos_peo", "limit": 2}'::jsonb, 'a provider due again: one worker call, its size from batch.cricos_peo');
  perform fx.ok(public.svc_cricos_peo_next(4)->0->>'provider_id' = '00000000-0000-0000-0000-0000000000a2', 'and the worker''s picker finds that provider (same eligibility)');
  truncate fx.fired;
  execute (select command from cron.job where jobname = 'cricos-peo') into v;
  perform fx.ok(v = 0, 'once leased (a check in flight) the job does not call the worker again');
  update pipeline.provider_contact_checks set checked_at = now() - interval '2 days', outcome = 'budget' where provider_id = '00000000-0000-0000-0000-0000000000a2';
  execute (select command from cron.job where jobname = 'cricos-peo') into v;
  perform fx.ok(v = 1, 'a provider left by the budget is due, as the picker says');
  update pipeline.provider_contact_checks set checked_at = now() - interval '20 days', outcome = 'found';
  update catalogue.providers set publication_status = 'unpublished' where id = '00000000-0000-0000-0000-0000000000a1';
  update pipeline.provider_contact_checks set checked_at = now() - interval '200 days' where provider_id = '00000000-0000-0000-0000-0000000000a1';
  truncate fx.fired; execute (select command from cron.job where jobname = 'cricos-peo') into v;
  perform fx.ok(v = 0, 'an unpublished provider is not due (the picker''s pause respected)');
  update catalogue.providers set publication_status = 'published' where id = '00000000-0000-0000-0000-0000000000a1';
end $t$;

-- 5. (b) the NZ picker returns the same files ---------------------------------------------------------------------------------------------------
do $t$ begin
  perform fx.ok(public.svc_nz_cop_next(10) = (select v from fx.before_nzcop), 'NZ Code of Practice picker: the same files as before');
  perform fx.ok(jsonb_array_length(public.svc_nz_cop_next(1)) = 1 and public.svc_nz_cop_next(1)->0->>'path' = 'regulatory/NZ/nzqa/new-offset-20-batch-20.json', 'its limit and order unchanged');
  insert into pipeline.nz_cop_reads(path, error, reader) values ('regulatory/NZ/nzqa/new-offset-20-batch-20.json', null, 'v2'), ('regulatory/NZ/nzqa/new-offset-40-batch-20.json', 'stored file missing', 'v2');
  perform fx.ok(public.svc_nz_cop_next(10)->0->>'path' = 'regulatory/NZ/nzqa/new-offset-40-batch-20.json' and jsonb_array_length(public.svc_nz_cop_next(10)) = 1, 'a file read with an error is offered again; a read file is not');
end $t$;

-- 6. (f) the yield checks ----------------------------------------------------------------------------------------------------------------------
select security.integration_yield_checks_v1();
do $t$ begin
  perform fx.ok(exists (select 1 from pipeline.integration_issues where fingerprint = 'hidden_worker_error:coverage-sweep:provider_description' and severity = 'P1'),
    'a watched mode (provider_description, 2 of 2 failed) opens its hidden-error issue on the next check');
  perform fx.ok(not exists (select 1 from pipeline.integration_issues where fingerprint = 'hidden_worker_error:coverage-sweep:read'), 'an unwatched mode below the thresholds still opens nothing');
  perform fx.ok((select condition_cleared_at from pipeline.integration_issues where fingerprint = 'zero_yield:link_search') is not null,
    'link_search held by its own daily cap, no failures: idle, the zero-yield issue marked cleared (not closed)');
  perform fx.ok((select status from pipeline.integration_issues where fingerprint = 'zero_yield:link_search') <> 'closed', 'it is never closed by the check');
end $t$;
do $t$ declare v jsonb; begin
  v := security.integration_yield_checks_v1();
  perform fx.ok(v->'idle_by_cap' ? 'link_search', 'the run reports the lane as idle by its cap');
  update pipeline.integration_yield_buckets set failures = 1 where kind = 'ledger' and key = 'link_search';
  perform security.integration_yield_checks_v1();
  perform fx.ok((select condition_cleared_at from pipeline.integration_issues where fingerprint = 'zero_yield:link_search') is null, 'with a failure in the window the cap does not hide it: zero yield again');
  update pipeline.integration_yield_buckets set failures = 0 where kind = 'ledger' and key = 'link_search';
  delete from pipeline.course_link_search where id in (select id from pipeline.course_link_search limit 10);
  perform security.integration_yield_checks_v1();
  perform fx.ok((select condition_cleared_at from pipeline.integration_issues where fingerprint = 'zero_yield:link_search') is null, 'below its cap with work waiting: still zero yield');
  perform fx.set('integration.watched_modes', '["enrich_ai"]');
  update pipeline.integration_issues set status = 'closed' where fingerprint = 'hidden_worker_error:coverage-sweep:provider_description';
  perform security.integration_yield_checks_v1();
  perform fx.ok((select status from pipeline.integration_issues where fingerprint = 'hidden_worker_error:coverage-sweep:provider_description') = 'closed', 'the watched list is a setting (provider_description taken off: no reopening)');
  perform fx.set('integration.watched_modes', '["provider_description", "enrich_ai"]');
  perform fx.ok((select count(*) from pipeline.integration_issues where fingerprint like 'hidden_worker_error:%') = 1, 'one issue per mode, no duplicates');
end $t$;

-- 7. (f) Pipeline yield: the Enrich fields lane ------------------------------------------------------------------------------------------------
do $t$ declare v jsonb; j uuid; begin
  update pipeline.admin_jobs set updated_at = now() - interval '3 days', finished_at = null;  -- the lock-test tasks are outside the window
  insert into pipeline.admin_jobs(kind, state, finished_at) values ('enrich_fields', 'done', now()) returning id into j;
  insert into pipeline.field_enrich_items(job_id, field, state, value, evidence_id) values
    (j, 'english', 'filled', '{"x": 1}', gen_random_uuid()), (j, 'english', 'review', '{"x": 1}', gen_random_uuid()), (j, 'intakes', 'skipped', null, gen_random_uuid()),
    (j, 'intakes', 'failed', null, null), (j, 'campus', 'skipped', null, null);
  insert into pipeline.mode_outcome_ledger(mode, status, items, ok, failed) values ('enrich_ai', 200, 4, 4, 0), ('enrich_ai', 500, 0, 0, 1);
  v := (select l from jsonb_array_elements(security.pipeline_yield_v1(24)->'lanes') l where l->>'lane' = 'enrich_fields');
  perform fx.ok(jsonb_array_length(security.pipeline_yield_v1(24)->'lanes') = 5, 'five lanes');
  perform fx.ok(v->'stages'->'invoked' = '{"calls": 2, "failed_calls": 1}', 'Enrich fields: invoked 2, one failed (the 500 is not success)');
  perform fx.ok((v->'stages'->>'source_accessed')::int = 3 and (v->'stages'->>'read_completely')::int = 4 and (v->'stages'->>'extracted')::int = 2, 'stored pages 3, settled 4, values read 2');
  perform fx.ok(v->'stages'->'accepted_or_held' = '{"accepted": 1, "held": 1, "not_stated": 2, "failed": 1}' and (v->'stages'->>'published')::int = 1, 'accepted 1, held 1, not stated 2, failed 1; published 1');
  perform fx.ok(v->'stages'->'pages_discovered' = 'null' and v->'stages'->'consumer_read_back' = 'null', 'stages it does not have are shown as not held');
  perform fx.ok((select count(*) from jsonb_array_elements(security.pipeline_yield_v1(24)->'lanes') l where l->>'lane' in ('scholarships', 'course_pages', 'aer', 'descriptions')) = 4, 'the four lanes are unchanged');
end $t$;

-- 8. (e) ranking edition check: one issue per ranking system, nothing imported ------------------------------------------------------------------
-- the calendar here is set from today's date so the fixture does not depend on the day it runs: every edition of this year + 1 is out
insert into ranking.systems(code, publisher_name, ranking_name, official_url) values ('qs_wur', 'QS', 'QS World University Rankings', 'https://qs.example'),
  ('the_wur', 'THE', 'THE World University Rankings', 'https://the.example'), ('arwu', 'ShanghaiRanking', 'ARWU', 'https://arwu.example');
insert into ranking.systems(code, publisher_name, ranking_name, active) values ('old', 'Old', 'An inactive ranking', false);
do $t$ declare y int := extract(year from now())::int; v jsonb; n_obs int; begin
  perform fx.set('ranking.edition_calendar', '["qs_wur:1:1", "the_wur:1:1", "arwu:1:1", "old:1:1"]'); perform fx.set('ranking.edition_grace_days', '0');
  insert into ranking.editions(system_id, edition_year, status) select id, y + 1, 'accepted' from ranking.systems where code = 'qs_wur';
  insert into ranking.editions(system_id, edition_year, status) select id, y, 'accepted' from ranking.systems where code = 'the_wur';
  insert into ranking.editions(system_id, edition_year, status) select id, y + 1, 'rejected' from ranking.systems where code = 'the_wur';
  insert into ranking.manual_imports(system_id, edition_year, status, uploaded_at) select id, y, 'applied', now() - interval '60 days' from ranking.systems where code in ('qs_wur', 'the_wur');
  select count(*) into n_obs from ranking.editions;
  v := security.ranking_edition_check_v1();
  perform fx.ok((select array_agg(fingerprint order by fingerprint) from pipeline.integration_issues where fingerprint like 'ranking_edition:%') = array['ranking_edition:arwu', 'ranking_edition:the_wur'],
    'THE (edition not held; a rejected edition does not count) and ARWU (none held, never imported) raise one issue each; QS current; an inactive system never');
  perform fx.ok((select failure from pipeline.integration_issues where fingerprint = 'ranking_edition:arwu') like '%no edition held%last file import never%', 'the issue says what is missing');
  perform fx.ok((select severity || root_cause_class || layer from pipeline.integration_issues where fingerprint = 'ranking_edition:the_wur') = 'P2missing_dependencyLayer 1', 'P2, a licensed file is the missing dependency');
  perform security.ranking_edition_check_v1(); perform security.ranking_edition_check_v1();
  perform fx.ok((select count(*) from pipeline.integration_issues where fingerprint like 'ranking_edition:%') = 2, 'repeated runs: no duplicate issues');
  perform fx.ok((select count(*) from ranking.editions) = n_obs and (select count(*) from ranking.manual_imports) = 2, 'nothing imported or changed in the ranking tables');
  insert into ranking.editions(system_id, edition_year, status) select id, y + 1, 'accepted' from ranking.systems where code = 'the_wur';
  perform security.ranking_edition_check_v1();
  perform fx.ok((select condition_cleared_at from pipeline.integration_issues where fingerprint = 'ranking_edition:the_wur') is not null
            and (select status from pipeline.integration_issues where fingerprint = 'ranking_edition:the_wur') <> 'closed', 'the new edition imported: THE marked cleared, closed only after verification');
  update ranking.manual_imports set uploaded_at = now() - interval '500 days' where system_id = (select id from ranking.systems where code = 'qs_wur');
  perform security.ranking_edition_check_v1();
  perform fx.ok((select failure from pipeline.integration_issues where fingerprint = 'ranking_edition:qs_wur') like 'last file import % (older than 400 days)', 'an import older than ranking.import_max_age_days raises one for QS');
  perform fx.set('ranking.import_max_age_days', '1000'); perform security.ranking_edition_check_v1();
  perform fx.ok((select condition_cleared_at from pipeline.integration_issues where fingerprint = 'ranking_edition:qs_wur') is not null, 'the age is a setting');
  perform fx.set('ranking.edition_calendar', '["qs_wur:x:1", "the_wur:13:1"]');
  v := security.ranking_edition_check_v1();
  perform fx.ok((select count(*) from jsonb_array_elements(v->'systems') s where s->>'expected' is not null) = 0, 'a malformed calendar entry is ignored, never an error');
end $t$;
