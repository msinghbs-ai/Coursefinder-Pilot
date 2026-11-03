-- CF-247 P0 Autonomous AI Operations, workstream B: one worker release (coverage-sweep v0.59.5) for the other workstreams' interface requests
-- (Integration Controller 3 Nov 2026 18:20; branch cf247-ops-b2; spec s254). This migration holds only what the worker needs from the database.
-- Why (live, read-only, 3 Nov 2026 18:15-18:35 AEDT):
--   1 Workstream A (v2.15.429) queues AI diagnosis requests (pipeline.ops_ai_diagnosis_requests); A2 (migration 20261104100000, contract
--     ops-diagnose-v1) serves them through public.svc_ops_diagnosis_next (md5 adc209eb...) and public.svc_ops_diagnosis_record (md5 6f1fd771...),
--     but no worker mode reads them and no job calls one: ops.ai_diagnosis_on cannot be switched on usefully.
--   2 Workstream D (v2.15.430) added public.svc_enrich_ai_stash_v1 (md5 70a97d7a...); the worker did not call it (ops.answer_replay_on needs it).
--   3 Workstream C: the entry matrix reader dropped all 8 UWA China rows printed as ranges ("488 to 491") as value_not_in_quote, keeping no value;
--     stored UWA US Advanced Placement subject equivalences as seven minimums with one identity; and holds RMIT's International Baccalaureate and
--     Global Assessment Certificate pages as naming no country.
--   4 Workstream F (v2.15.432): about 70% of paid course-page searches repeat a query already searched (ops_cost.repeat_search_hours window).
-- What:
--   1 Job ops-diagnose (catalogued; '27,57 * * * *', outside the load policy's busy minutes) calls worker mode ops_diagnose with
--     batch.ops_diagnose requests, and only while ops.ai_diagnosis_on is 1 and a request waits: with the switch at 0 (as shipped) it does nothing.
--   2 Settings the worker reads through svc_worker_settings_v1 (prefix reading.): the diagnosis answer limit; the three reader behaviours that
--     change what is proposed (each ships off); the global-qualification names and phrases; the query-shared search switch (ships off).
--   3 public.svc_course_link_search_prior_v1(queries): for each query, the URLs of the latest answered search with the same query inside
--     ops_cost.repeat_search_hours (workstream F's lookback), read-only; used by link_search only with reading.link_search_share_on.
-- Spend: none by this migration. ops_diagnose spends AI only when the Platform Admin sets ops.ai_diagnosis_on (within ops.ai_requests_per_day and
--   budgets.ai_daily_ceiling_usd, both enforced by svc_ops_diagnosis_next). Query sharing only removes paid searches.
-- Consumer API (G3): untouched.
-- Activation (recorded setting changes, separate from this release): ops.ai_diagnosis_on 1 (workstream A, Platform Admin); reading.entry_range_lower_bound_on,
--   reading.entry_subject_rows_on, reading.entry_global_pages_on 1 (workstream C, after review); reading.link_search_share_on 1 (Integration Controller).
-- Replaces: nothing (the worker's own behaviour changes are in coverage-sweep v0.59.5)
-- Retires: nothing
-- Nothing is dropped or deleted.

do $g$
begin
  if to_regclass('pipeline.ops_ai_diagnosis_requests') is null or to_regprocedure('public.svc_ops_diagnosis_next(integer)') is null
     or to_regprocedure('public.svc_ops_diagnosis_record(bigint,jsonb,numeric)') is null or to_regprocedure('public.svc_enrich_ai_stash_v1(jsonb)') is null then
    raise exception 'worker requests: apply workstream A (20261104010000, 20261104100000) and workstream D (20261104020000) first';
  end if;
  -- contract ops-diagnose-v1: the definitions after workstream A2's migration 20261104100000
  if md5(pg_get_functiondef('public.svc_ops_diagnosis_next(integer)'::regprocedure)) <> 'adc209ebf9196c613e3dd82fa76fed61'
     or md5(pg_get_functiondef('public.svc_ops_diagnosis_record(bigint,jsonb,numeric)'::regprocedure)) <> '6f1fd77189ea85610a57c6feef16a130'
     or md5(pg_get_functiondef('public.svc_enrich_ai_stash_v1(jsonb)'::regprocedure)) <> '70a97d7a560571d2de2fecc68ea8ee64'
     or to_regprocedure('public.svc_course_link_search_record(uuid,integer,text[],text)') is null then  -- live only (no migration in the repository); called as before
    raise exception 'worker requests: a live function the worker v0.59.5 calls differs from the definition it was written against';
  end if;
end $g$;

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'batch.ops_diagnose', 'AI diagnosis: requests per worker call',
  'Job ops-diagnose asks the worker for at most this many AI diagnosis requests a call (the database also keeps ops.ai_requests_per_day and the daily AI ceiling).',
  'number', to_jsonb(5), 1, 20, 'requests', 1124, 'Operations controller', 'job ops-diagnose (worker mode ops_diagnose)', 'CF-247 ops B worker release (workstream A interface request, 3 Nov 2026 18:20)'),
 ('pipeline', 'reading.answer_tokens.ops_diagnosis', 'AI answer length: issue diagnosis',
  'Longest answer the AI diagnosis may give (tokens). An answer that reaches it is held, never parsed, and its cost recorded.',
  'number', to_jsonb(800), 200, 4000, 'tokens', 1125, 'Operations controller', 'worker coverage-sweep mode ops_diagnose (ops-diagnose.ts)', 'CF-247 ops B worker release (workstream A interface request)'),
 ('pipeline', 'reading.entry_range_lower_bound_on', 'Entry reader: a value within a printed range is its lower bound',
  'On (1): an entry-matrix row whose value is not printed but lies within exactly one range the quoted row prints ("488 to 491") takes the range''s printed lower bound (proposed to Layer 4 as usual). Off (0): dropped as value_not_in_quote, as before.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1126, 'Entry requirements', 'worker coverage-sweep mode entry_ai (entry.ts entryRangeLower)', 'CF-247 ops B worker release (workstream C interface request: UWA China rows); ships off'),
 ('pipeline', 'reading.entry_subject_rows_on', 'Entry reader: subject-equivalence rows as one subject-prerequisite row',
  'On (1): entry-matrix rows that share one identity (country, level, qualification, band, course) and each name a subject are proposed as one row with every subject and grade in its conditions. Off (0): one row each, as before.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1127, 'Entry requirements', 'worker coverage-sweep mode entry_ai (entry.ts entrySubjectRows)', 'CF-247 ops B worker release (workstream C interface request: UWA AP subjects); ships off'),
 ('pipeline', 'reading.entry_global_pages_on', 'Entry reader: read global-qualification pages',
  'On (1): an entry page whose heading names a global qualification (reading.entry_global_qualifications) and that says it applies whatever the country (reading.entry_global_phrases) is read instead of held for naming no country. Off (0): held, as before.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1128, 'Entry requirements', 'worker coverage-sweep mode entry_ai (entry.ts entryGlobalQualification)', 'CF-247 ops B worker release (workstream C interface request: RMIT IB and GAC); ships off'),
 ('pipeline', 'reading.entry_global_qualifications', 'Entry reader: global qualifications',
  'Qualifications taken in many countries whose entry page names no country (lower case, as the page heading names them).',
  'list', '["international baccalaureate", "ib diploma", "global assessment certificate", "gac"]'::jsonb, null, null, 'qualifications', 1129, 'Entry requirements',
  'worker coverage-sweep mode entry_ai (entry.ts entryGlobalQualification)', 'CF-247 ops B worker release (workstream C interface request)'),
 ('pipeline', 'reading.entry_global_phrases', 'Entry reader: words that say a qualification applies in any country',
  'A global-qualification page is read only when it prints one of these (lower case).',
  'list', '["regardless of country", "whatever country", "in any country", "from any country", "all countries", "irrespective of the country", "regardless of where"]'::jsonb, null, null, 'phrases', 1130, 'Entry requirements',
  'worker coverage-sweep mode entry_ai (entry.ts entryGlobalQualification)', 'CF-247 ops B worker release (workstream C interface request)'),
 ('pipeline', 'reading.link_search_share_on', 'Course-page search: one paid search per query',
  'On (1): the worker sends one course-page search per distinct query of its batch and records the answer for every course with that query, and records an earlier answer for the same query inside ops_cost.repeat_search_hours without a new search. Off (0): one search per course, as before.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1131, 'Course pages', 'worker coverage-sweep mode link_search (link-share.ts); public.svc_course_link_search_prior_v1', 'CF-247 ops B worker release (workstream F finding: 70% repeat searches); ships off')
on conflict (toolset_key, key) do nothing;
update pipeline.platform_toolset_settings set used_by = used_by || '; public.svc_course_link_search_prior_v1 (reused answers)', updated_at = now()
 where toolset_key = 'pipeline' and key = 'ops_cost.repeat_search_hours' and coalesce(used_by, '') not like '%svc_course_link_search_prior_v1%';

-- 2. an earlier answer for the same query (read-only) ----------------------------------------------------------------------------------------
create or replace function public.svc_course_link_search_prior_v1(p_queries text[]) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 ops B (workstream F finding): for each query (in the worker's form: NFKC, lower case, spaces collapsed), the URLs of the latest answered
-- course-page search with the same query inside ops_cost.repeat_search_hours (an empty list is an earlier "no result"). A search still being
-- answered (state sent) is not an earlier answer. Read-only.
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (select coalesce(jsonb_object_agg(z.k, z.results), '{}'::jsonb) from (
    select distinct on (k) k, s.results
      from pipeline.course_link_search s
      cross join lateral (select lower(btrim(regexp_replace(normalize(coalesce(s.query, ''), NFKC), '\s+', ' ', 'g'))) k) n
     where n.k = any (p_queries) and n.k <> '' and s.state <> 'sent' and jsonb_typeof(s.results) = 'array'
       and s.sent_at >= now() - make_interval(hours => security.pipeline_num_v1('ops_cost.repeat_search_hours', 24)::int)
     order by k, s.sent_at desc) z);
end $function$;
revoke all on function public.svc_course_link_search_prior_v1(text[]) from public, anon, authenticated;
do $r$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then execute 'grant execute on function public.svc_course_link_search_prior_v1(text[]) to service_role'; end if;
end $r$;

-- 3. job ops-diagnose (G1; no number in its command) --------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('ops-diagnose', 'Platform upkeep', 61, 'AI diagnosis of low-confidence issues',
  'At :27 and :57: while ops.ai_diagnosis_on is 1 and a diagnosis request waits, the worker (mode ops_diagnose) reads up to batch.ops_diagnose requests with the pinned model (ops.ai_diagnosis_model) and records each answer through public.svc_ops_diagnosis_record, which checks the cause and the quotes. Does nothing while the switch is 0 (as shipped). Spends AI within ops.ai_requests_per_day and the daily AI ceiling.',
  4, true)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'ops-diagnose') then
    perform cron.schedule('ops-diagnose', '27,57 * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'ops_diagnose', 'limit', security.pipeline_num_v1('batch.ops_diagnose', 5)::int)) where security.pipeline_num_v1('ops.ai_diagnosis_on', 0) >= 1 and exists (select 1 from pipeline.ops_ai_diagnosis_requests q where q.state = 'queued' or (q.state = 'leased' and q.leased_until < now()))$c$);
  end if;
end $j$;

-- 4. component register ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'ops-diagnose', 'Platform', 'Platform upkeep', 'Worker mode ops_diagnose: AI diagnosis of low-confidence integration issues (off until ops.ai_diagnosis_on)', 'active', '{}', '20261104110000')
on conflict do nothing;

-- 5. post-check ------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('reading.entry_range_lower_bound_on', 'reading.entry_subject_rows_on',
        'reading.entry_global_pages_on', 'reading.link_search_share_on') and (value #>> '{}')::numeric = 0) <> 4 then
    raise exception 'worker requests post-check: a behaviour that changes what is proposed or searched did not ship off'; end if;
  if not exists (select 1 from cron.job where jobname = 'ops-diagnose' and command like '%ops.ai_diagnosis_on%') then raise exception 'worker requests post-check: job ops-diagnose'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'ops-diagnose') then raise exception 'worker requests post-check: job ops-diagnose is not catalogued'; end if;
end $$;
