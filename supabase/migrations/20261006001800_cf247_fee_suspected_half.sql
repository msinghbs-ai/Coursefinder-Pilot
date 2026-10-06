do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_fee_rules_report(jsonb)'::regprocedure) is distinct from 'd7233b6b8ea2a5f3687c1e9d238cf322' then
    raise exception 'admin_fee_rules_report is not the migration 1790 definition; refusing to replace it';
  end if;
end $g$;
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
  m as (select j.*, abs(pa - ann) / ann gap, (abs(pa - ann) / ann > v_tol) differs, (fee_year >= v_year) page_year_ok, (ann > 0 and abs(pa / ann - 0.5) < 0.03) half from j),
  w as (select m.*, (differs and page_year_ok and not locked and not half) chg from m)
  select jsonb_build_object(
    'as_at', now(), 'tolerance', v_tol, 'year', v_year,
    'compared', (select count(*) from w),
    'agree', (select count(*) from w where not differs),
    'differ', (select count(*) from w where differs),
    'would_change', (select count(*) from w where chg),
    'suspected_half', (select count(*) from w where differs and page_year_ok and not locked and half),
    'suspected_half_sample', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select jsonb_build_object('course_id', course_id, 'title', display_title, 'provider', provider, 'page_fee', pa, 'cricos_per_year', round(ann, 0)) x from w where differs and page_year_ok and not locked and half order by provider, display_title limit 40) t),
    'protected_by_hand', (select count(*) from w where differs and page_year_ok and locked),
    'kept_older_year', (select count(*) from w where differs and fee_year < v_year),
    'kept_no_year', (select count(*) from w where differs and fee_year is null),
    'page_higher', (select count(*) from w where chg and pa > ann),
    'page_lower', (select count(*) from w where chg and pa < ann),
    'gap_over_20', (select count(*) from w where chg and gap > 0.2),
    'by_country', (select coalesce(jsonb_agg(x order by x->>'country'), '[]'::jsonb) from (select jsonb_build_object('country', country, 'compared', count(*), 'would_change', count(*) filter (where chg)) x from w group by country) t),
    'by_provider', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select jsonb_build_object('provider_id', provider_id, 'provider', provider, 'country', country, 'compared', count(*), 'would_change', count(*) filter (where chg)) x from w group by provider_id, provider, country order by count(*) filter (where chg) desc limit 25) t),
    'sample', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select jsonb_build_object('course_id', course_id, 'title', display_title, 'provider', provider, 'page_fee', pa, 'page_year', fee_year, 'cricos_per_year', round(ann, 0), 'gap', round(gap, 2)) x from w where chg order by gap desc limit 20) t)
  ) into v_out;
  return v_out;
end $f$;
revoke all on function public.admin_fee_rules_report(jsonb) from public, anon;
grant execute on function public.admin_fee_rules_report(jsonb) to authenticated;
