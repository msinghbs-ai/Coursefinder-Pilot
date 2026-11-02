-- CF-247 Scholarships beyond universities: a pilot cohort and stop conditions (Platform Admin decision 3 Nov 2026 08:44, admin docs/platform/
-- nz-enrichment-brief/2026-11-03-morning-decision-pack-0844.md §4: a controlled, PHASED extension of scholarship discovery and admission to eligible
-- registered providers where verified official scholarship evidence exists, and evidence-based legitimacy instead of the course minimum; "use
-- representative pilots before wider activation; stop expansion on wrong-provider admission, unsupported eligibility or material budget/operational
-- regressions"). Plan: admin docs/platform/nz-enrichment-brief/2026-11-03-scholarship-nonuni-pilot-plan.md.
-- Why (live, read-only, 3 Nov 2026 08:47-09:08 AEDT): the two proposals of v2.15.413 (P1 scholarship.non_university_admission, P2
--   scholarship.legitimacy_checks_on) are global switches. Switched on today, P1 opens admission to 999 Australian and 392 New Zealand governed
--   non-university providers at once, and P2 changes the search rule for every provider in every scholarship country (Canadian providers carry no
--   provider type, so all 1,130 would stop being searched; about 900 small Australian providers would start). There is no way to try them on a few.
-- What:
--   Pilot scope: the two proposals apply only to the providers listed in scholarship.pilot_provider_ids while scholarship.pilot_only is on (the
--      default). Empty list = nobody: with both proposals on and no providers listed, behaviour is exactly today's. Turning scholarship.pilot_only
--      off is the wider activation (both proposals for everyone), a separate deliberate step.
--      security.scholarship_admission_provider_ok_v1 (P1) and security.fc_sch_eligible_v1 (P2) check security.scholarship_pilot_scope_v1.
--   Pilot start: a listed provider is put first in the discovery order (security.fc_provider_tier_v1 tier 0) while a proposal is on, is queued if it
--      has no discovery row, and is due for one fresh discovery after the pilot list was last saved (the setting's updated_at); its pages already
--      read in the last reread.scholarship_candidate_days that were refused only because it is not a university are admitted again from their
--      stored facts (no new read, no AI, no Firecrawl), batch.scholarship_pilot_readmit an hour, by the hourly refill
--      (security.scholarship_discovery_refill_v1 -> security.scholarship_pilot_start_v1).
--   Award source: a non-university provider's page naming an award of another body (a government programme such as Australia Awards or
--      Manaaki, or a university's award listed by a college; the patterns are the setting scholarship.external_award_patterns) is refused as
--      "award of another body" (security.scholarship_admit_from_provider_page_v1, after the provider rule; universities are unchanged). Seen in
--      the stored refused pages of the proposed cohort (Kangan: Australia Awards; PCBT: a University of Adelaide scholarship; Unitec: Manaaki).
--   Stop conditions (read-only): security.scholarship_pilot_report_v1() per pilot provider and security.scholarship_pilot_stop_v1() in total, since
--      the pilot list was last saved: wrong-provider admission, unsupported eligibility, Firecrawl and AI spend against shares of the daily
--      scholarship budgets, and failed reads or stuck discovery. Every threshold is a setting. Nothing is switched off automatically: the report
--      says stop and why; the Platform Admin decides.
-- Firecrawl and AI: no limit is raised. Pilot providers spend inside the daily scholarship share, the per-provider cap and the AI ceiling as today.
-- Consumer API: untouched (G3). Nothing is published by this change: admitted records start unpublished, as today (Layer 4 governance unchanged).
-- Replaces: security.scholarship_admission_provider_ok_v1, security.fc_sch_eligible_v1, security.fc_provider_tier_v1, security.scholarship_discovery_refill_v1, security.scholarship_admit_from_provider_page_v1 (same names; md5-guarded)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on: the pilot list ships empty, scholarship.pilot_only on, and both proposals stay off.

create or replace function pg_temp.replace_once(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
begin
  if md5(pg_get_functiondef(p_sig::regprocedure)) = p_after then return p_sig || ': already applied'; end if;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_before then
    raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)); end if;
  execute p_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the replacement has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after; end if;
  return p_sig || ': applied';
end $f$;

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

-- 0. the definitions the new code reads are the ones it was written against (not changed here; live md5s read 3 Nov 2026 08:47 AEDT)
do $g$
declare r record;
begin
  for r in select * from (values ('security.scholarship_legitimacy_v1(uuid)', '90bdbf40913bdd120810bd6b7ff3e3bd'),
                                 ('security.scholarship_flag_v1(text,boolean)', '0beb3b60ecf485cffcd3e20bf1948df0'),
                                 ('security.scholarship_university(uuid)', '00ca2485d894ae4542b643a112c2b764')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'scholarship.pilot_provider_ids', 'Scholarships beyond universities: pilot providers',
  'Provider ids (catalogue) in the pilot. While "pilot providers only" is on, the two proposals above (non-university admission and the legitimacy checks) apply only to these providers. Empty: nobody. Saving this list starts the pilot measurement (the stop-condition report counts from the time it was last saved).',
  'list', '[]'::jsonb, null, null, null, 1027, 'Scholarships',
  'security.scholarship_pilot_scope_v1; security.scholarship_pilot_start_v1; security.fc_provider_tier_v1; security.scholarship_pilot_report_v1',
  'CF-247 scholarships beyond universities: pilot cohort (Platform Admin decision 3 Nov 2026 08:44 §4)'),
 ('pipeline', 'scholarship.external_award_patterns', 'Scholarships beyond universities: awards of another body',
  'Words that name an award of another body (a government programme, or a university''s award listed by a college). A non-university provider''s page whose scholarship name contains one of these is refused as "award of another body": the award belongs to its own awarding body, not to the college. Universities are not affected.',
  'list', '["australia awards", "manaaki", "destination australia", "new colombo", "fulbright", "endeavour", "chevening", "commonwealth scholarship", "university of "]'::jsonb,
  null, null, null, 1029, 'Scholarships', 'security.scholarship_external_award_v1; security.scholarship_admit_from_provider_page_v1',
  'CF-247 scholarships beyond universities: official award-source verification (decision 3 Nov 2026 08:44 §4)'),
 ('pipeline', 'scholarship.pilot_only', 'Scholarships beyond universities: pilot providers only',
  'On (normal until the pilot is signed off): non-university admission and the legitimacy checks apply only to the pilot providers; every other provider keeps today''s rules (universities only; the Firecrawl course minimum). Off: wider activation, both proposals apply to every provider.',
  'boolean', 'true'::jsonb, null, null, null, 1028, 'Scholarships', 'security.scholarship_pilot_scope_v1',
  'CF-247 scholarships beyond universities: phased activation (decision 3 Nov 2026 08:44 §4)'),
 ('pipeline', 'batch.scholarship_pilot_readmit', 'Scholarship pilot: stored pages admitted again an hour',
  'Pages of a pilot provider already read (within the candidate re-read time) and refused only because the provider was not a university, admitted again from their stored facts by the hourly refill. No new read, no AI, no Firecrawl.',
  'number', to_jsonb(50), 1, 500, 'pages', 1030, 'Job sizes', 'security.scholarship_pilot_start_v1 (job scholarship-discovery-refill)',
  'CF-247 scholarships beyond universities: pilot start'),
 ('pipeline', 'scholarship.pilot_stop_wrong_provider_max', 'Scholarship pilot stop: wrong-provider admissions at most',
  'Stop the expansion when more pilot admissions than this belong to another provider (page not on the provider''s own sites, a directory site, or a Layer 4 decision naming the provider).',
  'number', to_jsonb(0), 0, 20, 'records', 1031, 'Scholarships', 'security.scholarship_pilot_report_v1; security.scholarship_pilot_stop_v1',
  'CF-247 scholarships beyond universities: stop condition 1'),
 ('pipeline', 'scholarship.pilot_stop_unsupported_max', 'Scholarship pilot stop: admissions without eligibility evidence at most',
  'Stop the expansion when more pilot admissions than this lack eligibility evidence (the page did not say it is explicitly open to international students, currently offered, and a single scholarship page; or a Layer 4 decision on eligibility or audience).',
  'number', to_jsonb(0), 0, 20, 'records', 1032, 'Scholarships', 'security.scholarship_pilot_report_v1; security.scholarship_pilot_stop_v1',
  'CF-247 scholarships beyond universities: stop condition 2'),
 ('pipeline', 'scholarship.pilot_stop_fc_share_pct', 'Scholarship pilot stop: Firecrawl a day, share of the scholarship budget',
  'Stop the expansion when the pilot providers together use more than this share of the daily scholarship Firecrawl share (Firecrawl › Daily budget), averaged a day since the pilot started.',
  'number', to_jsonb(20), 1, 100, '%', 1033, 'Scholarships', 'security.scholarship_pilot_stop_v1', 'CF-247 scholarships beyond universities: stop condition 3 (budget)'),
 ('pipeline', 'scholarship.pilot_stop_ai_share_pct', 'Scholarship pilot stop: AI a day, share of the scholarship AI ceiling',
  'Stop the expansion when the AI reads of the pilot providers'' pages cost more than this share of the daily scholarship AI ceiling (OpenRouter guard), averaged a day since the pilot started.',
  'number', to_jsonb(20), 1, 100, '%', 1034, 'Scholarships', 'security.scholarship_pilot_stop_v1', 'CF-247 scholarships beyond universities: stop condition 3 (budget)'),
 ('pipeline', 'scholarship.pilot_stop_failed_pct', 'Scholarship pilot stop: failed page reads at most',
  'Stop the expansion when more than this share of a pilot provider''s page reads since the pilot started failed (once it has at least the reads below), or its discovery is stuck (failed, or out of attempts).',
  'number', to_jsonb(50), 1, 100, '%', 1035, 'Scholarships', 'security.scholarship_pilot_report_v1; security.scholarship_pilot_stop_v1', 'CF-247 scholarships beyond universities: stop condition 4 (operational)'),
 ('pipeline', 'scholarship.pilot_stop_min_reads', 'Scholarship pilot stop: reads before the failure share counts',
  'The failed-read share is judged only once a pilot provider has at least this many page reads since the pilot started.',
  'number', to_jsonb(10), 1, 1000, 'pages', 1036, 'Scholarships', 'security.scholarship_pilot_report_v1', 'CF-247 scholarships beyond universities: stop condition 4 (operational)')
on conflict (toolset_key, key) do nothing;

-- 2. new functions -------------------------------------------------------------------------------------------------------------------------
-- a listed pilot provider (the setting; empty = nobody)
create or replace function security.scholarship_pilot_member_v1(p_provider_id uuid) returns boolean language sql stable security definer set search_path to '' as
$function$
  select p_provider_id is not null and exists (
    select 1 from pipeline.platform_toolset_settings s, jsonb_array_elements_text(case when jsonb_typeof(s.value) = 'array' then s.value else '[]'::jsonb end) x(id)
     where s.toolset_key = 'pipeline' and s.key = 'scholarship.pilot_provider_ids' and lower(btrim(x.id)) = p_provider_id::text)
$function$;

-- an award of another body named on a non-university provider's page (the setting's patterns)
create or replace function security.scholarship_external_award_v1(p_name text) returns boolean language sql stable security definer set search_path to '' as
$function$
  select exists (select 1 from pipeline.platform_toolset_settings s, jsonb_array_elements_text(case when jsonb_typeof(s.value) = 'array' then s.value else '[]'::jsonb end) x(w)
                  where s.toolset_key = 'pipeline' and s.key = 'scholarship.external_award_patterns' and nullif(btrim(x.w), '') is not null
                    and strpos(lower(coalesce(p_name, '')), lower(x.w)) > 0)
