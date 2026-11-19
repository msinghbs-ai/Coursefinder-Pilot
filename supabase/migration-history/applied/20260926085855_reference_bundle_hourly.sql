do $guard$
declare v_before jsonb; v_after jsonb; v_diff jsonb;
begin
  v_before := security.consumer_api_snapshot_v1();
  execute $f$
    create or replace function public.zoho_edge_reference_bundle_v1()
    returns jsonb language plpgsql volatile security definer
    set search_path to 'pg_catalog', 'public', 'catalogue', 'ref', 'search'
    as $b$
    declare b jsonb; t timestamptz;
    begin
      select c.bundle, c.built_at into b, t from pipeline.consumer_reference_bundle_cache c where c.id=1;
      if b is null or t < now() - interval '3 hours' then
        return security.zoho_reference_bundle_live_v1();
      end if;
      return b;
    end $b$;
  $f$;
  v_after := security.consumer_api_snapshot_v1();
  v_diff := security.consumer_api_compare_v1(v_before, v_after);
  if jsonb_array_length(v_diff) > 0 then raise exception 'Consumer API output changed; aborting: %', v_diff; end if;
end $guard$;
select cron.alter_job(jobid, schedule := '50 * * * *') from cron.job where jobname='consumer-reference-bundle-refresh';
