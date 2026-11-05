-- CF-247 intake recovery and process accountability (Platform Admin decision 5 Nov 2026, recorded verbatim in admin
-- docs/platform/2026-11-05-intake-recovery-process-accountability-decision.md; design 2026-11-05-intake-calendar-v2-design.md;
-- evidence docs/platform/processes/intake-dates.md, measured 08:43-08:57).
-- Why: for the top 10 Australian universities 5,399 intake months on 2,606 courses are held with stored evidence, yet 0 start dates and
--   3 deadlines. Defects: D1 the AI calendar reader asked for months only; D2 the dated parser (calendar-dates-v1) was never applied to stored
--   calendars; D3 the AI saw only the first 24,000 characters; D4 the date step used only the latest approved calendar, and wrong documents
--   won (residential colleges, UNSW Global, Monash Indonesia); D5 month-only course pages never took a date; D6 a skipped row was never looked
--   at again; D7 no record of what the process did, missed and why, and no screen for it.
-- What (the existing reader, queue, approval, plan and apply are extended; no second reader):
--   1 Settings (G2), Intake dates and Reading sections: intake_dates.month_unique_match (1: decision §3), intake_dates.revisit_days,
--     central.calendar_excluded_words, central.auto_approve_calendar_dates (0: a deterministic dated reading still goes to a person until the
--     Platform Admin switches this on), batch.calendar_reread, reading.calendar_slice_chars, reading.calendar_max_slices,
--     reading.calendar_notes_max, reading.calendar_answer_tokens, process_results.validation_rows, process_results.history_rows,
--     process_results.window_days.
--   2 Tables (beside, never into, consumer shapes): pipeline.course_intake_date_events (every decision kept: a new run never overwrites
--     earlier failure evidence), pipeline.calendar_reread_state (each stored calendar document: deterministic first, AI only when that is
--     not safe), pipeline.calendar_reader_findings (what the reader dropped; fed to the next AI read), pipeline.process_results (each dated
--     measurement of a process). New columns on pipeline.course_intake_dates: calendar_set, inputs_fp, next_action, next_revisit_at.
--   3 Calendars: security.calendar_scope_v1, security.calendar_sources_v1 (each document's latest approved reading and its scope),
--     security.calendar_proposal_dates_v1 (one reading's dated starts, deadlines, meaning and who a deadline applies to),
--     security.calendar_dated_periods_v2 (every main teaching calendar of a university, not the latest only), security.calendar_set_v1.
--     A set-aside calendar is not deleted or replaced: its scope and reason are shown and a flag routes it to a person (decision §2).
--   4 security.intake_dates_plan_v3: plan v2 with v2 calendars, the unique-month rule (decision §3: one eligible commencement in that month
--     and year, never orientation or a deadline; a course page date that differs holds the row), the deadline that applies to international
--     applicants first, a next-action class for every outcome (decision §8) and an inputs fingerprint (calendar set and reader, page evidence,
--     course page, decision settings): a row is looked at again only when that changes or its class's revisit time passes (decision §7.9, §8).
--   5 md5-guarded edits: security.intake_dates_apply_v1(int, uuid[]) (d47fbe68: plan v3, the new columns, an event per decision),
--     security.intake_ui_selection_v1 (a61e8114) and security.run_now_cohort_create_v1 (410db5ca): plan v3 so Preview, cohort and job agree;
--     public.svc_central_ai_next (fc8273f8): calendar items carry the reader's notes; public.svc_central_ai_record (2f386c25): calendar
--     findings recorded; security.policy_auto_approve_v1 (12cce3d8): approving one calendar document no longer closes another document's
--     proposal, and deterministic dated readings are approved only when central.auto_approve_calendar_dates is 1.
--   6 Re-read of stored calendars, no Firecrawl: public.svc_calendar_reread_next / _record for worker mode calendar_reread (job
--     calendar-reread): the dated parser first; the existing pinned central-page model (central-ai queue) only when it gives no current or
--     future dated teaching start or the address cannot be trusted.
--   7 Process results: security.process_results_intake_dates_v1 (per university: eligible courses, stored pages, valid calendars, calendar
--     year and freshness, future periods, held values, outcomes by next action and reason, never examined, next revisit, admitted in the
--     window, values in the Website API source, AI cost), security.process_results_record_v1 (job process-results: a dated row, nothing
--     overwritten; the observer raises a flag for a university whose calendars are set aside or give no future start), the markdown for the
--     repository, and public.admin_process_results_v1 for Layer 2/3 Operations › Process results.
-- Consumer API: unchanged (G3). Values reach intakes[].year, start_date and application_deadline only through intake_dates_apply_v1 and the
--   existing projection refresh, as before.
-- Replaces: security.intake_dates_plan_v2 (by security.intake_dates_plan_v3; marked retiring); security.calendar_dated_periods_v1 in the date step (by security.calendar_dated_periods_v2); md5-guarded edits of intake_dates_apply_v1, intake_ui_selection_v1, run_now_cohort_create_v1, svc_central_ai_next, svc_central_ai_record, policy_auto_approve_v1
-- Retires: nothing (plan v2 is marked retiring; dropped by a paste file after hygiene.retire_after_days once unused)
-- Nothing is dropped or deleted.

create or replace function pg_temp.guard(p_sig text, p_md5 text, p_after_marker text) returns boolean language plpgsql as $g$
declare v text := pg_get_functiondef(p_sig::regprocedure);
begin
  if p_after_marker is not null and position(p_after_marker in v) > 0 then return false; end if;  -- already applied
  if md5(v) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %, expected %)', p_sig, md5(v), p_md5; end if;
  return true;
end $g$;

create or replace function pg_temp.edit(p_sig text, p_md5 text, p_marker text, p_old text[], p_new text[], p_times int[]) returns text language plpgsql as $e$
declare v text; i int; n int;
begin
  if not pg_temp.guard(p_sig, p_md5, p_marker) then return p_sig || ': already applied'; end if;
  v := pg_get_functiondef(p_sig::regprocedure);
  for i in 1 .. array_length(p_old, 1) loop
    n := (length(v) - length(replace(v, p_old[i], ''))) / length(p_old[i]);
    if n <> p_times[i] then raise exception '%: edit % must apply exactly % time(s), found %', p_sig, i, p_times[i], n; end if;
    v := replace(v, p_old[i], p_new[i]);
  end loop;
  execute v;
  return p_sig || ': edited';
end $e$;

-- 1 settings -------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'intake_dates.month_unique_match', 'Intake dates: a month takes the date of the only start that month',
  '1: when the course page gives a month but names no study period, the month takes the calendar date only when exactly one eligible teaching start of a main teaching calendar falls in that month and year (never orientation, enrolment or a deadline; a different date on the course page holds the row). Two or more starts keep the month only. 0: the course page must name the period.',
  'number', to_jsonb(1), 0, 1, 'on/off', 994, 'Intake dates', 'security.intake_dates_plan_v3; job intake-dates-apply',
  'Platform Admin decision 5 Nov 2026 §3: unique month matching approved under its safeguards'),
 ('pipeline', 'intake_dates.revisit_days', 'Intake dates: look again at a waiting row after',
  'A row waiting for the next academic year, an official calendar, course identity or a limit is looked at again after this many days, or at once when its calendar, page evidence, course page or the decision settings change. Rows held for ambiguity, a person or a reader correction wait for a change only.',
  'number', to_jsonb(14), 1, 90, 'days', 995, 'Intake dates', 'security.intake_dates_plan_v3',
  'Platform Admin decision 5 Nov 2026 §8: every held value has a next check through configurable scheduling'),
 ('pipeline', 'central.calendar_excluded_words', 'Calendars: addresses that are not a main teaching calendar',
  'An approved calendar whose address contains one of these words is set aside for intake dates (shown with the reason, never deleted) unless a person sets it by hand.',
  'list', '["indonesia","malaysia","/china","study-abroad","inbound","exchange","residential","ormond","trinity","unswglobal","senior-college","foundation"]'::jsonb, null, null, 'words', 996, 'Intake dates', 'security.calendar_scope_v1',
  'Platform Admin decision 5 Nov 2026 §2: wrong calendar documents identified (Monash Indonesia, Monash Study Abroad, Ormond and Trinity colleges, UNSW Global)'),
 ('pipeline', 'central.auto_approve_calendar_dates', 'Calendars: approve deterministic dated readings automatically',
  '1: a calendar reading by the dated parser (no AI) for a focus university is approved automatically when every start is quoted and the address is a main teaching calendar, as checked AI readings are. 0: a person approves it in the Adapter builder.',
  'number', to_jsonb(0), 0, 1, 'on/off', 997, 'Admission checks', 'security.policy_auto_approve_v1',
  'Off until the Platform Admin decides (a passing qualification never switches anything on by itself)'),
 ('pipeline', 'batch.calendar_reread', 'Calendar re-read: documents a run',
  'Stored calendar documents read again by the current calendar reader in one run of job calendar-reread (no Firecrawl).',
  'number', to_jsonb(20), 1, 60, 'documents', 998, 'Job sizes', 'job calendar-reread; public.svc_calendar_reread_next',
  'Platform Admin decision 5 Nov 2026 §2: read stored official calendars first'),
 ('pipeline', 'reading.calendar_slice_chars', 'Calendar reader: characters an AI call reads',
  'A long calendar document is read in slices of this size (the reader saw only the first 24,000 characters before).',
  'number', to_jsonb(24000), 4000, 60000, 'characters', 999, 'Intake dates', 'coverage-sweep central_ai (intake_calendar)',
  'Defect D3, 5 Nov 2026'),
 ('pipeline', 'reading.calendar_max_slices', 'Calendar reader: most slices a document',
  'At most this many AI calls for one calendar document; a longer document records the finding document_longer_than_read.',
  'number', to_jsonb(4), 1, 10, 'calls', 1000, 'Intake dates', 'coverage-sweep central_ai (intake_calendar)', 'Defect D3, 5 Nov 2026'),
 ('pipeline', 'reading.calendar_answer_tokens', 'Calendar reader: AI answer length',
  'Most tokens in one calendar read''s answer (dated starts, deadlines and quotes of every period need more than the month-only answer). A cut answer is never parsed; the read is held and tried again.',
  'number', to_jsonb(4000), 1000, 16000, 'tokens', 1000, 'Intake dates', 'coverage-sweep central_ai (intake_calendar)', 'Defect D1, 5 Nov 2026'),
 ('pipeline', 'reading.calendar_notes_max', 'Calendar reader: earlier findings given to the AI',
  'The newest open findings of a university''s calendar reads given to the next AI read as notes (0 gives none).',
  'number', to_jsonb(5), 0, 20, 'findings', 1001, 'Intake dates', 'public.svc_central_ai_next; security.calendar_reader_notes_v1',
  'Platform Admin decision 5 Nov 2026 §7: learn from newly encountered formats'),
 ('pipeline', 'process_results.validation_rows', 'Process results: rows shown for validation',
  'Recent decisions shown with their course, before and after, page wording, calendar quote and document on Process results.',
  'number', to_jsonb(25), 5, 200, 'rows', 1002, 'Process results', 'public.admin_process_results_v1', 'Platform Admin decision 5 Nov 2026 §6'),
 ('pipeline', 'process_results.history_rows', 'Process results: measurements listed',
  'Earlier dated measurements listed on Process results.', 'number', to_jsonb(30), 5, 500, 'measurements', 1003, 'Process results', 'public.admin_process_results_v1',
  'Platform Admin decision 5 Nov 2026 §5')
