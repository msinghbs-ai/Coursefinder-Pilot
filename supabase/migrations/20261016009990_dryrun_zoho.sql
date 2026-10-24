-- CF-247 (24 Oct 2026). UI audit Phase 2 — the Courses list shows what the course blade already holds (Platform Admin 24 Oct 2026 11:27;
-- decision record: admin repo docs/platform/ui-audit/2026-10-24-ui-cleanup-mandate.md).
-- The list read path (security.admin_course_page_fast_base, behind public.admin_read 'courses_page') already returns the provider's
-- international fee (amount, currency, year), the CRICOS registered total, the campus cities and the state; the screen already has the
-- columns (v2.15.330). Two gaps closed here, both additive on the admin read path (not the website API, Decision 266):
--   1 the fee's basis (per year, per course, …) joins the row (intl_fee_basis) so the list shows it as the blade does;
--   2 the International fee and City columns become sortable (sort keys intl_fee and city): the sort runs on the filtered set with one
--     indexed lookup per course; the legacy 'fee' sort (ui_courses_decision_page) is untouched.
-- Replaces: nothing (admin_course_page_fast_base edited in place, md5-guarded)
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

select pg_temp.edit_n('security.admin_course_page_fast_base(jsonb)', 'a828eb5404a7999c81c2336b09b5f366', array[
  array[$o$    select * from numbered order by
      case when v_sort='course' and v_dir='asc' then lower(canonical_title) end asc,$o$,
        $n$    select * from numbered order by
      -- 24 Oct 2026 (UI audit Phase 2): the International fee and City columns sort; one indexed lookup per filtered course
      case when v_sort='intl_fee' and v_dir='asc' then (select cf.amount from catalogue.course_fees cf where cf.course_id=numbered.id and cf.fee_type='provider_current_tuition' and cf.audience='international' and cf.status='active' order by cf.fee_year desc nulls last, cf.updated_at desc limit 1) end asc nulls last,
      case when v_sort='intl_fee' and v_dir='desc' then (select cf.amount from catalogue.course_fees cf where cf.course_id=numbered.id and cf.fee_type='provider_current_tuition' and cf.audience='international' and cf.status='active' order by cf.fee_year desc nulls last, cf.updated_at desc limit 1) end desc nulls last,
      case when v_sort='city' and v_dir='asc' then (select min(lower(ca.city)) from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id where cc.course_id=numbered.id and nullif(btrim(ca.city),'') is not null) end asc nulls last,
      case when v_sort='city' and v_dir='desc' then (select min(lower(ca.city)) from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id where cc.course_id=numbered.id and nullif(btrim(ca.city),'') is not null) end desc nulls last,
      case when v_sort='course' and v_dir='asc' then lower(canonical_title) end asc,$n$],
  array[$o$left join lateral (select cf.amount, cf.currency_code, cf.fee_year from catalogue.course_fees cf where cf.course_id=pg.id and cf.fee_type='provider_current_tuition'$o$,
        $n$left join lateral (select cf.amount, cf.currency_code, cf.fee_year, cf.basis from catalogue.course_fees cf where cf.course_id=pg.id and cf.fee_type='provider_current_tuition'$n$],
  array[$o$ifee.fee_year intl_fee_year,gcity.city_names,$o$, $n$ifee.fee_year intl_fee_year,ifee.basis intl_fee_basis,gcity.city_names,$n$]], array[1, 1, 1]);

do $t$ begin raise exception 'DRYRUN OK guards hold'; end $t$;
