-- CF-247 Decision 255 (6 Oct 2026, Platform Admin, multiple choice "Add a labelled fee used to the course drawer and APIs").
-- Both fees are already stored side by side: the page's current annual international fee (provider_current_tuition) and
-- the CRICOS registered course total (tuition, registered_total_course). This adds a label that says which one the
-- course uses and why, by the rule recorded under Decisions 254 and 255:
--   the page fee is used when the page names this year or later (Decision 255, which supersedes Decision 225 for a labelled
--   international annual fee), or when no CRICOS fee is registered. Otherwise the CRICOS total divided by the course
--   duration in years is used. A course with a fee entered or locked by hand is marked locked.
-- security.course_fee_used_v1(course_id) is read only. admin_course_fee_summary (the course drawer's fee read) gains one
-- key, fee_used, behind an md5 guard. No stored fee is changed. The Zoho, Wix and website APIs are not changed here: they read
-- through their own prebuilt layer and gain the field in a separate step.
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
  if cr.amount is not null and coalesce(v_yrs, 0) > 0 then v_ann := round(cr.amount / v_yrs, 0); end if;
  if pg.amount is not null and (pg.fee_year >= v_year or cr.amount is null) then
    return jsonb_build_object('source', 'page', 'per_year', pg.amount, 'currency', pg.currency_code, 'year', pg.fee_year, 'cricos_per_year', v_ann, 'locked', v_locked,
      'reason', case when cr.amount is null then 'No CRICOS fee is registered, so the course page fee is used.' else 'The course page names ' || pg.fee_year || ', this year or later, so the page fee is used.' end);
  elsif cr.amount is not null and v_ann is not null then
    return jsonb_build_object('source', 'cricos', 'per_year', v_ann, 'currency', cr.currency_code, 'year', null, 'page_per_year', pg.amount, 'page_year', pg.fee_year, 'locked', v_locked,
      'reason', case when pg.amount is null then 'No course page fee has been read, so the CRICOS registered fee is used (total divided by the course length).'
                     when pg.fee_year is null then 'The course page names no year, so the CRICOS registered fee is used (total divided by the course length).'
                     else 'The course page names ' || pg.fee_year || ', an earlier year, so the CRICOS registered fee is used (total divided by the course length).' end);
  end if;
  return jsonb_build_object('source', null, 'locked', v_locked, 'reason', 'No page fee or CRICOS fee with a course length is stored.');
end $f$;
revoke all on function security.course_fee_used_v1(uuid) from public, anon, authenticated;

do $p$
declare s text; d text;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'security' and p.proname = 'admin_course_fee_summary';
  if md5(s) is distinct from 'a9edf2b34508931f9eea1df7c8ed6dfc' then raise exception 'security.admin_course_fee_summary changed (md5 %), not replacing', md5(s); end if;
  if (length(d) - length(replace(d, '''cricos_registered'',coalesce((', ''))) / length('''cricos_registered'',coalesce((') <> 1 then raise exception 'snippet not found once'; end if;
  d := replace(d, '''cricos_registered'',coalesce((', '''fee_used'',security.course_fee_used_v1(p_course_id),' || chr(10) || '    ''cricos_registered'',coalesce((');
  execute d;
end $p$;
