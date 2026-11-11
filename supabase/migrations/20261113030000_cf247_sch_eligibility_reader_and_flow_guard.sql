-- CF-247 F-SCH.01: scholarship eligibility reader, Layer 4 only after the reader is silent, pilot report measurement fix, and the scholarship flow guard
-- (Platform Admin 12 Nov 2026 09:25 AEDT: "Find the issue with Scholarships not admitting fast enough and missing providers and missing scholarship ... why
-- parking on layer 4, build readers where required. Make sure platform is autonomous to execute this in future, self sustaining").
-- Guards: G1 (two new jobs, catalogued), G2 (every size, time and switch a setting; job commands carry no number), G3 (no consumer API object read or changed),
--   Decision 260 (Replaces/Retires, table purposes, register rows), Layer 4 authority unchanged: no agent decides an item; the reader's answer is acted on only
--   by the existing admission rule security.scholarship_admit_from_provider_page_v1, and only once sch_elig.apply_on is switched on (shadow until then).
-- Evidence (production, read only, 12 Nov 2026 09:30-10:40 AEDT):
--   * 2,226 coverage cases are international_unresolved: pages the AI called a scholarship, refused only for international_not_stated. 1,870 of them carry no
--     eligibility text at all (facts.eligibility_excerpt "not stated"). Each became a Layer 4 intervention (lane sch_coverage, har_sch_generate_v1) with the
--     first AI read as its only automated attempt; har.open_max_per_lane (150) is reached (144 + 6 open), so the rest wait unread. The narrow re-check reader
--     (mode scholarship_recheck, v0.33.0) only reads items already in the human queue (pipeline.scholarship_ai_reviews), never these candidates.
--   * security.scholarship_pilot_report_v1 stops two pilot providers: 7 EIT records were admitted on 2 Nov from a page snapshot that a later re-read replaced
--     (now facts listing_page, withdrawn by the publication review), and 2 ICMS records whose audience is international_and_domestic, which the report counts
--     as unsupported because it compares with 'international' only.
--   * Nothing watches the flow itself: whole days with no scholarship found or admitted (31 Oct-1 Nov, 4-6 Nov 2026) while every job reported success; five
--     built recoveries stay switched off with work waiting (sch_cov.recover_listings_on 144 suggested listings, recover_register_pages_on 19,
--     recover_stored_reads_on, retry.scholarship_transient_recover_on 68 "page could not be read" reviews, har.ai_escalate_on); 180 providers sit in an
--     unresolved coverage state that no job can act on because scholarship_scope_v1 refuses them.
-- Live definitions this change edits (md5 of pg_get_functiondef, read 12 Nov 2026 10:20 AEDT):
--   security.har_sch_generate_v1(integer)        983b3939e4c8686fa6fcb03752f56370
--   security.scholarship_pilot_report_v1()        a9a207a4e7f9481ee202470f98cb4511
-- Read and relied on, unchanged: security.scholarship_admit_from_provider_page_v1(bigint) 0741db9c35ef91eba6caa55b04fde869, security.ai_use_refusal_v1(text)
--   60c782e5aec7eb218c1149a3ad85dde2, security.ai_spend_capture_v1() 5b78fa074a9480d4f127ecc4fe93dcf3.
-- What:
--   1. settings (sch_elig.*, sch_flow.*, batch.sch_eligibility_*, retry.sch_eligibility_hours): the reader and its action ship off (new spend path; turning
--      them on is a separate recorded step); the flow guard ships on (reads and reports only).
--   2. pipeline.scholarship_eligibility_reads: one read per refused candidate (queued, leased, done, failed), its answer, cost (into pipeline.ai_spend_ledger
--      lane scholarship_ai through security.ai_spend_capture_v1) and what was done with it (shadow or live). A page whose stored copy changes is read again.
--   3. public.svc_scholarship_eligibility_next / _record (worker v0.75.0 mode scholarship_eligibility); security.scholarship_eligibility_enqueue_v1,
--      _apply_v1 (the rule), _fire_v1 (job scholarship-eligibility, every 10 minutes).
--      The rule, live only with sch_elig.apply_on: a sentence proven on the page (or on a linked page on the provider's own site) that the scholarship is
--      for domestic students only -> the case is recorded domestic_only; for international students (or both), when the missing eligibility was the
--      page's only refusal -> the page facts record the sentence and the candidate goes back through scholarship_admit_from_provider_page_v1, which checks
--      every other admission rule again; silent -> the case stays unresolved and may now go to a person (or, only with sch_elig.silent_resolves, is
--      recorded as not proven for international students).
--   4. security.har_sch_generate_v1: while sch_elig.on, an international_unresolved case is raised for a person only once the reader has read it and found
--      no sentence (or failed); the other two classes are unchanged.
--   5. security.scholarship_pilot_report_v1: audience international_and_domestic / both counts as supported; a record withdrawn by a later check is not
--      counted as an unsupported admission (it is no longer live; the withdrawal is the platform's own correction).
--   6. pipeline.scholarship_flow_checks + security.scholarship_flow_guard_v1 (job scholarship-flow-guard, hourly): raises one integration issue per cause
--      (lane full, recovery switched off with work waiting, dead-end coverage state, admission stalled, cases unresolved past sch_flow.aged_days) with its
--      numbers and the setting that clears it, and marks the condition cleared when it clears.
-- Replaces: security.har_sch_generate_v1 and security.scholarship_pilot_report_v1 (same names and signatures; md5-guarded text edits).
-- Retires: nothing.

-- 0. what this change reads must exist, and the definitions it edits must be the ones read --------------------------------------------------------------
do $g$
declare v_sig text;
begin
  foreach v_sig in array array['security.scholarship_admit_from_provider_page_v1(bigint)', 'security.ai_use_refusal_v1(text)', 'security.ai_use_allowed_v1(text)',
                               'security.ai_spend_capture_v1()', 'security.scholarship_admission_provider_ok_v1(uuid)', 'security.url_on_provider_sites(text,uuid)',
                               'security.third_party_host_v1(text)', 'security.coverage_country(uuid)', 'security.scholarship_scope_v1(uuid)',
                               'security.integration_issue_upsert_v1(jsonb,text)', 'security.pipeline_num_v1(text,numeric)', 'security.lane_paid_hold_v1(text)',
                               'pipeline.svc_pilot_submit_nonce(text,jsonb)'] loop
    if to_regprocedure(v_sig) is null then raise exception 'this change reads %, which does not exist', v_sig; end if;
  end loop;
  if md5(pg_get_functiondef('security.scholarship_admit_from_provider_page_v1(bigint)'::regprocedure)) <> '0741db9c35ef91eba6caa55b04fde869' then
    raise exception 'the admission rule this change relies on has changed since it was read';
  end if;
end $g$;

-- 1. settings (G2) ------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'sch_elig.on', 'Scholarship eligibility reader: read who may apply',
  '1: every 10 minutes, scholarship pages refused only because no sentence said international students may apply (coverage state "international eligibility unresolved") are read again with the narrow re-check question (stored copy first, the pinned first model of the scholarship chain, about US$0.0003 a page) and, when the page is silent, one page it links to for its eligibility or conditions on the same site (one Firecrawl credit through the scholarship share). While on, such a case goes to a person in Layer 4 only after the reader found no sentence. 0: off (cases go to a person as before).',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1420, 'F-SCH.01 (12 Nov 2026): ships off (new spend path); turning it on is a separate recorded step', 'Scholarship eligibility reader',
  'security.scholarship_eligibility_fire_v1 (job scholarship-eligibility), public.svc_scholarship_eligibility_next, security.har_sch_generate_v1'),
 ('pipeline', 'sch_elig.apply_on', 'Scholarship eligibility reader: act on proven sentences',
  '1: a sentence proven on the page (or on a linked page on the provider''s own site) is acted on: domestic only -> the case is recorded domestic only; international students (or both), when that was the page''s only refusal -> the page goes back through the admission rule (security.scholarship_admit_from_provider_page_v1), which checks every other rule again. 0: shadow: what would be done is recorded on each read and nothing changes.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1421, 'F-SCH.01: ships in shadow; activation is a separate recorded step', 'Scholarship eligibility reader', 'security.scholarship_eligibility_apply_v1'),
 ('pipeline', 'sch_elig.silent_resolves', 'Scholarship eligibility reader: a page still silent is not for international students',
  '1: a scholarship whose page and linked eligibility page both say nothing about international students is recorded as not proven for international students (resolved, not sent to a person). 0: it stays unresolved and may go to a person in Layer 4.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1422, 'F-SCH.01: a policy decision for the Platform Admin; ships off', 'Scholarship eligibility reader', 'security.scholarship_eligibility_apply_v1'),
 ('pipeline', 'sch_elig.link_follow_on', 'Scholarship eligibility reader: read a linked eligibility page',
  '1: when the scholarship page is silent, the reader also reads pages it links to for its eligibility, terms or conditions on the same site (Firecrawl through the scholarship share). 0: the page only.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1423, 'F-SCH.01', 'Scholarship eligibility reader', 'public.svc_scholarship_eligibility_next (worker mode scholarship_eligibility)'),
 ('pipeline', 'sch_elig.links_max', 'Scholarship eligibility reader: linked pages read per scholarship',
  'At most this many linked eligibility or conditions pages are read for one silent scholarship page, best match first; reading stops at the first that proves who may apply.',
  'number', to_jsonb(1), 0, 3, 'pages', 1424, 'F-SCH.01', 'Scholarship eligibility reader', 'public.svc_scholarship_eligibility_next (worker mode scholarship_eligibility)'),
 ('pipeline', 'sch_elig.policy_refused_too', 'Scholarship eligibility reader: also read providers the admission scope refuses',
  '1: pages of providers the scholarship admission scope refuses today (non-university providers outside the pilot) are read too, so they are ready when the scope widens. 0: admission-eligible providers only.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1425, 'F-SCH.01', 'Scholarship eligibility reader', 'security.scholarship_eligibility_enqueue_v1'),
 ('pipeline', 'sch_elig.max_tries', 'Scholarship eligibility reader: tries before a read is recorded failed',
  'A read that fails (model error, page not readable) is tried again until it has been tried this many times; then it is recorded failed and may go to a person.',
  'number', to_jsonb(2), 1, 5, 'tries', 1426, 'F-SCH.01', 'Scholarship eligibility reader', 'public.svc_scholarship_eligibility_record'),
 ('pipeline', 'retry.sch_eligibility_hours', 'Scholarship eligibility reader: try a failed read again after',
  'A failed read is due again this long after it failed.',
  'number', to_jsonb(6), 1, 168, 'hours', 1427, 'F-SCH.01', 'Scholarship eligibility reader', 'public.svc_scholarship_eligibility_record'),
 ('pipeline', 'batch.sch_eligibility_read', 'Scholarship eligibility reader: pages read per worker call',
  'Each worker call (every 10 minutes while there is work) reads at most this many scholarship pages.',
  'number', to_jsonb(20), 1, 40, 'pages', 1428, 'F-SCH.01', 'Scholarship eligibility reader', 'security.scholarship_eligibility_fire_v1 (job scholarship-eligibility)'),
 ('pipeline', 'batch.sch_eligibility_enqueue', 'Scholarship eligibility reader: cases queued per run',
  'Each run queues at most this many unresolved eligibility cases for reading, oldest first.',
  'number', to_jsonb(200), 1, 5000, 'cases', 1429, 'F-SCH.01', 'Scholarship eligibility reader', 'security.scholarship_eligibility_enqueue_v1'),
 ('pipeline', 'batch.sch_eligibility_apply', 'Scholarship eligibility reader: answers acted on per run',
  'Each run acts on (or, in shadow, records) at most this many finished reads.',
  'number', to_jsonb(200), 1, 5000, 'reads', 1430, 'F-SCH.01', 'Scholarship eligibility reader', 'security.scholarship_eligibility_apply_v1'),
 ('pipeline', 'sch_flow.on', 'Scholarship flow guard: check the scholarship flow every hour',
  '1: every hour the scholarship flow is checked for causes that stop admission (a Layer 4 lane full, a built recovery switched off with work waiting, a coverage state no job can move, no scholarship found or admitted for sch_flow.stall_hours, cases unresolved past sch_flow.aged_days); each cause is one integration issue with its numbers and the setting that clears it. Reads and reports only. 0: off.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1440, 'F-SCH.01: ships on (reads and reports only)', 'Scholarship flow guard', 'security.scholarship_flow_guard_v1 (job scholarship-flow-guard)'),
 ('pipeline', 'sch_flow.stall_hours', 'Scholarship flow guard: admission has stalled after',
  'Admission has stalled when no scholarship page was found and none admitted for this long while unresolved cases wait.',
  'number', to_jsonb(24), 1, 168, 'hours', 1441, 'F-SCH.01', 'Scholarship flow guard', 'security.scholarship_flow_guard_v1'),
 ('pipeline', 'sch_flow.aged_days', 'Scholarship flow guard: a case is overdue after',
  'Unresolved coverage cases older than this are reported together as overdue.',
  'number', to_jsonb(7), 1, 90, 'days', 1442, 'F-SCH.01', 'Scholarship flow guard', 'security.scholarship_flow_guard_v1')
on conflict (toolset_key, key) do nothing;

-- 2. the reads ----------------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.scholarship_eligibility_reads (
  candidate_id bigint primary key references pipeline.scholarship_page_candidates(id) on delete cascade,
  provider_id uuid not null,
  state text not null default 'queued' check (state in ('queued', 'leased', 'done', 'failed')),
  signature text not null default '',
  tries int not null default 0,
  leased_until timestamptz,
  next_try_at timestamptz,
  outcome text check (outcome in ('proven', 'silent', 'unread')),
  result jsonb,
  applied jsonb,
  cost_usd numeric not null default 0,
  last_error text,
  queued_at timestamptz not null default now(),
  read_at timestamptz,
  updated_at timestamptz not null default now());
comment on table pipeline.scholarship_eligibility_reads is 'CF-247 F-SCH.01: the eligibility reader''s read of each scholarship page refused only for international_not_stated: state, the proven sentence (page or linked page), its cost, and what was done with it (shadow or live). Kept by job scholarship-eligibility.';
create index if not exists scholarship_eligibility_reads_due on pipeline.scholarship_eligibility_reads(state, next_try_at) where state in ('queued', 'leased');
create index if not exists scholarship_eligibility_reads_apply on pipeline.scholarship_eligibility_reads(read_at) where state = 'done' and applied is null;
alter table pipeline.scholarship_eligibility_reads enable row level security;
create trigger ai_spend_capture after insert or update of cost_usd on pipeline.scholarship_eligibility_reads
  for each row execute function security.ai_spend_capture_v1('scholarship_ai', 'delta', '{cost_usd}');

create table if not exists pipeline.scholarship_flow_checks (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  findings jsonb not null,
  raised jsonb not null default '{}'::jsonb);
comment on table pipeline.scholarship_flow_checks is 'CF-247 F-SCH.01: each hourly check of the scholarship flow (job scholarship-flow-guard): the numbers behind every cause checked and the integration issues raised or cleared.';
alter table pipeline.scholarship_flow_checks enable row level security;

-- 3. the reader ---------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.scholarship_eligibility_enqueue_v1(p_limit integer default null)
 returns integer language plpgsql security definer set search_path to '' as $function$
-- F-SCH.01: unresolved eligibility cases (coverage state international_unresolved: the AI called the page a scholarship, refused only for
-- international_not_stated) are queued once each, oldest first; a page whose stored copy changed since its read is queued again.
declare v_lim int := greatest(0, coalesce(p_limit, security.pipeline_num_v1('batch.sch_eligibility_enqueue', 200)::int));
        v_all boolean := security.pipeline_num_v1('sch_elig.policy_refused_too', 0) >= 1; v_n int; v_again int;
begin
  update pipeline.scholarship_eligibility_reads e set state = 'queued', outcome = null, result = null, applied = null, tries = 0, next_try_at = null,
         leased_until = null, signature = coalesce(c.content_hash, ''), queued_at = now(), updated_at = now()
    from pipeline.scholarship_page_candidates c
   where c.id = e.candidate_id and e.state in ('done', 'failed') and c.admit_status = 'rejected' and coalesce(c.content_hash, '') <> e.signature;
  get diagnostics v_again = row_count;
  -- the admission scope is decided once per provider (it is costly per row: 2,200 rows timed out in the dry run)
  with cand as materialized (
    select c.id, c.provider_id, coalesce(c.content_hash, '') sig, i.first_seen
      from pipeline.scholarship_coverage_items i
      join pipeline.scholarship_page_candidates c on c.provider_id = i.provider_id and i.item_key = 'cand:' || c.id::text
     where i.present and i.state = 'international_unresolved'
       and c.admit_status = 'rejected' and c.admitted_scholarship_id is null and c.matched_scholarship_id is null
       and not exists (select 1 from pipeline.scholarship_eligibility_reads e where e.candidate_id = c.id)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)),
  ok as materialized (
    select p.provider_id, v_all or coalesce(security.scholarship_admission_provider_ok_v1(p.provider_id), false) ok
      from (select distinct cand.provider_id from cand) p)
  insert into pipeline.scholarship_eligibility_reads(candidate_id, provider_id, signature)
  select cand.id, cand.provider_id, cand.sig from cand join ok on ok.provider_id = cand.provider_id and ok.ok
   order by cand.first_seen, cand.id
   limit v_lim
  on conflict (candidate_id) do nothing;
  get diagnostics v_n = row_count;
  return v_n + v_again;
end $function$;

create or replace function public.svc_scholarship_eligibility_next(p_limit integer)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
-- F-SCH.01: leases due reads for worker mode scholarship_eligibility with the pinned first model of the scholarship chain (the same model as the
-- re-check reader); held while sch_elig.on is 0 or the AI guards refuse (credit floor, daily ceiling, lane guard scholarship_ai).
declare v jsonb; v_model text; v_why text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('sch_elig.on', 0) < 1 then return jsonb_build_object('items', '[]'::jsonb, 'held', 'sch_elig.on is 0'); end if;
  v_why := security.ai_use_refusal_v1('scholarship_ai');
  if v_why is not null then return jsonb_build_object('items', '[]'::jsonb, 'held', v_why); end if;
  select m.model_identifier into v_model from pipeline.scholarship_ai_extract_settings s join pipeline.scholarship_ai_models m on m.code = s.chain[1] where s.id = 1;
  if v_model is null then return jsonb_build_object('items', '[]'::jsonb, 'held', 'no pinned model (scholarship_ai_extract_settings.chain)'); end if;
  with pick as (
    select e.candidate_id from pipeline.scholarship_eligibility_reads e
     where (e.state = 'queued' and coalesce(e.next_try_at, '-infinity') <= now()) or (e.state = 'leased' and e.leased_until < now())
     order by e.queued_at, e.candidate_id limit greatest(1, least(coalesce(p_limit, 10), 40))  -- fixed: the worker's upper bound per call
     for update skip locked),
  upd as (update pipeline.scholarship_eligibility_reads e set state = 'leased', leased_until = now() + interval '15 minutes', tries = e.tries + 1, updated_at = now()  -- fixed: lease timer
            from pick where e.candidate_id = pick.candidate_id returning e.candidate_id)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'url', coalesce(c.final_url, c.url), 'storage_path', c.storage_path, 'provider_id', c.provider_id,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = c.provider_id),
           'country', security.coverage_country(c.provider_id),
           'name', coalesce(nullif(btrim(c.facts->'admission'->>'name'), ''), nullif(btrim(c.facts->'ai'->>'name'), ''), c.title, ''),
           'model', v_model,
           'link_follow', security.pipeline_num_v1('sch_elig.link_follow_on', 1) >= 1,
           'links_max', security.pipeline_num_v1('sch_elig.links_max', 1)::int)), '[]'::jsonb)
    into v from upd u join pipeline.scholarship_page_candidates c on c.id = u.candidate_id;
  return jsonb_build_object('items', v);
end $function$;

create or replace function public.svc_scholarship_eligibility_record(p_id bigint, p_result jsonb, p_cost numeric, p_error text)
 returns text language plpgsql security definer set search_path to '' as $function$
-- F-SCH.01: the worker's answer for one leased read (exactly once per lease). An error or an unread page is tried again until sch_elig.max_tries,
-- then recorded failed; an answer is recorded done and acted on by security.scholarship_eligibility_apply_v1. The cost always counts.
declare r pipeline.scholarship_eligibility_reads%rowtype; v_state text; v_max int := security.pipeline_num_v1('sch_elig.max_tries', 2)::int;
        v_retry interval := make_interval(hours => security.pipeline_num_v1('retry.sch_eligibility_hours', 6)::int);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from pipeline.scholarship_eligibility_reads where candidate_id = p_id for update;
  if r.candidate_id is null then return 'missing'; end if;
  if p_error is not null or coalesce(p_result->>'outcome', '') not in ('proven', 'silent', 'unread') or p_result->>'outcome' = 'unread' then
    v_state := case when r.tries < v_max then 'queued' else 'failed' end;
    update pipeline.scholarship_eligibility_reads set state = v_state, leased_until = null, cost_usd = cost_usd + coalesce(p_cost, 0),
           last_error = left(coalesce(p_error, 'outcome ' || coalesce(p_result->>'outcome', 'missing')), 300),
           outcome = case when v_state = 'failed' and p_result->>'outcome' = 'unread' then 'unread' end,
           result = case when v_state = 'failed' then p_result end,
           next_try_at = case when v_state = 'queued' then now() + v_retry end, read_at = case when v_state = 'failed' then now() end, updated_at = now()
     where candidate_id = p_id;
  else
    v_state := 'done';
    update pipeline.scholarship_eligibility_reads set state = 'done', leased_until = null, cost_usd = cost_usd + coalesce(p_cost, 0), last_error = null,
           outcome = p_result->>'outcome', result = p_result, applied = null, next_try_at = null, read_at = now(), updated_at = now()
     where candidate_id = p_id;
  end if;
  return v_state;
end $function$;

create or replace function security.scholarship_eligibility_apply_v1(p_limit integer default null)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
-- F-SCH.01: the rule for finished reads. In shadow (sch_elig.apply_on 0) only what would be done is recorded on the read. Live:
--   domestic proven                         -> the case is recorded domestic_only (coverage state domestic_only, resolved);
--   international or both proven, the page's only refusal was international_not_stated, the sentence's page on the provider's own site
--                                           -> the page facts record the sentence and the candidate goes back through
--                                              security.scholarship_admit_from_provider_page_v1, which checks every other rule again;
--   silent, with sch_elig.silent_resolves   -> recorded as not proven for international students (resolved); otherwise it stays unresolved and
--                                              security.har_sch_generate_v1 may raise it for a person.
-- No agent and no person is replaced: the decision is the existing admission rule's, on a sentence the page states.
declare v_lim int := greatest(0, coalesce(p_limit, security.pipeline_num_v1('batch.sch_eligibility_apply', 200)::int));
        v_live boolean := security.pipeline_num_v1('sch_elig.apply_on', 0) >= 1;
        v_silent boolean := security.pipeline_num_v1('sch_elig.silent_resolves', 0) >= 1;
        r record; v_act text; v_url text; v_only boolean; v_res jsonb; v_ev jsonb; v_by jsonb := '{}'::jsonb;
begin
  for r in select e.candidate_id, e.outcome, e.result, c.provider_id, c.admit_status, c.admit_reasons, c.facts, c.admitted_scholarship_id, c.matched_scholarship_id,
                  coalesce(c.final_url, c.url) page_url
             from pipeline.scholarship_eligibility_reads e join pipeline.scholarship_page_candidates c on c.id = e.candidate_id
            where e.state in ('done', 'failed') and e.applied is null
            order by e.read_at nulls last, e.candidate_id limit v_lim loop
    v_url := coalesce(nullif(r.result->>'source_url', ''), r.page_url);
    v_only := coalesce(r.admit_reasons, '{}'::text[]) <@ array['international_not_stated']
              and not exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(r.facts->'admission'->'reasons') = 'array' then r.facts->'admission'->'reasons' else '[]'::jsonb end) x
                               where x <> 'international_not_stated');
    v_act := case
      when r.admit_status is distinct from 'rejected' or r.admitted_scholarship_id is not null or r.matched_scholarship_id is not null then 'changed_since'
      when r.outcome = 'proven' and coalesce((r.result->>'audience_proven')::boolean, false) and r.result->>'audience' = 'domestic' then 'domestic'
      when r.outcome = 'proven' and coalesce((r.result->>'audience_proven')::boolean, false) and r.result->>'audience' in ('international', 'both') then
        case when not coalesce(security.url_on_provider_sites(v_url, r.provider_id), false) or security.third_party_host_v1(coalesce(v_url, '')) then 'sentence_off_provider_site'
             when not v_only then 'proven_other_refusals'
             else 'admit' end
      when r.outcome = 'silent' then 'silent'
      else 'unsettled' end;
    v_ev := jsonb_build_object('audience', r.result->>'audience', 'quote', r.result->>'audience_quote', 'source', r.result->>'source', 'source_url', v_url,
                               'model', r.result->>'model', 'read_at', now(), 'by', 'security.scholarship_eligibility_apply_v1');
    if not v_live then
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'shadow', 'action', v_act, 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
    elsif v_act = 'domestic' then
      update pipeline.scholarship_page_candidates set admit_reasons = array_append(array_remove(coalesce(admit_reasons, '{}'::text[]), 'international_not_stated'), 'domestic_only'),
             facts = coalesce(facts, '{}'::jsonb) || jsonb_build_object('eligibility_read', v_ev) where id = r.candidate_id;
      insert into pipeline.scholarship_admission_log(candidate_id, provider_id, action, detail) values (r.candidate_id, r.provider_id, 'eligibility_domestic', v_ev);
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', v_act, 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
    elsif v_act = 'admit' then
      update pipeline.scholarship_page_candidates
         set facts = jsonb_set(jsonb_set(jsonb_set(coalesce(facts, '{}'::jsonb) || jsonb_build_object('international', true, 'eligibility_read', v_ev, 'eligibility_excerpt', left(coalesce(r.result->>'audience_quote', ''), 600)),
                                                   '{admission,international_explicit}', 'true'::jsonb, true), '{admission,admit}', 'true'::jsonb, true), '{admission,reasons}', '[]'::jsonb, true),
             admit_status = null, admit_reasons = null
       where id = r.candidate_id;
      v_res := security.scholarship_admit_from_provider_page_v1(r.candidate_id);
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', v_act, 'admission', v_res, 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
      v_act := case when coalesce((v_res->>'admitted')::boolean, false) then 'admitted' else 'admission_refused' end;
    elsif v_act = 'silent' and v_silent then
      update pipeline.scholarship_page_candidates set admit_reasons = array_append(array_remove(coalesce(admit_reasons, '{}'::text[]), 'international_not_stated'), 'international_not_proven_after_eligibility_read'),
             facts = coalesce(facts, '{}'::jsonb) || jsonb_build_object('eligibility_read', v_ev) where id = r.candidate_id;
      insert into pipeline.scholarship_admission_log(candidate_id, provider_id, action, detail) values (r.candidate_id, r.provider_id, 'eligibility_not_proven', v_ev);
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', 'silent_resolved', 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
      v_act := 'silent_resolved';
    else
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', v_act, 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
    end if;
    v_by := v_by || jsonb_build_object(v_act, coalesce((v_by->>v_act)::int, 0) + 1);
  end loop;
  return jsonb_build_object('live', v_live, 'by_action', v_by);
