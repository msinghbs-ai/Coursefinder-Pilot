-- CF-247 s780: P1 hotfix, Provider details opens again for Curator and above (Platform Admin 19 Nov 2026 16:23 AEDT, chat S1-Build;
-- refs 3A9WTT and 3UD5A2).
-- Found (rolled-back live dry runs through GitHub Actions, 19 Nov 2026 16:25-16:40 AEDT; pipeline.ui_error_log):
--   * Both references are public.admin_read('provider_detail'), the read the Provider details blade makes twice when it opens
--     (api.providerDetail and providerRelated in src/lib/supabase.js). Both logged "permission denied for schema catalogue" for the Platform
--     Admin (user 63ba56cb-48d4-4169-98c2-7c4d1f72925b) at 16:21 and 16:22 AEDT, and again at 16:29.
--   * Cause: Pilot #1329 (commit a18020c8, 19 Nov 2026 04:44 AEDT, s712, migration 20261119045000) added accreditations to provider_detail
--     with a direct "select ... from catalogue.provider_accreditations" inside public.admin_read for rank 3 and above. public.admin_read is
--     not security definer (it runs as the signed-in user and hands every read to a security definer function); the authenticated role has
--     no usage on schema catalogue. So every Curator, Pipeline Operator, PIM Admin and Platform Admin was refused, while Viewers and
--     Counsellors (security.provider_accreditations_v3_v1, security definer) were not. Its dry run ran as the database owner and its live check
--     was made as a Viewer and a Counsellor, so the refused branch was never run as a signed-in Curator or above.
-- What changes (md5-guarded; no table; G3 untouched: the new function is in schema security and is not consumer API):
--   1. security.provider_accreditations_admin_v1(provider): security definer; for rank 3 and above every accreditation with its status (the same
--      columns and order as before), for any other role security.provider_accreditations_v3_v1 (the same as before). Executable by
--      authenticated (public.admin_read runs as the caller) and service_role only.
--   2. public.admin_read: the provider_detail branch reads the accreditations through it; nothing else in the function changes.
-- Replaces: the direct catalogue read in public.admin_read 'provider_detail'.
-- Retires: nothing.
-- G1: no job. G2: no setting. G3: untouched (75 functions, 48 tables).

do $$
begin
  if md5(replace(pg_get_functiondef('public.admin_read(text,jsonb)'::regprocedure), chr(13), '')) <> 'f10a3e3340943e304dafb2793eb07acc' then
    raise exception 'pre-check: public.admin_read changed since it was read (19 Nov 2026 16:35)';
  end if;
  if to_regprocedure('security.provider_accreditations_admin_v1(uuid)') is not null then
    raise exception 'pre-check: security.provider_accreditations_admin_v1 already exists';
  end if;
end $$;

-- the refusal, reproduced before the fix: the Platform Admin who hit 3A9WTT, as the signed-in role
create or replace function pg_temp.cf_as_user(p_user uuid, p_sql text) returns text language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute 'set local role authenticated';
  begin
    execute p_sql into v;
  exception when others then v := 'ERROR: ' || sqlerrm;
  end;
  execute 'reset role';
  return v;
end $f$;

do $$
declare v_pid uuid := coalesce((select a.provider_id from catalogue.provider_accreditations a order by a.provider_id limit 1),
                               (select p.id from catalogue.providers p order by p.id limit 1));
        v text;
begin
  v := pg_temp.cf_as_user('63ba56cb-48d4-4169-98c2-7c4d1f72925b', format($q$select (public.admin_read('provider_detail', jsonb_build_object('id', %L)) ? 'accreditations')::text$q$, v_pid));
  perform set_config('cf.diag', 'before: ' || coalesce(v, 'null') || '; ', true);
  if v not like '%permission denied for schema catalogue%' then
    raise notice 's780: the refusal did not reproduce before the fix (%)', v;
  end if;
end $$;

