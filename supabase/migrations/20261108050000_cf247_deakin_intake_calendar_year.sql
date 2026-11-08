-- CF-247 P0 IQ-00313 (Deakin commencement-date contamination, Platform Admin directive 8 Nov 2026): cross-year calendar resolution,
-- a calendar date admitted only inside the next cycle, and a rejected or withdrawn value is never admitted again.
-- Why (measured read-only on production, 8 Nov 2026):
--   * Ten Deakin November intakes carried start_date 2028-11-01 and intake_year 2028. They were written by job intake-dates-apply
--     (security.intake_dates_apply_v1 -> security.intake_dates_plan_v3, rule calendar-v3, runs 7 Nov 2026 14:26, 17:26, 20:26 and 23:26 UTC).
--   * The approved Deakin calendar (proposal 9d6eccfb, parser ai:gpt-4.1-mini, https://leadership.deakin.edu.au/academic-calendars) holds the
--     quote "Trimester 3: 1 Nov - 28 Jan 2028": a teaching period that STARTS on 1 November 2027 and ENDS on 28 January 2028. The reader's own
--     years for that period are [2026, 2027].
--   * security.calendar_proposal_dates_v1 gave a quote without a year after its first date "the first year anywhere in the quote", so the year
--     printed after the END date (2028) became the year of the START date: 1 Nov 2028. Nothing else printed a Deakin 2027 year, so it was the
--     only dated future start of Trimester 3 and the plan took it.
--   * The same resolver serves every university whose approved calendar was read before calendar-v2.1 (no `starts` array): 72 universities,
--     891 quotes. Other rows that the old rule dates wrongly (not yet written to any intake): ACU "Mon 4 Oct - Sun 2 Jan 2028" (research term D,
--     reader years [2027]) and Torrens "Main intake 4** | 02 Nov | 20 Nov | 07 Feb 2027".
--   * Effect of the new rule on every approved intake_calendar reading (read-only comparison with the old resolver, 8 Nov 2026): 1,409 resolver rows,
--     1,246 of them starts; 32 starts change, no row appears or disappears. 2 are corrected (Deakin Trimester 3 2028 -> 2027, ACU research term 2028 -> 2027).
--     30 lose a year the quote does not prove and are held month-only until the reader quotes the year with the date: Swinburne VE study periods 23 (the
--     year sits in a label after the end date), Cass Training 3 ("... | 3 January 2025": 1 October is 2024), Western Sydney 2, Torrens 2. No written intake changes.
-- What (existing architecture; no new job, scheduler, engine or screen):
--   1 security.calendar_proposal_dates_v1 (md5-guarded replacement, 84aa52bc): for a quote the reader gave without a `starts` array the year of
--     a start is (a) the year printed straight after its date, else (b) the last year printed before it in the same quote, else (c) for a
--     simple range "<start> - <end> <year>" the year of the END less one when the range wraps the year-end (a teaching period is under a year
--     long), else none. A year printed in a table row after several dates is never taken for the first date. A year the reader's own `years`
--     for the period do not list is dropped. The basis of (c) is kept in year_quote, so the year stays proved by evidence. Signature unchanged.
--   2 security.intake_dates_plan_v3 (md5-guarded edit, 1d531a83), three additions beside the existing gates:
--       a. the next dated start of a period is taken only when it falls within intake_dates.max_months_ahead months (setting, default 18)
--          of today; a start further away is held with the reason "the year of the named period is not printed ... " (class
--          academic_year_unproven, revisited on the timer): a calendar date alone never reaches two cycles ahead;
--       b. a calendar value recorded in pipeline.intake_date_rejections is never used again (provider, calendar reading, quote, year);
--       c. a value withdrawn from an intake (pipeline.course_intake_date_events, outcome withdrawn: its before_value is the rejected value)
--          is not admitted to that intake again; the row is held for a person with the reason "withdrawn: ...".
--   3 pipeline.intake_date_rejections (new, additive): the calendar values a person or a check rejected (the existing retraction table
--     pipeline.enrich_value_retractions is keyed on a field-enrichment item and cannot hold a calendar value).
--   4 security.intake_projection_reconcile_v1 (new): after a correction, re-evaluates the STORED Website item and the STORED Zoho item of the
--     named courses with the scans' own builders and transition rules (security.website_sync_item_v1 / zoho_sync_item_v1; the scans'
--     advisory locks), so a withdrawn intake leaves both stored items at once instead of at the next pass (about 55 minutes). The scans
--     themselves are unchanged and reach the same result.
--   5 setting intake_dates.max_months_ahead (G2): label, range, unit and used_by; changed on Settings > Pipeline settings with a reason.
-- Consumer API: unchanged (G3). Only security.* functions and pipeline.* tables are touched; the Website and Zoho objects are called, not changed.
-- Replaces: md5-guarded replacement of security.calendar_proposal_dates_v1 and md5-guarded edit of security.intake_dates_plan_v3
-- Retires: nothing (security.calendar_dated_periods_v1 keeps the old rule but is called only by the dormant intake_dates_plan_v1 and v2; listed for retirement by paste after hygiene.retire_after_days)
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

