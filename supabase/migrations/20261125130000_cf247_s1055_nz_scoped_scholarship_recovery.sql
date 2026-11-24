-- CF-247 s1055 (integrated by S1-Build for S3-Scholarship-ChatGPT; Admin #937 approval, SCH-FU-04, Admin #973 and #974; Platform Admin 24 Nov 2026
-- 20:35 and 20:41 AEDT): the four New Zealand universities whose scholarship listing reads are held by the Firecrawl listing cap (Victoria University
-- of Wellington, Otago, Canterbury, Auckland) are read under an explicitly scoped, unexpired on-demand request that names this recovery.
-- Reconciled 24 Nov 2026 20:50 AEDT: live security.fc_sch_held_v1 md5 1b9bbe30... equals the branch's guard; with no change, an on-demand request
-- scoped to scholarships leaves them held (the existing route does not meet the need). Renumbered from 20261124235900 above live head 20261125120000.
-- The branch's regression fixture (tests/fixtures/scholarship-recovery/nz-scoped-on-demand-regression.sql) runs at the end of this migration inside a
-- block that always rolls back, so every governed dry run and the apply itself prove: purpose, provider scope, expiry, the non-discovery path and the
-- unchanged Canadian behaviour. Paid calls stay under the vendor spend function (account reserve, budgets); no cron, setting or limit changes.
-- G1: no job. G2: no operational value (the four providers and the reason are the approval's own scope). G3: checked before and after.
-- Replaces: nothing (an exception inside security.fc_sch_held_v1 for one approved request).
-- Retires: nothing. Nothing dropped or deleted.
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
           and r.requested_via = 'claude_session'
           and r.reason = 'Admin #937: S3-Scholarship-ChatGPT NZQA listing recovery'
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

-- the committed regression fixture, run here and always rolled back (its own request and expiry change never persist)
do $regression$
begin
  begin
    declare
 target uuid := 'e096aba7-e1eb-4903-9a63-2bfb71e9a8b8';
 ca uuid := 'b509ab5c-87b2-4040-8385-d1ce610c7263';
 req uuid;
 r jsonb;
    begin
 if not security.fc_sch_held_v1(target,true) then raise exception 'ordinary scheduled cap not held'; end if;
 if not security.fc_sch_held_v1(ca,true) then raise exception 'Canadian scheduled cap not held'; end if;
 r := security.on_demand_open_v1('claude_session','Admin #937: S3-Scholarship-ChatGPT NZQA listing recovery',array[target,ca],jsonb_build_object('cap_firecrawl_units',1));
 req := (r->>'id')::uuid;
 perform security.on_demand_scope_v1(req,array['central']);
 if not security.fc_sch_held_v1(target,true) then raise exception 'incorrect purpose allowed'; end if;
 perform security.on_demand_scope_v1(req,array['scholarships']);
 if security.fc_sch_held_v1(target,true) then raise exception 'authorised NZ request held'; end if;
 if not security.fc_sch_held_v1(ca,true) then raise exception 'Canadian exemption incorrectly expanded'; end if;
 if not security.fc_sch_held_v1(target,false) then raise exception 'non-discovery scheduled path changed'; end if;
 if not security.fc_sch_held_v1('db910e88-67d1-4d2b-a65c-cea290aa0692',true) then raise exception 'unauthorised NZ provider allowed'; end if;
 update pipeline.on_demand_requests set expires_at=now()-interval '1 second' where id=req;
 if not security.fc_sch_held_v1(target,true) then raise exception 'expired request allowed'; end if;
      raise exception 'S1055_REGRESSION_OK';
    end;
  exception when others then
    if sqlerrm <> 'S1055_REGRESSION_OK' then raise exception 's1055 regression failed: %', sqlerrm; end if;
  end;
end $regression$;
