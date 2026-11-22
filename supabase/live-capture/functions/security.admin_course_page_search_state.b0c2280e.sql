CREATE OR REPLACE FUNCTION security.admin_course_page_search_state(p_page jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'search', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  select coalesce(jsonb_agg(
    i.item || jsonb_build_object(
      'search_projected', d.course_id is not null,
      'search_projection_status', d.publication_status,
      'search_projection_completeness', d.completeness_score,
      'search_projection_version', d.projection_version,
      'search_catalogue_generation', d.catalogue_generation,
      'search_projection_updated_at', d.updated_at,
      'search_projection_generated_at', d.generated_at,
      'search_has_fee', d.has_fee,
      'search_has_intake', d.has_intake,
      'search_has_english', d.has_english,
      'search_has_scholarship', d.has_scholarship
    )
    -- 25 Oct 2026 (hotfix v2.15.351): the columns the normal list path carries, from the same rows, so every sort shows them
    || jsonb_build_object(
      'intl_fee_amount', ifee.amount, 'intl_fee_currency', ifee.currency_code::text, 'intl_fee_year', ifee.fee_year, 'intl_fee_basis', ifee.basis,
      'city_names', gcity.city_names,
      'display_code', coalesce(ssc.identifier, i.item->>'course_code'), 'code_kind', case when ssc.identifier is not null then 'studysearch' else 'own' end,
      'open_to_international', oc.open_to_international, 'open_to_domestic', oc.open_to_domestic
    ) order by i.ord
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(p_page->'items','[]'::jsonb)) with ordinality as i(item,ord)
  left join search.course_documents d on d.course_id=nullif(i.item->>'id','')::uuid
  left join lateral (select cf.amount, cf.currency_code, cf.fee_year, cf.basis from catalogue.course_fees cf where cf.course_id=nullif(i.item->>'id','')::uuid
    and cf.fee_type='provider_current_tuition' and cf.audience='international' and cf.status='active' order by cf.fee_year desc nulls last, cf.updated_at desc limit 1) ifee on true
  left join lateral (select string_agg(distinct ca.city, ', ') city_names from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id
    where cc.course_id=nullif(i.item->>'id','')::uuid and nullif(btrim(ca.city),'') is not null) gcity on true
  left join lateral (select ci.identifier from catalogue.course_identifiers ci where ci.course_id=nullif(i.item->>'id','')::uuid and ci.scheme='studysearch'
    and not exists (select 1 from catalogue.course_identifiers j join ref.course_code_schemes s on s.scheme=j.scheme and s.printed where j.course_id=nullif(i.item->>'id','')::uuid) limit 1) ssc on true
  left join catalogue.courses oc on oc.id=nullif(i.item->>'id','')::uuid;

  return jsonb_set(coalesce(p_page,'{}'::jsonb),'{items}',v_items,true);
end
$function$
