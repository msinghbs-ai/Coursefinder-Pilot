-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 07:08, decision 2: the verified study loads go into the catalogue today; and 17 Nov 2026
-- 22:50: raise the route's daily cap so the stored-page queue clears).
-- Today's three readings of the queue under the international-first rule (workers v1.0.12, v1.0.13, v1.0.14) used the route's daily call
-- cap: 5,016 calls by 09:08 AEDT, US$0.47 of its US$3. Boost extraction has been held since, with 1,834 stored pages still to read, until
-- the cap resets at 11:00 AEDT (UTC midnight).
-- What it does: the route boost_extract may make 15,000 calls a day (was 5,000). Its US$3 daily cap is unchanged and still binds first at
-- today's price (about US$0.0001 a call). The route's prompt label names the prompt in use (boost-study-load-v4).
-- G1: no new job. G2: the cap is the route's own setting, changed with its reason. G3: nothing the consumer API reads is changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

update pipeline.ai_service_routes set daily_calls_cap = 15000, prompt_source = 'worker code: boost.ts (boost-study-load-v4)', changed_at = now(),
       reason = 'S2 - BOOST 18 Nov 2026 (Platform Admin 07:08 decision 2: verified study loads into the catalogue today); three readings under the international-first rule used the 5,000-call cap; US$3 daily cap unchanged; pinned to qwen3-30b as before'
 where service_code = 'boost_extract';
update pipeline.ai_service_routes set prompt_source = 'worker code: boost.ts (boost-study-load-v4)', changed_at = now(),
       reason = 'S2 - BOOST 18 Nov 2026: prompt label names the prompt in use (boost-study-load-v4); caps unchanged'
 where service_code = 'boost_extract_benchmark';

do $c$
begin
  if (select array[daily_usd_cap, daily_calls_cap] from pipeline.ai_service_routes where service_code = 'boost_extract') <> array[3, 15000]::numeric[] then raise exception 'post-check: the route caps are not US$3 and 15,000 calls'; end if;
  if (select cascade from pipeline.ai_service_routes where service_code = 'boost_extract') <> array['qwen3-30b'] then raise exception 'post-check: the route is not pinned to qwen3-30b'; end if;
end $c$;
