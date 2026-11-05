-- CF-247 final intake recovery (Platform Admin mandate "StudySearch — Final Intake Recovery Strategy and Self-Sustainability Acceptance",
-- 5 Nov 2026 12:44, recorded verbatim in admin docs/platform/2026-11-05-final-intake-recovery-strategy-mandate-1244.md; process record
-- docs/platform/processes/intake-dates.md §7). One bounded change on the existing architecture: no new engine, controller, scheduler or screen.
-- Why (measured 11:21-12:26, process record §7): R1 UNSW prints its year in year tabs above repeated Term blocks, so the reader kept 42 starts
--   with no year and 153 UNSW rows wait "for next academic year" although the 2027 dates are stored; R2 the Melbourne and Sydney key-dates
--   pages held are 2026 editions. 494 stored documents wait in calendar re-read order, most of them not needed by any intake row.
-- What:
--   1 Re-read on a reader change (R1): the worker's calendar reader is calendar-v2.1 (section year: coverage-sweep calendar.ts). The re-read
--     state keeps the reader version; public.svc_calendar_reread_next_v2(limit, reader) wakes every document read by an earlier reader,
--     reads only relevant documents (top Australian universities in the intake scope, a main teaching calendar address, intake rows still
--     missing a date), most missing rows first, and sets the rest aside with the reason "not needed" (woken again when they become relevant).
--     public.svc_calendar_reread_record_v2 records the reader version. The v1 pair is marked retiring.
--   2 Durable failure classes (mandate §9): security.intake_failure_class_v1 and a trigger on pipeline.course_intake_dates and
--     pipeline.course_intake_date_events (new columns failure_class, deterministic, revisit_trigger, evidence_year, reader, related_case).
--     An unchanged deterministic failure is never looked at again on a timer: its revisit is cleared and only a change of its inputs
--     (calendar set and reader, page evidence, course page, settings: intake_inputs_fp_v1) brings it back.
--   3 Publication check (mandate §6): security.intake_publication_check_v1 compares every admitted value with the Website API v2 source
--     (search.course_documents.intake_options, read only); a value admitted but not published is class consumer_publication_failed.
--     Run after job intake-dates-apply and before job process-results (their commands gain one call; no new job).
--   4 Bounded calendar refresh (R2, mandate: at most 40 Firecrawl credits in total, top 10 only): pipeline.calendar_refresh_requests and
--     public.svc_calendar_refresh_v1, called by the existing calendar-reread run after its reads. A stored main teaching calendar of a top
--     university is asked to be read again by the existing provider-facts job (status found) only when its reading by the current reader
--     shows no next-year start, the university holds no equivalent next-year edition, the copy is older than the setting, it is not a
--     person's decision, and it was not asked before. Credits are taken from pipeline.firecrawl_calls; the budget counts the larger of the
--     estimate and the use. The old edition stays (a new evidence artifact is registered; nothing replaced or deleted). Yield is recorded.
--   5 Process results: security.process_results_recovery_v1 (admitted and published by university, source type, year and precision; classes;
--     skipped and failed with reason and next revisit; refresh credits and yield; reader progress) recorded as process intake-recovery by job
--     process-results, and view recovery of public.admin_process_results_v1 (md5-guarded edit 1eadf705).
--   6 The Preview's rule label names plan v3 (md5-guarded edits: intake_ui_selection_v1 36ecb3ad, run_now_cohort_create_v1 a8b976cb).
-- Consumer API: unchanged (G3). search.course_documents is read only. Values still reach intakes[] only through intake_dates_apply_v1.
-- Replaces: public.svc_calendar_reread_next(integer) and public.svc_calendar_reread_record(uuid,jsonb,boolean,text,text) (by the _v2 pair; marked retiring); md5-guarded edits of admin_process_results_v1, intake_ui_selection_v1, run_now_cohort_create_v1
-- Retires: nothing (the v1 re-read pair is marked retiring; dropped by a paste file after hygiene.retire_after_days once unused)
-- Nothing is dropped or deleted.

create or replace function pg_temp.edit(p_sig text, p_md5 text, p_marker text, p_old text[], p_new text[], p_times int[]) returns text language plpgsql as $e$
declare v text := pg_get_functiondef(p_sig::regprocedure); i int; n int;
begin
  if position(p_marker in v) > 0 then return p_sig || ': already applied'; end if;
  if md5(v) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %, expected %)', p_sig, md5(v), p_md5; end if;
  for i in 1 .. array_length(p_old, 1) loop
    n := (length(v) - length(replace(v, p_old[i], ''))) / length(p_old[i]);
    if n <> p_times[i] then raise exception '%: edit % must apply exactly % time(s), found %', p_sig, i, p_times[i], n; end if;
    v := replace(v, p_old[i], p_new[i]);
  end loop;
  execute v;
  return p_sig || ': edited';
end $e$;

