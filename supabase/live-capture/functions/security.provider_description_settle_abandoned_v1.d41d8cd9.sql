CREATE OR REPLACE FUNCTION security.provider_description_settle_abandoned_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-reservation-settlement-v1
declare v_floor numeric := security.pipeline_num_v1('pdesc.read_cost_floor_usd', 0.003); v_avg numeric; v_est numeric;
        v_bound int := greatest(1, security.pipeline_num_v1('pdesc.queue_cap', 60)::int); v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('cf247 provider description spend')); -- fixed: the lock the reservation takes, so a settlement and a new reservation never see each other half done
  -- the observed cost of a read, the same expression the lease uses (svc_provider_description_next): cost over the reads that made a call
  select coalesce(sum(x.cost_usd) / nullif(count(*) filter (where x.ai_calls > 0), 0), 0) into v_avg from pipeline.provider_description_reads x;
  v_est := greatest(v_floor, v_avg);
  with a as (
    -- abandoned: a reservation that nothing is working on (not reading, or reading with a lease that has run out); a live lease is a call in flight
    select r.id from pipeline.provider_description_reads r
     where r.reserved_usd > 0 and (r.state <> 'reading' or r.leased_until is null or r.leased_until < now())
     order by r.updated_at, r.id limit v_bound for update skip locked),
  u as (
    update pipeline.provider_description_reads r
       set cost_usd = r.cost_usd + least(r.reserved_usd, v_est), -- the trigger ai_spend_capture writes the ledger row for this increase
           ai_calls = r.ai_calls + 1,
           reserved_usd = 0,
           checks = coalesce(r.checks, '{}'::jsonb) || jsonb_build_object('reservation_settlement', jsonb_build_object('basis', 'abandoned_reservation_assumed_called', 'settled_usd', least(r.reserved_usd, v_est),
                      'reserved_usd', r.reserved_usd, 'floor_usd', v_floor, 'observed_average_usd', round(v_avg, 6), 'ai_calls_before', r.ai_calls, 'state_before', r.state, 'at', now())),
           state = case when r.state = 'reading' then 'held' else r.state end,
           rule = case when r.state = 'reading' then 'existing_cost_reservation_uncertain' else r.rule end,
           reason = case when r.state = 'reading' then 'A paid read was leased and its result never recorded; its AI cost was settled at the dearer of the set floor and the observed cost of a read, and the read is offered again.' else r.reason end,
           leased_until = case when r.state = 'reading' then null else r.leased_until end,
           updated_at = now()
      from a where r.id = a.id
    returning 1)
  select count(*) into v_n from u;
  return v_n;
end $function$
