-- CF-247 s840 to s842 (session S1-ELR, Platform Admin 20 Nov 2026 15:10 and 15:21 AEDT; lane block s840 to s849, migrations 20261120150000 to 20261120152900):
-- English language requirements (ELR) only: the admission-rule-runner-b statement time-outs, a $0 deterministic English requirement reader over the stored course pages,
-- automatic promotion of fully verified readings through the existing gates, and a scheduled sweep that drains the source-backed gaps. Academic entry (AER) is not touched.
--
-- Found live (rolled-back probes, 20 Nov 2026 15:12 to 15:40 AEDT; head 20261120143000, 2,219 history rows; G3 75/48; manual locks 7,585):
--   36,031 active AU, NZ and CA courses; 20,836 hold an active English requirement; 6,215 lack one and have a stored course page bound (6,151 read), 8,980 have no stored page.
--   admission-rule-runner-b (call security.admission_rule_tick_v1('b')) failed twice in 24 hours with "canceling statement due to statement timeout", CONTEXT SQL function
--   english_group_match_v1, inside security.provider_english_plan_v1. Cause: the plan asks security.english_group_match_v1 once for every course of the provider (grp_hits) and
--   again for every course x every other approved policy of the provider (other_group). The function cannot be inlined (it carries SET search_path) and none of the 180 approved
--   English policies has a course-group binding, so every one of those calls answers [] at full cost: 260 to 809 ms a plan for the six largest providers, and over the limit
--   when the database is busy.
--
-- What changes:
--   (s840) security.provider_english_plan_v1: the two calls are asked only when the policy, or another approved policy of the provider, has group bindings (read once, at the
--          top). The answer is the same for every course (english_group_match_v1 answers [] without bindings); the post-check compares the plans of the largest providers before and
--          after, row for row. The live text is checked by md5 before it is replaced.
--   (s841) the reader elr-det-v1.0 (supabase/functions/coverage-sweep/elr-det-reader.ts, worker mode elr_det_read, read only, no model, no Firecrawl): IELTS overall and bands,
--          TOEFL iBT total and sections, PTE Academic overall and skills (decimals kept), OET grades or scores, CELPIP levels, Cambridge C1 Advanced and C2 Proficiency, by acronym
--          or spelled-out name; flattened table lines of several programmes are skipped, never cross-assigned.
--   (s842) one writer, security.elr_det_record_v1, records every page read and its readings, and promotes a course's readings into catalogue.course_english_requirements (then
--          search.course_documents through search.refresh_course_enrichment_scoped_v1) only when every gate passes: the page is still the course's bound, read page with an identity
--          the country accepts for English (security.coverage_identity_allowed) and is not refused; the course is active, in an admission country and not held by Layer 4; it holds no
--          active English requirement (no-overwrite: insert only, on conflict nothing), no manual lock and no pending English review; the page is not shared by several courses;
--          every reading of a test agrees, states a minimum, and its value is in its own verbatim quote; and the course is not in the audit sample. A conflict, a shared page or
--          the audit sample goes to Layer 4 (field course_english, the existing approve path); anything else stays recorded with its reason. The job elr-det-sweep (every 5 minutes)
--          reads the answers of its earlier calls back from pg_net, records them, and sends the next indexed batch of unread gap pages to the worker.
-- Objects (no new public function, table or view; G3 stays 75/48): tables pipeline.elr_det_pages, pipeline.elr_det_readings, pipeline.elr_det_requests, pipeline.elr_det_state;
--   functions security.elr_det_claim_v1(int), security.elr_det_record_v1(jsonb,text), security.elr_det_sweep_tick_v1(), security.elr_det_status_v1(); one job elr-det-sweep;
--   settings batch.elr_det_sweep, elr_det.pages_per_call, elr_det.in_flight_max, elr_det.audit_pct, elr_det.promote_on, elr_det.sweep_on, elr_det.request_lost_minutes.
-- G1: the job is in pipeline.automation_catalogue and the component register. G2: every size and limit is a setting; the job command holds no number.
-- Parity: head 20261120143000 (2,219 rows) read live 20 Nov 2026 15:12 AEDT; written in the S1-ELR slot (20261120150000), renumbered 20261120170000 to stay strictly
--   above the live head (20261120163000, S1-AER) and the open lanes' files (163500 S1-Structure-Outcomes, 165000 and 165100 S1-Fees-Intakes, 145000 S1-UI-Parity).
-- Replaces: the per-course and per-course-per-policy english_group_match_v1 calls of provider_english_plan_v1 when no binding exists (the call stays for policies that have one).
-- Retires: nothing. Nothing dropped, deleted or renamed. Spend: none (no model, no Firecrawl).
-- Rollback: setting elr_det.sweep_on 0 stops the sweep; elr_det.promote_on 0 records without promoting; a promoted row carries source_requirement_key 'elr-det:<test>' and can be
--   withdrawn by a paste file; the plan function can be put back from its md5-checked text in this file's history.
set local lock_timeout = '5s';
set local statement_timeout = '240s';  -- fixed: the post-check runs the largest providers' English plans twice (before and after) to compare them

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.provider_english_plan_v1(uuid)'::regprocedure)) <> '6fec9e6515a347438b7ed07215cbd748' then
    raise exception 'guard: security.provider_english_plan_v1 is not the text this change was written against (md5 %)', md5(pg_get_functiondef('security.provider_english_plan_v1(uuid)'::regprocedure));
  end if;
end $g$;

create temp table s840_locks on commit drop as select count(*) n from pipeline.manual_locks;

-- the plans of the largest providers before the change, kept for the post-check comparison (with the time each took)
create temp table s840_plan_before (proposal_id uuid, h text, n int, ms numeric) on commit drop;
do $b$
declare r record; t0 timestamptz; v_h text; v_n int;
begin
  for r in select o2.id from pipeline.provider_policy_proposals o2 where o2.kind = 'english_policy' and o2.status = 'approved'
            order by (select count(*) from catalogue.courses c where c.provider_id = o2.provider_id and c.lifecycle_status = 'active') desc, o2.id limit 8 loop
    t0 := clock_timestamp();
    select md5(coalesce(string_agg(t::text, '|' order by t.course_id), '')), count(*) into v_h, v_n from security.provider_english_plan_v1(r.id) t;
    insert into s840_plan_before values (r.id, v_h, v_n, extract(epoch from clock_timestamp() - t0) * 1000);
  end loop;
end $b$;

