create or replace function security.course_fee_rank_key(f catalogue.course_fees)
returns text language sql stable security definer set search_path to 'pg_catalog','pipeline','catalogue'
as $$
  select (case when exists(select 1 from pipeline.sources s where s.id=f.source_id and s.label like 'Layer 4 human review%') then '1' else '0' end)
      || (case when f.fee_year is not null then '1' else '0' end)
      || (case when f.notes like 'CF-247 provider rule admission%' then '1' else '0' end)
      || to_char(coalesce(f.last_verified_at, f.updated_at, 'epoch'::timestamptz),'YYYYMMDDHH24MISS')
      || f.id::text
$$;

create or replace function security.course_fee_dedupe_v1(p_apply boolean default false, p_course_ids uuid[] default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','security','catalogue','search'
as $function$
declare v_list jsonb; v_n int := 0; v_courses uuid[];
begin
  with a as (
    select f.*, security.course_fee_rank_key(f) rk,
           count(*) over (partition by f.course_id, f.audience, f.fee_type, f.amount) n
    from catalogue.course_fees f
    where f.fee_type='provider_current_tuition' and f.status='active'
      and (p_course_ids is null or f.course_id = any(p_course_ids))),
  r as (select a.*, row_number() over (partition by course_id, audience, fee_type, amount order by rk desc) pos from a where n>1)
  select jsonb_agg(jsonb_build_object('course',(select course_code from catalogue.courses c where c.id=r.course_id),
            'keep', pos=1, 'amount', amount, 'year', fee_year, 'basis', basis, 'origin',
            case when notes like 'CF-247 provider rule admission%' then 'provider rule' when notes ilike '%layer 3%' then 'Layer 3 AI' else 'other' end)
          order by course_id, pos),
         array_agg(distinct course_id)
  into v_list, v_courses from r;
  if p_apply and v_courses is not null then
    with a as (
      select f.id, row_number() over (partition by f.course_id, f.audience, f.fee_type, f.amount order by security.course_fee_rank_key(f) desc) pos,
             count(*) over (partition by f.course_id, f.audience, f.fee_type, f.amount) n
      from catalogue.course_fees f
      where f.fee_type='provider_current_tuition' and f.status='active' and f.course_id = any(v_courses))
    update catalogue.course_fees f set status='superseded', updated_at=now(),
           notes = f.notes || ' | superseded by one-current-tuition rule (Decision 132) ' || to_char(now(),'YYYY-MM-DD')
    from a where a.id=f.id and a.n>1 and a.pos>1;
    get diagnostics v_n = row_count;
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
  end if;
  return jsonb_build_object('mode',case when p_apply then 'apply' else 'proof' end,'courses',coalesce(cardinality(v_courses),0),'superseded',v_n,'rows',coalesce(v_list,'[]'::jsonb));
end $function$;
revoke all on function security.course_fee_dedupe_v1(boolean,uuid[]) from public, anon, authenticated;
revoke all on function security.course_fee_rank_key(catalogue.course_fees) from public, anon, authenticated;
