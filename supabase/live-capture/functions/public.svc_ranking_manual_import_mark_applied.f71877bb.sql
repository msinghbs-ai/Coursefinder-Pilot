CREATE OR REPLACE FUNCTION public.svc_ranking_manual_import_mark_applied(p_import_id uuid, p_validation_summary jsonb DEFAULT '{}'::jsonb, p_parse_summary jsonb DEFAULT '{}'::jsonb, p_supersede_inline boolean DEFAULT true)
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
$function$