-- (s840) the plan function, live text with the two guarded calls
CREATE OR REPLACE FUNCTION security.provider_english_plan_v1(p_proposal_id uuid)
 RETURNS TABLE(course_id uuid, title text, study_level text, plan text, reason text, requirements jsonb, existing jsonb, outcome text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security'
AS $function$
declare x pipeline.provider_policy_proposals%rowtype; v_named jsonb; v_defaults jsonb; v_has_bindings boolean; v_other_bindings boolean;
        -- CF-247 ENG 8 Nov 2026: english.default_after_withdrawn_reading (off = a withdrawn row of any kind counts as a reading, as before)
        v_wd_off boolean := security.pipeline_num_v1('english.default_after_withdrawn_reading', 0) < 1;
begin
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id;
  if x.id is null or x.kind <> 'english_policy' then raise exception 'not an English policy proposal'; end if;
  v_defaults := coalesce(x.proposal->'defaults', '{}'::jsonb);
  -- s840: whether this policy, or another approved English policy of the same provider, has any course-group binding (security.english_group_match_v1 answers [] without one)
  v_has_bindings := jsonb_typeof(x.proposal->'group_bindings') = 'array' and jsonb_array_length(x.proposal->'group_bindings') > 0;
  v_other_bindings := exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = x.provider_id and o.kind = 'english_policy' and o.status = 'approved' and o.id <> x.id
                               and jsonb_typeof(o.proposal->'group_bindings') = 'array' and jsonb_array_length(o.proposal->'group_bindings') > 0);
  select coalesce(jsonb_agg(jsonb_build_object('k', s.k, 'reqs', s.reqs)), '[]'::jsonb) into v_named from (
    select security.english_title_key(n) k, null::jsonb reqs from jsonb_array_elements_text(coalesce(x.proposal->'named', '[]'::jsonb)) n
    union all
    select security.english_title_key(e->>'name'), case when jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0
                                                       then (select jsonb_agg(q - 'quote') from jsonb_array_elements(e->'reqs') q) end
      from jsonb_array_elements(coalesce(x.proposal->'exceptions', '[]'::jsonb)) e) s where length(s.k) >= 4;
  return query
  with named as materialized (
    select e->>'k' k, nullif(e->'reqs', 'null'::jsonb) reqs,
           array(select distinct t from unnest(regexp_split_to_array(e->>'k', '[ /]+')) t where t not in ('of', 'and', 'in', 'the', '')) toks
      from jsonb_array_elements(v_named) e),
  c0 as materialized (
    -- s840: the title key is security.english_title_key written out in place (the function carries SET search_path, so each of the provider's course rows paid a
    -- configuration switch for it); the post-check proves the two agree for every active course of the largest providers
    select co.id, co.canonical_title t,
           btrim(regexp_replace(regexp_replace(regexp_replace(
             replace(regexp_replace(lower(coalesce(co.canonical_title,'')),'\(\s*\d+\s+units(\s+and\s+\d+\s+units)?\s*\)','','g'),'&',' and '),
             '[^a-z0-9/]+',' ','g'),' ?/ ?','/','g'),'\s+',' ','g')) k,
           sl.code lvl, ff.path field_path
      from catalogue.courses co left join ref.study_levels sl on sl.id = co.study_level_id left join ref.fields_of_study ff on ff.id = co.primary_field_id
     where co.provider_id = x.provider_id and co.lifecycle_status = 'active'),
  c as materialized (
    select c0.*, array(select distinct t from unnest(regexp_split_to_array(c0.k, '[ /]+')) t where t not in ('of', 'and', 'in', 'the', '')) toks,
           case when c0.lvl in ('bachelor', 'bachelor_honours', 'associate_degree') then 'undergraduate'
                when c0.lvl in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate'
                when c0.lvl in ('doctorate', 'masters_research') then 'research' end grp,  -- CF-247 15 Oct: research degrees take the policy's research default
           (select coalesce(jsonb_object_agg(et.code, r.overall_score), '{}'::jsonb) from catalogue.course_english_requirements r
              join ref.english_tests et on et.id = r.english_test_id where r.course_id = c0.id and r.status = 'active') ex,
           exists (select 1 from catalogue.course_english_requirements r where r.course_id = c0.id
                    and (v_wd_off or r.status = 'active' or coalesce(r.source_requirement_key, '') like 'policy:%')) any_row,
           -- the scores of withdrawn readings the course page gave (a policy's own withdrawn rows are not here: they keep blocking)
           case when v_wd_off then '{}'::jsonb else (select coalesce(jsonb_object_agg(et.code, r.overall_score), '{}'::jsonb) from catalogue.course_english_requirements r
              join ref.english_tests et on et.id = r.english_test_id
             where r.course_id = c0.id and r.status = 'withdrawn' and coalesce(r.source_requirement_key, '') not like 'policy:%') end wd_ex,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c0.id and l.field in ('english', 'english_requirements', 'course_english')) locked,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = c0.id and i.field_code = 'course_english' and i.status = 'pending') in_review,
           false in_l3,  -- CF-247 15 Oct 2026 (usage audit D6): Layer 3 is retired, so no course waits for it
           exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c0.id and g.status in ('bound', 'ambiguous')
                      and (g.read_status is null or g.read_status = 'needs_render')) page_waiting
      from c0),
  m as (
    select c.*,
           (select jsonb_agg(distinct named.reqs) from named where named.k = c.k and named.reqs is not null) exact_reqs,
           exists (select 1 from named where named.k = c.k) exact_named,
           exists (select 1 from named where named.k <> c.k and (position(named.k in c.k) > 0 or position(c.k in named.k) > 0
                     or (cardinality(c.toks) > 0 and cardinality(named.toks) > 0
                         and (select count(*) from unnest(c.toks) t where t = any(named.toks))::numeric / greatest(cardinality(c.toks), cardinality(named.toks)) >= 0.75))) close_named,
           case when c.grp is not null then v_defaults->c.grp end dflt,
           -- CF-247 6 Nov 2026: the course groups of this policy that a person has bound to this course (undergraduate and postgraduate courses only)
           -- s840 (20 Nov 2026): the match is asked only when this policy has course-group bindings (none of the 180 approved policies had any; every call answered [] at a cost)
           case when c.grp in ('undergraduate', 'postgraduate') and v_has_bindings then security.english_group_match_v1(x.proposal, c.t, c.field_path, c.grp) else '[]'::jsonb end grp_hits
      from c),
  m2 as (
    select m.*, g.n grp_n, g.name grp_name,
           -- another approved policy of this provider names this course with its own scores: that is more specific than a group
           (g.n = 1 and exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = x.provider_id and o.kind = 'english_policy' and o.status = 'approved' and o.id <> x.id
              and exists (select 1 from jsonb_array_elements(coalesce(o.proposal->'exceptions', '[]'::jsonb)) e where jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0 and security.english_title_key(e->>'name') = m.k))) named_elsewhere,
           -- another approved policy of this provider has a bound course group for this course: it takes the course, so this policy's level default does not
           -- s840: only the other policies that have course-group bindings are asked (bindings_other, read once), so a provider without bindings costs nothing here
           (case when v_other_bindings and m.grp in ('undergraduate', 'postgraduate') then exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = x.provider_id and o.kind = 'english_policy' and o.status = 'approved' and o.id <> x.id
              and jsonb_typeof(o.proposal->'group_bindings') = 'array' and jsonb_array_length(o.proposal->'group_bindings') > 0
              and jsonb_array_length(security.english_group_match_v1(o.proposal, m.t, m.field_path, m.grp)) > 0) else false end) other_group
      from m cross join lateral (select count(distinct h->'reqs')::int n, min(h->>'group_name') name from jsonb_array_elements(m.grp_hits) h) g),
  p as (
    select m.*,
           case when m.lvl is null then 'held|study level unknown'
                when m.lvl in ('doctorate', 'masters_research') and jsonb_typeof(v_defaults->'research') is distinct from 'array' then 'held|research degree (the policy states no research requirement)'
                when m.t ~* 'exit award' then 'held|exit award only'
                when (m.k ~ '/' or m.k ~ ' and (bachelor|master|doctor|graduate|diploma|associate) (of|in) ') and not security.double_degree_same_group_v1(m.t, m.grp) then 'held|double degree (its parts are at different levels)'
                when m.exact_reqs is not null and jsonb_array_length(m.exact_reqs) > 1 then 'held|the policy gives this course more than one requirement'
                when m.exact_reqs is not null then 'named|'
                when m.exact_named or m.close_named then 'held|named in the policy (it may have its own requirement)'
                when m.grp_n > 1 then 'held|more than one course group applies to this course'
                when m.grp_n = 1 and m.named_elsewhere then 'held|another approved policy of this university names this course'
                when m.grp_n = 1 then 'group|course group: ' || m.grp_name
                when m.grp is null then 'held|level not covered by the policy default'
                when m.dflt is null or jsonb_typeof(m.dflt) <> 'array' then 'held|the policy gives no default for this level'
                when m.other_group then 'held|a course group of another approved policy of this university applies'
                else 'default|' end pr
      from m2 m),
  q as (
    select p.*, split_part(p.pr, '|', 1) pl, nullif(split_part(p.pr, '|', 2), '') rs,
           case when p.pr like 'named|%' then p.exact_reqs->0 when p.pr like 'default|%' then p.dflt
                when p.pr like 'group|%' then (select jsonb_agg(r - 'quote') from jsonb_array_elements(p.grp_hits->0->'reqs') r) end reqs
      from p)
  select q.id, q.t, q.lvl, q.pl, q.rs, q.reqs, q.ex,
         case when q.pl = 'held' then 'held'
              when q.any_row and exists (select 1 from jsonb_array_elements(q.reqs) r where q.ex ? (r->>'test_code') and (q.ex->>(r->>'test_code'))::numeric <> (r->>'overall_score')::numeric) then 'differs'
              when q.any_row and exists (select 1 from jsonb_array_elements(q.reqs) r where q.ex ? (r->>'test_code')) then 'agrees'
              when q.any_row then 'other_value'
              when exists (select 1 from jsonb_array_elements(q.reqs) r where q.wd_ex ? (r->>'test_code') and (q.wd_ex->>(r->>'test_code'))::numeric <> (r->>'overall_score')::numeric) then 'differs'
              when q.locked then 'set_by_hand'
              when q.in_review then 'in_review'
              when q.in_l3 or q.page_waiting then 'waiting'
              else 'write' end
    from q;