-- 0 settings (G2) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'central.calendar_refresh_credit_budget', 'Calendar refresh: Firecrawl credits in total',
  'Most Firecrawl credits that calendar refresh may ever use (counted as the larger of each request''s estimate and its recorded use). When reached, no further refresh is asked.',
  'number', to_jsonb(40), 0, 200, 'credits', 1005, 'Intake dates', 'public.svc_calendar_refresh_v1; job calendar-reread',
  'Platform Admin mandate 5 Nov 2026 12:44 R2: up to 40 Firecrawl credits in total, top 10 only'),
 ('pipeline', 'central.calendar_refresh_credits_per_read', 'Calendar refresh: credits counted for a request',
  'Credits reserved for one refresh request before its use is recorded (a PDF read may use more than a page).',
  'number', to_jsonb(2), 1, 20, 'credits', 1006, 'Intake dates', 'public.svc_calendar_refresh_v1', 'Mandate 5 Nov 2026 R2: record credit use'),
 ('pipeline', 'batch.calendar_refresh', 'Calendar refresh: requests a run',
  'Stored calendars asked to be read again in one calendar-reread run.', 'number', to_jsonb(2), 0, 10, 'documents', 1007, 'Job sizes',
  'public.svc_calendar_refresh_v1; job calendar-reread', 'Mandate 5 Nov 2026 R2: bounded'),
 ('pipeline', 'central.calendar_refresh_min_age_days', 'Calendar refresh: stored copy at least this old',
  'A stored calendar is asked to be read again only when its copy is older than this.', 'number', to_jsonb(7), 1, 90, 'days', 1008, 'Intake dates',
  'public.svc_calendar_refresh_v1', 'Mandate 5 Nov 2026 R2: refresh stale editions only'),
 ('pipeline', 'batch.intake_publication_check', 'Publication check: rows a run',
  'Admitted intake values compared with the Website API v2 source in one check (after intake-dates-apply and before process-results).',
  'number', to_jsonb(500), 50, 5000, 'rows', 1009, 'Job sizes', 'security.intake_publication_check_v1; jobs intake-dates-apply, process-results',
  'Mandate 5 Nov 2026 §6: verify extracted to published, no silent drop')
on conflict (toolset_key, key) do nothing;

-- 1 columns and tables (beside the consumer shapes) -----------------------------------------------------------------------------------------
alter table pipeline.calendar_reread_state add column if not exists reader_version text;
alter table pipeline.course_intake_dates add column if not exists failure_class text, add column if not exists deterministic boolean,
  add column if not exists revisit_trigger text, add column if not exists evidence_year int, add column if not exists reader text,
  add column if not exists related_case text, add column if not exists publication_state text, add column if not exists publication_checked_at timestamptz;
alter table pipeline.course_intake_date_events add column if not exists failure_class text, add column if not exists deterministic boolean,
  add column if not exists revisit_trigger text, add column if not exists evidence_year int, add column if not exists reader text,
  add column if not exists related_case text, add column if not exists publication_state text, add column if not exists publication_checked_at timestamptz;
create index if not exists course_intake_dates_publication_idx on pipeline.course_intake_dates(publication_checked_at) where outcome = 'filled';

create table if not exists pipeline.calendar_refresh_requests (
  id bigserial primary key, fact_source_id uuid not null references pipeline.provider_fact_sources(id), provider_id uuid not null, url text not null,
  reader_version text, reason text not null, old_evidence_id uuid, old_content_hash text, old_read_at timestamptz, credit_estimate numeric not null,
  requested_at timestamptz not null default now(), status text not null default 'requested'
    check (status in ('requested', 'new_edition_stored', 'unchanged', 'failed')),
  new_evidence_id uuid, new_content_hash text, credits_used numeric, yield text check (yield in ('pending', 'next_year_starts', 'no_next_year')),
  next_year_starts int, resolved_at timestamptz);
comment on table pipeline.calendar_refresh_requests is 'CF-247 final intake recovery (Platform Admin mandate 5 Nov 2026 12:44 R2): each stored main teaching calendar of a top Australian university asked to be read again by the existing provider-facts job because its reading by the current calendar reader shows no next-year start and no equivalent edition is held: the reason, the old edition (kept), the credit estimate and use (pipeline.firecrawl_calls), the outcome and the useful yield. At most central.calendar_refresh_credit_budget credits in total; one request a document. Written by public.svc_calendar_refresh_v1; never read by the consumer API.';
create unique index if not exists calendar_refresh_requests_one_open on pipeline.calendar_refresh_requests(fact_source_id) where status = 'requested';
create index if not exists calendar_refresh_requests_url_idx on pipeline.calendar_refresh_requests(url);
alter table pipeline.calendar_refresh_requests enable row level security;

-- 2 failure classes (mandate §9) -----------------------------------------------------------------------------------------------------------
create or replace function security.calendar_latest_year_v1(p_provider uuid) returns int
language sql stable security definer set search_path to '' as $function$
  select max(p.year) from security.calendar_dated_periods_v2(p_provider) p where p.kind = 'start' and p.year_ok
$function$;
comment on function security.calendar_latest_year_v1(uuid) is 'CF-247 (mandate 5 Nov 2026 §9): the latest academic year a university''s main teaching calendars prove (a start whose year is printed in its quote or its section); null when none is proved.';

create or replace function security.intake_failure_class_v1(p_outcome text, p_reason text, p_complete boolean, p_deadline_kind text, p_provider uuid, p_intake_year int, p_month int)
returns table(failure_class text, deterministic boolean, revisit_trigger text)
language plpgsql stable security definer set search_path to '' as $function$
declare v_latest int; v_target int := coalesce(p_intake_year, extract(year from (now() at time zone 'Australia/Melbourne'))::int + 1);  -- fixed: the calendar year in Australia
        v_key text := 'cf247.intake_cal_' || replace(coalesce(p_provider::text, 'none'), '-', ''); v_cal jsonb;
