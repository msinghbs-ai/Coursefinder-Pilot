-- CF-247 s1321 (S1-Build; SS-Programme-Control 27 Nov 2026 21:08 AEDT, approved scoped development exception 1: "Implement the lightweight DOT
-- structured-data intake mechanism using existing record writers, evidence verification and admission rules").
-- What it adds:
--   1. pipeline.structured_intake_items: one row per submitted candidate (course-level academic entry or scholarship), with the submitter's own
--      key and a content key, so the same candidate is never taken twice, and its verification and outcome. No other store.
--   2. security.structured_intake_submit_v1: a closed list. Each candidate names its provider and course (identity: the course belongs to the
--      provider and its code is the submitted code), its scope, its facts and 1 to structured_intake.max_proofs proofs (https address, exact quote, sha256).
--   3. Verification on the platform's own stored copies (reuse before any fetch): security.structured_intake_next_v1 leases received items with the
--      newest stored copy of each proof page inside aer.stale_source_days; a page with none is read once directly by the worker (robots.txt
--      respected, no Firecrawl, no model, $0) and registered as ordinary evidence (action store), so it is reused, never read twice. The worker
--      (coverage-sweep mode intake_verify, v1.0.60) checks every quote is printed on that copy and security.structured_intake_record_v1 decides.
--   4. Decision, with the existing writers and admission rules:
--      - academic entry (scope exact_course): every quote on the stored copy; the course code printed on a proof page; the requirement quote on the
--        course's own bound page; the stated value and its scale in the quote. A course with active entry rows, a lock, a pending read or a
--        person's earlier rejection or return is compared or held, never overwritten. Otherwise the row is written as an ordinary proposed
--        course entry row with one Layer 4 course_entry_first_read item (reader structured_intake), exactly as the deterministic reader proposes
--        (security.aer_det_propose_v1). The existing machine rules (aer-machine-v1, aer-course-partial-v1) admit it or a person decides.
--        The other entry routes the submitter did not supply are carried as a dropped requirement, so the completeness gate never treats a partial
--        submission as the whole page.
--      - scholarship: the quotes are proved and the candidate is held with its reasons (a closed round, no current amount, a restricted or
--        affiliate scope). Scholarship activation authority stays with the Platform Admin; nothing is published by this change.
--   5. public.svc_structured_intake_v1 (service role): submit, next, store, record, verify, list. The operations workflow structured-intake reads a
--      submitter's file from the admin repository and calls submit; submit starts the worker once (pipeline.svc_pilot_submit_nonce).
-- G1: no job (on demand; the existing admission-rule-runner and aer-machine-admission jobs admit). G2: structured_intake.on, .verify_batch,
-- .confidence_verified, .max_items_per_submit, .max_proofs and .fetch_on are settings; the lease timer is a fixed claim timer.
-- G3: no consumer object changes (75/48 checked). Manual locks, decided Layer 4 items and cron checked. $0. Nothing dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the new objects

create temp table s1321_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before,
       (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) as decided_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $pre$;

create table if not exists pipeline.structured_intake_items (
  id uuid primary key default gen_random_uuid(),
  submitter text not null check (submitter ~ '^[a-z0-9][a-z0-9_-]{1,40}$'),
  batch_ref text not null check (length(batch_ref) between 1 and 200),
  candidate_key text not null check (length(candidate_key) between 1 and 200),
  content_key text not null,
  domain text not null check (domain in ('aer', 'scholarship')),
  provider_id uuid not null,
  course_id uuid,
  scope text not null,
  candidate jsonb not null,
  status text not null default 'received' check (status in ('received', 'verifying', 'proposed', 'compared', 'held', 'rejected')),
  status_reason text,
  verification jsonb,
  evidence_ids uuid[] not null default '{}',
  review_item_id uuid,
  row_ids uuid[] not null default '{}',
  attempts int not null default 0,
  leased_at timestamptz,
  submitted_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (submitter, candidate_key),
  unique (content_key)
);
create index if not exists structured_intake_items_status on pipeline.structured_intake_items (status, created_at);
comment on table pipeline.structured_intake_items is 'CF-247 s1321: structured candidates submitted by a research or processing worker (DOT first), one row each, with their verification on the platform''s own stored copies and the outcome (proposed through the existing course entry writer and Layer 4, compared with active rows, held or rejected). The submitter key and the content key keep each candidate single. Written only by security.structured_intake_*.';
alter table pipeline.structured_intake_items enable row level security;
revoke all on table pipeline.structured_intake_items from public, anon, authenticated;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
  ('pipeline', 'structured_intake.on', 'Structured intake: verify and propose submitted candidates',
   '1: submitted structured candidates (DOT and later processing workers) are proved on the platform''s stored copies and proposed through the existing writers. 0: candidates are kept as received and nothing is proved or proposed.',
   'number', to_jsonb(1), 0, 1, 'switch', 1570, 'Entry requirements', 'security.structured_intake_next_v1', 'CF-247 s1321 (SS-Programme-Control 27 Nov 2026 21:08)'),
  ('pipeline', 'structured_intake.verify_batch', 'Structured intake: candidates proved in one worker call',
   'How many received candidates one intake_verify call of the worker leases and proves on stored copies.',
   'number', to_jsonb(20), 1, 50, 'candidates', 1571, 'Entry requirements', 'security.structured_intake_next_v1', 'CF-247 s1321 (SS-Programme-Control 27 Nov 2026 21:08)'),
  ('pipeline', 'structured_intake.confidence_verified', 'Structured intake: confidence of a proved entry row',
   'The confidence written on a course entry row whose quote, course code and value were proved on the course''s own stored page. The machine rules admit rows at or above aer.machine_min_confidence.',
   'number', to_jsonb(0.9), 0.5, 1, 'share', 1572, 'Entry requirements', 'security.structured_intake_record_v1', 'CF-247 s1321 (SS-Programme-Control 27 Nov 2026 21:08)'),
  ('pipeline', 'structured_intake.max_items_per_submit', 'Structured intake: candidates in one submission',
   'The most candidates one submission may carry; a larger file is split by the submitter.',
   'number', to_jsonb(50), 1, 200, 'candidates', 1573, 'Entry requirements', 'security.structured_intake_submit_v1', 'CF-247 s1321 (SS-Programme-Control 27 Nov 2026 21:08)'),
  ('pipeline', 'structured_intake.max_proofs', 'Structured intake: proofs per candidate',
   'The most proof quotes one candidate may carry.',
   'number', to_jsonb(8), 1, 20, 'proofs', 1574, 'Entry requirements', 'security.structured_intake_submit_v1', 'CF-247 s1321 (SS-Programme-Control 27 Nov 2026 21:08)'),
  ('pipeline', 'structured_intake.fetch_on', 'Structured intake: read a proof page that has no stored copy',
   '1: a proof page with no stored copy inside the freshness period is read once directly (robots.txt respected, no Firecrawl, no model, $0) and stored as evidence, then reused. 0: such a candidate is held until the page is captured by the existing reads.',
   'number', to_jsonb(1), 0, 1, 'switch', 1575, 'Entry requirements', 'security.structured_intake_next_v1', 'CF-247 s1321 (SS-Programme-Control 27 Nov 2026 21:08)')
on conflict do nothing;

-- normalised page address for comparing a proof page with a bound page (scheme and host in lower case, no trailing slash, no fragment)
create or replace function security.structured_intake_url_v1(p_url text) returns text
language sql immutable set search_path to ''
as $f$ select regexp_replace(regexp_replace(lower(btrim(coalesce(p_url, ''))), '#.*$', ''), '/+$', '') $f$;
revoke all on function security.structured_intake_url_v1(text) from public, anon, authenticated;

-- 1. submit: a closed list; nothing outside it is stored
create or replace function security.structured_intake_submit_v1(p_submitter text, p_batch text, p_items jsonb, p_by text) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_max int := security.pipeline_num_v1('structured_intake.max_items_per_submit', 50)::int;
  v_maxp int := security.pipeline_num_v1('structured_intake.max_proofs', 8)::int;
  x jsonb; p jsonb; v_dom text; v_pid uuid; v_cid uuid; v_code text; v_scope text; v_key text; v_ck text; v_n int := 0; v_dup int := 0; v_id uuid;
  v_bad jsonb := '[]'::jsonb; v_idx int := 0; v_err text; v_cand jsonb;
begin
  if coalesce(btrim(p_by), '') = '' then raise exception 'INVALID_INPUT: who is submitting (by) is required'; end if;
  if p_submitter !~ '^[a-z0-9][a-z0-9_-]{1,40}$' then raise exception 'INVALID_INPUT: submitter'; end if;
  if coalesce(btrim(p_batch), '') = '' or length(p_batch) > 200 then raise exception 'INVALID_INPUT: batch reference'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > v_max then
    raise exception 'INVALID_INPUT: items is a list of 1 to % candidates', v_max;
  end if;
  for x in select * from jsonb_array_elements(p_items) loop
    v_idx := v_idx + 1; v_err := null;
    v_dom := x->>'domain'; v_scope := coalesce(x->>'scope', ''); v_key := btrim(coalesce(x->>'provisional_key', x->>'candidate_key', ''));
    begin v_pid := (x->>'provider_id')::uuid; v_cid := nullif(x->>'course_id', '')::uuid; exception when others then v_err := 'provider_id or course_id is not an id'; end;
    v_code := upper(btrim(coalesce(x->>'course_code', '')));
    if v_err is null and v_dom not in ('aer', 'scholarship') then v_err := 'domain is aer or scholarship'; end if;
    if v_err is null and (v_key = '' or length(v_key) > 200) then v_err := 'provisional_key is required'; end if;
    if v_err is null and v_scope !~ '^[a-z_]{3,40}$' then v_err := 'scope'; end if;
    if v_err is null and jsonb_typeof(x->'facts') <> 'object' then v_err := 'facts is an object'; end if;
    if v_err is null and (jsonb_typeof(x->'proof') <> 'array' or jsonb_array_length(x->'proof') = 0 or jsonb_array_length(x->'proof') > v_maxp) then v_err := format('proof is a list of 1 to %s quotes', v_maxp); end if;
    if v_err is null and not exists (select 1 from catalogue.providers pr where pr.id = v_pid) then v_err := 'unknown provider'; end if;
    if v_err is null and v_cid is not null and not exists (select 1 from catalogue.courses c where c.id = v_cid and c.provider_id = v_pid and upper(coalesce(c.course_code, '')) = v_code) then
      v_err := 'the course is not this provider''s course with this code';
    end if;
    if v_err is null and v_dom = 'aer' and v_cid is null then v_err := 'an academic entry candidate names its course'; end if;
    if v_err is null then
      for p in select * from jsonb_array_elements(x->'proof') loop
        if coalesce(p->>'final_url', '') !~ '^https://[a-z0-9.-]+(/|$)' or length(p->>'final_url') > 500 then v_err := 'proof address is an https address'; exit; end if;
        if length(btrim(coalesce(p->>'quote', ''))) < 8 or length(p->>'quote') > 300 then v_err := 'proof quote is 8 to 300 characters'; exit; end if;
        if coalesce(p->>'sha256', '') !~ '^[0-9a-f]{64}$' then v_err := 'proof sha256'; exit; end if;
      end loop;
    end if;
    if v_err is not null then v_bad := v_bad || jsonb_build_object('index', v_idx, 'key', v_key, 'error', v_err); continue; end if;
    -- only the fields the intake reads are kept (no free-form instruction travels with a candidate)
    v_cand := jsonb_build_object('domain', v_dom, 'provider_code', x->>'provider_code', 'course_code', v_code, 'scope', v_scope, 'status', x->>'status',
                'study_level', x->>'study_level', 'audience', x->>'audience', 'edition', x->>'edition', 'facts', x->'facts',
                'proof', (select jsonb_agg(jsonb_build_object('source', left(q->>'source', 80), 'final_url', q->>'final_url', 'quote', q->>'quote', 'sha256', q->>'sha256',
                                                              'locator', left(q->>'locator', 200), 'mime', left(q->>'mime', 80), 'retrieved_at', q->>'retrieved_at'))
                          from jsonb_array_elements(x->'proof') q),
                'unresolved', x->'unresolved');
    v_ck := md5(v_dom || '|' || coalesce(v_cid::text, v_pid::text) || '|' || (x->'facts')::text);
    insert into pipeline.structured_intake_items (submitter, batch_ref, candidate_key, content_key, domain, provider_id, course_id, scope, candidate, submitted_by)
    values (p_submitter, p_batch, v_key, v_ck, v_dom, v_pid, v_cid, v_scope, v_cand, left(p_by, 120))
    on conflict do nothing returning id into v_id;
    if v_id is null then v_dup := v_dup + 1; else v_n := v_n + 1; end if;
    v_id := null;
  end loop;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('structured_intake', 'submitted', 'pipeline.structured_intake_items',
          jsonb_build_object('submitter', p_submitter, 'batch', p_batch, 'received', v_n, 'duplicates', v_dup, 'refused', jsonb_array_length(v_bad), 'change', 's1321', 'by', left(p_by, 120)), security.system_actor_id());
  return jsonb_build_object('received', v_n, 'duplicates', v_dup, 'refused', v_bad);
end $f$;
comment on function security.structured_intake_submit_v1(text, text, jsonb, text) is 'CF-247 s1321: takes structured candidates (closed list: domain, provider, course and code, scope, facts, 1 to structured_intake.max_proofs proofs with https address, exact quote and sha256). A candidate already taken (same submitter key or same course and facts) is a duplicate and is not stored again.';
revoke all on function security.structured_intake_submit_v1(text, text, jsonb, text) from public, anon, authenticated;

-- 2. next: lease received items with the stored copy of each proof page (reuse; nothing is fetched)
create or replace function security.structured_intake_next_v1() returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_on int := security.pipeline_num_v1('structured_intake.on', 1)::int;
  v_n int := security.pipeline_num_v1('structured_intake.verify_batch', 20)::int;
  v_stale int := security.pipeline_num_v1('aer.stale_source_days', 90)::int;
  v_items jsonb;
begin
  if v_on <> 1 then return jsonb_build_object('held', 'intake_off', 'items', '[]'::jsonb); end if;
  with picked as (
    select i.id from pipeline.structured_intake_items i
     where i.status = 'received' or (i.status = 'verifying' and i.leased_at < now() - interval '15 minutes')  -- fixed: claim timer of a lost worker call
     order by i.created_at, i.id limit v_n for update skip locked
  ), upd as (
    update pipeline.structured_intake_items i set status = 'verifying', leased_at = now(), attempts = i.attempts + 1, updated_at = now()
      from picked where i.id = picked.id returning i.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'proofs',
           (select coalesce(jsonb_agg(jsonb_build_object('i', q.o - 1, 'quote', q.p->>'quote', 'url', q.p->>'final_url',
                     'evidence_id', ev.id, 'storage_path', ev.storage_path, 'mime', ev.mime_type, 'content_hash', ev.content_hash, 'captured_at', ev.captured_at) order by q.o), '[]'::jsonb)
              from jsonb_array_elements(u.candidate->'proof') with ordinality q(p, o)
              left join lateral (select e.id, e.storage_path, e.mime_type, e.content_hash, e.captured_at from pipeline.evidence_artifacts e
                                  where e.source_url = q.p->>'final_url' and e.storage_path is not null and e.captured_at >= now() - make_interval(days => v_stale)
                                  order by e.captured_at desc limit 1) ev on true))), '[]'::jsonb)
    into v_items from upd u;
  return jsonb_build_object('items', v_items, 'fetch_on', security.pipeline_num_v1('structured_intake.fetch_on', 1)::int, 'min_quote_chars', security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int,
                            'pdf_max_pages', 40);  -- fixed: pages of a stored PDF proof read for its text, as the entry reader's default