on conflict (toolset_key, key) do nothing;

-- 2 tables and columns --------------------------------------------------------------------------------------------------------------------
alter table pipeline.course_intake_dates add column if not exists calendar_set text, add column if not exists inputs_fp text,
  add column if not exists next_action text, add column if not exists next_revisit_at timestamptz;
create index if not exists course_intake_dates_provider_idx on pipeline.course_intake_dates(provider_id, next_action);

create table if not exists pipeline.course_intake_date_events (
  id bigserial primary key, intake_id uuid not null, course_id uuid not null, provider_id uuid not null, run_at timestamptz not null default now(),
  rule text, outcome text not null, reason text, next_action text, next_revisit_at timestamptz, calendar_set text, proposal_id uuid,
  periods text[], start_precision text, deadline_kind text, before_value jsonb, after_value jsonb, page_quote text, start_quote text,
  deadline_quote text, calendar_url text, calendar_evidence_id uuid, bounded boolean not null default false);
comment on table pipeline.course_intake_date_events is 'CF-247 intake recovery (Platform Admin decision 5 Nov 2026 §5): every decision of the intake-dates job (security.intake_dates_apply_v1), one row per intake row per run: outcome, reason, next action and revisit, the calendar set, before and after, the page wording and calendar quote and document. Appended only; a later success never overwrites an earlier failure. Read on Layer 2/3 Operations › Process results. Never read by the consumer API.';
create index if not exists course_intake_date_events_provider_idx on pipeline.course_intake_date_events(provider_id, run_at desc);
create index if not exists course_intake_date_events_intake_idx on pipeline.course_intake_date_events(intake_id, run_at desc);
alter table pipeline.course_intake_date_events enable row level security;

create table if not exists pipeline.calendar_reread_state (
  fact_source_id uuid primary key references pipeline.provider_fact_sources(id), provider_id uuid not null, content_hash text, reader text,
  state text not null default 'waiting' check (state in ('waiting', 'leased', 'dated_by_parser', 'sent_to_ai', 'read_by_ai', 'no_dates', 'failed')),
  reason text, parser_summary jsonb, attempts int not null default 0, leased_until timestamptz, last_at timestamptz, created_at timestamptz not null default now());
comment on table pipeline.calendar_reread_state is 'CF-247 intake recovery (decision 5 Nov 2026 §2, §7): each stored calendar document read again by the current calendar reader, without Firecrawl: the dated parser first (dated_by_parser), the pinned central-page model only when the parser gives no current or future dated teaching start or the address is not trusted (sent_to_ai, then read_by_ai), with the reason. Read again only when the document or the reader changes. Written by public.svc_calendar_reread_record; never read by the consumer API.';
alter table pipeline.calendar_reread_state enable row level security;

create table if not exists pipeline.calendar_reader_findings (
  id bigserial primary key, provider_id uuid not null, fact_source_id uuid, code text not null, detail text, example text, times int not null default 1,
  first_seen timestamptz not null default now(), last_seen timestamptz not null default now(), resolved_at timestamptz,
  unique (provider_id, fact_source_id, code, detail));
comment on table pipeline.calendar_reader_findings is 'CF-247 intake recovery (decision 5 Nov 2026 §7), as pipeline.fee_reader_findings for fees: what the calendar reader could not take or dropped (quote not on the page, a date not in its quote, no year, not a teaching start, not a main calendar, a document longer than read, no future start), per university and document with an example. The newest open findings go to the next AI read as notes; resolved when a later read no longer has them; kept, never deleted. Never read by the consumer API.';
alter table pipeline.calendar_reader_findings enable row level security;

create table if not exists pipeline.process_results (
  id bigserial primary key, process_key text not null, scope_key text not null, measured_at timestamptz not null default now(),
  summary jsonb not null, markdown text, measured_by text);
comment on table pipeline.process_results is 'CF-247 process accountability (Platform Admin decision 5 Nov 2026 §5, §6): each dated measurement of a production process (what it did, how many, what was missed and why, the next revisit, admitted and published deltas), written by job process-results and on request; nothing is overwritten, so earlier failure evidence stays. Shown on Layer 2/3 Operations › Process results and committed to the repository by the process-results workflow. Never read by the consumer API.';
create index if not exists process_results_key_idx on pipeline.process_results(process_key, scope_key, measured_at desc);
alter table pipeline.process_results enable row level security;

-- 3 calendars ----------------------------------------------------------------------------------------------------------------------------
create or replace function security.calendar_scope_v1(p_proposal jsonb, p_url text, p_parser text) returns text
language sql stable security definer set search_path to '' as $function$
  select case
    when p_parser = 'set by hand' then 'main_teaching'
    when coalesce(p_proposal->>'scope', '') not in ('', 'main_teaching') then p_proposal->>'scope'
    when exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'central.calendar_excluded_words'), '[]'::jsonb)) w
                  where lower(coalesce(p_url, '')) like '%' || lower(w) || '%') then 'excluded_by_address'
    else 'main_teaching' end
$function$;
comment on function security.calendar_scope_v1(jsonb, text, text) is 'CF-247 (decision 5 Nov 2026 §2): the scope of an approved calendar reading: set by hand = main teaching; the reader''s scope when it gave one; excluded_by_address when the address has a word of central.calendar_excluded_words; else main teaching.';

create or replace function security.calendar_sources_v1(p_provider uuid)
returns table(proposal_id uuid, fact_source_id uuid, url text, evidence_id uuid, parser text, decided_at timestamptz, scope text, used boolean, set_aside_reason text, proposal jsonb)
language sql stable security definer set search_path to '' as $function$
  with latest as (
    select distinct on (coalesce(p.fact_source_id::text, p.url)) p.id, p.fact_source_id, p.url, p.evidence_id, p.parser, p.decided_at, p.proposal
      from pipeline.provider_policy_proposals p
     where p.provider_id = p_provider and p.kind = 'intake_calendar' and p.status = 'approved'
     order by coalesce(p.fact_source_id::text, p.url), p.decided_at desc nulls last, p.created_at desc)
  select l.id, l.fact_source_id, l.url, l.evidence_id, l.parser, l.decided_at, s.scope, s.scope = 'main_teaching',
         case when s.scope = 'excluded_by_address' then 'the address names another campus, college, exchange or pathway calendar'
              when s.scope <> 'main_teaching' then 'the reader found this calendar is ' || replace(s.scope, '_', ' ') end,
         l.proposal
    from latest l, lateral (select security.calendar_scope_v1(l.proposal, l.url, l.parser) scope) s
$function$;
comment on function security.calendar_sources_v1(uuid) is 'CF-247 (decision 5 Nov 2026 §2): each calendar document of a university with its latest approved reading, its scope and whether intake dates use it (set aside with a reason otherwise; nothing replaced or deleted).';

