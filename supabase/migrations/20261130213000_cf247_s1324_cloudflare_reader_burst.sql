-- CF-247 s1324 (S1-Build; SS-Programme-Control 27 Nov 2026 22:36 AEDT, Decision 2: "Approve the isolated studysearch-reader-burst
-- deployment subject to restricting the API token to Techm only. Approved limits: one Standard-3 instance, minimum zero instances, five-minute
-- idle shutdown, US$2 daily compute ceiling, US$20 monthly compute ceiling, public stored university evidence only ... Preserve Supabase as the
-- default runtime"; M3 Cloudflare Containers runbook v1.0 §2, §4, §7 and §8).
-- What it adds (the platform's own gate and record for the burst reader; no queue, scheduler, admission engine or storage):
--   1. Settings (G2, Settings › Pipeline settings): cloudflare_reader.on (the kill switch), .slots (1: reader-01 only; a second slot needs a
--      separate approval), .idle_minutes (5), .daily_usd_cap (2), .monthly_usd_cap (20), .usd_per_awake_hour (0.22, standard-3 at full CPU,
--      published rate) and .max_pages.
--   2. pipeline.cloudflare_reader_runs: one row per burst read (evidence, slot, times, HTTP status, the container's own measures, the
--      result summary and the estimated cost: awake time, reading plus the idle timeout, at the published rate). It is the run log the caps
--      are checked against; it holds no work.
--   3. public.svc_cloudflare_reader_v1 (service role): gate (switch, slot free, day and month estimates under their caps, the evidence a
--      stored public university source copy) and record. The coverage-sweep worker (mode burst_read, v1.0.61) is the only caller: it reads the
--      stored copy and sends it signed to the isolated Worker; Cloudflare never receives a Supabase credential and writes nothing here.
-- Supabase stays the default runtime: nothing routes work to Cloudflare by itself; a burst read is started by hand (benchmark workflow).
-- G1: no job. G3: 75/48 checked. Locks and cron checked. Spend: only the approved benchmark, inside the caps. Nothing dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the new objects

create temp table s1324_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
  ('pipeline', 'cloudflare_reader.on', 'Cloudflare burst reader: on',
   'The kill switch of the isolated Cloudflare reader (studysearch-reader-burst). 0: no burst read starts; Supabase does all processing as before.',
   'number', to_jsonb(1), 0, 1, 'switch', 1580, 'Services & limits', 'public.svc_cloudflare_reader_v1', 'CF-247 s1324 (SS-Programme-Control 27 Nov 2026 22:36, Decision 2)'),
  ('pipeline', 'cloudflare_reader.slots', 'Cloudflare burst reader: container slots',
   'How many named container slots may run at once (reader-01, reader-02). Approved: 1. A second slot needs a separate Platform Admin approval.',
   'number', to_jsonb(1), 1, 1, 'slots', 1581, 'Services & limits', 'public.svc_cloudflare_reader_v1', 'CF-247 s1324 (Decision 2: one Standard-3 instance)'),
  ('pipeline', 'cloudflare_reader.idle_minutes', 'Cloudflare burst reader: idle shutdown',
   'Minutes a container stays awake after its last read before it stops (the Worker''s IDLE_MS). Approved: 5.',
   'number', to_jsonb(5), 1, 5, 'minutes', 1582, 'Services & limits', 'public.svc_cloudflare_reader_v1', 'CF-247 s1324 (Decision 2: five-minute idle shutdown)'),
  ('pipeline', 'cloudflare_reader.daily_usd_cap', 'Cloudflare burst reader: daily compute ceiling',
   'No burst read starts when the day''s estimated container compute (Melbourne day) has reached this amount.',
   'number', to_jsonb(2), 0, 2, 'USD', 1583, 'Services & limits', 'public.svc_cloudflare_reader_v1', 'CF-247 s1324 (Decision 2: US$2 daily compute ceiling)'),
  ('pipeline', 'cloudflare_reader.monthly_usd_cap', 'Cloudflare burst reader: monthly compute ceiling',
   'No burst read starts when the month''s estimated container compute has reached this amount.',
   'number', to_jsonb(20), 0, 20, 'USD', 1584, 'Services & limits', 'public.svc_cloudflare_reader_v1', 'CF-247 s1324 (Decision 2: US$20 monthly compute ceiling)'),
  ('pipeline', 'cloudflare_reader.usd_per_awake_hour', 'Cloudflare burst reader: estimated cost of an awake hour',
   'Standard-3 (2 vCPU, 8 GiB, 16 GB disk) at full CPU at Cloudflare''s published rates (RAM 0.072, CPU 0.144, disk 0.004). Used for the estimate the caps are checked against; reconciled with the invoice.',
   'number', to_jsonb(0.22), 0.01, 5, 'USD per hour', 1585, 'Services & limits', 'public.svc_cloudflare_reader_v1', 'CF-247 s1324 (M3 runbook §2 rate card)'),
  ('pipeline', 'cloudflare_reader.max_pages', 'Cloudflare burst reader: PDF pages read',
   'The most pages of one stored PDF the burst reader reads.',
   'number', to_jsonb(400), 1, 1000, 'pages', 1586, 'Services & limits', 'public.svc_cloudflare_reader_v1', 'CF-247 s1324 (Decision 2)')
on conflict do nothing;

create table if not exists pipeline.cloudflare_reader_runs (
  id uuid primary key default gen_random_uuid(),
  evidence_id uuid not null,
  slot text not null,
  requested_by text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'running' check (status in ('running', 'done', 'failed')),
  http_status int,
  wall_ms int,
  estimated_usd numeric(10, 4),
  result jsonb
);
create index if not exists cloudflare_reader_runs_started on pipeline.cloudflare_reader_runs (started_at);
comment on table pipeline.cloudflare_reader_runs is 'CF-247 s1324: one row per read of the isolated Cloudflare burst reader (evidence, slot, times, HTTP status, the container''s own measures, the result summary and the estimated compute cost). The daily and monthly caps are checked against it. A log only: it holds no work.';
alter table pipeline.cloudflare_reader_runs enable row level security;
revoke all on table pipeline.cloudflare_reader_runs from public, anon, authenticated;

create or replace function public.svc_cloudflare_reader_v1(p_action text, p_args jsonb default '{}'::jsonb, p_by text default null) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_on int := security.pipeline_num_v1('cloudflare_reader.on', 1)::int;
  v_slots int := security.pipeline_num_v1('cloudflare_reader.slots', 1)::int;
  v_idle numeric := security.pipeline_num_v1('cloudflare_reader.idle_minutes', 5);
  v_day numeric := security.pipeline_num_v1('cloudflare_reader.daily_usd_cap', 2);
  v_month numeric := security.pipeline_num_v1('cloudflare_reader.monthly_usd_cap', 20);
  v_rate numeric := security.pipeline_num_v1('cloudflare_reader.usd_per_awake_hour', 0.22);
  v_today date := (now() at time zone 'Australia/Melbourne')::date;
  e pipeline.evidence_artifacts%rowtype; v_spent_day numeric; v_spent_month numeric; v_slot text; v_run uuid; v_wall int; v_est numeric;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_action = 'gate' then
    if v_on <> 1 then return jsonb_build_object('ok', false, 'held', 'HELD:SWITCHED_OFF'); end if;
    -- a lost call frees its slot after the lease timer
    update pipeline.cloudflare_reader_runs set status = 'failed', finished_at = now(), result = coalesce(result, '{}'::jsonb) || jsonb_build_object('error', 'lost call')
     where status = 'running' and started_at < now() - interval '15 minutes';  -- fixed: claim timer of a lost call
    select coalesce(sum(r.estimated_usd), 0) into v_spent_day from pipeline.cloudflare_reader_runs r where (r.started_at at time zone 'Australia/Melbourne')::date = v_today;
    select coalesce(sum(r.estimated_usd), 0) into v_spent_month from pipeline.cloudflare_reader_runs r where date_trunc('month', r.started_at at time zone 'Australia/Melbourne') = date_trunc('month', now() at time zone 'Australia/Melbourne');
    if v_spent_day >= v_day then return jsonb_build_object('ok', false, 'held', 'HELD:BUDGET_GATE', 'reason', format('day estimate US$%s of US$%s', v_spent_day, v_day)); end if;
    if v_spent_month >= v_month then return jsonb_build_object('ok', false, 'held', 'HELD:BUDGET_GATE', 'reason', format('month estimate US$%s of US$%s', v_spent_month, v_month)); end if;
    select s into v_slot from (select 'reader-' || lpad(g::text, 2, '0') s from generate_series(1, v_slots) g) z
     where not exists (select 1 from pipeline.cloudflare_reader_runs r where r.status = 'running' and r.slot = z.s) order by s limit 1;
    if v_slot is null then return jsonb_build_object('ok', false, 'held', 'HELD:SLOT_BUSY'); end if;
    -- public stored university evidence only: a stored source copy captured from a provider page
    select * into e from pipeline.evidence_artifacts where id = (p_args->>'evidence_id')::uuid;
    if e.id is null or e.storage_path is null or e.evidence_type <> 'source_snapshot' or coalesce(e.source_url, '') !~ '^https://'
       or e.storage_path !~ '^layer2/' or e.content_hash !~ '^[0-9a-f]{64}$' then
      return jsonb_build_object('ok', false, 'held', 'HELD:NOT_PUBLIC_STORED_EVIDENCE');
    end if;
    insert into pipeline.cloudflare_reader_runs (evidence_id, slot, requested_by) values (e.id, v_slot, left(coalesce(p_by, 'unknown'), 120)) returning id into v_run;
    return jsonb_build_object('ok', true, 'run_id', v_run, 'slot', v_slot, 'storage_path', e.storage_path, 'content_hash', e.content_hash, 'mime', e.mime_type,
                              'source_url', e.source_url, 'max_pages', security.pipeline_num_v1('cloudflare_reader.max_pages', 400)::int,
                              'spent_day_usd', v_spent_day, 'spent_month_usd', v_spent_month);
  elsif p_action = 'record' then
    v_wall := nullif(p_args->>'wall_ms', '')::int;
    -- estimate: the call's awake time plus the idle timeout, at the published standard-3 rate
    v_est := round(((coalesce(v_wall, 0) / 1000.0) + v_idle * 60) / 3600.0 * v_rate, 4);
    update pipeline.cloudflare_reader_runs set status = case when coalesce((p_args->>'http')::int, 0) between 200 and 299 then 'done' else 'failed' end,
           finished_at = now(), http_status = (p_args->>'http')::int, wall_ms = v_wall, estimated_usd = v_est, result = p_args->'result'
     where id = (p_args->>'run_id')::uuid and status = 'running';
    if not found then raise exception 'INVALID_INPUT: no running burst read with that id'; end if;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('cloudflare_reader', 'burst_read', 'pipeline.cloudflare_reader_runs',
            jsonb_build_object('run_id', p_args->>'run_id', 'http', p_args->>'http', 'wall_ms', v_wall, 'estimated_usd', v_est, 'by', left(coalesce(p_by, ''), 120), 'change', 's1324'),
            security.system_actor_id());
    return jsonb_build_object('run_id', p_args->>'run_id', 'estimated_usd', v_est);
  elsif p_action = 'list' then
    return jsonb_build_object('runs', (select coalesce(jsonb_agg(to_jsonb(r) - 'result' || jsonb_build_object('summary', r.result) order by r.started_at desc), '[]'::jsonb)
                                         from (select * from pipeline.cloudflare_reader_runs order by started_at desc limit 20) r));  -- fixed: listing bound
  end if;
  raise exception 'INVALID_INPUT: action is gate, record or list';
end $f$;
comment on function public.svc_cloudflare_reader_v1(text, jsonb, text) is 'CF-247 s1324: the gate and record of the isolated Cloudflare burst reader: the kill switch, one free named slot (cloudflare_reader.slots), the day and month estimates under their caps, and only a stored public university source copy; record writes the run''s result and estimated cost.';
revoke all on function public.svc_cloudflare_reader_v1(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_cloudflare_reader_v1(text, jsonb, text) to service_role;

do $post$
declare v jsonb := security.consumer_api_check_v1(); b record;
begin
  select * into b from pg_temp.s1324_guard;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from cron.job where active) <> b.cron_before then raise exception 'post-check: active job count changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'cloudflare\_reader.%') <> 7 then raise exception 'post-check: cloudflare_reader settings missing'; end if;
end $post$;
