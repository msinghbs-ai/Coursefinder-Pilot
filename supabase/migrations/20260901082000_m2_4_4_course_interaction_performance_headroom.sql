-- CF-CHG-20260830-048
-- M2.4.4 final integration performance correction.
-- Keep the existing complex-filter Course page as fallback.
-- Add a page-first fast path for the normal unfiltered Course browse and remove
-- the general catalogue-page roundtrip from per-Course state summary.

create index if not exists courses_canonical_title_lower_id_idx
  on catalogue.courses ((lower(canonical_title)), id);

create or replace function security.admin_course_page_unfiltered_fast(
  p_args jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','catalogue','ref','scholarship','search','public','auth'
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_total bigint:=0;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select count(*) into v_total from catalogue.courses;

  with paged as (
    select
      c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,
      c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
      c.duration_value,c.description,c.delivery_mode canonical_delivery_mode,
      coalesce(p.display_name,p.canonical_name) provider_name,
      co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
      sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    left join ref.study_levels sl on sl.id=c.study_level_id
    left join ref.fields_of_study fos on fos.id=c.primary_field_id
    order by lower(c.canonical_title),c.id
    limit v_limit offset v_offset
  ), enriched as (
    select
      pg.id,pg.stable_key,pg.canonical_title,pg.display_title,pg.course_code,pg.course_url,
      pg.lifecycle_status,pg.publication_status,pg.last_verified_at,pg.created_at,pg.updated_at,pg.provider_id,
      pg.provider_name,pg.country_code,pg.country_name,pg.currency_code,pg.level_code,pg.level_name,pg.field_code,pg.field_of_study,
      case when dm.mode_count=1 then dm.single_mode when dm.mode_count>1 then dm.mode_count::text||' modes' else pg.canonical_delivery_mode end delivery_mode,
      fee.amount fee_amount,fee.currency_code::text fee_currency,
      sig.has_registration,sig.has_structure,sig.has_fee,sig.has_intake,sig.has_english,sig.has_description,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score_v2,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score,
      sch.has_scholarship,lnk.has_link,coalesce(geo.region_count,0)>0 has_state,
      coalesce(geo.campus_count,0) campus_count,
      case when geo.region_count=1 then geo.single_code else null end subdivision_code,
      case when geo.region_count=1 then geo.single_name when geo.region_count>1 then geo.region_count::text||' regions' else null end subdivision_name,
      coalesce(geo.region_count,0) region_count,
      (d.course_id is not null) search_projected,d.publication_status search_projection_status,d.completeness_score search_projection_completeness,
      d.projection_version search_projection_version,d.catalogue_generation search_catalogue_generation,d.updated_at search_projection_updated_at,
      d.generated_at search_projection_generated_at,d.has_fee search_has_fee,d.has_intake search_has_intake,d.has_english search_has_english,d.has_scholarship search_has_scholarship
    from paged pg
    left join search.course_documents d on d.course_id=pg.id
    left join lateral (
      select cf.amount,cf.currency_code
      from catalogue.course_fees cf
      where cf.course_id=pg.id
        and cf.fee_type='tuition'
        and cf.basis='registered_total_course'
        and coalesce(cf.status,'active')='active'
      order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc
      limit 1
    ) fee on true
    cross join lateral (
      select
        exists(select 1 from catalogue.course_registrations r where r.course_id=pg.id) has_registration,
        (pg.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=pg.id)) has_structure,
        exists(select 1 from catalogue.course_fees cf where cf.course_id=pg.id and coalesce(cf.status,'active')='active') has_fee,
        exists(select 1 from catalogue.course_intakes ci where ci.course_id=pg.id and coalesce(ci.status,'active')='active') has_intake,
        exists(select 1 from catalogue.course_english_requirements er where er.course_id=pg.id and coalesce(er.status,'active')='active') has_english,
        (pg.description is not null and length(trim(pg.description))>0) has_description
    ) sig
    cross join lateral (
      select exists(
        select 1 from scholarship.scopes ss
        where coalesce(ss.include_exclude,'include')='include'
          and (ss.course_id=pg.id or (ss.scope_type='provider' and ss.provider_id=pg.provider_id))
      ) has_scholarship
    ) sch
    cross join lateral (
      select exists(select 1 from catalogue.course_links l where l.course_id=pg.id and l.status='active') has_link
    ) lnk
    left join lateral (
      select count(distinct cc.campus_id)::int campus_count,
             count(distinct sd.id)::int region_count,
             min(sd.code) single_code,min(sd.name) single_name
      from catalogue.course_campuses cc
      join catalogue.campuses ca on ca.id=cc.campus_id
      left join ref.subdivisions sd on sd.id=ca.subdivision_id
      where cc.course_id=pg.id
    ) geo on true
    left join lateral (
      select count(distinct cc.delivery_mode)::int mode_count,min(cc.delivery_mode) single_mode
      from catalogue.course_campuses cc
      where cc.course_id=pg.id and cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
    ) dm on true
  )
  select jsonb_build_object(
    'items',coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb),
    'total',v_total,'limit',v_limit,'offset',v_offset,
    'sort','course','direction','asc',
    'execution_profile','page_first_unfiltered_v1'
  ) into v_result
  from enriched e;

  return v_result;