begin
  if p_outcome in ('filled', 'nothing_new') then
    if p_complete then return; end if;
    if p_deadline_kind = 'not_stated' then
      failure_class := 'missing_application_deadline_evidence'; deterministic := true; revisit_trigger := 'the calendar or the course page prints a closing date'; return next; return;
    end if;
    return;
  end if;
  failure_class := case
    when p_reason in ('intakes locked by hand', 'course held', 'kept by a lock or the same-month guard') then 'admission_held'
    when p_reason like 'no valid academic calendar%set aside%' then 'wrong_institution_or_campus'
    when p_reason like 'no valid academic calendar%' then 'no_valid_calendar_source'
    when p_reason in ('no page behind the intake', 'page refused for this course') or p_reason like 'page not proved%' then 'course_identity_unresolved'
    when p_reason like 'no stored reading of the page%' then 'calendar_interpretation_failed'
    when p_reason like 'the calendar does not print the year%' or p_reason like 'the year of the named period is not printed%' then 'academic_year_unproven'
    when p_reason like 'several study periods start%' or p_reason like 'two start days%' then 'multiple_periods_match'
    when p_reason like 'the course page gives its own start date%' or p_reason like 'the page excludes this month%' or p_reason = 'intake is not a month' then 'course_level_exception'
    when p_reason like 'the course page names no study period%' or p_reason = 'the named period does not start in this month' then 'no_matching_commencement_period'
    when p_reason like '%past%' or p_reason like 'the calendar has no future start%' or p_reason like 'the calendar prints no start%' then 'waiting'
    else 'calendar_interpretation_failed' end;
  if failure_class = 'waiting' then
    -- a start in this month whose year is not proved (none printed, or claimed for the intake's year without evidence): the year is unproven;
    -- else no proved edition reaches the intake's year: the edition is stale; else the next start is a later year's
    -- the university's dated starts, read once a transaction (a run classifies many rows of one university)
    v_cal := nullif(current_setting(v_key, true), '')::jsonb;
    if v_cal is null then
      v_cal := jsonb_build_object('latest', (select max(s.year) from security.calendar_dated_periods_v2(p_provider) s where s.kind = 'start' and s.year_ok),
                                  'unproven', coalesce((select jsonb_agg(distinct jsonb_build_object('m', s.month, 'y', s.year)) from security.calendar_dated_periods_v2(p_provider) s
                                                         where s.kind = 'start' and not coalesce(s.year_ok, false)), '[]'::jsonb));
      perform set_config(v_key, v_cal::text, true);
    end if;
    if exists (select 1 from jsonb_array_elements(v_cal->'unproven') u where (u->>'m')::int = p_month and (u->>'y' is null or (u->>'y')::int = p_intake_year)) then
      failure_class := 'academic_year_unproven';
    else
      v_latest := (v_cal->>'latest')::int;
      failure_class := case when v_latest is null then 'academic_year_unproven' when v_latest < v_target then 'stale_calendar_edition' else 'waiting_for_next_academic_year' end;
    end if;
  end if;
  deterministic := failure_class not in ('course_identity_unresolved', 'waiting_for_next_academic_year', 'consumer_publication_failed');
  revisit_trigger := case failure_class
    when 'admission_held' then 'the lock or hold is removed'
    when 'wrong_institution_or_campus' then 'the main campus teaching calendar is approved'
    when 'no_valid_calendar_source' then 'an official main teaching calendar is approved'
    when 'course_identity_unresolved' then 'the course page is proved (Course Link) or the revisit date'
    when 'calendar_interpretation_failed' then 'the calendar reader or the stored page changes'
    when 'academic_year_unproven' then 'the calendar reader or the stored calendar changes'
    when 'stale_calendar_edition' then 'a newer calendar edition is stored (calendar refresh or provider facts)'
    when 'multiple_periods_match' then 'the course page names its period, or the calendar changes'
    when 'course_level_exception' then 'a person decides, or the course page changes'
    when 'no_matching_commencement_period' then 'the course page or the calendar changes'
    when 'waiting_for_next_academic_year' then 'the revisit date (intake_dates.revisit_days)' end;
  return next;
end $function$;
comment on function security.intake_failure_class_v1(text, text, boolean, text, uuid, int, int) is 'CF-247 (mandate 5 Nov 2026 §9): the durable failure class of an intake date decision (no valid calendar source, stale calendar edition, wrong institution or campus, course identity unresolved, calendar interpretation failed, academic year unproven, no matching commencement period, multiple periods match, course-level exception, missing application deadline evidence, admission held, waiting for next academic year; consumer publication failed is set by the publication check), whether it is deterministic, and the change that brings it back.';

create or replace function security.intake_failure_class_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $function$
declare c record; v_year int; v_month int;
begin
  select i.intake_year, array_position(array['january','february','march','april','may','june','july','august','september','october','november','december'], lower(btrim(i.intake_label)))
    into v_year, v_month from catalogue.course_intakes i where i.id = new.intake_id;
  select * into c from security.intake_failure_class_v1(new.outcome, new.reason, new.next_action = 'complete', new.deadline_kind, new.provider_id, v_year, v_month);
  new.failure_class := c.failure_class; new.deterministic := c.deterministic; new.revisit_trigger := c.revisit_trigger;
  new.evidence_year := coalesce((new.after_value->>'year')::int, v_year);
  new.reader := (select p.parser from pipeline.provider_policy_proposals p where p.id = new.proposal_id);
  new.related_case := case when c.failure_class in ('wrong_institution_or_campus', 'no_valid_calendar_source', 'stale_calendar_edition', 'academic_year_unproven')
                             then 'calendar:' || coalesce(new.calendar_evidence_id::text, new.provider_id::text)
                           when c.failure_class = 'course_identity_unresolved' then 'course:' || new.course_id end;
  -- mandate §9: an unchanged deterministic failure is never repeated on a timer; only a change of its inputs brings it back
  if c.deterministic then new.next_revisit_at := null; end if;
  return new;
end $function$;
comment on function security.intake_failure_class_trg_v1() is 'CF-247 (mandate 5 Nov 2026 §9): sets the failure class, deterministic flag, revisit trigger, evidence year, reader and related case of an intake date decision; clears the timer revisit of a deterministic failure.';
create or replace trigger intake_failure_class before insert or update of outcome, reason, next_action, deadline_kind on pipeline.course_intake_dates
  for each row execute function security.intake_failure_class_trg_v1();
create or replace trigger intake_failure_class before insert on pipeline.course_intake_date_events
  for each row execute function security.intake_failure_class_trg_v1();

-- 3 publication check (mandate §6) ---------------------------------------------------------------------------------------------------------
create or replace function security.intake_publication_check_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare r record; v_state text; n_pub int := 0; n_fail int := 0; n_off int := 0;
begin
  for r in
    select d.intake_id, d.course_id, d.provider_id, i.intake_label, i.intake_year, i.start_date, i.application_deadline
      from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id
     where d.outcome = 'filled' and d.applied_at is not null
       and (d.publication_checked_at is null or d.publication_checked_at < d.applied_at or d.publication_state = 'consumer_publication_failed')
     order by d.publication_checked_at nulls first, d.applied_at
     limit security.pipeline_num_v1('batch.intake_publication_check', 500)::int
  loop
    v_state := case
      when exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.provider_id) then 'provider_not_published'
      when exists (select 1 from search.course_documents cd, jsonb_array_elements(coalesce(cd.intake_options, '[]'::jsonb)) e
                    where cd.course_id = r.course_id and e->>'label' = r.intake_label
                      and (e->>'year')::int is not distinct from r.intake_year
                      and (e->>'start_date')::date is not distinct from r.start_date
                      and (e->>'application_deadline')::date is not distinct from r.application_deadline) then 'published'
      else 'consumer_publication_failed' end;
    update pipeline.course_intake_dates set publication_state = v_state, publication_checked_at = now(),
           failure_class = case when v_state = 'consumer_publication_failed' then 'consumer_publication_failed' else failure_class end,
           deterministic = case when v_state = 'consumer_publication_failed' then false else deterministic end,
           revisit_trigger = case when v_state = 'consumer_publication_failed' then 'the next publication check (after the next projection refresh)' else revisit_trigger end
     where intake_id = r.intake_id;
    update pipeline.course_intake_date_events e set publication_state = v_state, publication_checked_at = now()
     where e.id = (select max(x.id) from pipeline.course_intake_date_events x where x.intake_id = r.intake_id and x.outcome = 'filled');
    if v_state = 'published' then n_pub := n_pub + 1; elsif v_state = 'provider_not_published' then n_off := n_off + 1; else n_fail := n_fail + 1; end if;
  end loop;
  return jsonb_build_object('published', n_pub, 'consumer_publication_failed', n_fail, 'provider_not_published', n_off);
