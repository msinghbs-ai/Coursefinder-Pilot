-- CF-247 S2 - BOOST (own follow-up after the canonical squash of Thu 19 Nov 2026, from the Platform Admin's 17 Nov 22:05 and 22:45 benchmark
-- decision): benchmark run bench-5, the same three named models (Qwen3 30B, Mistral Small 3.2, MiMo v2.6 Flash) on the current study-load
-- reader (prompt boost-study-load-v5, selector study-load-windows-v5, worker v1.0.22), across the countries of the Boost priority matrix.
-- The claim builds the cohort itself when the label has no rows: up to boost.benchmark_pages_per_country stored course pages of courses with no
-- study load per country. Job boost-benchmark (every 2 minutes) works through it. Nothing a benchmark answers is staged or admitted; results
-- stay in pipeline.boost_benchmark_items. A result never qualifies or switches on anything by itself (Qwen3 30B stays the only qualified
-- model; Platform Admin 18 Nov 2026 11:57: no Mistral route).
-- Numbered 20261118273000: above the post-squash live head (20261118272000) and below the open Pilot #1314 (20261118275000), so that PR stays above the head.
-- Replaces: the benchmark run label bench-4 (prompt v4) with bench-5
-- Retires: nothing

set local lock_timeout = '5s';

update pipeline.platform_toolset_settings set value = to_jsonb('bench-5'::text), updated_at = now(),
       reason = 'CF-247 S2 - BOOST, 19 Nov 2026 (after the squash): benchmark run bench-5 on prompt boost-study-load-v5, selector study-load-windows-v5'
 where toolset_key = 'pipeline' and key = 'boost.benchmark_label';

do $c$
begin
  if (select value #>> '{}' from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'boost.benchmark_label') <> 'bench-5' then
    raise exception 'post-check: the benchmark label is not bench-5';
  end if;
  if exists (select 1 from pipeline.boost_benchmark_items where run_label = 'bench-5') then raise exception 'post-check: run bench-5 already has rows'; end if;
  if (select count(*) from pipeline.boost_model_qualifications where lane = 'study_load') <> 1 then
    raise exception 'post-check: the study-load admission qualification changed';
  end if;
  if not exists (select 1 from cron.job where jobname = 'boost-benchmark' and active) then raise exception 'post-check: job boost-benchmark is not active'; end if;
end $c$;