-- 0 setting (G2) ----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'intake_dates.max_months_ahead', 'Intake dates: a calendar date is taken only within this many months',
  'The intake-dates plan fills a start date from an approved calendar only when the next dated start of the course''s named study period falls within this many months of today. A start further away is held (month only) until the next cycle comes into range or the calendar is read again. It stops a calendar date reaching two academic cycles ahead.',
  'number', to_jsonb(18), 6, 36, 'months', 1012, 'Intake dates', 'security.intake_dates_plan_v3; job intake-dates-apply',
  'P0 IQ-00313 (8 Nov 2026): Deakin Trimester 3 read as 1 November 2028 instead of 1 November 2027')
on conflict (toolset_key, key) do nothing;

-- 1 the year of a start in a quote without a `starts` array (md5-guarded replacement) -------------------------------------------------------
do $$ begin
  if position('range ending' in pg_get_functiondef('security.calendar_proposal_dates_v1(uuid)'::regprocedure)) = 0
     and md5(pg_get_functiondef('security.calendar_proposal_dates_v1(uuid)'::regprocedure)) <> '84aa52bcfa132b6308df5e402c82505f' then
    raise exception 'live security.calendar_proposal_dates_v1 differs from the definition this change replaces (md5 %)', md5(pg_get_functiondef('security.calendar_proposal_dates_v1(uuid)'::regprocedure));
  end if;
