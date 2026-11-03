-- CF-247 scholarship sources and ownership (Layer 4 integrator handover 3 Nov 2026, Priority 3 items 9-12; evidence recovery mandate 20:47 §6;
-- upstream evidence audit 19:50; Platform Admin decisions 19:22/19:23). Lands after workstream A's shared contract (20261104010000).
--
-- 1. Approved single reads (item 9). The Platform Admin approved a Firecrawl and AI read of two held scholarships only: VU ref 1323 and Bond ref
--    1230. No governed route reads one item:
--    - security.scholarship_ai_enqueue_v1 queues every unread candidate of a provider, not one item;
--    - public.svc_scholarship_ai_next hands the worker the candidate's stored copy before anything else, so Bond (candidate 6712, copy of
--      29 Sep 2026) would be re-read from the old copy, never from the page;
--    - with AI admission on, a settled answer goes to security.scholarship_ai_apply_v1 and may admit, bypassing the Layer 4 decision.
--    security.scholarship_read_request_v1(review, fresh, reason, approved_by) is the single-item read control. It is bounded to one held item,
--    logged in pipeline.scholarship_read_requests, and refuses: a held item that is not pending, a page on a directory site, an item whose owner
--    is in question (open owner proposal), a provider not searched or not published, an item already queued, and any request past the daily
--    allowance scholarship.single_read_daily_max, which ships at 0 (OFF: a read spends Firecrawl and AI). It queues exactly one row on the
--    normal scholarship AI path (pipeline.scholarship_ai_queue, run_kind admit/reread, the active model and instructions), so the page is read
--    by the worker through svc_fc_spend and stored as evidence in the normal way. A fresh request (fresh_read) is never given a stored copy and
--    never counts as one while the paid lane is held. A request-bound read never admits or publishes: its answer is attached to the held item
--    in Layer 4 (security.scholarship_ai_review_open_v1), where the decision stays. A page that cannot be read ends the request at once (one
--    read, no retry, no other model), so a dead page costs one credit.
-- 2. Ownership of held scholarships on directory pages (item 10). Live 3 Nov 2026 20:5x: 21 pending held scholarships, all on state-government
--    listing pages (coursesearch.studymelbourne.vic.gov.au 12, search.studyqueensland.qld.gov.au 9), held by 5 provider records (Lexis TESOL 9,
--    Marriott Academy 5, Kangaroo International College 3, Prime Education Group 3, Victorian Skills College 1). Every candidate of those five
--    providers (77, 56, 77, 68, 77) is on a portal host: discovery (map_search) kept portal search results as the provider's own pages. The hosts
--    are now listed as directory sites, so the AI queue closes new reads of them (v2.15.271), but the held items raised before stay open and
--    their names point to other institutions. security.scholarship_owner_check_v1 records one proposal per such held item in
--    pipeline.scholarship_owner_proposals, with its evidence (holder, page host, how it was found, page title and heading, stored copy,
--    extractions) and the institutions it names, matched to provider records of the same country by name or alias, with whether that
--    institution already holds a scholarship of the same name. It proposes; it never reassigns, refuses or admits. Ships ON as the 'auto'
--    remedy sch_owner_proposals (records only). The decision is the Platform Admin's (paste file); a read of an item with an open proposal is
--    refused (owners checked before credits are spent).
-- 3. Report: security.scholarship_sources_report_v1() (read only) measures each root cause registered here: held items on directory pages and
--    their proposals, held items duplicating an active scholarship of the same provider (series key), scholarships on '/staging/' addresses,
--    and the single-read requests by state. security.scholarship_sources_verify_v1(issue) is the verification of the remedies below.
-- 4. Root causes and remedies registered through workstream A's contract.
-- 5. Directory-site candidates are never queued (IQ-00132, overnight mandate 3 Nov 2026 21:59 P1). Live 3 Nov 2026: 22,133 scholarship AI queue
--    rows (77 providers, 13 Oct to 2 Nov) were queued by the nightly scholarship-ai-backfill (security.scholarship_ai_enqueue_v1) and then failed
--    by svc_scholarship_ai_next with skip_reason 'directory site'; a failed row leaves no extraction, so the same candidates were queued again
--    every night (7,962 in the last 7 days). 22:06 AEDT: 7,555 directory-site candidates of 164 providers are still queueable (21 have a pending
--    held item: the D4 refusals). The enqueue now marks such a candidate refused once (admit_status 'skipped', admit_reasons
--    {directory_site}, an admission-log row with outcome not_needed) and never queues it; a candidate with a pending held item is left to Layer 4.
--    A known scholarship whose page is on a directory site is not queued for a re-read either. Ships ON (scholarship.enqueue_directory_gate_on 1):
--    it only stops work the worker refuses; it reads, spends and admits nothing.
--
-- Settings (G2): scholarship.single_read_daily_max (0, OFF), batch.scholarship_owner_check (200), scholarship.enqueue_directory_gate_on (1, ON).
-- Edited live functions (md5-guarded; live md5s read 3 Nov 2026 20:50-20:55 AEDT and re-read 22:05 AEDT after v2.15.443, unchanged):
--   public.svc_scholarship_ai_next(integer)                         18e76dbc9984be55370434ca27066c7b -> 709ad0f93b16e99f8962e85671f0b291
--   public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)
--                                                                   aa337a9fb30a75452a7b54bddbf8d00f -> b2fafccb2532afc3e0d1337588b5c43d
--   security.scholarship_ai_has_copy_v1(bigint)                     08db702a7e4231ea00acf36da80c04d4 -> ecc54cd39a4fb9fc9c4c2217f6548d30
--   security.scholarship_ai_enqueue_v1(text,uuid[],uuid,boolean)   04a9aa8c56fc0d5593c813da3ecd270d -> 549948c5251a1ce3d424266d155e70cb
-- Read, not edited: security.scholarship_ai_review_open_v1(bigint,text) 0f10b0a35109fd6a6c6be36e4d4ea26d.
-- Not touched: anything changed in v2.15.434 (workstream C), the consumer API (G3), manual course-link bindings.
-- Replaces: queuing directory-site candidates every night for the worker to refuse (scholarship_ai_enqueue_v1); the stored-copy-first read for an approved fresh read (svc_scholarship_ai_next, scholarship_ai_has_copy_v1); admission by an approved
--           single read (svc_scholarship_ai_record: the answer goes to Layer 4)
-- Retires: nothing
-- Nothing is dropped or deleted. Nothing is read, spent, admitted or published by this migration.