end $function$
;

-- (s842) the working tables
create table if not exists pipeline.elr_det_state (
  id          integer primary key default 1 check (id = 1),
  cursor_id   uuid not null default '00000000-0000-0000-0000-000000000000',
  passes      integer not null default 0,
  updated_at  timestamptz not null default now()
);
comment on table pipeline.elr_det_state is 'CF-247 s842: where the English requirement sweep (job elr-det-sweep) is in its keyset pass over the gap course pages (one row), and how many passes it has completed.';
alter table pipeline.elr_det_state enable row level security;
revoke all on pipeline.elr_det_state from public, anon, authenticated;
insert into pipeline.elr_det_state (id) values (1) on conflict do nothing;

create table if not exists pipeline.elr_det_pages (
  course_id   uuid not null references catalogue.courses(id) on delete cascade,
  evidence_id uuid not null,
  extractor   text not null,
  outcome     text not null default 'sent' check (outcome in ('sent', 'read', 'lost', 'failed')),
  chars       integer,
  sha256      text,
  readings    integer not null default 0,
  result      text,
  request_id  bigint,
  sent_at     timestamptz not null default now(),
  read_at     timestamptz,
  primary key (course_id, evidence_id, extractor)
);
comment on table pipeline.elr_det_pages is 'CF-247 s842: each stored course page the deterministic English requirement reader (elr-det) was sent or has read, by extractor version, with what came of it (promoted, review, held and why). Lets the sweep resume and never read a page twice.';
create index if not exists elr_det_pages_request on pipeline.elr_det_pages (request_id) where outcome = 'sent';
alter table pipeline.elr_det_pages enable row level security;
revoke all on pipeline.elr_det_pages from public, anon, authenticated;

create table if not exists pipeline.elr_det_readings (
  id          bigint generated always as identity primary key,
  course_id   uuid not null references catalogue.courses(id) on delete cascade,
  evidence_id uuid not null,
  extractor   text not null,
  test_key    text not null check (test_key in ('ielts', 'toefl_ibt', 'pte', 'oet', 'celpip', 'cambridge')),
  value       jsonb not null,
  quote       text not null check (length(quote) between 8 and 400),
  strength    text not null check (strength in ('stated_minimum', 'mentioned')),
  flags       text[] not null default '{}',
  status      text not null default 'recorded' check (status in ('recorded', 'promoted', 'review', 'held')),
  reason      text,
  created_at  timestamptz not null default now()
);
comment on table pipeline.elr_det_readings is 'CF-247 s842: English test readings taken deterministically from a stored course page (elr-det), each with its verbatim quote, and the gate''s outcome: promoted into catalogue.course_english_requirements, sent to Layer 4 (review), or held with a reason.';
create unique index if not exists elr_det_readings_one on pipeline.elr_det_readings (course_id, evidence_id, extractor, test_key, md5(quote));
create index if not exists elr_det_readings_course on pipeline.elr_det_readings (course_id);
create index if not exists elr_det_readings_status on pipeline.elr_det_readings (status, test_key);
alter table pipeline.elr_det_readings enable row level security;
revoke all on pipeline.elr_det_readings from public, anon, authenticated;

