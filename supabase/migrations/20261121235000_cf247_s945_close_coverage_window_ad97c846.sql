-- CF-247 s945 (session S1-Coverage-Unlock-UI-Notes, follow-up of s903): close the coverage unlock on-demand window ad97c846, which expired at 15:09 AEDT.
-- Pilot CLAUDE.md on-demand rule: work a Claude session opened is closed with security.on_demand_close_v1 once it has run, and its use and credit reported.
-- Read live (rolled back, 21 Nov 2026 15:21 AEDT): state open past its expiry; Firecrawl use 110 units of the 20,000 cap (scholarship pages 94, provider facts 11,
-- listing pages 5); 66,863 credits left on the plan; OpenRouter spend in the window, all lanes, US$0.0561.
-- G1: no job. G2: no value. G3 stays 75/48. Spend: none by this change.
-- Parity: head 20261121230000 read 21 Nov 2026 15:21 AEDT; no open migration; this file is numbered strictly above it.
-- Replaces: nothing. Retires: nothing (the window is closed, its record and report kept). Nothing dropped or deleted.
set local lock_timeout = '5s';
set local statement_timeout = '60s';  -- fixed: the post-check reads the consumer API check

do $c$
declare v_id constant uuid := 'ad97c846-4c3b-447f-b2c7-18b14caa9daa'; v_state text; r jsonb; v_api jsonb; v_locks int := (select count(*) from pipeline.manual_locks); v_cron int := (select count(*) from cron.job where active);
begin
  select state into v_state from pipeline.on_demand_requests where id = v_id;
  if v_state is null then raise exception 's945: on-demand request % not found', v_id; end if;
  if v_state = 'open' then r := security.on_demand_close_v1(v_id); raise notice 's945: closed %: %', v_id, left(r::text, 600);
  else raise notice 's945: request % is already %', v_id, v_state; end if;
  if (select state from pipeline.on_demand_requests where id = v_id) <> 'closed' then raise exception 'post-check: the window is not closed'; end if;
  if (select actual from pipeline.on_demand_requests where id = v_id) is null then raise exception 'post-check: the window has no report of its use'; end if;
  if (select count(*) from cron.job where active) <> v_cron then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> v_locks then raise exception 'post-check: the manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
