-- CF-247 s1296 (S2-AER; SS-Programme-Control 27 Nov 2026 11:27 AEDT, "Complete Autonomous AER Reader Selection and Admission").
-- Read live 27 Nov 2026 12:10 AEDT:
--   * 171 scheduled reads in 7 days read 25 courses: 150 runs were stopped by the entry-requirements AI route being switched off (Models & services; a protected
--     control, 19 Nov to 26 Nov 21:13), the route has been open since, and the eligible pool is about empty (0 to 2 courses a run).
--   * 15,532 courses are in the pool; 10,384 hold an entry row; of the 5,148 that hold none (and wait for no Layer 4 decision) 2,712 were never actually read (a Layer 4
--     item superseded by the deterministic re-read 1,410, "no proven course page" 1,071, D-R2 not read 222), 2,348 were read and gave no result, 84 hit the row limit.
--     The selector held all of them behind one flat timer (aer.schedule_retry_days, 30): any enrich item, read or not, kept a course out of the pool for 30 days.
--   * The platform's own rule ("an unchanged copy, reader and settings are never read again; a change makes it eligible", security.aer_recovery_rule_v1,
--     layer4.reread_change_keys) works on waiting Layer 4 items only; the scheduled selector, the E13 pilot and the knowledge in pipeline.ops_remedy_knowledge
--     (ops_learning_retry_check_v1) were not joined to it.
--   * The E13 recovery pilot total (aer.e13_recover_total_max 1,000) was used up on 19 Nov by asks, not reads: 120 reads replaced a held read, 306 asks met the AI route
--     switched off (a protected control), 172 found the item already superseded or another read waiting, and 402 were genuine reads that were refused as still incomplete.
-- What it changes (no new table, job, queue, reader or spend):
--   1. security.aer_first_read_state_v1 (read only): the one rule for the next read of a course with no entry row. A last outcome that was not a read (superseded, unproven
--      page, D-R2 not read, an AI refusal) is read again after aer.schedule_technical_retry_hours. A read that gave no result is read again only when its stored copy changed
--      (or, for "no quoted requirement" / "no row met the rules", the reader changed: aer.read_again_change_keys). A read cut at the row limit waits for a higher limit. An
--      earlier incomplete read is read again only when every item it dropped was a domestic cut-off statistic (worker v1.0.55 no longer holds a read for those); any other
--      drop needs a reader for that structure and is reported, not repeated. The deterministic reader goes first: the AI reader reads a course only when the deterministic
--      reader's outcome on the same copy is one of aer.ai_after_det_outcomes (no reading, no row) or absent. Recorded failures of the same copy are honoured through
--      security.ops_learning_retry_check_v1.
--   2. security.aer_schedule_courses_v1 selects from that rule (same columns). aer.schedule_retry_days stays for outcomes the rule does not classify.
--   3. security.aer_schedule_tick_v1: each run is clamped to the part of the day's paid cap (budgets.paid_daily_cap_usd x aer.schedule_paid_share) still unspent, counted
--      from the AI spend ledger; the run records what it spent, and records the outcomes of the reads that finished (security.aer_first_read_learn_v1) through
--      ops_learning_record_v1, once per copy and reader.
--   4. security.aer_e13_recover_v1: the pilot total and the daily allowance count reads made, not asks that never reached a read (aer.e13_not_read_pattern).
--   5. Two recovery patterns are seeded in pipeline.ops_remedy_knowledge (the same table S1-Build's s1292 extends), with their conditions and the structures needing a reader.
-- G1: no job. G2: new values are settings with label, range, unit and used_by; the constants below are marked fixed. G3: 75/48 checked. Locks: unchanged, checked.
-- Nothing dropped or deleted. Consumers: no change to what the Website or Zoho read (the read order of courses changes; no row is written here).
-- Replaces: the flat read-again timer in security.aer_schedule_courses_v1 (aer.schedule_retry_days, now only for unclassified outcomes) and the E13 pilot's count of unread asks. Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function and setting writes

create temp table s1296_guard on commit drop as select (select count(*) from pipeline.manual_locks) locks_before;
create temp table s1296_cron on commit drop as select jobid from cron.job;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v; end if;
  if to_regprocedure('security.aer_course_population_v1(uuid)') is null or to_regprocedure('security.ops_learning_retry_check_v1(text,text,text)') is null
     or to_regprocedure('security.ops_learning_record_v1(jsonb)') is null or to_regprocedure('security.ai_spend_today_v1()') is null
     or to_regprocedure('security.aer_e13_class_v1(jsonb)') is null or to_regprocedure('security.course_entry_max_rows_v1(uuid)') is null then
    raise exception 'guard: a function this change reads is missing';
  end if;
end $g$;

-- 1. settings (G2)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'aer.not_a_read_pattern', 'Entry requirements: outcomes that were not a read',
  'A course whose latest entry read ended with a reason matching this pattern (case-insensitive) was not read: its Layer 4 item was superseded, the page was not proved to be its own, a corrected read was not made, or no answer could be recorded. It is read again after the technical retry hours, not after the long read-again days.',
  'text', to_jsonb('^Layer 4 superseded|^no proven course page|^corrected read \(D-R2\) not read|^corrected read refused \(D-R2\)|^no answer could be recorded'::text), null, null, 'pattern', 1150,
  'CF-247 s1296: an outcome that was not a read does not wait for the read-again interval', 'Entry requirements', 'security.aer_first_read_state_v1'),
 ('pipeline', 'aer.no_result_pattern', 'Entry requirements: reads that found nothing on the page',
  'A read that ended with a reason matching this pattern found no requirement on the stored copy. It is read again only when the stored copy changes.',
  'text', to_jsonb('does not state it'::text), null, null, 'pattern', 1151,
  'CF-247 s1296: never repeat an identical unsuccessful read (Platform Admin 4 Nov 2026 12:24 §1)', 'Entry requirements', 'security.aer_first_read_state_v1'),
 ('pipeline', 'aer.no_result_reader_pattern', 'Entry requirements: reads that gave no row for a reason the reader can change',
  'A read that ended with a reason matching this pattern (no quoted requirement, no row met the admission rules) is read again when the stored copy changes or when a setting in aer.read_again_change_keys changes.',
  'text', to_jsonb('no quoted requirement|no row met the admission'::text), null, null, 'pattern', 1152,
  'CF-247 s1296: a reader change can make a read that gave no row eligible; an unchanged reader and copy cannot', 'Entry requirements', 'security.aer_first_read_state_v1'),
 ('pipeline', 'aer.page_limit_pattern', 'Entry requirements: reads stopped by the length of the page',
  'A read that failed because the stored page is longer than the reader takes is read again only when the stored copy changes.',
  'text', to_jsonb('^held_partial: page text'::text), null, null, 'pattern', 1153,
  'CF-247 s1296: a page the reader cannot take stays unread until the copy changes', 'Entry requirements', 'security.aer_first_read_state_v1'),
 ('pipeline', 'aer.read_again_change_keys', 'Entry requirements: settings that make a read that gave no row eligible again',
  'When any setting matching these keys (SQL LIKE) changes after a read that gave no row, the course is read again. Use only settings that change what the reader returns.',
  'list', '["layer4.reader_revision"]'::jsonb, null, null, 'setting keys', 1154,
  'CF-247 s1296: the reader revision is the platform''s own signal that the reader changed', 'Entry requirements', 'security.aer_first_read_state_v1'),
 ('pipeline', 'aer.ai_after_det_outcomes', 'Entry requirements: deterministic outcomes after which the AI reader reads a course',
  'The deterministic reader (aer-det) reads a stored copy first at no cost. The AI reader reads the course when the deterministic outcome on the same copy is one of these, or when there is none. Any other outcome (rows proposed, a shared page, another programme, a row limit, not admitted) is not a reading problem and is not repeated by the AI reader.',
  'list', '["no_reading", "no_row"]'::jsonb, null, null, 'outcomes', 1155,
  'CF-247 s1296: reader selection from the existing deterministic outcomes', 'Entry requirements', 'security.aer_first_read_state_v1'),
 ('pipeline', 'aer.domestic_statistic_pattern', 'Entry requirements: domestic cut-off statistic words',
  'An earlier incomplete read is read again when every item it dropped is a domestic cut-off statistic: it matches this pattern (PostgreSQL word boundaries) and not aer.domestic_statistic_exclude. The reader (v1.0.55) no longer holds a read for such a drop.',
  'text', to_jsonb('\m(median|lowest|highest|cut.?off|entry score range)\M'::text), null, null, 'pattern', 1156,
  'CF-247 s1296: the same words as the reader (course-entry.ts ENTRY_DOMESTIC_STATISTIC)', 'Entry requirements', 'security.aer_first_read_state_v1'),
 ('pipeline', 'aer.domestic_statistic_exclude', 'Entry requirements: words that keep a drop from being a domestic statistic',
  'A dropped quote naming one of these (international, overseas, an English test, a visa, an "or equivalent" route open to everyone, or a requirement word such as must, minimum or at least) is never treated as a domestic statistic.',
  'text', to_jsonb('\m(international|overseas|ielts|toefl|pte|visa|must|required?|requires|need|minimum|at least|should|eligible|apply)\M|\mor (an |any )?equivalent'::text), null, null, 'pattern', 1157,
  'CF-247 s1296: the same words as the reader (course-entry.ts ENTRY_DOMESTIC_STATISTIC_EXCLUDE, s1280 equivalent route)', 'Entry requirements', 'security.aer_first_read_state_v1'),
 ('pipeline', 'aer.schedule_technical_retry_hours', 'Scheduled entry reading: read a course again after an outcome that was not a read',
  'A course whose last outcome was not a read (see the outcomes that were not a read) is not asked again for this many hours, so a repeating technical fault cannot spend on every run.',
  'number', '24'::jsonb, 1, 720, 'hours', 1158,
  'CF-247 s1296: spaced retries for outcomes that were not a read', 'Entry requirements', 'security.aer_first_read_state_v1'),
 ('pipeline', 'aer.schedule_paid_share', 'Scheduled entry reading: share of the day''s paid cap it may use',
  'Each hourly run asks for no more courses than this share of the daily paid cap (Paid spend: platform cap a day) still allows, counted from today''s AI spend on the entry-reading lane, and never more than the cap leaves across all lanes.',
  'number', '0.6'::jsonb, 0, 1, 'share of the cap', 1159,
  'CF-247 s1296: Standing Authority Charter 23 Nov 2026 §2, each lane checks the day''s spend before a paid call', 'Entry requirements', 'security.aer_schedule_tick_v1'),
 ('pipeline', 'aer.e13_not_read_pattern', 'Entry requirements: E13 recovery asks that were not a read',
  'An E13 recovery ask whose recorded outcome matches this pattern never reached a read (the AI route was switched off, the item was already superseded, or another read waited). It does not count against the pilot total or the daily allowance.',
  'text', to_jsonb('AI route is switched off|no longer waits|another read of this course waits|Layer 4 item is no lo|no proven course page'::text), null, null, 'pattern', 1160,
  'CF-247 s1296: the pilot total counts reads made', 'Entry requirements', 'security.aer_e13_recover_v1')