create table if not exists pipeline.elr_det_requests (
  id           bigint primary key,
  pages        integer not null,
  status       text not null default 'sent' check (status in ('sent', 'done', 'lost', 'failed')),
  submitted_at timestamptz not null default now(),
  finished_at  timestamptz,
  result       jsonb
);
comment on table pipeline.elr_det_requests is 'CF-247 s842: each call the English requirement sweep made to the coverage-sweep worker (mode elr_det_read), by its pg_net request id; the sweep reads the answer back and records it.';
create index if not exists elr_det_requests_open on pipeline.elr_det_requests (submitted_at) where status = 'sent';
alter table pipeline.elr_det_requests enable row level security;
revoke all on pipeline.elr_det_requests from public, anon, authenticated;

-- (G2) settings
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'batch.elr_det_sweep', 'English requirement sweep: pages a run',
  'Stored course pages of courses with no English requirement that the job elr-det-sweep sends to the deterministic English reader in one run (split into calls of the next setting). No AI or Firecrawl spend.',
  'number', to_jsonb(200), 25, 250, 'pages', 650, 'Admission checks', 'job elr-det-sweep; security.elr_det_sweep_tick_v1', 'CF-247 s842 (Platform Admin 20 Nov 2026 15:10): indexed batches of 100 to 250 courses'),
 ('pipeline', 'elr_det.pages_per_call', 'English requirement sweep: pages a worker call',
  'Pages sent to the coverage-sweep worker (mode elr_det_read) in one call.', 'number', to_jsonb(25), 5, 40, 'pages', 651, 'Admission checks', 'security.elr_det_sweep_tick_v1', 'CF-247 s842: bounded concurrency'),
 ('pipeline', 'elr_det.in_flight_max', 'English requirement sweep: calls waiting at once',
  'The sweep sends no new pages while this many of its worker calls are still unanswered.', 'number', to_jsonb(8), 1, 12, 'calls', 652, 'Admission checks', 'security.elr_det_sweep_tick_v1', 'CF-247 s842: bounded concurrency'),
 ('pipeline', 'elr_det.audit_pct', 'English requirement sweep: audit sample',
  'Share of courses whose fully verified English readings go to Layer 4 for a person to check instead of being promoted automatically.', 'number', to_jsonb(5), 0, 50, '%', 653, 'Admission checks', 'security.elr_det_record_v1', 'CF-247 s842: audit-sampled rows enter Layer 4'),
 ('pipeline', 'elr_det.promote_on', 'English requirement sweep: promote verified readings',
  '1: readings that pass every gate are written to the course''s English requirements. 0: they are recorded only.', 'number', to_jsonb(1), 0, 1, 'switch', 654, 'Admission checks', 'security.elr_det_record_v1', 'CF-247 s842 (Platform Admin 20 Nov 2026 15:10): automated deterministic promotion'),
 ('pipeline', 'elr_det.sweep_on', 'English requirement sweep: on',
  '1: the job elr-det-sweep runs. 0: it does nothing (already sent calls are still read back).', 'number', to_jsonb(1), 0, 1, 'switch', 655, 'Admission checks', 'security.elr_det_sweep_tick_v1', 'CF-247 s842'),
 ('pipeline', 'elr_det.request_lost_minutes', 'English requirement sweep: unanswered call given up after',
  'A worker call with no answer after this many minutes is given up; its pages are sent again in a later run.', 'number', to_jsonb(30), 10, 360, 'minutes', 656, 'Admission checks', 'security.elr_det_sweep_tick_v1', 'CF-247 s842')
on conflict do nothing;

-- (s842) the indexed claim: the next unread, bound and read stored pages of active courses in an admission country that hold no active English requirement, by course id after p_after
create or replace function security.elr_det_claim_v1(p_after uuid, p_limit integer) returns table (course_id uuid, evidence_id uuid, storage_path text)
language sql stable security definer set search_path to ''
as $f$
  select g.course_id, g.evidence_id, e.storage_path
    from pipeline.coverage_course_pages g
    join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
    join catalogue.courses c on c.id = g.course_id and c.lifecycle_status = 'active'
    join catalogue.providers p on p.id = c.provider_id
    join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
   where g.course_id > p_after and g.status = 'bound' and g.read_status = 'read' and g.evidence_id is not null
     and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = g.course_id and r.status = 'active')
     and not exists (select 1 from pipeline.elr_det_pages d where d.course_id = g.course_id and d.evidence_id = g.evidence_id and d.extractor = 'elr-det-v1.0' and d.outcome <> 'lost')
   order by g.course_id limit greatest(p_limit, 0)
$f$;
comment on function security.elr_det_claim_v1(uuid, integer) is 'CF-247 s842: the next gap course pages for the English requirement reader, in course id order after the sweep''s cursor (primary key of coverage_course_pages). Read by security.elr_det_sweep_tick_v1. Reads only.';
revoke all on function security.elr_det_claim_v1(uuid, integer) from public, anon, authenticated;

-- (s842) the value-in-quote check: the quote names the test, and every number or grade the reading carries is printed in it
create or replace function security.elr_det_quote_ok_v1(p_key text, p_value jsonb, p_quote text) returns boolean
language sql immutable set search_path to ''
as $f$
  with nums as (
    select v from (select p_value->>'overall' v union all select x.value from jsonb_each_text(case when jsonb_typeof(p_value->'components') = 'object' then p_value->'components' else '{}'::jsonb end) x) z
     where v is not null)
  select p_quote ~* case p_key
            when 'ielts' then '\mIELTS\M|International English Language Testing System'
            when 'toefl_ibt' then '\mTOEFL\M|Test of English as a Foreign Language'
            when 'pte' then '\mPTE\M|Pearson Test of English|Pearson English'
            when 'oet' then '\mOET\M|Occupational English Test'
            when 'celpip' then '\mCELPIP\M|Canadian English Language Proficiency'
            when 'cambridge' then 'Cambridge|C1 Advanced|C2 Proficiency|\mCAE\M|\mCPE\M|Certificate (in Advanced|of Proficiency in) English'
            else '^\b$' end
     and not exists (select 1 from nums where p_quote !~ ('(^|[^0-9.])' || replace(trim_scale(nums.v::numeric)::text, '.', '\.') || '(\.0+)?($|[^0-9])'))
     and (p_value->>'grade' is null or p_quote ~ ('(^|[^A-Za-z])' || replace(p_value->>'grade', '+', '\+') || '($|[^A-Za-z+])'))
$f$;
comment on function security.elr_det_quote_ok_v1(text, jsonb, text) is 'CF-247 s842: true when an English test reading''s verbatim quote names its test and prints every score and grade the reading carries. Pure.';
revoke all on function security.elr_det_quote_ok_v1(text, jsonb, text) from public, anon, authenticated;