end $$;

revoke all on function security.admin_course_page_unfiltered_fast(jsonb) from public,anon;
grant execute on function security.admin_course_page_unfiltered_fast(jsonb) to authenticated,service_role;

create or replace function security.admin_course_page_fast(
  p_args jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','catalogue','public','auth'
as $$
declare
  v_q text:=nullif(trim(coalesce(p_args->>'query','')),'');
  v_provider_id uuid;
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'course'));
  v_dir text:=lower(coalesce(nullif(p_args->>'direction',''),'asc'));
  v_simple boolean;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  v_simple :=
    v_q is null
    and nullif(p_args->>'country_code','') is null
    and nullif(p_args->>'subdivision_code','') is null
    and nullif(p_args->>'provider_id','') is null
    and nullif(p_args->>'level_code','') is null
    and nullif(p_args->>'field_code','') is null
    and nullif(p_args->>'delivery_mode','') is null
    and nullif(p_args->>'lifecycle_status','') is null
    and nullif(p_args->>'publication_status','') is null
    and nullif(p_args->>'has_fee','') is null
    and nullif(p_args->>'has_intake','') is null
    and nullif(p_args->>'has_english','') is null
    and nullif(p_args->>'has_scholarship','') is null
    and nullif(p_args->>'has_state','') is null
    and nullif(p_args->>'has_link','') is null
    and nullif(p_args->>'min_completeness','') is null
    and nullif(p_args->>'freshness','') is null
    and v_sort='course' and v_dir='asc';

  if v_simple then
    return security.admin_course_page_unfiltered_fast(p_args);
  end if;

  if v_q is not null and v_q ~* '^course:' then
    select c.provider_id into v_provider_id
    from catalogue.courses c where c.stable_key=v_q limit 1;
  elsif v_q is not null and v_q ~ '^[0-9]{6}[A-Za-z]$' then
    select c.provider_id into v_provider_id
    from catalogue.courses c where upper(c.course_code)=upper(v_q) limit 1;
  end if;

  if v_provider_id is not null and nullif(p_args->>'provider_id','') is null then
    return security.admin_course_page_fast_base(p_args||jsonb_build_object('provider_id',v_provider_id::text));
  end if;

  return security.admin_course_page_fast_base(p_args);
end $$;

revoke all on function security.admin_course_page_fast(jsonb) from public,anon;
grant execute on function security.admin_course_page_fast(jsonb) to authenticated,service_role;

