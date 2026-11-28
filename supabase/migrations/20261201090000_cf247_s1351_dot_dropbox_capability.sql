-- CF-247 s1351 (S1-Build; Platform Admin direction PC-20261128-DOT-DROPBOX-POC, 28 Nov 2026: "one temporary high-entropy HTTPS upload capability URL ...
-- a narrowly scoped URL capability check on the existing endpoint; do not create a new connector, user account, public bucket, parallel pipeline").
-- A drop-off capability: one random token (256 bits) that lets its holder upload and finalise ONE agreed package (country, provider, package name)
-- in the private data-intake bucket through the existing dot-intake endpoint, until it expires or is revoked; it reads nothing else, lists
-- nothing, cannot overwrite or delete. Only its SHA-256 is kept. Issued and revoked by the Platform Admin (or the service role), each logged.
--   * pipeline.data_intake_capabilities; public.admin_data_intake_capability_issue_v1 (returns the token once) and ..._revoke_v1.
--   * public.svc_data_intake_v1: a capability_sha256 instead of user_id: the capability's scope replaces whatever the caller states; the rest
--     (switch, prechecks, derived immutable paths, READY manifest last, existing structured intake writer, audit) is unchanged.
--   * settings data_intake.capability_max_hours (the longest a capability may last) and data_intake.capability_max_bytes (its file ceiling).
-- G1: no job. G2: values are settings. G3: not the consumer API; 75/48 checked. Nothing dropped or deleted. No account, connector or bucket added.
-- Replaces: the signed-in-user-only gate of public.svc_data_intake_v1 (s1344), kept beside the capability path.
-- Retires: nothing.
create temp table s1351_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $e$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_data_intake_v1(text,jsonb)'::regprocedure)) <> 'b85d57dadca46e6a826c261fb9caf266' then
    raise exception 'pre-check: public.svc_data_intake_v1 changed since it was read (s1344 live md5 b85d57da)';
  end if;
end $e$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
  ('pipeline', 'data_intake.capability_max_hours', 'Data intake drop-off: longest capability',
   'A drop-off capability (one package, one random token) can be issued for at most this many hours.',
   'number', to_jsonb(48), 1, 168, 'hours', 1593, 'Services & limits', 'public.admin_data_intake_capability_issue_v1', 'CF-247 s1351 (PC-20261128-DOT-DROPBOX-POC)'),
  ('pipeline', 'data_intake.capability_max_bytes', 'Data intake drop-off: capability file ceiling',
   'The largest file a drop-off capability accepts (also never above Data intake drop-off: largest file).',
   'number', to_jsonb(26214400), 1024, 52428800, 'bytes', 1594, 'Services & limits', 'public.admin_data_intake_capability_issue_v1', 'CF-247 s1351')
on conflict do nothing;

create table pipeline.data_intake_capabilities (
  id uuid primary key default gen_random_uuid(),
  token_sha256 text not null unique check (token_sha256 ~ '^[0-9a-f]{64}$'),
  producer text not null default 'dot' check (producer = 'dot'),
  country text not null check (country ~ '^[A-Z]{2}$'),
  provider_id uuid not null,
  package text not null check (package ~ '^[a-z0-9][a-z0-9._-]{2,80}$'),
  max_bytes bigint not null check (max_bytes > 0),
  expires_at timestamptz not null,
  revoked_at timestamptz, revoked_by uuid, revoke_reason text,
  issued_by uuid not null, issued_at timestamptz not null default now(), issue_reason text not null,
  uses int not null default 0, last_used_at timestamptz
);
comment on table pipeline.data_intake_capabilities is 'CF-247 s1351: one-package drop-off capabilities for the dot-intake endpoint (PC-20261128-DOT-DROPBOX-POC): the SHA-256 of a random token, the one package it may upload and finalise, its file ceiling, expiry and revocation. The token itself is never stored.';
alter table pipeline.data_intake_capabilities enable row level security;
revoke all on pipeline.data_intake_capabilities from public, anon, authenticated;

create or replace function public.admin_data_intake_capability_issue_v1(p_country text, p_provider_id uuid, p_package text, p_hours int, p_reason text)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_by uuid; v_token text; v_id uuid; v_max int := security.pipeline_num_v1('data_intake.capability_max_hours', 48)::int; v_exp timestamptz;
begin
  if current_user = 'postgres' or coalesce(auth.role(), '') = 'service_role' then v_by := security.system_actor_id();
  elsif auth.uid() is not null and security.current_role_rank() >= 6 then v_by := auth.uid();
  else raise exception 'platform admin required' using errcode = '42501'; end if;
  if coalesce(length(btrim(p_reason)), 0) < 8 then raise exception 'INVALID_INPUT: a reason of at least 8 characters'; end if;
  if p_hours is null or p_hours < 1 or p_hours > v_max then raise exception 'INVALID_INPUT: hours 1 to %', v_max; end if;
  if upper(coalesce(p_country, '')) !~ '^[A-Z]{2}$' or coalesce(p_package, '') !~ '^[a-z0-9][a-z0-9._-]{2,80}$' then raise exception 'INVALID_INPUT: country and package'; end if;
  if not exists (select 1 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = p_provider_id and k.iso_alpha2 = upper(p_country)) then
    raise exception 'INVALID_INPUT: provider_id is not a provider in country %', upper(p_country);
  end if;
  if exists (select 1 from pipeline.data_intake_packages d where d.producer = 'dot' and d.provider_id = p_provider_id and d.package = p_package and d.status <> 'uploading') then
    raise exception 'INVALID_INPUT: package % is already finalised; name a new package', p_package;
  end if;
  v_token := 'dic_' || encode(extensions.gen_random_bytes(32), 'hex');  -- 256 random bits
  v_exp := now() + make_interval(hours => p_hours);
  insert into pipeline.data_intake_capabilities (token_sha256, country, provider_id, package, max_bytes, expires_at, issued_by, issue_reason)
  values (encode(extensions.digest(v_token, 'sha256'), 'hex'), upper(p_country), p_provider_id, p_package,
          least(security.pipeline_num_v1('data_intake.capability_max_bytes', 26214400), security.pipeline_num_v1('data_intake.max_bytes', 26214400))::bigint, v_exp, v_by, left(p_reason, 300))
  returning id into v_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('intake', 'data_intake_capability_issued', 'pipeline.data_intake_capabilities',
          jsonb_build_object('capability_id', v_id, 'country', upper(p_country), 'provider_id', p_provider_id, 'package', p_package, 'expires_at', v_exp, 'reason', left(p_reason, 300), 'change', 's1351'), v_by);
  return jsonb_build_object('capability_id', v_id, 'token', v_token, 'expires_at', v_exp, 'country', upper(p_country), 'provider_id', p_provider_id, 'package', p_package,
                            'shown_once', 'The token is not stored; only its SHA-256 is kept.');
end $f$;
revoke all on function public.admin_data_intake_capability_issue_v1(text, uuid, text, int, text) from public, anon;
grant execute on function public.admin_data_intake_capability_issue_v1(text, uuid, text, int, text) to authenticated, service_role;
comment on function public.admin_data_intake_capability_issue_v1(text, uuid, text, int, text) is 'CF-247 s1351: issues one drop-off capability for one package (Platform Admin or service role), returns its token once, logs it; at most data_intake.capability_max_hours.';

create or replace function public.admin_data_intake_capability_revoke_v1(p_capability_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_by uuid; v_n int;
begin
  if current_user = 'postgres' or coalesce(auth.role(), '') = 'service_role' then v_by := security.system_actor_id();
  elsif auth.uid() is not null and security.current_role_rank() >= 6 then v_by := auth.uid();
  else raise exception 'platform admin required' using errcode = '42501'; end if;
  if coalesce(length(btrim(p_reason)), 0) < 8 then raise exception 'INVALID_INPUT: a reason of at least 8 characters'; end if;
  update pipeline.data_intake_capabilities set revoked_at = now(), revoked_by = v_by, revoke_reason = left(p_reason, 300) where id = p_capability_id and revoked_at is null;
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('intake', 'data_intake_capability_revoked', 'pipeline.data_intake_capabilities', jsonb_build_object('capability_id', p_capability_id, 'revoked', v_n, 'reason', left(p_reason, 300), 'change', 's1351'), v_by);
  return jsonb_build_object('capability_id', p_capability_id, 'revoked', v_n = 1);
end $f$;
revoke all on function public.admin_data_intake_capability_revoke_v1(uuid, text) from public, anon;
grant execute on function public.admin_data_intake_capability_revoke_v1(uuid, text) to authenticated, service_role;
comment on function public.admin_data_intake_capability_revoke_v1(uuid, text) is 'CF-247 s1351: revokes a drop-off capability at once (Platform Admin or service role), logged.';

create or replace function public.svc_data_intake_v1(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_user uuid; v_prov uuid; v_cc text; v_pkg text; v_p record; v_out jsonb; v_missing int; v_bad int; v_root text; v_days int; v_exp timestamptz;
  v_cap pipeline.data_intake_capabilities%rowtype; v_capmax bigint;
  v_check boolean := p_action in ('precheck_upload', 'precheck_finalise');
  v_act text := replace(p_action, 'precheck_', '');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_action not in ('gate', 'precheck_upload', 'upload', 'precheck_finalise', 'finalise', 'status') then
    raise exception 'INVALID_INPUT: action is gate, precheck_upload, upload, precheck_finalise, finalise or status';
  end if;
  if security.pipeline_num_v1('data_intake.on', 0) < 1 then return jsonb_build_object('ok', false, 'held', 'HELD:SWITCHED_OFF'); end if;
  if p_args ? 'capability_sha256' then
    -- s1351 (PC-20261128-DOT-DROPBOX-POC): a one-package capability instead of a signed-in user: active, unexpired, not revoked; its scope wins
    select * into v_cap from pipeline.data_intake_capabilities c
     where c.token_sha256 = lower(coalesce(p_args->>'capability_sha256', '')) and c.revoked_at is null and c.expires_at > now();
    if v_cap.id is null then return jsonb_build_object('ok', false, 'held', 'HELD:CAPABILITY_INVALID'); end if;
    v_user := v_cap.issued_by; v_exp := v_cap.expires_at; v_capmax := v_cap.max_bytes;
    p_args := p_args || jsonb_build_object('country', v_cap.country, 'provider_id', v_cap.provider_id, 'package', v_cap.package);
    if p_action = 'gate' then
      update pipeline.data_intake_capabilities set uses = uses + 1, last_used_at = now() where id = v_cap.id;
    end if;
  else
    begin v_user := (p_args->>'user_id')::uuid; exception when others then v_user := null; end;
    -- the identity: an active dot_submitter assignment whose expiry is set and no further ahead than data_intake.role_max_days
    v_days := security.pipeline_num_v1('data_intake.role_max_days', 14)::int;
    select min(ur.expires_at) into v_exp from security.user_roles ur join security.roles r on r.code = ur.role_code
     where ur.user_id = v_user and ur.role_code = 'dot_submitter' and r.status = 'active' and (ur.expires_at is null or ur.expires_at > now());
    if v_user is null or not exists (select 1 from security.user_roles ur join security.roles r on r.code = ur.role_code
                                      where ur.user_id = v_user and ur.role_code = 'dot_submitter' and r.status = 'active'
                                        and (ur.expires_at is null or ur.expires_at > now())) then
      return jsonb_build_object('ok', false, 'held', 'HELD:NOT_DOT_SUBMITTER');
    end if;
    if exists (select 1 from security.user_roles ur where ur.user_id = v_user and ur.role_code = 'dot_submitter'
                and (ur.expires_at is null or ur.expires_at > now() + make_interval(days => v_days))) then
      return jsonb_build_object('ok', false, 'held', 'HELD:EXPIRY_NOT_BOUNDED', 'max_days', v_days);  -- no open-ended or over-long assignment
    end if;
  end if;
  if p_action = 'gate' then
    return jsonb_build_object('ok', true, 'producer', 'dot', 'expires_at', v_exp,
      'max_bytes', least(security.pipeline_num_v1('data_intake.max_bytes', 26214400)::bigint, coalesce(v_capmax, 9223372036854775807)),
      'scope', case when v_cap.id is null then null else jsonb_build_object('country', v_cap.country, 'provider_id', v_cap.provider_id, 'package', v_cap.package) end);
  end if;
  -- package identity: country, provider (in that country), package name; the path is derived, never taken from the caller
  v_cc := upper(coalesce(p_args->>'country', '')); v_pkg := coalesce(p_args->>'package', '');
  begin v_prov := (p_args->>'provider_id')::uuid; exception when others then v_prov := null; end;
  if v_cc !~ '^[A-Z]{2}$' or v_pkg !~ '^[a-z0-9][a-z0-9._-]{2,80}$' or v_prov is null then
    raise exception 'INVALID_INPUT: country (2 letters), provider_id and package (3 to 81 lower-case letters, digits, dot, dash or underscore)';
  end if;
  if not exists (select 1 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = v_prov and k.iso_alpha2 = v_cc) then
    raise exception 'INVALID_INPUT: provider_id is not a provider in country %', v_cc;
  end if;
  v_root := 'dot/' || v_cc || '/' || v_prov::text || '/' || v_pkg || '/';
  if p_action <> 'status' and not v_check then
    perform pg_advisory_xact_lock(hashtextextended('data_intake:' || v_prov::text || ':' || v_pkg, 0));  -- one writer per package at a time
  end if;
  select * into v_p from pipeline.data_intake_packages where producer = 'dot' and provider_id = v_prov and package = v_pkg;
  if p_action = 'status' then
    return jsonb_build_object('ok', true, 'package', v_pkg, 'status', coalesce(v_p.status, 'none'), 'receipt', v_p.receipt, 'error', v_p.error,
      'attempts', coalesce(v_p.attempts, 0), 'last_attempt_at', v_p.last_attempt_at,
      'files', (select count(*) from pipeline.data_intake_files f where f.package_id = v_p.id));
  end if;
  if v_act = 'upload' then
    if coalesce(p_args->>'sha256', '') !~ '^[0-9a-f]{64}$' or coalesce(p_args->>'path', '') <> v_root || 'files/' || (p_args->>'sha256') || '.' || coalesce(p_args->>'ext', '')
       or coalesce(p_args->>'ext', '') not in ('pdf', 'html', 'json', 'jsonl', 'txt') or coalesce((p_args->>'bytes')::bigint, 0) < 1 then
      raise exception 'INVALID_INPUT: sha256, extension, size and stored path';
    end if;
    if v_p.id is not null and v_p.status <> 'uploading' then
      raise exception 'INVALID_INPUT: package % is finalised (%) and takes no more files', v_pkg, v_p.status;
    end if;
    if v_check then return jsonb_build_object('ok', true, 'path', p_args->>'path'); end if;
    if v_p.id is null then
      insert into pipeline.data_intake_packages (producer, country, provider_id, package, created_by) values ('dot', v_cc, v_prov, v_pkg, v_user)
      returning * into v_p;
    end if;
    insert into pipeline.data_intake_files (package_id, path, sha256, bytes, mime, source_url, uploaded_by)
    values (v_p.id, p_args->>'path', p_args->>'sha256', (p_args->>'bytes')::bigint, coalesce(p_args->>'mime', ''), nullif(p_args->>'source_url', ''), v_user)
    on conflict (package_id, sha256) do nothing;
    get diagnostics v_bad = row_count;
    update pipeline.data_intake_packages set updated_at = now() where id = v_p.id;
    return jsonb_build_object('ok', true, 'package', v_pkg, 'path', p_args->>'path', 'sha256', p_args->>'sha256', 'replay', v_bad = 0);
  end if;
  -- finalise: the READY manifest, written last
  if coalesce(p_args->>'manifest_sha256', '') !~ '^[0-9a-f]{64}$' or coalesce(p_args->>'manifest_path', '') <> v_root || 'manifest-' || (p_args->>'manifest_sha256') || '.json' then
    raise exception 'INVALID_INPUT: manifest sha256 and stored path';
  end if;
  if v_p.id is not null and v_p.status = 'received' then
    if v_p.manifest_sha256 is distinct from p_args->>'manifest_sha256' then
      raise exception 'INVALID_INPUT: package % was finalised with another manifest (%); a changed manifest needs a new package', v_pkg, left(v_p.manifest_sha256, 12);
    end if;
    return jsonb_build_object('ok', true, 'package', v_pkg, 'status', 'received', 'replay', true, 'receipt', v_p.receipt);
  end if;
  if v_p.id is null then raise exception 'INVALID_INPUT: package % has no uploaded files', v_pkg; end if;
  if v_p.status = 'refused' then raise exception 'INVALID_INPUT: package % was refused: %', v_pkg, v_p.error; end if;
  if jsonb_typeof(p_args->'manifest'->'files') <> 'array' or jsonb_typeof(p_args->'manifest'->'items') <> 'array' then
    raise exception 'INVALID_INPUT: the manifest has files and items arrays';
  end if;
  select count(*) into v_missing from jsonb_array_elements(p_args->'manifest'->'files') m
   where not exists (select 1 from pipeline.data_intake_files f where f.package_id = v_p.id and f.sha256 = m->>'sha256');
  select count(*) into v_bad from jsonb_array_elements(p_args->'manifest'->'items') x where coalesce(x->>'provider_id', '') <> v_prov::text;
  if v_missing > 0 or v_bad > 0 or jsonb_array_length(p_args->'manifest'->'files') = 0 or jsonb_array_length(p_args->'manifest'->'items') = 0 then
    -- an incomplete manifest is held, not refused: the package stays open so the missing originals can still arrive
    if not v_check then update pipeline.data_intake_packages set attempts = attempts + 1, last_attempt_at = now(), updated_at = now(),
                          error = 'HELD:MANIFEST_INCOMPLETE' where id = v_p.id; end if;
    return jsonb_build_object('ok', false, 'held', 'HELD:MANIFEST_INCOMPLETE', 'package', v_pkg, 'files_missing', v_missing, 'items_other_provider', v_bad);
  end if;
  if v_check then return jsonb_build_object('ok', true, 'path', p_args->>'manifest_path'); end if;
  v_out := public.svc_structured_intake_v1('submit', jsonb_build_object('submitter', 'dot', 'batch', v_pkg, 'items', p_args->'manifest'->'items'),
                                           'data-intake ' || v_root || ' ' || left(p_args->>'manifest_sha256', 12));
  update pipeline.data_intake_packages set status = 'received', manifest_path = p_args->>'manifest_path', manifest_sha256 = p_args->>'manifest_sha256',
         receipt = v_out, error = null, attempts = attempts + 1, last_attempt_at = now(), updated_at = now() where id = v_p.id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('intake', 'data_intake_finalise', 'pipeline.data_intake_packages',
          jsonb_build_object('package_id', v_p.id, 'user_id', v_user, 'root', v_root, 'manifest_sha256', p_args->>'manifest_sha256', 'receipt', v_out, 'change', 's1344'),
          security.system_actor_id());
  -- candidate-level outcome: each candidate is received, a duplicate or refused with its reason (the receipt); proof and admission follow
  return jsonb_build_object('ok', true, 'package', v_pkg, 'status', 'received', 'replay', false, 'receipt', v_out,
    'candidates', jsonb_build_object('received', coalesce((v_out->>'received')::int, 0), 'duplicates', coalesce((v_out->>'duplicates')::int, 0),
                                     'refused', coalesce(jsonb_array_length(v_out->'refused'), 0)));
end $f$;
revoke all on function public.svc_data_intake_v1(text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_data_intake_v1(text, jsonb) to service_role;

do $e$
declare v jsonb := security.consumer_api_check_v1(); g record;
begin
  select * into g from s1351_guard;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API baseline changed: %', v; end if;
  if (select count(*) from cron.job where active) <> g.cron_before then raise exception 'post-check: active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> g.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (public.svc_data_intake_v1('gate', jsonb_build_object('capability_sha256', repeat('0', 64)))->>'held') is distinct from 'HELD:CAPABILITY_INVALID' then raise exception 'post-check: an unknown capability passes the gate'; end if;
  if has_function_privilege('authenticated', 'public.svc_data_intake_v1(text, jsonb)', 'EXECUTE') then raise exception 'post-check: svc_data_intake_v1 is executable by authenticated'; end if;
end $e$;