do $guard$
begin
  if to_regclass('pipeline.ops_remedies') is null or to_regprocedure('security.ops_remedy_register_v1(text,jsonb)') is null
     or to_regprocedure('security.ops_root_cause_register_v1(text,jsonb)') is null then
    raise exception 'scholarship sources and ownership needs workstream A''s shared contract (20261104010000) first';
  end if;
end $guard$;

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

-- 0. definitions read, not edited, are the ones this change was written against
do $g$
declare v_sig text;
begin
  if md5(pg_get_functiondef('security.scholarship_ai_review_open_v1(bigint,text)'::regprocedure)) <> '0f10b0a35109fd6a6c6be36e4d4ea26d' then
    raise exception 'live security.scholarship_ai_review_open_v1 differs from the definition this change was written against';
  end if;
  foreach v_sig in array array['security.scholarship_ai_active_v1()', 'security.scholarship_ai_fire_v1()', 'security.third_party_host_v1(text)',
                               'security.provider_sch_search_off_v1(uuid)', 'security.scholarship_series_key_v1(text)', 'security.coverage_country(uuid)',
                               'security.site_host_v1(text)'] loop
    if to_regprocedure(v_sig) is null then raise exception 'this change reads %, which does not exist', v_sig; end if;
  end loop;
end $g$;

-- 1. settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'scholarship.single_read_daily_max', 'Approved single scholarship reads a day',
  'How many held scholarships may be read on their own each day through security.scholarship_read_request_v1 (one Firecrawl read and the AI read, on the normal scholarship path; the answer goes to Layer 4). 0 switches single reads off. Each request names who approved it.',
  'number', to_jsonb(0), 0, 10, 'reads', 327, 'CF-247 handover 3 Nov 2026 Priority 3 item 9: ships off; the Platform Admin sets it for an approved read', 'Scholarships',
  'security.scholarship_read_request_v1'),
 ('pipeline', 'batch.scholarship_owner_check', 'Held scholarships checked for ownership per run',
  'Each run of the owner check (remedy sch_owner_proposals) records at most this many new owner proposals for held scholarships on directory pages.',
  'number', to_jsonb(200), 1, 1000, 'held items', 328, 'CF-247 handover 3 Nov 2026 Priority 3 item 10', 'Scholarships',
  'security.scholarship_owner_check_v1; remedy sch_owner_proposals'),
 ('pipeline', 'scholarship.enqueue_directory_gate_on', 'Never queue scholarship pages on directory sites',
  '1: a candidate page on a directory site is marked refused (not needed) when the scholarship AI enqueue meets it, instead of being queued for the worker to refuse every night; known scholarships on a directory site are not queued for a re-read. 0: queued as before.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 329, 'CF-247 IQ-00132, overnight mandate 3 Nov 2026 21:59 P1: stop directory-site refusals being queued again', 'Scholarships',
  'security.scholarship_ai_enqueue_v1')
on conflict (toolset_key, key) do nothing;

-- 2. tables and columns (beside the consumer API; nothing it reads changes)
create table if not exists pipeline.scholarship_read_requests (
  id bigint generated always as identity primary key,
  review_id bigint not null,
  candidate_id bigint,
  scholarship_id uuid,
  provider_id uuid,
  url text not null,
  fresh boolean not null,
  reason text not null,
  approved_by text not null,
  requested_by text not null default current_user,
  requested_at timestamptz not null default now(),
  queue_id bigint,
  state text not null default 'queued' check (state in ('queued', 'read', 'read_failed', 'refused')),
  before jsonb not null default '{}'::jsonb,
  outcome jsonb,
  finished_at timestamptz);
comment on table pipeline.scholarship_read_requests is 'CF-247 (4 Nov 2026): approved single reads of held scholarships (security.scholarship_read_request_v1): who approved, why, fresh or not, the held item before, the one queue row, and the outcome (read, read_failed, refused) with the extraction, stored copy and evidence. One open request per held item.';
create unique index if not exists scholarship_read_requests_open on pipeline.scholarship_read_requests(review_id) where state = 'queued';

