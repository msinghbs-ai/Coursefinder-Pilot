-- NZQA scholarship recovery, Admin #937. Integration Controller must reconcile migration ordering before release.
-- Narrowly exempt the four capped universities only during an explicitly scoped, unexpired on-demand request.
-- No change to paid acquisition enforcement, Canadian eligibility, or scheduled caps.
set local lock_timeout = '5s';
do $patch$
declare
  d text := pg_get_functiondef('security.fc_sch_held_v1(uuid,boolean)'::regprocedure);
  needle constant text := '    return true;';
  replacement constant text := $body$    -- NZQA recovery: only the specifically authorised scholarship request can lift the listing cap.
    -- The vendor spend function still enforces account reserve and other existing paid-call controls.
    if p_discovery
       and p_provider_id in ('e096aba7-e1eb-4903-9a63-2bfb71e9a8b8'::uuid,
                             'db910e88-67d1-4d2b-a65c-cea290aa0692'::uuid,
                             'ab12c7f8-e368-453d-9dfe-4ab8bd744829'::uuid,
                             '34616965-b2b7-42a7-8da7-50ffbf120958'::uuid)
       and security.fc_sch_eligible_v1(p_provider_id)
       and exists (
         select 1 from pipeline.on_demand_requests r
         where r.id = security.on_demand_request_for_v2(p_provider_id, 'sch_listing')
           and r.requested_via = 'S3-Scholarship-ChatGPT'
           and r.purpose_groups = array['scholarships']::text[]
           and r.estimate ? 'cap_firecrawl_units'
       )
    then return false; end if;
    return true;$body$;
  g jsonb := security.consumer_api_check_v1();
  locks_before bigint := (select count(*) from pipeline.manual_locks);
  cron_before bigint := (select count(*) from cron.job where active);
begin
  if md5(d) <> '1b9bbe30b3570d321b036a75c868683a' then
    raise exception 'NZ recovery: shared function checksum changed; integration reconciliation required';
  end if;
  if (length(d)-length(replace(d,needle,'')))/length(needle) <> 1 then
    raise exception 'NZ recovery: cap return not unique';
  end if;
  if (g->>'functions')::int <> 75 or (g->>'relations')::int <> 48
     or jsonb_array_length(coalesce(g->'drift','[]'::jsonb)) <> 0
     or locks_before <> 7585 or cron_before > 140 then
    raise exception 'NZ recovery: production guard failed';
  end if;
  execute replace(d,needle,replacement);
  if pg_get_functiondef('security.fc_sch_held_v1(uuid,boolean)'::regprocedure) <> replace(d,needle,replacement) then
    raise exception 'NZ recovery: unexpected function definition';
  end if;
  if security.consumer_api_check_v1() is distinct from g
     or (select count(*) from pipeline.manual_locks) <> locks_before
     or (select count(*) from cron.job where active) <> cron_before then
    raise exception 'NZ recovery: post-change guard failed';
  end if;
end $patch$;
