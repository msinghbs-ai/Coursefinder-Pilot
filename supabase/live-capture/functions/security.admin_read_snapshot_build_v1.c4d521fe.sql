CREATE OR REPLACE FUNCTION security.admin_read_snapshot_build_v1(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_key = 'platform_notices' then
    return jsonb_build_object('notices', coalesce(security.platform_notices_v1(), '[]'::jsonb), 'samples', coalesce(security.toolset_sample_notices_v1(), '[]'::jsonb));
  elsif p_key = 'scholarship_publishability' then
    return jsonb_build_object('rows', coalesce((select jsonb_agg(jsonb_build_object('scholarship_id', x.scholarship_id, 'publishable', x.publishable, 'missing', to_jsonb(x.missing)))
                                                  from security.scholarship_publishability_v1() x), '[]'::jsonb));
  elsif p_key = 'field_coverage' then
    -- the queries of public.admin_field_coverage('overview') for every country and no provider filter (the screen filters by country)
    return jsonb_build_object(
      'courses_by_country', (select coalesce(jsonb_agg(jsonb_build_object('country', x.country_code, 'field', x.attribute, 'total', x.total, 'filled', x.filled,
                                                                        'in_queue', x.in_queue, 'not_stated', x.not_stated, 'in_review', x.in_review)), '[]'::jsonb)
                               from (select a.country_code, a.attribute, count(*) total, count(*) filter (where a.state = 'admitted') filled,
                                            count(*) filter (where a.state = 'in_queue') in_queue, count(*) filter (where a.state = 'not_on_page') not_stated,
                                            count(*) filter (where a.state in ('in_review', 'candidate', 'awaiting_l3')) in_review
                                       from pipeline.course_attribute_coverage a group by 1, 2) x),
      'providers_by_country', (select coalesce(jsonb_agg(jsonb_build_object('country', z.cc, 'field', z.field, 'total', z.total, 'filled', z.filled)), '[]'::jsonb)
                                 from (select p.cc, f.field, count(*) total, count(*) filter (where f.has) filled
                                         from (select p.*, security.coverage_country(p.id) cc from catalogue.providers p
                                                where coalesce(p.lifecycle_status, 'active') = 'active' and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')) p
                                         cross join lateral (values
                                           ('p_website', nullif(btrim(p.website), '') is not null),
                                           ('p_address', nullif(btrim(p.address_line1), '') is not null),
                                           ('p_campuses', exists (select 1 from catalogue.campuses k where k.provider_id = p.id)),
                                           ('p_type', p.provider_type_id is not null),
                                           ('p_international', p.enrols_international is not null),
                                           ('p_logo', nullif(btrim(p.logo_url), '') is not null or exists (select 1 from catalogue.provider_assets a where a.provider_id = p.id and a.asset_type = 'logo')),
                                           ('p_contact', nullif(btrim(p.phone), '') is not null or nullif(btrim(p.email), '') is not null),
                                           ('p_scholarships', exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active')),
                                           ('p_description', nullif(btrim(p.description), '') is not null)) f(field, has)
                                        group by 1, 2) z),
      'computed_at', (select max(computed_at) from pipeline.course_attribute_coverage),
      'ai_spent_today_usd', (select x.spent from security.ai_spend_today_v1() x where x.use = 'enrich_fields'));
  end if;
  raise exception 'unknown snapshot %', p_key using errcode = '22023';
end $function$