-- one reading's dated periods (calendar_dated_periods_v1 applied to one reading; the AI v2 reading adds meaning and who a deadline applies to)
create or replace function security.calendar_proposal_dates_v1(p_proposal_id uuid)
returns table(proposal_id uuid, period text, kind text, year int, month int, day int, on_date date, rolling_text text, quote text, applies_to text, meaning text, year_quote text)
language sql stable security definer set search_path to '' as $function$
  with cal as (select p.id, p.proposal from pipeline.provider_policy_proposals p where p.id = p_proposal_id),
  per as (select cal.id, lower(btrim(e->>'period')) period, e from cal, jsonb_array_elements(coalesce(cal.proposal->'periods', '[]'::jsonb)) e),
  given as (
    select per.id, per.period, k.kind, nullif(x->>'year', '')::int y, nullif(x->>'month', '')::int m, nullif(x->>'day', '')::int d, x->>'quote' q,
           x->>'applies_to' applies_to, x->>'meaning' meaning, x->>'year_quote' year_quote
      from per, lateral (values ('start', per.e->'starts'), ('deadline', per.e->'deadlines')) k(kind, arr), jsonb_array_elements(coalesce(k.arr, '[]'::jsonb)) x
     where jsonb_typeof(k.arr) = 'array'
       -- decision §1: only a teaching start is a commencement (never orientation, enrolment or a deadline)
       and (k.kind = 'deadline' or coalesce(x->>'meaning', 'teaching_start') = 'teaching_start')),
  quoted as (
    select per.id, per.period, 'start'::text kind, q,
           regexp_match(q, '(?:\m(\d{1,2})(?:st|nd|rd|th)?\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\M|\m(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?\M)(?:,?\s+(20\d\d))?', 'i') d
      from per, jsonb_array_elements_text(coalesce(per.e->'quotes', '[]'::jsonb)) q
     where not (per.e ? 'starts')
       and q !~* '\m(exams?|examinations?|supplementary|census|results|holidays?|break|recess|graduation|enrolment|withdraw\w*|orientation)\M'),
  quoted_dates as (
    select z.id, z.period, z.kind, coalesce(nullif(z.d[5], '')::int, (regexp_match(z.q, '\m(20\d\d)\M'))[1]::int) y,
           (array_position(array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'], lower(left(coalesce(z.d[2], z.d[3]), 3))))::int m,
           case when z.q !~ '\m\d{1,2}(st|nd|rd|th)?\s*[–—-]\s*\d{1,2}(st|nd|rd|th)?\s+[A-Za-z]' then coalesce(z.d[1], z.d[4])::int end d, z.q,
           null::text applies_to, null::text meaning, null::text year_quote
      from quoted z where z.d is not null),
  quoted_kept as (
    select q.* from quoted_dates q join per on per.id = q.id and per.period = q.period where per.e->'months' @> to_jsonb(q.m)),
  dated as (select * from given union all select * from quoted_kept)
  select a.id, a.period, a.kind, a.y, a.m, a.d,
         case when a.y is not null and a.d between 1 and extract(day from (make_date(a.y, a.m, 1) + interval '1 month - 1 day'))::int  -- fixed: the last day of the month
              then make_date(a.y, a.m, a.d) end,
         null::text, left(a.q, 300), a.applies_to, a.meaning, left(a.year_quote, 300)
    from dated a where a.m between 1 and 12
  union all
  select per.id, per.period, 'rolling', null, null, null, null, left(r, 300), left(r, 300), null, null, null
    from per, jsonb_array_elements_text(coalesce(per.e->'deadline_rolling', '[]'::jsonb)) r
$function$;
comment on function security.calendar_proposal_dates_v1(uuid) is 'CF-247 (decision 5 Nov 2026 §1, §2): the dated starts, deadlines and rolling deadline wording of one approved calendar reading, as calendar_dated_periods_v1 reads the latest one; only teaching starts count as a commencement.';

create or replace function security.calendar_dated_periods_v2(p_provider uuid)
returns table(proposal_id uuid, period text, kind text, year int, month int, day int, on_date date, rolling_text text, quote text, applies_to text, meaning text, url text, evidence_id uuid, year_ok boolean)
language sql stable security definer set search_path to '' as $function$
  select d.proposal_id, d.period, d.kind, d.year, d.month, d.day, d.on_date, d.rolling_text, d.quote, d.applies_to, d.meaning, s.url, s.evidence_id,
         -- the year is printed in the quote, or in the heading the reader quoted for it (year_quote, on the page)
         d.year is not null and (d.quote ~ ('\m' || d.year || '\M') or coalesce(d.year_quote, '') ~ ('\m' || d.year || '\M'))
    from security.calendar_sources_v1(p_provider) s, lateral security.calendar_proposal_dates_v1(s.proposal_id) d
   where s.used
$function$;
comment on function security.calendar_dated_periods_v2(uuid) is 'CF-247 (decision 5 Nov 2026, defect D4): the dated periods of every main teaching calendar of a university (each document''s latest approved reading), with its document; replaces calendar_dated_periods_v1 (latest approved calendar only) in the intake date step.';

create or replace function security.calendar_set_v1(p_provider uuid) returns text
language sql stable security definer set search_path to '' as $function$
  select case when count(*) filter (where s.used) = 0 then 'none:' || count(*)
              else md5(string_agg(s.proposal_id::text || ':' || s.parser, ',' order by s.proposal_id) filter (where s.used)) end
    from security.calendar_sources_v1(p_provider) s
$function$;
comment on function security.calendar_set_v1(uuid) is 'CF-247 (decision 5 Nov 2026 §8): the fingerprint of the calendar readings a university''s intake dates use (each reading and its parser), or none:<n set aside>; a change makes every row of the university eligible again.';

create or replace function security.intake_inputs_fp_v1(p_set text, p_evidence uuid, p_course_url text, p_settings text) returns text
language sql immutable as $function$ select md5(coalesce(p_set, '') || '|' || coalesce(p_evidence::text, '') || '|' || coalesce(p_course_url, '') || '|' || coalesce(p_settings, '')) $function$;
comment on function security.intake_inputs_fp_v1(text, uuid, text, text) is 'CF-247 (decision 5 Nov 2026 §7.9, §8): the inputs an intake row was decided on (calendar set and reader, page evidence, course page, decision settings); a row is not looked at again while they are unchanged and its revisit time has not passed.';

-- decision §8: the next action of a decision, and when it is looked at again without a change
create or replace function security.intake_next_action_v1(p_outcome text, p_reason text, p_complete boolean) returns text
language sql immutable as $function$
  select case
    when p_outcome in ('filled', 'nothing_new') and p_complete then 'complete'
    when p_outcome in ('filled', 'nothing_new') then 'awaiting_official_calendar'
    when p_reason in ('intakes locked by hand', 'course held', 'kept by a lock or the same-month guard') then 'human_decision_required'
    when p_reason like 'no valid academic calendar%set aside%' then 'calendar_needs_correction'
    when p_reason like 'no valid academic calendar%' then 'awaiting_official_calendar'
    when p_reason in ('no page behind the intake', 'page refused for this course') or p_reason like 'page not proved%' then 'course_identity_unresolved'
    when p_reason like 'no stored reading of the page%' or p_reason like 'the calendar does not print the year%' then 'reader_correction_needed'
    when p_reason like '%past%' or p_reason like 'the calendar has no future start%' or p_reason like 'the calendar prints no start%'
      or p_reason like 'the year of the named period is not printed%' then 'waiting_for_next_academic_year'
    when p_reason like 'the course page gives its own start date%' then 'human_decision_required'
    else 'evidence_ambiguous' end
$function$;
comment on function security.intake_next_action_v1(text, text, boolean) is 'CF-247 (decision 5 Nov 2026 §8): the next-action class of an intake date decision: complete, awaiting official calendar, calendar needs correction, course identity unresolved, evidence ambiguous, reader correction needed, human decision required, waiting for next academic year (budget or operational limit and not published by provider are given by the process results).';

create or replace function security.intake_revisit_at_v1(p_next_action text) returns timestamptz
language sql stable security definer set search_path to '' as $function$
  select case when p_next_action in ('awaiting_official_calendar', 'course_identity_unresolved', 'waiting_for_next_academic_year', 'budget_or_operational_limit', 'ready_for_scheduled_recovery')
              then now() + make_interval(days => security.pipeline_num_v1('intake_dates.revisit_days', 14)::int) end
$function$;
comment on function security.intake_revisit_at_v1(text) is 'CF-247 (decision 5 Nov 2026 §8): when a waiting row is looked at again without a change (intake_dates.revisit_days); null for complete rows and for rows that wait for a change only (ambiguous, a person, a reader correction, a calendar correction).';

-- 4 plan v3 -------------------------------------------------------------------------------------------------------------------------------
create or replace function security.intake_dates_plan_v3(p_course_ids uuid[] default null, p_limit int default null)
returns table(intake_id uuid, course_id uuid, provider_id uuid, proposal_id uuid, outcome text, reason text, periods text[],
              new_year int, new_start date, new_deadline date, start_precision text, deadline_kind text, deadline_text text,
              start_quote text, deadline_quote text, before_value jsonb, page_quote text, calendar_evidence_id uuid, calendar_url text, rule text,
              calendar_set text, inputs_fp text, next_action text, next_revisit_at timestamptz)
language plpgsql stable security definer set search_path to '' as $function$
declare
  v_lists boolean := security.pipeline_num_v1('intake_dates.name_period_lists', 0) = 1;
  v_unique boolean := security.pipeline_num_v1('intake_dates.month_unique_match', 0) = 1;
  v_settings text := 'lists=' || v_lists::text || ';unique=' || v_unique::text;
  v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: the calendar day in Australia (month roll-over)
  v_max_before int := security.pipeline_num_v1('intake_dates.deadline_max_days_before', 366)::int;
  v_limit int := coalesce(p_limit, security.pipeline_num_v1('batch.intake_dates_apply', 200)::int);
  r record; v_m int; v_year int; v_starts date[]; v_start date; v_pers text[]; v_sq text; v_dl date[]; v_dq text; v_roll text; v_url text; v_chk jsonb;
  v_raw text; v_pq text; v_named text[]; v_cal jsonb := '[]'::jsonb; v_cal_provider uuid; v_n int; v_page_dates date[]; v_intl boolean;
begin
  for r in
    with prov as materialized (
      select distinct c.provider_id from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
       where i.status = 'active' and c.lifecycle_status = 'active' and (p_course_ids is null or i.course_id = any (p_course_ids))
         and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
         and exists (select 1 from pipeline.provider_policy_proposals p where p.provider_id = c.provider_id and p.kind = 'intake_calendar' and p.status = 'approved')),
    sets as materialized (select prov.provider_id, security.calendar_set_v1(prov.provider_id) s from prov)
    select i.id, i.course_id, c.provider_id, i.intake_label, i.intake_year, i.start_date, i.application_deadline, i.evidence_id, c.course_url, sets.s cal_set,
           security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings) fp
      from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id join sets on sets.provider_id = c.provider_id
      left join pipeline.enrich_focus_providers f on f.provider_id = c.provider_id and f.in_focus
     where i.status = 'active' and c.lifecycle_status = 'active'
       and (p_course_ids is null or i.course_id = any (p_course_ids))
       and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
       -- decision §7.9, §8: looked at again only when an input changed or the row's revisit time passed
       and not exists (select 1 from pipeline.course_intake_dates d where d.intake_id = i.id
                          and d.inputs_fp is not distinct from security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings)
                          and (d.next_revisit_at is null or d.next_revisit_at > now()))
     order by f.rank nulls last, i.course_id, i.id
     limit v_limit
  loop
    intake_id := r.id; course_id := r.course_id; provider_id := r.provider_id; periods := null; new_year := null; new_start := null; new_deadline := null;
    outcome := null; start_precision := null; deadline_kind := null; deadline_text := null; start_quote := null; deadline_quote := null; reason := null; proposal_id := null;
    page_quote := null; calendar_evidence_id := null; calendar_url := null; rule := 'calendar-v3'; calendar_set := r.cal_set; inputs_fp := r.fp;
    before_value := jsonb_build_object('year', r.intake_year, 'start_date', r.start_date, 'application_deadline', r.application_deadline);
    if v_cal_provider is distinct from r.provider_id then
      v_cal := coalesce((select jsonb_agg(to_jsonb(s)) from security.calendar_dated_periods_v2(r.provider_id) s), '[]'::jsonb);
      v_cal_provider := r.provider_id;
    end if;
    -- a university whose approved calendars are all set aside, or give nothing, has no valid calendar
    if r.cal_set like 'none:%' then
      outcome := 'skipped';
      reason := case when split_part(r.cal_set, ':', 2)::int > 0 then 'no valid academic calendar: the approved calendars are set aside (not the main teaching calendar)'
                     else 'no valid academic calendar' end;
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; continue;
    end if;
    v_m := array_position(array['january','february','march','april','may','june','july','august','september','october','november','december'], lower(btrim(r.intake_label)));
    if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('intakes', 'intake')) then
      outcome := 'skipped'; reason := 'intakes locked by hand';
    elsif security.course_held_v1(r.course_id) then outcome := 'skipped'; reason := 'course held';
    elsif v_m is null then outcome := 'skipped'; reason := 'intake is not a month';
    end if;
    if outcome = 'skipped' then
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action); return next; outcome := null; continue;
    end if;
    select e.source_url into v_url from pipeline.evidence_artifacts e where e.id = r.evidence_id;
    if v_url is null then reason := 'no page behind the intake';
    elsif security.page_refused_v1(r.course_id, v_url) then reason := 'page refused for this course';
    else
      v_chk := security.course_page_check_v1(r.course_id, v_url, null, null);
      if v_chk->>'verdict' is distinct from 'pass' then reason := 'page not proved to be the course''s own (E16 ' || coalesce(v_chk->>'verdict', 'no verdict') || ')'; end if;
    end if;
    if reason is not null then
      outcome := 'skipped'; next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; outcome := null; continue;
    end if;
    v_raw := security.intake_page_wording_v1(r.course_id, r.evidence_id, v_url);
    page_quote := left(v_raw, 600);
    if security.intake_month_negated_v1(v_raw, v_m) then
      outcome := 'skipped'; reason := 'the page excludes this month (listed for withdrawal)';
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := null; return next; outcome := null; continue;
    end if;
    v_pq := security.intake_period_text_v1(v_raw, v_lists);
    select array_agg(distinct s.period) into v_named
      from jsonb_to_recordset(v_cal) s(period text, kind text)
     where s.kind = 'start' and s.period ~ '^[a-z][a-z _-]*[0-9]+$' and v_pq ~ ('\m' || regexp_replace(s.period, '[ _-]+', '[ _-]*', 'g') || '\M');
    if v_named is null then
      if coalesce(v_raw, '') = '' then
        outcome := 'skipped'; start_precision := 'month'; reason := 'no stored reading of the page''s intake wording (month only)';
        next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := null; return next; outcome := null; continue;
      end if;
      if not v_unique then
        outcome := 'skipped'; start_precision := 'month'; reason := 'the course page names no study period of the calendar (month only)';
        next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := null; return next; outcome := null; continue;
      end if;
      -- decision §3: the month takes the date only when exactly one eligible teaching start falls in that month of the intake's year
      select min(s.year) into v_year from jsonb_to_recordset(v_cal) s(kind text, year int, month int, on_date date, year_ok boolean)
       where s.kind = 'start' and s.month = v_m and s.year is not null
         and (s.year_ok or v_pq ~ ('\m' || s.year || '\M'))
         and (s.on_date >= v_today or (s.on_date is null and make_date(s.year, s.month, 1) >= date_trunc('month', v_today)::date))
         and (r.intake_year is null or s.year = r.intake_year);
      if v_year is null then
        outcome := 'skipped'; start_precision := 'month';
        reason := case when r.intake_year is not null then 'the calendar prints no start in this month of the intake''s own year (month only)'
                       when exists (select 1 from jsonb_to_recordset(v_cal) s(kind text, month int, year int, year_ok boolean) where s.kind = 'start' and s.month = v_m and s.year_ok)
                         then 'the calendar''s starts in this month are past (month only)'
                       when exists (select 1 from jsonb_to_recordset(v_cal) s(kind text, month int) where s.kind = 'start' and s.month = v_m)
                         then 'the calendar does not print the year of its start in this month (month only)'
                       else 'the calendar has no future start in this month (month only)' end;
        next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
        return next; outcome := null; continue;
      end if;
      -- one entry per period (its dated start when any calendar dates it); two periods, or two dates, are ambiguous
      select count(distinct coalesce(z.pd::text, z.period)), array_agg(distinct z.period) into v_n, v_named
        from (select s.period, min(s.on_date) pd from jsonb_to_recordset(v_cal) s(kind text, period text, year int, month int, on_date date, year_ok boolean)
               where s.kind = 'start' and s.month = v_m and s.year = v_year and (s.year_ok or v_pq ~ ('\m' || s.year || '\M')) group by s.period) z;
      if v_n > 1 then
        outcome := 'skipped'; start_precision := 'month'; periods := v_named;
        reason := 'several study periods start in this month (month only)';
        next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := null; return next; outcome := null; continue;
      end if;
      rule := 'calendar-v3-unique-month';
    end if;
    -- the next start of the period(s) in this month, on or after today, in the intake's own year when it holds one
    select min(s.year) into v_year from jsonb_to_recordset(v_cal) s(kind text, period text, year int, month int, on_date date, year_ok boolean)
     where s.kind = 'start' and s.period = any (v_named) and s.month = v_m and s.year is not null
       and (s.year_ok or v_pq ~ ('\m' || s.year || '\M'))
       and (s.on_date >= v_today or (s.on_date is null and make_date(s.year, s.month, 1) >= date_trunc('month', v_today)::date))
       and (r.intake_year is null or s.year = r.intake_year);
    if v_year is null then
      outcome := 'skipped'; start_precision := 'month';
      reason := case when r.intake_year is not null then 'the calendar prints no start of the named period in the intake''s own year'
                     when exists (select 1 from jsonb_to_recordset(v_cal) s(kind text, period text, year int, month int, year_ok boolean) where s.kind = 'start' and s.period = any (v_named)
                                     and s.month = v_m and s.year is not null and (s.year_ok or v_pq ~ ('\m' || s.year || '\M')))
                       then 'the named period''s starts in this month are past'
                     when exists (select 1 from jsonb_to_recordset(v_cal) s(kind text, period text, month int) where s.kind = 'start' and s.period = any (v_named) and s.month = v_m)
                       then 'the year of the named period is not printed (month only)'
                     else 'the named period does not start in this month' end;
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; outcome := null; continue;
    end if;
    select array_agg(distinct s.on_date) filter (where s.on_date is not null), array_agg(distinct s.period), min(s.quote), min(s.proposal_id::text)::uuid, min(s.url), min(s.evidence_id::text)::uuid
      into v_starts, v_pers, v_sq, proposal_id, calendar_url, calendar_evidence_id
      from jsonb_to_recordset(v_cal) s(proposal_id uuid, kind text, period text, year int, month int, on_date date, quote text, url text, evidence_id uuid, year_ok boolean)
     where s.kind = 'start' and s.period = any (v_named) and s.month = v_m and s.year = v_year and (s.year_ok or v_pq ~ ('\m' || s.year || '\M'));
    periods := v_pers; start_quote := v_sq;
    v_start := case when cardinality(v_starts) = 1 then v_starts[1] end;
    -- decision §3: no more specific course-level date may contradict it (a full date of this month and year printed on the course page)
    select array_agg(distinct make_date(v_year, v_m, m[1]::int)) into v_page_dates
      from regexp_matches(coalesce(v_raw, ''), '\m(\d{1,2})(?:st|nd|rd|th)?\s+' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m] || '[a-z]*,?\s+' || v_year || '\M', 'gi') m
     where m[1]::int between 1 and 28 or (m[1]::int <= extract(day from (make_date(v_year, v_m, 1) + interval '1 month - 1 day'))::int);  -- fixed: the last day of the month
    if v_page_dates is not null and (v_start is null or not (v_start = all (v_page_dates))) then
      outcome := 'skipped'; start_precision := 'month';
      reason := 'the course page gives its own start date for this intake (' || array_to_string(v_page_dates, ', ') || ')';
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := null; return next; outcome := null; continue;
    end if;
    start_precision := case when v_start is not null then 'day' else 'year' end;
    if cardinality(v_starts) > 1 then reason := 'two start days in this month: year only'; end if;
    -- the deadline of the matched period(s): one dated closing date before the start; one for international applicants first
    select bool_or(s.applies_to = 'international') into v_intl from jsonb_to_recordset(v_cal) s(kind text, period text, on_date date, applies_to text)
     where s.kind = 'deadline' and s.period = any (v_pers) and s.on_date is not null
       and s.on_date <= coalesce(v_start, make_date(v_year, v_m, 1)) and s.on_date >= coalesce(v_start, make_date(v_year, v_m, 1)) - v_max_before;
    select array_agg(distinct s.on_date), min(s.quote) into v_dl, v_dq
      from jsonb_to_recordset(v_cal) s(kind text, period text, on_date date, quote text, applies_to text)
     where s.kind = 'deadline' and s.period = any (v_pers) and s.on_date is not null
       and coalesce(s.applies_to, 'unstated') in ('international', 'all', 'unstated')
       and (not coalesce(v_intl, false) or s.applies_to = 'international')
       and s.on_date <= coalesce(v_start, make_date(v_year, v_m, 1)) and s.on_date >= coalesce(v_start, make_date(v_year, v_m, 1)) - v_max_before;
    select min(s.rolling_text) into v_roll from jsonb_to_recordset(v_cal) s(kind text, period text, rolling_text text) where s.kind = 'rolling' and s.period = any (v_pers);
    if cardinality(v_dl) = 1 then deadline_kind := 'date'; new_deadline := v_dl[1]; deadline_quote := v_dq;
    elsif v_roll is not null then deadline_kind := 'rolling'; deadline_text := v_roll; deadline_quote := v_roll;
    else deadline_kind := 'not_stated'; end if;
    new_year := case when r.intake_year is null then v_year end;
    new_start := case when r.start_date is null then v_start end;
    new_deadline := case when r.application_deadline is null then new_deadline end;
    outcome := case when new_year is not null or new_start is not null or new_deadline is not null then 'filled' else 'nothing_new' end;
    next_action := security.intake_next_action_v1(outcome, reason,
                     coalesce(r.intake_year, new_year) is not null and coalesce(r.start_date, new_start) is not null and coalesce(r.application_deadline, new_deadline) is not null);
    next_revisit_at := security.intake_revisit_at_v1(next_action);
    return next; outcome := null;
  end loop;
