-- CF-247 Release B: course enrichment from verified stored evidence (Platform Admin mandate 3 Nov 2026 13:09, 2026-11-03-consolidated-enrichment-
-- developer-readiness-mandate-1309.md §4 Release B, decisions D1, D2, D3 and §6 priorities 1, 2 and 5). Extends the existing Enrich fields engine
-- (security.enrich_fields_slice_v1, public.svc_enrich_ai_next / svc_enrich_ai_record, worker mode enrich_ai); no new engine, job, screen or reader.
-- Why (production, read-only, 3 Nov 2026 13:11-13:58 AEDT; measured over the 7 days before):
--   the standing gap queue finished each batch in 2 to 33 minutes and then waited for its next 6-hourly run (duty cycle about 1 to 9%);
--   every item is one course and one field, so a course page is read again for each field asked in a later task; and an item skipped because a
--   page did not state a field, or because no source had a value, holds the course as "not on page" (coverage cache) and raises the same
--   "no value" hold whether the page was read or not (D3: never unavailable only because an adapter returned nothing).
-- What:
--   1 Multi-field extraction (§6 priority 2): when the reader takes a course's stored page for one field (enrich_fields_slice_v1, source
--     ai_stored), security.enrich_siblings_v1 adds the course's other missing supported fields (setting enrich.multi_field_fields, at most
--     enrich.multi_field_max_per_page) to the same task as items on the same stored copy; svc_enrich_ai_next leases a course's due items of a
--     task together, so the worker reads the page once for all of them (its existing per-page path: one call for campus, duration, delivery,
--     international, English and intakes; one call for description and deadline). Each value is checked by its existing field rules and
--     admitted by the existing paths (enrich_apply_v1, enrich_course_text_record_v1, Layer 4). A sibling is never added when the field is
--     locked by hand, held, being worked on elsewhere, outside the country's source rules, outside a person's task's chosen fields, already
--     found absent on an unchanged copy, or (description, deadline) over enrich.course_text_items_per_day. No page is fetched (D1).
--   2 D2 + D3: an explicit, configurable absence catalogue (pipeline.field_absence_classes: not_on_this_page, on_other_stored_page,
--     needs_source_discovery, evidence_pending, explicitly_not_stated, not_applicable, identity_unresolved) with its classification rules
--     (pipeline.field_absence_rules) and one record per course and field (pipeline.course_field_absence: evidence id, content hash, reader
--     version, confidence, reason, next eligibility date or evidence-change trigger), written when an Enrich fields item settles (trigger
--     field_enrich_items_absence) and resolved when a value is filled or sent to Layer 4. A negative is "verified" only from a stored page a
--     reader read (source ai_stored with its evidence) at or above absence.verified_min_confidence; an adapter or source that returned nothing
--     is needs_source_discovery or evidence_pending, never a negative, and no longer raises the "no value" hold (field_enrich_items_flag_v1).
--     An unchanged copy (same content hash) is never read again after a verified negative (enrich_fields_slice_v1, siblings); a new copy or a
--     new page makes it due again. The coverage cache (course_coverage_build_v1) shows the class for the fields in absence.coverage_fields
--     (delivery, duration) instead of the blanket "not on page", in a new column course_attribute_coverage.absence_class.
--   3 Throughput (§6 priority 5): job field-gap-queue is checked hourly (23 * * * *) and runs when security.field_gap_queue_due_v1 says so:
--     no standing task open, at least gaps.advance_minutes since the last run, and either the pass is unfinished, the last run found work or held
--     courses waiting for page proof (which feed job source-proof-feed), or gaps.idle_rerun_minutes have passed. Minute :23 is outside the load policy's busy windows (:00-:05, :35-:42, :47-:48).
--   4 Job source-proof-feed (Integration Controller 3 Nov 2026 13:50): security.source_proof_feed_v1 records every run in a new table
--     pipeline.source_proof_feed_runs (outcome done / held / idle, hold reason such as no_page_proof_input, settled, routed, ms), as
--     field_gap_queue_run_v1 does, so a run with nothing to do is told apart from a run that never happened.
-- Spend: no Firecrawl (D1: no new acquisition; siblings read only the stored copy already leased). AI through the existing enrich_fields lane and
--   its guard (security.ai_use_allowed_v1('enrich_fields'), the platform daily ceiling); siblings share the page call.
-- Consumer API (G3): unchanged. Values reach only the columns the existing admission paths write.
-- Replaces: public.svc_enrich_ai_next, public.svc_enrich_ai_record, security.enrich_fields_slice_v1, security.field_enrich_items_flag_v1, security.course_coverage_build_v1, security.source_proof_feed_v1 (same names; md5-guarded edits); the blanket "not on page" coverage state for delivery and duration
-- Retires: nothing
-- Nothing is dropped or deleted. No job is added (field-gap-queue's schedule and guard change). Multi-field reading ships OFF (enrich.multi_field_on 0):
--   the Integration Controller switches it on as a separate, recorded setting change once svc_enrich_ai_record runs clear of statement time-outs
--   (IQ-00053); the hourly gap queue ships at gaps.advance_minutes 60.

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

-- 0. the definitions the new code calls are the ones it was written against (not changed here) ------------------------------------------
do $g$
declare r record;
begin
  for r in select * from (values ('security.enrich_fields_v1()', '80ee183b324c196b4c9559cec6e3360f'), ('security.enrich_item_in_flight_v1(uuid,uuid,text)', '35caac7c2ae66aa43ea0ffc9a6d5f654'),
                                 ('security.field_sources_for_v1(text,text)', 'd8c74083ed675fb2383fedd4b4a1ec49'), ('security.enrich_deadline_missing_v1(uuid)', null),
                                 ('security.field_gap_queue_run_v1()', '429835d4d27375da95901104838a0cad')) v(sig, m) loop
    if to_regprocedure(r.sig) is null then raise exception 'release B: % is missing', r.sig; end if;
    if r.m is not null and md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'enrich.multi_field_on', 'Read every missing field from the same stored page',
  'On (1): when the reader takes a course''s stored page for one field, the course''s other missing fields (enrich.multi_field_fields) are read from the same copy in the same task. Off (0): one field at a time, as before.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1111, 'Course description and deadline',
  'security.enrich_siblings_v1 (enrich_fields_slice_v1); public.svc_enrich_ai_next', 'CF-247 Release B (mandate 3 Nov 2026 13:09 §6 priority 2): one read of a stored page for every missing field'),
 ('pipeline', 'enrich.multi_field_fields', 'Fields read together from one stored page',
  'The course fields read from the same stored copy when one of them is asked. Only fields the Enrich fields engine reads from the stored page (source ai_stored) and the country''s source rules allow are added.',
  'list', '["campus", "duration", "delivery", "international", "english", "intakes", "description", "deadline"]'::jsonb, null, null, 'fields', 1112, 'Course description and deadline',
  'security.enrich_siblings_v1', 'CF-247 Release B (mandate 3 Nov 2026 13:09 §6 priority 2): one read of a stored page for every missing field'),
 ('pipeline', 'enrich.multi_field_max_per_page', 'Most fields added to one page read',
  'Most other fields added to one course page read (besides the field asked).', 'number', to_jsonb(8), 1, 12, 'fields', 1113, 'Course description and deadline',
  'security.enrich_siblings_v1', 'CF-247 Release B (mandate 3 Nov 2026 13:09 §6 priority 2): one read of a stored page for every missing field'),
 ('pipeline', 'absence.verified_min_confidence', 'Absence: confidence of a verified negative',
  'A field the reader did not find on a stored page counts as a verified negative (the same copy is not read again for it) only at or above this confidence. Classification rules give each outcome its confidence (pipeline.field_absence_rules).',
  'number', to_jsonb(0.7), 0, 1, 'share', 1114, 'Field absence (D2, D3)',
  'security.field_absence_unchanged_v1 (enrich_fields_slice_v1, enrich_siblings_v1)', 'CF-247 Release B (decisions D2, D3, 3 Nov 2026 13:09)'),
 ('pipeline', 'absence.pending_recheck_hours', 'Absence: evidence pending, asked again after',
  'A field whose evidence is pending (a failed or cut read, a page asked for and not yet stored) is due again after this many hours.',
  'number', to_jsonb(24), 1, 720, 'hours', 1115, 'Field absence (D2, D3)',
  'security.field_absence_classify_v1', 'CF-247 Release B (decisions D2, D3, 3 Nov 2026 13:09)'),
 ('pipeline', 'absence.coverage_fields', 'Absence: fields shown by class on Coverage',
  'For these fields the coverage cache shows the absence class (found elsewhere, evidence pending, needs a source, identity unresolved, not on the page) instead of a blanket "not on page".',
  'list', '["delivery", "duration"]'::jsonb, null, null, 'fields', 1116, 'Field absence (D2, D3)',
  'security.course_coverage_build_v1 (job course-coverage-build)', 'CF-247 Release B (decision D2, 3 Nov 2026 13:09)'),
 ('pipeline', 'gaps.advance_minutes', 'Gap queue: shortest time between runs',
  'The standing gap queue is checked every hour and starts its next batch once the previous one has finished and this many minutes have passed, while its pass is unfinished, its last run found work, or it holds courses waiting for page proof (the input of job source-proof-feed).',
  'number', to_jsonb(60), 60, 720, 'minutes', 1024, 'Gap queue',
  'security.field_gap_queue_due_v1 (job field-gap-queue)', 'CF-247 Release B (mandate 3 Nov 2026 13:09 §6 priority 5): automatic next-batch advancement'),
 ('pipeline', 'gaps.idle_rerun_minutes', 'Gap queue: run again after a pass that found nothing',
  'After a full pass found nothing, the next run waits this long (new pages and filled values are found then).',
  'number', to_jsonb(360), 60, 1440, 'minutes', 1025, 'Gap queue',
  'security.field_gap_queue_due_v1 (job field-gap-queue)', 'CF-247 Release B (mandate 3 Nov 2026 13:09 §6 priority 5): automatic next-batch advancement')
