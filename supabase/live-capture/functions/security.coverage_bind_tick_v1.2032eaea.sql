CREATE OR REPLACE FUNCTION security.coverage_bind_tick_v1(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare r record; v jsonb:='[]'::jsonb;
begin
  for r in select provider_id from pipeline.coverage_provider_discovery
            where mapped_at is not null and (bound_at is null or bound_at<mapped_at) order by mapped_at limit greatest(1,least(p_limit,50)) loop
    v:=v||jsonb_build_object('provider_id',r.provider_id,'result',security.coverage_bind_v2(r.provider_id));
  end loop;
  return v;
end $function$
