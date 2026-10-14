create or replace function api.website_v2_tuition(p_doc search.course_documents)
returns jsonb language sql stable set search_path to 'pg_catalog','search' as $$
  with pt as (
    select (o->>'amount')::numeric amount, o->>'currency' currency, o->>'basis' basis, nullif(o->>'fee_year','')::int fee_year
    from jsonb_array_elements(coalesce(p_doc.provider_tuition_options,'[]'::jsonb)) o
    where (o->>'amount') ~ '^[0-9]+(\.[0-9]+)?$' and (o->>'amount')::numeric > 0
    order by nullif(o->>'fee_year','')::int desc nulls last limit 1
  ), dur as (
    select case lower(coalesce(c.duration_unit,'')) when 'weeks' then c.duration_value when 'months' then c.duration_value*52/12.0 when 'years' then c.duration_value*52 end weeks
    from catalogue.courses c where c.id = p_doc.course_id
  ), t as (
    select
      coalesce(pt.amount, nullif(p_doc.regulatory_tuition_amount,0)) amount,
      case when pt.amount is not null then pt.currency else p_doc.regulatory_tuition_currency end currency,
      case when pt.amount is not null then
             case when pt.basis ~* 'total|course' and pt.basis !~* 'annual' then 'course_total'
                  when pt.basis ~* 'session|semester|trimester|unit|credit' then 'per_session'
                  when pt.basis ~* 'indicative' then 'indicative_annual'
                  when pt.basis ~* 'annual|per.?year|yearly' then 'annual'
                  else 'unspecified' end
           when nullif(p_doc.regulatory_tuition_amount,0) is not null then 'course_total' end basis,
      case when pt.amount is not null then 'provider_current' when nullif(p_doc.regulatory_tuition_amount,0) is not null then 'regulatory_registered' end source,
      pt.basis basis_label, pt.fee_year
    from (select 1) one left join pt on true
  )
  select case when t.amount is null then null else jsonb_build_object(
    'amount', t.amount, 'currency', t.currency, 'basis', t.basis, 'basis_label', t.basis_label, 'source', t.source, 'year', t.fee_year,
    'annual_amount', case when t.basis in ('annual','indicative_annual') then t.amount
                          when t.basis = 'course_total' and (select weeks from dur) >= 52 then round(t.amount / ((select weeks from dur)/52.0)) end,
    'annual_is_derived', (t.basis = 'course_total' and coalesce((select weeks from dur),0) >= 52)) end
  from t
$$;
revoke all on function api.website_v2_tuition(search.course_documents) from public;