create or replace function security.admin_course_state_summary(p_course_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','catalogue','publishing','search','scholarship','auth'
as $$
declare
  v_rank integer:=0;
  v_stable_key text;
  v_lifecycle text;
  v_publication text;
  v_verified timestamptz;
  v_has_registration boolean:=false;
  v_has_structure boolean:=false;
  v_has_fee boolean:=false;
  v_has_intake boolean:=false;
  v_has_english boolean:=false;
  v_has_description boolean:=false;
  v_has_scholarship boolean:=false;
  v_score numeric:=0;
  v_channels jsonb;
  v_search jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select c.stable_key,c.lifecycle_status,c.publication_status,c.last_verified_at,
         exists(select 1 from catalogue.course_registrations r where r.course_id=c.id),
         (c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.id)),
         exists(select 1 from catalogue.course_fees cf where cf.course_id=c.id and coalesce(cf.status,'active')='active'),
         exists(select 1 from catalogue.course_intakes ci where ci.course_id=c.id and coalesce(ci.status,'active')='active'),
         exists(select 1 from catalogue.course_english_requirements er where er.course_id=c.id and coalesce(er.status,'active')='active'),
         (c.description is not null and length(trim(c.description))>0),
         exists(
           select 1 from scholarship.scopes ss
           where coalesce(ss.include_exclude,'include')='include'
             and (ss.course_id=c.id or (ss.scope_type='provider' and ss.provider_id=c.provider_id))
         )
  into v_stable_key,v_lifecycle,v_publication,v_verified,
       v_has_registration,v_has_structure,v_has_fee,v_has_intake,v_has_english,v_has_description,v_has_scholarship
  from catalogue.courses c
  where c.id=p_course_id;

  if v_stable_key is null then return '{}'::jsonb; end if;

  v_score:=round(((v_has_registration::int+v_has_structure::int+v_has_fee::int+v_has_intake::int+v_has_english::int+v_has_description::int)*100.0/6.0)::numeric,2);

  select coalesce(jsonb_agg(jsonb_build_object(
    'channel_code',es.channel_code,'channel_name',ch.name,'audience',ch.audience,
    'locale',es.locale,'publication_status',es.publication_status,
    'published_at',es.published_at,'unpublished_at',es.unpublished_at,
    'completeness_score',es.completeness_score,'last_checked_at',es.last_checked_at,'updated_at',es.updated_at
  ) order by es.channel_code,es.locale),'[]'::jsonb)
  into v_channels
  from publishing.entity_states es
  left join publishing.channels ch on ch.code=es.channel_code
  where es.entity_id=p_course_id;

  select jsonb_build_object(
    'projected',d.course_id is not null,
    'publication_status',d.publication_status,
    'completeness_score',d.completeness_score,
    'projection_version',d.projection_version,
    'catalogue_generation',d.catalogue_generation,
    'updated_at',d.updated_at,'generated_at',d.generated_at,'source_updated_at',d.source_updated_at,
    'has_fee',d.has_fee,'has_intake',d.has_intake,'has_english',d.has_english,'has_scholarship',d.has_scholarship,
    'global_projection',case when ps.projection_code is null then null else jsonb_build_object(
      'projection_code',ps.projection_code,'generation',ps.generation,'row_count',ps.row_count,
      'rebuilt_at',ps.rebuilt_at,'content_hash',ps.content_hash,'metadata',ps.metadata
    ) end
  )
  into v_search
  from (select 1) x
  left join search.course_documents d on d.course_id=p_course_id
  left join search.projection_state ps on ps.projection_code='courses';

  return jsonb_build_object(
    'canonical',jsonb_build_object(
      'lifecycle_status',v_lifecycle,'publication_status',v_publication,'last_verified_at',v_verified
    ),
    'canonical_presence',jsonb_build_object('scholarship',v_has_scholarship),
    'admin_readiness',jsonb_build_object(
      'score',v_score,
      'signals',jsonb_build_object(
        'registration',v_has_registration,'structure',v_has_structure,'fee',v_has_fee,
        'intake',v_has_intake,'english',v_has_english,'description',v_has_description
      ),
      'definition','display-only six-signal canonical presence readiness; not truth, approval, freshness or publication'
    ),
    'consumer_channels',v_channels,
    'search',coalesce(v_search,'{}'::jsonb)
  );
end $$;

revoke all on function security.admin_course_state_summary(uuid) from public,anon;
grant execute on function security.admin_course_state_summary(uuid) to authenticated,service_role;