on conflict (toolset_key, key) do nothing;
update pipeline.platform_toolset_settings set used_by = used_by || '; security.enrich_siblings_v1 (siblings count toward it)', updated_at = now()
 where toolset_key = 'pipeline' and key = 'enrich.course_text_items_per_day' and coalesce(used_by, '') not like '%enrich_siblings_v1%';

-- 2. the absence catalogue, its rules and the record per course and field (D2, D3) -------------------------------------------------------
create table if not exists pipeline.field_absence_classes (
  code text primary key, label text not null, meaning text not null,
  verified_negative boolean not null default false,  -- the same copy is not read again for the field (at or above absence.verified_min_confidence)
  coverage_state text,                               -- the course_attribute_coverage state shown for absence.coverage_fields (null: the page state)
  reeval_trigger text not null check (reeval_trigger in ('page_change', 'new_page', 'identity_change', 'intake_added', 'date', 'none')),
  sort int not null default 0, active boolean not null default true, updated_at timestamptz not null default now());
comment on table pipeline.field_absence_classes is 'CF-247 Release B (decisions D2, D3, Platform Admin 3 Nov 2026 13:09): the configurable catalogue of why a course field has no value: the class, whether it is a verified negative, the coverage state it shows and what makes the field due again (a changed page, a new page, a resolved identity, an added intake, a date). Changed by the Platform Admin with a reason; admission rules are not here.';
insert into pipeline.field_absence_classes(code, label, meaning, verified_negative, coverage_state, reeval_trigger, sort) values
 ('not_on_this_page', 'Not on this page', 'The reader read the course''s stored page and the page does not state the field. A verified negative for that copy only: a changed copy or a new page is read again.', true, 'not_on_page', 'page_change', 1),
 ('on_other_stored_page', 'Found on another stored page', 'The course page does not state it, but another stored reading of the course (its adapter reading or the page''s own candidates) holds a value: settled from that evidence, not by reading the page again.', false, 'candidate', 'none', 2),
 ('needs_source_discovery', 'Needs source discovery', 'No stored page of the course could be read for the field (no allowed source had a value). Not a negative: it waits for a page to be found (paid acquisition is decided under D1).', false, null, 'new_page', 3),
 ('evidence_pending', 'Evidence pending', 'The page is asked for, the read failed or was cut, or the answer could not be checked. Asked again after absence.pending_recheck_hours.', false, 'in_queue', 'date', 4),
 ('explicitly_not_stated', 'Explicitly not stated', 'The page says so itself (for example applications are rolling, with no closing date). Kept until the page changes.', true, 'not_on_page', 'page_change', 5),
 ('not_applicable', 'Not applicable', 'The field does not apply now (a deadline with no active intake; a campus for an online-only course). Due again when that changes.', false, 'not_on_page', 'intake_added', 6),
 ('identity_unresolved', 'Source identity unresolved', 'The page found is not proved to be this course''s (E16), or its proof does not admit the field in this country. Due again when the course''s page identity changes.', false, 'page_found', 'identity_change', 7)
