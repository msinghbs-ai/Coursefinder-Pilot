-- Version 20261111235900 (re-issued 11 Nov 2026 15:1x AEDT): first merged as 20261111235000 (Pilot #1020), a version #1019 had already applied, so
--   deploy-on-merge refused it and ran nothing. Same content under a free version; no other change.
-- CF-247 F-INT: RMIT Rule B switch-on, validation findings (Platform Admin 11 Nov 2026 14:38 AEDT "RMIT added").
-- Evidence (production, 11 Nov 2026 14:45 AEDT): with RMIT listed in intake_dates.nearest_start_providers, Rule B filled 14 RMIT intakes (Graduate Diploma and
--   Certificate, 1 Mar 2027 and 19 Jul 2027; 2 University Pathways Fast Track rows, 4 Jan and 19 Jul 2027). 445 RMIT rows were held "the course page does not
--   state <month> as an intake": the RMIT adapter kept only "adapter pattern: February" as the page wording, not the page's words ("Next intake: February,
--   July"). The worker fix (coverage-sweep worker v0.68.0, same change) keeps the end of the adapter's match. Read again from the stored pages, RMIT's
--   vocational and pathway courses (Certificate IV, Diploma, Advanced Diploma, Non AQF Award: about 64 rows) would then be dated from the university's main
--   (higher education) teaching calendar, which they do not follow.
-- What:
--   1. setting intake_dates.nearest_start_hold_levels (G2, list of study level codes): Rule B gives no date to a course at one of these levels.
--   2. md5-guarded text edit of security.intake_nearest_start_v1 (body a99b42c7... -> 5e864efd...): after the research-degree hold, a course whose study level
--      is in the setting is held "a vocational or pathway course is not dated from the main teaching calendar (month only)".
--   Narrows Rule B only; nothing is switched on. The two RMIT pathway rows Rule B filled today are withdrawn separately through
--   security.intake_date_withdraw_v1 (a governed data step, not by this migration).
-- Verified on production in a rolled-back transaction with the exact edit applied to the live definition: the edit applies once; the inserted block's md5
--   (55d7b0f0...) equals this file's; resulting body md5 5e864efd7758ea2149e28f6566ac466b.
-- Guards: G1 (no job), G2 (the levels are a setting), G3 (no consumer API object), G4 (cf-247-s534).
-- Replaces: security.intake_nearest_start_v1 (same name; md5-guarded text edit, resulting md5 checked).
-- Retires: nothing.
-- Reversal: reverse the one edit (body a99b42c7007436a78860a386652f81a9); the setting is removed by paste file.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'intake_dates.nearest_start_hold_levels', 'Intake dates: study levels the nearest start never dates',
  'Rule B (Decision 271) dates a stated month from the university''s main teaching calendar. Courses at these study levels (vocational and pathway courses of a dual-sector university, which follow their own calendar) keep the month only. Empty: every coursework level may take the nearest start. Research degrees are always held.',
  'list', '["certificate","certificate_i","certificate_ii","certificate_iii","certificate_iv","diploma","advanced_diploma","vocational_short_course","non_aqf_award","foundation"]'::jsonb,
  0, null, 'study level codes', 1015, 'Intake dates',
  'security.intake_nearest_start_v1 (Rule B helper used by security.intake_dates_plan_v3 and the shadow)',
  'CF-247 F-INT (11 Nov 2026, RMIT Rule B switch-on): vocational and pathway courses follow their own calendar')
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


select pg_temp.edit_all('security.intake_nearest_start_v1(uuid,uuid,integer,integer,text,jsonb,date,integer,integer)', 'a99b42c7007436a78860a386652f81a9', '5e864efd7758ea2149e28f6566ac466b',
  array[$o$'doctorate', 'masters_research')) then
    return jsonb_build_object('admit', false, 'skip', 'a research degree is not dated from the coursework calendar (month only)');
  end if;$o$],
  array[$n$'doctorate', 'masters_research')) then
    return jsonb_build_object('admit', false, 'skip', 'a research degree is not dated from the coursework calendar (month only)');
  end if;
  -- 11 Nov 2026 (F-INT, RMIT switch-on): a level named in intake_dates.nearest_start_hold_levels (the vocational and pathway courses of a dual-sector
  -- university, which follow their own calendar) is not dated from the main teaching calendar
  if exists (select 1 from catalogue.courses c join ref.study_levels l on l.id = c.study_level_id where c.id = p_course
               and l.code in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s
                               where s.toolset_key = 'pipeline' and s.key = 'intake_dates.nearest_start_hold_levels' and jsonb_typeof(s.value) = 'array')) then
    return jsonb_build_object('admit', false, 'skip', 'a vocational or pathway course is not dated from the main teaching calendar (month only)');
  end if;$n$]);

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_nearest_start_v1(uuid,uuid,integer,integer,text,jsonb,date,integer,integer)'::regprocedure)) <> '5e864efd7758ea2149e28f6566ac466b' then
    raise exception 'post-check: security.intake_nearest_start_v1 does not have the recorded body'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.nearest_start_hold_levels') then
    raise exception 'post-check: intake_dates.nearest_start_hold_levels missing'; end if;
end $post$;