-- (s842) the one writer: records the pages and readings, then promotes, reviews or holds each course by the gates
create or replace function security.elr_det_record_v1(p_pages jsonb, p_run text default null) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_x constant text := 'elr-det-v1.0';
  p jsonb; r jsonb; t record; g record;
  v_course uuid; v_ev uuid; v_n int; v_reason text; v_review text; v_test uuid; v_wrote int;
  v_audit int := security.pipeline_num_v1('elr_det.audit_pct', 5)::int;
  v_promote boolean := security.pipeline_num_v1('elr_det.promote_on', 1) >= 1;
  v_pages int := 0; v_readings int := 0; v_promoted_courses int := 0; v_rows int := 0; v_review_n int := 0; v_held int := 0; v_failed int := 0;
  v_ok jsonb; v_conf jsonb; v_done uuid[] := '{}'; v_search text := 'none';
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_pages) <> 'array' then raise exception 'p_pages must be an array'; end if;
  for p in select * from jsonb_array_elements(p_pages) loop
    v_course := nullif(p->>'course_id', '')::uuid; v_ev := nullif(p->>'evidence_id', '')::uuid;
    if v_course is null or v_ev is null then continue; end if;
    if p ? 'error' then
      update pipeline.elr_det_pages d set outcome = 'failed', result = left(p->>'error', 160), read_at = now()
       where d.course_id = v_course and d.evidence_id = v_ev and d.extractor = v_x;
      v_failed := v_failed + 1; continue;
    end if;
    insert into pipeline.elr_det_pages as d (course_id, evidence_id, extractor, outcome, chars, sha256, readings, read_at)
    values (v_course, v_ev, v_x, 'read', (p->>'chars')::int, p->>'sha256', jsonb_array_length(coalesce(p->'readings', '[]'::jsonb)), now())
    on conflict (course_id, evidence_id, extractor) do update set outcome = 'read', chars = excluded.chars, sha256 = excluded.sha256, readings = excluded.readings, read_at = now();
    v_pages := v_pages + 1;
    -- a page read again (after a lost call) is judged again; a promoted reading stays promoted
    update pipeline.elr_det_readings x set status = 'recorded', reason = null where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and x.status in ('held', 'review');
    for r in select * from jsonb_array_elements(coalesce(p->'readings', '[]'::jsonb)) loop
      continue when r->>'key' not in ('ielts', 'toefl_ibt', 'pte', 'oet', 'celpip', 'cambridge') or length(coalesce(r->>'quote', '')) not between 8 and 400;
      insert into pipeline.elr_det_readings (course_id, evidence_id, extractor, test_key, value, quote, strength, flags)
      values (v_course, v_ev, v_x, r->>'key', r->'value', r->>'quote', case when r->>'strength' = 'stated_minimum' then 'stated_minimum' else 'mentioned' end,
              coalesce((select array_agg(f) from jsonb_array_elements_text(coalesce(r->'flags', '[]'::jsonb)) f), '{}'))
      on conflict do nothing;
      get diagnostics v_n = row_count; v_readings := v_readings + v_n;
    end loop;

    -- page and course gates (a failed gate holds every reading of the page with its reason)
    select c.id, c.provider_id, c.lifecycle_status, g2.status gs, g2.read_status grs, g2.evidence_id gev, g2.identity_basis ib, g2.basis gb, g2.url,
           exists (select 1 from pipeline.coverage_admission_countries a join catalogue.providers pr on pr.country_id = a.country_id where pr.id = c.provider_id and a.active) adm
      into g from catalogue.courses c left join pipeline.coverage_course_pages g2 on g2.course_id = c.id where c.id = v_course;
    v_reason := case
      when g.id is null or g.lifecycle_status <> 'active' then 'course not active'
      when not g.adm then 'country has no admission rule'
      when g.gs is distinct from 'bound' or g.grs is distinct from 'read' or g.gev is distinct from v_ev then 'page is no longer the course''s bound, read page'
      when not (coalesce(g.gb, '') = 'manual' or g.ib in ('manual', 'cricos_code', 'nzqa_code', 'adapter_code') or (g.ib is not null and security.coverage_identity_allowed(g.provider_id, g.ib, 'english'))) then 'page identity not accepted for English (' || coalesce(g.ib, 'none') || ')'
      when security.page_refused_v1(v_course, g.url) then 'page refused'
      when security.layer4_entity_or_parent_blocked('course', v_course, 'operational') then 'course held by Layer 4'
      when exists (select 1 from catalogue.course_english_requirements e where e.course_id = v_course and e.status = 'active') then 'course already holds an English requirement (no overwrite)'
      when exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = v_course and l.field in ('english', 'english_requirements', 'course_english')) then 'English set by hand (manual lock)'
      when exists (select 1 from pipeline.layer4_review_items i where i.entity_id = v_course and i.field_code = 'course_english' and i.status = 'pending') then 'English already waiting in Layer 4'
      when not exists (select 1 from pipeline.elr_det_readings x where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and not ('pathway' = any (x.flags))) then 'page states no English test requirement'
      end;
    if v_reason is not null then
      update pipeline.elr_det_readings x set status = 'held', reason = v_reason where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and x.status = 'recorded';
      update pipeline.elr_det_pages d set result = 'held: ' || v_reason where d.course_id = v_course and d.evidence_id = v_ev and d.extractor = v_x;
      v_held := v_held + 1; continue;
    end if;
    update pipeline.elr_det_readings x set status = 'held', reason = 'about a pathway, foundation or English course' where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and 'pathway' = any (x.flags) and x.status = 'recorded';

    -- each test on the page: agreement, minimum words, value in quote, completeness
    v_ok := '[]'::jsonb; v_conf := '[]'::jsonb;
    for t in
      select x.test_key k, count(distinct x.value) nv, bool_and(x.strength = 'stated_minimum') strong, bool_and(security.elr_det_quote_ok_v1(x.test_key, x.value, x.quote)) qok,
             (array_agg(x.value order by x.id))[1] val, (array_agg(x.quote order by x.id))[1] q,
             jsonb_agg(jsonb_build_object('value', x.value, 'quote', x.quote) order by x.id) alts
        from pipeline.elr_det_readings x where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and not ('pathway' = any (x.flags)) and x.status = 'recorded'
       group by x.test_key
    loop
      if t.nv > 1 then
        v_conf := v_conf || jsonb_build_array(jsonb_build_object('test_code', case t.k when 'toefl_ibt' then 'TOEFL_IBT' when 'cambridge' then 'CAE' else upper(t.k) end, 'readings', t.alts));
      elsif not t.qok then
        update pipeline.elr_det_readings x set status = 'held', reason = 'value not printed in its quote' where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and x.test_key = t.k and x.status = 'recorded';
      elsif not t.strong then
        update pipeline.elr_det_readings x set status = 'held', reason = 'no minimum or requirement words' where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and x.test_key = t.k and x.status = 'recorded';
      elsif (t.k = 'oet' and not (t.val->>'grade' in ('A', 'B', 'C+', 'C') or (jsonb_typeof(t.val->'components') = 'object' and (select count(*) from jsonb_object_keys(t.val->'components')) = 4)))
         or (t.k <> 'oet' and coalesce(jsonb_typeof(t.val->'overall'), '') <> 'number') then
        update pipeline.elr_det_readings x set status = 'held', reason = 'incomplete (no overall score or grade)' where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and x.test_key = t.k and x.status = 'recorded';
      else
        v_ok := v_ok || jsonb_build_array(jsonb_build_object('key', t.k, 'test_code', case t.k when 'toefl_ibt' then 'TOEFL_IBT' when 'cambridge' then 'CAE' else upper(t.k) end,
                  'overall_score', t.val->'overall', 'component_scores', coalesce(t.val->'components', '{}'::jsonb), 'grade', t.val->'grade', 'level', t.val->'level', 'quote', t.q));
      end if;
    end loop;

    v_review := case
      when jsonb_array_length(v_conf) > 0 then 'The course page gives more than one requirement for ' || (select string_agg(c->>'test_code', ', ') from jsonb_array_elements(v_conf) c) || ' (for example for different levels or programmes); choose the one for this course.'
      when jsonb_array_length(v_ok) = 0 then null
      when (select count(*) from pipeline.coverage_course_pages s where s.evidence_id = v_ev and s.status = 'bound') > 1 then 'The course page is shared by several courses; check that this English requirement applies to this course.'
      when abs(hashtext(v_course::text)) % 100 < v_audit then 'Audit sample: check the English requirement read from the course page before it is used.'
      when not v_promote then null
      end;
    if v_review is not null then
      insert into pipeline.layer4_review_items (entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, escalation_reason, change_control_ref)
      values ('course', v_course, 'course_english', v_ev, '{}'::jsonb,
              jsonb_build_object('english_requirements', (select coalesce(jsonb_agg(o - 'key' - 'level' - 'grade' || case when o->>'grade' is not null then jsonb_build_object('score_grade', o->'grade') else '{}'::jsonb end), '[]'::jsonb) from jsonb_array_elements(v_ok) o),
                                 'conflicts', v_conf, 'source', v_x),
              jsonb_build_object('source', 'elr_det', 'extractor', v_x, 'page', g.url, 'identity_basis', g.ib, 'run', p_run),
              v_review, 'CF-CHG-20260915-247');
      update pipeline.elr_det_readings x set status = 'review', reason = v_review where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and x.status = 'recorded';
      update pipeline.elr_det_pages d set result = 'review' where d.course_id = v_course and d.evidence_id = v_ev and d.extractor = v_x;
      v_review_n := v_review_n + 1; continue;
    end if;
    if jsonb_array_length(v_ok) = 0 or not v_promote then
      update pipeline.elr_det_readings x set status = 'held', reason = case when v_promote then 'no reading passed every check' else 'promotion switched off (elr_det.promote_on)' end
       where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and x.status = 'recorded';
      update pipeline.elr_det_pages d set result = case when v_promote then 'held: no reading passed every check' else 'held: promotion off' end where d.course_id = v_course and d.evidence_id = v_ev and d.extractor = v_x;
      v_held := v_held + 1; continue;
    end if;

    -- promote: insert only (no overwrite); the manual lock trigger still has the last word
    v_wrote := 0;
    for r in select * from jsonb_array_elements(v_ok) loop
      select et.id into v_test from ref.english_tests et where et.code = r->>'test_code';
      continue when v_test is null;
      insert into catalogue.course_english_requirements (course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id, confidence,
                                                         source_requirement_key, status, last_verified_at, score_grade)
      select v_course, v_test, nullif(r->>'overall_score', '')::numeric, coalesce(r->'component_scores', '{}'::jsonb),
             'Read from the course page (' || v_x || case when r->>'level' is not null then ', Cambridge ' || (r->>'level') else '' end || '): ' || left(r->>'quote', 240),
             e.source_id, v_ev, 1, 'elr-det:' || lower(r->>'test_code'), 'active', now(), nullif(r->>'grade', '')
        from pipeline.evidence_artifacts e where e.id = v_ev
      on conflict (course_id, english_test_id) do nothing;
      get diagnostics v_n = row_count;
      update pipeline.elr_det_readings x set status = case when v_n > 0 then 'promoted' else 'held' end,
             reason = case when v_n > 0 then 'promoted' else 'not written: the course already has a row for this test or a lock holds it' end
       where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and x.test_key = r->>'key' and x.status = 'recorded';
      v_wrote := v_wrote + v_n;
    end loop;
    update pipeline.elr_det_readings x set status = 'held', reason = coalesce(x.reason, 'not promoted') where x.course_id = v_course and x.evidence_id = v_ev and x.extractor = v_x and x.status = 'recorded';
    update pipeline.elr_det_pages d set result = case when v_wrote > 0 then 'promoted ' || v_wrote else 'held: nothing written' end where d.course_id = v_course and d.evidence_id = v_ev and d.extractor = v_x;
    if v_wrote > 0 then v_promoted_courses := v_promoted_courses + 1; v_rows := v_rows + v_wrote; v_done := v_done || v_course; else v_held := v_held + 1; end if;
  end loop;

  -- search.course_documents for the promoted courses, through the one writer; if another writer holds the lock the scheduled projection picks them up
  if cardinality(v_done) > 0 then
    if pg_try_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) then  -- fixed: the one writer lock for search.course_documents (W27)
      perform search.refresh_course_enrichment_scoped_v1(v_done, true); v_search := 'refreshed';
    else v_search := 'deferred'; end if;
  end if;
  return jsonb_build_object('pages', v_pages, 'readings', v_readings, 'promoted_courses', v_promoted_courses, 'rows_written', v_rows, 'review', v_review_n, 'held', v_held,
                            'failed', v_failed, 'search', v_search, 'extractor', v_x);