on conflict (code) do nothing;

create table if not exists pipeline.field_absence_rules (
  id serial primary key, priority int not null, fields text[], item_states text[], sources text[], stored_page boolean,
  reason_pattern text not null, absence_class text references pipeline.field_absence_classes(code), confidence numeric not null default 0.5 check (confidence between 0 and 1),
  note text not null, active boolean not null default true, updated_at timestamptz not null default now(), unique (priority, reason_pattern));
comment on table pipeline.field_absence_rules is 'CF-247 Release B (decision D3, 3 Nov 2026 13:09): how a settled Enrich fields item is classified (first active rule by priority whose field, item state, source, stored-page condition and reason pattern match). absence_class null keeps the course and field''s previous classification (the item settled for a reason that is not an absence, such as locked, already filled or held by validation). The classification is then refined by evidence (security.field_absence_classify_v1).';
insert into pipeline.field_absence_rules(priority, fields, item_states, sources, stored_page, reason_pattern, absence_class, confidence, note) values
 (10, null, null, null, null, '(provider unpublished|locked by hand|already filled|^held|held_first_admission|the same page copy was read)', null, 0, 'not an absence: the previous classification is kept'),
 (20, null, null, null, null, '(no correct course page|no proven course page|does not admit|no longer the course''s bound page)', 'identity_unresolved', 0.9, 'E16 page identity'),
 (30, array['deadline'], array['skipped'], array['ai_stored'], null, 'rolling', 'explicitly_not_stated', 0.9, 'the page says applications are rolling'),
 (40, array['deadline'], null, null, null, 'no active intake to hold a deadline', 'not_applicable', 0.9, 'no active intake'),
 (50, null, array['skipped'], array['ai_stored'], null, '(does not state|names no campus|no campus named on the page|site-wide line)', 'not_on_this_page', 0.85, 'the reader read the stored page'),
 (60, null, array['skipped'], array['ai_stored'], null, '(quote is not on the page|quote does not name|quote names no|quote is about|outside the intake|intake_not_matched|not_tied_to_one_intake|date_not_in_quote|no_full_date|conflicting_dates)', 'not_on_this_page', 0.5, 'a value was read but not proved by its quote: below the verified level, so read again'),
 (70, null, null, null, false, 'no allowed source had a value', 'needs_source_discovery', 0.6, 'no stored page: never a negative (D3)'),
 (71, null, null, null, true, 'no allowed source had a value', 'evidence_pending', 0.4, 'a stored page exists but no source read it'),
 (80, null, array['failed'], null, null, '.*', 'evidence_pending', 0.2, 'the read failed'),
 (90, null, null, null, null, '(did not arrive in time|time budget|tries|HTTP|held_partial|output_truncated)', 'evidence_pending', 0.3, 'the read did not finish')
on conflict (priority, reason_pattern) do nothing;

create table if not exists pipeline.course_field_absence (
  course_id uuid not null, field text not null, absence_class text not null references pipeline.field_absence_classes(code),
  evidence_id uuid, content_hash text, reader_version text, confidence numeric, reason text,
  next_eligible_at timestamptz, reeval_trigger text, item_id bigint, classified_at timestamptz not null default now(), resolved_at timestamptz,
  primary key (course_id, field));
create index if not exists course_field_absence_open_idx on pipeline.course_field_absence (field, absence_class) where resolved_at is null;
comment on table pipeline.course_field_absence is 'CF-247 Release B (decisions D2, D3, 3 Nov 2026 13:09): why each course field has no value, from the latest settled Enrich fields item: the class (pipeline.field_absence_classes), the evidence and its content hash, the reader version, the confidence, the reason, and the next eligibility date or the evidence change that makes it due again. resolved_at is set when a value is filled or sent to Layer 4. Written by security.field_absence_classify_v1.';
alter table pipeline.course_attribute_coverage add column if not exists absence_class text;
comment on column pipeline.course_attribute_coverage.absence_class is 'CF-247 Release B (D2): the open absence class of a missing value (pipeline.course_field_absence); for absence.coverage_fields the state is the class''s coverage state.';

-- 3. helpers -------------------------------------------------------------------------------------------------------------------------------
-- the gap queue's missing-value rule for one course and field (security.field_gap_scan_v1, security.enrich_course_text_gaps_v1)
create or replace function security.enrich_course_field_missing_v1(p_course uuid, p_field text) returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select case p_field
           when 'campus' then not exists (select 1 from catalogue.course_campuses x where x.course_id = c.id)
           when 'duration' then c.duration_value is null when 'level' then c.study_level_id is null
           when 'delivery' then nullif(btrim(c.delivery_mode), '') is null when 'field_of_study' then c.primary_field_id is null
           when 'international' then c.open_to_international is null
           when 'english' then not exists (select 1 from catalogue.course_english_requirements x where x.course_id = c.id and coalesce(x.status, 'active') = 'active')
           when 'intakes' then not exists (select 1 from catalogue.course_intakes x where x.course_id = c.id and x.status = 'active')
           when 'description' then nullif(btrim(c.description), '') is null
           when 'deadline' then security.enrich_deadline_missing_v1(c.id)
           else false end
     from catalogue.courses c where c.id = p_course and c.lifecycle_status = 'active'), false)
$$;
comment on function security.enrich_course_field_missing_v1(uuid, text) is 'CF-247 Release B (3 Nov 2026): whether an active course is missing a field, by the standing gap queue''s rules (field_gap_scan_v1; description and deadline as enrich_course_text_gaps_v1).';
revoke all on function security.enrich_course_field_missing_v1(uuid, text) from public, anon, authenticated;

