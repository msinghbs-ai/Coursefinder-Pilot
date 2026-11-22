CREATE OR REPLACE FUNCTION security.platform_health_summary_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb:=security.platform_health_state_v1(true); v_at timestamptz; v_ms int; v_lines text[]; e jsonb; v_res bigint;
begin
  select started_at, duration_ms into v_at, v_ms from pipeline.platform_health_runs order by started_at desc limit 1;
  select count(*) into v_res from pipeline.platform_issues where resolved_at>=now()-interval '24 hours';
  v_lines:=array['Platform health: '||upper(v->>'overall')||' - '||(v->'counts'->>'critical')||' critical, '||(v->'counts'->>'warning')||' warning, '||(v->'counts'->>'info')||' info open issue(s); '||v_res||' resolved in the last 24 hours.',
                 'Last health run: '||coalesce(to_char(v_at at time zone 'Asia/Kolkata','DD Mon HH24:MI')||' IST ('||v_ms||' ms)','never')||'.'];
  for e in select x from jsonb_array_elements(v->'issues') x limit 15 loop
    v_lines:=v_lines||('- ['||(e->>'severity')||'] '||(e->>'area')||': '||(e->>'title')||' (since '||to_char((e->>'first_seen')::timestamptz at time zone 'Asia/Kolkata','DD Mon HH24:MI')||' IST'
                       ||case when e->>'acknowledged_at' is not null then ', acknowledged' else '' end||')');
  end loop;
  if jsonb_array_length(v->'issues')=0 then v_lines:=v_lines||'- No open issues.'::text;
  elsif jsonb_array_length(v->'issues')>15 then v_lines:=v_lines||('- ... and '||(jsonb_array_length(v->'issues')-15)||' more.'); end if;
  return jsonb_build_object('generated_at',now(),'overall',v->'overall','counts',v->'counts','resolved_24h',v_res,'last_run_at',v_at,'last_run_ms',v_ms,
    'text',array_to_string(v_lines,E'\n'),'issues',v->'issues','checks',v->'checks');
end $function$
