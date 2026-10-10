-- CF-247 Decision 254 (6 Oct 2026, Platform Admin 12:01 "Task Manager is the concept of Windows Task manager, only Running or
-- Queued Jobs management, closed Jobs and Scheduled Jobs are to be maintained from Jobs Tab", 13:27 "Through to C"). Job system
-- Phase A2 and B:
--   a finished task (done, failed or cancelled) writes one row to pipeline.jobs, the execution history the Scheduled jobs ›
--   Jobs tab already shows, with the task id in the payload so its per-provider result opens from there (A2)
--   the Task manager read returns live tasks only (queued, running, paused) unless asked for all (A2)
--   a task carries a scope (a state, country, provider or source) so a button can find the task it started after the page
--   is refreshed: read with kind and scope returns the matching live task (B)
-- admin_jobs and admin_jobs_tick_v1 are replaced whole, md5-guarded against the live definitions of migration 1720.
-- No text value in this file contains a semicolon.

alter table pipeline.admin_jobs add column if not exists scope text;
create index if not exists admin_jobs_kind_scope_idx on pipeline.admin_jobs(kind, scope, state);

-- The history row for a finished task. One per task, written once.
create or replace function security.admin_job_close_v1(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_j pipeline.admin_jobs%rowtype; v_pid uuid;
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id;
  if v_j.id is null or v_j.state not in ('done', 'failed', 'cancelled') then return; end if;
  if exists (select 1 from pipeline.jobs x where x.job_type = 'layer2_task' and x.payload->>'admin_job_id' = p_id::text) then return; end if;
  v_pid := case when coalesce(jsonb_array_length(v_j.args->'providers'), 0) = 1 then (v_j.args->'providers'->>0)::uuid else null end;
  insert into pipeline.jobs(job_type, domain, status, provider_id, requested_by, started_at, completed_at, attempt_count, payload, result, error_text)
  values ('layer2_task', v_j.kind, case when v_j.state = 'done' then 'completed' else 'failed' end, v_pid, v_j.requested_by, coalesce(v_j.started_at, v_j.created_at), coalesce(v_j.finished_at, now()), 1,
          jsonb_build_object('admin_job_id', v_j.id, 'kind', v_j.kind, 'title', v_j.title, 'scope', v_j.scope, 'reason', v_j.reason, 'args', v_j.args - 'providers', 'providers', coalesce(jsonb_array_length(v_j.args->'providers'), 0),
                             'mode', case when v_j.kind = 'qualify_adapters' then 'qualification' else 'apply' end),
          jsonb_build_object('state', v_j.state, 'progress', v_j.progress) || v_j.result,
          case when v_j.state = 'cancelled' then 'cancelled by a person (work done so far kept)' else v_j.error end);
end $f$;
revoke all on function security.admin_job_close_v1(uuid) from public, anon, authenticated;

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_jobs(text,jsonb)'::regprocedure) is distinct from 'b55b349bac07080f711386f8e0b34433' then
    raise exception 'admin_jobs changed, not replacing'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'security.admin_jobs_tick_v1(integer)'::regprocedure) is distinct from '7a72c695a1ade7244ddf9313536e0f11' then
    raise exception 'admin_jobs_tick_v1 changed, not replacing'; end if;
end $p$;

create or replace function public.admin_jobs(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_id uuid; v_kind text; v_ids uuid[]; v_j pipeline.admin_jobs%rowtype;
        v_q pipeline.admin_jobs%rowtype; v_fields text[]; v_title text; v_n int;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object(
      'jobs', coalesce((select jsonb_agg(to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0), 'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by)) order by j.created_at desc)
                         from (select * from pipeline.admin_jobs where state in ('queued', 'running', 'paused') or (p_args->>'all')::boolean order by created_at desc limit greatest(1, least(coalesce((p_args->>'limit')::int, 50), 200))) j), '[]'::jsonb),
      'match', case when p_args ? 'kind' then (select to_jsonb(j) - 'args' || jsonb_build_object('providers', coalesce(jsonb_array_length(j.args->'providers'), 0)) from pipeline.admin_jobs j
                      where j.kind = p_args->>'kind' and j.scope is not distinct from nullif(p_args->>'scope', '') and j.state in ('queued', 'running', 'paused') order by j.created_at desc limit 1) end,
      'job', case when p_args ? 'id' then (select to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0),
                    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'note', e.note, 'detail', e.detail) order by e.id desc) from (select * from pipeline.admin_job_events e where e.job_id = j.id order by e.id desc limit 200) e), '[]'::jsonb),
                    'qualifications', coalesce((select jsonb_agg(jsonb_build_object('provider_id', q.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'country', security.coverage_country(p.id), 'pages_read', q.pages_read, 'fields', q.fields, 'passing', q.passing, 'adapter', (select case when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end from pipeline.uni_adapters u where u.provider_id = q.provider_id), 'admitted', (select to_jsonb(u.admit_fields) from pipeline.uni_adapters u where u.provider_id = q.provider_id and u.admit)) order by coalesce(p.display_name, p.canonical_name))
                                       from pipeline.adapter_qualifications q join catalogue.providers p on p.id = q.provider_id where q.job_id = coalesce(j.args->>'qualification_job_id', j.id::text)::uuid), '[]'::jsonb))
                  from pipeline.admin_jobs j where j.id = (p_args->>'id')::uuid) end,
      'settings', jsonb_build_object('min_read_share', coalesce(security.firecrawl_setting('eval_field_share'), '0.5'::jsonb), 'min_agree_share', coalesce(security.firecrawl_setting('qualify_agree_share'), '0.9'::jsonb)),
      'countries', coalesce((select jsonb_agg(jsonb_build_object('code', k.iso_alpha2, 'name', k.name, 'adapters', n.n) order by k.name) from ref.countries k join (select p.country_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.country_id) n on n.country_id = k.id), '[]'::jsonb),
      'states', coalesce((select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name, 'country', k.iso_alpha2, 'adapters', n.n) order by s.code) from ref.subdivisions s join ref.countries k on k.id = s.country_id join (select p.subdivision_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.subdivision_id) n on n.subdivision_id = s.id), '[]'::jsonb),
      'can_admit', v_rank >= 6);
  end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'start' then
    v_kind := p_args->>'kind';
    if v_kind = 'qualify_adapters' then
      if v_rank < 5 then raise exception 'Operator (adapters) or above required' using errcode = '42501'; end if;
      v_ids := security.admin_jobs_resolve_adapters_v1(coalesce(p_args->'args', '{}'::jsonb));
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no adapters match that choice'; end if;
      v_title := 'Qualify ' || array_length(v_ids, 1) || ' adapter(s)' || coalesce(' in ' || nullif(btrim(coalesce(p_args->'args'->>'state', p_args->'args'->>'country', '')), ''), '');
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, coalesce(p_args->'args', '{}'::jsonb) || jsonb_build_object('providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason,
                coalesce(nullif(p_args->'args'->>'scope', ''), nullif(p_args->'args'->>'state', ''), nullif(p_args->'args'->>'country', '')))
        returning * into v_j;
    elsif v_kind = 'admit_qualified' then
      if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
      select * into v_q from pipeline.admin_jobs q where q.id = (p_args->'args'->>'qualification_job_id')::uuid;
      if v_q.id is null or v_q.kind <> 'qualify_adapters' or v_q.state <> 'done' then raise exception 'choose a finished Qualify job'; end if;
      v_fields := case when p_args->'args' ? 'fields' then array(select x from jsonb_array_elements_text(p_args->'args'->'fields') x where x in ('intakes', 'english', 'fee', 'delivery')) else array['intakes', 'english', 'fee', 'delivery'] end;
      v_ids := array(select q.provider_id from pipeline.adapter_qualifications q where q.job_id = v_q.id and q.passing && v_fields
                      and exists (select 1 from pipeline.uni_adapters u where u.provider_id = q.provider_id and u.enabled)
                      order by q.provider_id);
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no adapter passed for those fields'; end if;
      v_title := 'Admit the passing fields of ' || array_length(v_ids, 1) || ' adapter(s) (from ' || v_q.title || ')';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, jsonb_build_object('qualification_job_id', v_q.id, 'fields', to_jsonb(v_fields), 'providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason, v_q.id::text)
        returning * into v_j;
    else
      raise exception 'unknown job kind';
    end if;
    insert into pipeline.admin_job_events(job_id, note, detail) values (v_j.id, 'queued by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text), jsonb_build_object('reason', v_reason));
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('jobs', 'job_start', v_j.id::text, jsonb_build_object('kind', v_kind, 'title', v_j.title, 'providers', array_length(v_ids, 1), 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'id', v_j.id, 'title', v_j.title, 'providers', array_length(v_ids, 1));
  end if;
  v_id := (p_args->>'id')::uuid;
  select * into v_j from pipeline.admin_jobs j where j.id = v_id;
  if v_j.id is null then raise exception 'unknown job'; end if;
  if v_rank < 5 and v_j.requested_by <> auth.uid() then raise exception 'only the person who started it, or an Operator, may change this job' using errcode = '42501'; end if;
  if p_action = 'cancel' then
    if v_j.state in ('done', 'failed', 'cancelled') then raise exception 'the job has already finished'; end if;
    if v_j.state in ('queued', 'paused') then
      update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), updated_at = now(), cancel_requested = true where id = v_id;
      perform security.admin_job_close_v1(v_id);
    else
      update pipeline.admin_jobs set cancel_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'pause' then
    if v_j.state not in ('queued', 'running') then raise exception 'only a queued or running job can be paused'; end if;
    if v_j.state = 'queued' then
      update pipeline.admin_jobs set state = 'paused', updated_at = now() where id = v_id;
    else
      update pipeline.admin_jobs set pause_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'resume' then
    if v_j.state <> 'paused' then raise exception 'only a paused job can be resumed'; end if;
    update pipeline.admin_jobs set state = 'queued', pause_requested = false, updated_at = now() where id = v_id;
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_job_events(job_id, note, detail) values (v_id, p_action || ' requested by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text), jsonb_build_object('reason', v_reason));
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('jobs', 'job_' || p_action, v_id::text, jsonb_build_object('title', v_j.title, 'reason', v_reason), auth.uid());
  return jsonb_build_object('ok', true, 'id', v_id);
end $f$;
revoke all on function public.admin_jobs(text, jsonb) from public, anon;
grant execute on function public.admin_jobs(text, jsonb) to authenticated;

create or replace function security.admin_jobs_tick_v1(p_items integer default 10) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_lane text; v_j pipeline.admin_jobs%rowtype; v_fin boolean; v_out jsonb := '[]'::jsonb;
begin
  for v_lane in select distinct lane from pipeline.admin_jobs where state in ('queued', 'running') loop
    select * into v_j from pipeline.admin_jobs j where j.lane = v_lane and j.state in ('queued', 'running')
     order by (j.state = 'running') desc, j.created_at limit 1 for update skip locked;
    if v_j.id is null then continue; end if;
    if v_j.cancel_requested then
      update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'cancelled at a provider boundary, work done so far kept');
      perform security.admin_job_close_v1(v_j.id);
      v_out := v_out || jsonb_build_object('id', v_j.id, 'state', 'cancelled'); continue;
    end if;
    if v_j.pause_requested then
      update pipeline.admin_jobs set state = 'paused', pause_requested = false, updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'paused at a provider boundary');
      v_out := v_out || jsonb_build_object('id', v_j.id, 'state', 'paused'); continue;
    end if;
    if v_j.state = 'queued' then
      update pipeline.admin_jobs set state = 'running', started_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'started');
    end if;
    begin
      v_fin := security.admin_job_slice_v1(v_j.id, p_items);
    exception when others then
      update pipeline.admin_jobs set state = 'failed', error = left(sqlerrm, 500), finished_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'failed: ' || left(sqlerrm, 300));
      perform security.admin_job_close_v1(v_j.id);
      v_out := v_out || jsonb_build_object('id', v_j.id, 'state', 'failed'); continue;
    end;
    if v_fin then
      update pipeline.admin_jobs set state = 'done', finished_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note, detail) values (v_j.id, 'finished', (select j.result from pipeline.admin_jobs j where j.id = v_j.id));
      perform security.admin_job_close_v1(v_j.id);
    end if;
    v_out := v_out || jsonb_build_object('id', v_j.id, 'state', case when v_fin then 'done' else 'running' end);
  end loop;
  return v_out;
end $f$;
revoke all on function security.admin_jobs_tick_v1(integer) from public, anon, authenticated;
