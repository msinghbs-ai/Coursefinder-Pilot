-- CF-247 Workstream F: failures hidden behind a succeeded schedule, and country rules moved out of shared orchestration into country settings
-- (Platform Admin direction 3 Nov 2026 09:32, admin docs/platform/nz-enrichment-brief/2026-11-03-platform-led-enrichment-autonomy-mandate-0932.md
-- §4, §5 "detects hidden failures" and §7 "do not hardcode Australia-specific provider selection into the shared orchestration layer";
-- acceptance report 2026-11-03-platform-enrichment-control-autonomy-acceptance-report.md, engineering plan items 5 and 7).
-- Why (production, read-only, 3 Nov 2026 10:10-10:30 AEDT):
--   (a) enrich_ai, IQ-00053: 173 worker calls answered HTTP 500 "svc_enrich_ai_record: canceling statement due to statement timeout" between
--       05:27 and 05:40 (2,240 items of the standing gap task then settled as "no answer could be recorded after 3 tries", 586 of them English;
--       their AI cost was spent and rolled back with the record). Postgres log context on every one: "while locking tuple (981,9) in relation
--       admin_jobs ... SELECT 1 FROM ONLY pipeline.admin_jobs x WHERE id = $1 FOR KEY SHARE OF x". The record updates a field_enrich_items row
--       a second time in its transaction, so the foreign key to admin_jobs is checked (FOR KEY SHARE). The admin-jobs runner
--       (security.admin_jobs_tick_v1, each minute, 1.5-1.8 minutes a run from 05:25 to 05:41) holds the task's admin_jobs row FOR UPDATE for
--       its whole run, and the slices it calls (admin_job_slice_v1, enrich_fields_slice_v1, admin_job_watch_v1) take FOR UPDATE again; the
--       slice itself fires the enrich_ai workers (enrich_ai_fire_v1). FOR UPDATE conflicts with FOR KEY SHARE, so every record call made while
--       the runner held the row waited for the 8 s PostgREST lock and statement time-out. The 503 BOOT_ERROR answers in the same hour (21 of
--       194 failed answers) are the edge runtime refusing new isolates during the same burst; they are retried and are not this cause.
--   (b) nz_cop "never succeeded": it did its work. 63 NZQA files read (reader v2), 416 provider statuses, 189 signatories, 197 providers'
--       international-enrolment flag set (last change 20 Oct). Two faults hid that: the worker's answer carried no item count, so the ledger
--       recorded 0 items on every call; and its picker public.svc_nz_cop_next timed out on 19 of its last 30 calls (12.3 s against the 8 s
--       limit: a correlated max() over the 1,733 NZQA batch files ran once per file, 1.2 million buffer reads). Since 31 Oct nothing is new.
--   (c) cricos_peo: the caller is the cron job cricos-peo itself (jobid 147, active, every minute, 1,020 runs in 24 h; 1,008 ledger calls,
--       all with providers: []). It is not paused. All 1,546 Australian CRICOS providers were checked on 11 Oct and are due again after
--       recheck.cricos_contact_days (180), so nothing is due before April 2027. The job calls the worker without asking whether any work is due.
--   (d) Country literals in shared orchestration: security.enrich_focus_v1 (coverage_country <> 'AU'), security.enrich_focus_refresh_v1
--       (country_code = 'AU'), security.scholarship_discovery_refill_v1 (priority 4 and the reason for 'AU'; every Australian provider, others
--       only through the admission rule) and the country-scope-gate job command (security.country_scope_gate_v1(true, 'CA')).
--   (e) Rankings: no job checks for a new edition. QS editions held to 2027; THE to 2026 (THE 2027 is published, not held); ARWU none.
--       statistics-edition-discovery covers QILT and PRISMS files only (pipeline.statistics_edition_rules); the ranking import needs a licensed file.
--   (f) The yield checks open a hidden-error issue only after 3 failures and 25% of calls in 120 minutes: the hourly provider_description lane
--       failed its 2 calls in that window (IQ-00055) and raised nothing. The zero-yield check counted link_search as zero yield while its picker
--       was held by its own daily cap (IQ-00048). Pipeline yield had no Enrich fields lane.
-- What:
--   (a) The runner and the slices lock the task row FOR NO KEY UPDATE (the strongest lock that does not block a foreign-key check; they never
--       change the key). Skip-locked behaviour between runners is unchanged. 4 md5-guarded one-line edits.
--   (b) svc_nz_cop_next reads the latest batch time per source once (the same files are returned; 12.7 ms on production). Worker v0.59.3:
--       the nz_cop answer carries read and failed counts, so the ledger counts its work.
--   (c) Job cricos-peo runs security.cricos_peo_fire_v1(): the worker is called only when a provider is due (the picker's own eligibility,
--       without leasing; 22 ms). The job keeps its schedule and state; switched off, nothing runs, as before.
--   (d) Country lists in settings with today's values: enrich.focus_countries ["AU"], scholarship.refill_priority_countries ["AU"],
--       scholarship.refill_open_countries ["AU"], scholarship.refill_priority_focus 4, scholarship.refill_priority_other 1,
--       country_scope.gate_countries ["CA"]; read with security.pipeline_list_v1. The country-scope-gate command becomes
--       security.country_scope_gate_run_v1() (no literal). The focus list is ranked per country (one country today: unchanged).
--   (e) Job ranking-edition-check (daily, created PAUSED): one integration issue per active ranking system (fingerprint ranking_edition:<code>)
--       when the edition its publisher's calendar says is out (ranking.edition_calendar, ranking.edition_grace_days) is not held, or when the
--       last import is older than ranking.import_max_age_days or never happened. It imports nothing. Cleared when no longer seen.
--   (f) security.integration_yield_checks_v1: modes in integration.watched_modes (provider_description, enrich_ai) open a hidden-error issue at
--       integration.watched_mode_min_failures (1) failed answers in the window; a lane with no failures whose picker is held by its own daily
--       cap (security.worker_mode_capped_v1: link_search) is idle, not zero yield. security.pipeline_yield_v1 gains the Enrich fields lane.
-- Replaces: security.admin_jobs_tick_v1, security.admin_job_slice_v1, security.admin_job_watch_v1, security.enrich_fields_slice_v1, public.svc_nz_cop_next, security.enrich_focus_v1, security.enrich_focus_refresh_v1, security.scholarship_discovery_refill_v1, security.integration_yield_checks_v1, security.pipeline_yield_v1 (same names; md5-guarded); the commands of jobs cricos-peo and country-scope-gate
-- Retires: nothing
-- Nothing is dropped, deleted or switched on. The new job is created paused. No Firecrawl or AI spend is added. Consumer API untouched (G3).

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 0. the definitions the new code calls are the ones it was written against (not changed here)
do $g$
declare r record;
begin
  for r in select * from (values ('security.course_link_search_cap_reason_v1()', '5b46ddd0283dce924a2f6cdeb90c6549'),
                                 ('public.svc_cricos_peo_next(integer)', '9b7675ad956065b6ba793b5e744114ad'),
                                 ('security.integration_issue_upsert_v1(jsonb,text)', 'f292f65689a35e213a3d12a539c11b1d')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
  -- called with the same arguments as the job did; its body is not relied on
  if to_regprocedure('security.country_scope_gate_v1(boolean,text)') is null then raise exception 'security.country_scope_gate_v1(boolean, text) is missing'; end if;
end $g$;

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'enrich.focus_countries', 'Course page search: countries limited to the focus providers',
  'In these countries only the focus providers (enrich.focus_top_n, ranked by missing English and intakes within each country) and providers in a re-find wave get course page search and discovery. Every other country is searched for every provider.',
  'list', '["AU"]'::jsonb, null, null, 'countries', 1040, 'Course page search', 'security.enrich_focus_v1, security.enrich_focus_refresh_v1 (course-link-search-worker, coverage-discover, coverage-ai-match-prepare)',
  'Platform Admin direction 3 Nov 2026 09:32 §7: country rules in settings, not in shared code (today''s value)'),
 ('pipeline', 'scholarship.refill_priority_countries', 'Scholarship discovery: countries queued first',
  'Providers of these countries are queued for scholarship discovery with the focus priority and the reason largest_unsearched; others with the other priority and the reason university_<country>.',
  'list', '["AU"]'::jsonb, null, null, 'countries', 1041, 'Scholarships', 'security.scholarship_discovery_refill_v1 (job scholarship-discover-refill)',
  'Platform Admin direction 3 Nov 2026 09:32 §7 (today''s value)'),
 ('pipeline', 'scholarship.refill_open_countries', 'Scholarship discovery: countries where every eligible provider is queued',
  'In these countries every eligible provider is queued for scholarship discovery; in other countries only providers the scholarship admission rule accepts.',
  'list', '["AU"]'::jsonb, null, null, 'countries', 1042, 'Scholarships', 'security.scholarship_discovery_refill_v1 (job scholarship-discover-refill)',
  'Platform Admin direction 3 Nov 2026 09:32 §7 (today''s value)'),
 ('pipeline', 'scholarship.refill_priority_focus', 'Scholarship discovery: priority of the countries queued first',
  'The priority given to providers of the countries in scholarship.refill_priority_countries when they are queued.',
  'number', to_jsonb(4), 1, 10, 'priority', 1043, 'Scholarships', 'security.scholarship_discovery_refill_v1 (job scholarship-discover-refill)',
  'Platform Admin direction 3 Nov 2026 09:32 §7 (today''s value)'),
 ('pipeline', 'scholarship.refill_priority_other', 'Scholarship discovery: priority of other countries',
  'The priority given to providers of every other country when they are queued.',
  'number', to_jsonb(1), 1, 10, 'priority', 1044, 'Scholarships', 'security.scholarship_discovery_refill_v1 (job scholarship-discover-refill)',
  'Platform Admin direction 3 Nov 2026 09:32 §7 (today''s value)'),
 ('pipeline', 'country_scope.gate_countries', 'Country course scope: countries checked',
  'Each hour the country course scope check hides and shows the active courses of these countries by their level scope (pipeline.country_scope_levels). A country without scope levels is reported and skipped.',
  'list', '["CA"]'::jsonb, null, null, 'countries', 1045, 'Enrichment', 'security.country_scope_gate_run_v1 (job country-scope-gate)',
  'Platform Admin direction 3 Nov 2026 09:32 §7: the job command carries no country (today''s value)'),
 ('pipeline', 'integration.watched_modes', 'Integration checks: worker modes watched closely',
  'Worker modes that run rarely or whose failure hides behind a succeeded schedule (a picker time-out). Their failed answers open a hidden-error issue at the lower count below, on the next check.',
  'list', '["provider_description", "enrich_ai"]'::jsonb, null, null, 'worker modes', 1046, 'Integration queue', 'security.integration_yield_checks_v1 (hidden worker errors)',
  'Platform Admin direction 3 Nov 2026 09:32 §5: hidden failures detected (IQ-00053, IQ-00055)'),
 ('pipeline', 'integration.watched_mode_min_failures', 'Integration checks: failed answers before an issue (watched modes)',
  'A watched worker mode needs this many failed answers in the hidden-error window to open an issue (any share of its calls).',
  'number', to_jsonb(1), 1, 100, 'calls', 1047, 'Integration queue', 'security.integration_yield_checks_v1 (hidden worker errors)',
  'Platform Admin direction 3 Nov 2026 09:32 §5'),
 ('pipeline', 'ranking.edition_calendar', 'Ranking editions: publishers'' release calendar',
  'One entry per ranking system: code:month:offset. The edition named year + offset is published in that month of the year (QS in June for next year, THE in October for next year, ARWU in August for the same year).',
  'list', '["qs_wur:6:1", "the_wur:10:1", "arwu:8:0"]'::jsonb, null, null, 'entries', 1048, 'Register', 'security.ranking_edition_check_v1 (job ranking-edition-check)',
  'Platform Admin direction 3 Nov 2026 09:32 §5 (ranking refresh): a new edition raises a task'),
 ('pipeline', 'ranking.edition_grace_days', 'Ranking editions: days after the release month before an edition is expected',
  'An edition counts as published this many days after the first day of its release month.',
  'number', to_jsonb(30), 0, 120, 'days', 1049, 'Register', 'security.ranking_edition_check_v1 (job ranking-edition-check)',
  'Platform Admin direction 3 Nov 2026 09:32 §5 (ranking refresh)'),
 ('pipeline', 'ranking.import_max_age_days', 'Ranking editions: last import older than',
  'A ranking system whose last file import is older than this (or that was never imported) gets an integration issue asking for a new import.',
  'number', to_jsonb(400), 30, 1000, 'days', 1050, 'Register', 'security.ranking_edition_check_v1 (job ranking-edition-check)',
  'Platform Admin direction 3 Nov 2026 09:32 §5 (ranking refresh)')