end $function$;
comment on function security.intake_dates_plan_v3(uuid[], integer) is 'CF-247 intake recovery (decision 5 Nov 2026 §1-§3, §8): what each month intake row would gain from the university''s main teaching calendars (all of them, defect D4), the unique-month rule, its next action and revisit, and the inputs it was decided on. Read only; replaces intake_dates_plan_v2.';

-- 5 md5-guarded edits ------------------------------------------------------------------------------------------------------------------
do $apply$ begin
  if not pg_temp.guard('security.intake_dates_apply_v1(integer,uuid[])', 'd47fbe685ae62287264a1909c988e9d6', 'intake_dates_plan_v3') then return; end if;
  execute $def$
CREATE OR REPLACE FUNCTION security.intake_dates_apply_v1(p_limit integer, p_course_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_on boolean := coalesce((security.toolset_setting('pipeline', 'intake_dates.apply_enabled') #>> '{}')::boolean, false);
        v_filled int := 0; v_seen int := 0; v_courses uuid[] := '{}'; p record; v_n int; v_prov int := 0; v_by jsonb := '{}'::jsonb;
begin
  if not v_on then return jsonb_build_object('enabled', false, 'filled', 0); end if;
  perform pg_advisory_xact_lock(hashtext('cf247 intake dates apply'));  -- fixed: one run at a time
  -- 23:24 provenance: values filled before the page wording was kept get it now (as stored now), with the approved calendar's document
  update pipeline.course_intake_dates d
     set page_quote = coalesce(left(security.intake_page_wording_v1(d.course_id, i.evidence_id, e.source_url), 600), ''),
         calendar_evidence_id = cal.evidence_id, calendar_url = cal.url
    from catalogue.course_intakes i left join pipeline.evidence_artifacts e on e.id = i.evidence_id, pipeline.provider_policy_proposals cal
   where d.intake_id in (select d2.intake_id from pipeline.course_intake_dates d2 where d2.outcome = 'filled' and d2.calendar_url is null
                            and (p_course_ids is null or d2.course_id = any (p_course_ids))
                          limit security.pipeline_num_v1('batch.intake_dates_apply', 200)::int)
     and i.id = d.intake_id and cal.id = d.proposal_id;
  get diagnostics v_prov = row_count;
  -- CF-247 intake recovery (decision 5 Nov 2026): plan v3; every decision is also appended to pipeline.course_intake_date_events
  for p in select * from security.intake_dates_plan_v3(p_course_ids, p_limit) loop
    v_seen := v_seen + 1;
    if p.outcome = 'filled' then
      update catalogue.course_intakes i
         set intake_year = coalesce(i.intake_year, p.new_year), start_date = coalesce(i.start_date, p.new_start),
             application_deadline = coalesce(i.application_deadline, p.new_deadline)
       where i.id = p.intake_id and i.status = 'active'
         and (i.intake_year is null or i.intake_year = coalesce(p.new_year, i.intake_year));
      get diagnostics v_n = row_count;  -- 0 when a lock or the same-month guard kept the row as it was
      if v_n = 1 then v_filled := v_filled + 1; v_courses := v_courses || p.course_id; end if;
    end if;
    insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, proposal_id, outcome, reason, periods, start_precision, deadline_kind, deadline_text,
                                             start_quote, deadline_quote, before_value, after_value, applied_at, page_quote, calendar_evidence_id, calendar_url, rule,
                                             calendar_set, inputs_fp, next_action, next_revisit_at)
    select p.intake_id, p.course_id, p.provider_id, p.proposal_id,
           case when p.outcome = 'filled' and v_n = 0 then 'skipped' else p.outcome end,
           case when p.outcome = 'filled' and v_n = 0 then 'kept by a lock or the same-month guard' else p.reason end,
           p.periods, p.start_precision, p.deadline_kind, p.deadline_text, p.start_quote, p.deadline_quote, p.before_value,
           (select jsonb_build_object('year', i.intake_year, 'start_date', i.start_date, 'application_deadline', i.application_deadline) from catalogue.course_intakes i where i.id = p.intake_id), now(),
           p.page_quote, p.calendar_evidence_id, p.calendar_url, p.rule, p.calendar_set, p.inputs_fp,
           case when p.outcome = 'filled' and v_n = 0 then 'human_decision_required' else p.next_action end,
           case when p.outcome = 'filled' and v_n = 0 then null else p.next_revisit_at end
    on conflict (intake_id) do update set proposal_id = excluded.proposal_id, outcome = excluded.outcome, reason = excluded.reason, periods = excluded.periods,
           start_precision = excluded.start_precision, deadline_kind = excluded.deadline_kind, deadline_text = excluded.deadline_text, start_quote = excluded.start_quote,
           deadline_quote = excluded.deadline_quote, before_value = excluded.before_value, after_value = excluded.after_value, applied_at = excluded.applied_at,
           page_quote = excluded.page_quote, calendar_evidence_id = excluded.calendar_evidence_id, calendar_url = excluded.calendar_url, rule = excluded.rule,
           calendar_set = excluded.calendar_set, inputs_fp = excluded.inputs_fp, next_action = excluded.next_action, next_revisit_at = excluded.next_revisit_at;
    insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, rule, outcome, reason, next_action, next_revisit_at, calendar_set, proposal_id, periods,
                                                   start_precision, deadline_kind, before_value, after_value, page_quote, start_quote, deadline_quote, calendar_url, calendar_evidence_id, bounded)
    select d.intake_id, d.course_id, d.provider_id, d.rule, d.outcome, d.reason, d.next_action, d.next_revisit_at, d.calendar_set, d.proposal_id, d.periods,
           d.start_precision, d.deadline_kind, d.before_value, d.after_value, d.page_quote, d.start_quote, d.deadline_quote, d.calendar_url, d.calendar_evidence_id, p_course_ids is not null
      from pipeline.course_intake_dates d where d.intake_id = p.intake_id;
    v_by := jsonb_set(v_by, array[coalesce(case when p.outcome = 'filled' and v_n = 0 then 'human_decision_required' else p.next_action end, 'unclassified')],
                      to_jsonb(coalesce((v_by->>coalesce(case when p.outcome = 'filled' and v_n = 0 then 'human_decision_required' else p.next_action end, 'unclassified'))::int, 0) + 1));
    v_n := null;
  end loop;
  if cardinality(v_courses) > 0 then
    perform search.refresh_course_enrichment_scoped_v1((select array_agg(distinct x) from unnest(v_courses) x), true);
  end if;
  return jsonb_build_object('enabled', true, 'looked_at', v_seen, 'filled', v_filled, 'provenance_completed', v_prov, 'courses', coalesce(cardinality((select array_agg(distinct x) from unnest(v_courses) x)), 0),
                            'bounded', p_course_ids is not null, 'selected_courses', coalesce(cardinality(p_course_ids), 0), 'by_next_action', v_by);
end $function$
$def$;
end $apply$;

select pg_temp.edit('security.intake_ui_selection_v1(text,integer)', 'a61e8114a65bc5e13007b8ff1d262976', 'intake_dates_plan_v3',
  array['security.intake_dates_plan_v2('], array['security.intake_dates_plan_v3('], array[1]);
select pg_temp.edit('security.run_now_cohort_create_v1(text,uuid,text,text)', '410db5ca480e038e32d12c16f66eefa9', 'intake_dates_plan_v3',
  array['security.intake_dates_plan_v2('], array['security.intake_dates_plan_v3('], array[1]);

-- the reader's notes: the newest open findings of the university's calendar reads (decision §7)
create or replace function security.calendar_reader_notes_v1(p_provider uuid) returns text
language sql stable security definer set search_path to '' as $function$
  select nullif(string_agg('- ' || f.code || ': ' || coalesce(f.detail, '') || coalesce(' (example: ' || left(f.example, 160) || ')', ''), E'\n' order by f.last_seen desc), '')
    from (select * from pipeline.calendar_reader_findings f where f.provider_id = p_provider and f.resolved_at is null
           order by f.last_seen desc limit security.pipeline_num_v1('reading.calendar_notes_max', 5)::int) f
$function$;
comment on function security.calendar_reader_notes_v1(uuid) is 'CF-247 (decision 5 Nov 2026 §7): the newest open calendar reader findings of a university, given to the next AI read of its calendars as notes.';

select pg_temp.edit('public.svc_central_ai_next(integer)', 'fc8273f89031a309311d5e247f453fea', 'calendar_reader_notes_v1',
  array[$o$'storage_path', e.storage_path,$o$],
  array[$n$'storage_path', e.storage_path, 'notes', case when u.kind = 'intake_calendar' then security.calendar_reader_notes_v1(u.provider_id) end,$n$], array[1]);

-- findings of a calendar read: open what the reader dropped, resolve what a later read of the same document no longer has
create or replace function security.calendar_reader_findings_record_v1(p_fact_source uuid, p_provider uuid, p_parsed jsonb) returns int
language plpgsql security definer set search_path to '' as $function$
declare v_n int := 0;
begin
  if p_parsed is null or coalesce(p_parsed->>'parser', '') not like '%calendar-v2%' then return 0; end if;
  insert into pipeline.calendar_reader_findings as t(provider_id, fact_source_id, code, detail, example)
  select p_provider, p_fact_source, x->>'code', coalesce(x->>'detail', ''), left(x->>'example', 400)
    from jsonb_array_elements(coalesce(p_parsed->'findings', '[]'::jsonb)) x where coalesce(x->>'code', '') <> ''
  on conflict (provider_id, fact_source_id, code, detail) do update set times = t.times + 1, last_seen = now(), example = excluded.example, resolved_at = null;
  get diagnostics v_n = row_count;
  update pipeline.calendar_reader_findings f set resolved_at = now()
   where f.fact_source_id = p_fact_source and f.resolved_at is null
     and not exists (select 1 from jsonb_array_elements(coalesce(p_parsed->'findings', '[]'::jsonb)) x where x->>'code' = f.code and coalesce(x->>'detail', '') = f.detail);
  update pipeline.calendar_reread_state set state = 'read_by_ai', reason = coalesce(p_parsed->>'scope', 'read'), last_at = now() where fact_source_id = p_fact_source;
  return v_n;
end $function$;
comment on function security.calendar_reader_findings_record_v1(uuid, uuid, jsonb) is 'CF-247 (decision 5 Nov 2026 §7): records the findings of a calendar-v2 read (opened, repeated or resolved) and marks the document read by the AI.';

select pg_temp.edit('public.svc_central_ai_record(bigint,jsonb,numeric,text)', '2f386c25a249d5c8edfb557a3fbc3d84', 'calendar_reader_findings_record_v1',
  array['  r := public.svc_provider_policy_record(q.fact_source_id, p_parsed);'],
  array[E'  r := public.svc_provider_policy_record(q.fact_source_id, p_parsed);\n  if q.kind = ''intake_calendar'' then perform security.calendar_reader_findings_record_v1(q.fact_source_id, q.provider_id, p_parsed); end if;  -- CF-247 decision 5 Nov 2026 §7'],
  array[1]);

select pg_temp.edit('security.policy_auto_approve_v1()', '12cce3d801e7c4b75e021430357fcca2', 'auto_approve_calendar_dates',
  array[$o$where x.status = 'proposed' and x.parser like 'ai:%' and x.kind in ('english_policy', 'intake_calendar')$o$,
        $o$     where provider_id = r.provider_id and kind = r.kind and status = 'proposed' and id <> r.id;$o$],
  array[$n$where x.status = 'proposed' and x.kind in ('english_policy', 'intake_calendar')
              and (x.parser like 'ai:%'
                   -- CF-247 decision 5 Nov 2026 §2: a deterministic dated calendar reading, only when the Platform Admin switches it on
                   or (x.kind = 'intake_calendar' and x.parser = 'provider-policy-calendar-dates-v2' and security.pipeline_num_v1('central.auto_approve_calendar_dates', 0) = 1
                       and security.calendar_scope_v1(x.proposal, x.url, x.parser) = 'main_teaching'))$n$,
        $n$     where provider_id = r.provider_id and kind = r.kind and status = 'proposed' and id <> r.id
       and (r.kind <> 'intake_calendar' or fact_source_id is not distinct from r.fact_source_id);  -- CF-247 5 Nov 2026: one calendar document never closes another's$n$],
  array[1, 1]);

-- 6 re-read of stored calendars (worker mode calendar_reread) ----------------------------------------------------------------------------
create or replace function public.svc_calendar_reread_next(p_limit integer) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.calendar_reread_state(fact_source_id, provider_id, content_hash)
  select f.id, f.provider_id, f.content_hash from pipeline.provider_fact_sources f
   where f.kind = 'intake_calendar' and f.evidence_id is not null
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = f.provider_id)
  on conflict (fact_source_id) do update set state = 'waiting', attempts = 0, content_hash = excluded.content_hash, reason = 'the stored document changed'
   where pipeline.calendar_reread_state.content_hash is distinct from excluded.content_hash and pipeline.calendar_reread_state.state <> 'leased';
  with pick as (
    select s.fact_source_id from pipeline.calendar_reread_state s left join pipeline.enrich_focus_providers fp on fp.provider_id = s.provider_id and fp.in_focus
     where (s.state = 'waiting' or (s.state = 'leased' and s.leased_until < now())) and s.attempts < 3  -- fixed: three tries, then failed with the reason
     order by fp.rank nulls last, s.created_at limit greatest(1, least(coalesce(p_limit, 20), 60)) for update of s skip locked),  -- fixed: the worker's call bound
  upd as (update pipeline.calendar_reread_state s set state = 'leased', leased_until = now() + interval '4 minutes', attempts = s.attempts + 1  -- fixed: lease
            from pick where s.fact_source_id = pick.fact_source_id returning s.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'provider_id', f.provider_id, 'url', f.url, 'storage_path', e.storage_path,
           'trusted_address', security.calendar_scope_v1('{}'::jsonb, f.url, null) = 'main_teaching')), '[]'::jsonb) into v
    from upd u join pipeline.provider_fact_sources f on f.id = u.fact_source_id join pipeline.evidence_artifacts e on e.id = f.evidence_id;
  return v;
