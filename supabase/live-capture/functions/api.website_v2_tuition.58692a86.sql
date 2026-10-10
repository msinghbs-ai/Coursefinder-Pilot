CREATE OR REPLACE FUNCTION api.website_v2_tuition(p_doc search.course_documents)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'search', 'catalogue', 'api'
AS $function$
  with w as (select api.website_v2_weeks(c.duration_value, c.duration_unit) weeks from catalogue.courses c where c.id = p_doc.course_id),
  pt as (select api.website_v2_latest_fee(p_doc.provider_tuition_options) o),
  t as (
    select case when (select o from pt) is not null then ((select o->>'amount' from pt))::numeric when coalesce(p_doc.regulatory_tuition_amount,0) >= 1000 then p_doc.regulatory_tuition_amount end amount,
           case when (select o from pt) is not null then (select o->>'currency' from pt) else p_doc.regulatory_tuition_currency end currency,
           case when (select o from pt) is not null then api.website_v2_fee_basis((select o->>'basis' from pt)) when coalesce(p_doc.regulatory_tuition_amount,0) >= 1000 then 'course_total' end basis,
           case when (select o from pt) is not null then 'provider_current' when coalesce(p_doc.regulatory_tuition_amount,0) >= 1000 then 'regulatory_registered' end source,
           (select o->>'basis' from pt) basis_label, nullif((select o->>'fee_year' from pt),'')::int fee_year)
  select case when t.amount is null then null else jsonb_build_object(
    'amount', t.amount, 'currency', t.currency, 'basis', t.basis, 'basis_label', t.basis_label, 'source', t.source, 'year', t.fee_year,
    'annual_amount', api.website_v2_annual(p_doc.provider_tuition_options, p_doc.regulatory_tuition_amount, (select weeks from w)),
    'annual_is_derived', (t.basis = 'course_total' and coalesce((select weeks from w),0) >= 52)) end
  from t
$function$