alter table pipeline.scholarship_ai_queue add column if not exists fresh_read boolean not null default false;
alter table pipeline.scholarship_ai_queue add column if not exists read_request_id bigint;
comment on column pipeline.scholarship_ai_queue.fresh_read is 'CF-247 (4 Nov 2026): read the page now; no stored copy is given to the worker or counted as held.';
comment on column pipeline.scholarship_ai_queue.read_request_id is 'CF-247 (4 Nov 2026): the approved single read (pipeline.scholarship_read_requests) this row serves; its answer goes to Layer 4 and is never applied.';

create table if not exists pipeline.scholarship_owner_proposals (
  id bigint generated always as identity primary key,
  review_id bigint not null unique,
  candidate_id bigint,
  holder_provider_id uuid,
  url text not null,
  host text,
  finding text not null check (finding in ('directory_page')),
  named text,
  owner_candidates jsonb not null default '[]'::jsonb,
  proposed_action text not null check (proposed_action in ('refuse_from_holder')),
  evidence jsonb not null,
  state text not null default 'proposed' check (state in ('proposed', 'decided')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decision jsonb);
comment on table pipeline.scholarship_owner_proposals is 'CF-247 (4 Nov 2026): one owner proposal per held scholarship whose page is on a directory site (security.scholarship_owner_check_v1): the evidence that the holder is not the owner, the institutions the page names (provider records of the same country, and whether each already holds a scholarship of that name) and the proposed action. Proposals only: nothing is reassigned, refused or admitted here; the decision is the Platform Admin''s.';

-- 3. the single-item read control
create or replace function security.scholarship_read_request_v1(p_review bigint, p_fresh boolean, p_reason text, p_approved_by text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
-- CF-247 (4 Nov 2026, handover Priority 3 item 9): one approved read of one held scholarship, on the normal scholarship AI path, logged
declare v pipeline.scholarship_ai_reviews%rowtype; a record; v_why text; v_req bigint; v_q bigint;
        v_max int := security.pipeline_num_v1('scholarship.single_read_daily_max', 0)::int;
        v_today int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'a single read is requested by a Platform Admin paste (postgres) only'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 10 or length(btrim(coalesce(p_approved_by, ''))) < 3 or p_fresh is null then
    raise exception 'give who approved the read and when, the reason, and whether the page must be read fresh';
  end if;
  perform pg_advisory_xact_lock(hashtext('scholarship_read_request'));
  select * into v from pipeline.scholarship_ai_reviews where id = p_review for update;
  select count(*) into v_today from pipeline.scholarship_read_requests r where r.state <> 'refused'
     and r.requested_at >= (date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne');  -- fixed: the allowance is per Melbourne calendar day
  select * into a from security.scholarship_ai_active_v1();
  v_why := case
    when v.id is null then 'no such held item'
    when v.status <> 'pending' then 'the held item is ' || v.status
    when v.candidate_id is null and v.scholarship_id is null then 'the held item has no candidate or scholarship'
    when security.third_party_host_v1(v.url) then 'directory site: the page is not the provider''s own; decide the owner first'
    when exists (select 1 from pipeline.scholarship_owner_proposals o where o.review_id = v.id and o.state = 'proposed') then 'the owner is in question: decide the owner proposal first'
    when v.provider_id is not null and (security.provider_sch_search_off_v1(v.provider_id) or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = v.provider_id))
      then 'the provider is not searched for scholarships or not published'
    when exists (select 1 from pipeline.scholarship_ai_queue q where q.state in ('queued', 'leased')
                  and ((v.candidate_id is not null and q.candidate_id = v.candidate_id) or (v.scholarship_id is not null and q.scholarship_id = v.scholarship_id)))
      then 'a read of this item is already queued'
    when a.model_code is null then 'scholarship AI is off'
    when v_today >= v_max then 'single reads are off or today''s allowance is used (scholarship.single_read_daily_max = ' || v_max || ')'
  end;
  insert into pipeline.scholarship_read_requests(review_id, candidate_id, scholarship_id, provider_id, url, fresh, reason, approved_by, state, before, outcome, finished_at)
  values (p_review, v.candidate_id, v.scholarship_id, v.provider_id, coalesce(v.url, '?'), p_fresh, btrim(p_reason), btrim(p_approved_by),
          case when v_why is null then 'queued' else 'refused' end,
          jsonb_build_object('status', v.status, 'reason', v.reason, 'extraction_ids', v.extraction_ids, 'storage_path', v.storage_path,
                             'candidate_storage_path', (select c.storage_path from pipeline.scholarship_page_candidates c where c.id = v.candidate_id)),
          case when v_why is not null then jsonb_build_object('why', v_why) end, case when v_why is not null then now() end)
  returning id into v_req;
  if v_why is not null then return jsonb_build_object('ok', false, 'request', v_req, 'why', v_why); end if;
  insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, candidate_id, scholarship_id, provider_id, url, fresh_read, read_request_id)
  values (a.model_code, a.prompt_version, case when v.candidate_id is not null then 'admit' else 'reread' end, v.candidate_id,
          case when v.candidate_id is null then v.scholarship_id end, v.provider_id, v.url, p_fresh, v_req)
  returning id into v_q;
  update pipeline.scholarship_read_requests set queue_id = v_q where id = v_req;
  perform security.scholarship_ai_fire_v1();
  return jsonb_build_object('ok', true, 'request', v_req, 'queue_id', v_q, 'fresh', p_fresh, 'model', a.model_code);
end $function$;
revoke all on function security.scholarship_read_request_v1(bigint, boolean, text, text) from public, anon, authenticated;
comment on function security.scholarship_read_request_v1(bigint, boolean, text, text) is 'CF-247 (4 Nov 2026): the single-item read control for a held scholarship. Bounded to one held item, logged in pipeline.scholarship_read_requests, within scholarship.single_read_daily_max (0 = off). Queues one row on the normal scholarship AI path; the answer goes to Layer 4.';

-- the end of a request-bound read: its answer is attached to the held item in Layer 4 (never applied), and the request records the outcome
create or replace function security.scholarship_read_request_close_v1(p_request bigint, p_extraction bigint, p_state text, p_reason text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare e pipeline.scholarship_ai_extractions%rowtype; r jsonb;
begin
  select * into e from pipeline.scholarship_ai_extractions where id = p_extraction;
  -- the same copy as a decided held item would repeat that decision (security.scholarship_ai_review_open_v1); a request never decides, so it is only recorded
  if exists (select 1 from pipeline.scholarship_ai_reviews x where x.status in ('admitted', 'refused') and x.url = e.url and coalesce(x.storage_path, '') = coalesce(e.storage_path, '')) then
    r := jsonb_build_object('linked', false, 'why', 'the same copy as a decided held item; not attached');
  else
    r := security.scholarship_ai_review_open_v1(p_extraction, p_reason);
  end if;
  update pipeline.scholarship_read_requests set state = p_state, finished_at = now(),
         outcome = jsonb_build_object('extraction', e.id, 'storage_path', e.storage_path, 'evidence_id', e.evidence_id, 'url', e.url, 'model', e.model_code,
                     'verdict', e.verdict, 'error', e.error, 'name', e.answer->>'name', 'audience', e.answer->>'audience', 'audience_quote', e.answer->>'audience_quote',
                     'offered', e.answer->>'offered', 'offered_quote', e.answer->>'offered_quote', 'dates_quote', e.answer->>'dates_quote',
                     'open_date', e.answer->>'open_date', 'close_date', e.answer->>'close_date', 'value', e.answer->'value', 'review', r)
   where id = p_request and state = 'queued';
  return r;
end $function$;
revoke all on function security.scholarship_read_request_close_v1(bigint, bigint, text, text) from public, anon, authenticated;

-- 4. the read path: a fresh request gets no stored copy; a request-bound answer goes to Layer 4 (md5-guarded edits of live text)
select pg_temp.edit_once('public.svc_scholarship_ai_next(integer)', '18e76dbc9984be55370434ca27066c7b', '709ad0f93b16e99f8962e85671f0b291', array[
  array[$e$           where q.state = 'queued' and q.next_try_at <= now() and q.candidate_id is not null$e$,
        $e$           where q.state = 'queued' and q.next_try_at <= now() and q.candidate_id is not null and not q.fresh_read  -- CF-247 4 Nov 2026: an approved fresh read takes no copy$e$],
  array[$e$           'storage_path', coalesce(u.storage_path, (select c.storage_path$e$,
        $e$           'storage_path', case when u.fresh_read then null else coalesce(u.storage_path, (select c.storage_path$e$],
  array[$e$order by x.at desc limit 1)))), '[]'::jsonb)$e$,
        $e$order by x.at desc limit 1)) end)), '[]'::jsonb)$e$]], array[1, 1, 1]);