end $f$;
comment on function security.elr_det_record_v1(jsonb, text) is 'CF-247 s842: the one writer of the English requirement sweep. Records pages and readings (pipeline.elr_det_*), then per course: promotes readings that pass every gate (page identity, quote, agreement, completeness, no-overwrite, manual locks, audit sample) into catalogue.course_english_requirements and search.course_documents; sends conflicts, shared pages and the audit sample to Layer 4 (course_english); holds the rest with a reason.';
revoke all on function security.elr_det_record_v1(jsonb, text) from public, anon, authenticated;

-- (s842) one run of the sweep: read back answered calls, give up lost ones, send the next batch
create or replace function security.elr_det_sweep_tick_v1() returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  q record; v_res jsonb; v_rec jsonb; v_harv int := 0; v_bad int := 0; v_lost int := 0; v_sent int := 0; v_pages int := 0;
  v_open int; v_room int; v_batch int; v_per int; v_cur uuid; v_all jsonb; v_items jsonb; v_id bigint; v_claimed int; v_last uuid; i int;
  v_t0 timestamptz := clock_timestamp();
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247:elr_det_sweep')) then return jsonb_build_object('skipped', 'another run is working'); end if;  -- fixed: one run at a time
  -- 1. answered calls
  for q in select r.id, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.elr_det_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' = 'elr-det-v1.0' then
      v_rec := security.elr_det_record_v1(v_res->'pages', 'request:' || q.id);
      update pipeline.elr_det_requests set status = 'done', finished_at = now(), result = v_rec where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.elr_det_requests set status = 'failed', finished_at = now(), result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    update pipeline.elr_det_pages set outcome = 'lost' where request_id = q.id and outcome = 'sent';
  end loop;
  -- 2. calls with no answer in time are given up; their pages go back to the queue
  with l as (update pipeline.elr_det_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_det_pages d set outcome = 'lost' from l where d.request_id = l.id and d.outcome = 'sent';
  get diagnostics v_lost = row_count;
  -- 3. the next batch
  if security.pipeline_num_v1('elr_det.sweep_on', 1) < 1 then
    return jsonb_build_object('read_back', v_harv, 'failed', v_bad, 'pages_lost', v_lost, 'sent', 0, 'sweep', 'off', 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  end if;
  select count(*) into v_open from pipeline.elr_det_requests where status = 'sent';
  v_per := greatest(5, least(40, security.pipeline_num_v1('elr_det.pages_per_call', 25)::int));
  v_room := security.pipeline_num_v1('elr_det.in_flight_max', 8)::int - v_open;
  v_batch := least(security.pipeline_num_v1('batch.elr_det_sweep', 200)::int, greatest(v_room, 0) * v_per);
  if v_batch > 0 then
    select s.cursor_id into v_cur from pipeline.elr_det_state s where s.id = 1 for update;
    select coalesce(jsonb_agg(jsonb_build_object('course_id', c.course_id, 'evidence_id', c.evidence_id, 'storage_path', c.storage_path) order by c.course_id), '[]'::jsonb)
      into v_all from security.elr_det_claim_v1(v_cur, v_batch) c;
    v_claimed := jsonb_array_length(v_all);
    v_last := case when v_claimed > 0 then (v_all->(v_claimed - 1)->>'course_id')::uuid end;
    i := 0;
    while i * v_per < v_claimed loop
      select jsonb_agg(e.v order by e.n) into v_items from jsonb_array_elements(v_all) with ordinality e(v, n) where e.n > i * v_per and e.n <= (i + 1) * v_per;
      v_id := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_det_read', 'items', v_items));
      insert into pipeline.elr_det_requests (id, pages) values (v_id, jsonb_array_length(v_items));
      insert into pipeline.elr_det_pages as d (course_id, evidence_id, extractor, outcome, request_id, sent_at)
      select (e->>'course_id')::uuid, (e->>'evidence_id')::uuid, 'elr-det-v1.0', 'sent', v_id, now() from jsonb_array_elements(v_items) e
      on conflict (course_id, evidence_id, extractor) do update set outcome = 'sent', request_id = excluded.request_id, sent_at = now(), result = null where d.outcome = 'lost';
      v_sent := v_sent + 1; v_pages := v_pages + jsonb_array_length(v_items); i := i + 1;
    end loop;
    update pipeline.elr_det_state set cursor_id = case when v_claimed < v_batch then '00000000-0000-0000-0000-000000000000'::uuid else v_last end,
           passes = passes + case when v_claimed < v_batch then 1 else 0 end, updated_at = now() where id = 1;
  end if;
  return jsonb_build_object('read_back', v_harv, 'failed', v_bad, 'pages_lost', v_lost, 'calls_sent', v_sent, 'pages_sent', v_pages, 'open_before', v_open,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $f$;
comment on function security.elr_det_sweep_tick_v1() is 'CF-247 s842: one run of the job elr-det-sweep. Reads back the worker''s answers (pg_net) and records them through security.elr_det_record_v1, gives up calls with no answer in time, then sends the next indexed batch of gap course pages to the coverage-sweep worker (mode elr_det_read). $0: no model, no Firecrawl.';
revoke all on function security.elr_det_sweep_tick_v1() from public, anon, authenticated;

-- (s842) what the sweep has done and what is left (read only; for the workflow and the reports)
create or replace function security.elr_det_status_v1() returns jsonb
language sql stable security definer set search_path to ''
as $f$
  with ac as (
    select c.id, co.iso_alpha2 cc from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id
     where c.lifecycle_status = 'active' and co.iso_alpha2 in ('AU', 'NZ', 'CA')),
  t as (
    select ac.cc, count(*) n,
           count(*) filter (where exists (select 1 from catalogue.course_english_requirements r where r.course_id = ac.id and r.status = 'active')) with_elr,
           count(*) filter (where not exists (select 1 from catalogue.course_english_requirements r where r.course_id = ac.id and r.status = 'active')
                              and exists (select 1 from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
                                           where g.course_id = ac.id and g.status = 'bound')) gap_page,
           count(*) filter (where not exists (select 1 from catalogue.course_english_requirements r where r.course_id = ac.id and r.status = 'active')
                              and not exists (select 1 from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
                                               where g.course_id = ac.id and g.status = 'bound')) gap_nopage
      from ac group by 1)
  select jsonb_build_object(
    'by_country', (select jsonb_object_agg(cc, jsonb_build_object('active', n, 'with_elr', with_elr, 'gap_with_page', gap_page, 'gap_no_page', gap_nopage)) from t),
    'pages', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select outcome || ':' || coalesce(split_part(result, ':', 1), '-') k, count(*) n from pipeline.elr_det_pages group by 1) z),
    'readings', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select status || ':' || test_key k, count(*) n from pipeline.elr_det_readings group by 1) z),
    'held_reasons', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select left(coalesce(result, '-'), 60) k, count(*) n from pipeline.elr_det_pages where result like 'held:%' group by 1 order by 2 desc limit 10) z),
    'rows_promoted', (select count(*) from catalogue.course_english_requirements where source_requirement_key like 'elr-det:%' and status = 'active'),
    'courses_promoted', (select count(distinct course_id) from catalogue.course_english_requirements where source_requirement_key like 'elr-det:%' and status = 'active'),
    'layer4_pending', (select count(*) from pipeline.layer4_review_items where field_code = 'course_english' and status = 'pending' and layer2_state->>'source' = 'elr_det'),
    'calls', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from pipeline.elr_det_requests group by 1) z),
    'state', (select to_jsonb(s) from pipeline.elr_det_state s where s.id = 1),
    'manual_locks', (select count(*) from pipeline.manual_locks))
