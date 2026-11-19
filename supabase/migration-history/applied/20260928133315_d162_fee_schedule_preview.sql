-- CF-247 Decision 162 step 2: read-only comparison of a parsed provider fee schedule with the catalogue.
-- Each row {course_cricos, title, amount} is bound by the provider's CRICOS code plus the course CRICOS code
-- (Decision 149 scope). For each bound course it reports what an apply would do under the one-current-tuition
-- rule (Decision 132): insert (no provider tuition), same (identical amount and year), replace_older_year,
-- conflict_same_year (same fee year, different amount: goes to Layer 4, never overwritten), newer_exists
-- (a later fee year is already current: skipped). Nothing is written.
create or replace function public.svc_fee_schedule_preview(p_provider_cricos text, p_fee_year integer, p_rows jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','catalogue','pipeline','ref' as $f$
declare v_provider uuid; v_out jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>3000 then raise exception 'rows must be an array of at most 3000'; end if;
  select pr.provider_id into v_provider from catalogue.provider_registrations pr join catalogue.providers p on p.id=pr.provider_id join ref.countries c on c.id=p.country_id
   where c.iso_alpha2='AU' and lower(pr.registration_scheme)='cricos' and upper(btrim(pr.registration_code))=upper(btrim(p_provider_cricos)) limit 1;
  if v_provider is null then raise exception 'provider CRICOS not resolved'; end if;
  with r as (
    select upper(btrim(x->>'course_cricos')) code, x->>'title' title, (x->>'amount')::numeric amount, ord
      from jsonb_array_elements(p_rows) with ordinality z(x,ord)
  ), b as (
    select r.*, cr.course_id, c.canonical_title, c.lifecycle_status,
           (select jsonb_build_object('amount',f.amount,'fee_year',f.fee_year,'basis',f.basis) from catalogue.course_fees f
             where f.course_id=cr.course_id and f.fee_type='provider_current_tuition' and coalesce(f.status,'active')='active'
             order by f.fee_year desc nulls last limit 1) cur,
           (select f.amount from catalogue.course_fees f where f.course_id=cr.course_id and f.fee_type='tuition' and f.basis='registered_total_course' and coalesce(f.status,'active')='active' limit 1) cricos_total
      from r left join catalogue.course_registrations cr on lower(cr.scheme)='cricos' and upper(btrim(cr.registration_code))=r.code
                  and exists(select 1 from catalogue.courses c2 where c2.id=cr.course_id and c2.provider_id=v_provider)
      left join catalogue.courses c on c.id=cr.course_id
  ), d as (
    select b.*, case
      when course_id is null then 'unbound'
      when lifecycle_status<>'active' then 'course_not_active'
      when cur is null then 'insert'
      when (cur->>'fee_year')::int is null or (cur->>'fee_year')::int < p_fee_year then 'replace_older_year'
      when (cur->>'fee_year')::int > p_fee_year then 'newer_exists'
      when (cur->>'amount')::numeric = amount then 'same'
      else 'conflict_same_year' end action
    from b
  )
  select jsonb_build_object(
    'provider_id',v_provider,'fee_year',p_fee_year,'rows',(select count(*) from d),
    'bound',(select count(*) from d where course_id is not null),
    'actions',(select jsonb_object_agg(action,n) from (select action,count(*) n from d group by 1) a),
    'duplicate_codes',(select count(*) from (select code from d group by code having count(*)>1) q),
    'provider_active_courses',(select count(*) from catalogue.courses c where c.provider_id=v_provider and c.lifecycle_status='active'),
    'amount_range',(select jsonb_build_object('min',min(amount),'max',max(amount)) from d),
    'annual_vs_cricos_total_ratio',(select jsonb_build_object('min',round(min(cricos_total/nullif(amount,0)),2),'max',round(max(cricos_total/nullif(amount,0)),2)) from d where cricos_total is not null),
    'unbound_sample',(select coalesce(jsonb_agg(jsonb_build_object('code',code,'title',title)),'[]'::jsonb) from (select * from d where action='unbound' order by ord limit 10) u),
    'conflict_sample',(select coalesce(jsonb_agg(jsonb_build_object('code',code,'schedule',amount,'current',cur)),'[]'::jsonb) from (select * from d where action in ('conflict_same_year','newer_exists') order by ord limit 10) u),
    'sample',(select coalesce(jsonb_agg(jsonb_build_object('code',code,'title',title,'amount',amount,'action',action,'catalogue_title',canonical_title)),'[]'::jsonb) from (select * from d order by ord limit 8) u)
  ) into v_out;
  return v_out;
end $f$;
revoke all on function public.svc_fee_schedule_preview(text,integer,jsonb) from public, anon, authenticated;
grant execute on function public.svc_fee_schedule_preview(text,integer,jsonb) to service_role;