end $function$;

create or replace function security.scholarship_eligibility_fire_v1()
 returns jsonb language plpgsql security definer set search_path to '' as $function$
-- F-SCH.01, job scholarship-eligibility (every 10 minutes): queue, act on finished reads (shadow or live), and call the worker while reads are due
-- and the AI guards allow it. Nothing runs while sch_elig.on is 0.
declare v_q int; v_a jsonb; v_f boolean := false; v_due int;
begin
  if security.pipeline_num_v1('sch_elig.on', 0) < 1 then return jsonb_build_object('on', false); end if;
  v_q := security.scholarship_eligibility_enqueue_v1(null);
  v_a := security.scholarship_eligibility_apply_v1(null);
  select count(*) into v_due from pipeline.scholarship_eligibility_reads e
   where (e.state = 'queued' and coalesce(e.next_try_at, '-infinity') <= now()) or (e.state = 'leased' and e.leased_until < now());
  if v_due > 0 and security.ai_use_allowed_v1('scholarship_ai') then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'scholarship_eligibility', 'limit', security.pipeline_num_v1('batch.sch_eligibility_read', 20)::int));
    v_f := true;
  end if;
  return jsonb_build_object('on', true, 'queued', v_q, 'applied', v_a, 'due', v_due, 'fired', v_f);
