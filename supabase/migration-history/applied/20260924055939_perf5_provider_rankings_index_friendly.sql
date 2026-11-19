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
