-- CF-CHG-20260915-247
-- Use independently admitted, retained-Evidence provider-current tuition facts as positive benchmark truth.
-- Unresolved Layer 3 backlog remains negative/exception material and is not treated as known-positive truth.
create or replace function public.layer3_cf245_tuition_benchmark_cases_service(p_limit integer default 4)
returns jsonb
language plpgsql stable security definer
set search_path='pg_catalog','pipeline','catalogue'
as $$
declare v_limit integer:=least(greatest(coalesce(p_limit,4),3),6);v_rows jsonb;
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.provider_cricos,x.course_cricos),'[]'::jsonb) into v_rows
  from (
    select f.id as source_record_id,e.source_id,f.evidence_id,f.course_id,
      coalesce(pi.identifier,'provider-'||c.provider_id::text) as provider_cricos,
      coalesce(ci.identifier,'course-'||f.course_id::text) as course_cricos,
      e.source_url,
      jsonb_build_object('amount',f.amount,'currency_code',trim(f.currency_code),'basis',f.basis,'fee_year',f.fee_year,'audience','international') as candidate_payload,
      e.storage_path,e.mime_type,e.content_hash,e.captured_at
    from catalogue.course_fees f
    join catalogue.courses c on c.id=f.course_id
    join pipeline.evidence_artifacts e on e.id=f.evidence_id
    left join lateral (select identifier from catalogue.provider_identifiers p where p.provider_id=c.provider_id and p.is_primary order by p.verified_at desc nulls last limit 1) pi on true
    left join lateral (select identifier from catalogue.course_identifiers q where q.course_id=f.course_id and q.is_primary order by q.verified_at desc nulls last limit 1) ci on true
    where f.status='active' and f.audience='international' and f.fee_type='provider_current_tuition'
      and f.basis in ('annual','indicative_annual') and f.amount>0 and trim(f.currency_code) in ('AUD','NZD')
      and e.storage_path is not null and e.content_hash is not null
    order by f.updated_at desc,f.id
    limit v_limit
  ) x;
  return v_rows;
end $$;
revoke all on function public.layer3_cf245_tuition_benchmark_cases_service(integer) from public,anon,authenticated;
grant execute on function public.layer3_cf245_tuition_benchmark_cases_service(integer) to service_role;
comment on function public.layer3_cf245_tuition_benchmark_cases_service(integer) is 'CF-247 benchmark corpus: independently admitted, retained-Evidence provider-current tuition positives only; unresolved backlog is not positive truth.';
