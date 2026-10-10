CREATE OR REPLACE FUNCTION security.admin_layer_status_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth'
AS $function$
declare v_rank integer; v_payload jsonb; v_at timestamptz;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 select payload, computed_at into v_payload, v_at from security.admin_summary_snapshots
 where snapshot_key='layer_status_summary' and computed_at > now() - interval '10 minutes';
 if v_payload is not null then
   return v_payload || jsonb_build_object('snapshot_at', v_at, 'snapshot_source', 'snapshot');
 end if;
 return security.admin_layer_status_summary_compute() || jsonb_build_object('snapshot_at', now(), 'snapshot_source', 'live');
end $function$