on conflict (toolset_key, key) do nothing;

-- 2. the one rule for the next read of a course with no entry row (read only)
create or replace function security.aer_first_read_state_v1(p_provider uuid default null)
returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier integer, title text, read_class text, eligible boolean, why text, signature text)
language sql stable security definer set search_path = ''
as $f$
  with s as (
    select coalesce(security.toolset_setting('pipeline', 'aer.retry_now_error_pattern') #>> '{}', '') refused,
           coalesce(security.toolset_setting('pipeline', 'aer.not_a_read_pattern') #>> '{}', '') notread,
           coalesce(security.toolset_setting('pipeline', 'aer.no_result_pattern') #>> '{}', '') noresult,
           coalesce(security.toolset_setting('pipeline', 'aer.no_result_reader_pattern') #>> '{}', '') noreader,
           coalesce(security.toolset_setting('pipeline', 'aer.page_limit_pattern') #>> '{}', '') pagelimit,
           coalesce(security.toolset_setting('pipeline', 'aer.domestic_statistic_pattern') #>> '{}', '') dom,
           coalesce(security.toolset_setting('pipeline', 'aer.domestic_statistic_exclude') #>> '{}', '') domx,
           coalesce(security.toolset_setting('pipeline', 'aer.ai_after_det_outcomes'), '["no_reading", "no_row"]'::jsonb) detok,
           make_interval(hours => security.pipeline_num_v1('aer.schedule_technical_retry_hours', 24)::int) tech,
           make_interval(days => security.pipeline_num_v1('aer.schedule_retry_days', 30)::int) retry,
           security.pipeline_num_v1('layer4.reader_revision', 1)::text rev,
           (select max(t.updated_at) from pipeline.platform_toolset_settings t
             where t.toolset_key = 'pipeline'
               and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.read_again_change_keys'), '["layer4.reader_revision"]'::jsonb)) k where t.key like k)) changed_at,
           (select a.extractor from pipeline.aer_det_academic_pages a order by a.read_at desc nulls last limit 1) det_ext),
  c as (select p.* from security.aer_course_population_v1(p_provider) p
         where not exists (select 1 from catalogue.course_entry_requirements x where x.course_id = p.course_id and x.status in ('active', 'proposed'))
           and not exists (select 1 from pipeline.layer4_review_items r where r.entity_id = p.course_id and r.field_code = 'course_entry_first_read' and r.status = 'pending')),
  l as (select c.*, f.state last_state, coalesce(f.reason, '') last_reason, f.updated_at last_at, f.evidence_id last_ev, f.value last_value,
               g.evidence_id bound_ev,
               (select a.outcome from pipeline.aer_det_academic_pages a, s where a.course_id = c.course_id and a.evidence_id = g.evidence_id and a.extractor = s.det_ext
                 order by a.read_at desc nulls last limit 1) det,
               (select x.gate from pipeline.layer4_review_items r join pipeline.layer4_item_readiness x on x.item_id = r.id
                 where r.entity_id = c.course_id and r.field_code = 'course_entry_first_read' and r.status = 'superseded' order by r.decided_at desc nulls last limit 1) gate
          from c
          left join lateral (select * from pipeline.field_enrich_items f where f.course_id = c.course_id and f.field = 'entry_requirements' order by f.updated_at desc, f.id desc limit 1) f on true
          left join lateral (select pg.evidence_id from pipeline.coverage_course_pages pg where pg.course_id = c.course_id and pg.status = 'bound' order by pg.bound_at desc nulls last limit 1) g on true),
  k as (select l.*, s.tech, s.retry, s.changed_at, s.detok, s.rev, s.dom, s.domx,
               case
                 when l.last_state in ('queued', 'waiting', 'ai', 'leased', 'review') then 'in_progress'
                 when l.last_state is null then 'never_read'
                 when s.pagelimit <> '' and l.last_reason ~* s.pagelimit then 'page_limit'
                 when l.last_reason ~* '^held_partial: over_row_limit' then 'row_limit'
                 when s.noresult <> '' and l.last_reason ~* s.noresult then 'read_no_result'
                 when s.noreader <> '' and l.last_reason ~* s.noreader then 'read_no_row'
                 when l.last_reason like 'Layer 4 superseded%' and l.gate is not null and security.aer_e13_class_v1(l.gate) is not null then 'incomplete_read'
                 when (s.notread <> '' and l.last_reason ~* s.notread) or (s.refused <> '' and l.last_reason ~* s.refused) then 'not_a_read'
                 else 'other' end read_class
          from l cross join s),
  d as (select k.*,
               (k.last_ev is distinct from k.bound_ev) copy_changed,
               md5(coalesce(k.bound_ev::text, '-') || ':' || k.rev) sig,
               case when k.read_class = 'incomplete_read' then
                      case when security.aer_e13_class_v1(k.gate) = 'drops_uncovered'
                                and jsonb_array_length(coalesce(k.gate->'drops_uncovered', '[]'::jsonb)) > 0
                                and not exists (select 1 from jsonb_array_elements(k.gate->'drops_uncovered') x
                                                 where not (x->>'reason' = 'quote_not_on_page' and k.dom <> '' and coalesce(x->>'quote', '') ~* k.dom
                                                            and not (k.domx <> '' and coalesce(x->>'quote', '') ~* k.domx)))
                           then 'domestic_only' else 'other_drops' end end drops
          from k)
  select d.course_id, d.provider_id, d.country, d.provider_name, d.tier, d.title, d.read_class,
         ((case
            when d.read_class = 'in_progress' then false
            when d.det is not null and not (d.detok ? d.det) then false  -- reader selection: the deterministic reader's outcome on this copy is not a reading problem
            when d.read_class = 'never_read' then true
            when d.read_class = 'not_a_read' then d.last_at < now() - d.tech
            when d.read_class = 'incomplete_read' then d.copy_changed or (d.drops = 'domestic_only' and d.last_at < now() - d.tech)
            when d.read_class in ('read_no_result', 'page_limit') then d.copy_changed
            when d.read_class = 'read_no_row' then d.copy_changed or d.changed_at > d.last_at
            when d.read_class = 'row_limit' then d.copy_changed or coalesce(security.course_entry_max_rows_v1(d.provider_id), 0) > coalesce((d.last_value->>'limit')::int, 0)
            else d.last_at < now() - d.retry end)
         and coalesce((security.ops_learning_retry_check_v1('aer_first_read:unchanged_copy_no_result', d.course_id::text, d.sig)->>'allowed')::boolean, true)
         and not (d.det is not null and not (d.detok ? d.det))) as eligible,
         case
           when d.read_class = 'in_progress' then 'a read of this course is in progress'
           when d.det is not null and not (d.detok ? d.det) then 'the deterministic reader''s outcome on this copy is ' || d.det || ': not a reading problem for the AI reader'
           when d.read_class = 'never_read' then 'never read'
           when d.read_class = 'not_a_read' then case when d.last_at < now() - d.tech then 'the last outcome was not a read: ' || left(d.last_reason, 80) else 'the last outcome was not a read, asked less than the technical retry hours ago' end
           when d.read_class = 'incomplete_read' then case when d.copy_changed then 'the stored copy changed since the incomplete read'
                                                           when d.drops = 'domestic_only' then 'the incomplete read dropped only domestic cut-off statistics, which the reader no longer holds a read for'
                                                           else 'the incomplete read dropped printed requirements that are not domestic statistics (' || coalesce(security.aer_e13_class_v1(d.gate), 'incomplete') || '): the same reader would drop them again; a reader for this structure is needed' end
           when d.read_class in ('read_no_result', 'page_limit') then case when d.copy_changed then 'the stored copy changed since the read' else 'unchanged copy: the same read would give the same result (' || left(d.last_reason, 60) || ')' end
           when d.read_class = 'read_no_row' then case when d.copy_changed then 'the stored copy changed since the read' when d.changed_at > d.last_at then 'the reader changed since the read' else 'unchanged copy and reader: the same read would give the same result (' || left(d.last_reason, 60) || ')' end
           when d.read_class = 'row_limit' then case when d.copy_changed then 'the stored copy changed since the read' when coalesce(security.course_entry_max_rows_v1(d.provider_id), 0) > coalesce((d.last_value->>'limit')::int, 0) then 'the row limit rose' else 'the page has more requirements than the row limit; a limit for this university is the Platform Admin''s to set' end
           else 'read again after the read-again days' end why,
         d.sig signature
    from d
$f$;
comment on function security.aer_first_read_state_v1(uuid) is 'CF-247 s1296: the one rule for the next read of a course with no entry row (class, eligibility, reason, signature). Read only.';

-- 3. the selector reads the one rule (same columns as before)
create or replace function security.aer_schedule_courses_v1(p_limit integer, p_all boolean, p_provider uuid)
returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier integer, turn bigint)
language sql stable security definer set search_path = ''
as $f$
  with s as (select security.pipeline_num_v1('aer.schedule_per_provider', 5) per),
  c as (select x.* from security.aer_first_read_state_v1(p_provider) x where x.eligible),  -- s1296: the one rule (copy, reader, outcome that was not a read, deterministic outcome)
  r as (select c.*, row_number() over (partition by c.provider_id order by c.title, c.course_id) turn from c)
  select r.course_id, r.provider_id, r.country, r.provider_name, r.tier, r.turn
    from r cross join s
   where p_all or r.turn <= s.per
   order by r.turn, r.tier, r.provider_name, r.provider_id
   limit p_limit
$f$;

-- 4. outcomes of the reads that finished, recorded once per copy and reader (the existing recovery knowledge)
create or replace function security.aer_first_read_learn_v1()
returns jsonb
language plpgsql security definer set search_path = ''
as $f$
declare v_rev text := security.pipeline_num_v1('layer4.reader_revision', 1)::text; v_n int := 0; r record;
        v_notread text := coalesce(security.toolset_setting('pipeline', 'aer.not_a_read_pattern') #>> '{}', '');
        v_refused text := coalesce(security.toolset_setting('pipeline', 'aer.retry_now_error_pattern') #>> '{}', '');
begin
  for r in
    select f.course_id, f.evidence_id, f.state, f.reason, md5(coalesce(f.evidence_id::text, '-') || ':' || v_rev) sig,
           exists (select 1 from catalogue.course_entry_requirements x where x.course_id = f.course_id and x.status in ('active', 'proposed')) has_rows
      from pipeline.field_enrich_items f
     where f.field = 'entry_requirements' and f.state in ('filled', 'skipped', 'review') and f.updated_at > now() - interval '3 hours'  -- fixed: a little more than the run interval
       and not ((v_notread <> '' and coalesce(f.reason, '') ~* v_notread) or (v_refused <> '' and coalesce(f.reason, '') ~* v_refused))
     order by f.updated_at desc limit 500  -- fixed: bounded work in one run
  loop
    continue when exists (select 1 from pipeline.ops_remedy_outcomes o where o.knowledge_code = 'aer_first_read:unchanged_copy_no_result' and o.entity = r.course_id::text and o.evidence_signature = r.sig);
    perform security.ops_learning_record_v1(jsonb_build_object('code', 'aer_first_read:unchanged_copy_no_result', 'entity', r.course_id::text, 'evidence_signature', r.sig,
      'performed_by', 'platform', 'success', r.has_rows or r.state in ('filled', 'review'), 'stage_advanced', r.has_rows or r.state in ('filled', 'review'),
      'expected', 'a first read of this copy gives rows, or is not repeated on the same copy and reader',
      'observed', jsonb_build_object('state', r.state, 'reason', left(coalesce(r.reason, ''), 120)), 'evidence', jsonb_build_object('evidence_id', r.evidence_id, 'reader_revision', v_rev)));
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('recorded', v_n);
end $f$;
comment on function security.aer_first_read_learn_v1() is 'CF-247 s1296: records the outcome of each first read that finished (once per copy and reader) in the existing recovery knowledge. Called by the aer-scheduled-read run.';

insert into pipeline.ops_remedy_knowledge (code, lane, title, fingerprint_like, root_cause, remedy_code, trigger_conditions, authority, performed_by, expected_outcome,
  no_retry_condition, reuse_conditions, auto_eligible, eligibility_reason, eligibility_changed_at, eligibility_changed_by, seeded_from)
values
  ('aer_first_read:unchanged_copy_no_result', 'aer', 'A first read of a stored copy that gave no result is not repeated on the same copy and reader',
   array['aer:first_read:%'], 'repeat_of_identical_read', null,
   '{"signal": "a course with no entry row whose latest read found nothing on the stored copy, or whose read was cut or held, and whose copy and reader have not changed"}'::jsonb,
   'auto', 'platform', 'the course waits until its stored copy or the reader changes; an outcome that was not a read (superseded, unproven page, AI refusal) is read again after the technical retry hours',
   'do not read the same stored copy again with the same reader: the result is the same and the read spends',
   'use security.aer_first_read_state_v1 (class, eligibility, reason) before reporting zero eligible reads; the AI reader follows the deterministic reader only when its outcome on the copy is no_reading or no_row',
   true, 'the platform applies it through the selector and records each outcome once per copy and reader', now(), 'S2-AER (s1296)', 's1296'),
  ('aer_first_read:incomplete_structure_needs_reader', 'aer', 'An incomplete first read whose dropped items are not domestic statistics needs a reader for that structure',
   array['aer:first_read:%'], 'unsupported_source_structure', 'engineering_remediation',
   '{"signal": "E13 drops_uncovered with reason quote_not_on_page: the quote the model gave is not contiguous on the page (a heading or label joined to a sentence, table cells joined, an ellipsis across passages, a paraphrase)"}'::jsonb,
   'release', 'claude_engineering', 'the structure has a reader that keeps each requirement with a quote that is on the page; the course is then read once under it',
   'do not re-run the first read or the corrected read (D-R2): 294 corrected reads of the same copies were refused as still incomplete (12 to 19 Nov)',
   'route the structure and its evidence to the shared reader creation and qualification lifecycle (S2-Build); a domestic cut-off statistic is not such a structure (worker v1.0.55)',
   false, 'engineering pattern (release authority): the reader cannot produce the quote the gate needs', now(), 'S2-AER (s1296)', 's1296, E13 pilot 12 to 19 Nov 2026')
on conflict (code) do nothing;

-- 5. the tick: the paid cap, and the outcomes of the reads that finished
create or replace function security.aer_schedule_tick_v1(p_preview boolean default false)
returns jsonb
language plpgsql security definer set search_path = ''
as $f$
declare v_batch int := security.pipeline_num_v1('batch.aer_schedule_courses', 20)::int;
        v_daymax int := security.pipeline_num_v1('aer.schedule_daily_max', 200)::int;
        v_heldmax int := security.pipeline_num_v1('batch.aer_schedule_held', 10)::int;
        v_l4max int := security.pipeline_num_v1('aer.schedule_layer4_max', 600)::int;
        v_mxmax int := security.pipeline_num_v1('batch.aer_schedule_matrix', 4)::int;
        v_cost numeric := security.course_entry_cost_v1(); v_owner uuid; v_used int; v_l4 int; v_prog int; v_bp boolean; v_room int;
        v_ai text; v_aim text; v_bal numeric; v_floor numeric; v_why text; v_reason text; v_orank int; v_orole text;
        r record; v_job uuid; v_res jsonb; v_held jsonb := '[]'::jsonb; v_new jsonb := '[]'::jsonb; v_mx jsonb := '[]'::jsonb; v_skip jsonb := '[]'::jsonb;
        v_checked jsonb := '[]'::jsonb; v_nh int := 0; v_nn int := 0; v_nm int := 0; v_fc int := 0; v_est numeric;
        v_fair boolean := security.pipeline_num_v1('wc.aer_fair_on', 0) >= 1; v_rr jsonb; v_tech jsonb; v_parked int := 0;
        -- 11 Nov 2026 (F-AER.02 self-healing): corrected reads have their own 24-hour allowance, apart from new reads
        v_cmax int := security.pipeline_num_v1('aer.schedule_correction_daily_max', 100)::int; v_cused int := 0; v_croom int := 0;
        -- s1296: the day's paid cap (Standing Authority Charter 23 Nov 2026 §2): each run asks for no more than the cap, and its share for this lane, still allow
        v_paid numeric := security.pipeline_num_v1('budgets.paid_daily_cap_usd', 5); v_share numeric := security.pipeline_num_v1('aer.schedule_paid_share', 0.6);
        v_spent_all numeric := 0; v_spent_lane numeric := 0; v_paid_room int := null; v_learn jsonb;
begin
  if not p_preview and not pg_try_advisory_xact_lock(hashtext('cf247:aer-scheduled-read')) then  -- fixed: one run at a time
    return jsonb_build_object('skipped', 'another run is in progress');
  end if;
  -- run-as (mandate 13:09 D6: only the identity and role permissions the platform already defines): the job runs as the database role cron uses,
  -- through these security-definer functions; each read is asked in the name of the owner of the platform's standing enrichment
  -- (pipeline.field_gap_queue_control.owner, Coverage › Attributes, Fill the gaps; the same owner the gap queue and enrichment plans use), and only
  -- while that owner holds an active, unexpired role at the rank Read next batch requires (admin_aer course_batch). Nothing is granted here.
  -- 12 Nov 2026 (F-AER.02): a corrected read the reader skipped before reading records nothing; close it as refused so its item is not blocked
  if not p_preview then perform security.aer_supersession_settle_v1(); end if;
  select c.owner into v_owner from pipeline.field_gap_queue_control c where c.id = 1;
  select ro.rank, ro.code into v_orank, v_orole from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ur.user_id = v_owner and (ur.expires_at is null or ur.expires_at > now()) and ro.status = 'active' order by ro.rank desc limit 1;
  select coalesce(sum(x.course_reads), 0), coalesce(sum(x.corrections), 0) into v_used, v_cused from pipeline.aer_schedule_runs x
   where x.ran_at > now() - interval '1 day';  -- fixed: the daily cap is counted over the last 24 hours
  select count(*) into v_l4 from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run');
  select count(*) into v_prog from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  -- 10 Nov 2026 (AER source recovery): a hold the technical lane has parked with its reason (row limit, human input, duplicate, stale read) waits for a setting, a person or another copy of the page;
  -- it is not a decision a reviewer can make, so it does not use the capacity (security.aer_parked_items_v1). The limit itself is unchanged. With wc.aer_fair_on the count below is replaced as before.
  select count(*) into v_parked from security.aer_parked_items_v1();
  v_bp := v_l4 - v_parked + v_prog >= v_l4max;
  -- 4 Nov 2026 (SS-021 F4, IQ-00128; wc.aer_fair_on): the same limit (aer.schedule_layer4_max, never raised or bypassed) counts distinct
  -- review-ready decisions and distinct reads in progress (security.work_review_room_v1, category aer); technically held and duplicate items
  -- are recorded for bounded technical recovery below, not counted
  if v_fair then
    v_rr := security.work_review_room_v1('aer');
    v_bp := coalesce((v_rr->>'room')::numeric, 0) <= 0;
  end if;
  v_room := greatest(0, least(v_batch, v_daymax - v_used));
  v_croom := greatest(0, least(v_heldmax, v_cmax - v_cused));
  -- s1296: the paid cap, from today's AI spend ledger (security.ai_spend_today_v1, the same day the AI limits use)
  select coalesce(sum(x.spent), 0), coalesce(sum(x.spent) filter (where x.use = 'enrich_fields'), 0) into v_spent_all, v_spent_lane from security.ai_spend_today_v1() x;
  if coalesce(v_cost, 0) > 0 then
    v_paid_room := greatest(0, floor(least(v_paid * v_share - v_spent_lane, v_paid - v_spent_all) / v_cost))::int;
    v_room := least(v_room, v_paid_room); v_croom := least(v_croom, v_paid_room);
  end if;
  v_ai := security.ai_use_refusal_v1('enrich_fields');
  v_aim := security.ai_use_refusal_v1('entry_matrix');
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  v_why := case when v_owner is null then 'no owner to run as (Coverage › Attributes, Fill the gaps)'
                when coalesce(v_orank, 0) < 6 then 'the owner it runs as does not hold the Platform Admin role that Read next batch requires'  -- fixed: the rank admin_aer course_batch requires
                when (security.ai_enrich_routes_v1()->'held') ? 'course_entry_requirements' then 'the entry requirements AI route is held: ' || (security.ai_enrich_routes_v1()->'held'->>'course_entry_requirements') || '; no course read is asked until it is on' -- 18 Nov 2026 (S2-Build): reads asked of a held route never finish
                when v_ai is not null then 'AI reading is stopped (AI limits): ' || v_ai
                when v_paid_room is not null and v_paid_room <= 0 then format('the paid cap for today is used: US$%s spent across all lanes, US$%s on entry reading, cap US$%s, share %s (budgets.paid_daily_cap_usd, aer.schedule_paid_share)',
                                                                             round(v_spent_all, 3), round(v_spent_lane, 3), v_paid, v_share)
                when v_room = 0 and v_croom = 0 and (v_daymax <= v_used or v_cmax <= v_cused) then 'the daily cap is reached'
                when v_room = 0 and v_croom = 0 then 'no course reads a run'
                when v_bal is not null and v_bal - (v_room + v_croom) * v_cost < v_floor then 'the estimate would take the OpenRouter balance below its floor (Toolsets & limits)' end;

  if v_why is null then
    -- (b) held reads first, through D-R2: they replace the waiting item, so they also run under back-pressure
    for r in select * from security.aer_schedule_held_v1(v_croom) loop
      v_checked := v_checked || jsonb_build_object('item_id', r.item_id, 'outcome', r.outcome);
      continue when not r.eligible;
      if p_preview then
        v_held := v_held || jsonb_build_object('item_id', r.item_id, 'course_id', r.course_id, 'provider_id', r.provider_id, 'country', r.country); v_nh := v_nh + 1;
        continue;
      end if;
      begin
        v_res := security.course_entry_correction_v1(r.item_id, v_owner,
                   'Scheduled entry reading (job aer-scheduled-read): the waiting read dropped printed requirements that no row covers; read again from the same stored page');
        v_held := v_held || jsonb_build_object('item_id', r.item_id, 'course_id', r.course_id, 'provider_id', r.provider_id, 'country', r.country, 'job_id', v_res->>'job_id');
        v_nh := v_nh + 1;
      exception when others then
        v_skip := v_skip || jsonb_build_object('item_id', r.item_id, 'why', left(sqlerrm, 300));
      end;
    end loop;
    -- (a) new course reads by eligibility rules, unless Layer 4 is full
    if not v_bp and v_room > 0 then
      -- 4 Nov 2026 (SS-021 F4, wc.aer_fair_on): university by university within its share and the new-university reserve (security.aer_fair_courses_v1)
      for r in select * from security.aer_schedule_courses_v1(v_room * 2) where not v_fair  -- fixed: twice the room, so courses the item gate holds can be passed over
               union all select * from security.aer_fair_courses_v1(v_room) where v_fair loop
        exit when v_nn >= v_room;
        if security.enrich_item_held_v1(r.course_id, 'entry_requirements') then
          v_skip := v_skip || jsonb_build_object('course_id', r.course_id, 'why', 'held by the item gate'); continue;
        end if;
        if p_preview then
          v_new := v_new || jsonb_build_object('course_id', r.course_id, 'provider_id', r.provider_id, 'provider', r.provider_name, 'country', r.country); v_nn := v_nn + 1;
          continue;
        end if;
        begin
          v_job := security.course_entry_read_enqueue_v1(r.course_id, v_owner,
                     'Scheduled entry reading (job aer-scheduled-read): eligible course with no entry requirement held');
          v_new := v_new || jsonb_build_object('course_id', r.course_id, 'provider_id', r.provider_id, 'provider', r.provider_name, 'country', r.country, 'job_id', v_job);
          v_nn := v_nn + 1;
          if v_fair then
            perform security.work_item_report_v1('aer', r.course_id::text, 'entry_read', 'claimed', jsonb_build_object('provider_id', r.provider_id, 'field', 'entry_requirements', 'owner', 'aer-scheduled-read'));
            perform security.work_item_report_v1('aer', r.course_id::text, 'entry_read', 'succeeded', jsonb_build_object('provider_id', r.provider_id, 'field', 'entry_requirements', 'outcome', 'succeeded_with_result'));
          end if;
        exception when others then
          v_skip := v_skip || jsonb_build_object('course_id', r.course_id, 'why', left(sqlerrm, 300));
        end;
      end loop;
    end if;
  end if;

  -- (c) due entry pages fetched again (own lane and guard), unless Layer 4 is full
  -- 4 Nov 2026 (SS-021 F4, wc.aer_fair_on): a refresh is gated by the count only when its university has a matrix item waiting (a refresh that
  -- could raise or duplicate a review item); other due refreshes go ahead within batch.aer_schedule_matrix and the AI guard
  if (not v_bp or v_fair) and v_aim is null and v_mxmax > 0 then
    for r in select s.id, s.provider_id, s.read_via from pipeline.entry_matrix_sources s
              where s.status = 'read' and s.read_via <> 'stored'
                and (not v_bp or not exists (select 1 from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'entry_matrix_first_run'
                                                                                          and i.entity_id = s.provider_id))
                and s.read_at < now() - make_interval(days => security.pipeline_num_v1('entry.matrix_refresh_days', 30)::int)
                and security.entry_matrix_enabled_v1(s.provider_id)
              order by s.read_at, s.id limit v_mxmax loop
      if not p_preview then
        update pipeline.entry_matrix_sources f set status = 'found', attempts = 0, updated_at = now() where f.id = r.id and f.status = 'read';
      end if;
      v_mx := v_mx || jsonb_build_object('source_id', r.id, 'provider_id', r.provider_id, 'read_via', r.read_via);
      v_nm := v_nm + 1;
      if r.read_via = 'firecrawl' then v_fc := v_fc + 1; end if;
    end loop;
  end if;

  v_est := round((v_nh + v_nn) * v_cost, 4);
  -- 4 Nov 2026 (SS-021 F4): technically held and duplicate entry items are recorded for bounded technical recovery (records only; isolated)
  if not p_preview then
    begin
      v_tech := security.aer_technical_recovery_v1();
    exception when others then v_tech := jsonb_build_object('error', left(sqlerrm, 200));
    end;
    -- s1296: the outcomes of the first reads that finished, in the existing recovery knowledge (records only; isolated)
    begin
      v_learn := security.aer_first_read_learn_v1();
    exception when others then v_learn := jsonb_build_object('error', left(sqlerrm, 200));
    end;
  end if;
  if not p_preview then
    insert into pipeline.aer_schedule_checks(item_id, checked_at, outcome)
    select (c->>'item_id')::uuid, now(), c->>'outcome' from jsonb_array_elements(v_checked) c
    on conflict (item_id) do update set checked_at = excluded.checked_at, outcome = excluded.outcome;
    insert into pipeline.aer_schedule_runs(course_reads, corrections, matrix_pages, layer4_waiting, in_progress, back_pressure, used_before, room, refusal, estimate_usd, detail)
    values (v_nn, v_nh, v_nm, v_l4, v_prog, v_bp, v_used, v_room, v_why, v_est,
            jsonb_build_object('held', v_held, 'new', v_new, 'matrix', v_mx, 'skipped', v_skip, 'checked', jsonb_array_length(v_checked),
                               'fair', v_fair, 'room_ready', v_rr, 'technical', v_tech, 'parked_not_counted', v_parked,
                               'corrections_used_24h', v_cused, 'corrections_daily_max', v_cmax, 'corrections_room', v_croom,
                               'paid', jsonb_build_object('cap_usd', v_paid, 'share', v_share, 'spent_all_usd', round(v_spent_all, 4), 'spent_lane_usd', round(v_spent_lane, 4), 'room', v_paid_room),
                               'learning', v_learn));
  end if;
  return jsonb_build_object('preview', p_preview, 'course_reads', v_nn, 'corrections', v_nh, 'matrix_pages', v_nm, 'firecrawl_credits_estimate', v_fc,
    'estimate_usd', v_est, 'cost_per_course_usd', round(v_cost, 5), 'layer4_waiting', v_l4, 'in_progress', v_prog, 'layer4_max', v_l4max, 'back_pressure', v_bp,
    'used_24h', v_used, 'daily_max', v_daymax, 'room', v_room, 'refusal', v_why, 'matrix_refusal', case when v_aim is not null then 'AI reading is stopped (AI limits): ' || v_aim end,
    'balance_usd', v_bal, 'floor_usd', v_floor, 'runs_as', jsonb_build_object('owner', v_owner, 'role', v_orole, 'rank', v_orank, 'source', 'pipeline.field_gap_queue_control.owner'),
    'checked', v_checked, 'held', v_held, 'new', v_new, 'matrix', v_mx, 'skipped', v_skip)
    || jsonb_build_object('fair', v_fair, 'room_ready', v_rr, 'technical', v_tech, 'parked_not_counted', v_parked,
                            'corrections_used_24h', v_cused, 'corrections_daily_max', v_cmax, 'corrections_room', v_croom,
                            'paid', jsonb_build_object('cap_usd', v_paid, 'share', v_share, 'spent_all_usd', round(v_spent_all, 4), 'spent_lane_usd', round(v_spent_lane, 4), 'room', v_paid_room));
end $f$;

-- 6. the E13 pilot counts reads made, not asks that never reached a read
create or replace function security.aer_e13_recover_v1(p_preview boolean default false)
returns jsonb
language plpgsql security definer set search_path = ''
as $f$
-- CF-247 AER throughput (mandate 4 Nov 2026 08:16 §8): held course reads a re-read can fix get the existing corrected read (D-R2) from the stored
-- copy of the same page. Readiness-aware (technical_blocked by the completeness gate; the gate is re-checked before acting), fair by university,
-- bounded a run and a day by settings, and only while aer.e13_recover_on is 1 (p_preview says what a run would ask, without writing).
-- The corrected read replaces the held read only when it is complete (security.enrich_entry_record_v1); nothing is approved here.
-- s1296: the daily allowance and the pilot total count reads made. An ask that never reached a read (the AI route switched off, an item already superseded,
-- another read waiting: aer.e13_not_read_pattern, or an ask the reader skipped before reading) is not counted; 12 to 19 Nov, 478 of the 1,000 asks were such.
declare v_on boolean := security.pipeline_num_v1('aer.e13_recover_on', 0) >= 1;
        v_batch int := security.pipeline_num_v1('batch.aer_e13_recover', 10)::int;
        v_day int := security.pipeline_num_v1('aer.e13_recover_daily_max', 40)::int;
        v_per int := security.pipeline_num_v1('aer.e13_recover_per_provider', 2)::int;
        v_tries int := security.pipeline_num_v1('aer.schedule_held_max_tries', 2)::int;
        v_retry interval := make_interval(days => security.pipeline_num_v1('aer.schedule_held_retry_days', 14)::int);
        v_tag text := 'AER technical recovery (E13)';
        v_notread text := coalesce(security.toolset_setting('pipeline', 'aer.e13_not_read_pattern') #>> '{}', '');
        v_owner uuid; v_rank int; v_ai text; v_bal numeric; v_floor numeric; v_cost numeric := security.course_entry_cost_v1();
        v_used int; v_room int; v_why text; r record; g jsonb; v_res jsonb; v_n int := 0;
        v_asked jsonb := '[]'::jsonb; v_skip jsonb := '[]'::jsonb; v_cand int := 0;
        -- 4 Nov 2026 (direction 10:00 §4): a bounded, reversible pilot: listed universities only, a total over the pilot, and never an item whose
        -- corrected read was refused on the same stored copy (the reader is deterministic on unchanged evidence)
        v_prov text[] := security.pipeline_list_v1('aer.e13_recover_providers', '[]'::jsonb); v_total int := security.pipeline_num_v1('aer.e13_recover_total_max', 40)::int; v_all int;
begin
  select c.owner into v_owner from pipeline.field_gap_queue_control c where c.id = 1;
  select ro.rank into v_rank from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ur.user_id = v_owner and (ur.expires_at is null or ur.expires_at > now()) and ro.status = 'active' order by ro.rank desc limit 1;
  select count(*) into v_used from pipeline.aer_read_supersessions s
   where s.requested_at > now() - interval '1 day' and s.reason like v_tag || '%'  -- fixed: the daily budget is counted over the last 24 hours
     and not ((v_notread <> '' and coalesce(s.outcome, '') ~* v_notread)
              or (s.state = 'requested' and exists (select 1 from pipeline.field_enrich_items f where f.id = s.enrich_item_id and f.state in ('skipped', 'failed'))));
  select count(*) into v_all from pipeline.aer_read_supersessions s where s.reason like v_tag || '%'
     and not ((v_notread <> '' and coalesce(s.outcome, '') ~* v_notread)
              or (s.state = 'requested' and exists (select 1 from pipeline.field_enrich_items f where f.id = s.enrich_item_id and f.state in ('skipped', 'failed'))));
  v_room := greatest(0, least(v_batch, v_day - v_used, v_total - v_all));
  v_ai := security.ai_use_refusal_v1('enrich_fields');
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  v_why := case when not v_on and not p_preview then 'aer.e13_recover_on is 0'
                when v_owner is null then 'no owner to run as (Coverage > Attributes, Fill the gaps)'
                when coalesce(v_rank, 0) < 6 then 'the owner it runs as does not hold the Platform Admin role'  -- fixed: the rank Read next batch requires
                when v_ai is not null then 'AI reading is stopped (AI limits): ' || v_ai
                when cardinality(v_prov) = 0 then 'no university is in the pilot (aer.e13_recover_providers)'
                when v_room = 0 and v_all >= v_total then 'the pilot total is used (aer.e13_recover_total_max)'
                when v_room = 0 then 'the daily budget of E13 recovery is used (aer.e13_recover_daily_max)'
                when v_bal is not null and v_bal - v_room * v_cost < v_floor then 'the estimate would take the OpenRouter balance below its floor (Toolsets & limits)' end;
  if v_why is not null and not (p_preview and v_why = 'aer.e13_recover_on is 0') then
    return jsonb_build_object('on', v_on, 'preview', p_preview, 'refusal', v_why, 'used_24h', v_used, 'room', v_room, 'asked', 0);
  end if;
  for r in
    with c as (
      select i.id, i.entity_id, i.created_at, co.provider_id,
             (select count(*) from pipeline.aer_read_supersessions s where s.old_item_id = i.id) tries
        from pipeline.layer4_review_items i
        join pipeline.layer4_item_readiness x on x.item_id = i.id
        join catalogue.courses co on co.id = i.entity_id
        join pipeline.coverage_course_pages pg on pg.course_id = i.entity_id
       where i.status = 'pending' and i.field_code = 'course_entry_first_read'
         and x.readiness = 'technical_blocked' and 'completeness_gate' = any (x.reasons)
         and security.aer_e13_class_v1(x.gate) = 'drops_uncovered'
         and pg.evidence_id is not null and pg.url = i.proposed_value->>'url'
         and co.provider_id::text = any (v_prov)
         -- mandate 16:32 §4: the shared rule (an unchanged copy, reader and settings never read again; a change makes it eligible)
         and coalesce((security.aer_recovery_rule_v1(i.id)->>'eligible')::boolean, false)
         and not exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = i.id and (s.state = 'requested' or s.requested_at > now() - v_retry))
         and not exists (select 1 from pipeline.field_enrich_items f where f.course_id = i.entity_id and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased'))),
    k as (select c.*, row_number() over (partition by c.provider_id order by c.tries, c.created_at, c.id) turn from c where c.tries < v_tries)
    select * from k where k.turn <= v_per order by k.turn, k.tries, k.created_at, k.id
  loop
    exit when v_n >= v_room;
    v_cand := v_cand + 1;
    -- the gate result may be older than the item's last change: checked again before anything is asked
    g := security.course_entry_gate_v1(r.id);
    if security.aer_e13_class_v1(g) is distinct from 'drops_uncovered' then
      v_skip := v_skip || jsonb_build_object('item_id', r.id, 'why', 'the gate now says ' || coalesce(security.aer_e13_class_v1(g), 'nothing'));
      continue;
    end if;
    if p_preview then
      v_asked := v_asked || jsonb_build_object('item_id', r.id, 'course_id', r.entity_id, 'provider_id', r.provider_id, 'tries', r.tries); v_n := v_n + 1;
      continue;
    end if;
    begin
      v_res := security.course_entry_correction_v1(r.id, v_owner,
                 v_tag || ': the held read dropped printed requirements that no row covers; read again from the stored copy of the same page (try ' || (r.tries + 1) || ')');
      v_asked := v_asked || jsonb_build_object('item_id', r.id, 'course_id', r.entity_id, 'provider_id', r.provider_id, 'tries', r.tries, 'job_id', v_res->>'job_id');
      v_n := v_n + 1;
    exception when others then
      v_skip := v_skip || jsonb_build_object('item_id', r.id, 'why', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('on', v_on, 'preview', p_preview, 'refusal', null, 'used_24h', v_used, 'pilot_used', v_all, 'room', v_room, 'candidates', v_cand, 'asked', v_n,
                            'estimate_usd', round(v_n * v_cost, 4), 'items', v_asked, 'skipped', v_skip);
end $f$;

-- post-checks: the rule is coherent, nothing it offers holds a row, a lock or a pending decision; the consumer API, locks and jobs are unchanged
do $c$
declare v jsonb := security.consumer_api_check_v1(); v_pop int; v_state int; v_elig int; v_bad int; v_total int;
begin
  select count(*) into v_pop from security.aer_course_population_v1() p
   where not exists (select 1 from catalogue.course_entry_requirements x where x.course_id = p.course_id and x.status in ('active', 'proposed'))
     and not exists (select 1 from pipeline.layer4_review_items r where r.entity_id = p.course_id and r.field_code = 'course_entry_first_read' and r.status = 'pending');
  select count(*), count(*) filter (where eligible) into v_state, v_elig from security.aer_first_read_state_v1();
  if v_state <> v_pop then raise exception 'post-check: the rule classifies % courses, the pool without rows is %', v_state, v_pop; end if;
  select count(*) into v_bad from security.aer_schedule_courses_v1(100000, true) s
   where exists (select 1 from catalogue.course_entry_requirements x where x.course_id = s.course_id and x.status in ('active', 'proposed'))
      or exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = s.course_id and l.field in ('entry_requirements', 'all'))
      or exists (select 1 from pipeline.layer4_review_items r where r.entity_id = s.course_id and r.field_code = 'course_entry_first_read' and r.status = 'pending');
  if v_bad > 0 then raise exception 'post-check: % offered courses hold a row, a lock or a waiting decision', v_bad; end if;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API drift: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1296_guard) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select 1 from cron.job j where j.jobid not in (select jobid from s1296_cron)) then raise exception 'post-check: a cron job was added'; end if;
  select count(*) into v_total from cron.job where active;
  if v_total > 140 then raise exception 'post-check: % active cron jobs, above 140', v_total; end if;
  raise notice 's1296: % courses classified, % eligible; E13 preview %', v_state, v_elig, (select security.aer_e13_recover_v1(true));
end $c$;
