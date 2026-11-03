CREATE OR REPLACE FUNCTION security.admin_job_close_v1(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_j pipeline.admin_jobs%rowtype; v_pid uuid;
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id;
  if v_j.id is null or v_j.state not in ('done', 'failed', 'cancelled') then return; end if;
  if exists (select 1 from pipeline.jobs x where x.job_type = 'layer2_task' and x.payload->>'admin_job_id' = p_id::text) then return; end if;
  v_pid := case when coalesce(jsonb_array_length(v_j.args->'providers'), 0) = 1 then (v_j.args->'providers'->>0)::uuid else null end;
  insert into pipeline.jobs(job_type, domain, status, provider_id, requested_by, started_at, completed_at, attempt_count, payload, result, error_text)
  values ('layer2_task', v_j.kind, case when v_j.state = 'done' then 'completed' else 'failed' end, v_pid, v_j.requested_by, coalesce(v_j.started_at, v_j.created_at), coalesce(v_j.finished_at, now()), 1,
          jsonb_build_object('admin_job_id', v_j.id, 'kind', v_j.kind, 'title', v_j.title, 'scope', v_j.scope, 'reason', v_j.reason, 'args', v_j.args - 'providers', 'providers', coalesce(jsonb_array_length(v_j.args->'providers'), 0),
                             'provider_names', (select jsonb_agg(coalesce(p.display_name, p.canonical_name) order by coalesce(p.display_name, p.canonical_name)) from catalogue.providers p where p.id::text in (select jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)))),
                             'mode', case when v_j.kind = 'qualify_adapters' then 'qualification' else 'apply' end),
          jsonb_build_object('state', v_j.state, 'progress', v_j.progress) || v_j.result,
          case when v_j.state = 'cancelled' then 'cancelled by a person (work done so far kept)' else v_j.error end);
end $function$
