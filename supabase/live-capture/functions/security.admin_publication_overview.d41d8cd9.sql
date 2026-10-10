CREATE OR REPLACE FUNCTION security.admin_publication_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'search', 'publishing', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select jsonb_build_object(
    'course_documents',jsonb_build_object(
      'total',count(*),
      'published',count(*) filter(where publication_status='published'),
      'unpublished',count(*) filter(where publication_status='unpublished'),
      'has_fee',count(*) filter(where has_fee),
      'has_intake',count(*) filter(where has_intake),
      'has_english',count(*) filter(where has_english),
      'has_scholarship',count(*) filter(where has_scholarship),
      'latest_generated_at',max(generated_at)
    ),
    'projection',coalesce((select jsonb_build_object(
      'projection_code',ps.projection_code,'generation',ps.generation,'rebuilt_at',ps.rebuilt_at,'row_count',ps.row_count,
      'content_hash',ps.content_hash,'projection_version',ps.metadata->>'projection_version','enrichment_gate',ps.metadata->>'enrichment_gate'
    ) from search.projection_state ps where ps.projection_code='courses'),'{}'::jsonb),
    'channels',coalesce((select jsonb_agg(jsonb_build_object(
      'code',ch.code,'name',ch.name,'audience',ch.audience,'status',ch.status,
      'entity_state_count',(select count(*) from publishing.entity_states es where es.channel_code=ch.code),
      'published_count',(select count(*) from publishing.entity_states es where es.channel_code=ch.code and es.publication_status='published')
    ) order by ch.code) from publishing.channels ch),'[]'::jsonb)
  ) into v_result
  from search.course_documents;
  return v_result;
end
$function$
