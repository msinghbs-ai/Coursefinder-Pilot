-- CF-247 S2 - BOOST (Platform Admin 17 Nov 2026 22:50, directive "Remove artificial locks and run Boost continuously now", items 1 and 3), and
-- two page rules that the first live results showed are needed before any model is qualified.
-- What it does:
--   1. Boost runs all day. The overnight window of the Boost gate and the quiet window of Boost promotion are opened to the whole day by their
--      settings (boost.ingest_window_start_minute 0, boost.ingest_window_end_minute 1440, boost.quiet_window_start_hour 0,
--      boost.quiet_window_end_hour 24). What still holds Boost: the switches, Pipeline Maintenance Mode, the migration squash blackout,
--      housekeeping-daily and the dispatcher locks.
--   2. The squash blackout starts at the migration freeze: Thu 19 Nov 2026 01:15 Melbourne (was 01:30); it ends 03:30 as before.
--   3. Throughput: job boost-extract runs every minute with 40 courses a run (it was every 5 minutes with 20), job worker-boost-bulk-ingest every
--      2 minutes with up to 10 files a run, and the route boost_extract may spend US$3 and make 5,000 calls a day (was US$1 and 1,500).
--   4. Page rule: security.boost_extract_claim_v1 no longer hands out a stored page whose text is also stored for another course. Such a page
--      is a general page of the provider, not the course's own (first live results, 17 Nov 2026 23:22 to 23:30: one page text stored for 21
--      courses gave "full_time" for some of them and "not stated" for others). 236 of the 2,380 queued courses are on such pages.
--   5. Spend: the cost of each Boost reading goes to the AI spend ledger (trigger ai_spend_capture on pipeline.boost_extract_items), so the
--      route's daily cap and the daily AI ceiling count Boost. Until now the calls were recorded (pipeline.ai_invocations) but not the spend.
--   6. The 40 courses read so far are given back (state released) to be read again by worker v1.0.10, which no longer sends or accepts a
--      sentence about a visa as a study load (28 of the first 29 study loads rested on one visa sentence).
-- What it does not do: it qualifies no model for admission. Everything Boost stages stays shadow.
-- G1: no new job. G2: every value changed is a setting or the route's own cap; the job commands hold no number. G3: no consumer API object is changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('security.boost_on_demand_v1(timestamptz)') is null then raise exception 'migration 20261118000100 (promotion held in the squash blackout) is not applied'; end if;
  if to_regprocedure('security.boost_extract_claim_v1(int)') is null or to_regclass('pipeline.boost_extract_items') is null then raise exception 'migration 20261117235000 is not applied'; end if;
end $pre$;

-- 1. and 2. All day, and the blackout from the freeze
update pipeline.platform_toolset_settings s set value = v.value, reason = 'CF-247 Boost, Platform Admin 17 Nov 2026 22:50: Boost runs all day; only the squash blackout and housekeeping-daily hold it', updated_at = now()
  from (values ('boost.ingest_window_start_minute', to_jsonb(0)), ('boost.ingest_window_end_minute', to_jsonb(1440)),
               ('boost.quiet_window_start_hour', to_jsonb(0)), ('boost.quiet_window_end_hour', to_jsonb(24))) v(key, value)
 where s.toolset_key = 'pipeline' and s.key = v.key;
update pipeline.platform_toolset_settings set value = to_jsonb(1795011300), updated_at = now(),
       reason = 'CF-247 Boost, Platform Admin 17 Nov 2026 22:50: the squash lock is the migration freeze, Thu 19 Nov 2026 01:15 to 03:30 Melbourne'
 where toolset_key = 'pipeline' and key = 'boost.ingest_blackout_start_epoch';

update pipeline.automation_catalogue set description =
  'Every 2 minutes, all day (Platform Admin 17 Nov 2026 22:50), not during the migration squash blackout, not while housekeeping-daily runs or just after it starts, and only when no PR 1, PR 2 or PR 3 tick holds its lock: loads the Boost result files from Storage staging-boost/inbound (each once) and settles them. Only qualified models are admitted, study load only, where the course has none.'
 where jobname = 'worker-boost-bulk-ingest';
update pipeline.automation_catalogue set description =
  'Every minute, all day (Platform Admin 17 Nov 2026 22:50), only when Boost extraction is switched on, not during the migration squash blackout and not beside housekeeping-daily: worker coverage-sweep reads stored course pages of courses with no study load, in the order of the Boost priority matrix, through the Models & services route Boost extraction, and writes result files to Storage staging-boost/inbound. Results are shadow only until a model is qualified.'
 where jobname = 'boost-extract';