create or replace function security.provider_accreditations_admin_v1(p_provider_id uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
-- s780 (19 Nov 2026): Provider details › accreditations. Curator and above (rank 3+) see every row with its status, so rows under review show;
-- any other role sees what API v3 sends (security.provider_accreditations_v3_v1). Security definer: public.admin_read runs as the caller.
begin
  if coalesce(security.current_role_rank(), 0) >= 3 then
    return (select coalesce(jsonb_agg(jsonb_build_object('body_code', a.body_code, 'accredited_unit_name', a.accredited_unit_name, 'status', a.status,
                     'accredited_since', a.accredited_since, 'expires_at', a.expires_at, 'rating', a.rating, 'rating_period', a.rating_period,
                     'source_url', a.source_url, 'verified_at', a.verified_at) order by a.body_code, a.accredited_unit_name nulls first, a.id), '[]'::jsonb)
              from catalogue.provider_accreditations a where a.provider_id = p_provider_id);
  end if;
  return security.provider_accreditations_v3_v1(p_provider_id);
end $function$;

revoke all on function security.provider_accreditations_admin_v1(uuid) from public, anon;
grant execute on function security.provider_accreditations_admin_v1(uuid) to authenticated, service_role;
comment on function security.provider_accreditations_admin_v1(uuid) is
  's780 (19 Nov 2026): accreditations for Provider details (public.admin_read provider_detail): every row with its status for rank 3+, the API v3 rows otherwise.';

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.cf_edit_def('public.admin_read(text,jsonb)'::regprocedure, 'f10a3e3340943e304dafb2793eb07acc',
  array[$o$   ||jsonb_build_object('accreditations',case when coalesce(security.current_role_rank(),0)>=3 then
       (select coalesce(jsonb_agg(jsonb_build_object('body_code',a.body_code,'accredited_unit_name',a.accredited_unit_name,'status',a.status,
                'accredited_since',a.accredited_since,'expires_at',a.expires_at,'rating',a.rating,'rating_period',a.rating_period,
                'source_url',a.source_url,'verified_at',a.verified_at) order by a.body_code,a.accredited_unit_name nulls first,a.id),'[]'::jsonb)
          from catalogue.provider_accreditations a where a.provider_id=v_id)
     else security.provider_accreditations_v3_v1(v_id) end);end if;$o$],
  array[$n$   -- s780 (19 Nov 2026, refs 3A9WTT and 3UD5A2): read through a security definer helper; public.admin_read runs as the caller, who has no
   -- usage on schema catalogue, so the direct read added by 20261119045000 refused every Curator and above
   ||jsonb_build_object('accreditations',security.provider_accreditations_admin_v1(v_id));end if;$n$]);

-- post-checks
do $$
declare v_pid uuid := coalesce((select a.provider_id from catalogue.provider_accreditations a order by a.provider_id limit 1),
                               (select p.id from catalogue.providers p order by p.id limit 1));
        v_admin text; v_rank text; v_viewer_rank int; v_direct int; v_rows int; v_live int;
begin
  if (select prosecdef from pg_proc where oid = 'public.admin_read(text,jsonb)'::regprocedure) then
    raise exception 'post-check: public.admin_read must stay security invoker';
  end if;
  -- no public function the signed-in role can run reads schema catalogue while running as the caller
  select count(*) into v_direct from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and not p.prosecdef and p.prosrc ~ 'catalogue\.' and has_function_privilege('authenticated', p.oid, 'EXECUTE');
  if v_direct > 0 then raise exception 'post-check: % public function(s) run as the caller and read schema catalogue', v_direct; end if;
  -- the Platform Admin who hit 3A9WTT and 3UD5A2 opens Provider details, as the signed-in role
  v_rank := pg_temp.cf_as_user('63ba56cb-48d4-4169-98c2-7c4d1f72925b', 'select security.current_role_rank()::text');
  v_admin := pg_temp.cf_as_user('63ba56cb-48d4-4169-98c2-7c4d1f72925b',
               format($q$select jsonb_array_length(public.admin_read('provider_detail', jsonb_build_object('id', %L))->'accreditations')::text$q$, v_pid));
  select count(*) into v_live from catalogue.provider_accreditations a where a.provider_id = v_pid;
  perform set_config('cf.diag', coalesce(current_setting('cf.diag', true), '') || format('after: platform_admin rank=%s accreditations=%s (held %s) provider=%s', v_rank, v_admin, v_live, v_pid), true);
  if v_admin like 'ERROR:%' or v_admin is null then raise exception 'post-check: Provider details still fails for the Platform Admin: %', v_admin; end if;
  if v_rank::int >= 3 and v_admin::int <> v_live then raise exception 'post-check: % accreditations returned, % held', v_admin, v_live; end if;
end $$;