end $function$;

revoke all on function security.scholarship_eligibility_enqueue_v1(integer) from public, anon, authenticated;
revoke all on function security.scholarship_eligibility_apply_v1(integer) from public, anon, authenticated;
revoke all on function security.scholarship_eligibility_fire_v1() from public, anon, authenticated;
revoke all on function public.svc_scholarship_eligibility_next(integer) from public, anon, authenticated;
revoke all on function public.svc_scholarship_eligibility_record(bigint, jsonb, numeric, text) from public, anon, authenticated;
grant execute on function public.svc_scholarship_eligibility_next(integer) to service_role;
grant execute on function public.svc_scholarship_eligibility_record(bigint, jsonb, numeric, text) to service_role;

-- 4 and 5. md5-guarded edits ----------------------------------------------------------------------------------------------------------------------------
create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.har_sch_generate_v1(integer)', '983b3939e4c8686fa6fcb03752f56370', array[
  array[$o$         and coalesce(security.scholarship_admission_provider_ok_v1(x.provider_id), false)),$o$,
        $n$         and coalesce(security.scholarship_admission_provider_ok_v1(x.provider_id), false)
         -- F-SCH.01 (12 Nov 2026): while the eligibility reader is on, an eligibility case goes to a person only once the reader has read it and found no
         -- sentence (or its read failed); a proven sentence is the admission rule's to act on, not a person's
         and (x.state <> 'international_unresolved' or security.pipeline_num_v1('sch_elig.on', 0) < 1
              or exists (select 1 from pipeline.scholarship_eligibility_reads e where x.item_key = 'cand:' || e.candidate_id::text
                          and (e.state = 'failed' or (e.state = 'done' and e.outcome = 'silent'))))),$n$]
], array[1]);