end $function$;
comment on function security.intake_publication_check_v1() is 'CF-247 (mandate 5 Nov 2026 §6): every admitted intake value compared with the Website API v2 source (search.course_documents.intake_options, read only): published, provider not published (the Published switch decides), or consumer publication failed (a durable class, checked again next run). Run by jobs intake-dates-apply and process-results.';

-- 4 re-read on a reader change, relevant documents first (R1, mandate §8) -------------------------------------------------------------------
create or replace function security.calendar_reread_relevant_v1() returns table(provider_id uuid, missing int)
language sql stable security definer set search_path to '' as $function$
  select c.provider_id, count(*)::int
    from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
   where i.status = 'active' and c.lifecycle_status = 'active' and (i.start_date is null or i.intake_year is null)
     and c.provider_id in (select (e->>'id')::uuid from jsonb_array_elements(security.intake_ui_scopes_v1()) e)
   group by c.provider_id
$function$;
comment on function security.calendar_reread_relevant_v1() is 'CF-247 (mandate 5 Nov 2026 §8): the universities of the intake scope (top Australian universities) whose intake rows still miss a year or start date, with how many; the calendar re-read and refresh read only their calendars.';

create or replace function public.svc_calendar_reread_next_v2(p_limit integer, p_reader text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v jsonb; v_rel jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if coalesce(p_reader, '') = '' then raise exception 'the calendar reader version is required'; end if;
  select coalesce(jsonb_object_agg(x.provider_id, x.missing), '{}'::jsonb) into v_rel from security.calendar_reread_relevant_v1() x;
  insert into pipeline.calendar_reread_state(fact_source_id, provider_id, content_hash)
  select f.id, f.provider_id, f.content_hash from pipeline.provider_fact_sources f
   where f.kind = 'intake_calendar' and f.evidence_id is not null
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = f.provider_id)
  on conflict (fact_source_id) do update set state = 'waiting', attempts = 0, content_hash = excluded.content_hash, reason = 'the stored document changed'
   where pipeline.calendar_reread_state.content_hash is distinct from excluded.content_hash and pipeline.calendar_reread_state.state <> 'leased';
  -- the reader changed: every document read by an earlier reader is read again (none with an AI read still open)
  update pipeline.calendar_reread_state s set state = 'waiting', attempts = 0, reason = 'the calendar reader changed to ' || p_reader
   where s.reader_version is distinct from p_reader and s.state in ('dated_by_parser', 'read_by_ai', 'no_dates', 'failed', 'sent_to_ai')
     and not (s.state = 'no_dates' and s.reason like 'not needed:%')
     and not exists (select 1 from pipeline.central_ai_queue q where q.fact_source_id = s.fact_source_id and q.state in ('queued', 'leased'));
  -- set aside until needed: no intake row of the university misses a date, or the address is not a main teaching calendar
  update pipeline.calendar_reread_state s set state = 'no_dates', reader_version = p_reader, last_at = now(),
         reason = case when not v_rel ? s.provider_id::text then 'not needed: no intake row of this university in the intake scope misses a date'
                       else 'not needed: the address is not a main teaching calendar' end
    from pipeline.provider_fact_sources f
   where f.id = s.fact_source_id and s.state = 'waiting'
     and (not v_rel ? s.provider_id::text or security.calendar_scope_v1('{}'::jsonb, f.url, null) <> 'main_teaching');
  -- needed again: woken when the university's rows need a date again and the address is a main teaching calendar
  update pipeline.calendar_reread_state s set state = 'waiting', attempts = 0, reason = 'needed: intake rows of this university miss a date'
    from pipeline.provider_fact_sources f
   where f.id = s.fact_source_id and s.state = 'no_dates' and s.reason like 'not needed:%'
     and v_rel ? s.provider_id::text and security.calendar_scope_v1('{}'::jsonb, f.url, null) = 'main_teaching';
  with pick as (
    select s.fact_source_id from pipeline.calendar_reread_state s
     where (s.state = 'waiting' or (s.state = 'leased' and s.leased_until < now())) and s.attempts < 3  -- fixed: three tries, then failed with the reason
     order by (v_rel->>s.provider_id::text)::int desc nulls last, s.created_at limit greatest(1, least(coalesce(p_limit, 20), 60)) for update of s skip locked),  -- fixed: the worker's call bound
  upd as (update pipeline.calendar_reread_state s set state = 'leased', leased_until = now() + interval '4 minutes', attempts = s.attempts + 1  -- fixed: lease
            from pick where s.fact_source_id = pick.fact_source_id returning s.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'provider_id', f.provider_id, 'url', f.url, 'storage_path', e.storage_path,
           'trusted_address', security.calendar_scope_v1('{}'::jsonb, f.url, null) = 'main_teaching')), '[]'::jsonb) into v
    from upd u join pipeline.provider_fact_sources f on f.id = u.fact_source_id join pipeline.evidence_artifacts e on e.id = f.evidence_id;
  return v;
