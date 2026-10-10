CREATE OR REPLACE FUNCTION security.admin_data_quality_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth'
AS $function$
declare v_rank int:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  if p_operation='data_quality_overview' then return security.data_quality_overview_cached(p_args); end if;
  if p_operation='data_quality_exceptions' then return security.data_quality_exceptions_impl(p_args); end if;
  if p_operation='data_quality_quarantine' then
    if v_rank<3 then raise exception 'curator role required for quarantine details' using errcode='42501'; end if;
    return security.data_quality_quarantine_impl(p_args);
  end if;
  raise exception 'unsupported data quality operation: %',p_operation using errcode='22023';
end
$function$