end $$;
create or replace function security.calendar_proposal_dates_v1(p_proposal_id uuid)
returns table(proposal_id uuid, period text, kind text, year integer, month integer, day integer, on_date date, rolling_text text, quote text, applies_to text, meaning text, year_quote text)
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
    select per.id, per.period, 'start'::text kind, q, per.e->'years' yrs,
           regexp_match(q, '(?:\m(\d{1,2})(?:st|nd|rd|th)?\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\M|\m(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?\M)(?:,?\s+(20\d\d))?', 'i') d,
           -- the text of the first date itself (the same alternatives, in the same order), to split the quote before and after it
           (regexp_match(q, '(\m\d{1,2}(?:st|nd|rd|th)?\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\M|\m(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?\M)', 'i'))[1] dtxt
      from per, jsonb_array_elements_text(coalesce(per.e->'quotes', '[]'::jsonb)) q
     where not (per.e ? 'starts')
       and q !~* '\m(exams?|examinations?|supplementary|census|results|holidays?|break|recess|graduation|enrolment|withdraw\w*|orientation)\M'),
  cut as (
    select z.*, left(z.q, position(z.dtxt in z.q) - 1) head, substr(z.q, position(z.dtxt in z.q) + length(z.dtxt)) tail
      from quoted z where z.d is not null and z.dtxt is not null),
  rng as (
    -- "<start> - <end> <year>": the end date of a simple range and the year printed after it (an optional weekday before the end date)
    select c.*, regexp_match(c.tail, '^\s*(?:-|–|—|to|until)\s*(?:(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?,?\s+)?(?:(\d{1,2})(?:st|nd|rd|th)?\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)|(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?)\M,?\s+(20\d\d)\M(.*)$', 'is') rg
      from cut c),
  yr as (
    select r.*, nullif(r.d[5], '')::int y_after,
           nullif(substring(r.head from '.*\m(20\d\d)\M'), '')::int y_head,
           r.rg[5]::int y_end,
           -- a range that ends after the year-end starts in the year before the printed one; nothing else follows the end date (no second date, no other year)
           case when r.rg is not null and r.rg[6] !~* '\m20\d\d\M'
                     and r.rg[6] !~* '\m(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|jun(e)?|jul(y)?|aug(ust)?|sep(t(ember)?)?|oct(ober)?|nov(ember)?|dec(ember)?)\M'
                then case when array_position(array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'], lower(left(coalesce(r.rg[2], r.rg[3]), 3)))
                              >= array_position(array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'], lower(left(coalesce(r.d[2], r.d[3]), 3)))
                          then r.rg[5]::int else r.rg[5]::int - 1 end end y_range
      from rng r),
  pick as (select y.*, coalesce(y.y_after, y.y_head, y.y_range) y_raw from yr y),
  quoted_dates as (
    select p.id, p.period, p.kind,
           -- the reader's own years for the period must list it: a year the reader never found for this period is not taken
           case when p.y_raw is not null and (coalesce(jsonb_array_length(case when jsonb_typeof(p.yrs) = 'array' then p.yrs end), 0) = 0 or p.yrs @> to_jsonb(p.y_raw)) then p.y_raw end y,
           (array_position(array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'], lower(left(coalesce(p.d[2], p.d[3]), 3))))::int m,
           -- a day range ("18 – 20 January 2027"): which day the period starts is not certain, so no day (the year still counts)
           case when p.q !~ '\m\d{1,2}(st|nd|rd|th)?\s*[–—-]\s*\d{1,2}(st|nd|rd|th)?\s+[A-Za-z]' then coalesce(p.d[1], p.d[4])::int end d, p.q,
           null::text applies_to, null::text meaning,
           case when p.y_after is null and p.y_head is null and p.y_range is not null then 'range ending ' || p.y_end || ': the start falls in ' || p.y_range end year_quote
      from pick p),
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
comment on function security.calendar_proposal_dates_v1(uuid) is 'CF-247 (P0 IQ-00313, 8 Nov 2026): the dated starts and deadlines of one approved calendar reading. A quote read without a starts array takes the year printed straight after its date, else the last year printed before it, else (a simple range "<start> - <end> <year>") the year of the end less one when the range wraps the year-end; a year printed after several dates, or one the reader''s own years for the period do not list, is never taken for the first date. The basis of a range-derived year is kept in year_quote.';

-- 2 the plan: the horizon, rejected calendar values, a withdrawn value never admitted again (md5-guarded edit) ----------------------------------
select pg_temp.edit('security.intake_dates_plan_v3(uuid[],integer)', '1d531a835fcaa6996ac32f88d218eea8', 'intake_dates.max_months_ahead',
  array[
    $o$  r record; v_m int; v_year int;$o$,
    $o$      v_cal := coalesce((select jsonb_agg(to_jsonb(s)) from security.calendar_dated_periods_v2(r.provider_id) s), '[]'::jsonb);$o$,
    $o$    select array_agg(distinct s.on_date) filter (where s.on_date is not null), array_agg(distinct s.period), min(s.quote), min(s.proposal_id::text)::uuid, min(s.url), min(s.evidence_id::text)::uuid$o$,
    $o$    v_start := case when cardinality(v_starts) = 1 then v_starts[1] end;$o$
  ],
  array[
    $n$  -- P0 IQ-00313: a calendar date is taken only within this many months of today
  v_ahead int := greatest(1, security.pipeline_num_v1('intake_dates.max_months_ahead', 18)::int);
  r record; v_m int; v_year int;$n$,
    $n$      -- P0 IQ-00313: a calendar value recorded as rejected is never used again (provider, reading, quote, year)
      v_cal := coalesce((select jsonb_agg(to_jsonb(s)) from security.calendar_dated_periods_v2(r.provider_id) s
                          where not exists (select 1 from pipeline.intake_date_rejections j
                                             where j.provider_id = r.provider_id and j.proposal_id is not distinct from s.proposal_id
                                               and j.quote is not distinct from s.quote and j.year is not distinct from s.year)), '[]'::jsonb);$n$,
    $n$    -- P0 IQ-00313: the next dated start must lie within the horizon (intake_dates.max_months_ahead); a later one is a later cycle whose year is not proved
    if make_date(v_year, v_m, 1) > (date_trunc('month', v_today) + make_interval(months => v_ahead))::date then
      outcome := 'skipped'; start_precision := 'month';
      reason := 'the year of the named period is not printed for the next cycle: its next dated start is more than ' || v_ahead || ' months away (month only)';
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; outcome := null; continue;
    end if;
    select array_agg(distinct s.on_date) filter (where s.on_date is not null), array_agg(distinct s.period), min(s.quote), min(s.proposal_id::text)::uuid, min(s.url), min(s.evidence_id::text)::uuid$n$,
    $n$    v_start := case when cardinality(v_starts) = 1 then v_starts[1] end;
    -- P0 IQ-00313: a value withdrawn from this intake (the withdrawn event's before_value is the rejected value) is not admitted to it again
    if exists (select 1 from pipeline.course_intake_date_events w
                where w.intake_id = r.id and w.outcome = 'withdrawn'
                  and (w.before_value->>'year')::int is not distinct from v_year and (w.before_value->>'start_date')::date is not distinct from v_start) then
      outcome := 'skipped'; start_precision := 'month'; start_quote := null;
      reason := 'withdrawn: this value was rejected earlier and is not admitted again (a person decides)';
      next_action := 'human_decision_required'; next_revisit_at := null;
      return next; outcome := null; continue;
    end if;$n$
  ],
  array[1, 1, 1, 1]);

-- 3 the rejected calendar values (new, additive) --------------------------------------------------------------------------------------------
create table if not exists pipeline.intake_date_rejections (
  id bigserial primary key,
  provider_id uuid not null,
  proposal_id uuid,
  quote text,
  year integer,
  start_date date,
  reason text not null,
  case_ref text,
  rejected_by text,
  rejected_at timestamptz not null default now()
);
comment on table pipeline.intake_date_rejections is 'CF-247 P0 IQ-00313 (8 Nov 2026): the calendar values a person or a check rejected as wrong (a start date read with the wrong year): the university, the approved reading (proposal_id), the quote and the year the reading gave. security.intake_dates_plan_v3 never uses a calendar value listed here. Rows are kept; a row is set aside by a person, never by the process. Written by the corrections of the Platform Admin and the Integration Controller; never read by the consumer API.';
create unique index if not exists intake_date_rejections_value_idx on pipeline.intake_date_rejections (provider_id, coalesce(proposal_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(quote, ''), coalesce(year, 0));
alter table pipeline.intake_date_rejections enable row level security;
revoke all on pipeline.intake_date_rejections from public, anon, authenticated;

-- 4 stored Website and Zoho items follow a correction at once (new, additive) -----------------------------------------------------------------
create or replace function security.intake_projection_reconcile_v1(p_course_ids uuid[]) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare r record; v jsonb; h text; it pipeline.website_sync_items%rowtype; zt pipeline.zoho_sync_items%rowtype; v_out jsonb;
begin
  if coalesce(cardinality(p_course_ids), 0) = 0 then return '[]'::jsonb; end if;
  -- the Website scan's own lock (waits for a scan that is running, then no scan interleaves with this transaction)
  perform pg_advisory_xact_lock(hashtext('website-sync-check'));
  for r in select w.item_key, w.ref_id from pipeline.website_sync_items w where w.entity = 'course' and w.ref_id = any (p_course_ids) order by w.item_key loop
    v := security.website_sync_item_v1('course', r.ref_id, r.item_key);
    h := case when v is null then null else md5((v - 'generated_at' - 'freshness')::text) end;
    select * into it from pipeline.website_sync_items where entity = 'course' and item_key = r.item_key;
    -- the transitions of security.website_sync_check_v1, for stored items only (a new item is created by the scan)
    if v is null then
      if it.removed_at is null then
        update pipeline.website_sync_items set removed_at = now(), hash = null, item = null, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = 'course' and item_key = r.item_key;
      end if;
    elsif it.removed_at is not null then
      update pipeline.website_sync_items set removed_at = null, hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = 'course' and item_key = r.item_key;
    elsif it.hash is null then
      update pipeline.website_sync_items set hash = h, item = v, ref_id = r.ref_id where entity = 'course' and item_key = r.item_key;
    elsif it.hash <> h then
      update pipeline.website_sync_items set hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = 'course' and item_key = r.item_key;
    elsif it.item is null then
      update pipeline.website_sync_items set item = v where entity = 'course' and item_key = r.item_key;
    end if;
  end loop;
  -- the Zoho scan reads the stored Website item, so it follows the Website step
  perform pg_advisory_xact_lock(hashtext('zoho-sync-check'));
  for r in select z.item_key, z.ref_id from pipeline.zoho_sync_items z where z.entity = 'course' and z.ref_id = any (p_course_ids) order by z.item_key loop
    v := security.zoho_sync_item_v1('course', r.ref_id, r.item_key);
    h := case when v is null then null else md5((v - 'generated_at' - 'freshness')::text) end;
    select * into zt from pipeline.zoho_sync_items where entity = 'course' and item_key = r.item_key;
    if v is null then
      if zt.removed_at is null then
        update pipeline.zoho_sync_items set removed_at = now(), hash = null, item = null, seq = nextval('pipeline.zoho_sync_seq'), seq_at = now() where entity = 'course' and item_key = r.item_key;
      end if;
    elsif zt.removed_at is not null then
      update pipeline.zoho_sync_items set removed_at = null, hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.zoho_sync_seq'), seq_at = now() where entity = 'course' and item_key = r.item_key;
    elsif zt.hash is null then
      update pipeline.zoho_sync_items set hash = h, item = v, ref_id = r.ref_id where entity = 'course' and item_key = r.item_key;
    elsif zt.hash <> h then
      update pipeline.zoho_sync_items set hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.zoho_sync_seq'), seq_at = now() where entity = 'course' and item_key = r.item_key;
    elsif zt.item is null then
      update pipeline.zoho_sync_items set item = v where entity = 'course' and item_key = r.item_key;
    end if;
  end loop;
  -- what the stored items now show for each course: its intakes (label, year, start date)
  select coalesce(jsonb_agg(jsonb_build_object('course_id', c.id,
           'website', (select jsonb_agg(jsonb_build_object('label', e->>'label', 'year', e->>'year', 'start_date', e->>'start_date') order by e->>'label')
                         from pipeline.website_sync_items w, jsonb_array_elements(coalesce(w.item->'intakes', '[]'::jsonb)) e where w.entity = 'course' and w.ref_id = c.id and w.removed_at is null),
           'zoho', (select jsonb_agg(jsonb_build_object('label', e->>'label', 'year', e->>'year', 'start_date', e->>'start_date') order by e->>'label')
                      from pipeline.zoho_sync_items z, jsonb_array_elements(coalesce(z.item->'intakes', '[]'::jsonb)) e where z.entity = 'course' and z.ref_id = c.id and z.removed_at is null)) order by c.id), '[]'::jsonb)
    into v_out from unnest(p_course_ids) c(id);
  return v_out;
end $function$;
comment on function security.intake_projection_reconcile_v1(uuid[]) is 'CF-247 P0 IQ-00313 (8 Nov 2026): re-evaluates the stored Website item and then the stored Zoho item of the named courses with the scans'' own builders, transition rules and advisory locks (security.website_sync_check_v1, security.zoho_sync_check_v1), so a corrected intake leaves both stored items without waiting for the next pass. Returns the intakes (label, year, start date) each stored item now holds. Changes no consumer API object.';
revoke all on function security.intake_projection_reconcile_v1(uuid[]) from public, anon, authenticated;

comment on function security.intake_dates_plan_v3(uuid[], integer) is 'CF-247 intake dates plan v3 (decisions 5 Nov 2026; P0 IQ-00313, 8 Nov 2026): the horizon (intake_dates.max_months_ahead), calendar values listed in pipeline.intake_date_rejections are never used, and a value withdrawn from an intake is not admitted to it again, beside the course-specific offering gate, provider rounds and pilot share.';
