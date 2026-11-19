-- CF-247 Decision 254 (6 Oct 2026, Platform Admin 13:27 "Through to C", 13:55 "Option 1"). Job system Phase C: the four
-- long-running actions that had their own progress panels become tasks worked by the same dispatcher, started from the
-- same button, listed in the same Task manager and closed into the same Jobs history:
--   reread_pages        Read pages again for one or many universities (public.admin_university_reread 'queue')
--   firecrawl_run       a Firecrawl run, read_page or find_page (public.admin_firecrawl_write 'start')
--   adapter_apply       an adapter applied to a university's stored pages (public.admin_uni_adapter_write 'apply')
--   central_page_read   a central English or key-dates page attached or read again (public.admin_provider_central_page)
-- These are watcher tasks: starting one performs the existing admin action as the person pressing the button (its own
-- checks and log entry are unchanged), then the dispatcher watches the underlying work a slice a minute and writes the
-- progress to the task row. Cancel stops the underlying work where it can be stopped (a re-read request still waiting
-- or sending, a Firecrawl run) and otherwise stops the watching. Pause and resume map to a Firecrawl run's stop and
-- continue, and are refused for the other watchers (they can only be cancelled). A watcher that sees no progress for a
-- while finishes with a note saying how far the work got, so a task never waits for ever on a reader that moved on.
-- EXCEPTION TO THE MIGRATION RULES, granted by the Platform Admin at 13:55 ("Option 1"): the check constraint on
-- admin_jobs.kind from migration 1720 can only be widened by removing it and adding it again, so this file contains that
-- one constraint removal. No table, row or function is removed. Snippet patches are md5-guarded, each snippet found
-- exactly once. No text value in this file contains a semicolon: {sc} becomes chr(59).

alter table pipeline.admin_jobs drop constraint admin_jobs_kind_check;
alter table pipeline.admin_jobs add constraint admin_jobs_kind_check
  check (kind in ('qualify_adapters', 'admit_qualified', 'reread_pages', 'firecrawl_run', 'adapter_apply', 'central_page_read'));

