-- CF-247 AER v2: the shared 50-case stratified evaluation set and its spend plan (Platform Admin 14 Nov 2026, item 3: "prepare the shared 50-case
--   stratified evaluation set to benchmark Qwen3 30B (pinned providers + require_parameters), Mistral Small 3.2 24B, and MiMo-V2.6-Flash once Phase 1b is
--   ready. Record the proposed test call count and max spend before starting paid calls").
-- What:
--   1. pipeline.aer_v2_eval_cases: the 50 cases of set aer-v2-eval-50-v1, each a course with its bound official page frozen at selection (evidence id,
--      content hash, storage path), so the three models read the same stored bytes. Strata (first match wins; at most 2 courses of a provider in a stratum,
--      4 in S2 and 8 in S3; stable order md5(course_id || set)):
--        S3  8  courses the v2 trial read on 13 Nov (known failure shapes: joined lead-ins, long quotes, no answer, cut answers; one provider, no cap)
--        S1 14  courses whose v1 read waits in Layer 4 as gate_incomplete (the backlog v3 is to clear)
--        S2 10  courses with rows a person decided in Layer 4 (gold rows for agreement)
--        S4  7  courses with 6 or more active requirement rows (many routes on one page)
--        S5  5  long pages (stored size between the 90th and 97th percentile; tests the never-cut rule)
--        S6  6  courses with no requirement held and no Layer 4 read (candidate negatives)
--   2. pipeline.aer_v2_eval_plans: the proposed run, status 'proposed': 3 evaluation versions x 50 cases = 150 calls, at most 300 with one retry of a call
--      that returned no answer, and a maximum spend of US$2.00 (basis recorded in the row). Status 'proposed' approves nothing: a paid call needs the
--      Platform Admin to approve the plan and open an on-demand request, and no runner exists in this change.
-- Nothing is read, called, spent or admitted. aer.v2_shadow_on stays 0; the 1,912-page queue and every page's tries are unchanged.
-- Replaces: nothing. Retires: nothing.

create table if not exists pipeline.aer_v2_eval_cases (
  eval_set text not null,
  case_no integer not null,
  stratum text not null,
  stratum_label text not null,
  course_id uuid not null,
  provider_id uuid not null,
  evidence_id uuid not null,
  content_hash text,
  storage_path text not null,
  stored_bytes bigint,
  selected_at timestamptz not null default now(),
  primary key (eval_set, case_no),
  unique (eval_set, course_id)
);
comment on table pipeline.aer_v2_eval_cases is 'AER v2 benchmark: the shared evaluation cases (Platform Admin 14 Nov 2026 item 3). One row per case: the course, its stratum and its bound official page frozen at selection (evidence id, content hash, storage path), so every benchmarked model reads the same stored bytes. Selection only; nothing here is read or admitted.';

create table if not exists pipeline.aer_v2_eval_plans (
  id bigserial primary key,
  eval_set text not null,
  versions text[] not null,
  cases integer not null,
  calls_proposed integer not null,
  calls_max integer not null,
  retry_rule text not null,
  max_usd numeric not null,
  per_call_max_usd jsonb not null,
  basis text not null,
  status text not null default 'proposed' check (status in ('proposed', 'approved', 'run', 'closed')),
  depends_on text not null,
  recorded_by text not null,
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz not null default now()
);
comment on table pipeline.aer_v2_eval_plans is 'AER v2 benchmark: the proposed run of an evaluation set (versions, cases, the proposed and maximum call count, the maximum spend and its basis), recorded before any paid call (Platform Admin 14 Nov 2026 item 3). A proposed plan approves nothing; approval is the Platform Admin''s and the spend goes through an on-demand request.';

-- the set (frozen once: a set already selected is never re-selected)
insert into pipeline.aer_v2_eval_cases(eval_set, case_no, stratum, stratum_label, course_id, provider_id, evidence_id, content_hash, storage_path, stored_bytes)
with base as materialized (
  select c.id course_id, c.provider_id, g.evidence_id, a.content_hash, a.storage_path, (o.metadata->>'size')::bigint bytes
    from catalogue.courses c
    join security.aer_eligible_v1() e on e.provider_id = c.provider_id
    join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'
    join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null
    left join storage.objects o on o.bucket_id = 'evidence' and o.name = a.storage_path
   where c.lifecycle_status = 'active' and c.open_to_international is not false),
trial as materialized (select distinct r.course_id from pipeline.aer_v2_shadow_results r where r.prompt_version = 'aer-v2-course-v2'),
gi as materialized (select distinct l.course_id from (
    select distinct on (a.review_item_id) a.review_item_id, a.reason_code, i.entity_id course_id
      from pipeline.layer4_review_items i join pipeline.aer_machine_admissions a on a.review_item_id = i.id
     where i.field_code = 'course_entry_first_read' and i.status = 'pending' and i.entity_type = 'course'
     order by a.review_item_id, a.updated_at desc) l where l.reason_code = 'gate_incomplete'),
person as materialized (select distinct l.course_id from pipeline.aer_labelled_rows_v1 l where l.course_id is not null and l.decision is not null),
many as materialized (select r.course_id from catalogue.course_entry_requirements r where r.status = 'active' group by 1 having count(*) >= 6),
pct as materialized (select percentile_cont(0.90) within group (order by b.bytes) p90, percentile_cont(0.97) within group (order by b.bytes) p97 from base b where b.bytes is not null),
held as materialized (select b.course_id from base b
                       where not exists (select 1 from catalogue.course_entry_requirements r where r.course_id = b.course_id)
                         and not exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = b.course_id and i.field_code = 'course_entry_first_read')),