end $function$;
comment on function public.svc_calendar_reread_next_v2(integer, text) is 'CF-247 (mandate 5 Nov 2026 R1, §8): the next stored calendar documents for the given calendar reader: new, changed, or read by an earlier reader; only main teaching calendars of universities in the intake scope with rows missing a date, most missing first (the rest set aside as not needed, woken when needed); leased for the worker. Replaces svc_calendar_reread_next(integer). Service role only.';

create or replace function public.svc_calendar_reread_record_v2(p_id uuid, p_parsed jsonb, p_send_to_ai boolean, p_reason text, p_error text, p_reader text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare r jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  r := public.svc_calendar_reread_record(p_id, p_parsed, p_send_to_ai, p_reason, p_error);
  if p_error is null then update pipeline.calendar_reread_state set reader_version = p_reader where fact_source_id = p_id; end if;
  return r || jsonb_build_object('reader', p_reader);
end $function$;
comment on function public.svc_calendar_reread_record_v2(uuid, jsonb, boolean, text, text, text) is 'CF-247 (mandate 5 Nov 2026 R1): records a stored calendar document read again (svc_calendar_reread_record) with the calendar reader version that read it. Service role only.';
revoke all on function public.svc_calendar_reread_next_v2(integer, text), public.svc_calendar_reread_record_v2(uuid, jsonb, boolean, text, text, text) from public, anon, authenticated;

-- 5 bounded calendar refresh (R2) ----------------------------------------------------------------------------------------------------------
create or replace function public.svc_calendar_refresh_v1(p_reader text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_budget numeric := security.pipeline_num_v1('central.calendar_refresh_credit_budget', 40);
        v_each numeric := security.pipeline_num_v1('central.calendar_refresh_credits_per_read', 2);
        v_batch int := security.pipeline_num_v1('batch.calendar_refresh', 2)::int;
        v_age int := security.pipeline_num_v1('central.calendar_refresh_min_age_days', 7)::int;
        v_next int := extract(year from (now() at time zone 'Australia/Melbourne'))::int + 1;  -- fixed: the next academic year in Australia
        v_spent numeric; v_asked int := 0; r record; v_prop uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- outcomes of earlier requests: the provider-facts job has read the document again (or given up)
  update pipeline.calendar_refresh_requests q set
         status = case when f.status in ('failed', 'error') then 'failed' when f.content_hash is distinct from q.old_content_hash then 'new_edition_stored' else 'unchanged' end,
         new_evidence_id = f.evidence_id, new_content_hash = f.content_hash, resolved_at = now(),
         yield = case when f.content_hash is distinct from q.old_content_hash then 'pending' else 'no_next_year' end
    from pipeline.provider_fact_sources f
   where f.id = q.fact_source_id and q.status = 'requested' and f.status not in ('found', 'reading') and f.updated_at > q.requested_at;
  update pipeline.calendar_refresh_requests q set credits_used = (select coalesce(sum(c.credits_used), 0) from pipeline.firecrawl_calls c where c.url = q.url and c.at >= q.requested_at
                                                                     and c.at < coalesce(q.resolved_at, now()) + interval '1 hour')  -- fixed: the read follows the request
   where q.requested_at > now() - interval '7 days';  -- fixed: credits of recent requests are refreshed; older ones are settled
  -- useful yield: the new edition, read by the current reader, gives a next-year start
  for r in select q.id, q.fact_source_id from pipeline.calendar_refresh_requests q where q.yield = 'pending' loop
    select p.id into v_prop from pipeline.provider_policy_proposals p
     where p.fact_source_id = r.fact_source_id and p.kind = 'intake_calendar' and p.status = 'approved' and p.parser like '%' || p_reader
       and p.content_hash = (select f.content_hash from pipeline.provider_fact_sources f where f.id = r.fact_source_id)
     order by p.decided_at desc nulls last limit 1;
    if v_prop is not null then
      update pipeline.calendar_refresh_requests set next_year_starts = (select count(*) from security.calendar_proposal_dates_v1(v_prop) d where d.kind = 'start' and d.year >= v_next),
             yield = case when exists (select 1 from security.calendar_proposal_dates_v1(v_prop) d where d.kind = 'start' and d.year >= v_next) then 'next_year_starts' else 'no_next_year' end
       where id = r.id;
    end if;
  end loop;
  select coalesce(sum(greatest(q.credit_estimate, coalesce(q.credits_used, 0))), 0) into v_spent from pipeline.calendar_refresh_requests q;
  if v_batch > 0 then
    for r in
      with rel as (select * from security.calendar_reread_relevant_v1()),
      held as (select rel.provider_id from rel where exists (select 1 from security.calendar_dated_periods_v2(rel.provider_id) p where p.kind = 'start' and p.year_ok and p.year >= v_next))
      select f.id, f.provider_id, f.url, f.evidence_id, f.content_hash, f.read_at, rel.missing
        from pipeline.provider_fact_sources f join rel on rel.provider_id = f.provider_id join pipeline.calendar_reread_state s on s.fact_source_id = f.id
       where f.kind = 'intake_calendar' and f.evidence_id is not null and f.status not in ('found', 'reading') and f.decided_by is null and f.decision is null
         -- never a person's binding, and never a reading that says the calendar is not the main teaching calendar
         and not exists (select 1 from pipeline.provider_policy_proposals p where p.fact_source_id = f.id and p.status = 'approved'
                           and (p.decided_by is not null or p.parser = 'set by hand' or coalesce(p.proposal->>'scope', '') not in ('', 'main_teaching')))
         and security.calendar_scope_v1('{}'::jsonb, f.url, null) = 'main_teaching'
         and s.reader_version = p_reader and s.state in ('dated_by_parser', 'read_by_ai', 'no_dates') and coalesce(s.reason, '') not like 'not needed:%'
         and coalesce(f.read_at, f.updated_at) < now() - make_interval(days => v_age)
         and f.provider_id not in (select held.provider_id from held)
         and not exists (select 1 from pipeline.calendar_refresh_requests q where q.url = f.url)
         -- its own reading by the current reader shows no next-year start
         and not exists (select 1 from pipeline.provider_policy_proposals p, security.calendar_proposal_dates_v1(p.id) d
                          where p.fact_source_id = f.id and p.kind = 'intake_calendar' and p.status = 'approved' and d.kind = 'start' and d.year >= v_next)
       order by rel.missing desc, f.rank nulls last
       limit v_batch
    loop
      exit when v_spent + v_each > v_budget;
      insert into pipeline.calendar_refresh_requests(fact_source_id, provider_id, url, reader_version, reason, old_evidence_id, old_content_hash, old_read_at, credit_estimate)
      values (r.id, r.provider_id, r.url, p_reader, format('no %s start in the stored copy read by %s; no equivalent %s edition held; %s intake rows miss a date', v_next, p_reader, v_next, r.missing),
              r.evidence_id, r.content_hash, r.read_at, v_each)
      on conflict do nothing;
      update pipeline.provider_fact_sources set status = 'found', attempts = 0, updated_at = now() where id = r.id;
      v_spent := v_spent + v_each; v_asked := v_asked + 1;
    end loop;
  end if;
  return jsonb_build_object('asked', v_asked, 'credits_counted', v_spent, 'budget', v_budget,
    'open', (select count(*) from pipeline.calendar_refresh_requests where status = 'requested'));
end $function$;
comment on function public.svc_calendar_refresh_v1(text) is 'CF-247 (mandate 5 Nov 2026 12:44 R2): records the outcome, credit use and yield of earlier calendar refresh requests, then asks the existing provider-facts job to read again (status found) at most batch.calendar_refresh stored main teaching calendars of top universities whose reading by the given reader shows no next-year start, with no equivalent edition held, an old copy, no person''s decision and no earlier request for the address, while the credits counted stay within central.calendar_refresh_credit_budget. The old edition is kept. Service role only.';
revoke all on function public.svc_calendar_refresh_v1(text) from public, anon, authenticated;

-- 6 process results: the recovery measurement (mandate §10, §16) ---------------------------------------------------------------------------
create or replace function security.process_results_recovery_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
  with u as (select (e->>'id')::uuid id, e->>'name' name from jsonb_array_elements(security.intake_ui_scopes_v1()) e),
  w as (select now() - make_interval(days => security.pipeline_num_v1('process_results.window_days', 7)::int) since),
  ev as (select e.* from pipeline.course_intake_date_events e, w where e.run_at >= w.since and e.provider_id in (select id from u)),
  d as (select d.* from pipeline.course_intake_dates d where d.provider_id in (select id from u))
  select jsonb_build_object(
    'measured_at', now(), 'window_since', (select since from w),
    'admitted', (select coalesce(jsonb_agg(x order by x->>'university', x->>'year'), '[]'::jsonb) from (
       select jsonb_build_object('university', u.name, 'source_type', 'approved calendar', 'rule', ev.rule, 'year', coalesce((ev.after_value->>'year')::int, (ev.before_value->>'year')::int),
                'precision', ev.start_precision, 'admitted', count(*), 'with_start_date', count(*) filter (where ev.after_value->>'start_date' is not null),
                'with_deadline', count(*) filter (where ev.after_value->>'application_deadline' is not null),
                'published', count(*) filter (where ev.publication_state = 'published'), 'publication_failed', count(*) filter (where ev.publication_state = 'consumer_publication_failed'),
                'provider_not_published', count(*) filter (where ev.publication_state = 'provider_not_published'), 'not_checked', count(*) filter (where ev.publication_state is null)) x
         from ev join u on u.id = ev.provider_id where ev.outcome = 'filled'
        group by u.name, ev.rule, coalesce((ev.after_value->>'year')::int, (ev.before_value->>'year')::int), ev.start_precision) z),
    'classes', (select coalesce(jsonb_agg(x order by (x->>'rows')::int desc), '[]'::jsonb) from (
       select jsonb_build_object('university', u.name, 'class', coalesce(d.failure_class, case when d.next_action = 'complete' then 'complete' else 'not_classified_yet' end),
                'deterministic', bool_and(d.deterministic), 'rows', count(*), 'reason', min(d.reason), 'next_revisit_at', min(d.next_revisit_at), 'revisit_trigger', min(d.revisit_trigger)) x
         from d join u on u.id = d.provider_id
        group by u.name, coalesce(d.failure_class, case when d.next_action = 'complete' then 'complete' else 'not_classified_yet' end)) z),
    'refresh', jsonb_build_object(
       'budget', security.pipeline_num_v1('central.calendar_refresh_credit_budget', 40),
       'credits_counted', (select coalesce(sum(greatest(q.credit_estimate, coalesce(q.credits_used, 0))), 0) from pipeline.calendar_refresh_requests q),
       'credits_used', (select coalesce(sum(q.credits_used), 0) from pipeline.calendar_refresh_requests q),
       'requests', (select coalesce(jsonb_agg(jsonb_build_object('university', u.name, 'url', q.url, 'requested_at', q.requested_at, 'reason', q.reason, 'status', q.status,
                       'credits_used', q.credits_used, 'yield', q.yield, 'next_year_starts', q.next_year_starts) order by q.requested_at desc), '[]'::jsonb)
                      from pipeline.calendar_refresh_requests q join u on u.id = q.provider_id)),
    'reader', (select coalesce(jsonb_agg(jsonb_build_object('reader', s.reader_version, 'state', s.state, 'documents', s.n) order by s.reader_version nulls first, s.state), '[]'::jsonb)
                 from (select reader_version, state, count(*) n from pipeline.calendar_reread_state group by 1, 2) s),
    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'last_run', (select max(r.start_time) from cron.job_run_details r where r.jobid = j.jobid),
                       'last_status', (select r.status from cron.job_run_details r where r.jobid = j.jobid order by r.start_time desc limit 1))), '[]'::jsonb)
               from cron.job j where j.jobname in ('calendar-reread', 'central-ai', 'provider-facts', 'intake-dates-apply', 'process-results')))
