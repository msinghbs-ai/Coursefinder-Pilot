-- CF-247 (15 Oct 2026): the flag unit. Platform Admin, 15 Oct 2026 15:20: "we don't keep burning the toolset on repetitive waste and produce
-- nothing. we need to automate flag and keep moving and have flag unit that can be removed or raised manually and automatically by tried burn.
-- evidence of that flag will details why it was raised or released manually and the said entry or provider get re-entered in queue. this will
-- prevent the false case of providers website being out and when comes online we re-join them for enrichment."
-- Decisions (multiple choice): flags on providers, course fields and jobs; hard reasons flag at once, soft reasons after 2 tries; re-entry when the
-- input changes, or after a free check (no Firecrawl, no AI) on a back-off of 3, 7, 14 and 30 days; a person can raise or release any flag with a reason.
-- Found (15 Oct, 6 hours): about 4,000 worker calls, 3 jobs produced anything; the central-page finder put four universities straight back in its
-- queue after each refusal (716 refusals today); every Canadian and New Zealand gap had been tried and skipped by Enrich fields on 14 Oct.
-- Replaces: the waste guard's hourly idle check for worker jobs (now every 10 minutes, measured from each job's own results); the logo finder's
--   fixed 30-day retry (now the flag's recheck); the central-page finder's "back in the queue, unchanged" after a refusal (now a flag until due)
-- Retires: nothing (pipeline.enrichment_flags is extended, not replaced; every writer of it now leaves a history)
-- 1 Settings (Flags)  2 Flag columns, history table, state kept in step for every writer  3 Raise, release, re-queue, hold checks
-- 4 Enrich fields: held items are not queued; a skip counts a try; a fill releases  5 Logo finder and central pages use flags
-- 6 Worker jobs that run empty are paused by flag and tried again on a back-off  7 Recheck job flag-recheck  8 Screen API  9 Backfill
-- Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.svc_logo_find_next(integer)": "0117c645fb4d56897e21a1c30d45c91b", "public.svc_logo_find_record(uuid,text,text,text,text,text,text,integer,integer,text,text,jsonb)": "f41cc650bdf5d9b8abdc07e82742d325", "public.svc_central_find_next(integer)": "db56277114e5b3c01cf1052fb91d45d5", "public.svc_central_find_record(uuid,jsonb,jsonb)": "b94f89ea42d76e305ceba7c356454c65"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'flag.soft_tries', 'Tries before a soft flag holds', 'A soft reason (the page gives no value, nothing found) holds an item after this many tries. A second try is only made when the item''s input has changed. Hard reasons (site down, blocked, not due) hold at once.', 'number', to_jsonb(2), 1, 5, 'tries', 780, 'Platform Admin 15 Oct 2026: "Hard at once, soft after 2 tries"', 'Flags', 'security.flag_raise_v1; Enrich fields'),
 ('pipeline', 'flag.recheck_days', 'Free recheck back-off for providers', 'Days between free checks (no Firecrawl, no AI) of a held provider: first, second, third, then every after. A website that answers again is released and re-queued.', 'list', '[3, 7, 14, 30]'::jsonb, null, null, 'days', 781, 'Platform Admin 15 Oct 2026: "Change detected + free recheck"', 'Flags', 'security.flag_recheck_v1; coverage-sweep mode flag_check'),
 ('pipeline', 'flag.job_recheck_hours', 'Trial run back-off for paused jobs', 'Hours before a job paused for running empty is switched on again to look for new work: first, second, third, then every after.', 'list', '[1, 2, 4, 6]'::jsonb, null, null, 'hours', 782, 'Platform Admin 15 Oct 2026: "we don''t keep burning the toolset on repetitive waste"', 'Flags', 'security.flag_jobs_v1'),
 ('pipeline', 'flag.empty_calls_to_pause', 'Empty runs before a worker job is paused', 'A worker job whose last this-many runs all found nothing to do is paused and flagged.', 'number', to_jsonb(30), 5, 200, 'runs', 783, 'Platform Admin 15 Oct 2026: "automate flag and keep moving"', 'Flags', 'security.flag_jobs_v1'),
 ('pipeline', 'flag.never_pause_modes', 'Worker jobs never paused for running empty', 'Worker modes whose job has no queue (it reads a balance or a status) and is never paused.', 'list', '["openrouter_balance"]'::jsonb, null, null, 'modes', 784, 'A balance check produces no items by design', 'Flags', 'security.flag_jobs_v1'),
 ('pipeline', 'flag.manage_min_rank', 'Lowest role that can raise or release flags', 'Role rank: 4 Pipeline Operator, 5 PIM Admin, 6 Platform Admin. Lower roles see flags but cannot change them.', 'number', to_jsonb(6), 3, 6, 'role rank', 785, 'Platform Admin 15 Oct 2026', 'Flags', 'public.admin_flags'),
 ('pipeline', 'batch.flag_check', 'Held providers checked per recheck', 'Each recheck reads this many held providers'' home pages directly (no Firecrawl, no AI).', 'number', to_jsonb(20), 1, 50, 'providers', 786, 'Free recheck', 'Flags', 'coverage-sweep mode flag_check'),
 ('pipeline', 'batch.flag_change_scan', 'Held course fields checked for new input per recheck', 'Each recheck looks at this many held course fields for a course page read again with new content.', 'number', to_jsonb(2000), 100, 20000, 'flags', 787, 'Change detected', 'Flags', 'security.flag_recheck_v1')
on conflict do nothing;

-- 2 Flag columns, history, state kept in step
alter table pipeline.enrichment_flags
  add column if not exists kind text not null default 'hard' check (kind in ('hard', 'soft')),
  add column if not exists state text not null default 'raised' check (state in ('counting', 'raised', 'released')),
  add column if not exists tries integer not null default 1,
  add column if not exists checks integer not null default 0,
  add column if not exists evidence jsonb not null default '{}'::jsonb,
  add column if not exists next_check_at timestamptz,
  add column if not exists input_mark text,
  add column if not exists raised_by_kind text not null default 'auto' check (raised_by_kind in ('auto', 'person')),
  add column if not exists released_at timestamptz,
  add column if not exists released_by text,
  add column if not exists release_kind text check (release_kind in ('auto', 'person')),
  add column if not exists release_reason text,
  add column if not exists updated_at timestamptz not null default now();
comment on table pipeline.enrichment_flags is 'CF-247 flag unit (15 Oct 2026): one row per held item (provider, course field or job) and reason. state raised = held out of every queue; counting = a soft reason seen fewer times than the setting; released = back in the queue. Who or what raised or released it, why, and the evidence; history in pipeline.enrichment_flag_events.';
update pipeline.enrichment_flags set state = case when cleared_at is null then 'raised' else 'released' end, released_at = cleared_at,
       release_kind = case when cleared_at is not null then 'auto' end, released_by = case when cleared_at is not null then source end;
update pipeline.enrichment_flags set next_check_at = flagged_at + make_interval(days => security.pipeline_num_v1('logo.retry_after_days', 30)::int)
 where reason_code = 'logo_not_found' and state = 'raised';
create index if not exists enrichment_flags_due_idx on pipeline.enrichment_flags (next_check_at) where state = 'raised' and next_check_at is not null;
create index if not exists enrichment_flags_provider_idx on pipeline.enrichment_flags (provider_id) where state = 'raised';

create table pipeline.enrichment_flag_events (
  id bigserial primary key,
  flag_id bigint not null references pipeline.enrichment_flags(id) on delete cascade,
  action text not null check (action in ('raised', 'counted', 're_raised', 'released', 'check_failed', 'requeued')),
  actor text not null,
  actor_kind text not null check (actor_kind in ('auto', 'person')),
  reason text,
  evidence jsonb not null default '{}'::jsonb,
  at timestamptz not null default now()
);
comment on table pipeline.enrichment_flag_events is 'CF-247 flag unit (15 Oct 2026): the history of every flag: raised, counted, released, re-queued, free check failed; by a job or a person; why; and the evidence. Never edited.';
create index enrichment_flag_events_flag_idx on pipeline.enrichment_flag_events (flag_id, at);
alter table pipeline.enrichment_flag_events enable row level security;
revoke all on pipeline.enrichment_flag_events from anon, authenticated;

-- every writer of a flag leaves state and history in step (the waste guard, adapter checks and the rest write flags directly)
CREATE OR REPLACE FUNCTION security.enrichment_flags_sync_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if coalesce(current_setting('cf.flag_fn', true), '') = '1' then new.updated_at := now(); return new; end if;  -- the flag functions keep their own state
  if tg_op = 'INSERT' then
    new.state := case when new.cleared_at is null then 'raised' else 'released' end;
    if new.state = 'released' then new.released_at := new.cleared_at; new.release_kind := 'auto'; new.released_by := new.source; end if;
  elsif new.cleared_at is distinct from old.cleared_at then
    if new.cleared_at is null then
      if old.release_kind = 'person' then new.cleared_at := old.cleared_at; return new; end if;  -- a person's release stands against automatic re-raising
      new.state := 'raised'; new.tries := old.tries + 1; new.released_at := null;
    else
      new.state := 'released'; new.released_at := new.cleared_at; new.release_kind := coalesce(new.release_kind, 'auto'); new.released_by := coalesce(new.released_by, new.source);
    end if;
  end if;
  new.updated_at := now();
  return new;
end $function$;

CREATE OR REPLACE FUNCTION security.enrichment_flags_log_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if coalesce(current_setting('cf.flag_fn', true), '') = '1' then return null; end if;  -- the flag functions write their own history
  if tg_op = 'INSERT' then
    insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence)
    values (new.id, case when new.state = 'raised' then 'raised' else 'released' end, coalesce(new.source, 'unknown'), 'auto', new.reason, new.evidence);
  elsif new.state is distinct from old.state then
    insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence)
    values (new.id, case new.state when 'raised' then 're_raised' when 'released' then 'released' else 'counted' end, coalesce(new.source, 'unknown'), 'auto', new.reason, new.evidence);
  end if;
  return null;