$function$;

-- where the two proposals apply: the pilot providers while scholarship.pilot_only is on (default); everyone once it is off (wider activation)
create or replace function security.scholarship_pilot_scope_v1(p_provider_id uuid) returns boolean language sql stable security definer set search_path to '' as
$function$
  select not security.scholarship_flag_v1('scholarship.pilot_only', true) or security.scholarship_pilot_member_v1(p_provider_id)
$function$;

-- when the pilot list was last saved: the pilot measurement starts here
create or replace function security.scholarship_pilot_since_v1() returns timestamptz language sql stable security definer set search_path to '' as
$function$
  select s.updated_at from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'scholarship.pilot_provider_ids'
$function$;

-- pilot start, from the hourly refill: queue listed providers, one fresh discovery after the list was saved, stored refused pages admitted again
create or replace function security.scholarship_pilot_start_v1() returns jsonb language plpgsql security definer set search_path to '' as
$function$
declare v_since timestamptz := security.scholarship_pilot_since_v1(); v_q int := 0; v_due int := 0; v_re int := 0; v_adm int := 0; c record; r jsonb;
begin
  if not (security.scholarship_flag_v1('scholarship.non_university_admission', false) or security.scholarship_flag_v1('scholarship.legitimacy_checks_on', false))
     or not exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'scholarship.pilot_provider_ids'
                     and jsonb_typeof(s.value) = 'array' and jsonb_array_length(s.value) > 0) then
    return jsonb_build_object('pilot', false);
  end if;
  -- a listed provider without a discovery row is queued (same gates as the refill: eligible, own website, search on, published)
  insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
  select p.id, btrim(p.website), 0, 'scholarship_pilot', 'pending'
    from catalogue.providers p join ref.countries k on k.id = p.country_id
   where security.scholarship_pilot_member_v1(p.id) and p.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
     and nullif(btrim(coalesce(p.website, '')), '') is not null and not security.third_party_host_v1(p.website)
     and security.fc_sch_eligible_v1(p.id) and not security.provider_sch_search_off_v1(p.id)
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
     and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p.id)
  on conflict do nothing;
  get diagnostics v_q = row_count;
  -- one fresh discovery after the list was saved: first in the order, due now (a held or not-yet-due row of a listed provider)
  update pipeline.scholarship_discovery_providers d set tier = security.fc_provider_tier_v1(d.provider_id), next_discover_at = now(), updated_at = now()
   where security.scholarship_pilot_member_v1(d.provider_id) and d.status in ('pending', 'deferred', 'mapped', 'empty')
     and coalesce(d.discovered_at, '-infinity') < v_since and coalesce(d.next_discover_at, '-infinity') > now();
  get diagnostics v_due = row_count;
  -- pages already read and refused only because the provider was not a university: admitted again from their stored facts
  for c in select x.id from pipeline.scholarship_page_candidates x
            where security.scholarship_pilot_member_v1(x.provider_id) and x.admit_status = 'rejected'
              and x.admit_reasons = array['not a university provider in a scholarship country'] and x.read_status = 'read'
              and x.admitted_scholarship_id is null and x.matched_scholarship_id is null
              and x.read_at > now() - make_interval(days => security.pipeline_num_v1('reread.scholarship_candidate_days', 90)::int)
              and security.scholarship_admission_provider_ok_v1(x.provider_id)
            order by x.provider_id, x.id limit greatest(0, security.pipeline_num_v1('batch.scholarship_pilot_readmit', 50)::int) loop
    r := security.scholarship_admit_from_provider_page_v1(c.id);
    v_re := v_re + 1;
    if (r->>'admitted')::boolean then v_adm := v_adm + 1; end if;
  end loop;
  return jsonb_build_object('pilot', true, 'since', v_since, 'queued', v_q, 'due', v_due, 'readmitted', v_re, 'admitted', v_adm);