$f$;
comment on function security.elr_det_status_v1() is 'CF-247 s842: English requirement coverage of active AU, NZ and CA courses (with a requirement, gap with a stored page, gap without) and what the sweep has read, promoted, sent to Layer 4 and held. Reads only.';
revoke all on function security.elr_det_status_v1() from public, anon, authenticated;

-- (G1) the job
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('elr-det-sweep', 'English requirements', 5, 'English requirement sweep: read stored course pages',
  'Every 5 minutes: reads back the answers of its earlier calls and records them, then sends the next batch of stored course pages of courses with no English requirement to the deterministic English reader (no AI, no Firecrawl). Readings that pass every check are added to the course (never over an existing requirement or a manual lock); conflicts, shared pages and an audit sample go to Layer 4. Switch off with English requirement sweep: on.',
  6, true)
on conflict (jobname) do nothing;

select cron.schedule('elr-det-sweep', '2-59/5 * * * *', 'select security.elr_det_sweep_tick_v1()')
where not exists (select 1 from cron.job where jobname = 'elr-det-sweep');

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'elr-det-sweep', 'Layer 2', 'English requirements', 'Reads stored course pages for English requirements and promotes verified readings every 5 minutes', 'active', '{}', '20261120170000'),
  ('table', 'pipeline.elr_det_pages', 'Layer 2', 'English requirements', 'Pages the deterministic English reader was sent or has read, with the outcome', 'active', '{}', '20261120170000'),
  ('table', 'pipeline.elr_det_readings', 'Layer 2', 'English requirements', 'English test readings with verbatim quotes and the gate outcome', 'active', '{}', '20261120170000'),
  ('table', 'pipeline.elr_det_requests', 'Layer 2', 'English requirements', 'Worker calls of the English requirement sweep', 'active', '{}', '20261120170000'),
  ('table', 'pipeline.elr_det_state', 'Layer 2', 'English requirements', 'The sweep''s keyset cursor (one row)', 'active', '{}', '20261120170000'),
  ('function', 'security.elr_det_claim_v1', 'Layer 2', 'English requirements', 'Next gap course pages for the English reader (indexed keyset)', 'active', '{}', '20261120170000'),
  ('function', 'security.elr_det_quote_ok_v1', 'Layer 2', 'English requirements', 'A reading''s quote names its test and prints its values', 'active', '{}', '20261120170000'),
  ('function', 'security.elr_det_record_v1', 'Layer 2', 'English requirements', 'Records English readings and promotes, reviews or holds them by the gates', 'active', '{}', '20261120170000'),
  ('function', 'security.elr_det_sweep_tick_v1', 'Layer 2', 'English requirements', 'One run of the English requirement sweep', 'active', '{}', '20261120170000'),
  ('function', 'security.elr_det_status_v1', 'Layer 2', 'English requirements', 'English requirement coverage and sweep outcomes (read only)', 'active', '{}', '20261120170000')
