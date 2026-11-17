-- CF-247 Wave 2, PR B (S2-Build; Platform Admin 17 Nov 2026 19:08 and 19:58; Mapper Contract v1.2 of S1-RM-Design): layout drift flags from
-- the Layer 1 readers, and the job that answers Re-infer Parser Spec requests.
--   1. Drift from every reader: a trigger on pipeline.layer1_run_queue flags drift on the source's parser line (pipeline.layer1_source_parsers)
--      when a run stops on a layout error of its reader (headers or columns not found, an expected column missing, a sheet or header row not
--      found), and clears the flag when a later run of the source completes. The readers' own code is not changed (CRICOS, NZQA, PRISMS,
--      provider facts and the Canadian readers each word it their own way). A source read by code gets its parser row as hardcoded the first
--      time drift is flagged, as public.svc_layer1_parser_drift_record does. The trigger never fails a run update.
--   2. Re-infer: job layer1-parser-reinfer (hourly, only when a request is waiting) starts layer1-ai-induction-mapper (action reinfer) with a
--      one-time nonce. For an AI-built parser it reads a fresh sample of the source file (setting layer1.declarative_max_file_mb), asks the model
--      through the worker (route layer1_induction_map), checks the new spec with security.layer1_parser_spec_validate_v1 and records it with
--      public.svc_layer1_parser_record (version up, drift and request cleared). A hardcoded parser is answered "needs a code change". Every
--      outcome is a control event (layer1: parser_reinfer_done, _failed, _skipped). Nothing resumes a source; a person accepts the result.
-- G1: the job is catalogued. G2: batch and file size are settings; the fire guard and input bounds are marked fixed. G3: no consumer API object.
-- Replaces: nothing (drift had no writer; re-infer requests had no reader; Mapper Contract v1.2).
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: deploy-time safety

do $pre$ begin
  if to_regclass('pipeline.layer1_source_parsers') is null or to_regclass('pipeline.layer1_run_queue') is null or to_regclass('pipeline.layer1_source_inductions') is null
     or to_regprocedure('security.layer1_parser_spec_validate_v1(jsonb,text,jsonb)') is null or to_regprocedure('public.svc_layer1_parser_record(uuid,jsonb)') is null then
    raise exception 'an object this change builds on is missing';
  end if;
end $pre$;

-- settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer1.declarative_max_file_mb', 'Layer 1 declarative reader: largest source file',
  'The largest source file the declarative reader downloads for an AI-built parser (re-infer samples and runs). A larger file stops with its size named.',
  'number', to_jsonb(50), 1, 500, 'MB', 1213, 'Wave 2 PR B (S2-Build, 17 Nov 2026)', 'Layer 1 register', 'layer1-ai-induction-mapper (reinfer) and the Layer 1 declarative runner'),
 ('pipeline', 'batch.layer1_parser_reinfer', 'Re-infer parser specs: sources a run',
  'How many waiting Re-infer Parser Spec requests one run of the job answers.',
  'number', to_jsonb(3), 1, 20, 'sources', 1214, 'Wave 2 PR B (S2-Build, 17 Nov 2026)', 'Layer 1 register', 'job layer1-parser-reinfer')
on conflict (toolset_key, key) do nothing;

-- 1. drift
create or replace function security.layer1_parser_drift_mark_v1(p_source_id uuid, p_flagged boolean, p_message text)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  insert into pipeline.layer1_source_parsers(source_id, parser_kind) values (p_source_id, 'hardcoded') on conflict (source_id) do nothing;
  update pipeline.layer1_source_parsers p
     set drift_flagged_at = case when p_flagged then coalesce(p.drift_flagged_at, now()) end,
         drift_message = case when p_flagged then left(coalesce(p_message, ''), 600) end, updated_at = now()
   where p.source_id = p_source_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', case when p_flagged then 'parser_drift_flagged' else 'parser_drift_cleared' end, p_source_id::text, jsonb_build_object('message', left(coalesce(p_message, ''), 600)), null);
end $function$;
comment on function security.layer1_parser_drift_mark_v1(uuid, boolean, text) is 'Wave 2: flags or clears layout drift on a Layer 1 source''s parser line (a source read by code gets its row as hardcoded), with a control event.';

