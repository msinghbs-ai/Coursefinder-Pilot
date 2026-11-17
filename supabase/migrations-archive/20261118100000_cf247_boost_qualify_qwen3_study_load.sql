-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 07:08, decision 2): Qwen3 30B is qualified for Boost study load, and the study loads it has
-- verified against their pages under prompt boost-study-load-v4 are admitted into the catalogue.
-- The decision: admission needs (a) a qualified model, (b) page-supported evidence, (c) an empty target field; never overwrite a value.
--   (a) Qwen3 30B (OpenRouter qwen/qwen3-30b-a3b-instruct-2507) won benchmark bench-1 of the three named candidates (220 stored pages): most
--       answers, fewest failures, and where it and Mistral Small 3.2 both answered they agree on 118 of 123 pages (96%). Its own answers
--       passed the page check on 163 of 180 calls (90.6%). The Platform Admin decided to qualify the winner.
--   (b) Only rows the worker verified against the whole stored page are admitted: the quote is on the page and states the value; when the
--       page states a study load for international students, the value is that one (decision 1, worker v1.0.14).
--   (c) security.boost_promote_v1 (unchanged) fills study_load only where it is null and no manual lock holds it, one row per course, and
--       leaves updated_at as it is.
-- What it does:
--   1. Inserts the qualification row (lane study_load, provider openrouter, the pinned model).
--   2. Sets the readings of worker v1.0.14 (prompt boost-study-load-v4) that verified a study load back to staged, and settles each of their
--      batches with security.boost_promote_v1. Readings under the earlier prompts stay shadow or refused and are never admitted.
--   From here worker-boost-bulk-ingest admits each new verified study load as its result file is loaded (it already calls the promotion).
-- What it does not do: it qualifies no other lane or model, changes no function, and sends nothing to Layer 4.
-- G1: no new job. G2: no new value. G3: no consumer API object's shape is changed; study_load is filled only where it was empty.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
declare v text;
begin
  v := md5(pg_get_functiondef('security.boost_promote_v1(text,boolean,timestamptz)'::regprocedure));
  if v <> 'fa4e3a8671577e2674e652fc5012f497' then raise exception 'security.boost_promote_v1 is not the definition this migration relies on (md5 %)', v; end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118093000') then raise exception 'migration 20261118093000 (worker v1.0.14 rules) is not applied'; end if;
end $pre$;

-- what the catalogue holds before: no course that has a study load may change
create temp table cf_boost_before on commit drop as
  select id, study_load, study_load_source, study_load_evidence_id from catalogue.courses where study_load is not null;

-- 1. The qualification
insert into pipeline.boost_model_qualifications(lane, provider, model, qualified_by, qualified_at, reason)
values ('study_load', 'openrouter', 'qwen/qwen3-30b-a3b-instruct-2507', null, now(),
        'Platform Admin decision 18 Nov 2026 07:08 (S2 - BOOST): qualify the winner of benchmark bench-1 (Qwen3 30B; agrees with Mistral Small 3.2 on 118 of 123 pages, 96%). Admits only page-verified study loads under prompt boost-study-load-v4, only where the course has none.')
on conflict (lane, provider, model) do nothing;

-- 2. The verified readings of worker v1.0.14 are settled again, batch by batch
update pipeline.boost_inbound_staging set promotion_state = 'staged', promotion_note = null, promoted_at = null
 where lane = 'study_load' and prompt_version = 'boost-study-load-v4' and worker_status = 'verified' and promotion_state = 'shadow'
   and answer->>'study_load' is not null and provider = 'openrouter' and model = 'qwen/qwen3-30b-a3b-instruct-2507';

do $p$
declare b text;
begin
  for b in select distinct batch_id from pipeline.boost_inbound_staging where promotion_state = 'staged' and lane = 'study_load' order by batch_id loop
    perform security.boost_promote_v1(b, false, now());
  end loop;
end $p$;

-- 3. Post-checks
do $c$
declare v_changed int; v_admitted int; v_filled int; v_left int;
begin
  select count(*) into v_changed from cf_boost_before b join catalogue.courses c on c.id = b.id
   where c.study_load is distinct from b.study_load or c.study_load_source is distinct from b.study_load_source or c.study_load_evidence_id is distinct from b.study_load_evidence_id;
  if v_changed > 0 then raise exception 'post-check: % course(s) that already held a study load were changed', v_changed; end if;
  select count(*) into v_admitted from pipeline.boost_inbound_staging where promotion_state = 'admitted';
  if exists (select 1 from pipeline.boost_inbound_staging where promotion_state = 'admitted' and (prompt_version <> 'boost-study-load-v4' or worker_status <> 'verified')) then
    raise exception 'post-check: a row not verified under prompt boost-study-load-v4 was admitted';
  end if;
  if exists (select entity_id from pipeline.boost_inbound_staging where promotion_state = 'admitted' group by entity_id having count(*) > 1) then raise exception 'post-check: a course was admitted twice'; end if;
  select count(*) into v_filled from catalogue.courses c join pipeline.boost_inbound_staging s on s.entity_id = c.id and s.promotion_state = 'admitted'
   where c.study_load = s.answer->>'study_load' and c.study_load_source = 'provider_page' and c.study_load_evidence_id = s.evidence_id
     and not exists (select 1 from cf_boost_before b where b.id = c.id);
  if v_filled <> v_admitted then raise exception 'post-check: % rows admitted but % courses filled from them', v_admitted, v_filled; end if;
  select count(*) into v_left from pipeline.boost_inbound_staging where promotion_state = 'staged' and lane = 'study_load';
  if v_left > 0 then raise exception 'post-check: % study-load rows are still staged', v_left; end if;
  if (select count(*) from pipeline.boost_model_qualifications) <> 1 then raise exception 'post-check: the qualifications are not the one row this migration adds'; end if;
  raise notice 'Boost study load: % rows admitted, % courses filled', v_admitted, v_filled;
end $c$;