select pg_temp.edit_once('security.scholarship_ai_has_copy_v1(bigint)', '08db702a7e4231ea00acf36da80c04d4', 'ecc54cd39a4fb9fc9c4c2217f6548d30', array[
  array[$e$                  where q.id = p_queue_id
$e$,
        $e$                  where q.id = p_queue_id and not q.fresh_read  -- CF-247 4 Nov 2026: an approved fresh read never counts a stored copy
$e$]], array[1]);

select pg_temp.edit_once('public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)',
  'aa337a9fb30a75452a7b54bddbf8d00f', 'b2fafccb2532afc3e0d1337588b5c43d', array[
  array[$e$    return jsonb_build_object('ok', true, 'retry', true);$e$,
        $e$    -- CF-247 4 Nov 2026: an approved single read refused for credits three times ends its request
    if q.read_request_id is not null and q.attempts >= 3 then
      update pipeline.scholarship_read_requests set state = 'refused', finished_at = now(), outcome = jsonb_build_object('why', 'no scraper credit after 3 tries')
       where id = q.read_request_id and state = 'queued';
    end if;
    return jsonb_build_object('ok', true, 'retry', true);$e$],
  array[$e$  v_why := case when q.run_kind in ('admit', 'reread') then security.scholarship_ai_unsettled_v1(p_answer, p_checks, p_verdict, p_error) end;$e$,
        $e$  -- CF-247 4 Nov 2026: an approved single read whose page could not be read ends here (one read; no retry, no other model)
  if q.read_request_id is not null and p_error is not null and p_storage_path is null then
    update pipeline.scholarship_ai_queue set state = 'done', done_at = now(), leased_until = null, extraction_id = v_id where id = q.id;
    r := security.scholarship_read_request_close_v1(q.read_request_id, v_id, 'read_failed', 'Approved read: the page could not be read (' || left(p_error, 200) || ')');
    return jsonb_build_object('ok', true, 'extraction', v_id, 'request', r);
  end if;
  v_why := case when q.run_kind in ('admit', 'reread') then security.scholarship_ai_unsettled_v1(p_answer, p_checks, p_verdict, p_error) end;$e$],
  array[$e$    insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url, step, storage_path, root_id)$e$,
        $e$    insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url, step, storage_path, root_id, fresh_read, read_request_id)$e$],
  array[$e$            coalesce(p_storage_path, q.storage_path), coalesce(q.root_id, q.id));$e$,
        $e$            coalesce(p_storage_path, q.storage_path), coalesce(q.root_id, q.id), q.fresh_read and coalesce(p_storage_path, q.storage_path) is null, q.read_request_id);$e$],
  array[$e$  select ai_admission into v_on from pipeline.scholarship_ai_extract_settings where id = 1;$e$,
        $e$  -- CF-247 4 Nov 2026: an approved single read never admits or publishes; its answer goes to the held item in Layer 4, where the decision stays
  if q.read_request_id is not null then
    if p_error is null or q.attempts >= 3 then
      r := security.scholarship_read_request_close_v1(q.read_request_id, v_id, case when p_error is null then 'read' else 'read_failed' end,
             coalesce(v_why, 'Approved read: answer recorded; the decision stays in Layer 4'));
    end if;
    return jsonb_build_object('ok', true, 'extraction', v_id, 'request', r);
  end if;
  select ai_admission into v_on from pipeline.scholarship_ai_extract_settings where id = 1;$e$]], array[1, 1, 1, 1, 1]);