on conflict do nothing;

-- 2. a list setting reader (pipeline toolset; a missing or non-list value gives the default) ---------------------------------------------------
create or replace function security.pipeline_list_v1(p_key text, p_default jsonb default '[]'::jsonb) returns text[]
language sql stable security definer set search_path to '' as $function$
  select array(select jsonb_array_elements_text(coalesce(
           (select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key and jsonb_typeof(s.value) = 'array'),
           case when jsonb_typeof(p_default) = 'array' then p_default else '[]'::jsonb end)))
$function$;
revoke all on function security.pipeline_list_v1(text, jsonb) from public, anon, authenticated;
comment on function security.pipeline_list_v1(text, jsonb) is 'CF-247 (direction 3 Nov 2026 09:32 §7): a list setting of toolset pipeline as text[] (country lists and other lists read by shared orchestration)';

-- 3. (a) the admin-jobs runner and its slices lock the task row without blocking foreign-key checks ------------------------------------------
select pg_temp.edit_once('security.admin_jobs_tick_v1(integer)', '6a482636d1f67ca41add017f8c241b01', 'e760363a6af21d850f7e6e1c86bca0cb', array[
  array[$e$limit v_n for update skip locked loop$e$,
        $e$limit v_n for no key update skip locked loop  -- CF-247 IQ-00053: the row is held for the whole run; NO KEY UPDATE does not block the workers' foreign-key checks$e$]], array[1]);
select pg_temp.edit_once('security.admin_job_slice_v1(uuid,integer)', '6d9ba8d97a068061566d2790eec103fc', '88f82c974b0ecde708a0550413791d86', array[
  array[$e$select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;$e$,
        $e$select * into v_j from pipeline.admin_jobs j where j.id = p_id for no key update;  -- CF-247 IQ-00053: never blocks the workers' foreign-key checks$e$]], array[1]);
select pg_temp.edit_once('security.admin_job_watch_v1(uuid)', '042c960f0f7d6fdb4d83a725e644a4a8', 'ad21305f89ee441bde462cc35e5a8a98', array[
  array[$e$select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;$e$,
        $e$select * into v_j from pipeline.admin_jobs j where j.id = p_id for no key update;  -- CF-247 IQ-00053: never blocks the workers' foreign-key checks$e$]], array[1]);
select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', 'b677308fffdc23e5fbd2ad54d1b97d30', '4babdac64e58459fe38d79def27842ea', array[
  array[$e$select * into j from pipeline.admin_jobs where id = p_id for update;$e$,
        $e$select * into j from pipeline.admin_jobs where id = p_id for no key update;  -- CF-247 IQ-00053: the enrich_ai record checks its task row (FOR KEY SHARE) while this runs$e$]], array[1]);

-- 4. (b) the NZ Code of Practice picker reads the latest batch time per source once -------------------------------------------------------------
select pg_temp.edit_once('public.svc_nz_cop_next(integer)', '255c75c911ce848c7787a64194fa0722', 'e745750b29d7436a022d2227eb8fc52b', array[
  array[$e$              from pipeline.evidence_artifacts e join pipeline.sources s on s.id = e.source_id
$e$,
        $e$              from pipeline.evidence_artifacts e join pipeline.sources s on s.id = e.source_id
              -- CF-247 hidden failures (3 Nov 2026): the latest batch time per source, once (it was a correlated max() per file: 12.3 s, over the 8 s limit)
              join (select e2.source_id, max(e2.captured_at) latest from pipeline.evidence_artifacts e2 join pipeline.sources s2 on s2.id = e2.source_id
                     where s2.url like 'https://www.nzqa.govt.nz/providers/%' and e2.storage_path like 'regulatory/NZ/nzqa/%-offset-%' group by e2.source_id) m on m.source_id = e.source_id
$e$],
  array[$e$               and e.captured_at > (select max(e2.captured_at) from pipeline.evidence_artifacts e2 where e2.source_id = e.source_id and e2.storage_path like 'regulatory/NZ/nzqa/%-offset-%')$e$,
        $e$               and e.captured_at > m.latest$e$]], array[1, 1]);

-- 5. (c) cricos-peo calls the worker only when a provider is due --------------------------------------------------------------------------------
create or replace function security.cricos_peo_fire_v1() returns integer
language plpgsql security definer set search_path to '' as $function$
-- CF-247 hidden failures (direction 3 Nov 2026 09:32 §5): the eligibility of public.svc_cricos_peo_next (not edited), without leasing. The job
-- called the worker every minute with nothing due (1,008 idle calls a day); the worker is now called only when a provider is due.
begin
  if not exists (select 1 from catalogue.providers p
                  where p.lifecycle_status = 'active'
                    and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
                    and exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and lower(r.registration_scheme) = 'cricos' and r.registration_code ~* '^[0-9]{5}[A-Z]$')
                    and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
                    and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'regulatory_peo'
                                      and (k.checked_at > now() - make_interval(days => security.pipeline_num_v1('recheck.cricos_contact_days', 180)::int) and k.outcome <> 'budget'
                                           or k.checked_at > now() - interval '1 hour'))) then  -- fixed: a check in flight (as the picker)
    return 0;
  end if;
  perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'cricos_peo', 'limit', security.pipeline_num_v1('batch.cricos_peo', 2)::int));
  return 1;
end $function$;
revoke all on function security.cricos_peo_fire_v1() from public, anon, authenticated;

-- 6. (d) country rules from settings ---------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.enrich_focus_v1(uuid)', '803098094b9d8404ad1b9531c7e597bd', '1fe6696838ac6bbf5dec7684a536b492', array[
  array[$e$      or coalesce(security.coverage_country(p_provider_id), '') <> 'AU'$e$,
        $e$      -- CF-247 3 Nov 2026 (direction 09:32 §7): the countries limited to their focus providers are a setting
      or coalesce(security.coverage_country(p_provider_id), '') <> all (security.pipeline_list_v1('enrich.focus_countries', '["AU"]'))$e$]], array[1]);
select pg_temp.edit_once('security.enrich_focus_refresh_v1()', '0588c931c545df5ef8a1b58730c9d3b5', '80e467c21f37828c4490314a216d28c7', array[
  array[$e$row_number() over (order by count(*)$e$, $e$row_number() over (partition by d.country_code order by count(*)$e$],
  array[$e$where d.country_code = 'AU' and not exists$e$,
        $e$where d.country_code = any (security.pipeline_list_v1('enrich.focus_countries', '["AU"]')) and not exists$e$],
  array[$e$group by d.provider_id) g$e$, $e$group by d.provider_id, d.country_code) g  -- CF-247 3 Nov 2026: focus countries from the setting, ranked within each country$e$]], array[1, 1, 1]);
select pg_temp.edit_once('security.scholarship_discovery_refill_v1(integer)', '5a72808f07e2f5219518ed3fc20fcdb7', 'aa26bbc2b99e3390a4730abc2fa14992', array[
  array[$e$declare v_pending int;$e$,
        $e$declare v_pri text[] := security.pipeline_list_v1('scholarship.refill_priority_countries', '["AU"]'); v_open text[] := security.pipeline_list_v1('scholarship.refill_open_countries', '["AU"]');
        v_pending int;$e$],
  array[$e$case when q.cc = 'AU' then 4 else 1 end, case when q.cc = 'AU' then 'largest_unsearched' else 'university_' || lower(q.cc) end, 'pending'$e$,
        $e$case when q.cc = any (v_pri) then security.pipeline_num_v1('scholarship.refill_priority_focus', 4)::int else security.pipeline_num_v1('scholarship.refill_priority_other', 1)::int end,
           case when q.cc = any (v_pri) then 'largest_unsearched' else 'university_' || lower(q.cc) end, 'pending'  -- CF-247 3 Nov 2026 (direction 09:32 §7): countries and priorities are settings$e$],
  array[$e$and (k.iso_alpha2 = 'AU' or security.scholarship_admission_provider_ok_v1(p.id))$e$,
        $e$and (k.iso_alpha2 = any (v_open) or security.scholarship_admission_provider_ok_v1(p.id))$e$]], array[1, 1, 1]);

create or replace function security.country_scope_gate_run_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 3 Nov 2026 (direction 09:32 §7): the job country-scope-gate checks the countries in country_scope.gate_countries (its command carries
-- no country); security.country_scope_gate_v1 is unchanged and reports a country without scope levels.
declare v_out jsonb := '{}'::jsonb; v_cc text;
begin
  foreach v_cc in array security.pipeline_list_v1('country_scope.gate_countries', '["CA"]') loop
    v_out := v_out || jsonb_build_object(v_cc, security.country_scope_gate_v1(true, v_cc));
  end loop;
  return v_out;
end $function$;
revoke all on function security.country_scope_gate_run_v1() from public, anon, authenticated;

-- 7. (f) the yield checks: watched modes, a picker held by its own daily cap is idle; the Enrich fields lane -------------------------------------
create or replace function security.worker_mode_capped_v1(p_mode text) returns text
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 IQ-00048 follow-up: why a lane's picker is held by its own governed daily cap (capacity, not a failure), or null. One line per lane
-- that has such a cap; the cap's own reader decides.
begin
  return case p_mode when 'link_search' then security.course_link_search_cap_reason_v1() else null end;
end $function$;
revoke all on function security.worker_mode_capped_v1(text) from public, anon, authenticated;

select pg_temp.edit_once('security.integration_yield_checks_v1()', '4c25bf79db544f8605c9c25b45fc8318', '2bcba102aa776a21c888bae711fd3374', array[
  array[$e$        v_back interval := make_interval(hours => security.pipeline_num_v1('integration.first_run_lookback_hours', 24)::int);$e$,
        $e$        v_back interval := make_interval(hours => security.pipeline_num_v1('integration.first_run_lookback_hours', 24)::int);
        v_watch text[] := security.pipeline_list_v1('integration.watched_modes', '["provider_description", "enrich_ai"]');
        v_wmin int := security.pipeline_num_v1('integration.watched_mode_min_failures', 1)::int; v_cap text; v_capped jsonb := '{}'::jsonb;$e$],
  array[$e$      if r.failures >= v_minf and r.failures * 100 >= v_share * r.calls then$e$,
        $e$      -- CF-247 3 Nov 2026 (direction 09:32 §5; IQ-00053, IQ-00055): a watched mode opens its issue on its first failed answers in the window
      if (r.failures >= v_minf and r.failures * 100 >= v_share * r.calls) or (r.failures >= v_wmin and split_part(r.key, ':', 2) = any (v_watch)) then$e$],
  array[$e$        if r.failures > 0 or r.items > 0 or v_wait then$e$,
        $e$        -- CF-247 IQ-00048 follow-up: no failure in the window and the picker held by its own daily cap is idle, not zero yield
        v_cap := case when r.failures = 0 then security.worker_mode_capped_v1(r.key) end;
        if v_cap is not null then v_capped := v_capped || jsonb_build_object(r.key, v_cap); end if;
        if v_cap is null and (r.failures > 0 or r.items > 0 or v_wait) then$e$],
  array[$e$    v_ok := v_ok || 'zero_yield'::text; v_out := v_out || jsonb_build_object('zero_yield', v_n);$e$,
        $e$    v_ok := v_ok || 'zero_yield'::text; v_out := v_out || jsonb_build_object('zero_yield', v_n, 'idle_by_cap', v_capped);$e$]], array[1, 1, 1, 1]);

select pg_temp.edit_once('security.pipeline_yield_v1(integer)', '87ab2f7e7a6acf18a18c7191c9eb2b98', '2061ab3dd67f20b28f9e6327dc9ad0b0', array[
  array[$e$declare v_h int := coalesce(p_hours, security.pipeline_num_v1('integration.yield_window_hours', 24)::int); v_since timestamptz; v jsonb;$e$,
        $e$declare v_h int := coalesce(p_hours, security.pipeline_num_v1('integration.yield_window_hours', 24)::int); v_since timestamptz; v jsonb; ef record;$e$],
  array[$e$  v_since := now() - make_interval(hours => v_h);
$e$,
        $e$  v_since := now() - make_interval(hours => v_h);
  -- CF-247 3 Nov 2026 (direction 09:32 §5): the Enrich fields lane, the items of the tasks that ran in the window
  select count(*) items, count(*) filter (where i.evidence_id is not null or i.storage_path is not null) stored, count(*) filter (where i.state in ('filled', 'review', 'skipped')) settled,
         count(*) filter (where i.value is not null) valued, count(*) filter (where i.state = 'filled') filled, count(*) filter (where i.state = 'review') review,
         count(*) filter (where i.state = 'skipped') skipped, count(*) filter (where i.state = 'failed') failed
    into ef from pipeline.field_enrich_items i
   where i.job_id in (select j.id from pipeline.admin_jobs j where j.kind = 'enrich_fields' and coalesce(j.finished_at, j.updated_at) >= v_since);
$e$],
  array[$e$where r.published_at >= v_since and nullif(btrim(p.description), '') is not null and p.publication_status = 'published' and p.lifecycle_status = 'active')))));$e$,
        $e$where r.published_at >= v_since and nullif(btrim(p.description), '') is not null and p.publication_status = 'published' and p.lifecycle_status = 'active'))),
    -- Enrich fields (worker mode enrich_ai; the standing gap queue and operator tasks). Consumer read-back is not traced per item.
    jsonb_build_object('lane', 'enrich_fields', 'label', 'Enrich fields (AI reads)', 'stages', jsonb_build_object(
      'invoked', (select jsonb_build_object('calls', count(*), 'failed_calls', count(*) filter (where l.status >= 400 or l.failed > 0)) from pipeline.mode_outcome_ledger l
                   where l.run_at >= v_since and l.mode = 'enrich_ai'),
      'source_accessed', ef.stored,
      'pages_discovered', null,
      'read_completely', ef.settled,
      'extracted', ef.valued,
      'accepted_or_held', jsonb_build_object('accepted', ef.filled, 'held', ef.review, 'not_stated', ef.skipped, 'failed', ef.failed),
      'published', ef.filled,
      'consumer_read_back', null))));$e$]], array[1, 1, 1]);

