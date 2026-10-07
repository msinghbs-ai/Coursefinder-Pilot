-- CF-247, 7 Oct 2026: automatic adapter build, part 2 of 4: the build table and the admin function (start, stop, read, states). See 20261007001900 for the decisions.

create table if not exists pipeline.adapter_autobuilds (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  status text not null default 'queued' check (status in ('queued', 'finding_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'done', 'failed', 'stopped')),
  step_started_at timestamptz not null default now(),
  fc_run_id uuid, draft_id uuid,
  credits_cap int not null default 150,
  note text, result jsonb not null default '{}'::jsonb, error text,
  requested_by uuid not null, reason text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index if not exists adapter_autobuilds_provider_idx on pipeline.adapter_autobuilds(provider_id, created_at desc);
create unique index if not exists adapter_autobuilds_one_active on pipeline.adapter_autobuilds(provider_id) where status not in ('done', 'failed', 'stopped');
alter table pipeline.adapter_autobuilds enable row level security;
revoke all on pipeline.adapter_autobuilds from public, anon, authenticated;

create or replace function security.adapter_autobuild_state_v1(p_provider_id uuid)
returns jsonb language sql stable set search_path to '' as $f$
  select jsonb_build_object(
    'adapter', (select case when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end from pipeline.uni_adapters u where u.provider_id = p_provider_id),
    'admit_fields', (select u.admit_fields from pipeline.uni_adapters u where u.provider_id = p_provider_id),
    'build', (select jsonb_build_object('id', b.id, 'status', b.status, 'note', b.note, 'error', b.error, 'result', b.result, 'created_at', b.created_at, 'updated_at', b.updated_at)
                from pipeline.adapter_autobuilds b where b.provider_id = p_provider_id order by b.created_at desc limit 1))
$f$;

create or replace function public.admin_adapter_autobuild(p_action text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_today int; v_cap int; v_id uuid; v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'PIM Operator or Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'states' then
    select coalesce(jsonb_object_agg(x.id, security.adapter_autobuild_state_v1(x.id::uuid)), '{}'::jsonb) into v
      from (select distinct jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) id limit 200) x;
    return v;
  end if;
  if p_action = 'read' then
    return security.adapter_autobuild_state_v1(v_pid) || jsonb_build_object('can_manage', v_rank >= 6,
      'today', (select count(*) from pipeline.adapter_autobuilds b where (b.created_at at time zone 'Australia/Melbourne')::date = (now() at time zone 'Australia/Melbourne')::date),
      'per_day', (security.firecrawl_setting('autobuild_per_day') #>> '{}')::int,
      'model', security.firecrawl_setting('builder_model') #>> '{}');
  end if;
  if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'start' then
    if not exists (select 1 from catalogue.providers where id = v_pid) then raise exception 'unknown provider'; end if;
    if exists (select 1 from pipeline.uni_adapters u where u.provider_id = v_pid and u.admit) then raise exception 'this provider already has an admitting adapter: change it in the builder instead'; end if;
    if exists (select 1 from pipeline.adapter_autobuilds b where b.provider_id = v_pid and b.status not in ('done', 'failed', 'stopped')) then raise exception 'a build is already running for this provider'; end if;
    v_today := (select count(*) from pipeline.adapter_autobuilds b where (b.created_at at time zone 'Australia/Melbourne')::date = (now() at time zone 'Australia/Melbourne')::date);
    v_cap := coalesce((security.firecrawl_setting('autobuild_per_day') #>> '{}')::int, 25);
    if v_today >= v_cap then raise exception 'the automatic builds for today are used (% of %). It is a setting under Adapter builder', v_today, v_cap; end if;
    insert into pipeline.adapter_autobuilds(provider_id, credits_cap, requested_by, reason, note)
    values (v_pid, coalesce((security.firecrawl_setting('autobuild_credits') #>> '{}')::int, 150), auth.uid(), v_reason, 'Waiting to start (within 2 minutes).')
    returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_autobuild_start', v_pid::text, jsonb_build_object('build_id', v_id, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'build_id', v_id);
  elsif p_action = 'stop' then
    update pipeline.adapter_autobuilds set status = 'stopped', note = 'Stopped by a Platform Admin: ' || v_reason, updated_at = now()
     where provider_id = v_pid and status not in ('done', 'failed', 'stopped') returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_autobuild_stop', v_pid::text, jsonb_build_object('build_id', v_id, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', v_id is not null);
  end if;
  raise exception 'unknown action';
end $f$;
revoke all on function public.admin_adapter_autobuild(text, jsonb) from public, anon;
grant execute on function public.admin_adapter_autobuild(text, jsonb) to authenticated, service_role;