end $function$;
comment on function public.svc_calendar_reread_next(integer) is 'CF-247 (decision 5 Nov 2026 §2): the next stored calendar documents for the current calendar reader (new, changed, or never read by it), focus universities first; leased for the worker. Service role only.';

create or replace function public.svc_calendar_reread_record(p_id uuid, p_parsed jsonb, p_send_to_ai boolean, p_reason text, p_error text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare s pipeline.calendar_reread_state%rowtype; r jsonb; v_q bigint;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into s from pipeline.calendar_reread_state where fact_source_id = p_id for update;
  if s.fact_source_id is null then return jsonb_build_object('ok', false); end if;
  if p_error is not null then
    update pipeline.calendar_reread_state set state = case when s.attempts >= 3 then 'failed' else 'waiting' end, reason = left(p_error, 400), leased_until = null, last_at = now()  -- fixed: three tries
     where fact_source_id = p_id;
    return jsonb_build_object('ok', true, 'state', 'error');
  end if;
  -- the dated parser's reading is recorded as a proposal of its own (never into an approved one); approval stays with the existing mechanism
  if p_parsed is not null and jsonb_array_length(coalesce(p_parsed->'periods', '[]'::jsonb)) > 0 then
    r := public.svc_provider_policy_record(p_id, p_parsed);
  end if;
  if p_send_to_ai then
    -- the existing central-page AI queue (job central-ai, pinned model); one open item a document
    if not coalesce((select c.enabled from pipeline.central_ai_settings c where c.id = 1), false) then
      p_send_to_ai := false; p_reason := 'the central-page AI reader is switched off; ' || coalesce(p_reason, '');
    else
      insert into pipeline.central_ai_queue(fact_source_id, provider_id, kind, content_hash)
      select f.id, f.provider_id, f.kind, f.content_hash from pipeline.provider_fact_sources f where f.id = p_id
         and not exists (select 1 from pipeline.central_ai_queue q where q.fact_source_id = f.id and q.state in ('queued', 'leased'))
      returning id into v_q;
    end if;
  end if;
  update pipeline.calendar_reread_state set state = case when p_send_to_ai then 'sent_to_ai' when r is not null then 'dated_by_parser' else 'no_dates' end,
         reader = coalesce(p_parsed->>'parser', s.reader), reason = left(p_reason, 400), parser_summary = jsonb_build_object('periods', jsonb_array_length(coalesce(p_parsed->'periods', '[]'::jsonb)),
         'starts', (select count(*) from jsonb_array_elements(coalesce(p_parsed->'periods', '[]'::jsonb)) e, jsonb_array_elements(coalesce(e->'starts', '[]'::jsonb)) x),
         'deadlines', (select count(*) from jsonb_array_elements(coalesce(p_parsed->'periods', '[]'::jsonb)) e, jsonb_array_elements(coalesce(e->'deadlines', '[]'::jsonb)) x),
         'proposal', r), leased_until = null, last_at = now()
   where fact_source_id = p_id;
  return jsonb_build_object('ok', true, 'proposal', r, 'sent_to_ai', p_send_to_ai);
end $function$;
comment on function public.svc_calendar_reread_record(uuid, jsonb, boolean, text, text) is 'CF-247 (decision 5 Nov 2026 §2): records a stored calendar document read again: the dated parser''s reading as its own proposal (existing approval), and the existing central-page AI queue when the parser cannot read it safely, with the reason. Service role only.';
revoke all on function public.svc_calendar_reread_next(integer), public.svc_calendar_reread_record(uuid, jsonb, boolean, text, text) from public, anon, authenticated;

-- 7 process results -------------------------------------------------------------------------------------------------------------------
create or replace function security.process_results_intake_dates_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_unis jsonb := security.intake_ui_scopes_v1(); v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: the calendar day in Australia
        v_per jsonb; v_job jsonb;
begin
  with u as (select (e->>'id')::uuid id, e->>'name' name, (e->>'active_courses')::int active from jsonb_array_elements(v_unis) e),
  i as (select c.provider_id, i.* from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
         where c.lifecycle_status = 'active' and i.status = 'active' and c.provider_id in (select id from u)),
  d as (select d.* from pipeline.course_intake_dates d join i on i.id = d.intake_id),
  cal as (select u.id provider_id, s.* from u, lateral security.calendar_sources_v1(u.id) s),
  per as (select u.id provider_id, p.* from u, lateral security.calendar_dated_periods_v2(u.id) p)
  select jsonb_agg(jsonb_build_object(
    'provider_id', u.id, 'university', u.name, 'active_courses', u.active,
    'courses_with_intakes', (select count(distinct course_id) from i where i.provider_id = u.id),
    'intake_rows', (select count(*) from i where i.provider_id = u.id),
    'course_pages_stored', (select count(distinct p.course_id) from pipeline.coverage_course_pages p where p.provider_id = u.id and p.read_status = 'read' and p.status = 'bound'),
    'calendars_approved', (select count(*) from cal where cal.provider_id = u.id),
    'calendars_valid', (select count(*) from cal where cal.provider_id = u.id and cal.used),
    'calendars_set_aside', (select coalesce(jsonb_agg(jsonb_build_object('url', cal.url, 'scope', cal.scope, 'reason', cal.set_aside_reason)), '[]'::jsonb) from cal where cal.provider_id = u.id and not cal.used),
    'calendar_latest_year', (select max(per.year) from per where per.provider_id = u.id and per.kind = 'start'),
    'calendar_freshest', (select max(cal.decided_at) from cal where cal.provider_id = u.id and cal.used),
    'future_periods', (select count(*) from per where per.provider_id = u.id and per.kind = 'start' and per.year is not null
                        and (per.on_date >= v_today or (per.on_date is null and make_date(per.year, per.month, 1) >= date_trunc('month', v_today)::date))),
    'future_dated_starts', (select count(*) from per where per.provider_id = u.id and per.kind = 'start' and per.on_date >= v_today),
    'future_deadlines', (select count(*) from per where per.provider_id = u.id and per.kind = 'deadline' and per.on_date >= v_today),
    'held', jsonb_build_object('month', (select count(*) from i where i.provider_id = u.id),
                               'year', (select count(*) from i where i.provider_id = u.id and i.intake_year is not null),
                               'start_date', (select count(*) from i where i.provider_id = u.id and i.start_date is not null),
                               'application_deadline', (select count(*) from i where i.provider_id = u.id and i.application_deadline is not null)),
    'in_website_source', jsonb_build_object(
        'year', (select count(*) from search.course_documents sd, jsonb_array_elements(case when jsonb_typeof(sd.intake_options) = 'array' then sd.intake_options else '[]'::jsonb end) o where sd.provider_id = u.id and o->>'year' is not null),
        'start_date', (select count(*) from search.course_documents sd, jsonb_array_elements(case when jsonb_typeof(sd.intake_options) = 'array' then sd.intake_options else '[]'::jsonb end) o where sd.provider_id = u.id and o->>'start_date' is not null),
        'application_deadline', (select count(*) from search.course_documents sd, jsonb_array_elements(case when jsonb_typeof(sd.intake_options) = 'array' then sd.intake_options else '[]'::jsonb end) o where sd.provider_id = u.id and o->>'application_deadline' is not null)),
    'outcomes', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select coalesce(d.next_action, 'not classified (decided before ' || 'calendar-v3)') k, count(*) n from d where d.provider_id = u.id group by 1) x),
    'reasons', (select coalesce(jsonb_agg(jsonb_build_object('next_action', next_action, 'reason', reason, 'rows', n) order by n desc), '[]'::jsonb)
                  from (select d.next_action, coalesce(d.reason, d.outcome) reason, count(*) n from d where d.provider_id = u.id and d.outcome <> 'filled' group by 1, 2) x),
    'never_examined', (select count(*) from i where i.provider_id = u.id and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
                         and not exists (select 1 from pipeline.course_intake_dates d2 where d2.intake_id = i.id)),
    'last_attempt', (select max(d.applied_at) from d where d.provider_id = u.id),
    'next_revisit', (select min(d.next_revisit_at) from d where d.provider_id = u.id and d.next_revisit_at is not null),
    'waiting_for_change_only', (select count(*) from d where d.provider_id = u.id and d.next_revisit_at is null and coalesce(d.next_action, '') not in ('complete')),
    'admitted_7_days', (select jsonb_build_object('year', count(*) filter (where e.before_value->>'year' is null and e.after_value->>'year' is not null),
                                                  'start_date', count(*) filter (where e.before_value->>'start_date' is null and e.after_value->>'start_date' is not null),
                                                  'application_deadline', count(*) filter (where e.before_value->>'application_deadline' is null and e.after_value->>'application_deadline' is not null))
                          from pipeline.course_intake_date_events e where e.provider_id = u.id and e.outcome = 'filled'
                           and e.run_at > now() - make_interval(days => security.pipeline_num_v1('process_results.window_days', 7)::int)),
    'calendar_reread', (select coalesce(jsonb_object_agg(s.state, s.n), '{}'::jsonb) from (select s.state, count(*) n from pipeline.calendar_reread_state s where s.provider_id = u.id group by 1) s),
    'reader_findings_open', (select count(*) from pipeline.calendar_reader_findings f where f.provider_id = u.id and f.resolved_at is null),
    'ai_cost_usd_7_days', (select coalesce(sum(q.cost_usd), 0) from pipeline.central_ai_queue q where q.provider_id = u.id and q.kind = 'intake_calendar'
                             and q.created_at > now() - make_interval(days => security.pipeline_num_v1('process_results.window_days', 7)::int)),
    'firecrawl_credits', 0
  ) order by u.active desc) into v_per from u;
  v_job := jsonb_build_object(
    'intake_dates_apply', (select jsonb_build_object('schedule', j.schedule, 'active', j.active,
        'last_run', (select jsonb_build_object('at', r.start_time, 'status', r.status, 'message', left(r.return_message, 300)) from cron.job_run_details r where r.jobid = j.jobid order by r.start_time desc limit 1),
        'last_success', (select max(r.start_time) from cron.job_run_details r where r.jobid = j.jobid and r.status = 'succeeded'))
      from cron.job j where j.jobname = 'intake-dates-apply'),
    'calendar_reread', (select jsonb_build_object('schedule', j.schedule, 'active', j.active,
        'last_run', (select jsonb_build_object('at', r.start_time, 'status', r.status) from cron.job_run_details r where r.jobid = j.jobid order by r.start_time desc limit 1))
      from cron.job j where j.jobname = 'calendar-reread'),
    'enabled', coalesce((security.toolset_setting('pipeline', 'intake_dates.apply_enabled') #>> '{}')::boolean, false),
    'batch', security.pipeline_num_v1('batch.intake_dates_apply', 200),
    'month_unique_match', security.pipeline_num_v1('intake_dates.month_unique_match', 0),
    'revisit_days', security.pipeline_num_v1('intake_dates.revisit_days', 14));
  return jsonb_build_object('process', 'intake-dates', 'scope', 'top-au', 'measured_at', now(), 'universities', coalesce(v_per, '[]'::jsonb), 'jobs', v_job,
    'totals', jsonb_build_object(
      'active_courses', (select sum((x->>'active_courses')::int) from jsonb_array_elements(v_per) x),
      'courses_with_intakes', (select sum((x->>'courses_with_intakes')::int) from jsonb_array_elements(v_per) x),
      'course_pages_stored', (select sum((x->>'course_pages_stored')::int) from jsonb_array_elements(v_per) x),
      'calendars_valid', (select sum((x->>'calendars_valid')::int) from jsonb_array_elements(v_per) x),
      'future_periods', (select sum((x->>'future_periods')::int) from jsonb_array_elements(v_per) x),
      'intake_rows', (select sum((x->>'intake_rows')::int) from jsonb_array_elements(v_per) x),
      'held_year', (select sum((x->'held'->>'year')::int) from jsonb_array_elements(v_per) x),
      'held_start_date', (select sum((x->'held'->>'start_date')::int) from jsonb_array_elements(v_per) x),
      'held_application_deadline', (select sum((x->'held'->>'application_deadline')::int) from jsonb_array_elements(v_per) x),
      'website_start_date', (select sum((x->'in_website_source'->>'start_date')::int) from jsonb_array_elements(v_per) x),
      'never_examined', (select sum((x->>'never_examined')::int) from jsonb_array_elements(v_per) x)));
end $function$;
comment on function security.process_results_intake_dates_v1() is 'CF-247 process accountability (decision 5 Nov 2026 §6, §10): the intake dates process for the top Australian universities, measured from saved results: eligible courses, stored pages, valid and set-aside calendars, calendar year and freshness, future periods and deadlines, held values, values in the Website API source, outcomes by next action and reason, never examined, last attempt, next revisit, admitted in the window, calendar re-read state, reader findings, AI cost; and the jobs. Read only.';

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'process_results.window_days', 'Process results: admitted and cost window', 'Values admitted and AI cost counted over this many days in a process measurement.',
  'number', to_jsonb(7), 1, 90, 'days', 1004, 'Process results', 'security.process_results_intake_dates_v1', 'Platform Admin decision 5 Nov 2026 §10')
on conflict (toolset_key, key) do nothing;

create or replace function security.process_results_markdown_v1(p_summary jsonb) returns text
language sql immutable as $function$
  select '# Process record: intake dates (generated)' || E'\n\n' ||
    '**Measured:** ' || to_char((p_summary->>'measured_at')::timestamptz at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI') || ' AEDT. Scope: top Australian universities by active courses. Generated by security.process_results_markdown_v1 from pipeline.process_results; the hand-written design and history are in the process record.' || E'\n\n' ||
    '| University | Active courses | Course pages stored | Valid calendars (set aside) | Future periods | Intake rows | With year | With start date | With deadline | Start dates in Website source | Never examined | Next revisit |' || E'\n' ||
    '|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---|' || E'\n' ||
    coalesce((select string_agg('| ' || (x->>'university') || ' | ' || (x->>'active_courses') || ' | ' || (x->>'course_pages_stored') || ' | ' || (x->>'calendars_valid') || ' (' || jsonb_array_length(x->'calendars_set_aside') || ') | ' ||
                                (x->>'future_periods') || ' | ' || (x->>'intake_rows') || ' | ' || (x->'held'->>'year') || ' | ' || (x->'held'->>'start_date') || ' | ' || (x->'held'->>'application_deadline') || ' | ' ||
                                (x->'in_website_source'->>'start_date') || ' | ' || (x->>'never_examined') || ' | ' ||
                                coalesce(to_char((x->>'next_revisit')::timestamptz at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'), 'on change') || ' |', E'\n')
              from jsonb_array_elements(p_summary->'universities') x), '') || E'\n\n## What was missed, and why\n\n' ||
    coalesce((select string_agg('### ' || (x->>'university') || E'\n\n' ||
               coalesce((select string_agg('- ' || coalesce(y->>'next_action', 'not classified') || ': ' || (y->>'reason') || ' (' || (y->>'rows') || ')', E'\n')
                          from (select y from jsonb_array_elements(x->'reasons') y limit 8) z), '- nothing held') ||
               coalesce(E'\n- calendars set aside: ' || nullif((select string_agg((c->>'url') || ' (' || (c->>'scope') || ')', '; ') from jsonb_array_elements(x->'calendars_set_aside') c), ''), ''), E'\n\n')
              from jsonb_array_elements(p_summary->'universities') x), '') || E'\n'
$function$;
comment on function security.process_results_markdown_v1(jsonb) is 'CF-247 (decision 5 Nov 2026 §5): the intake dates process measurement as markdown for the repository (process-results workflow).';

create or replace function security.process_results_record_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v jsonb := security.process_results_intake_dates_v1(); v_id bigint; v_flags int := 0; x jsonb;
begin
  insert into pipeline.process_results(process_key, scope_key, measured_at, summary, markdown, measured_by)
  values ('intake-dates', 'top-au', now(), v, security.process_results_markdown_v1(v), coalesce(auth.uid()::text, 'job process-results'))
  returning id into v_id;
  -- decision §11: the observer routes a university whose calendars are set aside or give no future start to a person (existing flags)
  for x in select * from jsonb_array_elements(v->'universities') loop
    if (x->>'calendars_valid')::int = 0 or (x->>'future_periods')::int = 0 then
      insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source, evidence)
      values ('provider', x->>'provider_id', (x->>'provider_id')::uuid, 'intake_calendar', 'calendar_needs_correction',
              format('%s: intake dates need a current main teaching calendar: %s valid, %s set aside, %s future study periods. Next action: approve the correct official calendar (Adapter builder, central pages) or check the calendar reader findings.',
                     x->>'university', x->>'calendars_valid', jsonb_array_length(x->'calendars_set_aside'), x->>'future_periods'),
              'process-results', jsonb_build_object('set_aside', x->'calendars_set_aside', 'reread', x->'calendar_reread', 'process_result_id', v_id))
      on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, evidence = excluded.evidence, flagged_at = now(), cleared_at = null;
      v_flags := v_flags + 1;
    else
      update pipeline.enrichment_flags set cleared_at = now() where entity = 'provider' and entity_key = x->>'provider_id' and field = 'intake_calendar'
         and reason_code = 'calendar_needs_correction' and cleared_at is null;
    end if;
  end loop;
  return jsonb_build_object('id', v_id, 'flags', v_flags, 'totals', v->'totals');
end $function$;
comment on function security.process_results_record_v1() is 'CF-247 (decision 5 Nov 2026 §5, §11): records a dated measurement of the intake dates process (job process-results) and routes universities without a usable calendar to a person through the existing flags; nothing earlier is overwritten.';

create or replace function public.admin_process_results_v1(p_view text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_rank int := security.current_role_rank(); v_pid uuid; v_rows int := security.pipeline_num_v1('process_results.validation_rows', 25)::int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Operations read permission required' using errcode = '42501'; end if;
  if p_view = 'latest' then
    return (select jsonb_build_object('id', r.id, 'measured_at', r.measured_at, 'measured_by', r.measured_by, 'summary', r.summary)
              from pipeline.process_results r where r.process_key = coalesce(p_args->>'process', 'intake-dates') order by r.measured_at desc limit 1);
  elsif p_view = 'history' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'measured_at', r.measured_at, 'measured_by', r.measured_by, 'totals', r.summary->'totals') order by r.measured_at desc), '[]'::jsonb)
              from (select * from pipeline.process_results r where r.process_key = coalesce(p_args->>'process', 'intake-dates') order by r.measured_at desc
                     limit security.pipeline_num_v1('process_results.history_rows', 30)::int) r);
  elsif p_view = 'measure' then
    if v_rank < 4 then raise exception 'Operator permission required to measure' using errcode = '42501'; end if;
    return security.process_results_record_v1();
  elsif p_view = 'university' then
    v_pid := (p_args->>'provider_id')::uuid;
    if not exists (select 1 from jsonb_array_elements(security.intake_ui_scopes_v1()) e where (e->>'id')::uuid = v_pid) then raise exception 'not a university in this process scope' using errcode = '22023'; end if;
    return jsonb_build_object(
      'calendars', (select coalesce(jsonb_agg(jsonb_build_object('proposal_id', s.proposal_id, 'url', s.url, 'evidence_id', s.evidence_id, 'parser', s.parser, 'decided_at', s.decided_at,
                      'scope', s.scope, 'used', s.used, 'set_aside_reason', s.set_aside_reason,
                      'starts', (select coalesce(jsonb_agg(jsonb_build_object('period', d.period, 'date', d.on_date, 'year', d.year, 'month', d.month, 'quote', d.quote) order by d.year, d.month), '[]'::jsonb)
                                   from security.calendar_proposal_dates_v1(s.proposal_id) d where d.kind = 'start'),
                      'deadlines', (select coalesce(jsonb_agg(jsonb_build_object('period', d.period, 'date', d.on_date, 'applies_to', d.applies_to, 'quote', d.quote)), '[]'::jsonb)
                                      from security.calendar_proposal_dates_v1(s.proposal_id) d where d.kind = 'deadline'))), '[]'::jsonb)
                    from security.calendar_sources_v1(v_pid) s),
      'reread', (select coalesce(jsonb_agg(jsonb_build_object('url', f.url, 'state', s.state, 'reason', s.reason, 'reader', s.reader, 'last_at', s.last_at, 'summary', s.parser_summary)), '[]'::jsonb)
                   from pipeline.calendar_reread_state s join pipeline.provider_fact_sources f on f.id = s.fact_source_id where s.provider_id = v_pid),
      'findings', (select coalesce(jsonb_agg(jsonb_build_object('code', f.code, 'detail', f.detail, 'example', f.example, 'times', f.times, 'last_seen', f.last_seen) order by f.last_seen desc), '[]'::jsonb)
                     from pipeline.calendar_reader_findings f where f.provider_id = v_pid and f.resolved_at is null),
      'flags', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'reason', g.reason, 'flagged_at', g.flagged_at)), '[]'::jsonb)
                  from pipeline.enrichment_flags g where g.provider_id = v_pid and g.field = 'intake_calendar' and g.cleared_at is null),
      'recent', (select coalesce(jsonb_agg(x order by x->>'run_at' desc), '[]'::jsonb) from (
                   select jsonb_build_object('run_at', e.run_at, 'course_id', e.course_id, 'course_title', coalesce(c.display_title, c.canonical_title), 'course_url', c.course_url,
                     'outcome', e.outcome, 'reason', e.reason, 'next_action', e.next_action, 'next_revisit_at', e.next_revisit_at, 'rule', e.rule,
                     'before', e.before_value, 'after', e.after_value, 'page_quote', e.page_quote, 'start_quote', e.start_quote, 'deadline_quote', e.deadline_quote,
                     'calendar_url', e.calendar_url, 'calendar_evidence_id', e.calendar_evidence_id, 'bounded', e.bounded) x
                     from pipeline.course_intake_date_events e join catalogue.courses c on c.id = e.course_id
                    where e.provider_id = v_pid and (p_args->>'outcome' is null or e.outcome = p_args->>'outcome')
                    order by e.run_at desc limit v_rows) y));
  end if;
  raise exception 'unknown view %', p_view using errcode = '22023';
