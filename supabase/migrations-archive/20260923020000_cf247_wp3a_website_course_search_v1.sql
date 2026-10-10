-- CF-CHG-20260915-247 WP3a — website course search (additive; Zoho functions untouched).
create or replace function api.website_text_array(p jsonb)
returns text[] language sql immutable set search_path to 'pg_catalog' as $$
  select case jsonb_typeof(p)
    when 'array' then nullif(array(select btrim(x) from jsonb_array_elements_text(p) x where btrim(x)<>''), '{}')
    when 'string' then case when btrim(p #>> '{}')<>'' then array[btrim(p #>> '{}')] end
  end $$;

create or replace function public.website_edge_course_search_v1(p_filters jsonb default '{}'::jsonb, p_page integer default 1, p_page_size integer default 20)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','search','catalogue','ref','security','api' as $$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1);
  v_size int := coalesce(p_page_size,20);
  v_kw text := nullif(btrim(coalesce(f->>'keyword','')),'');
  v_countries text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(coalesce(f->'country_codes',f->'country_code'))) x);
  v_areas text[] := api.website_text_array(f->'study_area_codes');
  v_levels text[] := api.website_text_array(f->'study_level_codes');
  v_subdivs text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'subdivision_codes')) x);
  v_cities text[] := (select array_agg(lower(x)) from unnest(api.website_text_array(coalesce(f->'cities',f->'city'))) x);
  v_postcodes text[] := api.website_text_array(f->'postcodes');
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_modes text[] := api.website_text_array(f->'delivery_modes');
  v_min numeric := nullif(f->>'tuition_annual_min','')::numeric;
  v_max numeric := nullif(f->>'tuition_annual_max','')::numeric;
  v_result jsonb;
