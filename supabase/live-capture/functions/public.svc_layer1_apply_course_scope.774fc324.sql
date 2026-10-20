CREATE OR REPLACE FUNCTION public.svc_layer1_apply_course_scope(p_source_id uuid, p_scope_tag text, p_course_scheme text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'catalogue', 'pipeline', 'ref'
AS $function$
DECLARE
  v_in_scope int := 0;
  v_retired int := 0;
  v_levelled int := 0;
BEGIN
  IF coalesce(auth.role(),'') <> 'service_role' THEN
    RAISE EXCEPTION 'service_role required';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pipeline.ca_course_scope_keys sk
    LEFT JOIN ref.study_levels sl ON sl.code = sk.study_level_code
    WHERE sk.source_id = p_source_id
      AND sk.scope_tag = p_scope_tag
      AND sk.course_scheme = p_course_scheme
      AND sl.id IS NULL
  ) THEN
    RAISE EXCEPTION 'course scope contains unsupported study level';
  END IF;

  UPDATE catalogue.courses c
     SET lifecycle_status = 'inactive',
         publication_status = 'unpublished',
         updated_at = now()
   WHERE c.canonical_source_id = p_source_id
     AND (c.lifecycle_status IS DISTINCT FROM 'inactive'
          OR c.publication_status IS DISTINCT FROM 'unpublished')
     AND EXISTS (
       SELECT 1
       FROM catalogue.course_identifiers ci
       WHERE ci.course_id = c.id
         AND ci.source_id = p_source_id
         AND ci.scheme = p_course_scheme
     )
     AND NOT EXISTS (
       SELECT 1
       FROM catalogue.course_identifiers ci
       JOIN pipeline.ca_course_scope_keys sk
         ON sk.source_id = p_source_id
        AND sk.scope_tag = p_scope_tag
        AND sk.provider_id = ci.provider_id
        AND sk.course_scheme = ci.scheme
        AND sk.identifier = ci.identifier
       WHERE ci.course_id = c.id
         AND ci.source_id = p_source_id
         AND ci.scheme = p_course_scheme
     );
  GET DIAGNOSTICS v_retired = ROW_COUNT;

  UPDATE catalogue.courses c
     SET lifecycle_status = 'active',
         publication_status = 'unpublished',
         study_level_id = sl.id,
         updated_at = now()
    FROM catalogue.course_identifiers ci
    JOIN pipeline.ca_course_scope_keys sk
      ON sk.source_id = p_source_id
     AND sk.scope_tag = p_scope_tag
     AND sk.course_scheme = ci.scheme
     AND sk.provider_id = ci.provider_id
     AND sk.identifier = ci.identifier
    JOIN ref.study_levels sl
      ON sl.code = sk.study_level_code
   WHERE ci.course_id = c.id
     AND ci.source_id = p_source_id
     AND ci.scheme = p_course_scheme
     AND (c.lifecycle_status IS DISTINCT FROM 'active'
          OR c.publication_status IS DISTINCT FROM 'unpublished'
          OR c.study_level_id IS DISTINCT FROM sl.id);

  SELECT count(*)
    INTO v_in_scope
    FROM catalogue.courses c
    JOIN catalogue.course_identifiers ci ON ci.course_id = c.id
    JOIN pipeline.ca_course_scope_keys sk
      ON sk.source_id = p_source_id
     AND sk.scope_tag = p_scope_tag
     AND sk.provider_id = ci.provider_id
     AND sk.course_scheme = ci.scheme
     AND sk.identifier = ci.identifier
   WHERE ci.source_id = p_source_id
     AND ci.scheme = p_course_scheme;

  SELECT count(*)
    INTO v_levelled
    FROM catalogue.courses c
    JOIN catalogue.course_identifiers ci ON ci.course_id = c.id
    JOIN pipeline.ca_course_scope_keys sk
      ON sk.source_id = p_source_id
     AND sk.scope_tag = p_scope_tag
     AND sk.provider_id = ci.provider_id
     AND sk.course_scheme = ci.scheme
     AND sk.identifier = ci.identifier
   WHERE ci.source_id = p_source_id
     AND ci.scheme = p_course_scheme
     AND c.study_level_id IS NOT NULL;

  RETURN jsonb_build_object(
    'scope_tag', p_scope_tag,
    'in_scope', v_in_scope,
    'retired', v_retired,
    'levelled', v_levelled
  );
END
$function$