end $function$;

create index if not exists edge_request_log_mode_idx on pipeline.edge_request_log (function_name, mode, created_at desc);
create trigger enrichment_flags_sync before insert or update on pipeline.enrichment_flags for each row execute function security.enrichment_flags_sync_v1();
create trigger enrichment_flags_log after insert or update on pipeline.enrichment_flags for each row execute function security.enrichment_flags_log_v1();

-- 3 Raise, release, re-queue, hold checks
CREATE OR REPLACE FUNCTION security.flag_list_num_v1(p_key text, p_n integer)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the n-th step of a back-off list setting (0-based); past the end, the last step
  select ((s.value -> least(greatest(p_n, 0), jsonb_array_length(s.value) - 1)) #>> '{}')::numeric::int
    from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key and jsonb_typeof(s.value) = 'array' and jsonb_array_length(s.value) > 0
$function$;

CREATE OR REPLACE FUNCTION security.flag_raise_v1(p_entity text, p_key text, p_provider_id uuid, p_field text, p_code text, p_reason text, p_kind text,
                                                 p_actor text, p_actor_kind text, p_evidence jsonb, p_input_mark text, p_next_check timestamptz)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f pipeline.enrichment_flags; v_state text; v_action text; v_tries int; v_soft int := security.pipeline_num_v1('flag.soft_tries', 2)::int;
begin
  perform set_config('cf.flag_fn', '1', true);
  select * into f from pipeline.enrichment_flags x where x.entity = p_entity and x.entity_key = p_key and x.field = coalesce(p_field, '') and x.reason_code = p_code for update;
  if not found then
    v_state := case when p_kind = 'hard' or v_soft <= 1 then 'raised' else 'counting' end;
    insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source, kind, state, tries, evidence, next_check_at, input_mark, raised_by_kind, cleared_at)
    values (p_entity, p_key, p_provider_id, coalesce(p_field, ''), p_code, p_reason, p_actor, p_kind, v_state, 1, coalesce(p_evidence, '{}'::jsonb), p_next_check, p_input_mark, p_actor_kind,
            case when v_state = 'raised' then null else now() end)
    returning * into f;
    v_action := case v_state when 'raised' then 'raised' else 'counted' end;
  elsif f.state = 'raised' then
    update pipeline.enrichment_flags set reason = p_reason, evidence = coalesce(p_evidence, evidence), input_mark = coalesce(p_input_mark, input_mark),
           next_check_at = coalesce(p_next_check, next_check_at) where id = f.id;
    v_state := 'raised';  -- already held: evidence refreshed, no new history line
  else
    v_tries := case when f.state = 'counting' then f.tries + 1 else 1 end;
    v_state := case when p_kind = 'hard' or v_tries >= v_soft then 'raised' else 'counting' end;
    update pipeline.enrichment_flags set reason = p_reason, source = p_actor, kind = p_kind, state = v_state, tries = v_tries, evidence = coalesce(p_evidence, '{}'::jsonb),
           next_check_at = p_next_check, input_mark = coalesce(p_input_mark, input_mark), raised_by_kind = p_actor_kind, flagged_at = now(),
           cleared_at = case when v_state = 'raised' then null else coalesce(cleared_at, now()) end,
           released_at = case when v_state = 'raised' then null else released_at end
     where id = f.id;
    v_action := case when v_state = 'counting' then 'counted' when f.state = 'released' then 're_raised' else 'raised' end;
  end if;
  if v_action is not null then
    insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence) values (f.id, v_action, p_actor, p_actor_kind, p_reason, coalesce(p_evidence, '{}'::jsonb));
  end if;
  perform set_config('cf.flag_fn', '', true);
  return jsonb_build_object('id', f.id, 'state', v_state);