end $function$;

-- the stop conditions per provider, since the pilot list was last saved (read-only)
create or replace function security.scholarship_pilot_report_v1()
returns table(provider_id uuid, provider_name text, provider_type text, country text, listed boolean, in_scope boolean, admission_ok boolean, search_ok boolean,
              legitimacy_ok boolean, active_courses int, discovery_status text, discovery_attempts int, candidates int, pages_read int, pages_failed int,
              admitted int, refused_not_university int, wrong_provider int, unsupported_eligibility int, firecrawl_credits numeric, ai_usd numeric,
              stop boolean, stop_reasons text[])
language sql stable security definer set search_path to '' as
$function$
  with cfg as (
    select coalesce(security.scholarship_pilot_since_v1(), now()) since,
           security.pipeline_num_v1('scholarship.pilot_stop_wrong_provider_max', 0) wrong_max,
           security.pipeline_num_v1('scholarship.pilot_stop_unsupported_max', 0) unsup_max,
           security.pipeline_num_v1('scholarship.pilot_stop_failed_pct', 50) failed_pct,
           security.pipeline_num_v1('scholarship.pilot_stop_min_reads', 10) min_reads),
  who as (  -- the listed providers; after wider activation also every non-university provider with an admission since the pilot started
    select p.id from catalogue.providers p where security.scholarship_pilot_member_v1(p.id)
    union
    select l.provider_id from pipeline.scholarship_admission_log l, cfg
     where not security.scholarship_flag_v1('scholarship.pilot_only', true) and l.action = 'admitted' and l.at >= cfg.since
       and not security.scholarship_university(l.provider_id)),
  adm as (  -- records admitted since the pilot started, with their page facts and Layer 4 decisions
    select l.provider_id, s.id sid, s.source_url, s.provider_id rec_provider, s.audience, sp.facts,
           exists (select 1 from pipeline.layer4_block_decisions b where b.entity_type = 'scholarship' and b.entity_id = s.id
                    and b.reason_code ~* 'provider') or
           exists (select 1 from pipeline.layer4_publication_decisions b where b.entity_type = 'scholarship' and b.entity_id = s.id
                    and b.reason_code ~* 'provider') l4_provider,
           exists (select 1 from pipeline.layer4_block_decisions b where b.entity_type = 'scholarship' and b.entity_id = s.id
                    and b.reason_code ~* '(eligib|audience|international|nationalit)') or
           exists (select 1 from pipeline.layer4_publication_decisions b where b.entity_type = 'scholarship' and b.entity_id = s.id
                    and b.reason_code ~* '(eligib|audience|international|nationalit)') l4_eligibility
      from pipeline.scholarship_admission_log l join who w on w.id = l.provider_id cross join cfg
      join scholarship.scholarships s on s.id = l.scholarship_id
      left join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
     where l.action = 'admitted' and l.at >= cfg.since),
  rows as (
    select p.id, coalesce(p.display_name, p.canonical_name) pname, t.code tcode, k.iso_alpha2::text cc,
           security.scholarship_pilot_member_v1(p.id) listed, security.scholarship_pilot_scope_v1(p.id) in_scope,
           security.scholarship_admission_provider_ok_v1(p.id) adm_ok, security.fc_sch_eligible_v1(p.id) search_ok, security.scholarship_legitimacy_v1(p.id) legit,
           (select count(*) from catalogue.courses co where co.provider_id = p.id and co.lifecycle_status = 'active')::int courses,
           d.status dstatus, d.attempts dattempts,
           (select count(*) from pipeline.scholarship_page_candidates x where x.provider_id = p.id)::int cands,
           (select count(*) from pipeline.scholarship_page_candidates x where x.provider_id = p.id and x.read_at >= cfg.since and x.read_status = 'read')::int pread,
           (select count(*) from pipeline.scholarship_page_candidates x where x.provider_id = p.id and x.read_at >= cfg.since and x.read_status in ('failed', 'scrape_failed', 'blocked'))::int pfail,
           (select count(*) from adm a where a.provider_id = p.id)::int admitted,
           (select count(*) from pipeline.scholarship_page_candidates x where x.provider_id = p.id and x.admit_status = 'rejected'
               and 'not a university provider in a scholarship country' = any (x.admit_reasons))::int refused_nu,
           (select count(*) from adm a where a.provider_id = p.id
               and (a.rec_provider is distinct from a.provider_id or not security.url_on_provider_sites(a.source_url, a.provider_id)
                    or security.third_party_host_v1(coalesce(a.source_url, '')) or a.l4_provider))::int wrong,
           (select count(*) from adm a where a.provider_id = p.id
               and (a.audience is distinct from 'international' or a.facts is null or a.l4_eligibility
                    or coalesce((a.facts->'admission'->>'international_explicit')::boolean, false) is not true
                    or coalesce((a.facts->'admission'->>'offered')::boolean, false) is not true
                    or coalesce((a.facts->'admission'->>'detail_page')::boolean, false) is not true))::int unsup,
           (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = p.id and u.purpose like 'sch\_%' and u.at >= cfg.since) fc,
           (select coalesce(sum(e.cost_usd), 0) from pipeline.scholarship_ai_extractions e where e.provider_id = p.id and e.at >= cfg.since) ai,
           cfg.*
      from who w join catalogue.providers p on p.id = w.id cross join cfg
      join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id
      left join pipeline.scholarship_discovery_providers d on d.provider_id = p.id)
  select r.id, r.pname, r.tcode, r.cc, r.listed, r.in_scope, r.adm_ok, r.search_ok, r.legit, r.courses, r.dstatus, r.dattempts, r.cands, r.pread, r.pfail,
         r.admitted, r.refused_nu, r.wrong, r.unsup, r.fc, r.ai,
         cardinality(z.reasons) > 0, z.reasons
    from rows r cross join lateral (select array_remove(array[
           case when r.wrong > r.wrong_max then 'wrong-provider admission (' || r.wrong || ')' end,
           case when r.unsup > r.unsup_max then 'admission without eligibility evidence (' || r.unsup || ')' end,
           case when r.pread + r.pfail >= r.min_reads and r.pfail * 100.0 / (r.pread + r.pfail) > r.failed_pct
                then 'failed page reads (' || r.pfail || ' of ' || (r.pread + r.pfail) || ')' end,
           case when r.dstatus = 'failed' or coalesce(r.dattempts, 0) >= 3 then 'discovery stuck (' || coalesce(r.dstatus, '') || ')' end], null) reasons) z
   order by cardinality(z.reasons) > 0 desc, r.cc, r.pname
