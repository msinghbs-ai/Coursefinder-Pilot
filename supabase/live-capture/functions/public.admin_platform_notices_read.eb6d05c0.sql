CREATE OR REPLACE FUNCTION public.admin_platform_notices_read(p_layer integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  v := security.platform_notices_v1() || coalesce(security.toolset_sample_notices_v1(), '[]'::jsonb);
  return jsonb_build_object('can_manage', v_rank >= 6, 'generated_at', now(),
    'notices', coalesce((select jsonb_agg(n || jsonb_build_object('acknowledged', a.acknowledged_at is not null and a.acknowledged_at >= (n->>'last_at')::timestamptz,
                                                                   'acknowledged_at', a.acknowledged_at, 'ack_reason', a.reason)
                                          order by case n->>'severity' when 'high' then 0 when 'warning' then 1 else 2 end, (n->>'last_at') desc)
                         from jsonb_array_elements(v) n left join pipeline.platform_notice_acks a on a.notice_key = n->>'key'
                         where p_layer is null or (n->>'layer')::int = p_layer), '[]'::jsonb));
end $function$
