-- CF-247 s833 (Platform Admin 20 Nov 2026 14:24 AEDT, chat S1-Courses): the Layer 4 course description queue no longer times out.
-- Found live after Pilot #1420 (rolled-back probes, 20 Nov 2026 14:30 to 14:40 AEDT): public.admin_course_description_queue('summary') took 37 s and ('items') 15 s against the 8 s limit.
--   Cause 1: every open re-checked the 159 pending descriptions against the rules one by one (security.course_description_check_v1, about 0.14 s each, 22 s),
--            both in the sample test (security.course_description_sample_ids_v1) and in the summary.
--   Cause 2: security.course_description_reconcile_v1 joined every one of the 271,000 AI reading rows, with their large JSON, to find 159 (4 to 12 s); the summary
--            copied every description reading and read its JSON for all of them (4 s).
-- What changes: (a) one stored row, pipeline.cdesc_queue_snapshot, rebuilt every 15 minutes by the new job cdesc-queue-refresh: the summary and every pending item
--   already checked against the rules, with the sample flag. (b) public.admin_course_description_queue answers 'summary' and 'items' (no provider, no recheck, no sample
--   search by provider) from that row when it is fresh (setting cdesc.queue_snapshot_max_age_minutes, 35); an item decided since is dropped at read time, so a decided card never
--   shows again. When the row is older, or the call names a provider or asks for a re-check, the live path runs exactly as before. (c) two in-place edits make the live path
--   faster: the reconcile reads its one reading by key; the summary reads only the state, reason and admitted flag of the readings it counts.
-- Nothing is decided, admitted or published by this change; no description, setting value, lock or spend changes. Firecrawl and AI: none.
-- Objects (no new public function, table or view): table pipeline.cdesc_queue_snapshot; functions security.cdesc_queue_refresh_v1(), security.cdesc_queue_stored_v1(text,int,boolean);
--   three md5-free but fragment-guarded in-place edits (each fragment must occur exactly once): public.admin_course_description_queue(text,jsonb) (signature unchanged),
--   security.course_description_reconcile_v1, security.course_description_summary_v1; one job cdesc-queue-refresh.
-- G1: the job is registered in pipeline.automation_catalogue and the component register. G2: the age limit is a setting (the 15 minute schedule is the job's cron, the 180 s time-out
--   is marked fixed). G3: no consumer API object; the consumer API baseline check is read before and after (75 functions, 48 relations, no drift).
-- Parity: head 20261120140000 (2,218 rows) read live 20 Nov 2026 14:25 AEDT; no open Pilot pull request; task number s833 above s832.
-- Replaces: the read-time re-check of every pending description on each open of the queue (kept as the fallback).
-- Retires: nothing. Nothing dropped, deleted or renamed.
-- Rollback: unschedule cdesc-queue-refresh (the queue then reads live again by itself after the setting's minutes); the three edits are each one fragment and can be reversed with the same helper.
set local lock_timeout = '5s';
set local statement_timeout = '180s';  -- fixed: the first rebuild of the stored queue runs the rule checks once (about 40 s)

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

-- setting (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'cdesc.queue_snapshot_max_age_minutes', 'Course description queue: oldest stored copy shown as current',
   'The Layer 4 course description queue (summary and cards) reads a stored copy rebuilt every 15 minutes. If the copy is older than this, the screen checks the rules live again, as before (slower).',
   'number', to_jsonb(35), 5, 240, 'minutes', 983, 'Course descriptions', 'public.admin_course_description_queue (security.cdesc_queue_stored_v1)', 'CF-247 s833 (Platform Admin 20 Nov 2026 14:24)')
on conflict (toolset_key, key) do nothing;

-- the stored queue: one row
create table if not exists pipeline.cdesc_queue_snapshot (
  id smallint primary key default 1 check (id = 1),
  summary jsonb not null,
  items jsonb not null,
  refreshed_at timestamptz not null default now(),
  run_ms integer not null default 0
);
alter table pipeline.cdesc_queue_snapshot enable row level security;
revoke all on table pipeline.cdesc_queue_snapshot from public, anon, authenticated;
comment on table pipeline.cdesc_queue_snapshot is 'CF-247 s833: the stored Layer 4 course description queue (summary and every pending card already checked against the rules), one row, rebuilt every 15 minutes by job cdesc-queue-refresh. Read only through security.cdesc_queue_stored_v1().';

-- one rebuild: the same figures and cards as the live functions, with the rule checks run once
create or replace function security.cdesc_queue_refresh_v1()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_t0 timestamptz := clock_timestamp(); v_cap int := security.pipeline_num_v1('enrich.course_description_report_max', 500)::int; v_summary jsonb; v_items jsonb; v_ms int;
begin
  if not pg_try_advisory_xact_lock(hashtext('cdesc_queue_refresh')) then return jsonb_build_object('ok', false, 'skipped', 'a rebuild is already running'); end if;
  perform set_config('statement_timeout', '180s', true);  -- fixed: the rule checks of up to 500 pending descriptions
  v_summary := security.course_description_summary_v1(null, false);
  with t as materialized (select * from security.course_description_reconcile_v1(null, true, v_cap)),
  pool as (
    select r.id item_id, k.iso_alpha2::text country
      from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
      join catalogue.providers pv on pv.id = c.provider_id join ref.countries k on k.id = pv.country_id
     where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.status <> 'superseded'
       and (r.status <> 'pending' or r.id in (select t.item_id from t where t.class = 'ready'))),
  strata as (select upper(x) code from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_sample_countries'), '[]'::jsonb)) x),
  ranked as (select pool.item_id, pool.country, row_number() over (partition by pool.country order by md5(pool.item_id::text)) rn from pool where pool.country in (select code from strata)),
  smp as (select ranked.item_id from ranked where ranked.rn <= security.pipeline_num_v1('enrich.course_description_sample_' || lower(ranked.country), 0)),
  pg as (select t.* from t where t.class = 'ready')
  select coalesce(jsonb_agg(jsonb_build_object(
        'kind', 'provider_description', 'ref', pg.item_id::text, 'provider_id', pg.provider_id, 'provider', coalesce(pv.display_name, pv.canonical_name), 'subject', pg.course_title,
        'why', coalesce(nullif(i.escalation_reason, ''), 'Needs a decision'), 'created_at', pg.created_at, 'ready', true,
        'detail', jsonb_strip_nulls(jsonb_build_object('field_code', i.field_code, 'course_id', pg.course_id, 'course_code', c.course_code,
                    'code_label', case when pg.country = 'AU' then 'CRICOS' else 'Course code' end,
                    'before', i.before_value, 'proposed', i.proposed_value, 'evidence_id', i.evidence_id, 'captured_at', ev.captured_at, 'source_url', ev.source_url,
                    'reask', pg.reask, 'in_sample', pg.item_id in (select smp.item_id from smp),
                    'rules_now', jsonb_build_object('ok', true))))
      order by pg.created_at, pg.item_id), '[]'::jsonb)
    into v_items
    from pg join pipeline.layer4_review_items i on i.id = pg.item_id
    join catalogue.courses c on c.id = pg.course_id
    left join catalogue.providers pv on pv.id = pg.provider_id
    left join pipeline.evidence_artifacts ev on ev.id = i.evidence_id;
  v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
  insert into pipeline.cdesc_queue_snapshot(id, summary, items, refreshed_at, run_ms) values (1, v_summary, v_items, now(), v_ms)
  on conflict (id) do update set summary = excluded.summary, items = excluded.items, refreshed_at = excluded.refreshed_at, run_ms = excluded.run_ms;
  return jsonb_build_object('ok', true, 'run_ms', v_ms, 'items', jsonb_array_length(v_items));
end $f$;
comment on function security.cdesc_queue_refresh_v1() is 'CF-247 s833: rebuilds pipeline.cdesc_queue_snapshot (job cdesc-queue-refresh, every 15 minutes). Same figures and cards as the live functions; the rule checks run once here instead of on every open.';

-- the read: the stored summary, or one page of the stored cards that are still pending; null when there is no fresh copy, so the caller reads live
create or replace function security.cdesc_queue_stored_v1(p_kind text, p_offset int, p_sample boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare s pipeline.cdesc_queue_snapshot; v_page int := security.pipeline_num_v1('layer4.inbox_page_size', 25)::int; v_off int := greatest(coalesce(p_offset, 0), 0); v_out jsonb;
begin
  select * into s from pipeline.cdesc_queue_snapshot where id = 1;
  if s.id is null or s.refreshed_at < now() - make_interval(mins => security.pipeline_num_v1('cdesc.queue_snapshot_max_age_minutes', 35)::int) then return null; end if;
  if p_kind = 'summary' then return s.summary || jsonb_build_object('stored_at', s.refreshed_at); end if;
  with live as (
    select e.item, e.ord from jsonb_array_elements(s.items) with ordinality e(item, ord)
      join pipeline.layer4_review_items i on i.id = (e.item->>'ref')::uuid and i.status = 'pending'
     where not coalesce(p_sample, false) or coalesce((e.item->'detail'->>'in_sample')::boolean, false)),
  pg as (select live.item, live.ord from live order by live.ord limit v_page offset v_off)
  select jsonb_build_object('total', (select count(*) from live), 'offset', v_off, 'limit', v_page,
                            'items', coalesce((select jsonb_agg(pg.item order by pg.ord) from pg), '[]'::jsonb), 'stored_at', s.refreshed_at)
    into v_out;
  return v_out;
end $f$;
comment on function security.cdesc_queue_stored_v1(text, int, boolean) is 'CF-247 s833: the stored course description queue (summary, or one page of cards still pending), or null when the stored copy is older than cdesc.queue_snapshot_max_age_minutes.';

-- in-place edits: each old fragment must occur exactly once, so a definition that has drifted stops the change instead of being overwritten
create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.cf_edit_def('security.course_description_reconcile_v1(uuid,boolean,integer)'::regprocedure,
  array[$o$left join pipeline.field_enrich_items e on e.id = p.eid$o$],
  array[$n$left join lateral (select f.id, f.value from pipeline.field_enrich_items f where f.id = p.eid) e on true$n$]);

select pg_temp.cf_edit_def('security.course_description_summary_v1(uuid,boolean)'::regprocedure,
  array[$o$fe as (select f.* from pipeline.field_enrich_items f where f.field = 'description' and (p_provider is null or f.provider_id = p_provider))$o$,
        $o$coalesce(fe.value->>'admitted', '') <> ''$o$],
  array[$n$fe as (select f.state, f.reason, case when f.state = 'filled' then f.value->>'admitted' end admitted from pipeline.field_enrich_items f where f.field = 'description' and f.state in ('skipped', 'filled') and (p_provider is null or f.provider_id = p_provider))$n$,
        $n$coalesce(fe.admitted, '') <> ''$n$]);

select pg_temp.cf_edit_def('public.admin_course_description_queue(text,jsonb)'::regprocedure,
  array[$o$when 'summary' then security.course_description_summary_v1(nullif(a->>'provider_id', '')::uuid, coalesce((a->>'recheck')::boolean, false))$o$,
        $o$when 'items' then security.course_description_items_v1(nullif(a->>'provider_id', '')::uuid, coalesce((a->>'offset')::int, 0), coalesce((a->>'sample')::boolean, false))$o$],
  array[$n$when 'summary' then coalesce(case when nullif(a->>'provider_id', '') is null and not coalesce((a->>'recheck')::boolean, false) then security.cdesc_queue_stored_v1('summary', 0, false) end,
                                         security.course_description_summary_v1(nullif(a->>'provider_id', '')::uuid, coalesce((a->>'recheck')::boolean, false)))$n$,
        $n$when 'items' then coalesce(case when nullif(a->>'provider_id', '') is null then security.cdesc_queue_stored_v1('items', coalesce((a->>'offset')::int, 0), coalesce((a->>'sample')::boolean, false)) end,
                                     security.course_description_items_v1(nullif(a->>'provider_id', '')::uuid, coalesce((a->>'offset')::int, 0), coalesce((a->>'sample')::boolean, false)))$n$]);

-- the job (G1)
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('cdesc-queue-refresh', 'Course descriptions', 5, 'Course description queue: rebuild the stored copy',
  'Every 15 minutes: checks every pending course description against the rules once and stores the summary and the cards in one row, so the Layer 4 course description queue opens in well under a second. If this job stops, the screen checks the rules live again after the stored copy is older than the setting Course description queue: oldest stored copy shown as current (slower, as before).',
  6, false)
on conflict (jobname) do nothing;

select cron.schedule('cdesc-queue-refresh', '7,22,37,52 * * * *', 'select security.cdesc_queue_refresh_v1()')
where not exists (select 1 from cron.job where jobname = 'cdesc-queue-refresh');

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'cdesc-queue-refresh', 'Layer 4', 'Course descriptions', 'Rebuilds the stored course description queue every 15 minutes', 'active', '{}', '20261120143000'),
  ('table', 'pipeline.cdesc_queue_snapshot', 'Layer 4', 'Course descriptions', 'The stored course description queue (one row)', 'active', '{}', '20261120143000'),
  ('function', 'security.cdesc_queue_refresh_v1', 'Layer 4', 'Course descriptions', 'One rebuild of the stored course description queue', 'active', '{}', '20261120143000'),
  ('function', 'security.cdesc_queue_stored_v1', 'Layer 4', 'Course descriptions', 'Reads the stored course description queue (summary or one page of cards)', 'active', '{}', '20261120143000')
on conflict do nothing;

-- the first rebuild, so the queue reads the stored copy from the first open
create temp table s833_run on commit drop as select security.cdesc_queue_refresh_v1() r;

-- post-checks: the stored copy equals the live one, both calls answer quickly as a Platform Admin, and the consumer API has not moved
do $c$
declare
  v jsonb := (select r from s833_run); v_admin uuid; t0 timestamptz; v_s_ms numeric; v_i_ms numeric; v_sum jsonb; v_items jsonb; v_live jsonb; v_api jsonb;
begin
  if not (v->>'ok')::boolean then raise exception 'post-check: the first rebuild failed: %', v; end if;
  if (v->>'run_ms')::int > 150000 then raise exception 'post-check: the rebuild took % ms (limit 150 s)', v->>'run_ms'; end if;
  if not exists (select 1 from cron.job where jobname = 'cdesc-queue-refresh' and active) then raise exception 'post-check: the job is not scheduled'; end if;

  select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  if v_admin is null then raise exception 'post-check: no Platform Admin to act as'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);

  t0 := clock_timestamp(); v_sum := public.admin_course_description_queue('summary', '{}'::jsonb); v_s_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  t0 := clock_timestamp(); v_items := public.admin_course_description_queue('items', '{}'::jsonb); v_i_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if v_s_ms > 300 or v_i_ms > 300 then raise exception 'post-check: summary % ms, items % ms (limit 300 ms)', round(v_s_ms), round(v_i_ms); end if;
  if v_sum->>'stored_at' is null or v_items->>'stored_at' is null then raise exception 'post-check: the calls did not answer from the stored copy'; end if;

  -- the stored copy says what the live functions say (the rechecked live count is the stored total; the pending count is the live pending count)
  v_live := security.course_description_summary_v1(null, false);
  if (v_sum->>'pending') is distinct from (v_live->>'pending') or (v_sum->'by_class') is distinct from (v_live->'by_class') then
    raise exception 'post-check: the stored summary differs from the live one (% vs %)', v_sum->>'pending', v_live->>'pending';
  end if;
  if (v_items->>'total')::int > (v_live->>'pending')::int then raise exception 'post-check: more stored cards than pending items'; end if;
  if jsonb_array_length(v_items->'items') > (v_items->>'limit')::int then raise exception 'post-check: a page holds more than the page size'; end if;

  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  raise notice 's833: rebuild % ms, % cards stored; as a Platform Admin summary % ms, items % ms', v->>'run_ms', v->>'items', round(v_s_ms), round(v_i_ms);
end $c$;