select pg_temp.edit_once('security.scholarship_ai_enqueue_v1(text,uuid[],uuid,boolean)', '04a9aa8c56fc0d5593c813da3ecd270d', '549948c5251a1ce3d424266d155e70cb', array[
  array[$e$declare a record; v_n int := 0; v_k int;$e$,
        $e$declare a record; v_n int := 0; v_k int; v_gate boolean := security.pipeline_num_v1('scholarship.enqueue_directory_gate_on', 1) >= 1;$e$],
  array[$e$  if a.model_code is null then return 0; end if;
$e$,
        $e$  if a.model_code is null then return 0; end if;
  -- CF-247 4 Nov 2026 (IQ-00132): a candidate on a directory site is never queued (the worker refuses it); it is marked refused once, outcome not needed
  if v_gate then
    with d as (update pipeline.scholarship_page_candidates c set admit_status = 'skipped', admit_reasons = array['directory_site']
                where c.provider_id = any (p_provider_ids) and c.source <> 'register' and c.admitted_scholarship_id is null and c.matched_scholarship_id is null
                  and coalesce(c.admit_status, '') not in ('skipped', 'duplicate', 'admitted', 'matched_held')
                  and security.third_party_host_v1(coalesce(c.final_url, c.url))
                  and not exists (select 1 from pipeline.scholarship_ai_reviews r where r.candidate_id = c.id and r.status = 'pending')
               returning c.id, c.provider_id)
    insert into pipeline.scholarship_admission_log(candidate_id, provider_id, action, detail)
    select d.id, d.provider_id, 'skipped', jsonb_build_object('by', 'enqueue', 'reason', 'directory_site', 'outcome', 'not_needed', 'issue', 'IQ-00132') from d;
  end if;
$e$],
  array[$e$     and coalesce(c.admit_status, '') not in ('skipped', 'duplicate', 'admitted', 'matched_held')
     and not exists$e$,
        $e$     and coalesce(c.admit_status, '') not in ('skipped', 'duplicate', 'admitted', 'matched_held')
     and not (v_gate and security.third_party_host_v1(coalesce(c.final_url, c.url)))
     and not exists$e$],
  array[$e$     where s.provider_id = any (p_provider_ids) and s.lifecycle_status = 'active'
$e$,
        $e$     where s.provider_id = any (p_provider_ids) and s.lifecycle_status = 'active'
       and not (v_gate and security.third_party_host_v1(coalesce(sp.final_url, sp.url)))  -- CF-247 4 Nov 2026 (IQ-00132)
$e$]], array[1, 1, 1, 1]);