-- another stored reading of the course holds a value for the field (its adapter reading, or the page reading's candidates)
create or replace function security.field_absence_other_page_v1(p_course uuid, p_field text) returns boolean language sql stable security definer set search_path = '' as $$
  with x as (select coalesce((select r.fields->'extra' from pipeline.uni_adapter_results r where r.course_id = p_course order by r.at desc limit 1), '{}'::jsonb)
                    || coalesce((select g.candidates->'adapter_extra' from pipeline.coverage_course_pages g where g.course_id = p_course), '{}'::jsonb) e,
                    (select g.candidates from pipeline.coverage_course_pages g where g.course_id = p_course) c)
  select coalesce(case p_field
           when 'campus' then nullif(btrim(coalesce(x.e->>'campus', x.e->>'location')), '') is not null
           when 'duration' then nullif(btrim(x.e->>'duration'), '') is not null
           when 'delivery' then nullif(btrim(x.e->>'mode'), '') is not null
           when 'international' then nullif(btrim(x.e->>'student_type'), '') is not null
           when 'intakes' then jsonb_typeof(x.c->'intakes') = 'array' and jsonb_array_length(x.c->'intakes') > 0
           when 'english' then coalesce(x.c->'english' ? 'ielts_overall', false)
           else false end, false)
    from x
$$;
comment on function security.field_absence_other_page_v1(uuid, text) is 'CF-247 Release B (D2): another stored reading of the course (its latest adapter reading or the page reading''s candidates) holds a value for the field: on_other_stored_page, not a negative.';
revoke all on function security.field_absence_other_page_v1(uuid, text) from public, anon, authenticated;

-- an open absence is due again: its evidence-change trigger has happened or its date has passed (p_ev: the copy about to be read, or the bound one)
create or replace function security.field_absence_due_v1(p_course uuid, p_field text, p_ev uuid) returns boolean language sql stable security definer set search_path = '' as $$
  with a as (select * from pipeline.course_field_absence a where a.course_id = p_course and a.field = p_field and a.resolved_at is null),
  cur as (select coalesce(p_ev, (select g.evidence_id from pipeline.coverage_course_pages g where g.course_id = p_course and g.read_status = 'read')) ev),
  h as (select cur.ev, (select e.content_hash from pipeline.evidence_artifacts e where e.id = cur.ev) hash from cur)
  select case when not exists (select 1 from a) then true
    else (select case a.reeval_trigger
            when 'page_change' then h.ev is not null and case when h.hash is not null and a.content_hash is not null then h.hash <> a.content_hash else h.ev is distinct from a.evidence_id end
            when 'new_page' then h.ev is not null
            when 'identity_change' then h.ev is distinct from a.evidence_id
                                     or exists (select 1 from pipeline.course_page_proofs y where y.course_id = p_course and y.proven and y.checked_at > a.classified_at)
            when 'intake_added' then exists (select 1 from catalogue.course_intakes x where x.course_id = p_course and x.status = 'active')
                                  or (h.ev is not null and h.ev is distinct from a.evidence_id)
            when 'date' then coalesce(a.next_eligible_at <= now(), true)
            else true end
          from a, h) end
$$;
comment on function security.field_absence_due_v1(uuid, text, uuid) is 'CF-247 Release B (D2): whether a course field''s open absence is due again: a changed copy (content hash), a new stored page, a resolved page identity, an added intake, or its date (pipeline.field_absence_classes.reeval_trigger).';
revoke all on function security.field_absence_due_v1(uuid, text, uuid) from public, anon, authenticated;

-- a verified negative on this very content: the copy is not read again for the field (D2)
create or replace function security.field_absence_unchanged_v1(p_course uuid, p_field text, p_ev uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select p_ev is not null and exists (
    select 1 from pipeline.course_field_absence a join pipeline.field_absence_classes k on k.code = a.absence_class
     where a.course_id = p_course and a.field = p_field and a.resolved_at is null and k.verified_negative
       and coalesce(a.confidence, 0) >= security.pipeline_num_v1('absence.verified_min_confidence', 0.7)
       and (a.evidence_id = p_ev or (a.content_hash is not null and a.content_hash = (select e.content_hash from pipeline.evidence_artifacts e where e.id = p_ev))))
$$;
comment on function security.field_absence_unchanged_v1(uuid, text, uuid) is 'CF-247 Release B (D2): the copy about to be read (the same evidence, or one with the same content hash) was read for the field and the field was a verified negative: not read again.';
revoke all on function security.field_absence_unchanged_v1(uuid, text, uuid) from public, anon, authenticated;

-- classify a settled Enrich fields item (called by trigger field_enrich_items_absence; the backfill below)
create or replace function security.field_absence_classify_v1(p_item bigint) returns text language plpgsql security definer set search_path = '' as $$
declare i pipeline.field_enrich_items%rowtype; r record; k pipeline.field_absence_classes%rowtype; v_class text; v_conf numeric; v_stored boolean; v_next timestamptz;
        v_reader text := nullif(current_setting('cf247.reader_version', true), '');
begin
  select * into i from pipeline.field_enrich_items where id = p_item;
  if i.id is null or i.course_id is null then return null; end if;
  if i.state in ('filled', 'review') then
    update pipeline.course_field_absence set resolved_at = now(), item_id = i.id where course_id = i.course_id and field = i.field and resolved_at is null;
    return 'resolved';
  end if;
  if i.state not in ('skipped', 'failed') then return null; end if;
  v_stored := exists (select 1 from pipeline.coverage_course_pages g where g.course_id = i.course_id and g.evidence_id is not null and g.read_status = 'read');
  select x.* into r from pipeline.field_absence_rules x
   where x.active and (x.fields is null or i.field = any (x.fields)) and (x.item_states is null or i.state = any (x.item_states))
     and (x.sources is null or coalesce(i.source, '') = any (x.sources)) and (x.stored_page is null or x.stored_page = v_stored)
     and coalesce(i.reason, '') ~* x.reason_pattern
   order by x.priority, x.id limit 1;
  if r.id is not null and r.absence_class is null then return 'kept'; end if;
  v_class := coalesce(r.absence_class, 'evidence_pending'); v_conf := coalesce(r.confidence, 0.2);
  -- evidence-aware refinements
  if v_class = 'not_on_this_page' and security.field_absence_other_page_v1(i.course_id, i.field) then v_class := 'on_other_stored_page'; end if;
  if v_class in ('not_on_this_page', 'on_other_stored_page') and i.field = 'campus'
     and exists (select 1 from catalogue.courses c where c.id = i.course_id and c.delivery_mode = 'online') then v_class := 'not_applicable'; end if;
  select * into k from pipeline.field_absence_classes where code = v_class;
  -- D3: only a stored page that a reader read makes a negative; a source or adapter that returned nothing never does
  if k.verified_negative and (i.source is distinct from 'ai_stored' or i.evidence_id is null) then
    v_class := case when v_stored then 'evidence_pending' else 'needs_source_discovery' end; v_conf := least(v_conf, 0.3);
    select * into k from pipeline.field_absence_classes where code = v_class;
  end if;
  v_next := case k.reeval_trigger when 'date' then now() + make_interval(hours => security.pipeline_num_v1('absence.pending_recheck_hours', 24)::int)
                                  when 'none' then now() end;
  insert into pipeline.course_field_absence as a (course_id, field, absence_class, evidence_id, content_hash, reader_version, confidence, reason, next_eligible_at, reeval_trigger, item_id, classified_at, resolved_at)
  values (i.course_id, i.field, v_class, i.evidence_id, (select e.content_hash from pipeline.evidence_artifacts e where e.id = i.evidence_id),
          left(coalesce(v_reader, coalesce(i.source, 'none') || ' (no reader)'), 200), v_conf, left(i.reason, 300), v_next, k.reeval_trigger, i.id, now(), null)
  on conflict (course_id, field) do update set absence_class = excluded.absence_class, evidence_id = excluded.evidence_id, content_hash = excluded.content_hash,
         reader_version = excluded.reader_version, confidence = excluded.confidence, reason = excluded.reason, next_eligible_at = excluded.next_eligible_at,
         reeval_trigger = excluded.reeval_trigger, item_id = excluded.item_id, classified_at = now(), resolved_at = null;
  return v_class;
end $$;
comment on function security.field_absence_classify_v1(bigint) is 'CF-247 Release B (D2, D3): records why a settled Enrich fields item left its course field empty (pipeline.field_absence_rules, then evidence: another stored reading, online-only campus, and a negative only from a stored page a reader read), or resolves the record when a value is filled or sent to Layer 4.';
revoke all on function security.field_absence_classify_v1(bigint) from public, anon, authenticated;

create or replace function security.field_enrich_items_absence_trg_v1() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.course_id is null or new.state is not distinct from old.state then return null; end if;
  if new.state in ('filled', 'review', 'skipped', 'failed') then perform security.field_absence_classify_v1(new.id); end if;
  return null;
end $$;
comment on function security.field_enrich_items_absence_trg_v1() is 'CF-247 Release B (D2, D3): trigger field_enrich_items_absence: classifies each settled course item (security.field_absence_classify_v1).';
revoke all on function security.field_enrich_items_absence_trg_v1() from public, anon, authenticated;
do $t$
begin
  if not exists (select 1 from pg_trigger where tgname = 'field_enrich_items_absence' and tgrelid = 'pipeline.field_enrich_items'::regclass) then
    create trigger field_enrich_items_absence after update of state on pipeline.field_enrich_items for each row execute function security.field_enrich_items_absence_trg_v1();
  end if;
end $t$;

-- multi-field: the course's other missing fields join the same task on the same stored copy (§6 priority 2)
create or replace function security.enrich_siblings_v1(p_item bigint) returns integer language plpgsql security definer set search_path = '' as $$
declare i pipeline.field_enrich_items%rowtype; j pipeline.admin_jobs%rowtype; v_cc text; v_fields text[]; v_auto boolean; f text; v_n int := 0; v_k int;
        v_max int := greatest(1, security.pipeline_num_v1('enrich.multi_field_max_per_page', 8)::int);
        v_text_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int;
begin
  if security.pipeline_num_v1('enrich.multi_field_on', 1) < 1 then return 0; end if;
  select * into i from pipeline.field_enrich_items where id = p_item;
  if i.id is null or i.course_id is null or i.source is distinct from 'ai_stored' or i.storage_path is null or i.state <> 'ai' then return 0; end if;
  select * into j from pipeline.admin_jobs where id = i.job_id;
  select k.iso_alpha2::text into v_cc from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = i.provider_id;
  v_auto := coalesce((j.args->>'standing')::boolean, false) or coalesce(j.args->>'plan_mode' = 'auto', false);
  v_fields := array(select jsonb_array_elements_text(case when jsonb_typeof(security.toolset_setting('pipeline', 'enrich.multi_field_fields')) = 'array'
                                                          then security.toolset_setting('pipeline', 'enrich.multi_field_fields') else '[]'::jsonb end));
  -- a task a person started keeps to the fields they chose
  if not v_auto then
    v_fields := array(select x from unnest(v_fields) x where x = any (array(select jsonb_array_elements_text(case when jsonb_typeof(j.args->'fields') = 'array' then j.args->'fields' else '[]'::jsonb end))));
  end if;
  foreach f in array v_fields loop
    exit when v_n >= v_max;
    continue when f = i.field;
    continue when not exists (select 1 from security.enrich_fields_v1() e where e.field = f and e.level = 'course' and 'ai_stored' = any (e.sources));
    continue when not ('ai_stored' = any (coalesce(security.field_sources_for_v1(v_cc, f), '{}'::text[])));
    continue when not security.enrich_course_field_missing_v1(i.course_id, f);
    continue when exists (select 1 from pipeline.manual_locks lk where lk.entity = 'course' and lk.entity_id = i.course_id and lk.field in (f, 'all'));
    continue when exists (select 1 from pipeline.field_enrich_items o where o.job_id = i.job_id and o.provider_id = i.provider_id and o.course_id = i.course_id and o.field = f);
    continue when security.enrich_item_in_flight_v1(i.provider_id, i.course_id, f);
    -- D2: an open absence that is not due again, or a verified negative on this very content, is not read again
    continue when exists (select 1 from pipeline.course_field_absence a where a.course_id = i.course_id and a.field = f and a.resolved_at is null)
                  and not security.field_absence_due_v1(i.course_id, f, i.evidence_id);
    continue when security.field_absence_unchanged_v1(i.course_id, f, i.evidence_id);
    -- the reader's own rule: the same copy did not state it before (enrich_fields_slice_v1)
    continue when exists (select 1 from pipeline.field_enrich_items o where o.course_id = i.course_id and o.field = f and o.evidence_id = i.evidence_id and o.state = 'skipped'
                            and o.reason in ('the page does not state it', 'the page names no campus', 'only a site-wide line mentions international', 'no campus named on the page'));
    -- description and deadline: the standing daily limit counts these too
    continue when f in ('description', 'deadline') and v_auto and coalesce(j.args->>'standing', 'false') = 'true'
                  and (select count(*) from pipeline.field_enrich_items e join pipeline.admin_jobs j2 on j2.id = e.job_id
                        where e.field = f and e.created_at > now() - interval '1 day' and coalesce((j2.args->>'standing')::boolean, false)) >= v_text_cap;  -- fixed: the cap is a day's
    insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, tried, storage_path, evidence_id)
    values (i.job_id, i.provider_id, i.course_id, f, 'ai', 'ai_stored', array['ai_stored'], i.storage_path, i.evidence_id)
    on conflict do nothing;
    get diagnostics v_k = row_count;  -- the item gate (held courses) may refuse it
    if v_k > 0 then
      v_n := v_n + 1;
      if f = 'campus' then  -- a campus is linked through the university's campus list, as in the standing queue
        insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state) values (i.job_id, i.provider_id, null, 'campus_list', 'waiting') on conflict do nothing;
      end if;
    end if;
  end loop;
  return v_n;
