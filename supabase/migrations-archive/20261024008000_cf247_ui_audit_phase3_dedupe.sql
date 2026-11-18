-- CF-247 (24 Oct 2026). UI audit Phase 3 — dedupe and data-quality leaks (Platform Admin 24 Oct 2026 11:27; decision record: admin repo
-- docs/platform/ui-audit/2026-10-24-ui-cleanup-mandate.md section 4).
-- 1 The Dashboard's Scholarships tile said 2,059 "every status" while the Scholarships screen said 1,106 published of 1,436 held: the
--   2,059 counts 623 retired records too. The dashboard read gains the two figures the screen uses (additive keys on the admin read path)
--   so both screens state the same three numbers.
-- 2 One campus carries its street as its city ("1 Brazier Drive", Townsville Grammar School – Annandale Campus): corrected to Townsville
--   (count-guarded: exactly one such row).
-- Not here (data the register did not give, logged for Layer 1): 19 CRICOS providers named "N/A"/"NA" (the register's trading name) and one
-- NZQA course titled "--"; the screens show them as unnamed with the register code until the register read keeps the legal name.
-- Replaces: nothing (admin_dashboard_maturity_compute edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.admin_dashboard_maturity_compute()', '240d606e62a4ae008712e0d18e99eba5', array[
  array[$o$    'scholarships',(select count(*) from scholarship.scholarships),'jobs',(select count(*) from pipeline.jobs),$o$,
        $n$    'scholarships',(select count(*) from scholarship.scholarships),'jobs',(select count(*) from pipeline.jobs),
    /* 24 Oct 2026 (UI audit Phase 3): the figures the Scholarships screen states, so the Dashboard says the same */
    'scholarships_active',(select count(*) from scholarship.scholarships where lifecycle_status='active'),
    'scholarships_published',(select count(*) from scholarship.scholarships where lifecycle_status='active' and publication_status='published'),$n$]], array[1]);

do $g$ declare n int; begin
  select count(*) into n from catalogue.campuses where status = 'active' and city ~ '^\d+\s';
  if n <> 1 then raise exception 'expected exactly one active campus with a street for a city, found %', n; end if;
  update catalogue.campuses set city = 'Townsville', updated_at = now()
   where status = 'active' and city ~ '^\d+\s' and name ilike 'Townsville Grammar School%';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'the Townsville campus was not corrected (% rows)', n; end if;
end $g$;

-- the dashboard serves a 10-minute snapshot; refresh it so the new figures show straight away
update security.admin_summary_snapshots set payload = security.admin_dashboard_maturity_compute(), computed_at = now() where snapshot_key = 'dashboard';

select 'UI audit Phase 3: dashboard scholarship figures reconciled; one campus city corrected' ok;