$function$;
comment on function security.process_results_recovery_v1() is 'CF-247 (mandate 5 Nov 2026 §10, §16): the intake recovery measurement for the top Australian universities: values admitted in the window by university, source type, rule, year and precision with their publication state; rows by failure class with reason, next revisit and trigger; calendar refresh credits, requests and yield; documents by reader version and state; the jobs. Read only.';

create or replace function security.process_results_recovery_record_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v jsonb := security.process_results_recovery_v1(); v_id bigint;
begin
  insert into pipeline.process_results(process_key, scope_key, measured_at, summary, markdown, measured_by)
  values ('intake-recovery', 'top-au', now(), v,
          '# Process record: intake recovery (generated)' || chr(10) || chr(10) || 'Measured ' || to_char(now() at time zone 'Australia/Sydney', 'YYYY-MM-DD HH24:MI') || ' Sydney.' || chr(10) || chr(10)
          || '```json' || chr(10) || jsonb_pretty(v) || chr(10) || '```' || chr(10),
          coalesce(auth.uid()::text, 'job process-results'))
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $function$;
comment on function security.process_results_recovery_record_v1() is 'CF-247 (mandate 5 Nov 2026 §10): records a dated intake recovery measurement (process intake-recovery); nothing earlier is overwritten.';

select pg_temp.edit('public.admin_process_results_v1(text,jsonb)', '1eadf70533349cdbe605b9e9aee164cb', 'p_view = ''recovery''',
  array[$o$  end if;
  raise exception 'unknown view %'$o$],
  array[$n$  elsif p_view = 'recovery' then
    -- CF-247 mandate 5 Nov 2026 §10: the intake recovery measurement, live (read only)
    return security.process_results_recovery_v1();
  end if;
  raise exception 'unknown view %'$n$], array[1]);

