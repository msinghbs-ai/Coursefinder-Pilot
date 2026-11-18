-- CF-247 F-AER.02 AER self-healing: a corrected read the reader skipped before reading is closed, so its waiting item is not blocked (Platform Admin decision delivery
-- item 4, 11 Nov 2026, SS-017 / Operating Model v1.12: "Recover the ... pending re-reads without duplicate Layer 4 items").
-- Guards: G1 (no job added: the existing hourly aer-scheduled-read settles), G2 (no new operational value), G3 (no consumer API object read or changed), Decision 260 (housekeeping),
--   "a passing qualification never switches anything on by itself".
-- Evidence (production, read only, 11 Nov 2026 21:30 AEDT, project fxcwkweaxjtknorudmwp):
--   * 8 corrected reads (pipeline.aer_read_supersessions) were still 'requested': 5 since 3-4 Nov (RMIT research degrees x2, University of Auckland x3) and 3 asked today (RMIT).
--     Each one's read (pipeline.field_enrich_items) was 'skipped' within a minute of the request: "no proven course page: the page found is not proved to be this course's
--     (E16)". A supersession is closed only when a read records a result (security.enrich_entry_record_v1); a read skipped before the worker records none, so these never closed.
--     Of 277 corrected reads skipped in all, 269 closed this way and these 8 did not.
--   * While 'requested', the item is blocked: the recovery rule answers "a corrected read of this item is waiting for the reader", the held picker and every other recovery
--     leave it, and Layer 4 counts it as waiting_technical. Each of the 8 old items is still the course's one pending Layer 4 item (no duplicate).
--   * Dry run (rolled back): closing the 8 as refused leaves 8 pending items, 0 new; the recovery rule then classes each as changed_conditions and the held picker picks none
--     (the corrected-read check still refuses an unproved page), so no read is asked again on unchanged evidence.
-- What: security.aer_supersession_settle_v1 NEW: closes as 'refused' every requested supersession whose read was skipped (more than 10 minutes ago) or is gone, with the reader's
--   reason; the old item stays as it is. security.aer_schedule_tick_v1 (md5-guarded edit): runs it at the start of each non-preview run. Run once now.
-- Live definitions this change edits (pg_proc.prosrc md5, read 11 Nov 2026 21:30 AEDT), before -> after:
--   security.aer_schedule_tick_v1(boolean) b96163772b72f02b6c9956b1a263224a -> 800af9161234c24387bff6a74d6acb99
-- Replaces: security.aer_schedule_tick_v1 (same name; md5-guarded text edit, resulting md5 checked); taken back by supabase/held/aer_supersession_settle_forward_recovery.sql
-- Retires: nothing.

do $g$ begin
  if to_regprocedure('security.aer_schedule_tick_v1(boolean)') is null or to_regprocedure('security.aer_read_supersession_close_v1(uuid,text,text,uuid,jsonb)') is null
     or to_regclass('pipeline.aer_read_supersessions') is null or to_regclass('pipeline.field_enrich_items') is null then raise exception 'an object this change uses is missing'; end if;
end $g$;

create or replace function security.aer_supersession_settle_v1()
returns integer language plpgsql security definer set search_path = '' as $f$
declare r record; v_n int := 0;
begin
  for r in select s.id, e.id e_id, e.reason
             from pipeline.aer_read_supersessions s left join pipeline.field_enrich_items e on e.id = s.enrich_item_id
            where s.state = 'requested' and s.enrich_item_id is not null
              and (e.id is null or (e.state = 'skipped' and e.updated_at < now() - interval '10 minutes'))  -- fixed: the read's claim timer
            for update of s skip locked loop
    perform security.aer_read_supersession_close_v1(r.id, 'refused',
      case when r.e_id is null then 'the corrected read was not made: its read no longer exists'
           else 'the corrected read was not made: ' || coalesce(nullif(btrim(r.reason), ''), 'skipped by the reader') end, null, null);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $f$;
revoke all on function security.aer_supersession_settle_v1() from public, anon, authenticated;
comment on function security.aer_supersession_settle_v1() is 'CF-247 F-AER.02: closes as refused every corrected read (aer_read_supersessions) whose read was skipped before reading or is gone, with the reader''s reason, so its waiting item is not blocked. Run by security.aer_schedule_tick_v1.';

do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_schedule_tick_v1(boolean)', 'b96163772b72f02b6c9956b1a263224a', '800af9161234c24387bff6a74d6acb99',
     array[$o$  select c.owner into v_owner from pipeline.field_gap_queue_control c where c.id = 1;$o$],
     array[$n$  -- 12 Nov 2026 (F-AER.02): a corrected read the reader skipped before reading records nothing; close it as refused so its item is not blocked
  if not p_preview then perform security.aer_supersession_settle_v1(); end if;
  select c.owner into v_owner from pipeline.field_gap_queue_control c where c.id = 1;$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
    raise notice '%: applied', r.sig;
  end loop;
end $m$;

do $once$ begin raise notice 'corrected reads settled now: %', security.aer_supersession_settle_v1(); end $once$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_supersession_settle_v1', 'Layer 2', 'Closes corrected reads skipped before reading, so their waiting items are not blocked', 'active', '{}', '20261112123700')
on conflict do nothing;

do $post$ begin
  if position('aer_supersession_settle_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_schedule_tick_v1(boolean)'::regprocedure)) = 0 then raise exception 'post-check: the tick does not settle'; end if;
end $post$;