end $function$;

-- put the item back where its queue will pick it up
CREATE OR REPLACE FUNCTION security.flag_requeue_v1(p_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f pipeline.enrichment_flags; v_jobid bigint;
begin
  select * into f from pipeline.enrichment_flags where id = p_id;
  if f.reason_code in ('logo_not_found', 'site_unreachable') or (f.entity = 'provider' and f.reason_code = 'manual_hold') then
    update pipeline.provider_logo_finds set status = 'queued', updated_at = now() where provider_id = f.provider_id and status in ('not_found', 'failed');
    update pipeline.provider_central_search set state = 'queued', attempts = 0, leased_until = null, updated_at = now()
     where provider_id = f.provider_id and state in ('queued', 'failed') and f.reason_code <> 'logo_not_found';
    return case when f.reason_code = 'logo_not_found' then 'logo finder' else 'logo finder and central pages' end;
  elsif f.reason_code in ('central_not_due', 'central_budget') then
    update pipeline.provider_central_search set state = 'queued', attempts = 0, leased_until = null, updated_at = now() where provider_id = f.provider_id;
    return 'central pages';
  elsif f.entity = 'job' and f.reason_code in ('idle_paused', 'manual_hold') then
    select jobid into v_jobid from cron.job where jobname = f.entity_key;
    if v_jobid is not null then perform cron.alter_job(v_jobid, active := true); end if;
    update pipeline.job_idle_watch set paused_at = null, resumed_at = now() where jobname = f.entity_key;
    return 'job switched on';
  elsif f.entity = 'course' then
    return 'the next Enrich fields task includes it';
  end if;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION security.flag_release_v1(p_id bigint, p_actor text, p_actor_kind text, p_reason text, p_evidence jsonb, p_keep_checks boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f pipeline.enrichment_flags; v_q text;
begin
  perform set_config('cf.flag_fn', '1', true);
  update pipeline.enrichment_flags set state = 'released', cleared_at = now(), released_at = now(), released_by = p_actor, release_kind = p_actor_kind, release_reason = p_reason,
         tries = 0, checks = case when p_keep_checks then checks + 1 else 0 end, next_check_at = null
   where id = p_id and state <> 'released' returning * into f;
  if not found then perform set_config('cf.flag_fn', '', true); return null; end if;
  insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence) values (f.id, 'released', p_actor, p_actor_kind, p_reason, coalesce(p_evidence, '{}'::jsonb));
  v_q := security.flag_requeue_v1(f.id);
  if v_q is not null then
    insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence) values (f.id, 'requeued', p_actor, p_actor_kind, 'Back in the queue: ' || v_q, '{}'::jsonb);
  end if;
  perform set_config('cf.flag_fn', '', true);
  return jsonb_build_object('id', f.id, 'state', 'released', 'requeued', v_q);
end $function$;

CREATE OR REPLACE FUNCTION security.flag_provider_held_v1(p_provider_id uuid, p_codes text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from pipeline.enrichment_flags f where f.provider_id = p_provider_id and f.entity = 'provider' and f.state = 'raised'
                   and (f.reason_code = any (p_codes) or f.reason_code = 'manual_hold'))
$function$;