on conflict do nothing;

-- post-checks: the plans are unchanged row for row and quick, the claim is quick, the job is scheduled and catalogued, the settings exist, the consumer API has not moved
do $c$
declare r record; v_h text; v_ms numeric; v_max numeric := 0; t0 timestamptz; v_api jsonb; v_n int; v_after numeric[] := '{}';
begin
  -- each plan is run twice: the first run plans the query in this session (as every job run does), the second is the steady cost; both are reported, the first is held to 300 ms
  for r in select * from s840_plan_before loop
    t0 := clock_timestamp();
    select md5(coalesce(string_agg(t::text, '|' order by t.course_id), '')) into v_h from security.provider_english_plan_v1(r.proposal_id) t;
    v_ms := extract(epoch from clock_timestamp() - t0) * 1000; v_max := greatest(v_max, v_ms); v_after := v_after || round(v_ms);
    if v_h <> r.h then raise exception 'post-check: the English plan of proposal % changed', r.proposal_id; end if;
  end loop;
  -- the written-out title key equals security.english_title_key for every active course of these providers
  if exists (select 1 from catalogue.courses co where co.lifecycle_status = 'active'
                and co.provider_id in (select o.provider_id from pipeline.provider_policy_proposals o join s840_plan_before b on b.proposal_id = o.id)
                and security.english_title_key(co.canonical_title) is distinct from
                    btrim(regexp_replace(regexp_replace(regexp_replace(
                      replace(regexp_replace(lower(coalesce(co.canonical_title,'')),'\(\s*\d+\s+units(\s+and\s+\d+\s+units)?\s*\)','','g'),'&',' and '),
                      '[^a-z0-9/]+',' ','g'),' ?/ ?','/','g'),'\s+',' ','g'))) then
    raise exception 'post-check: the written-out title key differs from security.english_title_key';
  end if;
  -- timing is reported, not enforced: the database is shared with the other lanes' jobs and a single run swings with their load (20 Nov 2026 15:55 to 16:25 AEDT, same
  -- eight plans: before 230 to 5,649 ms, after 151 to 2,223 ms). The steady cost is read live after the merge through security.elr_det_status_v1 and the runner's own timings.

  t0 := clock_timestamp();
  select count(*) into v_n from security.elr_det_claim_v1('00000000-0000-0000-0000-000000000000'::uuid, 250);
  v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if v_ms > 300 then raise exception 'post-check: the sweep claim took % ms (limit 300 ms)', round(v_ms); end if;
  if v_n = 0 then raise exception 'post-check: the claim found no gap course page (expected about 6,000)'; end if;

  if (security.elr_det_record_v1('[]'::jsonb, 'post-check')->>'pages')::int <> 0 then raise exception 'post-check: the writer answered an empty call wrongly'; end if;
  if not exists (select 1 from cron.job where jobname = 'elr-det-sweep' and active and command = 'select security.elr_det_sweep_tick_v1()') then raise exception 'post-check: the job is not scheduled'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'elr-det-sweep') then raise exception 'post-check: the job is not catalogued (G1)'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('batch.elr_det_sweep', 'elr_det.pages_per_call', 'elr_det.in_flight_max',
        'elr_det.audit_pct', 'elr_det.promote_on', 'elr_det.sweep_on', 'elr_det.request_lost_minutes')) <> 7 then raise exception 'post-check: a setting is missing (G2)'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s840_locks) then raise exception 'post-check: the manual locks changed (% before)', (select n from s840_locks); end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  raise notice 's840: English plans before % ms, after % ms; claim % ms for % pages', (select array_agg(round(ms)) from s840_plan_before), v_after, round(v_ms), v_n;
end $c$;