-- 3. Throughput
update pipeline.platform_toolset_settings s set value = v.value, reason = 'CF-247 Boost, Platform Admin 17 Nov 2026 22:50: clear the stored-page queue tonight', updated_at = now()
  from (values ('batch.boost_extract', to_jsonb(40)), ('boost.ingest_files_per_run', to_jsonb(10))) v(key, value)
 where s.toolset_key = 'pipeline' and s.key = v.key;
update pipeline.ai_service_routes set daily_usd_cap = 3, daily_calls_cap = 5000, changed_at = now(),
       reason = 'S2 - BOOST 17 Nov 2026 (Platform Admin 22:50: raise the daily cap so the stored-page queue clears tonight); pinned to qwen3-30b as before'
 where service_code = 'boost_extract';
select cron.alter_job((select jobid from cron.job where jobname = 'boost-extract'), schedule := '* * * * *');
select cron.alter_job((select jobid from cron.job where jobname = 'worker-boost-bulk-ingest'), schedule := '*/2 * * * *');


-- 4. The claim: as migration 20261117235000, without pages stored for more than one course; a course read again starts with no cost
create or replace function security.boost_extract_claim_v1(p_limit int)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_left int := least(greatest(coalesce(p_limit, 0), 0), 500);  -- fixed: bound on one call; the size is the setting batch.boost_extract
  v_batch text := 'bx-' || to_char(now() at time zone 'utc', 'YYYYMMDD"T"HH24MISS') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
  v_cat text := security.boost_lane_category_v1('study_load');
  v_items jsonb := '[]'::jsonb; v_got jsonb; r record;
begin
  if not ('study_load' = any (security.pipeline_list_v1('boost.extract_lanes'))) or v_cat is null or v_left = 0 then
    return jsonb_build_object('batch_id', v_batch, 'items', v_items);
  end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_extract_claim'));
  for r in select m.country_code, m.weight from security.boost_country_category_matrix_v1() m
            where m.enrichment_category = v_cat and m.weight > 0 order by m.priority_rank loop
    exit when v_left <= 0;
    with shared as (
      select e.content_hash from pipeline.evidence_artifacts e
       where e.evidence_type = 'provider_course_page_text' and e.storage_path is not null and e.content_hash is not null
       group by e.content_hash having count(distinct e.entity_id) > 1),
    cand as (
      select c.id as entity_id, a.id as evidence_id, a.storage_path, coalesce(a.source_url, c.course_url) as source_url, c.display_title
        from catalogue.courses c
        join catalogue.providers p on p.id = c.provider_id
        join ref.countries k on k.id = p.country_id
        join lateral (select e.id, e.storage_path, e.source_url, e.content_hash from pipeline.evidence_artifacts e
                       where e.entity_id = c.id and e.evidence_type = 'provider_course_page_text' and e.storage_path is not null
                       order by e.captured_at desc nulls last limit 1) a on true
       where c.lifecycle_status = 'active' and c.study_load is null
         and (k.iso_alpha2 = r.country_code
              or k.iso_alpha2 in (select split_part(x, '=', 1) from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) x where split_part(x, '=', 2) = r.country_code))
         -- a stored page whose text is also stored for another course is a general page of the provider, not this course's page: not read
         and not exists (select 1 from shared h where h.content_hash = a.content_hash)
         and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id'))
         and not exists (select 1 from pipeline.boost_extract_items x where x.lane = 'study_load' and x.entity_id = c.id and x.evidence_id = a.id
                          and (x.state in ('verified', 'rejected', 'failed') or (x.state = 'claimed' and x.claimed_at > now() - interval '30 minutes')))  -- fixed: claim lease
       limit v_left),
    ins as (
      insert into pipeline.boost_extract_items as t (item_key, lane, entity, entity_id, evidence_id, country_code, state, batch_id, claimed_at)
      select 'sl-' || d.entity_id || '-' || d.evidence_id, 'study_load', 'course', d.entity_id, d.evidence_id, r.country_code, 'claimed', v_batch, now() from cand d
      on conflict (item_key) do update set state = 'claimed', batch_id = excluded.batch_id, claimed_at = now(), done_at = null, result_path = null, note = null,
                                          cost = null, model_called = null
      returning t.item_key, t.entity_id, t.evidence_id)
    select coalesce(jsonb_agg(jsonb_build_object('item_key', i.item_key, 'lane', 'study_load', 'entity', 'course', 'entity_id', i.entity_id, 'evidence_id', i.evidence_id,
             'storage_path', d.storage_path, 'source_url', d.source_url, 'country_code', r.country_code, 'weight', r.weight,
             'context', jsonb_build_object('title', d.display_title))), '[]'::jsonb)
      into v_got from ins i join cand d on d.entity_id = i.entity_id and d.evidence_id = i.evidence_id;
    v_items := v_items || v_got;
    v_left := v_left - jsonb_array_length(v_got);
  end loop;
  return jsonb_build_object('batch_id', v_batch, 'items', v_items);
