create or replace function security.admin_course_state_summary(p_course_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, catalogue, publishing, search, auth
as $$
declare
  v_rank integer:=0;
  v_stable_key text;
  v_lifecycle text;
  v_publication text;
  v_verified timestamptz;
  v_page jsonb;
  v_item jsonb;
  v_channels jsonb;
  v_search jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select c.stable_key,c.lifecycle_status,c.publication_status,c.last_verified_at
  into v_stable_key,v_lifecycle,v_publication,v_verified
  from catalogue.courses c
  where c.id=p_course_id;

  if v_stable_key is null then return '{}'::jsonb; end if;

  v_page:=security.admin_catalogue_page('courses_page',jsonb_build_object('query',v_stable_key,'limit',10,'offset',0));
  select i.item into v_item
  from jsonb_array_elements(coalesce(v_page->'items','[]'::jsonb)) i(item)
  where nullif(i.item->>'id','')::uuid=p_course_id
  limit 1;
  v_item:=coalesce(v_item,'{}'::jsonb);

  select coalesce(jsonb_agg(jsonb_build_object(
    'channel_code',es.channel_code,
    'channel_name',ch.name,
    'audience',ch.audience,
    'locale',es.locale,
    'publication_status',es.publication_status,
    'published_at',es.published_at,
    'unpublished_at',es.unpublished_at,
    'completeness_score',es.completeness_score,
    'last_checked_at',es.last_checked_at,
    'updated_at',es.updated_at
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
    'updated_at',d.updated_at,
    'generated_at',d.generated_at,
    'source_updated_at',d.source_updated_at,
    'has_fee',d.has_fee,
    'has_intake',d.has_intake,
    'has_english',d.has_english,
    'has_scholarship',d.has_scholarship,
    'global_projection',case when ps.projection_code is null then null else jsonb_build_object(
      'projection_code',ps.projection_code,
      'generation',ps.generation,
      'row_count',ps.row_count,
      'rebuilt_at',ps.rebuilt_at,
      'content_hash',ps.content_hash,
      'metadata',ps.metadata
    ) end
  )
  into v_search
  from (select 1) x
  left join search.course_documents d on d.course_id=p_course_id
  left join search.projection_state ps on ps.projection_code='courses';

  return jsonb_build_object(
    'canonical',jsonb_build_object(
      'lifecycle_status',v_lifecycle,
      'publication_status',v_publication,
      'last_verified_at',v_verified
    ),
    'canonical_presence',jsonb_build_object(
      'scholarship',coalesce((v_item->>'has_scholarship')::boolean,false)
    ),
    'admin_readiness',jsonb_build_object(
      'score',v_item->'completeness_score_v2',
      'signals',jsonb_build_object(
        'registration',coalesce((v_item->>'has_registration')::boolean,false),
        'structure',coalesce((v_item->>'has_structure')::boolean,false),
        'fee',coalesce((v_item->>'has_fee')::boolean,false),
        'intake',coalesce((v_item->>'has_intake')::boolean,false),
        'english',coalesce((v_item->>'has_english')::boolean,false),
        'description',coalesce((v_item->>'has_description')::boolean,false)
      ),
      'definition','display-only six-signal canonical presence readiness; not truth, approval, freshness or publication'
    ),
    'consumer_channels',v_channels,
    'search',coalesce(v_search,'{}'::jsonb)
  );
end
$$;
