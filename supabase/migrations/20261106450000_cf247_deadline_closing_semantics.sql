-- CF-247 P0 deadline semantics, Admin #382 critical comment 6685067695 (6 Nov 2026).
-- Source evidence: field_enrich_items 273361 / 273381 / 273383 called printed
-- commencement dates application deadlines. Existing on-page/date/window checks
-- did not establish an application-closing event. This pure guard repairs that rule.
-- Reuses: existing enrich_course_text_record_v1 -> course_deadline_in_quote_v1.
-- Changes: the same helper now requires unambiguous application-closing semantics
-- in the date's own clause. Multi-date/negative/non-application clauses wait.
-- Replaces: security.course_deadline_in_quote_v1(date,text), same signature/grants.
-- Retires: nothing. No job, setting, Worker, API object, admission trust or row change.
-- Recorded live before-md5: f01e9be83e58c9c48c33e5fde4de05d9 (6 Nov 2026).
-- Generated with pinned Supabase CLI 2.120.0 as 20261106125737, then only this
-- never-applied file was assigned reserved logical slot 20261106450000. The ID
-- records ordering after live 400000, before pending 500000/550000, not execution.
do $guard$
declare v_md5 text := md5(pg_get_functiondef('security.course_deadline_in_quote_v1(date,text)'::regprocedure));
begin
  if v_md5 not in ('f01e9be83e58c9c48c33e5fde4de05d9', '2357306ca969fb7b299021bac3b6f3fa') then
    raise exception 'deadline guard live definition differs (md5 %); reconcile before applying', v_md5;
  end if;
end $guard$;

create or replace function security.course_deadline_in_quote_v1(p_date date, p_quote text) returns boolean
language sql immutable set search_path = '' as $deadline$
  -- P0 deadline semantics (Admin #382, 6 Nov 2026): a printed commencement date is
  -- not an application closing date. The closing cue and the only full date must
  -- be in the same clause. Ambiguous multi-date clauses wait for better evidence.
  with grammar as (
    select '(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|jun(e)?|jul(y)?|aug(ust)?|sep(t(ember)?)?|oct(ober)?|nov(ember)?|dec(ember)?)'::text mon
  ), dates as (
    select extract(year from p_date)::int::text y, extract(month from p_date)::int::text m, extract(day from p_date)::int::text d,
           (array['jan(uary)?','feb(ruary)?','mar(ch)?','apr(il)?','may','jun(e)?','jul(y)?','aug(ust)?','sep(t(ember)?)?','oct(ober)?','nov(ember)?','dec(ember)?'])[extract(month from p_date)::int] mon
  ), patterns as (
    select '\m(0?' || d || '(st|nd|rd|th)?\s+' || dates.mon || '\.?\s*,?\s*' || y
           || '|' || dates.mon || '\.?\s+0?' || d || '(st|nd|rd|th)?\s*,?\s*' || y
           || '|0?' || d || '[/.-]0?' || m || '[/.-]' || y || '|' || y || '-0?' || m || '-0?' || d || ')\M' target,
           '\m([0-9]{1,2}(st|nd|rd|th)?\s+' || grammar.mon || '\.?\s*,?\s*[0-9]{4}'
           || '|' || grammar.mon || '\.?\s+[0-9]{1,2}(st|nd|rd|th)?\s*,?\s*[0-9]{4}'
           || '|[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{4}|[0-9]{4}-[0-9]{1,2}-[0-9]{1,2})\M' full_date
      from dates cross join grammar
  ), clauses as (
    select lower(t) t from regexp_split_to_table(coalesce(p_quote, ''), E'[;\n\r]+|[.!?]\\s+(?=[A-Za-z])') t
  )
  select coalesce(p_date is not null and exists (
    select 1 from clauses c cross join patterns p
     where c.t ~ p.target
       and c.t ~ '(\mapplications?\M.*\m(close[sd]?|closing|due|deadlines?)\M|\mapplication\s+deadlines?\M|\mclosing\s+date\M|\mapply\s+(by|before)\M|\mapplications?\M.*\m(received|submitted)\s+(by|before)\M|\mintakes?\M.*\mcloses?\M)'
       and c.t !~ '\m(not|never|fees?|payments?|deposits?|scholarships?|exams?|census)\M'
       and c.t !~ '\m(starts?|starting|commencements?|commences?|commencing|begins?|beginning)\M'
       and c.t !~ ('\mintakes?[[:space:]:]+' || p.target)
       and (select count(*) from regexp_matches(c.t, p.full_date, 'g')) = 1
  ), false)
$deadline$;

comment on function security.course_deadline_in_quote_v1(date,text) is 'CF-247 P0 Admin #382 (6 Nov 2026): an application closing cue and exactly one full matching date in the same clause are required; commencement, opening, fee/scholarship deadlines, negation and ambiguous multiple dates are refused. Existing quote identity, intake match, locks and admission windows still apply.';
do $post$
begin
  if md5(pg_get_functiondef('security.course_deadline_in_quote_v1(date,text)'::regprocedure)) <> '2357306ca969fb7b299021bac3b6f3fa' then
    raise exception 'deadline guard after-md5 differs; transaction must roll back';
  end if;
  if security.course_deadline_in_quote_v1('2026-11-02', 'Start date 02 Nov 2026')
     or security.course_deadline_in_quote_v1('2027-02-15', 'Intakes 15 February 2027')
     or security.course_deadline_in_quote_v1('2026-10-12', 'Start Dates 12 October 2026')
     or not security.course_deadline_in_quote_v1('2026-11-30', 'Applications for the February 2027 intake close 30 November 2026') then
    raise exception 'deadline semantic guard post-check failed';
  end if;
end $post$;
