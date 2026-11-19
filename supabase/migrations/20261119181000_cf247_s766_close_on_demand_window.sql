-- CF-247 s766 addendum: the on-demand read of the six higher-education providers has answered, so its window is closed (follows 20261119175000).
-- Replaces: nothing
-- Retires: nothing
--
-- Request ebcc6b09-e71d-4baa-b809-1842402d0742 (opened by 20261119175000) covered the stored-page reads of Torrens, Moore, AUT, CIHE, Kaplan Murdoch and Sydney Met.
-- Three were admitted (Kaplan Murdoch, CIHE, Sydney Met); Torrens, Moore and AUT were held by the sentence checks on the model answer, not by identity.
-- This change only closes the window: security.on_demand_close_v1 records the actual use and the credit left, and a control event keeps the figures beside the decision.
-- It refuses, changing nothing, while any read of that request is still queued or running. No setting, route, lock or description is touched; Firecrawl stays at 0.
-- G1: no job. G2: no value in code. G3: untouched (75 functions, 48 tables; no new object).

set local lock_timeout = '5s'; -- fixed: lock wait guard for the close below

do $g$
begin
  if exists (select 1 from pipeline.provider_description_reads r
              where r.checks->>'on_demand_request' = 'ebcc6b09-e71d-4baa-b809-1842402d0742' and r.state in ('queued', 'running')) then
    raise exception 'refused: a read of the s766 on-demand request is still queued or running; nothing was changed';
  end if;
end $g$;

create temp table cf_s766_close on commit drop as
select o.id, security.on_demand_close_v1(o.id) as closed
  from pipeline.on_demand_requests o
 where o.id = 'ebcc6b09-e71d-4baa-b809-1842402d0742' and o.closed_at is null;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'on_demand', 'closed', 's766-au-university-identity-on-demand',
       jsonb_build_object('migration', '20261119181000', 'request', c.id, 'result', to_jsonb(c.closed)), null
  from cf_s766_close c;

do $k$
begin
  if exists (select 1 from pipeline.on_demand_requests where id = 'ebcc6b09-e71d-4baa-b809-1842402d0742' and closed_at is null) then
    raise exception 'post-check: the s766 on-demand request is closed';
  end if;
  if security.pipeline_num_v1('pdesc.acquire_firecrawl', 0) <> 0 then raise exception 'post-check: Firecrawl acquisition stays off'; end if;
end $k$;