end $$;
comment on function security.enrich_siblings_v1(bigint) is 'CF-247 Release B (mandate 3 Nov 2026 13:09 §6 priority 2): when the reader takes a course''s stored page for one field, adds the course''s other missing fields (enrich.multi_field_fields, at most enrich.multi_field_max_per_page) to the same task on the same copy: the country''s source rules, locks, holds, items in progress, open absences not yet due, verified negatives on the same content, a person''s chosen fields and the standing daily limit for description and deadline are kept. Called by enrich_fields_slice_v1.';
revoke all on function security.enrich_siblings_v1(bigint) from public, anon, authenticated;

-- job field-gap-queue: run when the next batch is due (§6 priority 5)
create or replace function security.field_gap_queue_due_v1() returns boolean language sql stable security definer set search_path = '' as $$
  with l as (select r.run_at, r.outcome, r.items from pipeline.field_gap_queue_runs r order by r.id desc limit 1),
  k as (select c.cursor_course_id from pipeline.field_gap_queue_checkpoint c where c.id = 1)
  select not exists (select 1 from pipeline.admin_jobs j where j.kind = 'enrich_fields' and coalesce((j.args->>'standing')::boolean, false) and j.state in ('queued', 'running', 'paused'))
     and (not exists (select 1 from l)
          or ((select l.run_at from l) <= now() - make_interval(mins => security.pipeline_num_v1('gaps.advance_minutes', 60)::int) + interval '5 minutes'  -- fixed: the hourly job starts a few seconds either side
              and ((select k.cursor_course_id from k) is not null or (select l.outcome from l) in ('done', 'held')
                   or (select l.run_at from l) <= now() - make_interval(mins => security.pipeline_num_v1('gaps.idle_rerun_minutes', 360)::int) + interval '5 minutes'))) -- fixed: as above