-- One look at the underlying work of a watcher task. Writes progress and result to the task row, returns true when finished.
create or replace function security.admin_job_watch_v1(p_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $f$
declare v_j pipeline.admin_jobs%rowtype; v_done int := 0; v_total int := 0; v_fin boolean := false; v_note text := null; v_phase text := null;
        v_last_done int; v_last_at timestamptz; v_stall interval; v_ids uuid[]; r record;
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;
  v_last_done := coalesce((v_j.cursor->>'last_done')::int, -1);
  v_last_at := coalesce((v_j.cursor->>'last_change_at')::timestamptz, v_j.started_at, v_j.created_at);
  if v_j.kind = 'reread_pages' then
    v_stall := interval '30 minutes';
    select * into r from pipeline.university_reread_requests q where q.id = (v_j.args->>'request_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the re-read request is gone';
    elsif r.status = 'cancelled' then v_fin := true; v_note := 'cancelled before every university was sent (' || cardinality(r.done_ids) || ' of ' || cardinality(r.provider_ids) || ' sent)';
    elsif r.status = 'failed' then v_fin := true; v_note := 'the request failed: ' || coalesce(r.last_error, 'no detail');
    elsif r.status in ('waiting', 'sending') then
      v_phase := 'sending'; v_done := cardinality(r.done_ids); v_total := cardinality(r.provider_ids);
    else
      v_phase := 'reading'; v_total := coalesce(r.pages, 0);
      v_ids := r.provider_ids;
      select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = any (v_ids) and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
      if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) sent back and read again'; end if;
    end if;
  elsif v_j.kind = 'firecrawl_run' then
    select * into r from pipeline.firecrawl_runs x where x.id = (v_j.args->>'run_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the run is gone';
    else
      v_done := coalesce(r.done, 0); v_total := coalesce(r.items, 0);
      if r.status <> 'running' then v_fin := true; v_note := 'run ' || r.status || ': ' || v_done || ' of ' || v_total || ' done, ' || coalesce(r.credits_used, 0) || ' credits'; end if;
    end if;
  elsif v_j.kind = 'adapter_apply' then
    v_stall := interval '20 minutes';
    v_total := coalesce((v_j.args->>'pages')::int, 0);
    select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = (v_j.args->>'provider_id')::uuid and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
    if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) read again with the adapter'; end if;
  elsif v_j.kind = 'central_page_read' then
    v_stall := interval '30 minutes'; v_total := 1;
    select * into r from pipeline.provider_fact_sources s where s.id = (v_j.args->>'source_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the central page record is gone';
    elsif r.status in ('read', 'parsed', 'no_values', 'failed') and r.updated_at >= coalesce(v_j.started_at, v_j.created_at) - interval '1 minute' then
      v_done := 1; v_fin := true; v_note := 'page ' || r.status || coalesce(': ' || (r.parse_summary->>'error'), '');
    end if;
  end if;
  if v_done <> v_last_done then v_last_done := v_done; v_last_at := now(); end if;
  if not v_fin and v_stall is not null and now() - v_last_at > v_stall then
    v_fin := true; v_note := coalesce(v_note, v_done || ' of ' || v_total || ' done, nothing more for ' || extract(epoch from v_stall)::int / 60 || ' minutes: the rest wait their turn in the reader');
  end if;
  update pipeline.admin_jobs set cursor = jsonb_build_object('last_done', v_last_done, 'last_change_at', v_last_at), progress = jsonb_build_object('done', v_done, 'total', v_total) || coalesce(jsonb_build_object('phase', v_phase), '{}'::jsonb), result = jsonb_build_object('done', v_done, 'total', v_total, 'errors', case when v_note like 'the request failed%' then 1 else 0 end) || coalesce(jsonb_build_object('note', v_note), '{}'::jsonb), updated_at = now() where id = p_id;
  if v_fin and v_note is not null then insert into pipeline.admin_job_events(job_id, note) values (p_id, v_note); end if;
  return v_fin;
end $f$;
revoke all on function security.admin_job_watch_v1(uuid) from public, anon, authenticated;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.admin_job_slice_v1(uuid,integer)'::regprocedure) is distinct from '625470cb5fa00d09cbb01a1f75dd20b3' then
    raise exception 'admin_job_slice_v1 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.admin_job_slice_v1(uuid,integer)'::regprocedure);
  v_pairs := array[
    array[$s$  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update{sc}$s$,
          $s$  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update{sc}
  if v_j.kind in ('reread_pages', 'firecrawl_run', 'adapter_apply', 'central_page_read') then return security.admin_job_watch_v1(p_id){sc} end if{sc}$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    v_pair[1] := replace(v_pair[1], '{sc}', chr(59)); v_pair[2] := replace(v_pair[2], '{sc}', chr(59));
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_jobs(text,jsonb)'::regprocedure) is distinct from '482e83fb4a2c26b4c749324efcd7bae2' then
    raise exception 'admin_jobs changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_jobs(text,jsonb)'::regprocedure);
  v_pairs := array[
    -- the start branch uses v_res, which the function did not declare
    array[$s$v_fields text[]{sc} v_title text{sc} v_n int{sc}$s$,
          $s$v_fields text[]{sc} v_title text{sc} v_n int{sc} v_res jsonb{sc}$s$],
    -- the person who started a task, on the task detail too
    array[$s$'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'note', e.note, 'detail', e.detail) order by e.id desc)$s$,
          $s$'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by),
                    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'note', e.note, 'detail', e.detail) order by e.id desc)$s$],
    -- the four watcher kinds: perform the existing admin action as the caller, then watch it
    array[$s$    else
      raise exception 'unknown job kind'{sc}
    end if{sc}$s$,
          $s$    elsif v_kind = 'reread_pages' then
      v_res := public.admin_university_reread('queue', coalesce(p_args->'args', '{}'::jsonb) || jsonb_build_object('reason', v_reason)){sc}
      v_ids := array(select distinct (x)::uuid from jsonb_array_elements_text(coalesce(p_args->'args'->'provider_ids', '[]'::jsonb)) x){sc}
      v_title := 'Read pages again: ' || case when cardinality(v_ids) = 1 then coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_ids[1]), '1 university') else cardinality(v_ids) || ' universities' end
                 || case when coalesce(p_args->'args'->>'which', 'all') = 'not_confirmed' then ' (pages not confirmed)' else '' end || case when coalesce((p_args->'args'->>'central')::boolean, false) then ' with central pages' else '' end{sc}
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('request_id', v_res->>'request_id', 'provider_ids', to_jsonb(v_ids), 'which', coalesce(p_args->'args'->>'which', 'all'), 'central', coalesce((p_args->'args'->>'central')::boolean, false)),
                jsonb_build_object('done', 0, 'total', cardinality(v_ids), 'phase', 'sending'), auth.uid(), v_reason, case when cardinality(v_ids) = 1 then v_ids[1]::text else coalesce(nullif(p_args->'args'->>'scope', ''), 'universities') end)
        returning * into v_j{sc}
    elsif v_kind = 'firecrawl_run' then
      v_res := public.admin_firecrawl_write('start', jsonb_build_object('use_case', p_args->'args'->>'use_case', 'reason', v_reason)){sc}
      v_title := 'Firecrawl run: ' || replace(coalesce(p_args->'args'->>'use_case', ''), '_', ' ') || ' (' || coalesce(v_res->>'items', '0') || ' pages, cap ' || coalesce(v_res->>'credits_cap', '-') || ' credits)'{sc}
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'firecrawl', v_title, jsonb_build_object('run_id', v_res->>'run_id', 'use_case', p_args->'args'->>'use_case', 'items', (v_res->>'items')::int), jsonb_build_object('done', 0, 'total', coalesce((v_res->>'items')::int, 0)), auth.uid(), v_reason, p_args->'args'->>'use_case')
        returning * into v_j{sc}
      v_ids := '{}'{sc}
    elsif v_kind = 'adapter_apply' then
      v_res := public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'reason', v_reason)){sc}
      v_title := 'Apply the adapter: ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = (p_args->'args'->>'provider_id')::uuid), '') || ' (' || coalesce(v_res->>'pages_read_again', '0') || ' pages)'{sc}
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'pages', coalesce((v_res->>'pages_read_again')::int, 0), 'providers', jsonb_build_array(p_args->'args'->>'provider_id')), jsonb_build_object('done', 0, 'total', coalesce((v_res->>'pages_read_again')::int, 0)), auth.uid(), v_reason, p_args->'args'->>'provider_id')
        returning * into v_j{sc}
      v_ids := array[(p_args->'args'->>'provider_id')::uuid]{sc}
    elsif v_kind = 'central_page_read' then
      v_res := public.admin_provider_central_page(coalesce(nullif(p_args->'args'->>'action', ''), 'add'), jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'kind', p_args->'args'->>'kind', 'url', p_args->'args'->>'url', 'title', p_args->'args'->>'title', 'reason', v_reason)){sc}
      v_title := 'Read a central page: ' || replace(coalesce(p_args->'args'->>'kind', ''), '_', ' ') || ' for ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = (p_args->'args'->>'provider_id')::uuid), ''){sc}
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('source_id', v_res->>'source_id', 'provider_id', p_args->'args'->>'provider_id', 'kind', p_args->'args'->>'kind', 'url', p_args->'args'->>'url', 'providers', jsonb_build_array(p_args->'args'->>'provider_id')), jsonb_build_object('done', 0, 'total', 1), auth.uid(), v_reason, p_args->'args'->>'provider_id')
        returning * into v_j{sc}
      v_ids := array[(p_args->'args'->>'provider_id')::uuid]{sc}
    else
      raise exception 'unknown job kind'{sc}
    end if{sc}$s$],
    -- cancel stops the underlying work where it can be stopped
    array[$s$    if v_j.state in ('queued', 'paused') then$s$,
          $s$    if v_j.kind = 'reread_pages' then
      update pipeline.university_reread_requests set status = 'cancelled', finished_at = now() where id = (v_j.args->>'request_id')::uuid and status in ('waiting', 'sending'){sc}
    elsif v_j.kind = 'firecrawl_run' then
      perform public.admin_firecrawl_write('stop', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason)){sc}
    end if{sc}
    if v_j.state in ('queued', 'paused') then$s$],
    array[$s$    if v_j.state not in ('queued', 'running') then raise exception 'only a queued or running job can be paused'{sc} end if{sc}$s$,
          $s$    if v_j.state not in ('queued', 'running') then raise exception 'only a queued or running job can be paused'{sc} end if{sc}
    if v_j.kind in ('reread_pages', 'adapter_apply', 'central_page_read') then raise exception 'this task cannot be paused, only cancelled'{sc} end if{sc}
    if v_j.kind = 'firecrawl_run' then perform public.admin_firecrawl_write('stop', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason)){sc} end if{sc}$s$],
    array[$s$    if v_j.state <> 'paused' then raise exception 'only a paused job can be resumed'{sc} end if{sc}$s$,
          $s$    if v_j.state <> 'paused' then raise exception 'only a paused job can be resumed'{sc} end if{sc}
    if v_j.kind = 'firecrawl_run' then perform public.admin_firecrawl_write('continue', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason)){sc} end if{sc}$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    v_pair[1] := replace(v_pair[1], '{sc}', chr(59)); v_pair[2] := replace(v_pair[2], '{sc}', chr(59));
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
