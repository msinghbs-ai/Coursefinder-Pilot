-- CF-CHG-20260915-247 Website API v2 (website-search-v2): helpers. Service-only.

create or replace function api.website_v2_label_month(p_label text)
returns int language sql immutable set search_path to 'pg_catalog' as $$
  select m.n from (values (1,'jan'),(2,'feb'),(3,'mar'),(4,'apr'),(5,'may'),(6,'jun'),(7,'jul'),(8,'aug'),(9,'sep'),(10,'oct'),(11,'nov'),(12,'dec')) m(n,k)
  where strpos(lower(coalesce(p_label,'')), m.k) > 0
  order by strpos(lower(p_label), m.k) limit 1
$$;

create or replace function api.website_v2_tuition(p_doc search.course_documents)
returns jsonb language sql stable set search_path to 'pg_catalog','search' as $$
  with pt as (
    select (o->>'amount')::numeric amount, o->>'currency' currency, o->>'basis' basis, nullif(o->>'fee_year','')::int fee_year
    from jsonb_array_elements(coalesce(p_doc.provider_tuition_options,'[]'::jsonb)) o
    where (o->>'amount') ~ '^[0-9]+(\.[0-9]+)?$'
    order by nullif(o->>'fee_year','')::int desc nulls last limit 1
  ), dur as (
    select case lower(coalesce(c.duration_unit,'')) when 'weeks' then c.duration_value when 'months' then c.duration_value*52/12.0 when 'years' then c.duration_value*52 end weeks
    from catalogue.courses c where c.id = p_doc.course_id
  ), t as (
    select
      coalesce(pt.amount, p_doc.regulatory_tuition_amount) amount,
      case when pt.amount is not null then pt.currency else p_doc.regulatory_tuition_currency end currency,
      case when pt.amount is not null then
             case when pt.basis ~* 'total|course' and pt.basis !~* 'annual' then 'course_total'
                  when pt.basis ~* 'session|semester|trimester|unit|credit' then 'per_session'
                  when pt.basis ~* 'indicative' then 'indicative_annual'
                  when pt.basis ~* 'annual|per.?year|yearly' then 'annual'
                  else 'unspecified' end
           when p_doc.regulatory_tuition_amount is not null then 'course_total' end basis,
      case when pt.amount is not null then 'provider_current' when p_doc.regulatory_tuition_amount is not null then 'regulatory_registered' end source,
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

create or replace function api.website_v2_provider_logo(p_provider_id uuid)
returns jsonb language sql stable set search_path to 'pg_catalog','catalogue' as $$
  select jsonb_build_object('storage_path', a.storage_path, 'mime_type', a.mime_type, 'content_hash', a.content_hash,
           'updated_at', coalesce(a.verified_at, a.observed_at), 'source_url', a.source_url,
           'attribution', 'Logo of the provider, from the provider''s own website', 'terms_status', 'management_decision_pending')
  from catalogue.provider_assets a
  where a.provider_id = p_provider_id and a.asset_type = 'logo' and a.status = 'approved' and a.is_primary and a.storage_path is not null
  order by coalesce(a.verified_at, a.observed_at) desc nulls last limit 1
$$;

create or replace function api.website_v2_ranking_summary(p_provider_id uuid)
returns jsonb language sql stable set search_path to 'pg_catalog','ranking' as $$
  with r as (
    select distinct on (s.code) s.code, e.edition_year, o.rank_display, o.rank_low, o.rank_exact
    from ranking.observation_provider_links l
    join ranking.observations o on o.id = l.observation_id
    join ranking.editions e on e.id = o.edition_id and e.status = 'accepted'
    join ranking.systems s on s.id = e.system_id
    where l.provider_id = p_provider_id
    order by s.code, e.edition_year desc, l.is_primary desc nulls last
  )
  select case when count(*) = 0 then null else jsonb_object_agg(r.code, jsonb_build_object(
    'edition_year', r.edition_year, 'rank_display', r.rank_display, 'rank_low', coalesce(r.rank_low, r.rank_exact),
    'terms_status', 'management_decision_pending')) end
  from r
$$;

create or replace function api.website_v2_provider_campuses(p_provider_id uuid)
returns jsonb language sql stable set search_path to 'pg_catalog','catalogue','ref','pipeline','security' as $$
  select coalesce(jsonb_agg(distinct jsonb_build_object('city', security.place_presentable(k.city), 'postcode', k.postcode, 'subdivision_code', s.code,
           'metro_area', rc.metro_area, 'regional_category', rc.category, 'regional_category_name', rc.category_name)), '[]'::jsonb)
  from catalogue.campuses k
  left join ref.subdivisions s on s.id = k.subdivision_id
  left join pipeline.campus_regional_class rc on rc.campus_id = k.id
  where k.provider_id = p_provider_id and nullif(btrim(k.city),'') is not null and coalesce(k.status,'active') <> 'inactive'
$$;

create or replace function api.website_v2_course_item(p_course_id uuid, p_cities text[] default null, p_postcodes text[] default null)
returns jsonb language plpgsql stable set search_path to 'pg_catalog','search','catalogue','ref','pipeline','security','api' as $$
declare d search.course_documents; v jsonb;
begin
  select * into d from search.course_documents where course_id = p_course_id;
  if not found then return null; end if;
  v := jsonb_build_object(
    'course_id', d.course_stable_key,
    'course_code', d.course_code,
    'title', d.course_title,
    'country_code', d.country_code,
    'provider', jsonb_build_object('provider_id', d.provider_stable_key, 'name', security.provider_presentable_name(d.provider_name), 'legal_name', d.provider_name,
                  'university_groups', security.provider_university_groups(d.provider_id),
                  'ranking_summary', api.website_v2_ranking_summary(d.provider_id),
                  'logo', api.website_v2_provider_logo(d.provider_id)),
    'campuses', coalesce((select jsonb_agg(jsonb_build_object('city', security.place_presentable(k.city), 'postcode', k.postcode, 'subdivision_code', s.code,
                   'is_primary', coalesce(cc.is_primary,false), 'metro_area', rc.metro_area, 'regional_category', rc.category, 'regional_category_name', rc.category_name)
                   order by (p_cities is not null and (lower(btrim(k.city)) = any(p_cities) or lower(rc.metro_area) = any(p_cities))) desc,
                            (p_postcodes is not null and btrim(k.postcode) = any(p_postcodes)) desc, cc.is_primary desc nulls last, k.city)
                 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id
                 left join ref.subdivisions s on s.id = k.subdivision_id left join pipeline.campus_regional_class rc on rc.campus_id = k.id
                 where cc.course_id = d.course_id), '[]'::jsonb),
    'study_level', jsonb_build_object('code', d.study_level_code, 'name', (select sl.name from ref.study_levels sl where sl.code = d.study_level_code limit 1)),
    'study_area', jsonb_build_object('code', d.primary_field_code, 'name', d.primary_field_name),
    'duration_months', (select round(c.duration_value * case lower(coalesce(c.duration_unit,'')) when 'weeks' then 12.0/52 when 'months' then 1 when 'years' then 12 end)::int
                        from catalogue.courses c where c.id = d.course_id),
    'delivery_modes', to_jsonb(d.delivery_modes),
    'tuition', api.website_v2_tuition(d),
    'intakes', coalesce((select jsonb_agg(distinct jsonb_build_object('label', i->>'label', 'month', api.website_v2_label_month(i->>'label'), 'year', i->'year',
                  'start_date', i->'start_date', 'application_deadline', i->'application_deadline'))
                 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) i where nullif(i->>'label','') is not null), '[]'::jsonb),
    'entry_requirements', jsonb_build_object(
        'summary', (select 'English: ' || string_agg(
                case e->>'test_code' when 'IELTS' then 'IELTS ' || to_char((e->>'overall_score')::numeric,'FM90.0')
                     when 'PTE' then 'PTE Academic ' || trim(to_char((e->>'overall_score')::numeric,'FM999'))
                     when 'TOEFL_IBT' then 'TOEFL iBT ' || trim(to_char((e->>'overall_score')::numeric,'FM999'))
                     else coalesce(e->>'test_name', e->>'test_code') || ' ' || (e->>'overall_score') end, ', '
                order by case e->>'test_code' when 'IELTS' then 1 when 'PTE' then 2 when 'TOEFL_IBT' then 3 else 4 end)
              from jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) e where (e->>'overall_score') ~ '^[0-9]+(\.[0-9]+)?$'),
        'basis', case when jsonb_array_length(coalesce(d.english_requirement_options,'[]'::jsonb)) > 0 then 'english_only' end),
    'english_requirements', coalesce((select jsonb_agg(jsonb_build_object('test_code', e->>'test_code', 'test_name', e->>'test_name',
                  'min_overall_score', e->'overall_score',
                  'min_band_score', (select min(z.v::numeric) from jsonb_each_text(case when jsonb_typeof(e->'component_scores')='object' then e->'component_scores' else '{}'::jsonb end) z(k2,v) where z.v ~ '^[0-9]+(\.[0-9]+)?$'),
                  'source', case when e->>'notes' ~* 'policy|central|university standard' then 'university_policy' else 'course_page' end))
                 from jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) e), '[]'::jsonb),
    'official_url', d.official_course_url,
    'scholarship_count', jsonb_array_length(coalesce(d.scholarship_options,'[]'::jsonb)),
    'subdivision_codes', to_jsonb(d.subdivision_codes),
    'publication_status', d.publication_status,
    'freshness', jsonb_build_object('projection_updated_at', d.updated_at, 'source_updated_at', d.source_updated_at));
  v := v || jsonb_build_object(
    'campus_city', v->'campuses'->0->'city',
    'campus_metro_area', v->'campuses'->0->'metro_area');
  return v;
end $$;

revoke all on function api.website_v2_label_month(text) from public;
revoke all on function api.website_v2_tuition(search.course_documents) from public;
revoke all on function api.website_v2_provider_logo(uuid) from public;
revoke all on function api.website_v2_ranking_summary(uuid) from public;
revoke all on function api.website_v2_provider_campuses(uuid) from public;
revoke all on function api.website_v2_course_item(uuid, text[], text[]) from public;
