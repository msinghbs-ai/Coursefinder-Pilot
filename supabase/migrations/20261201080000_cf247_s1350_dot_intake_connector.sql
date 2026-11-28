-- CF-247 s1350 (S1-Build; Platform Admin 28 Nov 2026 13:05 AEDT: "implement a private StudySearch DOT Intake API connector using the existing deployed
-- dot-intake Edge Function ... secure agent authentication, evidence upload, package finalisation and status retrieval ... credentials outside the
-- agent conversation and public GitHub repositories ... restricted permissions, expiry, revocation and audit"; SS-Programme-Control
-- PC-20261128-DOT-AUTH-REVIEW: a private scoped tool with backend credential handling and short-lived authenticated access, reusing the endpoint/gate).
-- The connector is the edge function dot-intake-connector (an MCP tool server, also callable as plain JSON). DOT's agent signs in to it with its
-- own key, registered like every API key (s935): API version dot v1, key dot_intake_connector_v1 in private.api_keys, NOT ISSUED here (a random
-- hash nobody holds). The Platform Admin issues it once on Settings > API usage (shown once, stored only as its SHA-256) and puts it in DOT's
-- connector settings; it is switched off or rotated there, and every call is logged in pipeline.api_requests with this version and key.
-- Behind the key the connector opens a short-lived session for the one DOT user (the active, unexpired dot_submitter whose expiry is bounded),
-- calls the deployed dot-intake function with it and signs the session out again; no password is stored anywhere. The dot-intake gate, the
-- private data-intake bucket and the existing structured intake and admission rules are unchanged.
-- G1: no job. G2: no operational value in code (the key's rate is its own row). G3: not the consumer API; 75/48 checked. Nothing dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.
create temp table s1350_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before,
       (select count(*) from private.api_keys where enabled) as keys_before;

do $e$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $e$;

insert into pipeline.api_versions (platform, api_version, endpoint, label, key_store, status, frozen, sort, note)
values ('dot', 'v1', 'dot-intake-connector', 'DOT intake connector v1', 'private.api_keys', 'active', false, 90,
        'CF-247 s1350: DOT''s private connector to the data-intake drop-off (upload, finalise, status). Not a consumer API.')
on conflict (platform, api_version, endpoint) do nothing;

insert into private.api_keys (key_name, platform, api_version, consumer, token_sha256, enabled, rate_per_minute, note)
values ('dot_intake_connector_v1', 'dot', 'v1', 'DOT (evidence agent)',
        encode(extensions.digest(encode(extensions.gen_random_bytes(32), 'hex'), 'sha256'), 'hex'), true, 60,
        'CF-247 s1350 (28 Nov 2026): DOT''s key for the dot-intake connector. [not issued] Nobody holds this key yet: rotate it on Settings > API usage to issue it (shown once).')
on conflict (key_name) do nothing;
insert into pipeline.api_key_events (key_name, event, note)
values ('dot_intake_connector_v1', 'switched_on', 'CF-247 s1350: own key for dot v1 added (not issued)');

create or replace function public.svc_data_intake_identity_v1(p_producer text) returns jsonb
language plpgsql stable security definer set search_path to ''
as $f$
declare v_days int := security.pipeline_num_v1('data_intake.role_max_days', 14)::int; v_ids uuid[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_producer is distinct from 'dot' then raise exception 'INVALID_INPUT: producer is dot'; end if;
  select array_agg(distinct ur.user_id) into v_ids from security.user_roles ur join security.roles r on r.code = ur.role_code
   where ur.role_code = 'dot_submitter' and r.status = 'active' and ur.expires_at > now() and ur.expires_at <= now() + make_interval(days => v_days);
  if coalesce(cardinality(v_ids), 0) = 0 then return jsonb_build_object('ok', false, 'held', 'HELD:NO_DOT_IDENTITY'); end if;
  if cardinality(v_ids) > 1 then return jsonb_build_object('ok', false, 'held', 'HELD:AMBIGUOUS_DOT_IDENTITY', 'users', cardinality(v_ids)); end if;
  return jsonb_build_object('ok', true, 'user_id', v_ids[1]);
end $f$;
revoke all on function public.svc_data_intake_identity_v1(text) from public, anon, authenticated;
grant execute on function public.svc_data_intake_identity_v1(text) to service_role;
comment on function public.svc_data_intake_identity_v1(text) is 'CF-247 s1350: the one producer user behind the dot-intake connector: an active dot_submitter whose expiry is set and within data_intake.role_max_days; none or several is held. The dot-intake gate decides again on every call.';

do $e$
declare v jsonb := security.consumer_api_check_v1(); g record; c jsonb := security.api_usage_coverage_v1();
begin
  select * into g from s1350_guard;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API baseline changed: %', v; end if;
  if (select count(*) from cron.job where active) <> g.cron_before then raise exception 'post-check: active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> g.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if jsonb_array_length(coalesce(c->'missing_versions', '[]'::jsonb)) > 0 or jsonb_array_length(coalesce(c->'missing_keys', '[]'::jsonb)) > 0 then raise exception 'post-check: the API usage read path misses a version or key: %', c; end if;
  if public.api_key_auth_v1('dot', 'v1', repeat('0', 64)) is not null then raise exception 'post-check: an unknown key signs in'; end if;
  if has_function_privilege('authenticated', 'public.svc_data_intake_identity_v1(text)', 'EXECUTE') then raise exception 'post-check: identity lookup is executable by authenticated'; end if;
  if (public.svc_data_intake_identity_v1('dot')->>'held') is distinct from 'HELD:NO_DOT_IDENTITY' and (select count(*) from security.user_roles where role_code = 'dot_submitter') = 0 then raise exception 'post-check: identity lookup found a user with no assignment'; end if;
end $e$;