-- what a worker call achieved: the number of items, rows or providers it handled (0 = it found nothing to do)
CREATE OR REPLACE FUNCTION security.worker_call_work_v1(p_content text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare j jsonb;
begin
  begin j := p_content::jsonb; exception when others then return null; end;
  if jsonb_typeof(j) <> 'object' then return null; end if;
  return (select coalesce(sum(case when jsonb_typeof(v) = 'number' then (v #>> '{}')::numeric when jsonb_typeof(v) = 'array' then jsonb_array_length(v) else 0 end), 0)
            from jsonb_each(j) e(k, v) where k in ('providers', 'items', 'rows', 'found', 'read', 'searched', 'pages', 'picked', 'discover', 'applied', 'done', 'checked'));
end $function$;

-- 4 Enrich fields: a held course field is not queued; a second try needs new input; a skip counts a try; a fill releases
CREATE OR REPLACE FUNCTION security.field_enrich_items_gate_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.course_id is null then return new; end if;
  if exists (select 1 from pipeline.enrichment_flags f
              where f.entity = 'course' and f.entity_key = new.course_id::text and f.field in (new.field, '')
                and ((f.state = 'raised' and f.reason_code in ('enrich_no_value', 'manual_hold'))
                     or (f.state = 'counting' and f.reason_code = 'enrich_no_value'
                         and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = new.course_id and g.evidence_id is not null
                                           and g.evidence_id::text is distinct from f.input_mark and g.read_at > f.flagged_at)))) then
    return null;  -- held, or tried once on the same input: not queued
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION security.field_enrich_items_flag_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f record;
begin
  if new.course_id is null or new.state is not distinct from old.state then return null; end if;
  if new.state = 'skipped' and coalesce(new.reason, '') ~* '(does not state|names no campus|quote is not on the page|site-wide line|no allowed source|not classified)' then
    perform security.flag_raise_v1('course', new.course_id::text, new.provider_id, new.field, 'enrich_no_value', 'Enrich fields: ' || new.reason, 'soft', 'enrich-fields', 'auto',
      jsonb_build_object('job_id', new.job_id, 'item_id', new.id, 'source', new.source, 'tried', new.tried, 'cost_usd', new.cost_usd, 'evidence_id', new.evidence_id),
      coalesce(new.evidence_id::text, new.storage_path), null);
  elsif new.state = 'filled' then
    for f in select id from pipeline.enrichment_flags where entity = 'course' and entity_key = new.course_id::text and field = new.field and reason_code = 'enrich_no_value' and state <> 'released' loop
      perform security.flag_release_v1(f.id, 'enrich-fields', 'auto', 'Value found by Enrich fields', jsonb_build_object('job_id', new.job_id, 'item_id', new.id), false);
    end loop;
  end if;
  return null;
end $function$;

create trigger field_enrich_items_gate before insert on pipeline.field_enrich_items for each row execute function security.field_enrich_items_gate_v1();
create trigger field_enrich_items_flag after update of state on pipeline.field_enrich_items for each row execute function security.field_enrich_items_flag_v1();

-- 6 Worker jobs that run empty: paused by flag; tried again on the back-off
CREATE OR REPLACE FUNCTION security.flag_jobs_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j record; f pipeline.enrichment_flags; v_n int; v_work int; v_since timestamptz; v_until timestamptz; v jsonb := '[]'::jsonb;
        v_need int := security.pipeline_num_v1('flag.empty_calls_to_pause', 30)::int;
        v_never text[] := coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'flag.never_pause_modes'), '{}');
begin
  for j in select c.jobid, c.jobname, c.active, (regexp_match(c.command, $re$'mode',\s*'([a-z_0-9]+)'$re$))[1] mode
             from cron.job c where c.command like '%svc_pilot_submit_nonce(''coverage-sweep''%' loop
    continue when j.mode is null or j.mode = any (v_never);
    select * into f from pipeline.enrichment_flags x where x.entity = 'job' and x.entity_key = j.jobname and x.field = '' and x.reason_code = 'idle_paused';
    if j.active and (f.id is null or f.state <> 'raised') then
      select count(*), count(*) filter (where coalesce(security.worker_call_work_v1(r.content), 1) > 0), min(l.created_at), max(l.created_at) into v_n, v_work, v_since, v_until
        from (select l2.* from pipeline.edge_request_log l2 where l2.function_name = 'coverage-sweep' and l2.mode = j.mode and l2.created_at > coalesce(f.released_at, '-infinity')
               order by l2.created_at desc limit v_need) l
        join net._http_response r on r.id = l.request_id where r.status_code = 200;
      if v_n >= v_need and v_work = 0 then
        perform cron.alter_job(j.jobid, active := false);
        perform security.flag_raise_v1('job', j.jobname, null, '', 'idle_paused', format('Paused: its last %s runs found nothing to do (worker mode %s)', v_n, j.mode), 'hard', 'flag-recheck', 'auto',
          jsonb_build_object('mode', j.mode, 'runs', v_n, 'with_work', 0, 'from', v_since, 'to', v_until),
          null, now() + make_interval(hours => coalesce(security.flag_list_num_v1('flag.job_recheck_hours', coalesce(f.checks, 0)), 6)));
        v := v || jsonb_build_object('paused', j.jobname);
      end if;
    elsif not j.active and f.state = 'raised' and f.reason_code = 'idle_paused' and f.next_check_at <= now() then
      perform security.flag_release_v1(f.id, 'flag-recheck', 'auto', 'Trial run: switched on again to look for new work', jsonb_build_object('mode', j.mode, 'check', f.checks + 1), true);
      v := v || jsonb_build_object('trial', j.jobname);
    end if;
  end loop;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_logo_find_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_items jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.id, p.canonical_name, p.website, k.iso_alpha2 country, f.requested_at
      from catalogue.providers p
      left join ref.countries k on k.id = p.country_id
      left join pipeline.provider_logo_finds f on f.provider_id = p.id
     where p.lifecycle_status = 'active' and nullif(btrim(p.website), '') is not null
       and not exists (select 1 from catalogue.provider_assets a where a.provider_id = p.id and a.is_primary and a.status = 'approved'
                        and a.asset_type in ('logo', 'logo_dark', 'logo_light'))
       and (f.provider_id is null
            or f.requested_at is not null
            or f.status = 'queued'
            or (f.status = 'trying' and f.last_tried_at < now() - interval '15 minutes')  -- fixed: claim lease, a run that died
            )
       -- CF-247 15 Oct 2026 (flag unit): a provider held (website down, logo not found) waits for its flag's recheck; a person's request goes through
       and (f.requested_at is not null or not security.flag_provider_held_v1(p.id, array['site_unreachable', 'logo_not_found']))
     order by (f.requested_at is not null) desc, f.requested_at, (select count(*) from catalogue.courses c where c.provider_id = p.id) desc, p.id
     limit greatest(p_limit, 0)
     for update of p skip locked),
  claim as (
    insert into pipeline.provider_logo_finds(provider_id, status, tries, last_tried_at, updated_at)
    select id, 'trying', 1, now(), now() from pick
    on conflict (provider_id) do update set status = 'trying', tries = pipeline.provider_logo_finds.tries + 1, last_tried_at = now(), requested_at = null, updated_at = now()
    returning provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', pick.id, 'name', pick.canonical_name, 'website', pick.website, 'country', pick.country)), '[]'::jsonb)
    into v_items from pick join claim on claim.provider_id = pick.id;
  return jsonb_build_object('items', v_items, 'min_pixels', security.pipeline_num_v1('logo.min_pixels', 64)::int);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_logo_find_record(p_provider_id uuid, p_status text, p_reason text, p_method text, p_storage_path text, p_mime_type text, p_content_hash text, p_width integer, p_height integer, p_source_url text, p_page_url text, p_evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_asset uuid; v_status text := p_status; f record;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_status not in ('found', 'not_found', 'failed') then raise exception 'unknown status %', p_status; end if;
  if p_status = 'found' then
    if p_storage_path is null or p_content_hash is null or p_mime_type not in ('image/svg+xml', 'image/png', 'image/jpeg', 'image/webp') then raise exception 'stored logo required'; end if;
    if exists (select 1 from catalogue.provider_assets a where a.provider_id = p_provider_id and a.is_primary and a.status = 'approved' and a.asset_type in ('logo', 'logo_dark', 'logo_light')) then
      v_status := 'skipped_has_logo';  -- a person added one meanwhile: theirs stays
    else
      insert into catalogue.provider_assets(provider_id, asset_type, source_url, storage_path, mime_type, width, height, content_hash, is_primary, status, observed_at, verified_at, metadata)
      values (p_provider_id, 'logo', p_source_url, p_storage_path, p_mime_type, p_width, p_height, p_content_hash, true, 'approved', now(), now(),
              jsonb_build_object('source_class', 'website_logo_finder', 'method', p_method, 'page_url', p_page_url, 'managed_storage', true, 'change_control_ref', 'CF-CHG-20260915-247') || coalesce(p_evidence, '{}'::jsonb))
      on conflict (provider_id, asset_type, coalesce(content_hash, ''), source_url) do update
        set storage_path = excluded.storage_path, is_primary = true, status = 'approved', verified_at = now(), metadata = catalogue.provider_assets.metadata || excluded.metadata
      returning id into v_asset;
      for f in select id from pipeline.enrichment_flags where entity = 'provider' and entity_key = p_provider_id::text and reason_code in ('logo_not_found', 'site_unreachable') and state <> 'released' loop
        perform security.flag_release_v1(f.id, 'logo-find', 'auto', 'Logo found and attached', jsonb_build_object('method', p_method, 'source_url', p_source_url), false);
      end loop;
    end if;
  else
    -- CF-247 15 Oct 2026 (flag unit): a home page that does not answer holds the provider (free recheck); otherwise the logo is looked for again later
    if coalesce(p_reason, '') like 'home page not read%' then
      perform security.flag_raise_v1('provider', p_provider_id::text, p_provider_id, '', 'site_unreachable', 'Website did not answer: ' || p_reason, 'hard', 'logo-find', 'auto',
        coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('page_url', p_page_url),
        null, now() + make_interval(days => coalesce(security.flag_list_num_v1('flag.recheck_days', 0), 3)));
    else
      perform security.flag_raise_v1('provider', p_provider_id::text, p_provider_id, 'logo', 'logo_not_found', coalesce(p_reason, 'no logo on the home page'), 'hard', 'logo-find', 'auto',
        coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('page_url', p_page_url),
        null, now() + make_interval(days => security.pipeline_num_v1('logo.retry_after_days', 30)::int));
    end if;
  end if;
  update pipeline.provider_logo_finds set status = v_status, reason = p_reason, method = p_method, source_url = p_source_url, page_url = p_page_url,
         provider_asset_id = coalesce(v_asset, provider_asset_id), updated_at = now()
   where provider_id = p_provider_id;
  return jsonb_build_object('provider_id', p_provider_id, 'status', v_status, 'provider_asset_id', v_asset);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_central_find_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.provider_id from pipeline.provider_central_search s join catalogue.providers p on p.id = s.provider_id
     where (s.state = 'queued' or (s.state = 'leased' and s.leased_until < now())) and s.attempts < 3
       and p.lifecycle_status = 'active' and p.website ~* '^https?://' and not security.third_party_host_v1(p.website)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)
       and (s.requested_at is not null or not security.flag_provider_held_v1(s.provider_id, array['central_not_due', 'central_budget', 'site_unreachable']))  -- CF-247 15 Oct 2026: held until due
     order by (s.requested_at is null), s.requested_at, (select count(*) from catalogue.courses c where c.provider_id = s.provider_id and c.lifecycle_status = 'active') desc
     limit greatest(1, least(coalesce(p_limit, 4), 10)) for update of s skip locked),
  upd as (update pipeline.provider_central_search s set state = 'leased', leased_until = now() + interval '10 minutes', attempts = s.attempts + 1, updated_at = now()
            from pick where s.provider_id = pick.provider_id returning s.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', u.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website)), '[]'::jsonb)
    into v from upd u join catalogue.providers p on p.id = u.provider_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_central_find_record(p_provider_id uuid, p_found jsonb, p_evidence jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_last timestamptz; v_due timestamptz;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_found is null then  -- no credit to spend: back in the queue, unchanged, and held by a flag until it is due (CF-247 15 Oct 2026: it was picked again every 5 minutes)
    update pipeline.provider_central_search set state = 'queued', leased_until = null, attempts = greatest(attempts - 1, 0), evidence = p_evidence, requested_at = null, updated_at = now() where provider_id = p_provider_id;
    select max(x.at) into v_last from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and security.fc_purpose_group_v1(x.purpose) = 'central';
    v_due := v_last + make_interval(days => security.fc_setting_num_v1('central_refresh_days', 30)::int);
    if v_due > now() then
      perform security.flag_raise_v1('provider', p_provider_id::text, p_provider_id, 'central_pages', 'central_not_due',
        format('Central pages read on %s; due again on %s (Firecrawl settings › central refresh days)', to_char(v_last at time zone 'Australia/Melbourne', 'DD Mon YYYY'), to_char(v_due at time zone 'Australia/Melbourne', 'DD Mon YYYY')),
        'hard', 'central-find', 'auto', coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('last_read', v_last, 'due', v_due), null, v_due);
    else
      perform security.flag_raise_v1('provider', p_provider_id::text, p_provider_id, 'central_pages', 'central_budget', 'No Firecrawl credit left in today''s share for central pages', 'hard', 'central-find', 'auto',
        coalesce(p_evidence, '{}'::jsonb), null, (date_trunc('day', now() at time zone 'Australia/Melbourne') + interval '1 day') at time zone 'Australia/Melbourne');  -- fixed: the daily budget resets at midnight
    end if;
    return;
  end if;
  update pipeline.provider_central_search s
     set state = case when p_evidence ? 'error' then (case when attempts >= 3 then 'failed' else 'queued' end) else 'done' end,
         found = case when p_evidence ? 'error' then s.found else p_found end, evidence = p_evidence, leased_until = null,
         searched_at = case when p_evidence ? 'error' then searched_at else now() end,
         requested_at = case when p_evidence ? 'error' then requested_at end, updated_at = now()
   where provider_id = p_provider_id;
end $function$;

-- 7 Recheck job
CREATE OR REPLACE FUNCTION security.flag_recheck_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f record; v_jobs jsonb; v_due int := 0; v_changed int := 0; v_sites int; v_req bigint;
begin
  v_jobs := security.flag_jobs_v1();
  -- held until a date (central pages not due, no budget today, logo looked for again): released when the date comes
  for f in select id, reason_code, checks from pipeline.enrichment_flags where state = 'raised' and next_check_at <= now() and reason_code in ('central_not_due', 'central_budget', 'logo_not_found') loop
    perform security.flag_release_v1(f.id, 'flag-recheck', 'auto', 'Due again: released on its recheck date', jsonb_build_object('check', f.checks + 1), true);
    v_due := v_due + 1;
  end loop;
  -- held course fields whose course page was read again with new content: released
  for f in select x.id from pipeline.enrichment_flags x
            where x.state = 'raised' and x.entity = 'course' and x.reason_code = 'enrich_no_value'
              and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = x.entity_key::uuid and g.evidence_id is not null
                            and g.evidence_id::text is distinct from x.input_mark and g.read_at > x.flagged_at)
            limit security.pipeline_num_v1('batch.flag_change_scan', 2000)::int loop
    perform security.flag_release_v1(f.id, 'flag-recheck', 'auto', 'Input changed: the course page was read again with new content', '{}'::jsonb, false);
    v_changed := v_changed + 1;
  end loop;
  -- held providers whose website is due a free check: the worker reads their home page directly (no Firecrawl, no AI)
  select count(*) into v_sites from pipeline.enrichment_flags where state = 'raised' and reason_code = 'site_unreachable' and next_check_at <= now();
  if v_sites > 0 then
    v_req := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'flag_check', 'limit', security.pipeline_num_v1('batch.flag_check', 20)::int));
  end if;
  return jsonb_build_object('jobs', v_jobs, 'released_due', v_due, 'released_changed', v_changed, 'sites_due', v_sites);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_flag_check_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select f.id from pipeline.enrichment_flags f where f.state = 'raised' and f.reason_code = 'site_unreachable' and f.next_check_at <= now()
     order by f.next_check_at limit greatest(p_limit, 0) for update skip locked),
  lease as (update pipeline.enrichment_flags f set next_check_at = now() + interval '15 minutes' from pick where f.id = pick.id returning f.id, f.provider_id)  -- fixed: claim lease
  select coalesce(jsonb_agg(jsonb_build_object('flag_id', l.id, 'provider_id', l.provider_id, 'name', p.canonical_name, 'website', p.website)), '[]'::jsonb) into v
    from lease l join catalogue.providers p on p.id = l.provider_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_flag_check_record(p_flag_id bigint, p_ok boolean, p_http integer, p_status text, p_evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f pipeline.enrichment_flags;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into f from pipeline.enrichment_flags where id = p_flag_id;
  if p_ok then
    return security.flag_release_v1(p_flag_id, 'flag-check', 'auto', format('Website answers again (HTTP %s)', p_http), coalesce(p_evidence, '{}'::jsonb), false);
  end if;
  perform set_config('cf.flag_fn', '1', true);
  update pipeline.enrichment_flags set checks = checks + 1, next_check_at = now() + make_interval(days => coalesce(security.flag_list_num_v1('flag.recheck_days', checks + 1), 30))
   where id = p_flag_id;
  insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence)
  values (p_flag_id, 'check_failed', 'flag-check', 'auto', format('Website still does not answer (%s%s)', p_status, case when p_http is null then '' else ' ' || p_http end), coalesce(p_evidence, '{}'::jsonb));
  perform set_config('cf.flag_fn', '', true);
  return jsonb_build_object('id', p_flag_id, 'state', 'raised');
