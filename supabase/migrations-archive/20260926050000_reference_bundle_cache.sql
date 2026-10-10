-- Package 6 (Decision 137): the consumer reference bundle is pre-computed every 10 minutes.
-- The live query moves unchanged to security.zoho_reference_bundle_live_v1(); the public function
-- returns the cached bundle, or the live result if the cache is older than 30 minutes.
-- Same return type, security mode, search path and grants (service_role only). Guarded (Decision 136).
do $guard$
declare d text; v_before jsonb; v_after jsonb; v_diff jsonb;
begin
  v_before := security.consumer_api_snapshot_v1();

  d := pg_get_functiondef('public.zoho_edge_reference_bundle_v1()'::regprocedure);
  if strpos(d,'FUNCTION public.zoho_edge_reference_bundle_v1()')=0 then raise exception 'unexpected function header'; end if;
  execute replace(d,'FUNCTION public.zoho_edge_reference_bundle_v1()','FUNCTION security.zoho_reference_bundle_live_v1()');
  revoke all on function security.zoho_reference_bundle_live_v1() from public, anon, authenticated;

  create table if not exists pipeline.consumer_reference_bundle_cache(
    id int primary key default 1 check (id=1),
    bundle jsonb not null,
    built_at timestamptz not null default now(),
    build_ms int
  );
  alter table pipeline.consumer_reference_bundle_cache enable row level security;
  revoke all on pipeline.consumer_reference_bundle_cache from public, anon, authenticated;

  execute $f$
    create or replace function security.refresh_reference_bundle_cache_v1()
    returns jsonb language plpgsql security definer set search_path to 'pg_catalog','security','pipeline'
    as $b$
    declare t0 timestamptz := clock_timestamp(); b jsonb;
    begin
      b := security.zoho_reference_bundle_live_v1();
      insert into pipeline.consumer_reference_bundle_cache(id,bundle,built_at,build_ms)
      values (1,b,now(),round(extract(epoch from clock_timestamp()-t0)*1000))
      on conflict (id) do update set bundle=excluded.bundle, built_at=excluded.built_at, build_ms=excluded.build_ms;
      return jsonb_build_object('built_at',now(),'bytes',length(b::text));
    end $b$;
  $f$;
  revoke all on function security.refresh_reference_bundle_cache_v1() from public, anon, authenticated;
  perform security.refresh_reference_bundle_cache_v1();

  execute $f$
    create or replace function public.zoho_edge_reference_bundle_v1()
    returns jsonb language plpgsql volatile security definer
    set search_path to 'pg_catalog', 'public', 'catalogue', 'ref', 'search'
    as $b$
    declare b jsonb; t timestamptz;
    begin
      select c.bundle, c.built_at into b, t from pipeline.consumer_reference_bundle_cache c where c.id=1;
      if b is null or t < now() - interval '30 minutes' then
        return security.zoho_reference_bundle_live_v1();
      end if;
      return b;
    end $b$;
  $f$;

  v_after := security.consumer_api_snapshot_v1();
  v_diff := security.consumer_api_compare_v1(v_before, v_after);
  if jsonb_array_length(v_diff) > 0 then raise exception 'Consumer API output changed; aborting: %', v_diff; end if;
  insert into pipeline.consumer_api_baselines(label, snapshot) values ('after package6 reference bundle cache', v_after);
end $guard$;

select cron.unschedule(jobid) from cron.job where jobname='consumer-reference-bundle-refresh';
select cron.schedule('consumer-reference-bundle-refresh','*/10 * * * *',$c$select security.refresh_reference_bundle_cache_v1();$c$);