end $function$;
comment on function public.admin_process_results_v1(text, jsonb) is 'CF-247 (decision 5 Nov 2026 §6): Layer 2/3 Operations › Process results: the latest and earlier measurements, a measurement on request (Operators), and one university''s calendars (with documents, scope, dated starts and deadlines), re-read state, reader findings, flags and recent decisions with their evidence. Saved results only.';
revoke all on function public.admin_process_results_v1(text, jsonb) from public, anon;
grant execute on function public.admin_process_results_v1(text, jsonb) to authenticated;

-- jobs (G1) -----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('calendar-reread', 'Admission', 66, 'Calendar re-read (stored documents)',
  'Hourly at :13: reads stored academic calendar documents again with the current calendar reader, at most Calendar re-read: documents a run (20), focus universities first. The dated parser first; the pinned central-page model (central-ai queue) only when the parser gives no current or future dated teaching start or the address is not trusted. No Firecrawl. A document is read again only when it or the reader changes (decision 5 Nov 2026 §2, §7).', 5, true),
 ('process-results', 'Admission', 67, 'Process results (intake dates)',
  'Hourly at :53: records a dated measurement of the intake dates process for the top Australian universities (pipeline.process_results) and routes universities without a usable calendar to a person through the existing flags. Read and record only (decision 5 Nov 2026 §5, §11).', 5, false)
