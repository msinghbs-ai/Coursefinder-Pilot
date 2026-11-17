-- CF-247 F-SCH: the scholarship AI picker works on a bounded window, so a large queue cannot stop every reading (Platform Admin S2-Scholarship
-- directive 13 Nov 2026 §1 "keep the extraction and recovery jobs running", §7 continuous and efficient operation).
-- Why (live, 13 Nov 2026 01:10-01:20 UTC): no scholarship AI reading has completed since 12 Nov 15:12 UTC. The daily backfill at 15:13 queued
--   8,764 admission items; from 19:00 every worker call failed with "svc_scholarship_ai_next: canceling statement due to statement timeout"
--   (about 1,400 failed calls). Measured inside the picker: its first step, closing directory-site and search-off items, ran
--   security.third_party_host_v1 on every due item (8,981) - 27.0 s on its own, past the statement timeout - before anything was leased. The
--   rest is cheap (stored-copy check 1.2 s over all items, reuse 0.2 s, hidden providers 16 ms). 8,904 of the queued items already have a stored
--   copy and could be read now, including the 43 long-page recovery items queued today.
-- Change: the picker first takes ONE window of the next due items in its own order and filters (hidden providers, stored copy while the paid
--   lane is held), at most batch.sch_ai_pick_scan (60; the worker leases at most 20 a call); it closes directory-site and search-off items within that window only, and leases only
--   from that window. The directory-site and search-off checks run once per distinct site and provider in the window (the same functions on one
--   page of each site), not once per item. Every item still gets the same check before it is leased (none is leased unchecked); an item outside the window is
--   checked when it reaches the window. Items that could never be leased (hidden provider, or no stored copy while the lane is held) stay
--   queued instead of being closed early; they were not read either way.
-- Settings: batch.sch_ai_pick_scan (60 items, 20-2,000).
-- Measured on the live text in a rolled-back run: two picks of 8 took 1.9 s and 1.5 s (was over the statement timeout), no item leased twice.
-- Replaces: public.svc_scholarship_ai_next(integer) (same name and signature; md5-guarded edit of the live text).
-- Retires: the whole-queue directory-site and search-off scan at the start of every pick (replaced in place by the window; nothing to drop).

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
 ('pipeline', 'batch.sch_ai_pick_scan', 'Scholarship AI: items the picker checks at once',
  'How many of the next due scholarship AI items one worker call checks (directory site, scholarship search off) before it leases from them. Larger checks more per call but takes longer.',
  'number', '60'::jsonb, 20, 2000, 'items', 1540, 'F-SCH 13 Nov 2026: the picker checked every queued item each call and timed out at 8,981 items', 'Job sizes', 'public.svc_scholarship_ai_next')
on conflict (toolset_key, key) do nothing;

select pg_temp.edit_n('public.svc_scholarship_ai_next(integer)', '170f4e72a98bb0bb22d51a1cb4c0d7a7', array[
  -- 1. the lease is taken only from the checked window
  array[$o$or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
$o$, $n$or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3 and q.id = any(v_win)  -- F-SCH 13 Nov 2026: only from the checked window
$n$],
  -- 2. the window, in the picker's own order and filters
  array[$o$  -- v2.15.271 (Platform Admin, 14 Oct 2026): pages on a directory site$o$, $n$  -- CF-247 F-SCH 13 Nov 2026: one bounded window of the next items, in the picker's order and filters; only these are checked and leased
  -- (the due items are put in order first and the per-item checks run only until the window is full: offset 0 keeps them out of the sort)
  select array_agg(w.id) into v_win from (
    select o.id from (select q.id, q.provider_id, q.run_kind from pipeline.scholarship_ai_queue q
                       where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
                       order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, q.id offset 0) o
     where (o.provider_id is null or o.run_kind in ('test', 'qualify') or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = o.provider_id))
       and (v_paid or security.scholarship_ai_has_copy_v1(o.id))
     limit greatest(20, least(v_scan, 2000))) w;
  -- the same two checks, once per distinct site and provider in the window (one row each), not once per item: 67 ms for 200 items, was 1.1 s per item check
  select array_agg(h.host) into v_tp from (select distinct on (security.site_host_v1(w.url)) security.site_host_v1(w.url) host, w.url
                                              from pipeline.scholarship_ai_queue w where w.id = any(v_win)) h
   where h.host is not null and security.third_party_host_v1(h.url);
  select array_agg(p.provider_id) into v_off from (select distinct w.provider_id from pipeline.scholarship_ai_queue w where w.id = any(v_win) and w.provider_id is not null) p
   where security.provider_sch_search_off_v1(p.provider_id);
  -- v2.15.271 (Platform Admin, 14 Oct 2026): pages on a directory site$n$],
  -- 3. directory-site and search-off items are closed within the window, not across the whole queue
  array[$o$   where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now()))
     and (security.third_party_host_v1(q.url) or (q.provider_id is not null and security.provider_sch_search_off_v1(q.provider_id)));$o$,
        $n$   where q.id = any(v_win) and q.state in ('queued', 'leased')  -- F-SCH 13 Nov 2026: the window only (was every due item: 27 s at 8,981)
     and (security.site_host_v1(q.url) = any(v_tp) or q.provider_id = any(v_off));$n$],
  -- 4. declarations
  array[$o$declare v jsonb; v_reuse int := security.pipeline_num_v1('waste.page_reuse_hours', 24)::int;$o$,
        $n$declare v jsonb; v_reuse int := security.pipeline_num_v1('waste.page_reuse_hours', 24)::int; v_win bigint[]; v_tp text[]; v_off uuid[];
        v_scan int := security.pipeline_num_v1('batch.sch_ai_pick_scan', 60)::int;$n$]
], array[1, 1, 1, 1]);
