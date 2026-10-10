CREATE OR REPLACE FUNCTION security.admin_course_state_summary(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'publishing', 'search', 'scholarship', 'auth'
AS $function$
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
end $function$
