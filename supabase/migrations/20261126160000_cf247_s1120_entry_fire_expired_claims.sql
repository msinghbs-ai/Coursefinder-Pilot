-- CF-247 s1120 (S1-Build / Integration Controller; Admin #1048 follow-up, 25 Nov 2026): the entry fetch job counts an expired fetch claim as due.
-- Found live (rolled back, 25 Nov 2026 07:30 AEDT, after s1110): job entry-matrix-read (security.entry_matrix_fire_v1, md5 0ab725cb...) starts a
-- worker call only when a run is due or a source is 'found'. The fetch (public.svc_entry_matrix_fetch_next) also takes a source whose claim ran out
-- ('reading', claimed over 20 minutes ago, tries left), but such a source alone never starts a call: CQUniversity's original address, handed back by
-- s1110 as an expired claim so worker v1.0.40 makes the first fetch, still waited at 07:27 AEDT with no other entry work due. The same applies to a
-- claim left by any call that stopped mid-fetch.
-- What changes (live on deploy): the due count also counts those sources, with the same test as the fetch. Nothing else in the function changes.
-- G1: no job (the existing entry-matrix-read). G2: no new value (the 20-minute claim timer is the fetch's own fixed timer; tries are
--   entry.matrix_attempts). G3: no consumer object changed (checked). Locks and cron checked unchanged. No spending limit changed.
-- Replaces: the due count that left expired fetch claims waiting.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.entry_matrix_fire_v1()'::regprocedure)) <> '0ab725cb35f7c7d5d2309f18ec94c119' then
    raise exception 'guard: security.entry_matrix_fire_v1 is not the definition this change was made from';
  end if;
end $g$;
create temp table s1120_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1120_cron on commit drop as select count(*) n from cron.job where active;

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
     and security.entry_matrix_enabled_v1(f.provider_id)
     and not security.aer_schedule_active_v1();  -- CF-247 (3 Nov 2026): while job aer-scheduled-read is on it refreshes due pages in bounded batches
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
  -- CF-247 s1120: a source whose fetch claim ran out (status reading, claimed over 20 minutes ago, tries left) is due too, as the fetch itself takes it
  -- (svc_entry_matrix_fetch_next); before, a claim left by a stopped call waited until other work happened to start a call
  v_due := v_due + (select count(*) from pipeline.entry_matrix_sources s where (s.status = 'found' or (s.status = 'reading' and s.updated_at < now() - interval '20 minutes'  -- fixed: claim timer (svc_entry_matrix_fetch_next)
                       and s.attempts < security.pipeline_num_v1('entry.matrix_attempts', 3))) and security.entry_matrix_enabled_v1(s.provider_id));
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'entry_ai' and l.created_at > now() - interval '4 minutes'  -- fixed: fire guard
     and not exists (select 1 from net._http_response h where h.id = l.request_id);
  if v_due > 0 and v_open = 0 then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'entry_ai', 'limit', security.pipeline_num_v1('batch.entry_matrix', 4)::int));
    v_sent := 1;
  end if;
  return jsonb_build_object('attached', v_att, 'refetch', v_ref, 'stored', v_st, 'queued', v_q, 'due', v_due, 'sent', v_sent);
end $function$;


do $c$
declare v_api jsonb;
begin
  if pg_get_functiondef('security.entry_matrix_fire_v1()'::regprocedure) not like '%s.status = ''reading'' and s.updated_at < now() - interval ''20 minutes''%' then raise exception 'post-check: the due count does not take expired claims'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1120_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1120_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