-- 5. ownership proposals for held scholarships on directory pages (records only)
create or replace function security.scholarship_owner_check_v1(p_limit integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
-- CF-247 (4 Nov 2026, handover Priority 3 item 10): a held scholarship whose page is on a directory site is not shown to be its holder's. One
-- proposal each, with the evidence and the institutions the page names; nothing is reassigned, refused or admitted.
declare v_new int; v_done int;
begin
  update pipeline.scholarship_owner_proposals o set state = 'decided', decided_at = coalesce(r.decided_at, now()),
         decision = jsonb_build_object('status', r.status, 'note', r.note, 'decided_by', r.decided_by)
    from pipeline.scholarship_ai_reviews r where r.id = o.review_id and o.state = 'proposed' and r.status <> 'pending';
  get diagnostics v_done = row_count;
  with rv as (
    select r.id, r.candidate_id, r.provider_id, r.url, r.storage_path, r.extraction_ids, c.source, c.title, c.read_status, c.evidence_id,
           c.facts->>'h1' h1, c.facts->>'page_title' page_title,
           coalesce((select nullif(e.answer->>'name', '') from pipeline.scholarship_ai_extractions e where e.id = r.extraction_ids[array_upper(r.extraction_ids, 1)]),
                    nullif(c.facts->>'h1', ''), nullif(btrim(regexp_replace(coalesce(c.title, ''), '\s+[-|]\s+[^-|]*$', '')), ''), r.url) named
      from pipeline.scholarship_ai_reviews r left join pipeline.scholarship_page_candidates c on c.id = r.candidate_id
     where r.status = 'pending' and security.third_party_host_v1(r.url)
       and not exists (select 1 from pipeline.scholarship_owner_proposals o where o.review_id = r.id)
     order by r.id limit greatest(1, coalesce(p_limit, 1))),
  raw as (
    select p.id, btrim(regexp_replace(x, '\s+(pty\.?\s*ltd\.?|limited|ltd\.?|inc\.?)$', '', 'i')) part
      from catalogue.providers p, regexp_split_to_table(coalesce(p.display_name, '') || ',' || coalesce(p.canonical_name, ''), '\s*[,()]\s*') x
     where p.lifecycle_status = 'active'
    union select a.provider_id, a.alias from catalogue.provider_aliases a where a.valid_to is null),
  parts as (select id, part from raw union select id, btrim(regexp_replace(part, '\s+(college|university|institute|academy)$', '', 'i')) from raw),
  -- a name part must hold one distinctive word (not a place, an organisation type or a common word)
  ok as (select * from parts where length(part) >= 3 and exists (select 1 from regexp_split_to_table(lower(part), '[^a-z0-9]+') w where w <> '' and w not in (
           'the', 'of', 'and', 'for', 'international', 'australia', 'australian', 'sydney', 'melbourne', 'brisbane', 'perth', 'adelaide', 'hobart', 'darwin',
           'canberra', 'queensland', 'victoria', 'victorian', 'college', 'university', 'institute', 'academy', 'school', 'education', 'group', 'training',
           'english', 'language', 'centre', 'center', 'campus', 'nz', 'new', 'zealand', 'global', 'business', 'technology', 'management', 'studies', 'study',
           'services', 'holdings', 'trust', 'pty', 'ltd'))),
  m as (select rv.id rid, pt.id pid, max(length(pt.part)) l from rv join ok pt on pt.id <> rv.provider_id
          and security.coverage_country(pt.id) is not distinct from security.coverage_country(rv.provider_id)
          and rv.named ~* ('(^|\W)' || regexp_replace(pt.part, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g') || '(\W|$)') group by 1, 2),
  ins as (
    insert into pipeline.scholarship_owner_proposals(review_id, candidate_id, holder_provider_id, url, host, finding, named, owner_candidates, proposed_action, evidence)
    select rv.id, rv.candidate_id, rv.provider_id, rv.url, security.site_host_v1(rv.url), 'directory_page', rv.named,
           coalesce((select jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website,
                       'holds_same_name', (select coalesce(jsonb_agg(s.id), '[]'::jsonb) from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active'
                                             and security.scholarship_series_key_v1(s.name) = security.scholarship_series_key_v1(rv.named))) order by m.l desc)
                       from m join catalogue.providers p on p.id = m.pid where m.rid = rv.id), '[]'::jsonb),
           'refuse_from_holder',
           jsonb_build_object('holder', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = rv.provider_id),
                              'holder_website', (select p.website from catalogue.providers p where p.id = rv.provider_id),
                              'holder_host', (select security.site_host_v1(p.website) from catalogue.providers p where p.id = rv.provider_id),
                              'page_host', security.site_host_v1(rv.url), 'directory_site', true,
                              'found_by', rv.source, 'discovery_method', (select d.method from pipeline.scholarship_discovery_providers d where d.provider_id = rv.provider_id),
                              'holder_candidates', (select count(*) from pipeline.scholarship_page_candidates c where c.provider_id = rv.provider_id),
                              'holder_candidates_on_directory_sites', (select count(*) from pipeline.scholarship_page_candidates c where c.provider_id = rv.provider_id and security.third_party_host_v1(c.url)),
                              'title', rv.title, 'page_title', rv.page_title, 'h1', rv.h1, 'read_status', rv.read_status,
                              'evidence_id', rv.evidence_id, 'storage_path', rv.storage_path, 'extraction_ids', rv.extraction_ids)
      from rv
    on conflict (review_id) do nothing
    returning 1)
  select count(*) into v_new from ins;
  return jsonb_build_object('proposed', v_new, 'decided', v_done,
                            'open', (select count(*) from pipeline.scholarship_owner_proposals where state = 'proposed'));
end $function$;
revoke all on function security.scholarship_owner_check_v1(integer) from public, anon, authenticated;

create or replace function security.scholarship_sources_report_v1()
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- CF-247 (4 Nov 2026): measures of the scholarship source and ownership root causes (read only)
  select jsonb_build_object(
    'held_on_directory_pages', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending' and security.third_party_host_v1(r.url)),
    'held_on_directory_pages_without_proposal', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending' and security.third_party_host_v1(r.url)
                                                   and not exists (select 1 from pipeline.scholarship_owner_proposals o where o.review_id = r.id)),
    'owner_proposals_open', (select count(*) from pipeline.scholarship_owner_proposals o where o.state = 'proposed'),
    'held_duplicating_active', (select count(*) from pipeline.scholarship_ai_reviews r join pipeline.scholarship_ai_extractions e on e.id = r.extraction_ids[array_upper(r.extraction_ids, 1)]
                                 where r.status = 'pending' and r.candidate_id is not null and nullif(e.answer->>'name', '') is not null
                                   and exists (select 1 from scholarship.scholarships s where s.provider_id = r.provider_id and s.lifecycle_status = 'active'
                                                and security.scholarship_series_key_v1(s.name) = security.scholarship_series_key_v1(e.answer->>'name'))),
    'staging_addresses_active', (select count(*) from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
                                  where s.lifecycle_status = 'active' and sp.url ~* '/staging/'),
    'staging_addresses_published', (select count(*) from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
                                     where s.lifecycle_status = 'active' and s.publication_status = 'published' and sp.url ~* '/staging/'),
    'directory_candidates_queueable', (select count(*) from pipeline.scholarship_page_candidates c where c.source <> 'register' and c.admitted_scholarship_id is null
                                        and c.matched_scholarship_id is null and coalesce(c.admit_status, '') not in ('skipped', 'duplicate', 'admitted', 'matched_held')
                                        and security.third_party_host_v1(coalesce(c.final_url, c.url))
                                        and not exists (select 1 from pipeline.scholarship_ai_reviews r where r.candidate_id = c.id and r.status = 'pending')),
    'held_on_staging_addresses', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending' and r.url ~* '/staging/'),
    'read_requests', (select coalesce(jsonb_object_agg(state, n), '{}'::jsonb) from (select state, count(*) n from pipeline.scholarship_read_requests group by 1) x))
