-- CF-247 F-SCH.15: the scholarship AI lane holds on a vendor-side block instead of closing the queue, re-queues what the block closed, and reads
-- never-decided pages before re-reads of earlier refused ones (Platform Admin S2-Scholarship directive 13 Nov 2026 23:07, Priority 3).
-- Why (live, 13 Nov 2026 12:10 UTC):
--   1. From 11:07 UTC every OpenRouter call answered HTTP 403 "Key limit exceeded (weekly limit)" (the key's weekly limit, not the account
--      balance of US$49.99). The lane kept firing five calls a minute; 2,360 readings failed and 1,154 queue items were closed on that error
--      (678 after one try, 476 after three); 194 more are queued with a failed try. Nothing paid ran on any lane after 11:06. ai_use_refusal_v1 knows the credit floor and ceilings, not a key limit.
--      The lane was paused by hand at 12:15 UTC (scholarship_ai_extract_settings.calls_at_once 5 -> 0, control event 47420).
--   2. The queue reads oldest first: 1,793 re-readings of pages refused under the old rules (queued 12 Nov 15:00) come before today's
--      never-decided pages (VUW 54, Notre Dame's official award PDFs, new Canadian university pages).
-- Change:
--   1. security.scholarship_ai_fire_v1: while the latest vendor block (HTTP 403 with "limit", or HTTP 402) within
--      scholarship.vendor_block_lookback_hours (24) has no success after it, the lane sends one probe call a minute, not calls_at_once; the first
--      success after the block re-queues the items the block closed (security.scholarship_ai_vendor_requeue_v1, at most
--      batch.sch_ai_vendor_requeue a minute), so nothing is lost and no person has to resume the lane.
--   2. public.svc_scholarship_ai_next: within the same order, never-decided pages (and records with no candidate) come before re-readings of
--      candidates already refused or admitted.
--   3. calls_at_once back to 5 (the pause is replaced by the automatic hold).
-- Settings: scholarship.vendor_block_lookback_hours (24 hours, 1-168), batch.sch_ai_vendor_requeue (500 items, 10-5,000).
-- Replaces: security.scholarship_ai_fire_v1(), public.svc_scholarship_ai_next(integer) (same names and signatures; md5-guarded edits).
-- Retires: the manual pause of 12:15 UTC (calls_at_once restored by this change).

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values
 ('pipeline', 'scholarship.vendor_block_lookback_hours', 'Scholarship AI: how far back a vendor block is looked for',
  'An OpenRouter key limit (HTTP 403) or no credit (HTTP 402) within this time, with no success after it, holds the lane to one probe call a minute; the first success re-queues what the block closed.',
  'number', '24'::jsonb, 1, 168, 'hours', 1541, 'F-SCH.15 (13 Nov 2026): a key weekly limit closed 2,508 queue items in an hour', 'Job sizes', 'security.scholarship_ai_fire_v1'),
 ('pipeline', 'batch.sch_ai_vendor_requeue', 'Scholarship AI: items re-queued after a vendor block, per minute',
  'How many queue items closed by a vendor block are put back each minute once calls succeed again.',
  'number', '500'::jsonb, 10, 5000, 'items', 1542, 'F-SCH.15 (13 Nov 2026)', 'Job sizes', 'security.scholarship_ai_vendor_requeue_v1')
on conflict (toolset_key, key) do nothing;

create index if not exists scholarship_ai_extractions_at_idx on pipeline.scholarship_ai_extractions (at desc);

create or replace function security.scholarship_ai_vendor_requeue_v1(p_since timestamptz) returns integer
language plpgsql security definer set search_path to '' as $f$
-- F-SCH.15: queue items whose last reading failed on a vendor block (key limit or no credit) since p_since go back to the queue, untried
declare v_n int;
begin
  with x as (
    select q.id from pipeline.scholarship_ai_queue q
     where q.state = 'done' and q.done_at >= p_since
       and exists (select 1 from pipeline.scholarship_ai_extractions e where e.id = q.extraction_id  -- the item's last reading
                    and (e.error like 'HTTP 403%limit%' or e.error like 'HTTP 402%'))
     order by q.id limit greatest(1, security.pipeline_num_v1('batch.sch_ai_vendor_requeue', 500)::int)
     for update skip locked)
  update pipeline.scholarship_ai_queue q set state = 'queued', attempts = 0, next_try_at = now(), done_at = null, leased_until = null
    from x where q.id = x.id;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail)
    values ('scholarship_ai', 'vendor_requeue', 'pipeline.scholarship_ai_queue', jsonb_build_object('requeued', v_n, 'since', p_since));
  end if;
  return v_n;
end $f$;

select pg_temp.edit_n('security.scholarship_ai_fire_v1()', '3d48dc20a4e9a571266f3de243a31545', array[
  array[$o$declare v_open int; v_max int; v_due int; v_sent int := 0;$o$, $n$declare v_open int; v_max int; v_due int; v_sent int := 0; v_block timestamptz; v_okat timestamptz;$n$],
  array[$o$  select calls_at_once into v_max from pipeline.scholarship_ai_extract_settings where id = 1;
$o$, $n$  select calls_at_once into v_max from pipeline.scholarship_ai_extract_settings where id = 1;
  -- F-SCH.15 (13 Nov 2026): a vendor-side block (OpenRouter key limit HTTP 403, no credit HTTP 402) holds the lane to one probe call; the first
  -- success after it re-queues the items the block closed
  select max(e.at) into v_block from pipeline.scholarship_ai_extractions e
   where e.at > now() - make_interval(hours => security.pipeline_num_v1('scholarship.vendor_block_lookback_hours', 24)::int)
     and (e.error like 'HTTP 403%limit%' or e.error like 'HTTP 402%');
  if v_block is not null then
    select max(e.at) into v_okat from pipeline.scholarship_ai_extractions e where e.at > v_block and e.error is null;
    if v_okat is null then v_max := least(coalesce(v_max, 3), 1);  -- fixed: one probe call while the vendor refuses
    else perform security.scholarship_ai_vendor_requeue_v1(v_block - make_interval(hours => security.pipeline_num_v1('scholarship.vendor_block_lookback_hours', 24)::int)); end if;
  end if;
$n$]
], array[1, 1]);

select pg_temp.edit_n('public.svc_scholarship_ai_next(integer)', '8b24b21a104963db0e2a9429ca03b627', array[
  array[$o$    select o.id from (select q.id, q.provider_id, q.run_kind from pipeline.scholarship_ai_queue q
$o$, $n$    select o.id from (select q.id, q.provider_id, q.run_kind from pipeline.scholarship_ai_queue q
                       left join pipeline.scholarship_page_candidates cd on cd.id = q.candidate_id  -- F-SCH.15: never-decided pages first
$n$],
  array[$o$                       order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, q.id offset 0) o$o$,
        $n$                       order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, (cd.admit_status is not null), q.id offset 0) o$n$]
], array[1, 1]);

update pipeline.scholarship_ai_extract_settings set calls_at_once = 5, changed_at = now(), changed_by = null,
       reason = 'F-SCH.15 (migration 20261113373500): the manual pause of 12:15 UTC is replaced by the automatic vendor-block hold (one probe call until a success, then re-queue). Back to 5.'
 where id = 1 and calls_at_once = 0;
insert into pipeline.admin_control_events(area, action, target, detail)
values ('scholarship_ai', 'resumed', 'pipeline.scholarship_ai_extract_settings.calls_at_once', jsonb_build_object('to', 5, 'by', 'migration 20261113373500', 'why', 'automatic vendor-block hold in place'));
