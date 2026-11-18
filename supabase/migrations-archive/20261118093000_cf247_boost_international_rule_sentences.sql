-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 07:08, decision 1), with worker coverage-sweep v1.0.14 (boost.ts, prompt boost-study-load-v4).
-- What the readings of worker v1.0.13 showed (18 Nov 2026 08:30 to 08:38, about 1,300 stored pages): the check for "a sentence that states a
-- study load for international students" was too loose. It counted fee lines ("International fee ... a standard full-time course load for
-- a year", 16 readings passed on it), work-rights notes ("Most students studying full time at Deakin need a Student Visa") and entry
-- requirements as such sentences. So correct general answers were refused ("Duration 4 years (full time)", 86) and some fee lines passed.
-- What it does:
--   1. Worker v1.0.14: a sentence counts only when it names international students or a student visa AND states a rule about how they may
--      study (must, only, not available, visa holders, "less than a full-time load", "International students: ..."); fee, tuition, credit
--      point, scholarship, work-rights and experience lines never count. A load named only as not offered, or offered only to domestic or
--      non-visa students, does not count; a sentence about international students that only rules part-time out states full-time.
--   2. Every stored page read under the earlier rules is given back (state released) and read again, including the verified ones: some of
--      them rest on a fee line. What those readings staged stays shadow or refused; promotion takes only rows in state staged.
--   3. The benchmark run under the new prompt is bench-4.
-- What it does not do: it qualifies no model for admission and admits nothing. Everything Boost stages stays shadow.
-- G1: no new job. G2: no new value. G3: no consumer API object is changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118083000') then raise exception 'migration 20261118083000 is not applied'; end if;
end $pre$;

update pipeline.ai_route_qualifications set prompt_version = 'boost-study-load-v4',
       note = coalesce(note, '') || ' | 18 Nov 2026: prompt boost-study-load-v4 (worker v1.0.14: only a stated rule for international students counts; fee and work-rights lines never)'
 where service_code in ('boost_extract', 'boost_extract_benchmark') and prompt_version = 'boost-study-load-v3';

update pipeline.boost_extract_items set state = 'released', note = 'read again by worker v1.0.14 (prompt boost-study-load-v4)', done_at = now()
 where state in ('verified', 'rejected', 'failed');

update pipeline.platform_toolset_settings set value = to_jsonb('bench-4'::text), updated_at = now(),
       reason = 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08: benchmark run bench-4 under prompt boost-study-load-v4 (worker v1.0.14)'
 where toolset_key = 'pipeline' and key = 'boost.benchmark_label';

select cron.alter_job((select jobid from cron.job where jobname = 'boost-extract'), active := true)
 where exists (select 1 from cron.job where jobname = 'boost-extract' and not active);

do $c$
begin
  if exists (select 1 from pipeline.boost_extract_items where state in ('verified', 'rejected', 'failed')) then raise exception 'post-check: a reading under the earlier rules was not given back'; end if;
  if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: a model is qualified for admission; this migration qualifies none'; end if;
  if exists (select 1 from pipeline.boost_inbound_staging where promotion_state = 'admitted') then raise exception 'post-check: a Boost row is admitted; this migration admits none'; end if;
  if (select count(*) from pipeline.ai_route_qualifications where service_code in ('boost_extract', 'boost_extract_benchmark') and prompt_version = 'boost-study-load-v4') <> 4 then
    raise exception 'post-check: the route qualifications do not name prompt boost-study-load-v4';
  end if;
  if not (select active from cron.job where jobname = 'boost-extract') then raise exception 'post-check: job boost-extract is not on'; end if;
end $c$;