create or replace function security.layer1_run_drift_watch_v1()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_msg text;
begin
  begin
    if new.status = 'failed' then
      v_msg := coalesce(nullif(new.result->'retry'->>'last_error', ''), nullif(new.result->>'error', ''), '');
      -- the layout errors the readers give (their own wording); timeouts, HTTP and plan errors are not drift
      if v_msg ~* '(headers? (not found|missing)|columns? (missing|not found)|required [a-z ]*columns? (is )?missing|does not contain expected [a-z ]*column|no [a-z0-9 /]*header row|sheet "?[^"]*"? not found|layout (changed|drift)|expected headers? missing)' then
        perform security.layer1_parser_drift_mark_v1(new.source_id, true, 'Run ' || left(new.id::text, 8) || ' stopped on the source layout: ' || left(v_msg, 500));
      end if;
    elsif new.status = 'completed' then
      if exists (select 1 from pipeline.layer1_source_parsers p where p.source_id = new.source_id and p.drift_flagged_at is not null and p.drift_flagged_at < coalesce(new.started_at, now())) then
        perform security.layer1_parser_drift_mark_v1(new.source_id, false, 'Run ' || left(new.id::text, 8) || ' read the source and completed');
      end if;
    end if;
  exception when others then
    raise warning 'layer1 drift watch (run %): %', new.id, sqlerrm;  -- never fails the run update
  end;
  return new;
end $function$;
comment on function security.layer1_run_drift_watch_v1() is 'Wave 2: on a Layer 1 run that stops on a layout error, flags drift on its source''s parser line; a later completed run clears it.';

create or replace trigger layer1_run_drift_watch
  after update of status on pipeline.layer1_run_queue
  for each row when (new.status is distinct from old.status and new.status in ('failed', 'completed'))
  execute function security.layer1_run_drift_watch_v1();

-- 2. re-infer
create or replace function security.layer1_parser_reinfer_due_v1()
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  select exists (
    select 1 from pipeline.layer1_source_parsers p
     where p.reinfer_requested_at is not null
       and not exists (select 1 from pipeline.admin_control_events e
                        where e.area = 'layer1' and e.action in ('parser_reinfer_done', 'parser_reinfer_failed', 'parser_reinfer_skipped')
                          and e.target = p.source_id::text and e.created_at >= p.reinfer_requested_at))
$function$;
comment on function security.layer1_parser_reinfer_due_v1() is 'Wave 2: true when a Re-infer Parser Spec request is waiting for an answer (fire guard of job layer1-parser-reinfer).';

create or replace function public.svc_layer1_parser_reinfer_queue_v1(p_limit integer)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (
    select coalesce(jsonb_agg(x order by x->>'requested_at'), '[]'::jsonb) from (
      select jsonb_build_object('source_id', p.source_id, 'parser_kind', p.parser_kind, 'target_record_type', p.target_record_type,
               'parser_spec', p.parser_spec, 'spec_version', p.spec_version, 'reinfer_reason', p.reinfer_reason, 'drift_message', p.drift_message,
               'requested_at', p.reinfer_requested_at,
               'induction', (select jsonb_build_object('id', i.id, 'country_code', i.country_code, 'source_url', i.payload->>'source_url',
                                     'connector_type', i.payload->>'connector_type', 'attribution_text', i.payload->>'attribution_text')
                               from pipeline.layer1_source_inductions i where i.source_id = p.source_id order by i.activated_at desc nulls last limit 1)) x
        from pipeline.layer1_source_parsers p
       where p.reinfer_requested_at is not null
         and not exists (select 1 from pipeline.admin_control_events e
                          where e.area = 'layer1' and e.action in ('parser_reinfer_done', 'parser_reinfer_failed', 'parser_reinfer_skipped')
                            and e.target = p.source_id::text and e.created_at >= p.reinfer_requested_at)
       order by p.reinfer_requested_at
       limit greatest(1, least(coalesce(p_limit, 3), 20))) q);  -- fixed: input-safety bound (the batch is the setting batch.layer1_parser_reinfer)
