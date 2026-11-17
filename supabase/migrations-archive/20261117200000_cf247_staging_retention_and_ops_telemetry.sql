-- CF-247 S1-Build Wave 2 (Platform Admin 17 Nov 2026 17:59 and 18:02): staging retention in housekeeping-daily, and read-only operations telemetry.
-- 1. Retention. housekeeping-daily (about 03:47 Melbourne) now also settles intermediate staging rows through security.staging_retention_v1:
--    pipeline.source_record_staging rows that were applied (status 'processed') more than their source's keep period ago (90 days by default,
--    per source in pipeline.source_retention_policies), and Boost staging rows that were settled but not admitted (shadow, proposed, refused).
--    Before a row goes, its hash is written to pipeline.staging_hash_ledger, kept for retention.raw_hash_keep_years (7). Admitted Boost rows,
--    rows of a source with a Layer 1 run in progress, published editions (destination.editions, pipeline.layer1_dataset_editions) and every
--    evidence record (pipeline.evidence_artifacts, class regulatory_evidence: immutable) are never touched.
--    The class catalogue says a dry run comes first (retention_class_policies.dry_run_required), so the switch retention.staging_prune_on
--    starts at 0: each night reports what would go; the Platform Admin turns pruning on (Settings > Pipeline settings > Housekeeping).
--    The older unreferenced-evidence purge (Storage & retention, category evidence_unreferenced) is aligned with the same rule (Platform Admin
--    17 Nov 2026 18:25): security.retention_evidence_candidates_v1 never offers evidence younger than retention.raw_hash_keep_years (7), so
--    neither its estimate nor the retention worker removes an evidence record or file before then.
-- 2. Telemetry (read only): views pipeline.ops_l1_apply_latency_v (chunked Layer 1 apply latency), pipeline.ops_l4_escalation_by_source_v
--    (Layer 4 escalation rate per source) and pipeline.ops_boost_vs_pr3_throughput_v (nightly Boost against daytime PR 3), read by the
--    Ops report through public.admin_ops_telemetry(). Look-back: setting telemetry.window_days.
-- G1: no new job (housekeeping-daily is catalogued; its description is updated). G2: every period, size and switch is a setting.
-- G3: no consumer API object is read for structure or changed.
-- Replaces: nothing (housekeeping_daily_v1 extended and retention_evidence_candidates_v1 aligned in place)
-- Retires: nothing

set local lock_timeout = '5s';

-- 0. The housekeeping function is replaced from its live definition (Pilot 20261016110000); stop if it changed since.
do $pre$
begin
  if md5(pg_get_functiondef('security.housekeeping_daily_v1()'::regprocedure)) <> 'd2761ea4beb46baed71ee88591d89c60' then
    raise exception 'pre-check: security.housekeeping_daily_v1 differs from the definition this change extends';
  end if;
  if md5(pg_get_functiondef('security.retention_evidence_candidates_v1()'::regprocedure)) <> '5b3912e24120bef44576688ecc63e914' then
    raise exception 'pre-check: security.retention_evidence_candidates_v1 differs from the definition this change aligns';
  end if;
end $pre$;

