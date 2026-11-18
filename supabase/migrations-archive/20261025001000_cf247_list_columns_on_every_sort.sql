-- CF-247 HOTFIX (25 Oct 2026, v2.15.351). Platform Admin consolidated mandate 25 Oct 2026, Part A: "list columns show "—" while the blade
-- shows data" (screenshots, v2.15.350, NZ filter: International fee "—" for every course, City "—" for most; Lincoln LI4245 blade shows
-- NZ$37,000 / Lincoln). Record: admin repo docs/platform/ui-audit/2026-10-25-consolidated-visibility-and-data.md (Part A).
-- Root cause (measured live): the course list (admin_read 'courses_page' → security.admin_course_page_fast → admin_course_page_fast_base)
-- builds International fee (catalogue.course_fees, provider_current_tuition, international, active) and City (catalogue.course_campuses →
-- catalogue.campuses.city) - the same rows the blade reads - in its normal path. But when the list is sorted by Completeness or Tuition
-- Only (sort 'completeness' or 'fee'), fast_base hands the page to the older public.ui_courses_decision_page, whose rows never carried
-- those columns, and security.admin_course_page_search_state only adds search-copy flags. NZ, sorted by Completeness: 0 of 50 rows had
-- a fee or a city; the same filter sorted by Course: 22 and 30 of 50 (Lincoln LI4245: 37000, Lincoln).
-- Fix: admin_course_page_search_state (called only by that branch) adds the same International fee, City, display code and
-- open-to fields to each row, from the same tables and with the same choice of row as the normal path. Order, filters and totals are
-- unchanged. Admin read only; the consumer API is not touched.
-- Replaces: nothing (security.admin_course_page_search_state edited in place, md5-guarded)
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

select pg_temp.edit_n('security.admin_course_page_search_state(jsonb)', 'e49924a6a4930ce4837cd5c61d3af53a', array[
  array[$o$      'search_has_scholarship', d.has_scholarship
    ) order by i.ord$o$,
        $n$      'search_has_scholarship', d.has_scholarship
    )
    -- 25 Oct 2026 (hotfix v2.15.351): the columns the normal list path carries, from the same rows, so every sort shows them
    || jsonb_build_object(
      'intl_fee_amount', ifee.amount, 'intl_fee_currency', ifee.currency_code::text, 'intl_fee_year', ifee.fee_year, 'intl_fee_basis', ifee.basis,
      'city_names', gcity.city_names,
      'display_code', coalesce(ssc.identifier, i.item->>'course_code'), 'code_kind', case when ssc.identifier is not null then 'studysearch' else 'own' end,
      'open_to_international', oc.open_to_international, 'open_to_domestic', oc.open_to_domestic
    ) order by i.ord$n$],
  array[$o$  left join search.course_documents d on d.course_id=nullif(i.item->>'id','')::uuid;$o$,
        $n$  left join search.course_documents d on d.course_id=nullif(i.item->>'id','')::uuid
  left join lateral (select cf.amount, cf.currency_code, cf.fee_year, cf.basis from catalogue.course_fees cf where cf.course_id=nullif(i.item->>'id','')::uuid
    and cf.fee_type='provider_current_tuition' and cf.audience='international' and cf.status='active' order by cf.fee_year desc nulls last, cf.updated_at desc limit 1) ifee on true
  left join lateral (select string_agg(distinct ca.city, ', ') city_names from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id
    where cc.course_id=nullif(i.item->>'id','')::uuid and nullif(btrim(ca.city),'') is not null) gcity on true
  left join lateral (select ci.identifier from catalogue.course_identifiers ci where ci.course_id=nullif(i.item->>'id','')::uuid and ci.scheme='studysearch'
    and not exists (select 1 from catalogue.course_identifiers j join ref.course_code_schemes s on s.scheme=j.scheme and s.printed where j.course_id=nullif(i.item->>'id','')::uuid) limit 1) ssc on true
  left join catalogue.courses oc on oc.id=nullif(i.item->>'id','')::uuid;$n$]],
  array[1, 1]);

select 'list: International fee and City on every sort (Completeness and Tuition Only included)' ok;
