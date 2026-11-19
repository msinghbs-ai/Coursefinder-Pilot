-- CF-222: keep governed Evidence, purge superseded QS operational import rows,
-- and keep rejected history out of the active Ranking import workflow.

DELETE FROM ranking.manual_imports mi
USING ranking.systems s
WHERE mi.system_id=s.id
  AND s.code='qs_wur'
  AND mi.status='rejected';

CREATE OR REPLACE FUNCTION security.admin_ranking_imports_read(p_args jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'security', 'ranking', 'pipeline', 'auth'
AS $function$
DECLARE
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_include_history boolean:=coalesce((p_args->>'include_history')::boolean,false);
BEGIN
  IF auth.uid() IS NULL THEN raise exception 'authentication required' using errcode='42501'; END IF;
  SELECT security.current_role_rank() INTO v_rank;
  IF coalesce(v_rank,0)<4 THEN raise exception 'pipeline_operator role required' using errcode='42501'; END IF;
  RETURN (
    SELECT jsonb_build_object(
      'total',(SELECT count(*) FROM ranking.manual_imports mi WHERE v_include_history OR mi.status<>'rejected'),
      'limit',v_limit,'offset',v_offset,
      'items',coalesce((
        SELECT jsonb_agg(to_jsonb(x) ORDER BY x.updated_at DESC,x.uploaded_at DESC)
        FROM (
          SELECT mi.id,s.code system_code,mi.edition_year,mi.publisher_name,mi.source_url,mi.methodology_url,
            mi.licensing_note,mi.revision_note,mi.original_filename,mi.mime_type,mi.byte_size,mi.content_hash,
            mi.storage_path,mi.evidence_artifact_id,mi.status,mi.validation_summary,mi.parse_summary,
            mi.uploaded_at,mi.updated_at,
            coalesce((
              SELECT coalesce(j.result->'detected_scope',j.payload->'detected_scope','[]'::jsonb)
              FROM pipeline.jobs j
              WHERE j.domain='ranking'
                AND j.job_type='ranking_import_acquire'
                AND j.payload->>'import_id'=mi.id::text
              ORDER BY j.created_at DESC LIMIT 1
            ),'[]'::jsonb) detected_scope,
            (SELECT count(*) FROM ranking.manual_imports mi2 WHERE mi2.system_id=mi.system_id AND mi2.edition_year=mi.edition_year AND (v_include_history OR mi2.status<>'rejected'))::integer logical_revision_count,
            (SELECT jsonb_build_object('id',j.id,'job_type',j.job_type,'status',j.status,'created_at',j.created_at,
               'started_at',j.started_at,'completed_at',j.completed_at,'error_text',j.error_text)
             FROM pipeline.jobs j
             WHERE j.domain='ranking' AND j.payload->>'import_id'=mi.id::text
             ORDER BY j.created_at DESC LIMIT 1) latest_job,
            (SELECT count(*) FROM pipeline.jobs j WHERE j.domain='ranking' AND j.payload->>'import_id'=mi.id::text)::integer job_count
          FROM ranking.manual_imports mi JOIN ranking.systems s ON s.id=mi.system_id
          WHERE v_include_history OR mi.status<>'rejected'
          ORDER BY mi.updated_at DESC,mi.uploaded_at DESC
          LIMIT v_limit OFFSET v_offset
        ) x
      ),'[]'::jsonb)
    )
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.svc_ranking_manual_import_mark_applied(
  p_import_id uuid,
  p_validation_summary jsonb DEFAULT '{}'::jsonb,
  p_parse_summary jsonb DEFAULT '{}'::jsonb,
  p_supersede_inline boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'ranking'
AS $function$
DECLARE
  v_system_id uuid;
  v_year integer;
  v_purged integer:=0;
BEGIN
  IF current_user NOT IN ('service_role','postgres') THEN
    raise exception 'service role required' using errcode='42501';
  END IF;
  SELECT system_id,edition_year INTO v_system_id,v_year FROM ranking.manual_imports WHERE id=p_import_id;
  IF v_system_id IS NULL THEN raise exception 'ranking import not found' using errcode='P0002'; END IF;

  UPDATE ranking.manual_imports
  SET status='applied', validation_summary=coalesce(p_validation_summary,'{}'::jsonb), parse_summary=coalesce(p_parse_summary,'{}'::jsonb), updated_at=now()
  WHERE id=p_import_id;

  IF p_supersede_inline THEN
    DELETE FROM ranking.manual_imports
    WHERE system_id=v_system_id
      AND edition_year=v_year
      AND id<>p_import_id
      AND storage_path LIKE 'inline://%';
    GET DIAGNOSTICS v_purged=ROW_COUNT;
  END IF;

  RETURN jsonb_build_object('ok',true,'import_id',p_import_id,'superseded_inline',v_purged,'purged_operational_rows',v_purged);
END
$function$;
