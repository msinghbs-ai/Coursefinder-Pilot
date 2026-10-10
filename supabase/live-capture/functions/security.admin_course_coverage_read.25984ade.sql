CREATE OR REPLACE FUNCTION security.admin_course_coverage_read(p_operation text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security', 'auth'
AS $function$
declare v_tier text:=nullif(p_args->>'tier',''); v jsonb;
  v_cstate text:=nullif(p_args->>'completeness_state','');
  -- Decision 213: country (ISO code) and provider filters
  v_country text:=upper(nullif(btrim(coalesce(p_args->>'country','')),''));
  v_provider uuid:=nullif(p_args->>'provider','')::uuid;
  c_states constant text[]:=array['present','source_null','not_applicable','zero','suppressed','not_yet_enriched','stale','ambiguous','rejected'];
  c_attrs constant text[]:=array['official_url','provider_tuition','english','intakes','registered_tuition','duration','campus'];
begin
  if auth.uid() is null or security.current_role_rank()<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  if p_operation='course_coverage_providers' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',q.provider_id,'name',q.name,'country',q.country_code,'courses',q.n) order by q.n desc, q.name)
      from (select x.provider_id, max(coalesce(p.display_name,p.canonical_name)) name, max(x.country_code) country_code, count(*) n
              from pipeline.course_completeness x join catalogue.providers p on p.id=x.provider_id
             where (v_country is null or x.country_code=v_country)
               and (coalesce(p_args->>'query','')='' or coalesce(p.display_name,p.canonical_name) ilike '%'||(p_args->>'query')||'%' or p.canonical_name ilike '%'||(p_args->>'query')||'%')
             group by x.provider_id order by count(*) desc limit 30) q),'[]'::jsonb);
  elsif p_operation='course_coverage' then
    with a as (select * from pipeline.course_attribute_coverage x
                where (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider)),
         cc as (select * from pipeline.course_completeness x
                where (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider))
    select jsonb_build_object(
      'computed_at',(select max(computed_at) from pipeline.course_attribute_coverage),
      'courses',(select count(distinct course_id) from a),
      'providers',(select count(distinct provider_id) from a),
      'tier',v_tier,'country',v_country,
      'provider',case when v_provider is null then null else (select jsonb_build_object('id',p.id,'name',coalesce(p.display_name,p.canonical_name)) from catalogue.providers p where p.id=v_provider) end,
      'countries',(select jsonb_agg(jsonb_build_object('code',country_code,'courses',n,'providers',pn) order by n desc) from (
          select country_code, count(*) n, count(distinct provider_id) pn from pipeline.course_completeness group by 1) k),
      'attributes',(select jsonb_agg(jsonb_build_object('attribute',attribute,'states',states,'total',total) order by ord) from (
          select attribute, jsonb_object_agg(state,n) states, sum(n) total, min(array_position(c_attrs,attribute)) ord
            from (select attribute,state,count(*) n from a group by 1,2) s group by attribute) x),
      'tiers',(select jsonb_agg(jsonb_build_object('tier',tier,'courses',n,'providers',p) order by tier) from (
          select tier, count(distinct course_id) n, count(distinct provider_id) p from pipeline.course_attribute_coverage
           where (v_country is null or country_code=v_country) group by tier) t),
      -- daily history has no provider dimension: no attribute trend for one provider
      'trend',case when v_provider is null then (select jsonb_agg(jsonb_build_object('date',snapshot_date,'attribute',attribute,'admitted',adm,'total',tot) order by snapshot_date, attribute) from (
          select snapshot_date, attribute, sum(courses) filter (where state='admitted') adm, sum(courses) tot
            from pipeline.course_coverage_daily_by_country where snapshot_date>=current_date-60 and (v_tier is null or tier=v_tier) and (v_country is null or country_code=v_country) group by 1,2) d) end,
      'completeness_states',(select jsonb_agg(jsonb_build_object('attribute',attribute,'states',
            (select jsonb_object_agg(k, coalesce((cs->>k)::int,0)) from unnest(c_states) k),'total',total) order by ord) from (
          select attribute, jsonb_object_agg(cstate,n) cs, sum(n) total, min(array_position(c_attrs,attribute)) ord
            from (select attribute, security.coverage_completeness_state(state) cstate, sum(n) n from (
                    select attribute,state,count(*) n from a group by 1,2) s0
                  group by 1,2) s group by attribute) x),
      -- Who supplied intakes, English and fees (adapter, central page, reader, hand-entered, other, or missing); snapshot rebuilt hourly.
      'field_sources',(select jsonb_agg(jsonb_build_object('field',z.field,'source',z.src,'courses',z.n) order by z.field,z.src) from (
          select 'intakes' field, s.intakes_src src, count(*) n from pipeline.course_field_source s where (v_tier is null or s.tier=v_tier) and (v_country is null or s.country_code=v_country) and (v_provider is null or s.provider_id=v_provider) group by 2
          union all select 'english', s.english_src, count(*) from pipeline.course_field_source s where (v_tier is null or s.tier=v_tier) and (v_country is null or s.country_code=v_country) and (v_provider is null or s.provider_id=v_provider) group by 2
          union all select 'fee', s.fee_src, count(*) from pipeline.course_field_source s where (v_tier is null or s.tier=v_tier) and (v_country is null or s.country_code=v_country) and (v_provider is null or s.provider_id=v_provider) group by 2) z),
      'field_sources_at',(select max(computed_at) from pipeline.course_field_source),
      'completeness_state_map',(select jsonb_object_agg(s, security.coverage_completeness_state(s))
          from unnest(array['admitted','candidate','in_review','awaiting_l3','not_on_page','blocked','page_found','site_known','no_website','missing_l1']) s),
      'completeness',(select jsonb_build_object(
            'computed_at',max(cc.computed_at),
            'courses',count(*),
            'attributes',max(cc.attributes),
            'completeness',round(avg(cc.completeness),1),
            'accounted_pct',round(avg(cc.accounted_pct),1),
            'fully_complete',count(*) filter (where cc.admitted=cc.attributes),
            'by_admitted',(select jsonb_agg(jsonb_build_object('admitted',b.admitted,'courses',b.n) order by b.admitted) from (
                select c2.admitted, count(*) n from cc c2 group by 1) b),
            'trend',case when v_tier is null then (select jsonb_agg(jsonb_build_object('date',d.snapshot_date,'courses',d.courses,'completeness',d.completeness,
                        'accounted_pct',d.accounted_pct,'fully_complete',d.fully_complete,'computed_at',d.computed_at) order by d.snapshot_date)
                      from pipeline.completeness_daily d where d.snapshot_date>=current_date-60
                       and case when v_provider is not null then d.scope='provider' and d.scope_id=v_provider
                                when v_country is not null then d.scope='country:'||v_country
                                else d.scope='platform' end) end)
          from cc)
    ) into v;
    return v;
  elsif p_operation='course_coverage_courses' then
    if v_cstate is not null and not (v_cstate = any(c_states)) then raise exception 'unknown completeness state %', v_cstate; end if;
    select jsonb_build_object('total',(select count(*) from pipeline.course_attribute_coverage x where x.attribute=p_args->>'attribute'
                 and (case when v_cstate is not null then security.coverage_completeness_state(x.state)=v_cstate else x.state=p_args->>'state' end)
                 and (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider)),
      'items',coalesce((select jsonb_agg(r) from (
        select x.course_id, c.canonical_title title, coalesce(p.display_name,p.canonical_name) provider_name, x.tier, x.country_code,
               (select min(registration_code) from catalogue.course_registrations cr where cr.course_id=x.course_id and lower(cr.scheme)='cricos') cricos,
               x.state, security.coverage_completeness_state(x.state) completeness_state, cc.completeness, cc.accounted_pct
          from pipeline.course_attribute_coverage x join catalogue.courses c on c.id=x.course_id join catalogue.providers p on p.id=x.provider_id
          left join pipeline.course_completeness cc on cc.course_id=x.course_id
         where x.attribute=p_args->>'attribute'
           and (case when v_cstate is not null then security.coverage_completeness_state(x.state)=v_cstate else x.state=p_args->>'state' end)
           and (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider)
         order by coalesce(p.display_name,p.canonical_name), c.canonical_title
         limit least(coalesce(nullif(p_args->>'limit','')::int,50),200) offset greatest(coalesce(nullif(p_args->>'offset','')::int,0),0)) r),'[]'::jsonb))
      into v;
    return v;
  end if;
  raise exception 'unknown coverage operation %', p_operation;
end $function$