$function$;

-- the stop decision in total: any provider's stop reason, or the pilot's Firecrawl or AI spend a day over its share (read-only)
create or replace function security.scholarship_pilot_stop_v1() returns jsonb language sql stable security definer set search_path to '' as
$function$
  with r as (select * from security.scholarship_pilot_report_v1()),
  t as (select count(*) providers, coalesce(sum(r.admitted), 0) admitted, coalesce(sum(r.wrong_provider), 0) wrong, coalesce(sum(r.unsupported_eligibility), 0) unsup,
               coalesce(sum(r.firecrawl_credits), 0) fc, coalesce(sum(r.ai_usd), 0) ai,
               coalesce(array_agg(r.provider_name || ': ' || array_to_string(r.stop_reasons, '; ')) filter (where r.stop), '{}') provider_stops from r),
  d as (select greatest(extract(epoch from now() - coalesce(security.scholarship_pilot_since_v1(), now())) / 86400.0, 1.0) days,  -- fixed: seconds in a day
               security.fc_setting_num_v1('daily_share_scholarships', 3500) * security.pipeline_num_v1('scholarship.pilot_stop_fc_share_pct', 20) / 100.0 fc_limit,
               coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'openrouter' and s.key = 'guard_scholarship_ai'), 0)
                 * security.pipeline_num_v1('scholarship.pilot_stop_ai_share_pct', 20) / 100.0 ai_limit)
  select jsonb_build_object('since', security.scholarship_pilot_since_v1(), 'days', round(d.days, 2), 'providers', t.providers, 'admitted', t.admitted,
           'wrong_provider', t.wrong, 'unsupported_eligibility', t.unsup,
           'firecrawl_per_day', round(t.fc / d.days, 1), 'firecrawl_limit_per_day', round(d.fc_limit, 1),
           'ai_usd_per_day', round(t.ai / d.days, 2), 'ai_limit_usd_per_day', round(d.ai_limit, 2),
           'stop', cardinality(t.provider_stops) > 0 or t.fc / d.days > d.fc_limit or t.ai / d.days > d.ai_limit,
           'reasons', to_jsonb(t.provider_stops
              || case when t.fc / d.days > d.fc_limit then array['Firecrawl ' || round(t.fc / d.days) || ' credits a day over the pilot share ' || round(d.fc_limit)] else '{}'::text[] end
              || case when t.ai / d.days > d.ai_limit then array['AI US$' || round(t.ai / d.days, 2) || ' a day over the pilot share US$' || round(d.ai_limit, 2)] else '{}'::text[] end))
    from t, d