end $function$;

-- 5. Spend into the ledger (lane boost_extract is the route's lane, so the cost lands on the service boost_extract)
do $t$
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'pipeline.boost_extract_items'::regclass and tgname = 'ai_spend_capture') then
    create trigger ai_spend_capture after insert or update of cost on pipeline.boost_extract_items
      for each row execute function security.ai_spend_capture_v1('boost_extract', 'delta', '{cost}');
  end if;
end $t$;

-- 6. The courses read before the page rules are read again
update pipeline.boost_extract_items set state = 'released', note = 'read again under study-load-windows-v2 (worker v1.0.10)', done_at = now()
 where state in ('verified', 'rejected', 'failed');

-- 7. Post-checks
do $c$
declare v_claim jsonb;
begin
  if security.boost_ingest_gate_v1(false, '2026-11-18 12:00+11')->>'reason' = 'outside the window' or security.boost_extract_gate_v1(false, '2026-11-18 15:30+11')->>'reason' = 'outside the window' then
    raise exception 'post-check: a Boost gate is still closed by the window at midday';
  end if;
  if (security.boost_ingest_gate_v1(false, '2026-11-19 01:20+11')->>'ok')::boolean or (security.boost_extract_gate_v1(false, '2026-11-19 03:29+11')->>'ok')::boolean then
    raise exception 'post-check: a Boost gate is open inside the squash lock (Thu 01:15 to 03:30)';
  end if;
  begin
    perform security.boost_promote_v1('post-check-no-such-batch', false, '2026-11-19 01:20+11');
    raise exception 'post-check: promotion ran inside the squash lock';
  exception when others then if sqlerrm not like 'migration squash blackout%' then raise; end if;
  end;
  if (security.boost_promote_v1('post-check-no-such-batch', false, '2026-11-18 12:00+11')->>'rows')::int <> 0 then raise exception 'post-check: promotion at midday did not run cleanly'; end if;
  if (select schedule from cron.job where jobname = 'boost-extract') <> '* * * * *' or (select schedule from cron.job where jobname = 'worker-boost-bulk-ingest') <> '*/2 * * * *' then
    raise exception 'post-check: the job schedules are not as set';
  end if;
  if exists (select 1 from cron.job where jobname in ('boost-extract', 'worker-boost-bulk-ingest') and (not active or command ~ '''limit'', [0-9]')) then
    raise exception 'post-check: a Boost job is inactive or holds a number';
  end if;
  if (select array[daily_usd_cap, daily_calls_cap] from pipeline.ai_service_routes where service_code = 'boost_extract') <> array[3, 5000]::numeric[] then raise exception 'post-check: the route caps are not as set'; end if;
  -- the claim hands out no page stored for more than one course; what it claims here is released again
  v_claim := security.boost_extract_claim_v1(40);
  if exists (select 1 from jsonb_array_elements(v_claim->'items') x
              join pipeline.evidence_artifacts e on e.id = (x->>'evidence_id')::uuid
              join pipeline.evidence_artifacts o on o.content_hash = e.content_hash and o.evidence_type = 'provider_course_page_text' and o.entity_id <> e.entity_id) then
    raise exception 'post-check: a page stored for more than one course was claimed';
  end if;
  if jsonb_array_length(v_claim->'items') > 0 then
    perform public.svc_boost_extract_done(v_claim->>'batch_id',
      (select jsonb_agg(jsonb_build_object('item_key', x->>'item_key', 'status', 'released', 'note', 'post-check of migration 20261118011000')) from jsonb_array_elements(v_claim->'items') x), null);
  end if;
  -- a run of the job in flight keeps its own claimed rows; every finished reading is released
  if exists (select 1 from pipeline.boost_extract_items where state in ('verified', 'rejected', 'failed')) then raise exception 'post-check: a course is not released for the new reading'; end if;
  if security.ai_ledger_service_v1('boost_extract', 'boost_extract_items', '{}'::jsonb) is distinct from 'boost_extract' then raise exception 'post-check: Boost spend would not land on the service boost_extract'; end if;
  if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified for admission by this change'; end if;
end $c$;