-- 8. (e) ranking edition check: one integration issue per ranking system; it imports nothing ----------------------------------------------------
create or replace function security.ranking_edition_check_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 3 Nov 2026 (direction 09:32 §5, ranking refresh): each active ranking system (ranking.systems) is compared with its publisher's
-- release calendar (ranking.edition_calendar) and its last file import. A newer edition not held, or an import older than
-- ranking.import_max_age_days (or none), opens or updates one integration issue (fingerprint ranking_edition:<code>) for a person to import the
-- licensed file in Rankings & statistics › Datasets. Nothing is fetched or imported. A system no longer behind marks its issue cleared.
declare v_grace int := security.pipeline_num_v1('ranking.edition_grace_days', 30)::int;
        v_age int := security.pipeline_num_v1('ranking.import_max_age_days', 400)::int;
        v_cal text[] := security.pipeline_list_v1('ranking.edition_calendar', '["qs_wur:6:1", "the_wur:10:1", "arwu:8:0"]');
        r record; i record; v_month int; v_off int; v_y int; v_expect int; v_held int; v_last timestamptz; v_why text[]; v_fp text;
        v_seen text[] := '{}'; v_out jsonb := '[]'::jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('ranking-edition-check')) then return jsonb_build_object('skipped', 'running'); end if;  -- fixed: lock key
  for r in select s.id, s.code, s.publisher_name, s.ranking_name, s.official_url from ranking.systems s where s.active order by s.code loop
    v_month := null; v_off := null; v_expect := null;
    select nullif(split_part(c, ':', 2), '')::int, coalesce(nullif(split_part(c, ':', 3), '')::int, 0) into v_month, v_off
      from unnest(v_cal) c where split_part(c, ':', 1) = r.code and split_part(c, ':', 2) ~ '^[0-9]{1,2}$' and split_part(c, ':', 3) ~ '^-?[0-9]*$' limit 1;
    if v_month between 1 and 12 then
      v_y := extract(year from now() at time zone 'UTC')::int;  -- fixed: the calendar year is counted in UTC
      v_expect := case when now() >= make_timestamptz(v_y, v_month, 1, 0, 0, 0, 'UTC') + make_interval(days => v_grace) then v_y else v_y - 1 end + v_off;
    end if;
    select max(e.edition_year) into v_held from ranking.editions e where e.system_id = r.id and e.status = 'accepted';
    select max(m.uploaded_at) into v_last from ranking.manual_imports m where m.system_id = r.id;
    v_why := '{}';
    if v_expect is not null and (v_held is null or v_held < v_expect) then
      v_why := v_why || ('edition ' || v_expect || ' is out by the publisher''s calendar; ' || coalesce('latest held ' || v_held, 'no edition held'));
    end if;
    if v_last is null or v_last < now() - make_interval(days => v_age) then
      v_why := v_why || ('last file import ' || coalesce(to_char(v_last, 'YYYY-MM-DD'), 'never') || ' (older than ' || v_age || ' days)');
    end if;
    if cardinality(v_why) > 0 then
      v_fp := 'ranking_edition:' || r.code;
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', v_fp,
        'title', r.ranking_name || ': a new edition to import', 'layer', 'Layer 1', 'subsystem', 'ranking.' || r.code,
        'failure', array_to_string(v_why, '; '),
        'expected', 'The latest edition published by ' || r.publisher_name || ' is imported from its licensed file (Rankings & statistics › Datasets). The platform does not fetch or import rankings.',
        'source', 'ranking-edition-check', 'validation_layer', 'V4',
        'evidence', jsonb_build_object('system', r.code, 'expected_edition', v_expect, 'held_edition', v_held, 'last_import', v_last, 'official_url', r.official_url),
        'severity', 'P2', 'root_cause_class', 'missing_dependency', 'workstream', 'A10'), 'ranking-edition-check');
      v_seen := v_seen || v_fp;
    end if;
    v_out := v_out || jsonb_build_object('system', r.code, 'expected', v_expect, 'held', v_held, 'last_import', v_last, 'issue', cardinality(v_why) > 0);
  end loop;
  for i in select x.id, x.fingerprint, x.condition_cleared_at, x.status from pipeline.integration_issues x
            where x.status <> 'closed' and x.fingerprint like 'ranking\_edition:%' and not (x.fingerprint = any (v_seen)) loop
    if i.condition_cleared_at is null then
      update pipeline.integration_issues set condition_cleared_at = now() where id = i.id;
      insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note)
      values (i.id, 'not_observed', i.status, i.status, 'ranking-edition-check', 'the edition is held and the import is recent; close after verification');
    end if;
  end loop;
  return jsonb_build_object('systems', v_out, 'issues', cardinality(v_seen));
