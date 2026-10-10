-- CF-247 Decision 255 (6 Oct 2026), correction found while investigating pages that show half the CRICOS yearly figure.
-- For a course shorter than a year (for example 26 weeks) the CRICOS registered total is the whole-course fee, and a
-- page that prints the course fee agrees with it. Dividing that total by 0.5 years doubled it and showed a false
-- disagreement (113 of 313 twenty-six-week courses). Both functions now divide by the course length only when it is a
-- year or more, so a course under a year compares and shows its whole-course fee. Same shapes, same grants. Read only.
create or replace function public.admin_fee_rules_report(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_tol numeric := coalesce((p_args->>'tolerance')::numeric, 0.05); v_year int := coalesce((p_args->>'year')::int, extract(year from now())::int); v_out jsonb;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  with pg as (
    select f.course_id, f.amount pa, f.fee_year from catalogue.course_fees f
     where f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.status = 'active' and f.amount > 0
       and f.basis in ('annual', 'indicative_annual', 'current indicative annual international tuition')),
  cr as (select course_id, amount ca from catalogue.course_fees where fee_type = 'tuition' and audience = 'international' and status = 'active' and basis = 'registered_total_course' and amount > 0),
  j as (
    select c.id course_id, c.display_title, p.id provider_id, p.display_name provider, k.iso_alpha2 country, pg.pa, pg.fee_year,
           cr.ca / greatest(case c.duration_unit when 'weeks' then c.duration_value / 52.0 when 'years' then c.duration_value when 'months' then c.duration_value / 12.0 end, 1) ann,
           exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = c.id and m.field in ('tuition', 'fee', 'fees')) locked
      from pg join cr using (course_id) join catalogue.courses c on c.id = pg.course_id
      join catalogue.providers p on p.id = c.provider_id left join ref.countries k on k.id = p.country_id
     where c.duration_value > 0 and c.duration_unit in ('weeks', 'years', 'months')),
  m as (select j.*, abs(pa - ann) / ann gap, (abs(pa - ann) / ann > v_tol) differs, (fee_year >= v_year) page_year_ok from j)
  select jsonb_build_object(
    'as_at', now(), 'tolerance', v_tol, 'year', v_year,
    'compared', (select count(*) from m),
    'agree', (select count(*) from m where not differs),
    'differ', (select count(*) from m where differs),
    'would_change', (select count(*) from m where differs and page_year_ok and not locked),
    'protected_by_hand', (select count(*) from m where differs and page_year_ok and locked),
    'kept_older_year', (select count(*) from m where differs and fee_year < v_year),
    'kept_no_year', (select count(*) from m where differs and fee_year is null),
    'page_higher', (select count(*) from m where differs and page_year_ok and not locked and pa > ann),
    'page_lower', (select count(*) from m where differs and page_year_ok and not locked and pa < ann),
    'gap_over_20', (select count(*) from m where differs and page_year_ok and not locked and gap > 0.2),
    'by_country', (select coalesce(jsonb_agg(x order by x->>'country'), '[]'::jsonb) from (select jsonb_build_object('country', country, 'compared', count(*), 'would_change', count(*) filter (where differs and page_year_ok and not locked)) x from m group by country) t),
    'by_provider', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select jsonb_build_object('provider_id', provider_id, 'provider', provider, 'country', country, 'compared', count(*), 'would_change', count(*) filter (where differs and page_year_ok and not locked)) x from m group by provider_id, provider, country order by count(*) filter (where differs and page_year_ok and not locked) desc limit 25) t),
    'sample', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select jsonb_build_object('course_id', course_id, 'title', display_title, 'provider', provider, 'page_fee', pa, 'page_year', fee_year, 'cricos_per_year', round(ann, 0), 'gap', round(gap, 2)) x from m where differs and page_year_ok and not locked order by gap desc limit 20) t)
  ) into v_out;
  return v_out;
end $f$;
revoke all on function public.admin_fee_rules_report(jsonb) from public, anon;
grant execute on function public.admin_fee_rules_report(jsonb) to authenticated;

create or replace function security.course_fee_used_v1(p_course_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_year int := extract(year from now())::int; pg record; cr record; v_yrs numeric; v_locked boolean; v_ann numeric;
begin
  select f.amount, f.fee_year, f.currency_code into pg from catalogue.course_fees f
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
  if pg.amount is not null and (pg.fee_year >= v_year or cr.amount is null) then
    return jsonb_build_object('source', 'page', 'per_year', pg.amount, 'currency', pg.currency_code, 'year', pg.fee_year, 'cricos_per_year', v_ann, 'locked', v_locked,
      'reason', case when cr.amount is null then 'No CRICOS fee is registered, so the course page fee is used.' else 'The course page names ' || pg.fee_year || ', this year or later, so the page fee is used.' end);
  elsif cr.amount is not null and v_ann is not null then
    return jsonb_build_object('source', 'cricos', 'per_year', v_ann, 'currency', cr.currency_code, 'year', null, 'page_per_year', pg.amount, 'page_year', pg.fee_year, 'locked', v_locked,
      'reason', case when pg.amount is null then 'No course page fee has been read, so the CRICOS registered fee is used (the registered total, divided by the course length when that is a year or more).'
                     when pg.fee_year is null then 'The course page names no year, so the CRICOS registered fee is used (the registered total, divided by the course length when that is a year or more).'
                     else 'The course page names ' || pg.fee_year || ', an earlier year, so the CRICOS registered fee is used (the registered total, divided by the course length when that is a year or more).' end);
  end if;
  return jsonb_build_object('source', null, 'locked', v_locked, 'reason', 'No page fee or CRICOS fee with a course length is stored.');
end $f$;
revoke all on function security.course_fee_used_v1(uuid) from public, anon, authenticated;