end $function$;

-- 8 Screen API: see flags and their history; raise or release with a reason
CREATE OR REPLACE FUNCTION public.admin_flags(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int; v_can boolean; v_actor text; v_reason text; v_id bigint; v_out jsonb := '[]'::jsonb; v_r jsonb; v_lim int; v_off int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := security.current_role_rank();
  if v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_can := v_rank >= security.pipeline_num_v1('flag.manage_min_rank', 6)::int;
  v_actor := coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text);
  v_lim := least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200); v_off := greatest(coalesce((p_args->>'offset')::int, 0), 0);
  if p_action = 'summary' then
    return jsonb_build_object('can_change', v_can,
      'by_reason', (select coalesce(jsonb_agg(z order by z.held desc, z.reason_code), '[]'::jsonb) from (
          select f.entity, f.reason_code, count(*) filter (where f.state = 'raised') held, count(*) filter (where f.state = 'counting') counting,
                 count(*) filter (where f.state = 'released') released, count(*) filter (where f.state = 'raised' and f.raised_by_kind = 'person') by_person,
                 min(f.next_check_at) filter (where f.state = 'raised') next_check
            from pipeline.enrichment_flags f group by 1, 2) z),
      'last_24h', (select jsonb_object_agg(e.action, e.n) from (select action, count(*) n from pipeline.enrichment_flag_events where at > now() - interval '24 hours' group by 1) e));
  elsif p_action = 'list' then
    return (with x as (
      select f.*, coalesce(p.display_name, p.canonical_name, pp.canonical_name) provider_name, coalesce(c.display_title, c.canonical_title) course_title, count(*) over () total
        from pipeline.enrichment_flags f
        left join catalogue.providers p on f.entity = 'provider' and p.id = f.provider_id
        left join catalogue.courses c on f.entity = 'course' and c.id::text = f.entity_key
        left join catalogue.providers pp on pp.id = coalesce(f.provider_id, c.provider_id)
       where (nullif(p_args->>'state', '') is null or f.state = p_args->>'state')
         and (nullif(p_args->>'entity', '') is null or f.entity = p_args->>'entity')
         and (nullif(p_args->>'reason_code', '') is null or f.reason_code = p_args->>'reason_code')
         and (nullif(p_args->>'q', '') is null or coalesce(p.canonical_name, pp.canonical_name, '') ilike '%' || (p_args->>'q') || '%' or coalesce(c.display_title, c.canonical_title, '') ilike '%' || (p_args->>'q') || '%' or f.entity_key ilike '%' || (p_args->>'q') || '%')
       order by f.updated_at desc, f.id desc limit v_lim offset v_off)
      select jsonb_build_object('can_change', v_can, 'total', coalesce(max(x.total), 0), 'items', coalesce(jsonb_agg(jsonb_build_object(
        'id', x.id, 'entity', x.entity, 'entity_key', x.entity_key, 'provider_id', x.provider_id, 'provider_name', x.provider_name, 'course_title', x.course_title,
        'field', x.field, 'reason_code', x.reason_code, 'reason', x.reason, 'kind', x.kind, 'state', x.state, 'tries', x.tries, 'checks', x.checks,
        'raised_by', x.source, 'raised_by_kind', x.raised_by_kind, 'flagged_at', x.flagged_at, 'next_check_at', x.next_check_at,
        'released_at', x.released_at, 'released_by', x.released_by, 'release_kind', x.release_kind, 'release_reason', x.release_reason) order by x.updated_at desc, x.id desc), '[]'::jsonb)) from x);
  elsif p_action = 'events' then
    v_id := (p_args->>'id')::bigint;
    return jsonb_build_object('flag', (select to_jsonb(f) from pipeline.enrichment_flags f where f.id = v_id),
      'events', (select coalesce(jsonb_agg(to_jsonb(e) - 'flag_id' order by e.at desc, e.id desc), '[]'::jsonb) from pipeline.enrichment_flag_events e where e.flag_id = v_id));
  elsif p_action in ('release', 'raise') then
    if not v_can then raise exception 'your role cannot change flags' using errcode = '42501'; end if;
    v_reason := btrim(coalesce(p_args->>'reason', ''));
    if length(v_reason) < 4 then raise exception 'give a reason (it is kept with the flag)'; end if;
    if p_action = 'release' then
      for v_id in select (jsonb_array_elements_text(coalesce(p_args->'ids', '[]'::jsonb)))::bigint loop
        v_r := security.flag_release_v1(v_id, v_actor, 'person', v_reason, jsonb_build_object('user_id', auth.uid()), false);
        if v_r is not null then v_out := v_out || v_r; end if;
      end loop;
      return jsonb_build_object('released', jsonb_array_length(v_out), 'items', v_out);
    end if;
    if p_args->>'entity' = 'provider' then
      if not exists (select 1 from catalogue.providers where id = (p_args->>'key')::uuid) then raise exception 'provider not found'; end if;
      v_r := security.flag_raise_v1('provider', p_args->>'key', (p_args->>'key')::uuid, '', 'manual_hold', v_reason, 'hard', v_actor, 'person', jsonb_build_object('user_id', auth.uid()), null, null);
    elsif p_args->>'entity' = 'job' then
      if not exists (select 1 from cron.job where jobname = p_args->>'key') then raise exception 'job not found'; end if;
      perform cron.alter_job((select jobid from cron.job where jobname = p_args->>'key'), active := false);
      v_r := security.flag_raise_v1('job', p_args->>'key', null, '', 'manual_hold', v_reason, 'hard', v_actor, 'person', jsonb_build_object('user_id', auth.uid()), null, null);
    else
      raise exception 'a person can hold a provider or a job';
    end if;
    return v_r;
  elsif p_action = 'targets' then
    return jsonb_build_object(
      'providers', (select coalesce(jsonb_agg(jsonb_build_object('key', p.id, 'label', p.canonical_name) order by p.canonical_name), '[]'::jsonb)
                      from (select id, canonical_name from catalogue.providers where canonical_name ilike '%' || coalesce(p_args->>'q', '') || '%' order by canonical_name limit 10) p),
      'jobs', (select coalesce(jsonb_agg(jsonb_build_object('key', j.jobname, 'label', j.jobname) order by j.jobname), '[]'::jsonb)
                 from (select jobname from cron.job where jobname ilike '%' || coalesce(p_args->>'q', '') || '%' order by jobname limit 10) j));
  end if;
  raise exception 'unknown action %', p_action;