end $function$;
revoke all on function security.ranking_edition_check_v1() from public, anon, authenticated;

-- 9. jobs (G1): catalogue first; the new job is created paused; the two changed commands carry no number and no country ---------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('ranking-edition-check', 'Layer 1 register', 61, 'Ranking editions: new edition or stale import',
  'Daily: compares each active ranking system with its publisher''s release calendar (ranking.edition_calendar, ranking.edition_grace_days) and its last file import (ranking.import_max_age_days); opens one integration issue per ranking system when a newer edition is out but not held, or the import is old. Imports nothing: a person imports the licensed file in Rankings & statistics › Datasets. Created paused.',
  5, false, null)
on conflict do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'ranking-edition-check') then
    perform cron.schedule('ranking-edition-check', '14 4 * * *', 'select security.ranking_edition_check_v1()');
    perform cron.alter_job((select jobid from cron.job where jobname = 'ranking-edition-check'), active := false);
  end if;
  perform cron.alter_job((select jobid from cron.job where jobname = 'cricos-peo'), command := $j$select security.cricos_peo_fire_v1()$j$);
  perform cron.alter_job((select jobid from cron.job where jobname = 'country-scope-gate'), command := $j$select security.country_scope_gate_run_v1()$j$);
end $c$;
update pipeline.automation_catalogue set description = 'Reads the Principal Executive Officer from the CRICOS website (Firecrawl). Held for internal use; never published. Calls the worker only when a provider is due (recheck.cricos_contact_days).'
 where jobname = 'cricos-peo' and description not like '%only when a provider is due%';
