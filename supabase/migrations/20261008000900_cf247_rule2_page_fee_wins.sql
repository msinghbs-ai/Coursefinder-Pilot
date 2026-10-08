-- CF-247 Standing Review Rule 2 (8 Oct 2026, Platform Admin): "regulatory values held until evidence from course page says
-- otherwise"; "Dont review it, provider page is the truth and overwrites it as it will detail registration fee inclusion, as
-- long as evidence is captured no need to review." and "No review required".
-- Rule 2 (page fee against the CRICOS registered fee) raises no Layer 4 item. The CRICOS registered fee is held until the
-- provider's own course page gives an annual international fee with captured evidence; that page fee then wins, whatever year
-- the page names (or none). This replaces Decision 255's "page names this year or later" condition.
-- Kept safeguards: the evidence must exist and its page must be on the provider's own site (a host on the Rule 1 shared-host
-- list that is not the provider's website does not count); a course with a fee entered or locked by hand keeps the earlier
-- rule unchanged. Both stored fees stay as they are; only the label of which fee is used changes. No stored row is written.
do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'security.course_fee_used_v1(uuid)'::regprocedure) is distinct from 'ae51169df5c347a5fcf5628c6f8e87dd' then
    raise exception 'course_fee_used_v1 is not the migration 1790 definition; refusing to replace it';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_fee_rules_report(jsonb)'::regprocedure) is distinct from '10bbafb98bb8edb77579a327499e24db' then
    raise exception 'admin_fee_rules_report is not the migration 1800 definition; refusing to replace it';
  end if;
end $g$;

-- The Rule 1 shared-host list as last measured by the daily rule run (cheap to read per course).
create or replace function security.l4_shared_hosts_v1()
returns text[] language sql stable security definer set search_path = '' as $f$
  select coalesce(array(select jsonb_array_elements_text(r.raised->'hosts')), '{}'::text[])
    from (select raised from pipeline.layer4_rule_runs where rule = 'unofficial_source' order by at desc limit 1) r
$f$;
revoke all on function security.l4_shared_hosts_v1() from public, anon, authenticated;

-- true when the evidence page is on the provider's own site (or at least not on a shared directory host)
create or replace function security.fee_evidence_own_site_v1(p_evidence_id uuid, p_course_id uuid)
returns boolean language sql stable security definer set search_path = '' as $f$
  select case when ea.id is null then false
              when h is null then true
              when not (h = any(security.l4_shared_hosts_v1())) then true
              else coalesce(h = ph or h like '%.' || ph, false) end
    from (select 1) one
    left join pipeline.evidence_artifacts ea on ea.id = p_evidence_id
    left join lateral (select substring(ea.source_url from '^https?://(?:www\.)?([^/:?#]+)') h) a on true
    left join lateral (select substring(p.website from '^https?://(?:www\.)?([^/:?#]+)') ph
                         from catalogue.courses c join catalogue.providers p on p.id = c.provider_id where c.id = p_course_id) b on true
$f$;
revoke all on function security.fee_evidence_own_site_v1(uuid, uuid) from public, anon, authenticated;

create or replace function security.course_fee_used_v1(p_course_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
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
end $f$;
revoke all on function security.course_fee_used_v1(uuid) from public, anon, authenticated;

create or replace function public.admin_fee_rules_report(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_tol numeric := coalesce((p_args->>'tolerance')::numeric, 0.05); v_year int := coalesce((p_args->>'year')::int, extract(year from now())::int); v_out jsonb;
  v_hosts text[] := security.l4_shared_hosts_v1();
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  with pg as (
    select distinct on (f.course_id) f.course_id, f.amount pa, f.fee_year, f.evidence_id, substring(ea.source_url from '^https?://(?:www\.)?([^/:?#]+)') h
      from catalogue.course_fees f left join pipeline.evidence_artifacts ea on ea.id = f.evidence_id
     where f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.status = 'active' and f.amount > 0
       and f.basis in ('annual', 'indicative_annual', 'current indicative annual international tuition')
     order by f.course_id, f.fee_year desc nulls last, f.created_at desc),
  cr as (select distinct on (course_id) course_id, amount ca from catalogue.course_fees where fee_type = 'tuition' and audience = 'international' and status = 'active' and basis = 'registered_total_course' and amount > 0 order by course_id, created_at desc),
  j as (
    select c.id course_id, c.display_title, p.id provider_id, p.display_name provider, k.iso_alpha2 country, pg.pa, pg.fee_year,
           cr.ca / greatest(case c.duration_unit when 'weeks' then c.duration_value / 52.0 when 'years' then c.duration_value when 'months' then c.duration_value / 12.0 end, 1) ann,
           exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = c.id and m.field in ('tuition', 'fee', 'fees')) locked,
           (pg.evidence_id is not null and exists (select 1 from pipeline.evidence_artifacts ea where ea.id = pg.evidence_id)) has_ev,
           (pg.h = any(v_hosts) and not coalesce(pg.h = substring(p.website from '^https?://(?:www\.)?([^/:?#]+)') or pg.h like '%.' || substring(p.website from '^https?://(?:www\.)?([^/:?#]+)'), false)) shared
      from pg join cr using (course_id) join catalogue.courses c on c.id = pg.course_id
      join catalogue.providers p on p.id = c.provider_id left join ref.countries k on k.id = p.country_id
     where c.duration_value > 0 and c.duration_unit in ('weeks', 'years', 'months')),
  m as (select j.*, abs(pa - ann) / ann gap, (abs(pa - ann) / ann > v_tol) differs, (ann > 0 and abs(pa / ann - 0.5) < 0.03) half from j),
  w as (select m.*, (differs and not locked and has_ev and not shared) chg from m)
  select jsonb_build_object(
    'as_at', now(), 'tolerance', v_tol, 'year', v_year, 'rule', 'rule_2',
    'compared', (select count(*) from w),
    'agree', (select count(*) from w where not differs),
    'differ', (select count(*) from w where differs),
    'would_change', (select count(*) from w where chg),
    'suspected_half', (select count(*) from w where chg and half),
    'suspected_half_sample', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select jsonb_build_object('course_id', course_id, 'title', display_title, 'provider', provider, 'page_fee', pa, 'cricos_per_year', round(ann, 0)) x from w where chg and half order by provider, display_title limit 40) t),
    'protected_by_hand', (select count(*) from w where differs and locked),
    'kept_no_evidence', (select count(*) from w where differs and not locked and not has_ev),
    'kept_other_site', (select count(*) from w where differs and not locked and has_ev and shared),
    'page_higher', (select count(*) from w where chg and pa > ann),
    'page_lower', (select count(*) from w where chg and pa < ann),
    'gap_over_20', (select count(*) from w where chg and gap > 0.2),
    'by_country', (select coalesce(jsonb_agg(x order by x->>'country'), '[]'::jsonb) from (select jsonb_build_object('country', country, 'compared', count(*), 'would_change', count(*) filter (where chg)) x from w group by country) t),
    'by_provider', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select jsonb_build_object('provider_id', provider_id, 'provider', provider, 'country', country, 'compared', count(*), 'would_change', count(*) filter (where chg)) x from w group by provider_id, provider, country order by count(*) filter (where chg) desc limit 25) t),
    'sample', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select jsonb_build_object('course_id', course_id, 'title', display_title, 'provider', provider, 'page_fee', pa, 'page_year', fee_year, 'cricos_per_year', round(ann, 0), 'gap', round(gap, 2)) x from w where chg order by gap desc limit 20) t)
  ) into v_out;
  return v_out;
end $f$;
