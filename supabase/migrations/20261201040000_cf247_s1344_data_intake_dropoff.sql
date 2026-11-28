-- CF-247 s1344 (S1-Build; SS-Programme-Control 28 Nov 2026 PC-20261128-DOT-STORAGE-APPROVED: "dedicated private data-intake bucket, restricted DOT
-- upload identity, automatic Edge Function processing and existing Admin UI controls"; supersedes the staging-boost/dot proposal).
-- Increment 1: the isolated drop-off and its records, used only through the edge function dot-intake.
--   * bucket data-intake (private, no storage policies: only the service role, through the edge function, writes or reads it; never BOOST).
--     Immutable paths <producer>/<country>/<provider id>/<package>/files/<sha256>.<ext> and .../manifest-<sha256>.json (written last).
--   * pipeline.data_intake_packages and pipeline.data_intake_files: one row per package and per uploaded original (actual SHA-256, bytes, MIME,
--     the source address DOT states). A finalised package takes no more files (immutable).
--   * role dot_submitter (rank 0, assigned to no one here): names the DOT identity for the gate and grants nothing else. Proven 28 Nov 2026
--     (rolled back) that a signed-in rank-0 user is refused by every admin function, table and bucket (admin docs s1344 Admin action).
--   * settings data_intake.on (the kill switch, on) and data_intake.max_bytes; the identity is what opens it: no one holds the role until the
--     Platform Admin assigns it with an expiry.
--   * public.svc_data_intake_v1 (service role only): gate, upload (records a stored original), finalise (the READY manifest: every listed original
--     must be recorded; each candidate's provider must be the package's; then the existing writer svc_structured_intake_v1 submit, submitter dot,
--     whose receipt is kept on the package), status. One audit row per finalise.
-- It writes no canonical row and activates nothing: the existing proof, binding, Layer 4, manual locks and admission rules decide. Nothing is
-- deleted; clearing a package from the active view (cleared_at) never removes its files.
-- G1: no job (finalise runs on the authenticated call). G2: both values are settings. G3: not the consumer API; 75/48 checked. $0.
-- Replaces: nothing (the staging-boost/dot proposal was never shipped).
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

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('data-intake', 'data-intake', false, 52428800,  -- fixed: the bucket's own ceiling; the endpoint applies data_intake.max_bytes below it
        array['application/pdf', 'text/html', 'application/json', 'application/x-ndjson', 'text/plain'])
on conflict (id) do nothing;

insert into security.roles (code, name, rank, description, status)
values ('dot_submitter', 'DOT evidence submitter', 0,
        'Uploads and finalises packages through the dot-intake endpoint only (s1344). Rank 0: no catalogue, admin, table or storage access.', 'active')
on conflict (code) do nothing;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
  ('pipeline', 'data_intake.on', 'Data intake drop-off: on',
   'The kill switch of the dot-intake endpoint. 0: every upload and finalise is refused (HELD:SWITCHED_OFF). Only a person holding an active, unexpired producer role (dot_submitter) can use it when on.',
   'number', to_jsonb(1), 0, 1, 'switch', 1590, 'Services & limits', 'public.svc_data_intake_v1; edge function dot-intake', 'CF-247 s1344 (PC-20261128-DOT-STORAGE-APPROVED)'),
  ('pipeline', 'data_intake.max_bytes', 'Data intake drop-off: largest file',
   'The largest original or manifest the dot-intake endpoint accepts.',
   'number', to_jsonb(26214400), 1024, 52428800, 'bytes', 1591, 'Services & limits', 'edge function dot-intake (through svc_data_intake_v1 gate)', 'CF-247 s1344')
on conflict do nothing;

create table pipeline.data_intake_packages (
  id uuid primary key default gen_random_uuid(),
  producer text not null check (producer ~ '^[a-z]{2,20}$'),
  country text not null check (country ~ '^[A-Z]{2}$'),
  provider_id uuid not null,
  package text not null check (package ~ '^[a-z0-9][a-z0-9._-]{2,80}$'),
  status text not null default 'uploading' check (status in ('uploading', 'received', 'refused')),
  manifest_path text, manifest_sha256 text, receipt jsonb, error text,
  attempts int not null default 0, last_attempt_at timestamptz,
  created_by uuid not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  cleared_at timestamptz,
  unique (producer, provider_id, package)
);
comment on table pipeline.data_intake_packages is 'CF-247 s1344: one package uploaded by a producer (DOT) to the private data-intake bucket: uploading until its READY manifest is finalised, then received (the structured intake receipt kept here) or refused (the reason). Immutable once finalised; cleared_at only hides it from the active view, nothing is deleted.';
create table pipeline.data_intake_files (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references pipeline.data_intake_packages(id),
  path text not null unique,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  bytes bigint not null check (bytes > 0),
  mime text not null,
  source_url text check (source_url is null or source_url ~ '^https://'),
  uploaded_by uuid not null, uploaded_at timestamptz not null default now(),
  unique (package_id, sha256)
);
comment on table pipeline.data_intake_files is 'CF-247 s1344: one original uploaded to the data-intake bucket for a package: the SHA-256 the server computed from the actual bytes, size, MIME and the source address the producer states. Never overwritten or deleted.';
alter table pipeline.data_intake_packages enable row level security;
alter table pipeline.data_intake_files enable row level security;
revoke all on pipeline.data_intake_packages, pipeline.data_intake_files from public, anon, authenticated;

create or replace function public.svc_data_intake_v1(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_user uuid; v_prov uuid; v_cc text; v_pkg text; v_p record; v_out jsonb; v_missing int; v_bad int; v_new boolean; v_root text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_action not in ('gate', 'upload', 'finalise', 'status') then raise exception 'INVALID_INPUT: action is gate, upload, finalise or status'; end if;
  if security.pipeline_num_v1('data_intake.on', 0) < 1 then return jsonb_build_object('ok', false, 'held', 'HELD:SWITCHED_OFF'); end if;
  begin v_user := (p_args->>'user_id')::uuid; exception when others then v_user := null; end;
  if v_user is null or not exists (select 1 from security.user_roles ur join security.roles r on r.code = ur.role_code
                                    where ur.user_id = v_user and ur.role_code = 'dot_submitter' and r.status = 'active'
                                      and (ur.expires_at is null or ur.expires_at > now())) then
    return jsonb_build_object('ok', false, 'held', 'HELD:NOT_DOT_SUBMITTER');
  end if;
  if p_action = 'gate' then
    return jsonb_build_object('ok', true, 'producer', 'dot', 'max_bytes', security.pipeline_num_v1('data_intake.max_bytes', 26214400)::bigint);
  end if;
  -- package identity: country, provider (the provider is in that country), package name; the path is derived, never taken from the caller
  v_cc := upper(coalesce(p_args->>'country', '')); v_pkg := coalesce(p_args->>'package', '');
  begin v_prov := (p_args->>'provider_id')::uuid; exception when others then v_prov := null; end;
  if v_cc !~ '^[A-Z]{2}$' or v_pkg !~ '^[a-z0-9][a-z0-9._-]{2,80}$' or v_prov is null then
    raise exception 'INVALID_INPUT: country (2 letters), provider_id and package (3 to 81 lower-case letters, digits, dot, dash or underscore)';
  end if;
  if not exists (select 1 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = v_prov and k.iso_alpha2 = v_cc) then
    raise exception 'INVALID_INPUT: provider_id is not a provider in country %', v_cc;
  end if;
  v_root := 'dot/' || v_cc || '/' || v_prov::text || '/' || v_pkg || '/';
  select * into v_p from pipeline.data_intake_packages where producer = 'dot' and provider_id = v_prov and package = v_pkg;
  if p_action = 'status' then
    return jsonb_build_object('ok', true, 'package', v_pkg, 'status', coalesce(v_p.status, 'none'), 'receipt', v_p.receipt, 'error', v_p.error,
      'files', (select count(*) from pipeline.data_intake_files f where f.package_id = v_p.id));
  end if;
  if p_action = 'upload' then
    if coalesce(p_args->>'sha256', '') !~ '^[0-9a-f]{64}$' or coalesce(p_args->>'path', '') <> v_root || 'files/' || (p_args->>'sha256') || '.' || coalesce(p_args->>'ext', '')
       or coalesce(p_args->>'ext', '') not in ('pdf', 'html', 'json', 'jsonl', 'txt') or coalesce((p_args->>'bytes')::bigint, 0) < 1 then
      raise exception 'INVALID_INPUT: sha256, extension, size and stored path';
    end if;
    if v_p.id is null then
      insert into pipeline.data_intake_packages (producer, country, provider_id, package, created_by) values ('dot', v_cc, v_prov, v_pkg, v_user)
      returning * into v_p;
    elsif v_p.status <> 'uploading' then
      raise exception 'INVALID_INPUT: package % is finalised (%) and takes no more files', v_pkg, v_p.status;
    end if;
    insert into pipeline.data_intake_files (package_id, path, sha256, bytes, mime, source_url, uploaded_by)
    values (v_p.id, p_args->>'path', p_args->>'sha256', (p_args->>'bytes')::bigint, coalesce(p_args->>'mime', ''), nullif(p_args->>'source_url', ''), v_user)
    on conflict (package_id, sha256) do nothing;
    get diagnostics v_bad = row_count;
    update pipeline.data_intake_packages set updated_at = now() where id = v_p.id;
    return jsonb_build_object('ok', true, 'package', v_pkg, 'path', p_args->>'path', 'sha256', p_args->>'sha256', 'replay', v_bad = 0);
  end if;
  -- finalise: the READY manifest, written last
  if v_p.id is null then raise exception 'INVALID_INPUT: package % has no uploaded files', v_pkg; end if;
  if v_p.status = 'received' then
    return jsonb_build_object('ok', true, 'package', v_pkg, 'status', 'received', 'replay', true, 'receipt', v_p.receipt);
  end if;
  if v_p.status = 'refused' then raise exception 'INVALID_INPUT: package % was refused: %', v_pkg, v_p.error; end if;
  if coalesce(p_args->>'manifest_sha256', '') !~ '^[0-9a-f]{64}$' or coalesce(p_args->>'manifest_path', '') <> v_root || 'manifest-' || (p_args->>'manifest_sha256') || '.json'
     or jsonb_typeof(p_args->'manifest'->'files') <> 'array' or jsonb_typeof(p_args->'manifest'->'items') <> 'array' then
    raise exception 'INVALID_INPUT: manifest (files and items arrays), its sha256 and stored path';
  end if;
  select count(*) into v_missing from jsonb_array_elements(p_args->'manifest'->'files') m
   where not exists (select 1 from pipeline.data_intake_files f where f.package_id = v_p.id and f.sha256 = m->>'sha256');
  select count(*) into v_bad from jsonb_array_elements(p_args->'manifest'->'items') x where coalesce(x->>'provider_id', '') <> v_prov::text;
  update pipeline.data_intake_packages set attempts = attempts + 1, last_attempt_at = now(), updated_at = now() where id = v_p.id;
  if v_missing > 0 or v_bad > 0 or jsonb_array_length(p_args->'manifest'->'files') = 0 then
    -- an incomplete manifest is held, not refused: the package stays uploading so the missing originals can still arrive
    return jsonb_build_object('ok', false, 'held', 'HELD:MANIFEST_INCOMPLETE', 'package', v_pkg, 'files_missing', v_missing, 'items_other_provider', v_bad);
  end if;
  v_out := public.svc_structured_intake_v1('submit', jsonb_build_object('submitter', 'dot', 'batch', v_pkg, 'items', p_args->'manifest'->'items'),
                                           'data-intake ' || v_root || ' ' || left(p_args->>'manifest_sha256', 12));
  update pipeline.data_intake_packages set status = 'received', manifest_path = p_args->>'manifest_path', manifest_sha256 = p_args->>'manifest_sha256',
         receipt = v_out, error = null, updated_at = now() where id = v_p.id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('intake', 'data_intake_finalise', 'pipeline.data_intake_packages',
          jsonb_build_object('package_id', v_p.id, 'user_id', v_user, 'root', v_root, 'manifest_sha256', p_args->>'manifest_sha256', 'receipt', v_out, 'change', 's1344'),
          security.system_actor_id());
  return jsonb_build_object('ok', true, 'package', v_pkg, 'status', 'received', 'replay', false, 'receipt', v_out);
end $f$;
revoke all on function public.svc_data_intake_v1(text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_data_intake_v1(text, jsonb) to service_role;
comment on function public.svc_data_intake_v1(text, jsonb) is 'CF-247 s1344: gate, upload, finalise and status of the dot-intake drop-off (data_intake.on): an active unexpired dot_submitter assignment; immutable package paths; the READY manifest finalised last submits through the existing structured intake writer (submitter dot). No canonical write, no activation.';

do $e$
declare v jsonb := security.consumer_api_check_v1(); g record;
begin
  select * into g from s1344_guard;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API baseline changed: %', v; end if;
  if (select count(*) from cron.job where active) <> g.cron_before then raise exception 'post-check: active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> g.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from security.user_roles) <> g.assignments_before then raise exception 'post-check: a role was assigned'; end if;
  if (select public from storage.buckets where id = 'data-intake') is distinct from false then raise exception 'post-check: data-intake must be a private bucket'; end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and (qual ilike '%data-intake%' or with_check ilike '%data-intake%')) then raise exception 'post-check: data-intake has a storage policy'; end if;
  if has_function_privilege('authenticated', 'public.svc_data_intake_v1(text, jsonb)', 'EXECUTE') then raise exception 'post-check: svc_data_intake_v1 is executable by authenticated'; end if;
end $e$;
