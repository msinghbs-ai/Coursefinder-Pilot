CREATE OR REPLACE FUNCTION public.admin_pipeline_yield(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'PIM Admin role or above required' using errcode = '42501'; end if;
  -- CF-247 P0 mandate 3 Nov 2026 §6: each lane's work, holds and cost beside the stage yield
  return security.pipeline_yield_v1(nullif(p_args->>'hours', '')::int) || jsonb_build_object('lane_status', security.lane_status_v1())
         -- CF-247 mandate 3 Nov 2026 12:04 §5: the per-field backlog, measured by the platform
         || jsonb_build_object('field_backlog', security.field_backlog_v1(nullif(p_args->>'country', '')));
end $function$