$$;
comment on function security.field_gap_queue_due_v1() is 'CF-247 Release B (mandate 3 Nov 2026 13:09 §6 priority 5): whether job field-gap-queue (checked hourly) starts its next batch: no standing task open, gaps.advance_minutes since the last run, and the pass unfinished or the last run found work, or gaps.idle_rerun_minutes since a run that found nothing.';
revoke all on function security.field_gap_queue_due_v1() from public, anon, authenticated;

-- 4. md5-guarded edits of the live engine -------------------------------------------------------------------------------------------------
-- 4a the reader takes one stored copy for every missing field; an unchanged copy is not read again after a verified negative
select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', '4babdac64e58459fe38d79def27842ea', 'c385d9c3a9fd33614f189773e45683f3', array[
  [$o$not coalesce((j.args->>'read_now')::boolean, false) and exists (
             select 1 from pipeline.field_enrich_items o$o$,
   $n$not coalesce((j.args->>'read_now')::boolean, false) and (security.field_absence_unchanged_v1(it.course_id, it.field, v_ev) or exists (
             select 1 from pipeline.field_enrich_items o$n$],
  [$o$'no campus named on the page')) then
          update pipeline.field_enrich_items set reason = 'the same page copy$o$,
   $n$'no campus named on the page'))) then
          -- CF-247 Release B (D2): or a verified negative on a copy with the same content (security.field_absence_unchanged_v1)
          update pipeline.field_enrich_items set reason = 'the same page copy$n$],
  [$o$        update pipeline.field_enrich_items set state = 'ai', source = 'ai_stored', storage_path = v_path, evidence_id = v_ev, updated_at = now() where id = it.id;
        v_settled := true; exit;$o$,
   $n$        update pipeline.field_enrich_items set state = 'ai', source = 'ai_stored', storage_path = v_path, evidence_id = v_ev, updated_at = now() where id = it.id;
        perform security.enrich_siblings_v1(it.id);  -- CF-247 Release B (§6 priority 2): the course's other missing fields from the same copy
        v_settled := true; exit;$n$]], array[1, 1, 1]);