update pipeline.automation_catalogue set description = 'Hourly: for each country in country_scope.gate_countries (today Canada), hides active courses whose level is missing or out of scope once their page was read for a credential, and shows inactive ones whose level is in scope at a provider with a page read recently. Every change logged in pipeline.course_scope_changes. Run size batch.country_scope_gate.'
 where jobname = 'country-scope-gate' and description not like '%country_scope.gate_countries%';

-- 10. component register ---------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'ranking-edition-check', 'Layer 1', 'Layer 1 register', 'Ranking editions: new edition or stale import raises an integration issue (paused until activated)', 'active', '{}', '20261103140000'),
 ('function', 'security.ranking_edition_check_v1', 'Layer 1', 'Layer 1 register', 'Job ranking-edition-check', 'active', '{}', '20261103140000'),
 ('function', 'security.pipeline_list_v1', 'Platform', 'Platform upkeep', 'List setting reader (country lists in shared orchestration)', 'active', '{}', '20261103140000'),
 ('function', 'security.cricos_peo_fire_v1', 'Layer 2', 'Course pages', 'Job cricos-peo: the worker only when a provider is due', 'active', '{}', '20261103140000'),
 ('function', 'security.country_scope_gate_run_v1', 'Layer 2', 'Enrichment', 'Job country-scope-gate: the countries in country_scope.gate_countries', 'active', '{}', '20261103140000'),
 ('function', 'security.worker_mode_capped_v1', 'Platform', 'Platform upkeep', 'Yield checks: a picker held by its own daily cap is idle', 'active', '{}', '20261103140000')
on conflict do nothing;

-- 11. post-check -----------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from cron.job where jobname = 'ranking-edition-check' and active) then raise exception 'hidden failures post-check: ranking-edition-check must be paused'; end if;
  if exists (select 1 from cron.job where jobname in ('cricos-peo', 'country-scope-gate') and command ~ '''|\(\s*[0-9]|,\s*[0-9]') then
    raise exception 'hidden failures post-check: a changed job command still carries a literal'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('enrich.focus_countries', 'scholarship.refill_priority_countries',
        'scholarship.refill_open_countries', 'scholarship.refill_priority_focus', 'scholarship.refill_priority_other', 'country_scope.gate_countries', 'integration.watched_modes',
        'integration.watched_mode_min_failures', 'ranking.edition_calendar', 'ranking.edition_grace_days', 'ranking.import_max_age_days')) <> 11 then
    raise exception 'hidden failures post-check: a setting is missing'; end if;
end $$;