begin
  if v_page < 1 then raise exception 'INVALID_INPUT: page must be >= 1' using errcode='22023'; end if;
  if v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page_size must be 1-50' using errcode='22023'; end if;
  if (v_min is not null and v_min < 0) or (v_max is not null and v_max < 0) then raise exception 'INVALID_INPUT: tuition bounds must be >= 0' using errcode='22023'; end if;

  with base as (
    select d.*,
      round(c.duration_value * case lower(coalesce(c.duration_unit,'')) when 'weeks' then 12.0/52 when 'months' then 1 when 'years' then 12 else null end)::int as duration_months,
      case lower(coalesce(c.duration_unit,'')) when 'weeks' then c.duration_value when 'months' then c.duration_value*52/12 when 'years' then c.duration_value*52 end as duration_weeks
    from search.course_documents d
    left join catalogue.courses c on c.id = d.course_id
    where not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = d.course_id)
      and (v_kw is null
           or d.search_tsv @@ websearch_to_tsquery('english', v_kw)
           or d.course_title ilike '%'||v_kw||'%'
           or d.provider_name ilike '%'||v_kw||'%'
           or lower(d.course_code) = lower(v_kw)
           or lower(d.course_stable_key) = lower(v_kw))
      and (v_countries is null or d.country_code = any(v_countries))
      and (v_areas is null or d.primary_field_code = any(v_areas))
      and (v_levels is null or d.study_level_code = any(v_levels))
      and (v_subdivs is null or d.subdivision_codes && v_subdivs)
      and (v_providers is null or d.provider_stable_key = any(v_providers))
      and (v_modes is null or d.delivery_modes && v_modes)
      and (not coalesce((f->>'has_intake')::boolean,false) or d.has_intake)
      and (not coalesce((f->>'has_english')::boolean,false) or d.has_english)
      and (not coalesce((f->>'has_official_url')::boolean,false) or d.has_link)
      and (v_cities is null and v_postcodes is null or exists (
            select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id
            where cc.course_id = d.course_id
              and (v_cities is null or lower(btrim(k.city)) = any(v_cities))
              and (v_postcodes is null or btrim(k.postcode) = any(v_postcodes))))
  ), priced as (
    select b.*, t.*
    from base b
    cross join lateral (
      select
        case when pt.amount is not null then pt.amount else b.regulatory_tuition_amount end as t_amount,
        case when pt.amount is not null then pt.currency else b.regulatory_tuition_currency end as t_currency,
        case when pt.amount is not null then
               case when pt.basis ~* 'total|course' and pt.basis !~* 'annual' then 'course_total'
                    when pt.basis ~* 'indicative' then 'indicative_annual'
                    when pt.basis ~* 'annual|per.?year|yearly' then 'annual'
                    else 'unspecified' end
             when b.regulatory_tuition_amount is not null then 'course_total' end as t_basis,
        case when pt.amount is not null then 'provider_current' when b.regulatory_tuition_amount is not null then 'regulatory_registered' end as t_source,
        pt.basis as t_basis_label
      from (select (o->>'amount')::numeric amount, o->>'currency' currency, o->>'basis' basis
            from jsonb_array_elements(coalesce(b.provider_tuition_options,'[]'::jsonb)) o
            where (o->>'amount') is not null
            order by (o->>'fee_year') desc nulls last limit 1) pt
      right join (select 1) one on true
    ) t
  ), annualised as (
    select p.*,
      case when p.t_basis in ('annual','indicative_annual') then p.t_amount
           when p.t_basis = 'course_total' and p.duration_weeks >= 52 then round(p.t_amount / (p.duration_weeks/52.0))
      end as annual_amount,
      (p.t_basis = 'course_total' and p.duration_weeks >= 52) as annual_is_derived
    from priced p
  ), filtered as (
    select * from annualised a
    where (not coalesce((f->>'has_tuition')::boolean,false) or a.t_amount is not null)
      and (v_min is null or a.annual_amount >= v_min)
      and (v_max is null or a.annual_amount <= v_max)
  ), counted as (select count(*) total from filtered),
  paged as (
    select * from filtered order by lower(course_title), course_stable_key
    limit v_size offset (v_page-1)*v_size
  )
  select jsonb_build_object(
    'contract_version','website-search-v1',
    'total',(select total from counted),
    'page',v_page,'page_size',v_size,'sort','title_asc',
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'course_id',p.course_stable_key,
      'course_code',p.course_code,
      'title',p.course_title,
      'provider',jsonb_build_object('provider_id',p.provider_stable_key,'name',p.provider_name),
      'campus_city',(select k.city from catalogue.course_campuses cc join catalogue.campuses k on k.id=cc.campus_id
                     where cc.course_id=p.course_id and nullif(btrim(k.city),'') is not null
                     order by (v_cities is not null and lower(btrim(k.city)) = any(v_cities)) desc, (v_postcodes is not null and btrim(k.postcode) = any(v_postcodes)) desc, cc.is_primary desc nulls last, k.city limit 1),
      'campuses',coalesce((select jsonb_agg(jsonb_build_object('city',k.city,'postcode',k.postcode,'subdivision_code',s.code,'is_primary',coalesce(cc.is_primary,false))
                           order by (v_cities is not null and lower(btrim(k.city)) = any(v_cities)) desc, cc.is_primary desc nulls last, k.city)
                           from catalogue.course_campuses cc join catalogue.campuses k on k.id=cc.campus_id
                           left join ref.subdivisions s on s.id=k.subdivision_id
                           where cc.course_id=p.course_id),'[]'::jsonb),
      'study_level',jsonb_build_object('code',p.study_level_code,'name',(select sl.name from ref.study_levels sl where sl.code=p.study_level_code limit 1)),
      'study_area',jsonb_build_object('code',p.primary_field_code,'name',p.primary_field_name),
      'duration_months',p.duration_months,
      'tuition',case when p.t_amount is null then null else jsonb_build_object(
          'amount',p.t_amount,'currency',p.t_currency,'basis',p.t_basis,'basis_label',p.t_basis_label,'source',p.t_source,
          'annual_amount',p.annual_amount,'annual_is_derived',coalesce(p.annual_is_derived,false)) end,
      'intakes',coalesce((select jsonb_agg(distinct jsonb_build_object('label',i->>'label','year',i->'year','start_date',i->'start_date','application_deadline',i->'application_deadline'))
                          from jsonb_array_elements(coalesce(p.intake_options,'[]'::jsonb)) i where nullif(i->>'label','') is not null),'[]'::jsonb),
      'english_requirements',coalesce((select jsonb_agg(jsonb_build_object('test_code',e->>'test_code','test_name',e->>'test_name','min_overall_score',e->'overall_score'))
                          from jsonb_array_elements(coalesce(p.english_requirement_options,'[]'::jsonb)) e),'[]'::jsonb),
      'entry_requirements',jsonb_build_object('summary',null),
      'official_url',p.official_course_url,
      'delivery_modes',to_jsonb(p.delivery_modes),
      'subdivision_codes',to_jsonb(p.subdivision_codes),
      'publication_status',p.publication_status,
      'freshness',jsonb_build_object('projection_updated_at',p.updated_at,'source_updated_at',p.source_updated_at)
    ) order by lower(p.course_title), p.course_stable_key) from paged p),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $$;
revoke all on function public.website_edge_course_search_v1(jsonb,integer,integer) from public, anon, authenticated;
grant execute on function public.website_edge_course_search_v1(jsonb,integer,integer) to service_role;
revoke all on function api.website_text_array(jsonb) from public, anon, authenticated;
