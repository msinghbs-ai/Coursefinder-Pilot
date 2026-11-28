-- CF-247 s1344 (S1-Build; SS-Programme-Control 28 Nov 2026 PC-20261128-DOT-STORAGE-IMPLEMENT and PC-20261128-1130-DOT-STORAGE: "Prepare smallest endpoint
-- off/guarded and one consolidated exact Admin action for narrow identity/expiry, actual DOT connector and kill switch").
-- Prepared switched OFF. Nothing is granted to anyone: no user is assigned the new role here; the Platform Admin's one action (admin docs) does that.
-- What it adds:
--   * role dot_submitter (rank 0, the same rank as a signed-in user with no role): it names the DOT identity for the gate and grants nothing else.
--     Proven 28 Nov 2026 (rolled back, a signed-in rank-0 user): of 401 public functions granted to authenticated, 295 check a rank or the service
--     role and the other 106 refuse or reach only 4 reads (integration status, a Layer 4 entity view, publication state, scholarship AI control) and
--     its own UI error report; pipeline and ref tables are refused; storage shows 0 objects and refuses writes (row-level security).
--   * settings dot_intake.on (0: off) and dot_intake.max_bytes (one JSONL file).
--   * public.svc_dot_intake_v1 (service role only, called by the edge function dot-intake after it has checked the caller's sign-in, the file's
--     SHA-256 and stored it once at staging-boost/dot/<package>/<sha256>.jsonl): the switch, an active unexpired dot_submitter assignment, the package
--     name; then the existing writer public.svc_structured_intake_v1 submit (submitter dot), whose receipt it returns, and one audit row.
--     It writes no canonical row, no evidence and activates nothing; the existing proof, binding and admission rules decide as for every intake.
-- G1: no job. G2: both values are settings. G3: not the consumer API; 75/48 checked. Locks, Layer 4 and cron checked. $0. Nothing dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.
create temp table s1344_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before,
       (select count(*) from security.user_roles) as assignments_before;

do $e$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $e$;

insert into security.roles (code, name, rank, description, status)
values ('dot_submitter', 'DOT evidence submitter', 0,
        'Submits structured intake packages through the dot-intake endpoint only (s1344). Rank 0: no catalogue, admin, table or storage access.', 'active')
on conflict (code) do nothing;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
  ('pipeline', 'dot_intake.on', 'DOT intake endpoint: on',
   'The kill switch of the dot-intake endpoint. 0: every DOT upload is refused (HELD:SWITCHED_OFF) and the Drive pickup route stays the only route.',
   'number', to_jsonb(0), 0, 1, 'switch', 1590, 'Services & limits', 'public.svc_dot_intake_v1; edge function dot-intake', 'CF-247 s1344 (PC-20261128-DOT-STORAGE-IMPLEMENT)'),
  ('pipeline', 'dot_intake.max_bytes', 'DOT intake endpoint: largest file',
   'The largest JSONL candidate file the dot-intake endpoint accepts.',
   'number', to_jsonb(1048576), 1024, 52428800, 'bytes', 1591, 'Services & limits', 'edge function dot-intake (through svc_dot_intake_v1 gate)', 'CF-247 s1344')
on conflict do nothing;

create or replace function public.svc_dot_intake_v1(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_user uuid; v_pkg text; v_out jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_action not in ('gate', 'submit') then raise exception 'INVALID_INPUT: action is gate or submit'; end if;
  if security.pipeline_num_v1('dot_intake.on', 0) < 1 then return jsonb_build_object('ok', false, 'held', 'HELD:SWITCHED_OFF'); end if;
  begin v_user := (p_args->>'user_id')::uuid; exception when others then v_user := null; end;
  if v_user is null or not exists (select 1 from security.user_roles ur join security.roles r on r.code = ur.role_code
                                    where ur.user_id = v_user and ur.role_code = 'dot_submitter' and r.status = 'active'
                                      and (ur.expires_at is null or ur.expires_at > now())) then
    return jsonb_build_object('ok', false, 'held', 'HELD:NOT_DOT_SUBMITTER');
  end if;
  if p_action = 'gate' then
    return jsonb_build_object('ok', true, 'max_bytes', security.pipeline_num_v1('dot_intake.max_bytes', 1048576)::bigint);
  end if;
  v_pkg := coalesce(p_args->>'package', '');
  if v_pkg !~ '^[a-z0-9][a-z0-9._-]{2,80}$' then raise exception 'INVALID_INPUT: package is 3 to 81 lower-case letters, digits, dot, dash or underscore'; end if;
  if coalesce(p_args->>'sha256', '') !~ '^[0-9a-f]{64}$' or coalesce(p_args->>'path', '') !~ '^dot/[a-z0-9._-]+/[0-9a-f]{64}\.jsonl$' then raise exception 'INVALID_INPUT: sha256 and stored path'; end if;
  v_out := public.svc_structured_intake_v1('submit', jsonb_build_object('submitter', 'dot', 'batch', v_pkg, 'items', p_args->'items'),
                                           'dot-intake ' || v_user::text || ' ' || left(p_args->>'sha256', 12));
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('intake', 'dot_intake_submit', 'pipeline.structured_intake_items',
          jsonb_build_object('user_id', v_user, 'package', v_pkg, 'sha256', p_args->>'sha256', 'path', p_args->>'path', 'receipt', v_out, 'change', 's1344'),
          security.system_actor_id());
  return jsonb_build_object('ok', true, 'package', v_pkg, 'sha256', p_args->>'sha256', 'path', p_args->>'path', 'receipt', v_out);
end $f$;
revoke all on function public.svc_dot_intake_v1(text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_dot_intake_v1(text, jsonb) to service_role;
comment on function public.svc_dot_intake_v1(text, jsonb) is 'CF-247 s1344: gate and submit of the dot-intake endpoint (off by default, dot_intake.on): an active unexpired dot_submitter assignment, then the existing structured intake writer (submitter dot); returns its receipt and writes one audit row. No canonical write, no evidence, no activation.';

do $e$
declare v jsonb := security.consumer_api_check_v1(); g record;
begin
  select * into g from s1344_guard;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API baseline changed: %', v; end if;
  if (select count(*) from cron.job where active) <> g.cron_before then raise exception 'post-check: active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> g.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from security.user_roles) <> g.assignments_before then raise exception 'post-check: a role was assigned'; end if;
  if security.pipeline_num_v1('dot_intake.on', 1) <> 0 then raise exception 'post-check: the DOT intake endpoint must ship off'; end if;
  if has_function_privilege('authenticated', 'public.svc_dot_intake_v1(text, jsonb)', 'EXECUTE') then raise exception 'post-check: svc_dot_intake_v1 is executable by authenticated'; end if;
end $e$;