-- 7 the Preview's rule names plan v3 ------------------------------------------------------------------------------------------------------
select pg_temp.edit('security.intake_ui_selection_v1(text,integer)', '36ecb3ad4d8fbd7a398e570159dfe4c8', 'Existing intake-dates-plan-v3 filled outcome',
  array['Existing intake-dates-plan-v2 filled outcome'], array['Existing intake-dates-plan-v3 filled outcome'], array[1]);
select pg_temp.edit('security.run_now_cohort_create_v1(text,uuid,text,text)', 'a8b976cbb37c1f92121ed51ce49fa019', 'intake-dates-plan-v3 filled within them',
  array['intake-dates-plan-v2 filled within them'], array['intake-dates-plan-v3 filled within them'], array[1]);

-- 8 jobs (G1): the existing jobs gain one call each; no new job (both are catalogued already: the rows below change nothing when present) ---
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('intake-dates-apply', 'Admission', 65, 'Intake dates apply', 'Hourly at :26: admits intake years, start dates and deadlines from approved calendars (security.intake_dates_apply_v1).', 5, true),
 ('process-results', 'Admission', 67, 'Process results (intake dates)', 'Hourly at :53: records a dated measurement of the intake dates process.', 5, false)
on conflict (jobname) do nothing;
select cron.schedule('intake-dates-apply', '26 * * * *', $c$select security.intake_dates_apply_v1(security.pipeline_num_v1('batch.intake_dates_apply', 200)::int); select security.intake_publication_check_v1()$c$);
select cron.schedule('process-results', '53 * * * *', 'select security.intake_publication_check_v1(); select security.process_results_record_v1(); select security.process_results_recovery_record_v1()');
update pipeline.automation_catalogue set description =
  'Hourly at :13: reads stored academic calendar documents again with the current calendar reader (calendar-v2.1: the year of each start from its own section), at most Calendar re-read: documents a run (20). Only main teaching calendars of universities in the intake scope whose rows miss a date, most missing first; the rest are set aside as not needed until needed. The dated parser first; the pinned central-page model only when the parser cannot read it safely. A document is read again when it or the reader changes. After the reads, asks the provider-facts job to read again at most Calendar refresh: requests a run stored calendars with no next-year start and no equivalent edition held, within Calendar refresh: Firecrawl credits in total (40) (mandate 5 Nov 2026 12:44 R1, R2, §8).'
 where jobname = 'calendar-reread';