on conflict (jobname) do nothing;
select cron.schedule('calendar-reread', '13 * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'calendar_reread', 'limit', security.pipeline_num_v1('batch.calendar_reread', 20)::int))$c$);
select cron.schedule('process-results', '53 * * * *', 'select security.process_results_record_v1()');

-- component register (housekeeping) ------------------------------------------------------------------------------------------------------
update pipeline.component_register set status = 'retiring', replaced_by = 'security.intake_dates_plan_v3', retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, updated_at = now()
 where kind = 'function' and name = 'security.intake_dates_plan_v2';
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.intake_dates_plan_v3', 'Layer 2', 'Admission', 'Intake dates plan: every main teaching calendar, unique-month rule, next action and revisit', 'active', array['security.intake_dates_plan_v2'], '20261105020000'),
 ('table', 'pipeline.course_intake_date_events', 'Layer 2', 'Admission', 'Every intake date decision, appended', 'active', '{}', '20261105020000'),
 ('table', 'pipeline.calendar_reread_state', 'Layer 2', 'Admission', 'Stored calendar documents read again by the current reader', 'active', '{}', '20261105020000'),
 ('table', 'pipeline.calendar_reader_findings', 'Layer 2', 'Admission', 'What the calendar reader could not take; notes for the next read', 'active', '{}', '20261105020000'),
 ('table', 'pipeline.process_results', 'Platform', 'Operations', 'Dated measurements of production processes', 'active', '{}', '20261105020000'),
 ('job', 'calendar-reread', 'Layer 2', 'Admission', 'Re-read stored calendars with the current reader', 'active', '{}', '20261105020000'),
 ('job', 'process-results', 'Platform', 'Operations', 'Measure and record the intake dates process', 'active', '{}', '20261105020000')
on conflict (kind, name) do nothing;