end $function$;

revoke execute on function security.enrichment_flags_sync_v1(), security.enrichment_flags_log_v1(), security.flag_list_num_v1(text, integer),
  security.flag_raise_v1(text, text, uuid, text, text, text, text, text, text, jsonb, text, timestamptz), security.flag_requeue_v1(bigint),
  security.flag_release_v1(bigint, text, text, text, jsonb, boolean), security.flag_provider_held_v1(uuid, text[]), security.worker_call_work_v1(text),
  security.field_enrich_items_gate_v1(), security.field_enrich_items_flag_v1(), security.flag_jobs_v1(), security.flag_recheck_v1(),
  public.svc_flag_check_next(integer), public.svc_flag_check_record(bigint, boolean, integer, text, jsonb), public.admin_flags(text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_flag_check_next(integer), public.svc_flag_check_record(bigint, boolean, integer, text, jsonb) to service_role;
grant execute on function public.admin_flags(text, jsonb) to authenticated;

-- 9 Backfill: what Enrich fields skipped on 14 Oct counts as tries (2 or more = held); a second try needs new input
select set_config('cf.flag_fn', '1', true);
with s as (
  select i.course_id, i.field, max(i.provider_id::text)::uuid provider_id, count(distinct i.job_id) tries,
         (array_agg(i.reason order by i.updated_at desc))[1] reason, (array_agg(coalesce(i.evidence_id::text, i.storage_path) order by i.updated_at desc))[1] mark,
         max(i.updated_at) last_at, (array_agg(i.job_id order by i.updated_at desc))[1] job_id, round(sum(coalesce(i.cost_usd, 0))::numeric, 4) cost
    from pipeline.field_enrich_items i
   where i.state = 'skipped' and i.course_id is not null
     and coalesce(i.reason, '') ~* '(does not state|names no campus|quote is not on the page|site-wide line|no allowed source|not classified)'
   group by i.course_id, i.field),
still as (
  select s.* from s join catalogue.courses c on c.id = s.course_id
   where case s.field when 'campus' then not exists (select 1 from catalogue.course_campuses x where x.course_id = c.id)
                      when 'duration' then c.duration_value is null when 'level' then c.study_level_id is null
                      when 'delivery' then nullif(btrim(c.delivery_mode), '') is null when 'field_of_study' then c.primary_field_id is null
                      when 'international' then c.open_to_international is null else false end),
ins as (
  insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source, kind, state, tries, evidence, input_mark, flagged_at, cleared_at)
  select 'course', still.course_id::text, still.provider_id, still.field, 'enrich_no_value', 'Enrich fields: ' || still.reason, 'enrich-fields', 'soft',
         case when still.tries >= security.pipeline_num_v1('flag.soft_tries', 2) then 'raised' else 'counting' end, still.tries,
         jsonb_build_object('backfill', 'CF-247 15 Oct 2026', 'last_job_id', still.job_id, 'cost_usd', still.cost), still.mark, still.last_at,
         case when still.tries >= security.pipeline_num_v1('flag.soft_tries', 2) then null else still.last_at end
    from still
  on conflict (entity, entity_key, field, reason_code) do nothing
  returning id, state, reason, evidence)
insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence)
select ins.id, case ins.state when 'raised' then 'raised' else 'counted' end, 'enrich-fields (backfill)', 'auto', ins.reason, ins.evidence from ins;
select set_config('cf.flag_fn', '', true);

-- the four universities the central-page finder kept picking: held until due
do $central$
declare r record; v_last timestamptz; v_due timestamptz;
begin
  for r in select distinct b.provider_id from pipeline.firecrawl_refusals_by_provider b where b.day = (now() at time zone 'Australia/Melbourne')::date and b.grp = 'central' and b.reason = 'not_due' loop
    select max(x.at) into v_last from pipeline.coverage_vendor_usage x where x.provider_id = r.provider_id and security.fc_purpose_group_v1(x.purpose) = 'central';
    v_due := v_last + make_interval(days => security.fc_setting_num_v1('central_refresh_days', 30)::int);
    if v_due > now() then
      perform security.flag_raise_v1('provider', r.provider_id::text, r.provider_id, 'central_pages', 'central_not_due',
        format('Central pages read on %s; due again on %s (picked every 5 minutes before the flag unit)', to_char(v_last at time zone 'Australia/Melbourne', 'DD Mon YYYY'), to_char(v_due at time zone 'Australia/Melbourne', 'DD Mon YYYY')),
        'hard', 'central-find', 'auto', jsonb_build_object('last_read', v_last, 'due', v_due), null, v_due);
    end if;
  end loop;