$function$;

revoke all on function security.scholarship_pilot_start_v1() from public, anon, authenticated;
revoke all on function security.scholarship_pilot_report_v1() from public, anon, authenticated;
revoke all on function security.scholarship_pilot_stop_v1() from public, anon, authenticated;

-- 3. whole replacements (md5-guarded; before = live 3 Nov 2026 08:47 AEDT) -----------------------------------------------------------------
-- P1: the governed non-university rule applies in the pilot scope only
select pg_temp.replace_once('security.scholarship_admission_provider_ok_v1(uuid)', '804be95b3e78fb9efe3ea0d967cbe666', '269f74a985acbc37f1f3b8615efa6254', $def$
CREATE OR REPLACE FUNCTION security.scholarship_admission_provider_ok_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select security.scholarship_university(p_provider_id)
      or (security.scholarship_flag_v1('scholarship.non_university_admission', false)
          -- CF-247 scholarships beyond universities (decision 3 Nov 2026 08:44 §4): the pilot providers only while scholarship.pilot_only is on
          and security.scholarship_pilot_scope_v1(p_provider_id)
          and exists (select 1 from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id join ref.countries k on k.id = p.country_id
                       where p.id = p_provider_id and p.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
                         and t.status = 'active' and p.provider_type_basis is not null
                         and t.code in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.non_university_types'), '[]'::jsonb)))
                         and nullif(btrim(coalesce(p.website, '')), '') is not null and not security.third_party_host_v1(p.website)))
$function$
$def$);

