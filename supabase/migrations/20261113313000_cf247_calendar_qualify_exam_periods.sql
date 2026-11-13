-- CF-247 F-INT: calendar qualification reads a main teaching calendar that also lists exam periods (Platform Admin decision 13 Nov 2026 13:03, Massey).
-- Platform Admin: "Do not reject an entire legitimate teaching calendar simply because it also publishes examination periods. Use the existing
--   calendar qualification mechanism to identify and admit only the explicitly proven teaching-start records ... Preserve rejection of application
--   due dates, add/drop dates, refund dates, orientation, examinations and ambiguous teaching periods."
-- Found (13 Nov 2026): Massey's official key-dates page (https://www.massey.ac.nz/study/key-dates-for-semesters-exam-periods-other-events/) was refused
--   twice by security.calendar_qualify_check_v1:
--   1. blocked_word: the word "exam" in the page address is in central.calendar_qualify_blocked_words, so the whole page was refused.
--   2. year_not_proved: the page prints the year in the heading of each table ("Semester One 2027"), not in the row; the table parser
--      (coverage-sweep policy.ts calendarStarts) took that year but kept no year_quote. Fixed in the parser in the same change (Pilot PR).
-- What:
--   1. Two new list settings (G2), shown on Settings > Pipeline settings > Intake dates:
--      central.calendar_qualify_shared_event_words ["exam"]: event words a main teaching calendar may also name in its address or title;
--      central.calendar_qualify_teaching_start_words: the wording that marks a start as a teaching start.
--   2. md5-guarded edit of security.calendar_qualify_check_v1: a shared event word does not block when every start in the window is quoted with
--      teaching-start wording; any other start (orientation, exam, enrolment) still blocks the whole page. The approved calendars used to look for
--      a contradiction keep a page whose address has only a shared event word. Every other rule is unchanged (period words, scope, year proof,
--      window, contradiction, rejected values, hand-set calendars).
-- Guards: G1 (no job), G2 (the word lists are settings), G3 (no consumer API object), G4 (cf-247-s541).
-- Replaces: security.calendar_qualify_check_v1 (same name; md5-guarded text edit, resulting md5 checked).
-- Retires: nothing.
-- Reversal: empty central.calendar_qualify_shared_event_words on Settings (nothing is let through), or reverse the edit (body 045d505668295345f8063e4e0dc65feb).

insert into pipeline.platform_toolset_settings(toolset_key, key, value, label, help, kind, unit, section, sort, used_by, reason)
values
  ('pipeline', 'central.calendar_qualify_shared_event_words', '["exam"]'::jsonb,
   'Calendar qualification: event words a main teaching calendar may also name',
   'A calendar page whose address or title has one of these words (and no other blocked word) is not refused for it when every teaching start it gives is quoted with teaching-start wording (next setting). Its exam, orientation, enrolment and application dates are never starts. Empty: such pages are refused as before.',
   'list', 'words', 'Intake dates', 1027, 'security.calendar_qualify_check_v1',
   'Platform Admin 13 Nov 2026 13:03 (Massey): a teaching calendar that also publishes exam periods is not rejected whole'),
  ('pipeline', 'central.calendar_qualify_teaching_start_words',
   '["lectures start","lectures begin","teaching starts","teaching begins","classes start","classes begin","semester starts","semester begins","semester and lectures start"]'::jsonb,
   'Calendar qualification: wording that marks a teaching start',
   'Used with the shared event words: every start the calendar gives in the window must be quoted with one of these phrases.',
   'list', 'words', 'Intake dates', 1028, 'security.calendar_qualify_check_v1',
   'Platform Admin 13 Nov 2026 13:03 (Massey): only explicitly labelled teaching starts')
on conflict (toolset_key, key) do nothing;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.calendar_qualify_check_v1(uuid)', '045d505668295345f8063e4e0dc65feb', 'accbbc5395c85e537d45eaaba25a2196',
  array[$o$'central.calendar_qualify_blocked_period_words') else '[]'::jsonb end) w where btrim(w) <> '') pblocked,$o$,
        $o$and not exists (select 1 from unnest(cfg.blocked) w where position(w in lower(x.url)) > 0)),$o$,
        $o$(select w from unnest(cfg.blocked) w where position(w in p.hay) > 0 order by w limit 1) bword,$o$],
  array[$n$'central.calendar_qualify_blocked_period_words') else '[]'::jsonb end) w where btrim(w) <> '') pblocked,
           -- 13 Nov 2026 (Platform Admin, Massey): event words a main teaching calendar may also name in its address or title (an exam period), and the
           -- teaching-start wording every start must be quoted with for such a page to be read as a teaching calendar; empty lists: no page is let through
           array(select lower(btrim(w)) from jsonb_array_elements_text(case when jsonb_typeof(security.toolset_setting('pipeline', 'central.calendar_qualify_shared_event_words')) = 'array' then security.toolset_setting('pipeline', 'central.calendar_qualify_shared_event_words') else '[]'::jsonb end) w where btrim(w) <> '') shared,
           array(select lower(btrim(w)) from jsonb_array_elements_text(case when jsonb_typeof(security.toolset_setting('pipeline', 'central.calendar_qualify_teaching_start_words')) = 'array' then security.toolset_setting('pipeline', 'central.calendar_qualify_teaching_start_words') else '[]'::jsonb end) w where btrim(w) <> '') tstart,$n$,
        $n$and not exists (select 1 from unnest(cfg.blocked) w where position(w in lower(x.url)) > 0 and not (w = any (cfg.shared)))),$n$,
        $n$(select w from unnest(cfg.blocked) w where position(w in p.hay) > 0
              -- 13 Nov 2026 (Platform Admin, Massey): a calendar that also lists exam dates is not refused for naming them when every start it gives
              -- in the window is quoted as a teaching start; application, add/drop, refund, orientation and exam dates are never starts
              and not (w = any (cfg.shared) and exists (select 1 from win)
                       and not exists (select 1 from win w2 where not exists (select 1 from unnest(cfg.tstart) t where position(t in lower(coalesce(w2.quote, ''))) > 0)))
            order by w limit 1) bword,$n$]);

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.calendar_qualify_check_v1(uuid)'::regprocedure)) <> 'accbbc5395c85e537d45eaaba25a2196' then
    raise exception 'post-check: security.calendar_qualify_check_v1 does not have the recorded body'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline'
        and key in ('central.calendar_qualify_shared_event_words', 'central.calendar_qualify_teaching_start_words')) <> 2 then
    raise exception 'post-check: the two calendar qualification settings are missing'; end if;
end $post$;
