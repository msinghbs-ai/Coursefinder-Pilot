-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 07:08, decision 1), with worker coverage-sweep v1.0.13.
-- What the first results of worker v1.0.12 showed (18 Nov 2026 07:55 to 08:03, 468 stored pages): on 214 pages that state a study load for
-- international students the model answered from the general statement instead and the page check refused the answer; on 51 the model
-- called a general statement "international". 96 answers passed, 95 of them on a sentence about international students.
-- What it does:
--   1. Worker v1.0.13 (boost.ts, prompt boost-study-load-v3): a page that states a study load for international students is asked about
--      those sentences only (selector study-load-international-v1), so the answer rests on them; other pages are read as before. The page
--      check reads the basis from the quote (a quoted sentence about international students decides the value) instead of from the model's label.
--   2. The readings worker v1.0.12 refused are given back (state released) and read again. Its verified readings are kept.
-- What it does not do: it qualifies no model for admission and admits nothing. Everything Boost stages stays shadow.
-- G1: no new job. G2: no new value. G3: no consumer API object is changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
begin
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'boost.yield_to_dispatchers') then raise exception 'migration 20261118074500 is not applied'; end if;
end $pre$;

update pipeline.ai_route_qualifications set prompt_version = 'boost-study-load-v3',
       note = coalesce(note, '') || ' | 18 Nov 2026: prompt boost-study-load-v3 (a page with a statement for international students is asked about that statement only)'
 where service_code in ('boost_extract', 'boost_extract_benchmark') and prompt_version = 'boost-study-load-v2';

update pipeline.boost_extract_items set state = 'released', note = 'refused under boost-study-load-v2; read again by worker v1.0.13', done_at = now()
 where state in ('rejected', 'failed');

-- the benchmark run under the new prompt is bench-3 (bench-2 started under boost-study-load-v2 and is left as it is)
update pipeline.platform_toolset_settings set value = to_jsonb('bench-3'::text), updated_at = now(),
       reason = 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08: benchmark run bench-3 under prompt boost-study-load-v3 (worker v1.0.13)'
 where toolset_key = 'pipeline' and key = 'boost.benchmark_label';

select cron.alter_job((select jobid from cron.job where jobname = 'boost-extract'), active := true)
 where exists (select 1 from cron.job where jobname = 'boost-extract' and not active);

do $c$
begin
  if exists (select 1 from pipeline.boost_extract_items where state in ('rejected', 'failed')) then raise exception 'post-check: a refused reading was not given back'; end if;
  if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: a model is qualified for admission; this migration qualifies none'; end if;
  if exists (select 1 from pipeline.boost_inbound_staging where promotion_state = 'admitted') then raise exception 'post-check: a Boost row is admitted; this migration admits none'; end if;
  if (select count(*) from pipeline.ai_route_qualifications where service_code in ('boost_extract', 'boost_extract_benchmark') and prompt_version = 'boost-study-load-v3') <> 4 then
    raise exception 'post-check: the route qualifications do not name prompt boost-study-load-v3';
  end if;
  if not (select active from cron.job where jobname = 'boost-extract') then raise exception 'post-check: job boost-extract is not on'; end if;
end $c$;