end $f$;
comment on function security.structured_intake_next_v1() is 'CF-247 s1321: leases up to structured_intake.verify_batch received structured candidates and gives, for each proof, the newest stored copy of its page inside aer.stale_source_days (reused, never fetched).';
revoke all on function security.structured_intake_next_v1() from public, anon, authenticated;

-- 3. record: the worker's quote proofs, then the decision through the existing writers
create or replace function security.structured_intake_record_v1(p_item uuid, p_result jsonb) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  i pipeline.structured_intake_items%rowtype; c catalogue.courses%rowtype; g record;
  v_conf numeric := security.pipeline_num_v1('structured_intake.confidence_verified', 0.9);
  v_proofs jsonb := coalesce(p_result->'proofs', '[]'::jsonb); v_f jsonb; v_req jsonb; v_req_ev uuid; v_q text;
  v_missing jsonb; v_ev uuid[]; v_code_ok boolean; v_status text; v_reason text; v_ver jsonb;
  v_kind text; v_desc text; v_score numeric; v_basis text; v_aud text; v_row uuid; v_rev uuid; v_act int; v_cmp jsonb; v_srcurl text; v_cap date;
  v_why text[] := '{}';
begin
  select * into i from pipeline.structured_intake_items where id = p_item for update;
  if i.id is null then raise exception 'INVALID_INPUT: unknown intake item'; end if;
  if i.status <> 'verifying' then return jsonb_build_object('item_id', i.id, 'status', i.status, 'note', 'not leased'); end if;
  v_f := i.candidate->'facts';
  -- every submitted quote must be printed on the platform's stored copy of its page
  select coalesce(jsonb_agg(jsonb_build_object('i', q.o - 1, 'url', q.p->>'final_url', 'reason', coalesce(z.r->>'reason', 'not_checked'))), '[]'::jsonb)
    into v_missing
    from jsonb_array_elements(i.candidate->'proof') with ordinality q(p, o)
    left join lateral (select x.value as r from jsonb_array_elements(v_proofs) x where (x.value->>'i')::int = q.o - 1 limit 1) z on true
   where not coalesce((z.r->>'found')::boolean, false);
  select coalesce(array_agg(distinct (x.value->>'evidence_id')::uuid), '{}') into v_ev from jsonb_array_elements(v_proofs) x where (x.value->>'found')::boolean and x.value->>'evidence_id' is not null;
  v_ver := jsonb_build_object('verifier', p_result->>'verifier', 'proofs', v_proofs, 'not_proved', v_missing, 'at', now());
  if jsonb_array_length(v_missing) > 0 then
    v_status := case when exists (select 1 from jsonb_array_elements(v_missing) m where m->>'reason' in ('no_stored_copy', 'stored_copy_unreadable')) and
                          not exists (select 1 from jsonb_array_elements(v_missing) m where m->>'reason' not in ('no_stored_copy', 'stored_copy_unreadable')) then 'held' else 'rejected' end;
    v_reason := case when v_status = 'held' then 'HELD:NO_STORED_COPY: a proof page has no stored copy and could not be read directly (robots, a refusal or a non-HTML page); it is proved when the page is captured'
                     else 'REJECTED:QUOTE_NOT_ON_STORED_COPY: a submitted quote is not printed on the platform''s stored copy of its page' end;
  elsif i.domain = 'scholarship' then
    -- proved; held with its reasons (activation authority stays with the Platform Admin; nothing is published here)
    if i.scope <> 'exact_course' then v_why := array_append(v_why, 'scope ' || i.scope || ' is not a published award for every student of the course'); end if;
    if (v_f->>'application_close') ~ '^\d{4}-\d{2}-\d{2}$' and (v_f->>'application_close')::date < (now() at time zone 'Australia/Melbourne')::date then
      v_why := array_append(v_why, 'the application round closed ' || (v_f->>'application_close')); end if;
    if v_f->'amount' is null or v_f->>'amount' is null then v_why := array_append(v_why, 'no current amount is stated'); end if;
    if cardinality(v_why) = 0 then v_why := array_append(v_why, 'scholarship candidates are proved and wait for the scholarship writers under the Platform Admin''s activation authority'); end if;
    v_status := 'held'; v_reason := 'HELD:SCHOLARSHIP: ' || array_to_string(v_why, '; ');
  else
    select * into c from catalogue.courses where id = i.course_id;
    select p.url, p.evidence_id, p.identity_basis into g from pipeline.coverage_course_pages p where p.course_id = i.course_id and p.status = 'bound' order by p.bound_at desc nulls last limit 1;
    v_code_ok := exists (select 1 from jsonb_array_elements(i.candidate->'proof') q where position(upper(coalesce(c.course_code, '#')) in upper(q->>'quote')) > 0);
    select q.p, (z.r->>'evidence_id')::uuid into v_req, v_req_ev
      from jsonb_array_elements(i.candidate->'proof') with ordinality q(p, o)
      join lateral (select x.value as r from jsonb_array_elements(v_proofs) x where (x.value->>'i')::int = q.o - 1 and (x.value->>'found')::boolean limit 1) z on true
     where security.structured_intake_url_v1(q.p->>'final_url') = security.structured_intake_url_v1(g.url)
       and position(upper(coalesce(c.course_code, '#')) in upper(q.p->>'quote')) = 0
     order by q.o limit 1;
    select count(*) into v_act from catalogue.course_entry_requirements r where r.course_id = i.course_id and r.status = 'active';
    if c.id is null or c.lifecycle_status <> 'active' then v_status := 'held'; v_reason := 'HELD:COURSE_NOT_ACTIVE';
    elsif i.scope <> 'exact_course' then v_status := 'held'; v_reason := 'HELD:SCOPE: only exact-course candidates are proposed';
    elsif not v_code_ok then v_status := 'held'; v_reason := 'HELD:IDENTITY: no proof quote prints the course code ' || coalesce(c.course_code, '');
    elsif g.url is null then v_status := 'held'; v_reason := 'HELD:NO_BOUND_PAGE: the course has no bound course page';
    elsif v_req is null then v_status := 'held'; v_reason := 'HELD:BOUND_PAGE_DIFFERS: no requirement quote is on the course''s bound page (' || g.url || '); the page is relinked by the existing course-page binding';
    elsif v_act > 0 or coalesce((v_f->>'comparison_only')::boolean, false) then
      v_q := v_req->>'quote';
      v_cmp := (select coalesce(jsonb_agg(jsonb_build_object('row_id', r.id, 'kind', r.kind, 'min_entry_score', r.min_entry_score, 'basis', r.min_entry_score_basis,
                 'same_value', (v_f->>'min_value') is not null and r.min_entry_score = (v_f->>'min_value')::numeric, 'quote_contains', position(lower(left(v_q, 40)) in lower(r.quote)) > 0)), '[]'::jsonb)
                  from catalogue.course_entry_requirements r where r.course_id = i.course_id and r.status = 'active');
      v_status := 'compared'; v_reason := format('COMPARED: the course has %s active entry row(s); replacing or adding to them is a person''s decision', v_act);
      v_ver := v_ver || jsonb_build_object('comparison', v_cmp);
    elsif exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.course_id and l.field in ('entry_requirements', 'all')) then
      v_status := 'held'; v_reason := 'HELD:MANUAL_LOCK';
    elsif exists (select 1 from catalogue.course_entry_requirements r where r.course_id = i.course_id and r.status = 'proposed')
       or exists (select 1 from pipeline.layer4_review_items o where o.entity_id = i.course_id and o.field_code = 'course_entry_first_read' and o.status = 'pending') then
      v_status := 'held'; v_reason := 'HELD:READ_WAITING: another entry read of this course is waiting in Layer 4';
    elsif exists (select 1 from pipeline.layer4_review_items o where o.entity_id = i.course_id and o.field_code = 'course_entry_first_read'
                    and o.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')) then
      v_status := 'held'; v_reason := 'HELD:PERSON_DECISION: a person rejected or returned an earlier entry read of this course';
    else
      v_q := v_req->>'quote';
      v_kind := case when coalesce(v_f->>'qualification_code', '') <> '' or v_f->>'basis' ~* 'degree|qualification|award' then 'prior_qualification' else 'minimum_grade' end;
      v_score := null; v_basis := null;
      if (v_f->>'min_value') ~ '^\d+(\.\d+)?$' then
        v_basis := case when lower(coalesce(v_f->>'scale', '')) like '%point%' then 'points' when lower(coalesce(v_f->>'scale', '')) ~ 'perc|%' then case when lower(v_q) like '%per cent%' then 'per cent' else '%' end
                        when lower(coalesce(v_f->>'scale', '')) like '%gpa%' then 'GPA' when lower(coalesce(v_f->>'scale', '')) like '%atar%' then 'ATAR' else null end;
        -- the number and its scale word are printed in the quote (B1 rule, as the deterministic reader)
        if v_basis is not null and strpos(lower(regexp_replace(v_q, '\s+', ' ', 'g')), lower(v_basis)) > 0
           and exists (select 1 from regexp_matches(v_q, '([0-9]+(\.[0-9]+)?)', 'g') m where m[1]::numeric = (v_f->>'min_value')::numeric) then
          v_score := (v_f->>'min_value')::numeric;
        else v_basis := null; end if;
      end if;
      if (v_f->>'min_value') is not null and v_score is null then
        v_status := 'held'; v_reason := 'HELD:VALUE_NOT_IN_QUOTE: the stated value and its scale are not both printed in the requirement quote';
      else
        v_desc := case when v_f->>'qualification_code' = 'IB_DP' and v_score is not null then 'International Baccalaureate Diploma with ' || trim(to_char(v_score, 'FM999990.##')) || ' points'
                       when coalesce(v_f->>'minimum', '') <> '' then left(v_f->>'minimum', 300)
                       else left(v_q, 300) end;
        if v_f->>'qualification_code' = 'IB_DP' and v_q !~* '(international baccalaureate|\mIB\M)' then v_status := 'held'; v_reason := 'HELD:QUALIFICATION_NOT_IN_QUOTE';
        else
          v_aud := case when v_q ~* '\m(international|overseas)\M' then 'international'
                        when v_q ~* '(\mVCE\M|\mATAR\M|\mVTAC\M|\mSTAT\M|Australian Year 12)' then 'domestic' else 'all' end;
          select e.source_url, e.captured_at::date into v_srcurl, v_cap from pipeline.evidence_artifacts e where e.id = v_req_ev;
          insert into catalogue.course_entry_requirements(course_id, kind, audience, description, min_grade, min_entry_score, min_entry_score_basis, quote, source_url, evidence_id, confidence, as_at, status, provenance)
          values (i.course_id, v_kind, v_aud, v_desc, null, v_score, v_basis, left(v_q, 300), coalesce(v_srcurl, g.url), v_req_ev, v_conf, coalesce(v_cap, current_date), 'proposed',
                  jsonb_build_object('reader', 'structured_intake', 'submitter', i.submitter, 'intake_item_id', i.id, 'verifier', p_result->>'verifier', 'field', 'entry_requirements'))
          returning id into v_row;
          insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
          values ('course', i.course_id, 'course_entry_first_read', v_req_ev, jsonb_build_object('active_rows', 0),
                  jsonb_build_object('reader', 'structured_intake', 'submitter', i.submitter, 'intake_item_id', i.id, 'url', g.url, 'rows', 1, 'notes', '[]'::jsonb,
                    -- the other routes printed on the page were not supplied: a partial submission is never the whole read
                    'dropped', case when coalesce((v_f->>'complete')::boolean, false) then '[]'::jsonb
                                    else jsonb_build_array(jsonb_build_object('reason', 'det_other_requirement', 'kind', 'other',
                                           'quote', left('Other entry requirements printed on this page were not supplied by the structured intake (' || i.submitter || ')', 300))) end,
                    'sample', jsonb_build_array(jsonb_build_object('id', v_row, 'kind', v_kind, 'audience', v_aud, 'description', v_desc, 'min_entry_score', v_score, 'min_entry_score_basis', v_basis, 'quote', left(v_q, 300)))),
                  jsonb_build_object('source', 'structured intake (' || i.submitter || ', ' || i.batch_ref || ')', 'page', g.url, 'identity_basis', g.identity_basis),
                  jsonb_build_object('reader', 'structured_intake', 'verifier', p_result->>'verifier'),
                  'pending', 'Course entry row submitted by ' || i.submitter || ' and proved on the stored page: the machine rules admit it when every check passes, otherwise a person decides', 'CF-CHG-20260915-247')
          returning id into v_rev;
          update catalogue.course_entry_requirements set provenance = provenance || jsonb_build_object('review_item_id', v_rev) where id = v_row;
          v_status := 'proposed'; v_reason := 'PROPOSED: one proposed row and Layer 4 item; the machine rules decide';
        end if;
      end if;
    end if;
  end if;
  update pipeline.structured_intake_items set status = v_status, status_reason = left(v_reason, 1000), verification = v_ver, evidence_ids = coalesce(v_ev, '{}'),
         review_item_id = coalesce(v_rev, review_item_id), row_ids = case when v_row is null then row_ids else row_ids || v_row end, leased_at = null, updated_at = now()
   where id = i.id;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('structured_intake', 'decided', 'pipeline.structured_intake_items',
          jsonb_build_object('item_id', i.id, 'status', v_status, 'reason', left(v_reason, 300), 'review_item_id', v_rev, 'row_id', v_row, 'change', 's1321', 'by', 'coverage-sweep', 'actor_kind', 'machine'), security.system_actor_id());
  return jsonb_build_object('item_id', i.id, 'status', v_status, 'reason', v_reason, 'review_item_id', v_rev, 'row_id', v_row);
end $f$;
comment on function security.structured_intake_record_v1(uuid, jsonb) is 'CF-247 s1321: records the worker''s quote proofs for a leased structured candidate and decides it: an academic entry candidate proved on the course''s bound page (course code printed, value and scale in the quote) becomes one proposed course entry row with a Layer 4 course_entry_first_read item for the existing machine rules; a course with active rows is compared; a lock, a waiting read or a person''s earlier decision holds it; a quote not on the stored copy rejects it. Scholarship candidates are proved and held with their reasons.';
revoke all on function security.structured_intake_record_v1(uuid, jsonb) from public, anon, authenticated;

-- 4. the service entry point (operations workflow and worker)
create or replace function public.svc_structured_intake_v1(p_action text, p_args jsonb default '{}'::jsonb, p_by text default null) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare v_out jsonb; v_req bigint; v_ev uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_action = 'submit' then
    v_out := security.structured_intake_submit_v1(p_args->>'submitter', p_args->>'batch', p_args->'items', p_by);
    if (v_out->>'received')::int > 0 and security.pipeline_num_v1('structured_intake.on', 1) >= 1 then
      v_req := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'intake_verify'));
      v_out := v_out || jsonb_build_object('worker_request', v_req);
    end if;
    return v_out;
  elsif p_action = 'verify' then
    if not exists (select 1 from pipeline.structured_intake_items where status = 'received' or (status = 'verifying' and leased_at < now() - interval '15 minutes')) then  -- fixed: claim timer
      return jsonb_build_object('worker_request', null, 'note', 'nothing to verify');
    end if;
    return jsonb_build_object('worker_request', pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'intake_verify')));
  elsif p_action = 'next' then return security.structured_intake_next_v1();
  elsif p_action = 'store' then
    -- a proof page read once by the worker (no stored copy inside the freshness period): registered as ordinary evidence, so it is reused
    if not exists (select 1 from pipeline.structured_intake_items i where i.id = (p_args->>'item_id')::uuid and i.status = 'verifying'
                     and exists (select 1 from jsonb_array_elements(i.candidate->'proof') q where q->>'final_url' = p_args->>'url')) then
      raise exception 'INVALID_INPUT: the address is not a proof of a leased intake item';
    end if;
    if coalesce(p_args->>'sha256', '') !~ '^[0-9a-f]{64}$' or coalesce(p_args->>'storage_path', '') !~ '^layer2/intake/[0-9a-f-]{36}/[0-9a-f]{64}\.html\.gz$' then
      raise exception 'INVALID_INPUT: stored copy';
    end if;
    select e.id into v_ev from pipeline.evidence_artifacts e where e.source_url = p_args->>'url' and e.content_hash = p_args->>'sha256' and e.storage_path = p_args->>'storage_path' limit 1;
    if v_ev is null then
      insert into pipeline.evidence_artifacts (evidence_type, source_url, storage_path, content_hash, mime_type, captured_at, metadata)
      values ('source_snapshot', p_args->>'url', p_args->>'storage_path', p_args->>'sha256', coalesce(p_args->>'mime', 'text/html'), now(),
              jsonb_build_object('kind', 'structured_intake_proof', 'read_via', 'direct', 'worker', p_by, 'http', p_args->'http', 'final_url', p_args->>'final_url',
                                 'intake_item_id', p_args->>'item_id', 'change', 's1321'))
      returning id into v_ev;
    end if;
    return jsonb_build_object('evidence_id', v_ev);
  elsif p_action = 'record' then return security.structured_intake_record_v1((p_args->>'item_id')::uuid, p_args);
  elsif p_action = 'list' then
    return jsonb_build_object('items', (select coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'submitter', i.submitter, 'batch', i.batch_ref, 'key', i.candidate_key,
              'domain', i.domain, 'course_id', i.course_id, 'course_code', i.candidate->>'course_code', 'status', i.status, 'reason', i.status_reason,
              'review_item_id', i.review_item_id, 'review_status', (select r.status from pipeline.layer4_review_items r where r.id = i.review_item_id),
              'rows', (select coalesce(jsonb_agg(jsonb_build_object('row_id', x.id, 'status', x.status, 'description', x.description) order by x.id), '[]'::jsonb)
                         from catalogue.course_entry_requirements x where x.id = any (i.row_ids)),
              'machine', (select jsonb_build_object('outcome', m.outcome, 'rule', m.rule, 'reason_code', m.reason_code, 'at', m.created_at) from pipeline.aer_machine_admissions m
                           where m.review_item_id = i.review_item_id order by m.created_at desc limit 1),
              'verification', i.verification->'not_proved', 'comparison', i.verification->'comparison', 'updated_at', i.updated_at) order by i.created_at), '[]'::jsonb)
             from pipeline.structured_intake_items i
            where (p_args->>'submitter' is null or i.submitter = p_args->>'submitter') and (p_args->>'batch' is null or i.batch_ref = p_args->>'batch')));
  end if;
  raise exception 'INVALID_INPUT: action is submit, verify, next, store, record or list';
end $f$;
comment on function public.svc_structured_intake_v1(text, jsonb, text) is 'CF-247 s1321: service entry point of the structured intake (submit, verify, next, store, record, list); submit and verify start the coverage-sweep worker mode intake_verify once.';
revoke all on function public.svc_structured_intake_v1(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_structured_intake_v1(text, jsonb, text) to service_role;


do $post$
declare v jsonb := security.consumer_api_check_v1(); b record;
begin
  select * into b from pg_temp.s1321_guard;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from cron.job where active) <> b.cron_before then raise exception 'post-check: active job count changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) <> b.decided_before then raise exception 'post-check: a Layer 4 item was decided'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('structured_intake.on', 'structured_intake.verify_batch', 'structured_intake.confidence_verified', 'structured_intake.max_items_per_submit', 'structured_intake.max_proofs', 'structured_intake.fetch_on')) <> 6 then
    raise exception 'post-check: intake settings missing';
  end if;
end $post$;
