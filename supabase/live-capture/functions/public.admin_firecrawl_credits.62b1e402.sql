CREATE OR REPLACE FUNCTION public.admin_firecrawl_credits(p_hours integer DEFAULT 24)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return security.firecrawl_credits_report_v1(p_hours) || jsonb_build_object('can_manage', v_rank >= 6);
end $function$