end $central$;

-- Job and register
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('flag-recheck', 'Platform upkeep', 93, 'Flags: hold, recheck and release',
  'Every 10 minutes: pauses worker jobs whose recent runs found nothing (trial run on a back-off), releases flags whose date has come (central pages due, logos to look for again), releases course fields whose page was read again with new content, and sends held providers to a free website check. Released items go back in their queue. Coverage & completeness › Flags.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('flag-recheck', '*/10 * * * *', 'select security.flag_recheck_v1()');

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('job', 'flag-recheck', 'Platform', 'Flag unit: hold, recheck and release; pauses worker jobs that run empty', 'active', '20261015080000'),
 ('table', 'pipeline.enrichment_flag_events', 'Platform', 'History of every flag: raised, released, re-queued, check failed; who and why', 'active', '20261015080000'),
 ('function', 'security.flag_recheck_v1()', 'Platform', 'Flag unit recheck', 'active', '20261015080000'),
 ('function', 'public.admin_flags(text,jsonb)', 'Platform', 'Flags screen', 'active', '20261015080000')
on conflict (kind, name) do nothing;

do $post$
declare v_expected jsonb := '{"public.svc_logo_find_next(integer)": "e12ffbf846893365dd7cc865be2310bb", "public.svc_logo_find_record(uuid,text,text,text,text,text,text,integer,integer,text,text,jsonb)": "7d65a466d9b41d87af10d017f1e18597", "public.svc_central_find_next(integer)": "3f35e4af86df0e1584dbde478105ce5d", "public.svc_central_find_record(uuid,jsonb,jsonb)": "f5a359b2a53c9b808846e7b00ee0ec53"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'flag unit post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $post2$
begin
  if not exists (select 1 from pg_trigger where tgname = 'field_enrich_items_gate') or not exists (select 1 from pg_trigger where tgname = 'enrichment_flags_sync') then
    raise exception 'flag unit post-check: triggers missing';
  end if;
  if exists (select 1 from pipeline.enrichment_flags where (state = 'raised') <> (cleared_at is null) and state <> 'counting') then
    raise exception 'flag unit post-check: state and cleared_at disagree';
  end if;
end $post2$;

-- DRY RUN checks
do $dry$
declare r jsonb; s jsonb; c jsonb;
begin
  r := security.flag_recheck_v1();
  select jsonb_object_agg(k, n) into s from (select entity||':'||reason_code||':'||state k, count(*) n from pipeline.enrichment_flags group by 1) z;
  select jsonb_object_agg(action, n) into c from (select action, count(*) n from pipeline.enrichment_flag_events group by 1) z;
  raise exception 'DRYRUN {"recheck": %, "flags": %, "events": %, "central_held": %}', r, s, c,
    (select jsonb_agg(p.canonical_name||' until '||to_char(f.next_check_at,'DD Mon')) from pipeline.enrichment_flags f join catalogue.providers p on p.id=f.provider_id where f.reason_code='central_not_due');
end $dry$;
