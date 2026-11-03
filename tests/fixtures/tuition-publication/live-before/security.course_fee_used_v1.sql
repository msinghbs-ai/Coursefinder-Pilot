CREATE OR REPLACE FUNCTION security.course_fee_used_v1(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_year int := extract(year from now())::int; pg record; cr record; v_yrs numeric; v_locked boolean; v_ann numeric; v_ev boolean;
begin
  select f.amount, f.fee_year, f.currency_code, f.evidence_id into pg from catalogue.course_fees f
   where f.course_id = p_course_id and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.status = 'active' and f.amount > 0
     and f.basis in ('annual', 'indicative_annual', 'current indicative annual international tuition')
   order by f.fee_year desc nulls last, f.created_at desc limit 1;
  select f.amount, f.currency_code into cr from catalogue.course_fees f
   where f.course_id = p_course_id and f.fee_type = 'tuition' and f.audience = 'international' and f.status = 'active' and f.amount > 0 and f.basis = 'registered_total_course'
   order by f.created_at desc limit 1;
  select case c.duration_unit when 'weeks' then c.duration_value / 52.0 when 'years' then c.duration_value when 'months' then c.duration_value / 12.0 end into v_yrs
    from catalogue.courses c where c.id = p_course_id;
  v_locked := exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = p_course_id and m.field in ('tuition', 'fee', 'fees'));
  if cr.amount is not null and coalesce(v_yrs, 0) > 0 then v_ann := round(cr.amount / greatest(v_yrs, 1), 0); end if;
  v_ev := pg.amount is not null and pg.evidence_id is not null and security.fee_evidence_own_site_v1(pg.evidence_id, p_course_id);
  if pg.amount is not null and (cr.amount is null or (not v_locked and v_ev) or (v_locked and pg.fee_year >= v_year)) then
    return jsonb_build_object('source', 'page', 'per_year', pg.amount, 'currency', pg.currency_code, 'year', pg.fee_year, 'cricos_per_year', v_ann, 'locked', v_locked, 'rule', 'rule_2',
      'reason', case when cr.amount is null then 'No CRICOS fee is registered, so the course page fee is used.'
                     when v_locked then 'The course page names ' || pg.fee_year || ', this year or later, so the page fee is used (fee entered or locked by hand: earlier rule kept).'
                     else 'The provider''s own course page gives this fee' || coalesce(' for ' || pg.fee_year, '') || ' and its evidence is captured, so it is used over the CRICOS registered fee (Rule 2).' end);
  elsif cr.amount is not null and v_ann is not null then
    return jsonb_build_object('source', 'cricos', 'per_year', v_ann, 'currency', cr.currency_code, 'year', null, 'page_per_year', pg.amount, 'page_year', pg.fee_year, 'locked', v_locked, 'rule', 'rule_2',
      'reason', case when pg.amount is null then 'No course page fee has been read, so the CRICOS registered fee is held (the registered total, divided by the course length when that is a year or more).'
                     when v_locked then 'A fee is entered or locked by hand and the course page names no current year, so the CRICOS registered fee is kept.'
                     when pg.evidence_id is null then 'The course page fee has no captured evidence, so the CRICOS registered fee is held.'
                     else 'The course page fee was read from a site shared by several providers, not the provider''s own site, so the CRICOS registered fee is held.' end);
  end if;
  return jsonb_build_object('source', null, 'locked', v_locked, 'reason', 'No page fee or CRICOS fee with a course length is stored.');
end $function$
