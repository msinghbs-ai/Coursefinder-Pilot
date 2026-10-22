-- CF-247 (22 Oct 2026). Platform Admin 14:44: "sydney website is difficult - java script changes the year, student type and no url change - only
-- 2027 is available - fees"; 15:51 found the data file behind the fee box (bachelor-of-commerce0.coredata.json, checked in a private window
-- at 15:59: the international fee is there for everyone). Choice 16:30: "Yes: fees and English", tried on courses first and switched on
-- only after the Platform Admin approves.
-- Each Sydney course page has a data file at the same address with .coredata.json instead of .html. It holds feeSummary.feesByYear (year,
-- INTFEE amount for a full-time year of 48 credit points) and entryRequirementsByYear (IELTS, TOEFL iBT, PTE). The University of Sydney had
-- no provider fee on any of its 655 courses: the fee is drawn in by the browser after a choice of student type and year.
-- 1 Companion pages can now be an address made from the bound page (pipeline.uni_adapter_companions.url_replace: the url_pattern's match
--   replaced), not only the bound address plus a suffix (security.companion_sync_v1).
-- 2 The University of Sydney's companion is its course data file, read directly (no scraper credits) by job companion-read, with patterns
--   for the first year's international fee and year, IELTS overall and each band, TOEFL iBT and PTE. Values are only recorded on
--   pipeline.course_companion_pages: nothing is written to courses until the Platform Admin approves admitting them (a later change).
-- Replaces: security.companion_sync_v1 (address made by replacement). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 ---------------------------------------------------------------------------------------------------------------------------------
alter table pipeline.uni_adapter_companions add column if not exists url_replace text;
comment on column pipeline.uni_adapter_companions.url_replace is 'CF-247 22 Oct 2026: when set, the companion address is the bound page address with url_pattern''s match replaced by this (for example \1.coredata.json); otherwise the bound address plus suffix.';

select pg_temp.edit_once('security.companion_sync_v1()', 'ce56347eb846de075a33146a5101f4f9', array[
  [$o$regexp_replace(g.url, '/+$', '') || c.suffix url$o$,
   $n$case when c.url_replace is not null then regexp_replace(g.url, c.url_pattern, c.url_replace)  -- 22 Oct 2026: an address made from the bound page (Sydney data file)
                else regexp_replace(g.url, '/+$', '') || c.suffix end url$n$]]);

-- 2 ---------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.uni_adapter_companions(provider_id, url_pattern, suffix, url_replace, patterns, read_via, reason)
select p.id, '^(https://www\.sydney\.edu\.au/courses/courses/[a-z]+/[a-z0-9-]+)\.html$', '', '\1.coredata.json',
       jsonb_build_object(
         'fee_international', '"year":\d{4},"fees":\[[^\]]*?"type":"INTFEE","title":"[^"]*","amount":"\$([\d,]+)"',
         'fee_year', '"year":(\d{4}),"fees":\[[^\]]*?"type":"INTFEE","title":"[^"]*","amount":"\$[\d,]+"',
         'ielts_overall', '"id":"IELTS-INDICATOR"[^}]*?"description":"A minimum result of ([\d.]+) overall',
         'ielts_band', '"id":"IELTS-INDICATOR"[^}]*?"description":"A minimum result of [\d.]+ overall and a minimum result of ([\d.]+) in each band',
         'toefl_ibt', '"id":"IBT-INDICATOR"[^}]*?"description":"A minimum result of (\d+) overall',
         'pte', '"id":"PTE-INDICATOR"[^}]*?"description":"A minimum result of (\d+) overall'),
       'direct',
       'CF-247 22 Oct 2026 (Platform Admin 16:30 "Yes: fees and English"): Sydney course data file (.coredata.json); values recorded, admitted only after approval'
  from catalogue.providers p where p.canonical_name = 'The University of Sydney'
on conflict (provider_id) do nothing;

do $chk$
begin
  if not exists (select 1 from pipeline.uni_adapter_companions c join catalogue.providers p on p.id = c.provider_id where p.canonical_name = 'The University of Sydney' and c.url_replace is not null) then
    raise exception 'Sydney companion not recorded';
  end if;
end $chk$;

select security.companion_sync_v1();