-- P2: the legitimacy checks replace the course minimum in the pilot scope only; everyone else keeps today's rule
select pg_temp.replace_once('security.fc_sch_eligible_v1(uuid)', '8064816107a9b44bb2aeccbfa4a2d867', '2c44de24ea2d1bda123e1c8679591a9f', $def$
CREATE OR REPLACE FUNCTION security.fc_sch_eligible_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- CF-247 scholarship recovery P2 (proposed, off until the Platform Admin switches scholarship.legitimacy_checks_on): evidence-based legitimacy
  -- instead of the course minimum; CF-247 scholarships beyond universities (decision 3 Nov 2026 08:44 §4): the pilot providers only while
  -- scholarship.pilot_only is on
  if security.scholarship_flag_v1('scholarship.legitimacy_checks_on', false) and security.scholarship_pilot_scope_v1(p_provider_id) then
    return security.scholarship_legitimacy_v1(p_provider_id);
  end if;
  -- D16 (31 Oct 2026): PL/pgSQL so its query plans are kept for the session; same rule as the SQL version
  return security.coverage_country(p_provider_id) is distinct from 'AU' or security.fc_courses_v1(p_provider_id) >= security.fc_setting_num_v1('scholarship_min_courses', 30);
end $function$
$def$);

-- order: a listed pilot provider first while a proposal is on
select pg_temp.replace_once('security.fc_provider_tier_v1(uuid)', '3d0aa9dc690e23df4fd0c7248aaa7300', '2d71dcbd8aab00516c8222f68b6cc51b', $def$
CREATE OR REPLACE FUNCTION security.fc_provider_tier_v1(p_provider_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CF-247 scholarship recovery F10: the course threshold of the order is the setting scholarship_tier_courses (was the literal 30)
  -- CF-247 scholarships beyond universities: a listed pilot provider is first while either proposal is on
  select case when exists (select 1 from pipeline.onboarding_pilot o where o.provider_id = p_provider_id and o.cohort = 'au-top-2026-10-12') then 0
              when security.scholarship_pilot_member_v1(p_provider_id)
                   and (security.scholarship_flag_v1('scholarship.non_university_admission', false) or security.scholarship_flag_v1('scholarship.legitimacy_checks_on', false)) then 0
              when security.coverage_country(p_provider_id) is distinct from 'AU' then 2
              when security.fc_courses_v1(p_provider_id) >= security.fc_setting_num_v1('scholarship_tier_courses', 30) then 1 else 3 end
$function$
$def$);

-- the hourly refill also starts the pilot (nothing happens while the list is empty or both proposals are off)
select pg_temp.replace_once('security.scholarship_discovery_refill_v1(integer)', '46a66f131b574375db6e9edbc2ad3f36', '5a72808f07e2f5219518ed3fc20fcdb7', $def$
CREATE OR REPLACE FUNCTION security.scholarship_discovery_refill_v1(p_keep integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pending int; v_added int := 0; v_tier int; v_due int; v_skip int; v_round int; v_pilot jsonb;
begin
  perform security.provider_sch_search_auto_v1();  -- v2.15.271: directory-only providers switched Off
  select count(*) into v_pending from pipeline.scholarship_discovery_providers where status in ('pending', 'deferred');
  if v_pending < p_keep then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
    select q.provider_id, q.website, case when q.cc = 'AU' then 4 else 1 end, case when q.cc = 'AU' then 'largest_unsearched' else 'university_' || lower(q.cc) end, 'pending'
      from (select p.id provider_id, k.iso_alpha2 cc,
                   coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')) website,
                   count(*) n
              from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
             where co.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
               -- CF-247 scholarship recovery P1 (proposed, off): with non-university admission on, governed non-university providers overseas too
               and (k.iso_alpha2 = 'AU' or security.scholarship_admission_provider_ok_v1(p.id))
               and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p.id)
             group by p.id, p.website, k.iso_alpha2) q
     where q.website is not null
       -- v2.15.265: qualifying providers only, never a directory site; top-50, Australian 30+, overseas
       and security.fc_sch_eligible_v1(q.provider_id) and not security.third_party_host_v1(q.website)
       and not security.provider_sch_search_off_v1(q.provider_id)  -- v2.15.271
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
     order by security.fc_provider_tier_v1(q.provider_id), q.n desc, q.provider_id limit greatest(0, p_keep - v_pending)
    on conflict do nothing;
    get diagnostics v_added = row_count;
  end if;
  -- CF-247 scholarships beyond universities: the pilot providers are queued, due once after the list was saved, and their stored refused pages admitted again
  v_pilot := security.scholarship_pilot_start_v1();
  -- CF-247 scholarship recovery F1: the stored processing tier, a batch an hour
  v_tier := security.scholarship_discovery_tier_refresh_v1(security.pipeline_num_v1('batch.scholarship_tier_refresh', 500)::int);
  -- F3: providers mapped before the cadence existed are due the cadence after their last map
  update pipeline.scholarship_discovery_providers set next_discover_at = coalesce(discovered_at, now()) + make_interval(days => security.pipeline_num_v1('reread.scholarship_discovery_days', 30)::int)
   where status in ('mapped', 'empty') and next_discover_at is null;
  get diagnostics v_due = row_count;
  -- F1: the address skip rules on unread candidates; F9: round states
  v_skip := security.scholarship_candidate_skip_v1(null, security.pipeline_num_v1('batch.scholarship_candidate_skip', 5000)::int);
  v_round := security.scholarship_round_state_refresh_v1(security.pipeline_num_v1('batch.scholarship_round_state', 1000)::int);
  return jsonb_build_object('pending_before', v_pending, 'added', v_added, 'pilot', v_pilot, 'tiers', v_tier, 'cadence_set', v_due, 'skipped', v_skip, 'round_states', v_round);
end $function$
$def$);

-- 4. edit (md5-guarded): award source for non-university providers (universities unchanged; no effect while P1 admits no non-university)
select pg_temp.edit_once('security.scholarship_admit_from_provider_page_v1(bigint)', '5b3557c1ea4488f3e9b751ad9e7371e9', '0741db9c35ef91eba6caa55b04fde869', array[
  array[$e$then r:=jsonb_build_object('admitted',false,'reason','not a university provider in a scholarship country');$e$,
        $e$then r:=jsonb_build_object('admitted',false,'reason','not a university provider in a scholarship country');
  -- CF-247 scholarships beyond universities (decision 3 Nov 2026 08:44 §4, official award source): a college's page naming another body's award
  elsif not security.scholarship_university(c.provider_id) and security.scholarship_external_award_v1(v_name) then r:=jsonb_build_object('admitted',false,'reason','award of another body');$e$]
]::text[][], array[1]);

-- 5. register (housekeeping) ----------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.scholarship_external_award_v1', 'Layer 2', 'Scholarships', 'An award of another body named on a non-university provider''s page', 'active', '{}', '20261103090000'),
 ('function', 'security.scholarship_pilot_member_v1', 'Layer 2', 'Scholarships', 'A listed pilot provider (scholarships beyond universities)', 'active', '{}', '20261103090000'),
 ('function', 'security.scholarship_pilot_scope_v1', 'Layer 2', 'Scholarships', 'Where the non-university and legitimacy proposals apply (pilot or everyone)', 'active', '{}', '20261103090000'),
 ('function', 'security.scholarship_pilot_since_v1', 'Layer 2', 'Scholarships', 'When the pilot list was last saved', 'active', '{}', '20261103090000'),
 ('function', 'security.scholarship_pilot_start_v1', 'Layer 2', 'Scholarships', 'Pilot start from the hourly refill (queue, fresh discovery, stored pages admitted again)', 'active', '{}', '20261103090000'),
 ('function', 'security.scholarship_pilot_report_v1', 'Layer 2', 'Scholarships', 'Pilot stop conditions per provider (read-only)', 'active', '{}', '20261103090000'),
 ('function', 'security.scholarship_pilot_stop_v1', 'Layer 2', 'Scholarships', 'Pilot stop decision in total (read-only)', 'active', '{}', '20261103090000')
on conflict do nothing;

-- 6. post-check ------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if security.scholarship_flag_v1('scholarship.non_university_admission', true) or security.scholarship_flag_v1('scholarship.legitimacy_checks_on', true) then
    raise exception 'scholarship pilot post-check: the two proposals must stay off (switching them on is the integrator''s deliberate step)'; end if;
  if not security.scholarship_flag_v1('scholarship.pilot_only', false) then raise exception 'scholarship pilot post-check: pilot providers only must be on'; end if;
  if exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'scholarship.pilot_provider_ids' and s.value <> '[]'::jsonb) then
    raise exception 'scholarship pilot post-check: the pilot list must ship empty'; end if;
  if (select count(*) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and (s.key like 'scholarship.pilot%' or s.key = 'batch.scholarship_pilot_readmit')
        and s.label is not null and s.used_by is not null and (s.kind <> 'number' or (s.unit is not null and s.min_value is not null and s.max_value is not null))) < 9
     or not exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'scholarship.external_award_patterns' and s.used_by is not null) then
    raise exception 'scholarship pilot post-check: settings incomplete (G2)'; end if;
  if (security.scholarship_pilot_start_v1()->>'pilot')::boolean then raise exception 'scholarship pilot post-check: the pilot must not start on apply'; end if;
end $$;
select 'CF-247 scholarships beyond universities: pilot scope and stop conditions (list empty, proposals off)' ok;
