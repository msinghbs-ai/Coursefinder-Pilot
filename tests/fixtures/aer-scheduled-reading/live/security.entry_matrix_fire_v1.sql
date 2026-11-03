CREATE OR REPLACE FUNCTION security.entry_matrix_fire_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_att int := 0; v_ref int := 0; v_st int := 0; v_q int := 0; v_due int; v_open int; v_sent int := 0;
begin
  if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;
  v_att := security.entry_matrix_attach_v1();
  -- AER Step B (29 Oct 2026): while PDF tables are read, a parked PDF source of a provider in scope is fetched like any page
  if security.pipeline_num_v1('entry.pdf_enabled', 0) >= 1 then
    update pipeline.entry_matrix_sources f set status = 'found', attempts = 0, error = null, updated_at = now()
     where f.status = 'pdf_step_b' and security.entry_matrix_enabled_v1(f.provider_id);
  end if;
  -- an entry page read longer ago than entry.matrix_refresh_days is fetched again (read again with AI only if it changed)
  update pipeline.entry_matrix_sources f set status = 'found', attempts = 0, updated_at = now()
   where f.status = 'read' and f.read_via <> 'stored'
     and f.read_at < now() - make_interval(days => security.pipeline_num_v1('entry.matrix_refresh_days', 30)::int)
     and security.entry_matrix_enabled_v1(f.provider_id);
  get diagnostics v_ref = row_count;
  v_st := security.entry_matrix_use_stored_v1();
  v_q := security.entry_matrix_enqueue_v1();
  -- 29 Oct 2026: a run whose lease ran out on its last try is closed as failed (the worker stopped without reporting back)
  update pipeline.entry_matrix_runs r set state = 'failed', leased_until = null, updated_at = now(),
         error = left('stopped after ' || r.attempts || ' tries without a reply: ' || coalesce(r.error, 'no error recorded'), 400)
   where r.state = 'leased' and r.leased_until < now() and r.attempts >= security.pipeline_num_v1('entry.matrix_attempts', 3);
  if not security.ai_use_allowed_v1('entry_matrix') then return jsonb_build_object('attached', v_att, 'refetch', v_ref, 'stored', v_st, 'queued', v_q, 'ai', 'stopped'); end if;
  select count(*) into v_due from pipeline.entry_matrix_runs r where (r.state = 'queued' or (r.state = 'leased' and r.leased_until < now()))
     and r.attempts < security.pipeline_num_v1('entry.matrix_attempts', 3);
  v_due := v_due + (select count(*) from pipeline.entry_matrix_sources s where s.status = 'found' and security.entry_matrix_enabled_v1(s.provider_id));
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'entry_ai' and l.created_at > now() - interval '4 minutes'  -- fixed: fire guard
     and not exists (select 1 from net._http_response h where h.id = l.request_id);
  if v_due > 0 and v_open = 0 then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'entry_ai', 'limit', security.pipeline_num_v1('batch.entry_matrix', 4)::int));
    v_sent := 1;
  end if;
  return jsonb_build_object('attached', v_att, 'refetch', v_ref, 'stored', v_st, 'queued', v_q, 'due', v_due, 'sent', v_sent);
end $function$
