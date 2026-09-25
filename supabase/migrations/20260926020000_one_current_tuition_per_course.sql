-- Decision 132: one current provider tuition record per course and audience.
-- Among ACTIVE records with the same amount, one stays active; the others become 'superseded'
-- (kept for audit, never deleted; search reads only active fees). Ranking:
--   1. a person's Layer 4 decision (source layer4_human_review)
--   2. a stated fee year over a blank one
--   3. a provider-rule admission over an AI admission (the rule's wording is the approved one)
--   4. the most recently verified
-- Records with different amounts are left for a person (a price change deserves review).
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
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','security','catalogue','search','pipeline'
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
    -- The kept record takes the approved provider rule's wording (Decision 97) where the
    -- provider has an active fee rule and the kept record says 'annual'.
    update catalogue.course_fees f set basis=pf.resolved_basis, updated_at=now(),
           notes = f.notes || ' | basis set to the approved provider rule wording (' || pf.rule_code || ', Decision 132)'
    from catalogue.courses c
    join pipeline.provider_fee_profiles pf on pf.provider_id=c.provider_id and pf.active
    where c.id=f.course_id and f.course_id = any(v_courses) and f.status='active'
      and f.fee_type='provider_current_tuition' and f.audience=pf.audience
      and f.basis='annual' and pf.resolved_basis<>'annual';
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
  end if;
  return jsonb_build_object('mode',case when p_apply then 'apply' else 'proof' end,'courses',coalesce(cardinality(v_courses),0),'superseded',v_n,'rows',coalesce(v_list,'[]'::jsonb));
end $function$;
revoke all on function security.course_fee_dedupe_v1(boolean,uuid[]) from public, anon, authenticated;
revoke all on function security.course_fee_rank_key(catalogue.course_fees) from public, anon, authenticated;

-- Keep it that way: after any active provider tuition is added or re-activated, tidy that course.
create or replace function security.course_fee_one_current_trg()
returns trigger language plpgsql security definer set search_path to 'pg_catalog','security','catalogue'
as $$
begin
  if new.fee_type='provider_current_tuition' and new.status='active' then
    perform security.course_fee_dedupe_v1(true, array[new.course_id]);
  end if;
  return null;
end $$;
revoke all on function security.course_fee_one_current_trg() from public, anon, authenticated;
drop trigger if exists course_fee_one_current on catalogue.course_fees;
create trigger course_fee_one_current after insert or update of status on catalogue.course_fees
for each row when (new.status='active' and new.fee_type='provider_current_tuition')
execute function security.course_fee_one_current_trg();