strata(stratum, label, want, per_provider, ord) as (values
  ('S3', 'v2 trial course (known failure shapes)', 8, 8, 1), ('S1', 'gate_incomplete v1 read in Layer 4', 14, 2, 2), ('S2', 'rows a person decided', 10, 4, 3),
  ('S4', 'six or more active requirement rows', 7, 2, 4), ('S5', 'long stored page (90th to 97th percentile)', 5, 2, 5), ('S6', 'no requirement held, no Layer 4 read', 6, 2, 6)),
tagged as (select b.*, case when b.course_id in (select course_id from trial) then 'S3'
                            when b.course_id in (select course_id from gi) then 'S1'
                            when b.course_id in (select course_id from person) then 'S2'
                            when b.course_id in (select course_id from many) then 'S4'
                            when b.bytes between (select p90 from pct) and (select p97 from pct) then 'S5'
                            when b.course_id in (select course_id from held) then 'S6' end stratum
             from base b),
capped as (select t.*, row_number() over (partition by t.stratum, t.provider_id order by md5(t.course_id::text || 'aer-v2-eval-50-v1')) prov_rank from tagged t where t.stratum is not null),
picked as (select c.*, s.label, s.ord, row_number() over (partition by c.stratum order by md5(c.course_id::text || 'aer-v2-eval-50-v1')) st_rank, s.want
             from capped c join strata s on s.stratum = c.stratum where c.prov_rank <= s.per_provider)
select 'aer-v2-eval-50-v1', row_number() over (order by p.ord, p.st_rank)::int, p.stratum, p.label, p.course_id, p.provider_id, p.evidence_id, p.content_hash, p.storage_path, p.bytes
  from picked p
 where p.st_rank <= p.want and not exists (select 1 from pipeline.aer_v2_eval_cases x where x.eval_set = 'aer-v2-eval-50-v1');

-- the proposed run, recorded before any paid call
insert into pipeline.aer_v2_eval_plans(eval_set, versions, cases, calls_proposed, calls_max, retry_rule, max_usd, per_call_max_usd, basis, depends_on, recorded_by)
select 'aer-v2-eval-50-v1', array['aer-v2-course-v3-qwen3-30b', 'aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash'],
       (select count(*) from pipeline.aer_v2_eval_cases where eval_set = 'aer-v2-eval-50-v1'),
       3 * (select count(*) from pipeline.aer_v2_eval_cases where eval_set = 'aer-v2-eval-50-v1'),
       6 * (select count(*) from pipeline.aer_v2_eval_cases where eval_set = 'aer-v2-eval-50-v1'),
       'one call per case and version; at most one retry of a call that returned no answer (no choices, HTTP error); a cut answer, a page over reading.aer_v2_page_chars or a verifier failure is never retried',
       2.00,
       '{"qwen/qwen3-30b-a3b-instruct-2507": 0.0059, "mistralai/mistral-small-3.2-24b-instruct": 0.0056, "xiaomi/mimo-v2.6-flash": 0.0065}'::jsonb,
       'Worst case per call: input at most 66,300 characters (page at most reading.aer_v2_page_chars 60,000; prompt 4,282; 39 qualifications 1,697; course header) taken as 22,100 tokens at 3 characters a token, plus reading.aer_v2_max_tokens 12,000 output tokens, at the dearest pinned provider (OpenRouter endpoints read 14 Nov 2026: Qwen Nebius US$0.10/US$0.30 per million in/out; Mistral Parasail US$0.09/US$0.30; MiMo Xiaomi US$0.14/US$0.28). 50 cases x 3 versions x US$0.0059/0.0056/0.0065 = US$0.89; doubled for the retry ceiling = US$1.79; plan cap US$2.00. The v2 trial cost about US$0.0011 a read.',
       'Lean AI Input Phase 1b ready (Platform Admin 14 Nov 2026 item 3); the Platform Admin approves this plan and opens an on-demand request before any call',
       'migration 20261114021500'
 where not exists (select 1 from pipeline.aer_v2_eval_plans x where x.eval_set = 'aer-v2-eval-50-v1');

-- post-checks
do $k$
declare n int; s jsonb;
begin
  select count(*) into n from pipeline.aer_v2_eval_cases where eval_set = 'aer-v2-eval-50-v1';
  if n <> 50 then raise exception 'post-check: % cases selected (expected 50)', n; end if;
  select jsonb_object_agg(stratum, k) into s from (select stratum, count(*) k from pipeline.aer_v2_eval_cases where eval_set = 'aer-v2-eval-50-v1' group by 1) z;
  if s <> '{"S1": 14, "S2": 10, "S3": 8, "S4": 7, "S5": 5, "S6": 6}'::jsonb then raise exception 'post-check: strata %', s; end if;
  if exists (select 1 from pipeline.aer_v2_eval_plans p where p.eval_set = 'aer-v2-eval-50-v1' and (p.status <> 'proposed' or p.calls_proposed <> 150 or p.calls_max <> 300 or p.max_usd <> 2.00)) then
    raise exception 'post-check: the plan must be proposed with 150 calls, at most 300, and US$2.00';
  end if;
  if (select count(*) from pipeline.aer_prompt_versions v where v.version = any (array['aer-v2-course-v3-qwen3-30b', 'aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash']) and v.status = 'evaluation') <> 3 then
    raise exception 'post-check: the three evaluation versions are missing';
  end if;
  if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 then raise exception 'post-check: the v2 reader must stay paused'; end if;
end $k$;