-- 1. Settings
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'retention.staging_prune_on', 'Staging retention: prune (1) or dry run only (0)',
   'housekeeping-daily removes applied staging rows past their keep period only when this is 1. At 0 it reports each night what it would remove (Admin events, area retention).',
   'number', to_jsonb(0), 0, 1, 'on (1) or dry run (0)', 760, 'Housekeeping', 'security.staging_retention_v1 (job housekeeping-daily)', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 18:02; class temporary_staging requires a dry run first'),
  ('pipeline', 'retention.staging_keep_days', 'Staging retention: keep applied staging rows for',
   'Applied Layer 1 staging rows (pipeline.source_record_staging, status processed) are kept this many days after they were applied, unless their source has its own period.',
   'number', to_jsonb(90), 30, 3650, 'days', 761, 'Housekeeping', 'security.staging_retention_v1 (job housekeeping-daily)', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 18:02 (90 days)'),
  ('pipeline', 'retention.boost_staging_keep_days', 'Staging retention: keep settled Boost rows for',
   'Boost staging rows settled as shadow, proposed or refused are kept this many days after settling. Admitted rows are always kept.',
   'number', to_jsonb(90), 30, 3650, 'days', 762, 'Housekeeping', 'security.staging_retention_v1 (job housekeeping-daily)', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 18:02 (90 days)'),
  ('pipeline', 'retention.raw_hash_keep_years', 'Staging retention: keep hashes of removed rows for',
   'Before a staging row is removed its hash, source and dates go to pipeline.staging_hash_ledger, kept this many years.',
   'number', to_jsonb(7), 7, 25, 'years', 763, 'Housekeeping', 'security.staging_retention_v1 (job housekeeping-daily)', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 18:02 (7-year raw snapshot hashes)'),
  ('pipeline', 'batch.staging_prune_rows', 'Staging retention: rows per night (each table)',
   'housekeeping-daily removes up to this many staging rows from each staging table in one run.',
   'number', to_jsonb(1000), 100, 10000, 'rows', 764, 'Housekeeping', 'security.staging_retention_v1 (job housekeeping-daily)', 'CF-247 S1-Build: bounded delete limit of class temporary_staging'),
  ('pipeline', 'telemetry.window_days', 'Operations telemetry: look-back',
   'The operations telemetry views (Layer 1 apply latency, Layer 4 escalation by source, Boost and PR 3 throughput) cover this many days.',
   'number', to_jsonb(30), 1, 180, 'days', 765, 'Housekeeping', 'pipeline.ops_*_v views, public.admin_ops_telemetry', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 18:02')
on conflict (toolset_key, key) do nothing;

-- 2. Retention classes (the existing catalogue)
insert into pipeline.retention_class_policies (class_key, object_scope, immutable, purge_allowed, default_retention_days, dry_run_required, bounded_delete_limit,
  post_delete_integrity_required, notes, change_control_ref)
values
  ('applied_source_staging', 'pipeline.source_record_staging (status processed) and pipeline.boost_inbound_staging (settled, not admitted)', false, true, 90, true, 1000, true,
   'Removed by housekeeping-daily (security.staging_retention_v1) after the keep period, hash first written to pipeline.staging_hash_ledger; dry run until retention.staging_prune_on is 1.',
   'CF-247 S1-Build 17 Nov 2026'),
  ('staging_hash_ledger', 'pipeline.staging_hash_ledger', false, true, 2557, true, 1000, true,
   'Hashes of removed staging rows, kept retention.raw_hash_keep_years (7) from removal.', 'CF-247 S1-Build 17 Nov 2026'),
  ('published_editions', 'destination.editions and pipeline.layer1_dataset_editions', true, false, null, true, null, true,
   'Published edition snapshots (edition_label, edition_key) are historical records: never purged.', 'CF-247 S1-Build 17 Nov 2026')
on conflict (class_key) do nothing;

-- 3. Per-source keep periods and the hash ledger
create table if not exists pipeline.source_retention_policies (
  source_id         uuid primary key references pipeline.sources(id),
  staging_keep_days int not null check (staging_keep_days between 30 and 3650),
  reason            text not null check (length(btrim(reason)) > 0),
  updated_by        uuid,
  updated_at        timestamptz not null default now()
);
comment on table pipeline.source_retention_policies is 'CF-247 S1-Build (Platform Admin 17 Nov 2026 18:02): a Layer 1 source''s own keep period for applied staging rows, where it differs from retention.staging_keep_days. Set with public.admin_source_retention_set.';
alter table pipeline.source_retention_policies enable row level security;
revoke all on pipeline.source_retention_policies from anon, authenticated;

create table if not exists pipeline.staging_hash_ledger (
  id               bigint generated always as identity primary key,
  origin           text not null check (origin in ('source_record_staging', 'boost_inbound_staging')),
  origin_id        bigint not null,
  source_id        uuid,
  record_key       text,
  content_hash     text,
  evidence_id      uuid,
  status           text,
  processed_at     timestamptz,
  pruned_at        timestamptz not null default now(),
  keep_until       timestamptz not null,
  unique (origin, origin_id)
);
comment on table pipeline.staging_hash_ledger is 'CF-247 S1-Build (Platform Admin 17 Nov 2026 18:02): the hash, source and dates of each staging row housekeeping-daily removed, kept retention.raw_hash_keep_years (7) so a removed raw record can still be matched.';
alter table pipeline.staging_hash_ledger enable row level security;
revoke all on pipeline.staging_hash_ledger from anon, authenticated;

-- 4. The retention step
create or replace function security.staging_retention_v1(p_dry boolean default true, p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_limit int := security.pipeline_num_v1('batch.staging_prune_rows', 1000)::int;
  v_keep  int := security.pipeline_num_v1('retention.staging_keep_days', 90)::int;
  v_bkeep int := security.pipeline_num_v1('retention.boost_staging_keep_days', 90)::int;
  v_years int := security.pipeline_num_v1('retention.raw_hash_keep_years', 7)::int;
  v_allowed boolean;
  v_srs_ids bigint[]; v_bis_ids bigint[];
  v_srs int := 0; v_bis int := 0; v_ledger_out int := 0;
  v_out jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' and coalesce(security.current_role_rank(), 0) < 3 then
    raise exception 'Curator role or above, or the service role, required';
  end if;
  -- the class catalogue decides whether anything may be removed at all
  select purge_allowed and not immutable into v_allowed from pipeline.retention_class_policies where class_key = 'applied_source_staging';
  if not coalesce(v_allowed, false) then p_dry := true; end if;
  perform pg_advisory_xact_lock(hashtext('cf247:staging_retention'));  -- fixed: one retention run at a time

  -- applied Layer 1 staging rows past their source's keep period, never for a source with a run in progress
  select coalesce(array_agg(id), '{}') into v_srs_ids from (
    select s.id
      from pipeline.source_record_staging s
      left join pipeline.source_retention_policies p on p.source_id = s.source_id
     where s.status = 'processed' and s.processed_at is not null
       and s.processed_at < p_now - make_interval(days => coalesce(p.staging_keep_days, v_keep))
       and not exists (select 1 from pipeline.layer1_run_queue q
                        where q.source_id = s.source_id and q.status not in ('completed', 'failed', 'no_change', 'cancelled', 'expired'))
     order by s.processed_at, s.id
     limit v_limit) x;

  -- settled Boost rows that were not admitted (admitted rows are the lineage of a catalogue value and stay)
  select coalesce(array_agg(id), '{}') into v_bis_ids from (
    select b.id from pipeline.boost_inbound_staging b
     where b.promotion_state in ('shadow', 'proposed', 'refused') and b.promoted_at is not null
       and b.promoted_at < p_now - make_interval(days => v_bkeep)
     order by b.promoted_at, b.id
     limit v_limit) x;

  if not p_dry then
    insert into pipeline.staging_hash_ledger (origin, origin_id, source_id, record_key, content_hash, status, processed_at, pruned_at, keep_until)
    select 'source_record_staging', s.id, s.source_id, s.source_record_id, s.content_hash, s.status, s.processed_at, p_now, p_now + make_interval(years => v_years)
      from pipeline.source_record_staging s where s.id = any (v_srs_ids)
    on conflict (origin, origin_id) do nothing;
    delete from pipeline.source_record_staging where id = any (v_srs_ids);
    get diagnostics v_srs = row_count;

    insert into pipeline.staging_hash_ledger (origin, origin_id, source_id, record_key, content_hash, evidence_id, status, processed_at, pruned_at, keep_until)
    select 'boost_inbound_staging', b.id, null, b.batch_id || '/' || b.item_key, md5(coalesce(b.answer::text, '')), b.evidence_id, b.promotion_state, b.promoted_at, p_now,
           p_now + make_interval(years => v_years)
      from pipeline.boost_inbound_staging b where b.id = any (v_bis_ids)
    on conflict (origin, origin_id) do nothing;
    delete from pipeline.boost_inbound_staging where id = any (v_bis_ids);
    get diagnostics v_bis = row_count;

    -- ledger rows past their own keep date
    delete from pipeline.staging_hash_ledger where id in (select id from pipeline.staging_hash_ledger where keep_until < p_now order by keep_until limit v_limit);
    get diagnostics v_ledger_out = row_count;
  end if;

  v_out := jsonb_build_object(
    'dry_run', p_dry,
    'source_record_staging', jsonb_build_object('due', cardinality(v_srs_ids), 'removed', v_srs, 'keep_days', v_keep,
       'by_source', coalesce((select jsonb_object_agg(coalesce(src.label, s.source_id::text, 'no source'), n)
                                from (select source_id, count(*) n from pipeline.source_record_staging where id = any (v_srs_ids) group by 1) s
                                left join pipeline.sources src on src.id = s.source_id), '{}'::jsonb)),
    'boost_inbound_staging', jsonb_build_object('due', cardinality(v_bis_ids), 'removed', v_bis, 'keep_days', v_bkeep),
    'hash_ledger', jsonb_build_object('rows', (select count(*) from pipeline.staging_hash_ledger), 'expired_removed', v_ledger_out, 'keep_years', v_years),
    'preserved', jsonb_build_object('destination_editions', (select count(*) from destination.editions),
                                    'layer1_dataset_editions', (select count(*) from pipeline.layer1_dataset_editions),
                                    'evidence_records', 'not touched (class regulatory_evidence)'));
  if cardinality(v_srs_ids) + cardinality(v_bis_ids) + v_ledger_out > 0 then
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('retention', case when p_dry then 'staging_retention_dry_run' else 'staging_retention' end, 'housekeeping-daily', v_out, null);
  end if;
  return v_out;
end $function$;
revoke all on function security.staging_retention_v1(boolean, timestamptz) from public, anon, authenticated;
comment on function security.staging_retention_v1(boolean, timestamptz) is 'CF-247 S1-Build (Platform Admin 17 Nov 2026 18:02): removes applied staging rows past their keep period (hash kept 7 years) or, as a dry run, reports them. Called by housekeeping-daily; editions and evidence are never touched.';

-- 4b. The unreferenced-evidence purge keeps evidence for retention.raw_hash_keep_years (7) as well as retention.evidence_min_age_days
create or replace function security.retention_evidence_candidates_v1()
 returns table(evidence_id uuid, storage_path text, created_at timestamp with time zone)
 language sql stable security definer set search_path to '' as $function$
  with a as (select r.started_at from pipeline.retention_runs r where r.category = 'evidence_audit' and r.status = 'done' order by r.finished_at desc limit 1)
  select e.id, e.storage_path, e.created_at
    from pipeline.evidence_artifacts e, a
   where e.created_at < least(a.started_at, now() - make_interval(days => security.pipeline_num_v1('retention.evidence_min_age_days', 7)::int),
                              now() - make_interval(years => security.pipeline_num_v1('retention.raw_hash_keep_years', 7)::int))
     and coalesce(e.retention_class, '') not in ('standard_365', 'source_evidence')
     and coalesce(e.storage_path, '') not like 'regulatory/%'
     and not exists (select 1 from pipeline.evidence_audit_refs r where r.evidence_id = e.id)
$function$;
update pipeline.platform_toolset_settings
   set help = 'The unreferenced-evidence purge never removes evidence younger than this many days, nor younger than retention.raw_hash_keep_years (7 years; Platform Admin 17 Nov 2026 18:25).'
 where toolset_key = 'pipeline' and key = 'retention.evidence_min_age_days';

-- 5. housekeeping-daily: the live body unchanged, plus the retention step
create or replace function security.housekeeping_daily_v1()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_limit int := security.pipeline_num_v1('batch.housekeeping_rows', 400000)::int; v_nonces int := 0; v_log int := 0; v_staging jsonb;
begin
  delete from pipeline.pilot_edge_nonces where id in (
    select n.id from pipeline.pilot_edge_nonces n
     where n.expires_at < now() - make_interval(days => security.pipeline_num_v1('retention.nonce_keep_days', 1)::int)
     limit v_limit);
  get diagnostics v_nonces = row_count;
  delete from cron.job_run_details where runid in (
    select d.runid from cron.job_run_details d
     where d.start_time < now() - make_interval(days => security.pipeline_num_v1('retention.job_log_keep_days', 3)::int)
     limit v_limit);
  get diagnostics v_log = row_count;
  if v_nonces + v_log > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('retention', 'housekeeping', 'housekeeping-daily', jsonb_build_object('request_codes', v_nonces, 'job_log', v_log), null);
  end if;
  -- staging retention (CF-247 S1-Build 17 Nov 2026): a dry run until retention.staging_prune_on is 1
  v_staging := security.staging_retention_v1(security.pipeline_num_v1('retention.staging_prune_on', 0) < 1);
  return jsonb_build_object('request_codes', v_nonces, 'job_log', v_log, 'staging', v_staging);
end $function$;
revoke execute on function security.housekeeping_daily_v1() from public, anon, authenticated;

update pipeline.automation_catalogue
   set description = 'Daily (about 03:47 Melbourne): removes expired one-time request codes and scheduled-job run records older than their settings, and settles applied staging rows past their keep period (Layer 1 staging 90 days, per source if set; settled Boost rows 90 days; hashes kept 7 years; editions and evidence never touched). Staging is a dry run until retention.staging_prune_on is 1. Settings › Pipeline settings › Housekeeping; each run is recorded in the admin events.'
 where jobname = 'housekeeping-daily';

-- 6. Telemetry views (read only)
create or replace view pipeline.ops_l1_apply_latency_v as
select q.id run_id, q.source_id, src.label source_label, q.country_code, q.status, q.started_at, q.completed_at,
       round(extract(epoch from (q.completed_at - q.started_at))::numeric, 1) seconds,
       q.processed_count, q.expected_count, q.failed_count, q.driver_dispatches,
       security.pipeline_num_v1('layer1.register_apply_chunk', 50)::int chunk_rows,
       ceil(coalesce(q.processed_count, 0) / greatest(security.pipeline_num_v1('layer1.register_apply_chunk', 50), 1))::int chunks,
       case when q.processed_count > 0 and q.completed_at is not null then
         round((extract(epoch from (q.completed_at - q.started_at)) * 1000
                / ceil(q.processed_count / greatest(security.pipeline_num_v1('layer1.register_apply_chunk', 50), 1)))::numeric, 0) end ms_per_chunk,
       case when q.processed_count > 0 and q.completed_at is not null then
         round((extract(epoch from (q.completed_at - q.started_at)) * 1000000 / q.processed_count)::numeric, 0) end ms_per_1000_records
  from pipeline.layer1_run_queue q
  left join pipeline.sources src on src.id = q.source_id
 where q.mode = 'apply'
   and q.requested_at > now() - make_interval(days => security.pipeline_num_v1('telemetry.window_days', 30)::int);
comment on view pipeline.ops_l1_apply_latency_v is 'CF-247 S1-Build ops telemetry: each Layer 1 register apply run in the look-back (telemetry.window_days) with its duration, records, chunks of layer1.register_apply_chunk rows and the time per chunk.';

create or replace view pipeline.ops_l4_escalation_by_source_v as
with w as (select now() - make_interval(days => security.pipeline_num_v1('telemetry.window_days', 30)::int) since),
ev as (select e.source_id, count(*) captured from pipeline.evidence_artifacts e, w where e.created_at > w.since group by 1),
l4 as (
  select e.source_id,
         count(*) items,
         count(*) filter (where r.status = 'pending') pending,
         count(*) filter (where r.status in ('approved', 'edited_approved')) approved,
         count(*) filter (where r.status = 'rejected') rejected,
         count(*) filter (where r.status in ('returned_layer2', 'returned_layer3')) returned,
         count(*) filter (where r.status = 'superseded') superseded,
         count(*) filter (where r.status = 'pending' and r.created_at < now() - make_interval(days => security.pipeline_num_v1('telemetry.l4_aged_days', 7)::int)) pending_aged,
         min(r.created_at) filter (where r.status = 'pending') oldest_pending
    from pipeline.layer4_review_items r
    left join pipeline.evidence_artifacts e on e.id = r.evidence_id, w
   where r.created_at > w.since
   group by 1)
select coalesce(l4.source_id, ev.source_id) source_id, coalesce(src.label, 'no source recorded') source_label, c.iso_alpha2 country_code,
       coalesce(ev.captured, 0) evidence_captured, coalesce(l4.items, 0) layer4_items,
       case when coalesce(ev.captured, 0) > 0 then round(coalesce(l4.items, 0)::numeric / ev.captured, 4) end escalation_rate,
       coalesce(l4.pending, 0) pending, coalesce(l4.pending_aged, 0) pending_aged, l4.oldest_pending,
       coalesce(l4.approved, 0) approved, coalesce(l4.rejected, 0) rejected, coalesce(l4.returned, 0) returned, coalesce(l4.superseded, 0) superseded
  from l4 full join ev
    on coalesce(ev.source_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(l4.source_id, '00000000-0000-0000-0000-000000000000'::uuid)
  left join pipeline.sources src on src.id = coalesce(l4.source_id, ev.source_id)
  left join ref.countries c on c.id = src.country_id
 where coalesce(l4.items, 0) > 0 or coalesce(ev.captured, 0) > 0;
comment on view pipeline.ops_l4_escalation_by_source_v is 'CF-247 S1-Build ops telemetry: per source over telemetry.window_days, evidence captured, Layer 4 review items raised from it (escalation rate = items / evidence) and their states, with pending items older than telemetry.l4_aged_days.';

create or replace view pipeline.ops_boost_vs_pr3_throughput_v as
with w as (select security.pipeline_num_v1('telemetry.window_days', 30)::int days,
                  security.pipeline_num_v1('boost.ingest_window_start_minute', 65)::int wfrom,
                  security.pipeline_num_v1('boost.ingest_window_end_minute', 290)::int wto),
d as (select (now() at time zone 'Australia/Melbourne')::date - g as day from w, generate_series(0, w.days - 1) g),
bf as (select (f.done_at at time zone 'Australia/Melbourne')::date as day, count(*) files, sum(coalesce(f.loaded, 0)) rows_loaded,
              count(*) filter (where f.status = 'failed') files_failed
         from pipeline.boost_ingest_files f where f.done_at is not null group by 1),
bs as (select (s.promoted_at at time zone 'Australia/Melbourne')::date as day, count(*) settled, count(*) filter (where s.promotion_state = 'admitted') admitted
         from pipeline.boost_inbound_staging s where s.promoted_at is not null group by 1),
cl as (select (r.tick_at at time zone 'Australia/Melbourne')::date as day,
              count(*) filter (where r.mode <> 'shadow' and r.status = 'succeeded') live_succeeded,
              count(*) filter (where r.mode <> 'shadow' and r.status not in ('succeeded', 'shadow_due', 'locked', 'already')) live_failed,
              count(*) filter (where r.mode <> 'shadow' and r.over_budget) live_over_budget,
              coalesce(sum(r.ms) filter (where r.mode <> 'shadow'), 0) live_ms,
              count(*) filter (where r.mode <> 'shadow' and r.status = 'succeeded'
                and not ((extract(hour from (r.tick_at at time zone 'Australia/Melbourne')) * 60 + extract(minute from (r.tick_at at time zone 'Australia/Melbourne')))
                         between w.wfrom and w.wto - 1)) daytime_succeeded,
              count(*) filter (where r.mode = 'shadow') shadow_due
         from pipeline.coverage_lane_runs r, w group by 1)
select d.day melbourne_date,
       coalesce(bf.files, 0) boost_files_loaded, coalesce(bf.files_failed, 0) boost_files_failed, coalesce(bf.rows_loaded, 0) boost_rows_loaded,
       coalesce(bs.settled, 0) boost_rows_settled, coalesce(bs.admitted, 0) boost_rows_admitted,
       coalesce(cl.live_succeeded, 0) pr3_runs_succeeded, coalesce(cl.daytime_succeeded, 0) pr3_daytime_runs_succeeded,
       coalesce(cl.live_failed, 0) pr3_runs_failed, coalesce(cl.live_over_budget, 0) pr3_runs_over_budget, coalesce(cl.live_ms, 0) pr3_live_ms,
       coalesce(cl.shadow_due, 0) pr3_shadow_due
  from d left join bf on bf.day = d.day left join bs on bs.day = d.day left join cl on cl.day = d.day;
comment on view pipeline.ops_boost_vs_pr3_throughput_v is 'CF-247 S1-Build ops telemetry: per Melbourne day over telemetry.window_days, nightly Boost ingestion (files and rows loaded, rows settled and admitted) beside PR 3 coverage lane runs (live succeeded, daytime outside the Boost window, failed, over budget, time; shadow rows while PR 3 is in shadow). PR 3 run rows are kept coverage_lane.keep_days.';

revoke all on pipeline.ops_l1_apply_latency_v, pipeline.ops_l4_escalation_by_source_v, pipeline.ops_boost_vs_pr3_throughput_v from public, anon, authenticated;
grant select on pipeline.ops_l1_apply_latency_v, pipeline.ops_l4_escalation_by_source_v, pipeline.ops_boost_vs_pr3_throughput_v to service_role;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'telemetry.l4_aged_days', 'Operations telemetry: Layer 4 item counts as aged after',
   'In Layer 4 escalation by source, a pending review item older than this many days counts as aged.',
   'number', to_jsonb(7), 1, 90, 'days', 766, 'Housekeeping', 'pipeline.ops_l4_escalation_by_source_v', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 18:02')
on conflict (toolset_key, key) do nothing;

-- 7. Admin calls (the Ops report and the retention controls)
create or replace function public.admin_ops_telemetry()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
  if auth.uid() is null and current_user <> 'postgres' then raise exception 'authentication required' using errcode = '42501'; end if;
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'window_days', security.pipeline_num_v1('telemetry.window_days', 30)::int,
    'l1_apply_latency', coalesce((select jsonb_agg(to_jsonb(v) order by v.started_at desc nulls first) from pipeline.ops_l1_apply_latency_v v), '[]'::jsonb),
    'l4_escalation_by_source', coalesce((select jsonb_agg(to_jsonb(v) order by v.layer4_items desc, v.evidence_captured desc) from pipeline.ops_l4_escalation_by_source_v v), '[]'::jsonb),
    'boost_vs_pr3', coalesce((select jsonb_agg(to_jsonb(v) order by v.melbourne_date desc) from pipeline.ops_boost_vs_pr3_throughput_v v), '[]'::jsonb),
    'staging_retention', (select jsonb_build_object('prune_on', security.pipeline_num_v1('retention.staging_prune_on', 0) >= 1,
                                                    'last', (select jsonb_build_object('at', e.created_at, 'action', e.action, 'detail', e.detail)
                                                               from pipeline.admin_control_events e
                                                              where e.area = 'retention' and e.action in ('staging_retention', 'staging_retention_dry_run')
                                                              order by e.created_at desc limit 1))));
end $function$;

create or replace function public.admin_source_retention_set(p_source_id uuid, p_keep_days int, p_reason text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_uid uuid := auth.uid(); v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to change a retention period' using errcode = '42501'; end if; -- fixed: retention is the Platform Admin's
  if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;
  if not exists (select 1 from pipeline.sources where id = p_source_id) then raise exception 'unknown source' using errcode = '22023'; end if;
  if p_keep_days is null then
    delete from pipeline.source_retention_policies where source_id = p_source_id;  -- back to retention.staging_keep_days
  else
    insert into pipeline.source_retention_policies (source_id, staging_keep_days, reason, updated_by, updated_at)
    values (p_source_id, p_keep_days, v_reason, v_uid, now())
    on conflict (source_id) do update set staging_keep_days = excluded.staging_keep_days, reason = excluded.reason, updated_by = excluded.updated_by, updated_at = now();
  end if;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('retention', 'source_retention_set', p_source_id::text, jsonb_build_object('staging_keep_days', p_keep_days, 'reason', v_reason), v_uid);
  return jsonb_build_object('source_id', p_source_id, 'staging_keep_days', p_keep_days);
end $function$;

create or replace function public.admin_staging_retention_preview()
returns jsonb language plpgsql security definer set search_path to '' as $function$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return security.staging_retention_v1(true);
end $function$;

revoke all on function public.admin_ops_telemetry(), public.admin_source_retention_set(uuid, int, text), public.admin_staging_retention_preview() from public, anon;
grant execute on function public.admin_ops_telemetry(), public.admin_source_retention_set(uuid, int, text), public.admin_staging_retention_preview() to authenticated, service_role;

-- 8. The register
insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('table', 'pipeline.source_retention_policies', 'Platform', 'Housekeeping', 'Per-source keep period for applied staging rows', 'active', '{}', '20261117200000'),
  ('table', 'pipeline.staging_hash_ledger', 'Platform', 'Housekeeping', 'Hashes of staging rows removed by housekeeping-daily, kept 7 years', 'active', '{}', '20261117200000'),
  ('function', 'security.staging_retention_v1', 'Platform', 'Housekeeping', 'Removes (or reports) applied staging rows past their keep period', 'active', '{}', '20261117200000'),
  ('view', 'pipeline.ops_l1_apply_latency_v', 'Platform', 'Operations telemetry', 'Layer 1 register apply latency per chunk', 'active', '{}', '20261117200000'),
  ('view', 'pipeline.ops_l4_escalation_by_source_v', 'Platform', 'Operations telemetry', 'Layer 4 escalation rate per source', 'active', '{}', '20261117200000'),
  ('view', 'pipeline.ops_boost_vs_pr3_throughput_v', 'Platform', 'Operations telemetry', 'Nightly Boost against daytime PR 3 throughput', 'active', '{}', '20261117200000')
on conflict do nothing;

-- 9. Post-checks
do $c$
declare v jsonb;
begin
  if pg_get_functiondef('security.housekeeping_daily_v1()'::regprocedure) not like '%security.staging_retention_v1(security.pipeline_num_v1(''retention.staging_prune_on'', 0) < 1)%' then
    raise exception 'post-check: housekeeping-daily does not call the retention step';
  end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline'
        and key in ('retention.staging_prune_on', 'retention.staging_keep_days', 'retention.boost_staging_keep_days', 'retention.raw_hash_keep_years',
                    'batch.staging_prune_rows', 'telemetry.window_days', 'telemetry.l4_aged_days')) <> 7 then
    raise exception 'post-check: retention or telemetry settings missing';
  end if;
  if not exists (select 1 from cron.job where jobname = 'housekeeping-daily' and active) then raise exception 'post-check: housekeeping-daily is not active'; end if;
  if (select count(*) from pipeline.retention_class_policies where class_key in ('applied_source_staging', 'staging_hash_ledger', 'published_editions')) <> 3 then
    raise exception 'post-check: retention classes missing';
  end if;
  v := security.staging_retention_v1(true);
  if (v->>'dry_run')::boolean is not true then raise exception 'post-check: the preview must be a dry run'; end if;
  perform count(*) from pipeline.ops_l1_apply_latency_v;
  perform count(*) from pipeline.ops_l4_escalation_by_source_v;
  perform count(*) from pipeline.ops_boost_vs_pr3_throughput_v;
  if has_table_privilege('anon', 'pipeline.ops_l4_escalation_by_source_v', 'select') or has_table_privilege('authenticated', 'pipeline.ops_l4_escalation_by_source_v', 'select') then
    raise exception 'post-check: a telemetry view is open to anon or authenticated';
  end if;
  if has_function_privilege('anon', 'public.admin_ops_telemetry()', 'execute') then raise exception 'post-check: admin_ops_telemetry is open to anon'; end if;
  if pg_get_functiondef('security.retention_evidence_candidates_v1()'::regprocedure) not like '%make_interval(years => security.pipeline_num_v1(''retention.raw_hash_keep_years'', 7)::int)%' then
    raise exception 'post-check: the evidence purge does not keep the 7-year floor';
  end if;
end $c$;