select pg_temp.edit_n('security.scholarship_pilot_report_v1()', 'a9a207a4e7f9481ee202470f98cb4511', array[
  array[$o$               and (a.audience is distinct from 'international' or a.facts is null or a.l4_eligibility$o$,
        $n$               -- F-SCH.01 (12 Nov 2026): international_and_domestic (or both) is open to international students; a record withdrawn by a later
               -- check is no longer live and is not counted (its page facts are the later read's, not the admitted ones)
               and a.publication_status is distinct from 'withdrawn'
               and (coalesce(a.audience, '') not in ('international', 'international_and_domestic', 'both') or a.facts is null or a.l4_eligibility$n$],
  array[$o$    select l.provider_id, s.id sid, s.source_url, s.provider_id rec_provider, s.audience, sp.facts,$o$,
        $n$    select l.provider_id, s.id sid, s.source_url, s.provider_id rec_provider, s.audience, s.publication_status, sp.facts,$n$]
], array[1, 1]);

-- 6. the flow guard -------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.scholarship_flow_guard_v1()
 returns jsonb language plpgsql security definer set search_path to '' as $function$
-- F-SCH.01, job scholarship-flow-guard (hourly): the causes that stop scholarships being admitted, each as one integration issue with its numbers and
-- the setting or owner that clears it; a cause no longer present is marked condition cleared. Reads and reports only: no switch is changed here.
declare v_stall_h int := security.pipeline_num_v1('sch_flow.stall_hours', 24)::int; v_aged_d int := security.pipeline_num_v1('sch_flow.aged_days', 7)::int;
        v_stall interval := make_interval(hours => v_stall_h); v_aged interval := make_interval(days => v_aged_d);
        v_cap int := security.pipeline_num_v1('har.open_max_per_lane', 150)::int;
        f jsonb := '[]'::jsonb; x jsonb; v_raised jsonb := '{}'::jsonb; v_iss jsonb; v_n int; v_m int; v_k int;
begin
  if security.pipeline_num_v1('sch_flow.on', 1) < 1 then return jsonb_build_object('on', false); end if;
  -- a. a Layer 4 lane at its cap while cases of its class wait unraised
  for x in select jsonb_build_object('lane', l.lane, 'open', l.open, 'cap', v_cap,
                    'waiting', case l.lane when 'sch_coverage' then (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.state in ('international_unresolved', 'source_not_discovered', 'ownership_conflict')) - l.open
                                          else (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.state = 'admitted_not_published' and i.reason ~ 'no stated award value') - l.open end)
             from (select i.lane, count(*) open from pipeline.layer4_interventions i where i.lane in ('sch_coverage', 'sch_value') and i.status in ('ai_pending', 'awaiting_input', 'resuming') group by 1) l
            where l.open >= v_cap loop
    if (x->>'waiting')::int > 0 then
      f := f || jsonb_build_object('code', 'lane_full:' || (x->>'lane'), 'severity', 'P1', 'count', (x->>'waiting')::int, 'detail', x,
             'title', format('Scholarships: Layer 4 lane %s is full (%s open, cap %s); %s cases wait unraised', x->>'lane', x->>'open', v_cap, x->>'waiting'),
             'expected', 'Cases a machine can settle are settled by a reader before Layer 4 (sch_elig.on for eligibility cases); the cap (har.open_max_per_lane) is not a queue.');
    end if;
  end loop;
  -- b. a built recovery switched off while its work waits
  for x in select jsonb_build_object('switch', s.k, 'waiting', s.n, 'what', s.what) from (values
      ('sch_elig.on', (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.state = 'international_unresolved')::int, 'eligibility cases a reader could settle'),
      ('sch_cov.recover_listings_on', (select count(*) from pipeline.scholarship_listing_pages l where l.source = 'suggested' and not l.active)::int
                                     + (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.state = 'traversal_incomplete')::int, 'listing pages found and never traversed'),
      ('sch_cov.recover_register_pages_on', (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.state = 'rejected_incorrectly' and i.recovery = 'reopen_read')::int, 'register pages never read'),
      ('sch_cov.recover_stored_reads_on', (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.state = 'rejected_incorrectly' and i.recovery = 'reread_stored')::int, 'refused pages that could be read again from their stored copy'),
      ('retry.scholarship_transient_recover_on', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending' and r.reason ~* 'could not be read|statement timeout')::int, 'Layer 4 reviews that are only a failed page read')
    ) s(k, n, what)
    where s.n > 0 and security.pipeline_num_v1(s.k, 0) < 1 loop
    f := f || jsonb_build_object('code', 'recovery_off:' || (x->>'switch'), 'severity', 'P2', 'count', (x->>'waiting')::int, 'detail', x,
           'title', format('Scholarships: %s waiting while %s is 0 (%s)', x->>'waiting', x->>'switch', x->>'what'),
           'expected', format('The Platform Admin switches %s on (Settings > Pipeline settings) or records why it stays off.', x->>'switch'));
  end loop;
  -- c. coverage states no job can move: providers reported unresolved while the scholarship scope refuses them
  select count(*), count(*) filter (where exists (select 1 from pipeline.scholarship_page_candidates c where c.provider_id = p.provider_id)) into v_n, v_m
    from pipeline.scholarship_coverage_providers p
   where p.provider_state in ('source_not_discovered', 'source_found_unread', 'traversal_incomplete', 'international_unresolved', 'rejected_incorrectly', 'awaiting_layer4', 'admitted_not_published', 'ownership_conflict')
     and security.scholarship_scope_v1(p.provider_id) <> 'in_scope';
  if v_n > 0 then
    f := f || jsonb_build_object('code', 'dead_end_scope', 'severity', 'P2', 'count', v_n, 'detail', jsonb_build_object('providers', v_n, 'with_pages_found', v_m),
           'title', format('Scholarships: %s providers are reported unresolved but the scholarship scope refuses them (%s already have pages found)', v_n, v_m),
           'expected', 'The scope decision (scholarship.pilot_only, scholarship_min_courses, scholarship.refill_open_countries) admits them, or coverage reports them blocked by policy (sch_cov.policy_disposition_on).');
  end if;
  -- d. admission stalled
  select count(*) into v_k from pipeline.scholarship_coverage_items i where i.present and i.state in ('source_not_discovered', 'source_found_unread', 'traversal_incomplete', 'international_unresolved', 'rejected_incorrectly', 'awaiting_layer4');
  if v_k > 0 and not exists (select 1 from pipeline.scholarship_page_candidates c where c.found_at > now() - v_stall)
     and not exists (select 1 from pipeline.scholarship_admission_log l where l.action = 'admitted' and l.at > now() - v_stall) then
    f := f || jsonb_build_object('code', 'admission_stalled', 'severity', 'P1', 'count', v_k, 'detail', jsonb_build_object('unresolved', v_k, 'window_hours', v_stall_h),
           'title', format('Scholarships: nothing found or admitted for %s hours while %s cases are unresolved', v_stall_h, v_k),
           'expected', 'Discovery, listing and reading jobs take work every run; a job that reports success with no work while cases wait is a stall.');
  end if;
  -- e. cases overdue
  select count(*) into v_n from pipeline.scholarship_coverage_items i join pipeline.scholarship_coverage_state_codes s on s.code = i.state
   where i.present and not s.resolved and i.first_seen < now() - v_aged;
  if v_n > 0 then
    f := f || jsonb_build_object('code', 'cases_overdue', 'severity', 'P2', 'count', v_n, 'detail', jsonb_build_object('overdue', v_n, 'by_state',
             (select jsonb_object_agg(q.state, q.n) from (select i.state, count(*) n from pipeline.scholarship_coverage_items i join pipeline.scholarship_coverage_state_codes s on s.code = i.state
                where i.present and not s.resolved and i.first_seen < now() - v_aged group by 1) q)),
           'title', format('Scholarships: %s coverage cases unresolved for more than %s days', v_n, v_aged_d),
           'expected', 'Each unresolved state has a job that moves it; the flow guard''s other findings name the ones that do not.');
  end if;
  -- raise or refresh each finding; clear causes no longer present
  for x in select * from jsonb_array_elements(f) loop
    begin
      v_iss := security.integration_issue_upsert_v1(jsonb_build_object(
        'fingerprint', 'sch_flow:' || (x->>'code'), 'title', x->>'title', 'layer', 'Layer 2', 'subsystem', 'scholarship flow guard', 'severity', x->>'severity',
        'workstream', 'A8', 'validation_layer', 'V4', 'source', 'scholarship-flow-guard',
        'root_cause_class', case when x->>'code' like 'recovery_off:%' or x->>'code' = 'dead_end_scope' then 'human_decision' when x->>'code' like 'lane_full:%' then 'queue_or_lease' else 'job_config' end,
        'failure', x->>'title', 'expected', x->>'expected', 'evidence', x->'detail', 'observed_at', now()), 'scholarship-flow-guard');
      v_raised := v_raised || jsonb_build_object(x->>'code', v_iss->>'issue_ref');
    exception when others then v_raised := v_raised || jsonb_build_object(x->>'code', 'error: ' || left(sqlerrm, 160));
    end;
  end loop;
  update pipeline.integration_issues i set condition_cleared_at = now()
   where i.fingerprint like 'sch\_flow:%' and i.condition_cleared_at is null and i.status <> 'closed'
     and not exists (select 1 from jsonb_array_elements(f) y where 'sch_flow:' || (y->>'code') = i.fingerprint);
  insert into pipeline.scholarship_flow_checks(findings, raised) values (f, v_raised);
  return jsonb_build_object('on', true, 'findings', jsonb_array_length(f), 'raised', v_raised);
end $function$;
revoke all on function security.scholarship_flow_guard_v1() from public, anon, authenticated;

-- 7. jobs (G1), catalogue first -----------------------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('scholarship-eligibility', 'Scholarships', 60, 'Scholarship eligibility reader',
  'Every 10 minutes: queues scholarship pages refused only for "international not stated", acts on finished reads (shadow until sch_elig.apply_on), and calls worker mode scholarship_eligibility while reads are due and the AI guards allow it (batch.sch_eligibility_read pages a call). Switch sch_elig.on (off until the Platform Admin switches it on).',
  5, true, null),
 ('scholarship-flow-guard', 'Scholarships', 61, 'Scholarship flow guard',
  'Every hour at :43: checks the causes that stop scholarships being admitted (Layer 4 lane full, built recovery switched off with work waiting, coverage states no job can move, admission stalled, cases overdue) and raises one integration issue per cause; clears causes that are gone. Reads and reports only. Switch sch_flow.on.',
  5, false, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'scholarship-eligibility') then
    perform cron.schedule('scholarship-eligibility', '4-59/10 * * * *', 'select security.scholarship_eligibility_fire_v1()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'scholarship-flow-guard') then
    perform cron.schedule('scholarship-flow-guard', '43 * * * *', 'select security.scholarship_flow_guard_v1()');
  end if;
end $j$;

-- 8. register (housekeeping) ----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'scholarship-eligibility', 'Layer 2', 'Scholarships', 'Eligibility reader for scholarships refused only for international_not_stated (shadow until sch_elig.apply_on)', 'active', '{}', '20261113030000'),
 ('job', 'scholarship-flow-guard', 'Layer 2', 'Scholarships', 'Hourly check of the causes that stop scholarship admission; one integration issue per cause', 'active', '{}', '20261113030000'),
 ('table', 'pipeline.scholarship_eligibility_reads', 'Layer 2', 'Scholarships', 'Eligibility reads, their proven sentences and what was done with them', 'active', '{}', '20261113030000'),
 ('table', 'pipeline.scholarship_flow_checks', 'Layer 2', 'Scholarships', 'Hourly scholarship flow checks and the issues raised', 'active', '{}', '20261113030000')
on conflict do nothing;

-- 9. post-check ---------------------------------------------------------------------------------------------------------------------------------------
do $p$
declare v jsonb; v_q int;
begin
  if pg_get_functiondef('security.har_sch_generate_v1(integer)'::regprocedure) not like '%scholarship_eligibility_reads e where x.item_key = %' then raise exception 'post-check: har_sch_generate_v1 not edited'; end if;
  if pg_get_functiondef('security.scholarship_pilot_report_v1()'::regprocedure) not like '%''international_and_domestic'', ''both''%' then raise exception 'post-check: pilot report not edited'; end if;
  if (select count(*) from cron.job where jobname in ('scholarship-eligibility', 'scholarship-flow-guard')) <> 2 then raise exception 'post-check: jobs'; end if;
  if (select count(*) from pipeline.automation_catalogue where jobname in ('scholarship-eligibility', 'scholarship-flow-guard')) <> 2 then raise exception 'post-check: catalogue'; end if;
  if security.pipeline_num_v1('sch_elig.on', -1) <> 0 or security.pipeline_num_v1('sch_elig.apply_on', -1) <> 0 or security.pipeline_num_v1('sch_elig.silent_resolves', -1) <> 0 then
    raise exception 'post-check: the reader, its action and the silent policy ship off';
  end if;
  -- while the reader is off nothing is queued or read, and Layer 4 raising is unchanged
  if (security.scholarship_eligibility_fire_v1()->>'on')::boolean then raise exception 'post-check: the reader ran while off'; end if;
  -- the cases the reader will read once switched on (counted only)
  select count(*) into v_q from pipeline.scholarship_coverage_items i join pipeline.scholarship_page_candidates c on c.provider_id = i.provider_id and i.item_key = 'cand:' || c.id::text
   where i.present and i.state = 'international_unresolved' and c.admit_status = 'rejected';
  if v_q = 0 then raise notice 'post-check: no international_unresolved case to read today'; end if;
  -- the guard runs and records
  v := security.scholarship_flow_guard_v1();
  if not coalesce((v->>'on')::boolean, false) then raise exception 'post-check: flow guard did not run (%)', v; end if;
  raise notice 'flow guard: %', v;
  -- the pilot report no longer stops on the two false findings
  if exists (select 1 from security.scholarship_pilot_report_v1() r where r.provider_id in ('2b61a262-c219-4396-bdbf-e35aee47639d', '435ca964-67a5-483c-bc8f-9d5ab059c0c2') and r.stop) then
    raise exception 'post-check: a pilot provider still stops on the corrected measure';
  end if;
end $p$;
