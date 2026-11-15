-- CF-247 Models & services › AI under load (Platform Admin 16 Nov 2026 07:41: "so the AI tab loads in < 1s"). After 20261116060000 the AI read
-- still took 1 to 3 s at busy times: security.ai_route_v1 (once per AI service, and on every AI hand-out by the workers) finds the latest OpenRouter
-- balance reading with "where kind = 'credits' and remaining_usd is not null order by observed_at desc limit 1", a sequential scan of
-- pipeline.layer3_openrouter_observations (about 37,700 rows) on every call. An index on (kind, observed_at desc) makes it a single index read.
-- Measured in a rolled-back live run: the 15 route reads 498 ms -> 150 ms; the AI read 998 ms -> 590 ms. No function changes.
-- G1: no job. G2: no number. G3: no consumer API object (security.consumer_api_check_v1() before and after).
-- Replaces: nothing. Retires: nothing. Nothing is dropped or deleted.

set local lock_timeout = '5s';

create index if not exists layer3_openrouter_observations_kind_observed_idx on pipeline.layer3_openrouter_observations (kind, observed_at desc);

do $$
begin
  if to_regclass('pipeline.layer3_openrouter_observations_kind_observed_idx') is null then raise exception 'post-check: the index is missing'; end if;
end $$;
