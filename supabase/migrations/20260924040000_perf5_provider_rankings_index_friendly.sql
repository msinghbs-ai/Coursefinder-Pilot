-- PERF-5: course detail no longer times out on provider rankings.
-- Deployed UAT (24 Sep 2026, 05:53 and 05:54 UTC) recorded HTTP 500 from
-- admin_read('course_detail'): statement timeouts. course_detail took 7.3 s cold; its
-- rankings part (security.admin_provider_rankings) matched observations with
-- "provider_id = X OR EXISTS(link to X)", which cannot use the existing indexes, so
-- every call scanned all ranking observations twice per ranking system.
-- Fix: find the provider's observation IDs once (direct UNION linked, each via its index),
-- then filter by that set. Generated from the live definition by guarded substitution.
-- Proven before applying: identical output for the 40 providers with the most ranking data.
do $mig$
declare d text; w text := 'where (o.provider_id=p_provider_id or exists(select 1 from ranking.observation_provider_links opl where opl.observation_id=o.id and opl.provider_id=p_provider_id)) and e.system_id=s.id';
begin
  d := pg_get_functiondef('security.admin_provider_rankings(uuid,integer)'::regprocedure);
  if strpos(d,'v_obs := array(')>0 then return; end if;
  if (length(d)-length(replace(d,w,'')))/length(w) <> 2 then raise exception 'where anchor not found twice'; end if;
  d := replace(d,E'  v_result jsonb;\n',E'  v_result jsonb;\n  v_obs uuid[];\n');
  d := replace(d,E'  if coalesce(v_rank,0)<1 then raise exception ''assigned CourseFinder role required'' using errcode=''42501''; end if;\n',
                 E'  if coalesce(v_rank,0)<1 then raise exception ''assigned CourseFinder role required'' using errcode=''42501''; end if;\n  -- Find this provider''s observations once (direct and linked), each via an index.\n  v_obs := array(select o.id from ranking.observations o where o.provider_id=p_provider_id union select opl.observation_id from ranking.observation_provider_links opl where opl.provider_id=p_provider_id);\n');
  d := replace(d, w, 'where o.id = any(v_obs) and e.system_id=s.id');
  if strpos(d,'v_obs := array(')=0 then raise exception 'role anchor not found'; end if;
  execute d;
end $mig$;
