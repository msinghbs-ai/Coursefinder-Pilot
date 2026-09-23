-- CF-CHG-20260915-247 WP3b — website scholarship search (additive; Zoho functions untouched).
create or replace function public.website_edge_scholarship_search_v1(p_filters jsonb default '{}'::jsonb, p_page integer default 1, p_page_size integer default 20)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','scholarship','catalogue','ref','security','api' as $$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1);
  v_size int := coalesce(p_page_size,20);
  v_kw text := nullif(btrim(coalesce(f->>'keyword','')),'');
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_cities text[] := (select array_agg(lower(x)) from unnest(api.website_text_array(coalesce(f->'cities',f->'city'))) x);
  v_levels text[] := api.website_text_array(f->'study_level_codes');
  v_types text[] := api.website_text_array(f->'amount_types');
  v_open boolean := coalesce((f->>'open_only')::boolean,false);
  v_not_applied text[] := '{}';
  v_result jsonb;
begin
  if v_page < 1 then raise exception 'INVALID_INPUT: page must be >= 1' using errcode='22023'; end if;
  if v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page_size must be 1-50' using errcode='22023'; end if;
  if api.website_text_array(f->'study_area_codes') is not null then v_not_applied := array_append(v_not_applied,'study_area_codes'); end if;
  if f ? 'min_academic_score' then v_not_applied := array_append(v_not_applied,'min_academic_score'); end if;
  if f ? 'citizenship' then v_not_applied := array_append(v_not_applied,'citizenship'); end if;

  with base as (
    select s.*, pr.stable_key provider_key, coalesce(nullif(pr.display_name,''), pr.canonical_name) provider_name,
      case when s.award_value_type='percentage' and s.award_percentage >= 100 and coalesce(s.award_applies_to_fee_type,s.award_fee_basis)='tuition_fee' then 'full_tuition'
           when s.award_value_type='percentage' and coalesce(s.award_applies_to_fee_type,s.award_fee_basis)='tuition_fee' then 'percentage_tuition'
           when s.award_value_type='percentage' then 'percentage'
           when s.award_value_type='fixed_amount' then 'fixed_amount' end as amount_type,
      case when s.application_close_date is null then 'unknown'
           when s.application_close_date < current_date then 'closed' else 'open' end as deadline_status
    from scholarship.scholarships s
    left join catalogue.providers pr on pr.id = s.provider_id
    where s.lifecycle_status = 'active'
      and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id)
      and not exists (select 1 from security.layer4_search_blocked_providers b where b.provider_id = s.provider_id)
      and (v_kw is null or s.name ilike '%'||v_kw||'%' or pr.canonical_name ilike '%'||v_kw||'%' or pr.display_name ilike '%'||v_kw||'%'
           or exists (select 1 from scholarship.criteria c where c.scholarship_id=s.id and c.human_text ilike '%'||v_kw||'%'))
      and (v_providers is null or pr.stable_key = any(v_providers))
      and (v_cities is null or exists (select 1 from catalogue.campuses k where k.provider_id = s.provider_id and lower(btrim(k.city)) = any(v_cities)))
      -- excluded only when a level restriction is stated and none matches
      and (v_levels is null or not exists (select 1 from scholarship.scopes sc where sc.scholarship_id=s.id and sc.study_level_id is not null and sc.include_exclude='include')
           or exists (select 1 from scholarship.scopes sc join ref.study_levels sl on sl.id=sc.study_level_id
                      where sc.scholarship_id=s.id and sc.include_exclude='include' and sl.code = any(v_levels)))
  ), filtered as (
    select * from base b
    where (not v_open or b.deadline_status <> 'closed')
      and (v_types is null or b.amount_type = any(v_types))
  ), counted as (select count(*) total from filtered),
  paged as (
    select * from filtered
    order by (deadline_status='open') desc, application_close_date nulls last, lower(name), stable_key
    limit v_size offset (v_page-1)*v_size
  )
  select jsonb_build_object(
    'contract_version','website-scholarship-search-v1',
    'total',(select total from counted),
    'page',v_page,'page_size',v_size,'sort','open_deadline_first',
    'filters_not_applied',to_jsonb(v_not_applied),
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'scholarship_id',p.stable_key,
      'reference_code',(select i.identifier_value from scholarship.identifiers i where i.scholarship_id=p.id and i.scheme='study_australia_scholarship_id' and i.status is distinct from 'retired' order by i.is_primary desc limit 1),
      'name',p.name,
      'provider',jsonb_build_object('provider_id',p.provider_key,'name',p.provider_name),
      'campus_city',null,
      'provider_cities',coalesce((select jsonb_agg(distinct k.city order by k.city) from catalogue.campuses k where k.provider_id=p.provider_id and nullif(btrim(k.city),'') is not null),'[]'::jsonb),
      'amount_type',p.amount_type,
      'amount_value',case p.amount_type when 'fixed_amount' then p.award_amount when 'full_tuition' then 100 when 'percentage_tuition' then p.award_percentage when 'percentage' then p.award_percentage end,
      'amount_currency',case when p.amount_type='fixed_amount' then p.award_currency_code end,
      'amount_note',p.award_value_text,
      'renewable',case when p.award_duration_basis in ('annual_program_duration','program_duration') then true end,
      'coverage_duration',p.award_duration_basis,
      'study_levels',null,
      'study_area_codes',null,
      'min_academic_score',null,
      'age_min',(select c.value_number from scholarship.criteria c where c.scholarship_id=p.id and c.criterion_type='minimum_age' and c.machine_evaluable limit 1),
      'age_max',null,
      'citizenship_eligibility',null,
      'eligibility_summary',(select left(c.human_text,1200) from scholarship.criteria c where c.scholarship_id=p.id and c.criterion_type='published_eligibility_narrative' limit 1),
      'application_open_date',p.application_open_date,
      'application_deadline',p.application_close_date,
      'deadline_status',p.deadline_status,
      'deadline_is_rolling',null,
      'official_url',coalesce((select i.identifier_value from scholarship.identifiers i where i.scholarship_id=p.id and i.scheme='first_party_detail_url' order by i.is_primary desc limit 1), p.source_url),
      'official_url_source',case when exists(select 1 from scholarship.identifiers i where i.scholarship_id=p.id and i.scheme='first_party_detail_url') then 'first_party' else 'study_australia' end,
      'academic_year',p.academic_year,
      'publication_status',p.publication_status,
      'freshness',jsonb_build_object('updated_at',p.updated_at)
    ) order by (p.deadline_status='open') desc, p.application_close_date nulls last, lower(p.name), p.stable_key) from paged p),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $$;
revoke all on function public.website_edge_scholarship_search_v1(jsonb,integer,integer) from public, anon, authenticated;
grant execute on function public.website_edge_scholarship_search_v1(jsonb,integer,integer) to service_role;