$function$;
revoke all on function security.scholarship_sources_report_v1() from public, anon, authenticated;

-- remedy action and verification (workstream A's contract: (p_issue bigint) returns jsonb)
create or replace function security.scholarship_owner_proposals_remedy_v1(p_issue bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare r jsonb;
begin
  r := security.scholarship_owner_check_v1(security.pipeline_num_v1('batch.scholarship_owner_check', 200)::int);
  return jsonb_build_object('ok', true, 'changed', (r->>'proposed')::int + (r->>'decided')::int > 0, 'evidence', r || jsonb_build_object('issue', p_issue));
end $function$;
revoke all on function security.scholarship_owner_proposals_remedy_v1(bigint) from public, anon, authenticated;

create or replace function security.scholarship_sources_verify_v1(p_issue bigint)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
-- passed when the measure of the issue's root cause is clear (issue without a diagnosis: the owner-proposal measure)
declare m jsonb := security.scholarship_sources_report_v1(); v_rc text; v_ok boolean;
begin
  select i.diagnosis->>'root_cause' into v_rc from pipeline.integration_issues i where i.id = p_issue;
  v_ok := case coalesce(v_rc, 'sch_held_on_directory_page')
    when 'sch_held_on_directory_page' then (m->>'held_on_directory_pages_without_proposal')::int = 0
    when 'sch_held_duplicates_active' then (m->>'held_duplicating_active')::int = 0
    when 'sch_source_staging_address' then (m->>'staging_addresses_active')::int = 0 and (m->>'held_on_staging_addresses')::int = 0
    when 'sch_enqueue_directory_site' then (m->>'directory_candidates_queueable')::int = 0
    when 'sch_held_read_reuses_old_copy' then coalesce((m->'read_requests'->>'queued')::int, 0) = 0
    else false end;
  return jsonb_build_object('passed', v_ok, 'measure', m, 'evidence', jsonb_build_object('root_cause', v_rc, 'issue', p_issue));
end $function$;
revoke all on function security.scholarship_sources_verify_v1(bigint) from public, anon, authenticated;

-- 6. root causes and remedies (workstream A's contract)
select security.ops_root_cause_register_v1('sch_held_on_directory_page', jsonb_build_object('class', 'data',
  'title', 'Held scholarships on directory pages are held by a provider the page does not show',
  'description', 'Discovery (map_search) kept state-government listing pages (Study Melbourne, Study Queensland) as a provider''s own pages; the held items raised from them before the hosts were listed as directory sites stay open under holders the pages do not name (3 Nov 2026: 21 items, 5 providers).',
  'detect', jsonb_build_object('fn', 'security.scholarship_sources_report_v1()', 'measure', 'held_on_directory_pages > 0')));
select security.ops_root_cause_register_v1('sch_held_read_reuses_old_copy', jsonb_build_object('class', 'rule',
  'title', 'A held scholarship cannot be read again on its own, or freshly',
  'description', 'The AI enqueue takes a whole provider, svc_scholarship_ai_next gives the worker the candidate''s stored copy first, and a settled answer may admit while AI admission is on. An approved read of one held item (VU 1323, Bond 1230) had no governed route.',
  'detect', jsonb_build_object('fn', 'security.scholarship_sources_report_v1()', 'measure', 'read_requests')));
select security.ops_root_cause_register_v1('sch_held_duplicates_active', jsonb_build_object('class', 'data',
  'title', 'A held scholarship duplicates an active scholarship of the same provider',
  'description', 'A held item raised before the same scholarship was admitted from another address (for example Macquarie ref 1184 from a /staging/ address, published a347e086 from the official page) is never matched again; Layer 4 has no duplicate choice.',
  'detect', jsonb_build_object('fn', 'security.scholarship_sources_report_v1()', 'measure', 'held_duplicating_active > 0')));
select security.ops_root_cause_register_v1('sch_source_staging_address', jsonb_build_object('class', 'data',
  'title', 'Scholarships read from a staging address',
  'description', 'Scholarships admitted from students.mq.edu.au/.../overseas/staging/... addresses (start years 2016 to 2019 on the pages); no official address for the same scholarship is held except the Vice-Chancellor''s International Scholarship.',
  'detect', jsonb_build_object('fn', 'security.scholarship_sources_report_v1()', 'measure', 'staging_addresses_active > 0')));
select security.ops_root_cause_register_v1('course_link_title_only_sibling', jsonb_build_object('class', 'rule',
  'title', 'A course page is bound to a same-title sibling course by title alone while the page states the other course''s CRICOS code',
  'description', 'Two active registered courses of a provider share a title; the reader binds the page to one by its CRICOS code and to the other by exact title (Swinburne 095881J cricos_code, 088407E exact_title; 3 Nov 2026: 214 such addresses).',
  'detect', jsonb_build_object('tables', jsonb_build_array('catalogue.course_links', 'pipeline.evidence_artifacts'), 'measure', 'metadata identity_basis exact_title beside cricos_code on the same address')));

select security.ops_root_cause_register_v1('sch_enqueue_directory_site', jsonb_build_object('class', 'rule',
  'title', 'Scholarship candidates on directory sites are queued every night and refused by the worker',
  'description', 'security.scholarship_ai_enqueue_v1 had no directory-site gate; svc_scholarship_ai_next failed each row (skip_reason directory site) and left no extraction, so the nightly backfill queued them again (IQ-00132: 22,133 failed rows, 77 providers).',
  'detect', jsonb_build_object('fn', 'security.scholarship_sources_report_v1()', 'measure', 'directory_candidates_queueable > 0', 'issue', 'IQ-00132')));

select security.ops_remedy_register_v1('sch_enqueue_directory_gate', jsonb_build_object('authority', 'release', 'treats', jsonb_build_array('sch_enqueue_directory_site'),
  'title', 'The enqueue marks directory-site candidates refused (not needed) and never queues them (release 20261104210000)',
  'verify_fn', 'security.scholarship_sources_verify_v1(bigint)',
  'notes', 'Setting scholarship.enqueue_directory_gate_on (1). A candidate with a pending held item is left to Layer 4.'));
select security.ops_remedy_register_v1('sch_owner_proposals', jsonb_build_object('authority', 'auto', 'treats', jsonb_build_array('sch_held_on_directory_page'),
  'title', 'Record an owner proposal with evidence for each held scholarship on a directory page',
  'action_fn', 'security.scholarship_owner_proposals_remedy_v1(bigint)', 'verify_fn', 'security.scholarship_sources_verify_v1(bigint)',
  'notes', 'Records proposals only (pipeline.scholarship_owner_proposals). Nothing is reassigned, refused or admitted; reads of items with an open proposal are refused.'));
select security.ops_remedy_register_v1('sch_owner_decision', jsonb_build_object('authority', 'admin', 'treats', jsonb_build_array('sch_held_on_directory_page'),
  'title', 'Platform Admin decides owner proposals (refuse from the holder) by paste file',
  'verify_fn', 'security.scholarship_sources_verify_v1(bigint)',
  'notes', 'Layer 4 refusal through security.scholarship_ai_review_apply_v1 with the proposal as the reason; the named institution''s own page is the source. No silent reassignment.'));
select security.ops_remedy_register_v1('sch_single_approved_read', jsonb_build_object('authority', 'admin', 'treats', jsonb_build_array('sch_held_read_reuses_old_copy'),
  'title', 'Approved single read of one held scholarship (security.scholarship_read_request_v1)',
  'verify_fn', 'security.scholarship_sources_verify_v1(bigint)',
  'notes', 'Spends one Firecrawl read and the AI read; scholarship.single_read_daily_max ships 0. The answer goes to Layer 4.'));
select security.ops_remedy_register_v1('sch_duplicate_close', jsonb_build_object('authority', 'admin', 'treats', jsonb_build_array('sch_held_duplicates_active'),
  'title', 'Close a held scholarship as a duplicate of the active one (Layer 4 duplicate route)',
  'verify_fn', 'security.scholarship_sources_verify_v1(bigint)',
  'notes', 'The Layer 4 duplicate close route is built by another workstream; the decision stays with the review route.'));
select security.ops_remedy_register_v1('sch_staging_reread', jsonb_build_object('authority', 'admin', 'treats', jsonb_build_array('sch_source_staging_address'),
  'title', 'Read staging-address scholarships again through Read again; record moves; replace only with an official page held as evidence',
  'verify_fn', 'security.scholarship_sources_verify_v1(bigint)',
  'notes', 'pipeline.scholarship_pages.requested_at (the existing route); a moved or redirected page is recorded in pipeline.scholarship_source_moves.'));
select security.ops_remedy_register_v1('course_link_cricos_identity', jsonb_build_object('authority', 'release', 'treats', jsonb_build_array('course_link_title_only_sibling'),
  'title', 'Do not bind by exact title when the page states a CRICOS code of another active course of the provider',
  'notes', 'Interface request to the course-link owner (workstream B): the reader''s identity rule and a governed review of the existing bindings. No manual binding is changed.'));