-- 4b a course's due items of a task are leased together (one page read for all of them)
select pg_temp.edit_once('public.svc_enrich_ai_next(integer)', 'dfaff31828c7d99d46f25719e5d985cf', 'e4bdf62857d011458e3293006a7e7426', array[
  [$o$  with pick as (select e.id from pipeline.field_enrich_items e
                 where (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3
                 order by e.job_id, (e.course_id is null), e.course_id, e.id limit v_lim for update skip locked),  -- a course's fields together$o$,
   $n$  with pick0 as (select e.id, e.job_id, e.course_id from pipeline.field_enrich_items e
                 where (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3
                 order by e.job_id, (e.course_id is null), e.course_id, e.id limit v_lim for update skip locked),  -- a course's fields together
  -- CF-247 Release B (§6 priority 2): with enrich.multi_field_on, the rest of each leased course's due stored-page items of the same task too
  pick1 as (select e.id from pipeline.field_enrich_items e
             where security.pipeline_num_v1('enrich.multi_field_on', 1) >= 1 and e.source = 'ai_stored' and e.course_id is not null
               and (e.job_id, e.course_id) in (select p0.job_id, p0.course_id from pick0 p0 where p0.course_id is not null)
               and (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3
             for update skip locked),
  pick as (select p0.id from pick0 p0 union select p1.id from pick1 p1),$n$]], array[1]);

-- 4c the reader version of each answer is kept with the absence it explains
select pg_temp.edit_once('public.svc_enrich_ai_record(jsonb)', 'ae1ced1c1f1fd092afe885cfc37be0b4', 'bcbfc91ce997b1516d90b1320264fa12', array[
  [$o$    if i.id is null then continue; end if;
    v_ev := i.evidence_id;$o$,
   $n$    if i.id is null then continue; end if;
    -- CF-247 Release B (D3): the reader version recorded with an absence (pipeline.course_field_absence.reader_version)
    perform set_config('cf247.reader_version', left(coalesce(nullif(concat_ws(' ', nullif(r->>'worker', ''), nullif(r->>'prompt_version', ''), nullif(r->>'model', '')), ''),
                                                                'enrich_ai ' || coalesce(i.source, '') || ' ' || coalesce((select m.model_identifier from pipeline.central_ai_settings m where m.id = 1), '')), 200), true);
    v_ev := i.evidence_id;$n$]], array[1]);

-- 4d D3: a source that returned nothing does not raise the "no value" hold (it is classified needs_source_discovery or evidence_pending)
select pg_temp.edit_once('security.field_enrich_items_flag_v1()', 'd2180b8be792558f8c9f3fa1eb3daf98', 'a874a3b37e11a116f39742c80311a50b', array[
  [$o$'(does not state|names no campus|quote is not on the page|site-wide line|no allowed source|not classified)'$o$,
   $n$'(does not state|names no campus|quote is not on the page|site-wide line|not classified)'$n$]], array[1]);

-- 4e the coverage cache shows the absence class for absence.coverage_fields instead of a blanket "not on page"
select pg_temp.edit_once('security.course_coverage_build_v1()', 'f698bf7f6cc2130adf3c9a4e174c3810', '2f6a9a8314281004d9fa4253527a5488', array[
  [$o$  create temp table _reg on commit drop as select field attribute, reader from pipeline.field_register where level='course' and active;$o$,
   $n$  create temp table _reg on commit drop as select field attribute, reader from pipeline.field_register where level='course' and active;
  -- CF-247 Release B (D2): the open absence of each course field and the state its class shows
  create temp table _ab on commit drop as
    select a.course_id, a.field, a.absence_class, k.coverage_state,
           a.field = any (array(select jsonb_array_elements_text(case when jsonb_typeof(security.toolset_setting('pipeline','absence.coverage_fields'))='array'
                                                                      then security.toolset_setting('pipeline','absence.coverage_fields') else '[]'::jsonb end))) by_class
      from pipeline.course_field_absence a join pipeline.field_absence_classes k on k.code=a.absence_class where a.resolved_at is null;$n$],
  [$o$  insert into pipeline.course_attribute_coverage(course_id,provider_id,attribute,state,tier,computed_at,country_code)$o$,
   $n$  insert into pipeline.course_attribute_coverage(course_id,provider_id,attribute,state,tier,computed_at,country_code,absence_class)$n$],
  [$o$      when g.reader='enrich' and ei.state in ('skipped','failed') then 'not_on_page'$o$,
   $n$      when g.reader='enrich' and ei.state in ('skipped','failed') and ab.by_class
        then coalesce(ab.coverage_state, case when r.blocked or sw.read_status in ('blocked','robots_disallowed') then 'blocked'
                                              when f.course_id is not null or v.url or sw.status='bound' or sw.verified or r.read_ok then 'page_found'
                                              when s.provider_id is not null then 'site_known' else 'no_website' end)
      when g.reader='enrich' and ei.state in ('skipped','failed') then 'not_on_page'$n$],
  [$o$    t.tier, now(), c.country_code
  from _c c$o$,
   $n$    t.tier, now(), c.country_code, case when not a.has then ab.absence_class end
  from _c c$n$],
  [$o$  left join _ei ei on ei.course_id=c.course_id and ei.field=case a.attribute when 'campus_city' then 'campus' else a.attribute end$o$,
   $n$  left join _ei ei on ei.course_id=c.course_id and ei.field=case a.attribute when 'campus_city' then 'campus' else a.attribute end
  left join _ab ab on ab.course_id=c.course_id and ab.field=a.attribute$n$]], array[1, 1, 1, 1, 1]);

-- 4f job source-proof-feed: every run recorded (Integration Controller 3 Nov 2026 13:50)
create table if not exists pipeline.source_proof_feed_runs (
  id bigserial primary key, run_at timestamptz not null default now(), outcome text not null check (outcome in ('done', 'held', 'idle')), hold_reason text,
  settled int not null default 0, routed jsonb not null default '{}'::jsonb, ms int);
create index if not exists source_proof_feed_runs_at_idx on pipeline.source_proof_feed_runs (run_at desc);
comment on table pipeline.source_proof_feed_runs is 'CF-247 Release B (Integration Controller 3 Nov 2026 13:50): every run of job source-proof-feed (security.source_proof_feed_v1): done (requests settled or courses routed to a lane), held (courses considered, none routable now: nothing_routable, or every waiting course already has an open request: requests_open), idle (no course waits for page proof: no_page_proof_input); with the settled count, the routes taken and the run time.';
select pg_temp.edit_once('security.source_proof_feed_v1()', '085c5dbb58b662260846526229c7b613', 'cade6b2de219c216709129ce4bc447ff', array[
  [$o$  return jsonb_build_object('settled', v_settled, 'routed', n, 'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);  -- fixed: milliseconds$o$,
   $n$  -- CF-247 Release B (Integration Controller 3 Nov 2026 13:50): every run is recorded with an honest outcome (pipeline.source_proof_feed_runs)
  v_act := v_settled > 0 or coalesce((n->>'relink')::int, 0) + coalesce((n->>'search')::int, 0) > 0;
  insert into pipeline.source_proof_feed_runs(outcome, hold_reason, settled, routed, ms)
  values (case when v_act then 'done' when n <> '{}'::jsonb then 'held'
               when exists (select 1 from pipeline.course_page_proofs pp where not pp.proven) then 'held' else 'idle' end,
          case when v_act then null when n <> '{}'::jsonb then 'nothing_routable'
               when exists (select 1 from pipeline.course_page_proofs pp where not pp.proven) then 'requests_open' else 'no_page_proof_input' end,
          v_settled, n, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);  -- fixed: milliseconds
  return jsonb_build_object('settled', v_settled, 'routed', n, 'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);  -- fixed: milliseconds$n$]], array[1]);

-- 5. the absence of delivery and duration already settled (the coverage fields): classified from each course's latest settled item ------------
-- (bounded: the latest item of each course for these fields; a data write beside the catalogue, nothing changed in it)
do $b$
declare v_n int;
begin
  if exists (select 1 from pipeline.course_field_absence) then return; end if;  -- fixed: once
  select count(*) into v_n from (
    select security.field_absence_classify_v1(x.id)
      from (select distinct on (e.course_id, e.field) e.id, e.state, e.course_id, e.field from pipeline.field_enrich_items e
             where e.course_id is not null and e.field in (select jsonb_array_elements_text(security.toolset_setting('pipeline', 'absence.coverage_fields')))
             order by e.course_id, e.field, e.id desc) x
     where x.state in ('skipped', 'failed') and security.enrich_course_field_missing_v1(x.course_id, x.field)) z;
  raise notice 'release B: % delivery and duration absences classified', v_n;
end $b$;

-- 6. job field-gap-queue: checked hourly, runs when the next batch is due --------------------------------------------------------------------
do $j$
declare v_id bigint; v_cmd text; v_sched text;
begin
  select j.jobid, j.command, j.schedule into v_id, v_cmd, v_sched from cron.job j where j.jobname = 'field-gap-queue';
  if v_id is null then raise exception 'release B: job field-gap-queue not found'; end if;
  if v_cmd = 'select security.field_gap_queue_run_v1() where security.field_gap_queue_due_v1()' and v_sched = '23 * * * *' then return; end if;
  if v_cmd <> 'select security.field_gap_queue_run_v1()' or v_sched <> '23 */6 * * *' then
    raise exception 'release B: field-gap-queue runs % at % (not what this change was written against)', v_cmd, v_sched; end if;
  perform cron.alter_job(v_id, schedule := '23 * * * *', command := 'select security.field_gap_queue_run_v1() where security.field_gap_queue_due_v1()');
end $j$;
update pipeline.automation_catalogue set description = description || ' Every run is recorded with its outcome and hold reason (pipeline.source_proof_feed_runs).'
 where jobname = 'source-proof-feed' and description not like '%source_proof_feed_runs%';
update pipeline.automation_catalogue set description = replace(description, 'Every 6 hours: ', 'Checked every hour (CF-247 Release B): ')
 where jobname = 'field-gap-queue' and description like 'Every 6 hours: %';
update pipeline.automation_catalogue set description = description || ' Starts its next batch only when security.field_gap_queue_due_v1 says so: no standing task open, gaps.advance_minutes since the last run, and the pass unfinished or the last run found work, or gaps.idle_rerun_minutes after a run that found nothing.'
 where jobname = 'field-gap-queue' and description not like '%field_gap_queue_due_v1%';

-- 7. component register ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.field_absence_classes', 'Layer 2', 'Enrichment', 'Absence catalogue (D2, D3): why a course field has no value and what makes it due again', 'active', '{}', '20261103210000'),
 ('table', 'pipeline.field_absence_rules', 'Layer 2', 'Enrichment', 'How a settled Enrich fields item is classified (D3)', 'active', '{}', '20261103210000'),
 ('table', 'pipeline.course_field_absence', 'Layer 2', 'Enrichment', 'The absence record per course and field (evidence, reader, confidence, next eligibility)', 'active', '{}', '20261103210000'),
 ('function', 'security.field_absence_classify_v1', 'Layer 2', 'Enrichment', 'Classifies a settled Enrich fields item (D2, D3)', 'active', '{}', '20261103210000'),
 ('function', 'security.field_enrich_items_absence_trg_v1', 'Layer 2', 'Enrichment', 'Trigger field_enrich_items_absence', 'active', '{}', '20261103210000'),
 ('function', 'security.field_absence_due_v1', 'Layer 2', 'Enrichment', 'An open absence is due again (evidence change or date)', 'active', '{}', '20261103210000'),
 ('function', 'security.field_absence_unchanged_v1', 'Layer 2', 'Enrichment', 'A verified negative on the same content: not read again', 'active', '{}', '20261103210000'),
 ('function', 'security.field_absence_other_page_v1', 'Layer 2', 'Enrichment', 'Another stored reading of the course holds the field', 'active', '{}', '20261103210000'),
 ('function', 'security.enrich_course_field_missing_v1', 'Layer 2', 'Enrichment', 'A course is missing a field (gap queue rules)', 'active', '{}', '20261103210000'),
 ('function', 'security.enrich_siblings_v1', 'Layer 2', 'Enrichment', 'Every missing field read from the same stored page (multi-field)', 'active', '{}', '20261103210000'),
 ('function', 'security.field_gap_queue_due_v1', 'Layer 2', 'Enrichment', 'Job field-gap-queue: the next batch is due', 'active', '{}', '20261103210000'),
 ('table', 'pipeline.source_proof_feed_runs', 'Layer 2', 'Enrichment', 'Every run of job source-proof-feed with its outcome and hold reason', 'active', '{}', '20261103210000')
on conflict do nothing;

-- 8. post-check ------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('enrich.multi_field_on', 'enrich.multi_field_fields',
        'enrich.multi_field_max_per_page', 'absence.verified_min_confidence', 'absence.pending_recheck_hours', 'absence.coverage_fields', 'gaps.advance_minutes', 'gaps.idle_rerun_minutes')) <> 8 then
    raise exception 'release B post-check: a setting is missing'; end if;
  if (select count(*) from pipeline.field_absence_classes where code in ('not_on_this_page', 'on_other_stored_page', 'needs_source_discovery', 'evidence_pending',
        'explicitly_not_stated', 'not_applicable', 'identity_unresolved')) <> 7 then raise exception 'release B post-check: the absence catalogue is incomplete'; end if;
  if (select count(*) from pg_trigger where tgname = 'field_enrich_items_absence' and tgrelid = 'pipeline.field_enrich_items'::regclass) <> 1 then
    raise exception 'release B post-check: trigger field_enrich_items_absence missing'; end if;
  if (select command from cron.job where jobname = 'field-gap-queue') <> 'select security.field_gap_queue_run_v1() where security.field_gap_queue_due_v1()' then
    raise exception 'release B post-check: field-gap-queue does not check that its next batch is due'; end if;
end $$;
