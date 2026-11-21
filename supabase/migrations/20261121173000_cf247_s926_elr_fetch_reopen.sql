-- CF-247 s926 (session S1-ELR-Unblock-IQ00624, Platform Admin 21 Nov 2026 11:05 AEDT, answer "Reopen and fetch"): a new on-demand request for the 52 queued central English pages.
-- English language requirements only.
--
-- Found live (rolled back, 11:02 AEDT): the s907 request (9cbdc5fb) was closed by elr-det-sweep at 10:42 AEDT with 0 Firecrawl units used, because every fetch call had been
-- refused by the worker (the s913 fault) and the queue was empty at that moment; s913 then queued the 52 pages again, but under the closed request, so none is sent.
-- elr-det-sweep has succeeded on every run since s910 (11 of 11, 10:12 to 11:02 AEDT, 2.6 to 4.5 s).
--
-- What changes: one new on-demand request ('claude_session', Firecrawl only, scope central, ondemand.window_hours) for the providers of the queued pages, and the queued
-- pages move to it. The sweep sends 10 a run and closes the request when the queue is empty (s907, s913). No function, job, table or setting changes.
-- Estimate: 52 Firecrawl credits (at most 78), from 67,120 left; no model.
-- G1: no new job. G2: no new value. G3 stays 75/48.
-- Parity: head 20261121170000 in main at 11:10 AEDT; this file is numbered strictly above it.
-- Replaces: the closed s907 on-demand request for the pages still queued (its record and report stay).
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';
set local statement_timeout = '60s';  -- fixed: the post-check reads the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s926_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s926_cron on commit drop as select count(*) n from cron.job where active;

do $od$
declare v_ids uuid[]; v_n int; v_id uuid; v_est jsonb; v_reason text := 'CF-247 s926 (Platform Admin 21 Nov 2026 11:05, reopen): one-off fetch of known, unstored central English pages for the English requirement sweep';
begin
  select array_agg(distinct provider_id), count(*) into v_ids, v_n from pipeline.elr_central_fetches f where f.status = 'queued' and (f.on_demand_id is null or not exists (select 1 from pipeline.on_demand_requests r where r.id = f.on_demand_id and r.state = 'open' and r.expires_at > now()));
  if coalesce(v_n, 0) = 0 then return; end if;
  v_est := jsonb_build_object('pages', v_n, 'firecrawl_credits', v_n, 'firecrawl_credits_most', ceil(v_n * 1.5), 'basis', 'one credit a page; a PDF or long page can cost more');
  perform security.on_demand_open_v1('claude_session', v_reason, v_ids, v_est, null, array['firecrawl']);
  select r.id into v_id from pipeline.on_demand_requests r where r.requested_via = 'claude_session' and r.reason = v_reason and r.state = 'open' order by r.opened_at desc limit 1;
  if v_id is null then raise exception 's907: the on-demand request was not opened'; end if;
  perform security.on_demand_scope_v1(v_id, array['central']);
  update pipeline.elr_central_fetches f set on_demand_id = v_id where f.status = 'queued' and (f.on_demand_id is null or not exists (select 1 from pipeline.on_demand_requests r where r.id = f.on_demand_id and r.state = 'open' and r.expires_at > now()));
  insert into pipeline.elr_central_fetch_state (on_demand_id, estimate) values (v_id, v_est || jsonb_build_object('credit_left_before', security.on_demand_credit_left_v1()));
  raise notice 's926: % pages of % universities queued under on-demand request %; estimate %; credit left %', v_n, cardinality(v_ids), v_id, v_est, security.on_demand_credit_left_v1();
end $od$;

do $c$
declare v_api jsonb; v_q int;
begin
  select count(*) into v_q from security.elr_central_fetch_claim_v1(10);
  if v_q = 0 and exists (select 1 from pipeline.elr_central_fetches where status = 'queued') then raise exception 'post-check: queued pages have no open on-demand request'; end if;
  if (select count(*) from pipeline.elr_central_fetches) > 100 then raise exception 'post-check: more than 100 pages queued'; end if;
  if (select count(*) from cron.job where active) <> (select n from s926_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s926_locks) then raise exception 'post-check: the manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  raise notice 's926: % pages ready to send under the new request', v_q;
end $c$;