end $function$;
comment on function public.svc_layer1_parser_reinfer_queue_v1(integer) is 'Wave 2: the waiting Re-infer Parser Spec requests, with the parser and the activated induction''s source, for layer1-ai-induction-mapper.';

create or replace function public.svc_layer1_parser_reinfer_note_v1(p_source_id uuid, p_outcome text, p_detail jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_outcome not in ('done', 'failed', 'skipped') then raise exception 'outcome is done, failed or skipped'; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'parser_reinfer_' || p_outcome, p_source_id::text, coalesce(p_detail, '{}'::jsonb), null);
end $function$;
comment on function public.svc_layer1_parser_reinfer_note_v1(uuid, text, jsonb) is 'Wave 2: records the answer to a Re-infer Parser Spec request (done, failed or skipped) as a control event.';

revoke all on function security.layer1_parser_drift_mark_v1(uuid, boolean, text) from public, anon, authenticated;
revoke all on function security.layer1_run_drift_watch_v1() from public, anon, authenticated;
revoke all on function security.layer1_parser_reinfer_due_v1() from public, anon, authenticated;
revoke all on function public.svc_layer1_parser_reinfer_queue_v1(integer) from public, anon, authenticated;
revoke all on function public.svc_layer1_parser_reinfer_note_v1(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_layer1_parser_reinfer_queue_v1(integer) to service_role;
grant execute on function public.svc_layer1_parser_reinfer_note_v1(uuid, text, jsonb) to service_role;

-- the job
insert into pipeline.pilot_nonce_functions(function_name, note)
select 'layer1-ai-induction-mapper', 'Wave 2 PR B: job layer1-parser-reinfer (action reinfer)'
where not exists (select 1 from pipeline.pilot_nonce_functions where function_name = 'layer1-ai-induction-mapper');

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('layer1-parser-reinfer', 'Layer 1 register', 310, 'Re-infer parser specs',
  'Answers Re-infer Parser Spec requests: reads a fresh sample of the source, asks the AI mapper for a new parser spec, checks it and records it for a person to accept. Runs hourly, only when a request is waiting.',
  5, true)
on conflict (jobname) do nothing;

select cron.schedule('layer1-parser-reinfer', '41 * * * *', 'select pipeline.svc_pilot_submit_nonce(''layer1-ai-induction-mapper'', jsonb_build_object(''action'', ''reinfer'', ''limit'', security.pipeline_num_v1(''batch.layer1_parser_reinfer'', 3)::int)) where security.layer1_parser_reinfer_due_v1()');

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, v.layer, 'Layer 1 register', v.purpose, 'active', '20261117233000'
  from (values
    ('job', 'layer1-parser-reinfer', 'L1 register', 'Wave 2: answers Re-infer Parser Spec requests through the AI mapper'),
    ('function', 'security.layer1_run_drift_watch_v1', 'Layer 1', 'Wave 2: layout drift flags from every Layer 1 reader (trigger on pipeline.layer1_run_queue)'),
    ('function', 'security.layer1_parser_drift_mark_v1', 'Layer 1', 'Wave 2: flag or clear drift on a parser line'),
    ('function', 'public.svc_layer1_parser_reinfer_queue_v1', 'Layer 1', 'Wave 2: waiting re-infer requests'),
    ('function', 'public.svc_layer1_parser_reinfer_note_v1', 'Layer 1', 'Wave 2: re-infer outcomes')
  ) v(kind, name, layer, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

-- post-checks
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'layer1_run_drift_watch' and tgrelid = 'pipeline.layer1_run_queue'::regclass) then raise exception 'post-check: trigger'; end if;
  if not exists (select 1 from cron.job where jobname = 'layer1-parser-reinfer' and active) then raise exception 'post-check: job'; end if;
  if (select command from cron.job where jobname = 'layer1-parser-reinfer') ~ '\(\s*[0-9]+\s*[,)]' then raise exception 'post-check: a number in the job command'; end if;
  -- the drift pattern: reader wording is drift; a timeout is not
  if not ('headers not found on Sheet1' ~* '(headers? (not found|missing)|columns? (missing|not found))') or ('canceling statement due to statement timeout' ~* '(headers? (not found|missing)|columns? (missing|not found))') then
    raise exception 'post-check: drift pattern';
  end if;
end $$;