update pipeline.automation_catalogue set description = description || ' Before measuring, checks admitted intake values against the Website API v2 source (publication check), and records the intake recovery measurement (process intake-recovery) (mandate 5 Nov 2026 §6, §10).'
 where jobname = 'process-results' and description not like '%publication check%';
update pipeline.automation_catalogue set description = description || ' After applying, checks admitted values against the Website API v2 source (security.intake_publication_check_v1; mandate 5 Nov 2026 §6).'
 where jobname = 'intake-dates-apply' and description not like '%publication_check%';

-- 9 component register (housekeeping) -------------------------------------------------------------------------------------------------------
update pipeline.component_register set status = 'retiring', replaced_by = 'public.svc_calendar_reread_next_v2',
       retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, updated_at = now()
 where kind = 'function' and name = 'public.svc_calendar_reread_next';
update pipeline.component_register set status = 'retiring', replaced_by = 'public.svc_calendar_reread_record_v2',
       retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, updated_at = now()
 where kind = 'function' and name = 'public.svc_calendar_reread_record';
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'public.svc_calendar_reread_next', 'Layer 2', 'Admission', 'Stored calendar re-read (v1)', 'retiring', '{}', '20261105020000'),
 ('function', 'public.svc_calendar_reread_record', 'Layer 2', 'Admission', 'Stored calendar re-read record (v1)', 'retiring', '{}', '20261105020000'),
 ('function', 'public.svc_calendar_reread_next_v2', 'Layer 2', 'Admission', 'Stored calendar re-read on a reader change, relevant documents first', 'active', array['public.svc_calendar_reread_next'], '20261105040000'),
 ('function', 'public.svc_calendar_reread_record_v2', 'Layer 2', 'Admission', 'Stored calendar re-read record with the reader version', 'active', array['public.svc_calendar_reread_record'], '20261105040000'),
 ('function', 'public.svc_calendar_refresh_v1', 'Layer 2', 'Admission', 'Bounded calendar refresh (40 Firecrawl credits in total)', 'active', '{}', '20261105040000'),
 ('function', 'security.intake_publication_check_v1', 'Layer 2', 'Admission', 'Admitted intake values against the Website API v2 source', 'active', '{}', '20261105040000'),
 ('function', 'security.intake_failure_class_v1', 'Layer 2', 'Admission', 'Durable failure classes of intake date decisions', 'active', '{}', '20261105040000'),
 ('table', 'pipeline.calendar_refresh_requests', 'Layer 2', 'Admission', 'Calendar refresh requests, credits and yield', 'active', '{}', '20261105040000')
on conflict (kind, name) do nothing;
update pipeline.component_register set status = 'retiring', replaced_by = 'public.svc_calendar_reread_next_v2',
       retire_after = coalesce(retire_after, current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int)
 where kind = 'function' and name = 'public.svc_calendar_reread_next' and status <> 'retiring';
update pipeline.component_register set status = 'retiring', replaced_by = 'public.svc_calendar_reread_record_v2',
       retire_after = coalesce(retire_after, current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int)
 where kind = 'function' and name = 'public.svc_calendar_reread_record' and status <> 'retiring';
