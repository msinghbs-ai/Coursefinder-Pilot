-- CF-247 F-PDESC (Platform Admin Directive 3, 9 Nov 2026, Blocker D "Throughput"): the reader's dispatch guard no longer skips a fire that is exactly one window after the last dispatch.
--
-- Live evidence (read 9 Nov 2026, project fxcwkweaxjtknorudmwp): the job fires at :06, :16, :26 and :56; pdesc.every_minutes is 10 (its floor). security.provider_description_fire_v1 asks "was a worker
-- call logged in the last pdesc.every_minutes minutes?" with a strict comparison. A dispatch logged at 23:06:00.326 is still inside the window at 23:16:00.314 (the cron job starts a few milliseconds
-- earlier each time), so the :16 fire sent nothing and the reader dispatched on every other fire only (:06, :26, :56 = three an hour, not four).
--
-- The edit adds 30 seconds of tolerance to that one comparison, marked fixed (a fire guard, not an operational value). The setting pdesc.every_minutes, its floor, the 4-minute in-flight guard, the AI
-- ceiling, the Firecrawl ceiling, the machine switches and the job schedule are unchanged. Manual Run Now is unchanged (it sets v_last to null).
--
-- Live definition this change edits (pg_proc.prosrc md5, read 9 Nov 2026): security.provider_description_fire_v1() fc835699c88759e4a0b12c6d95e47965 -> 21662da5fc9c4e15facbaef47b63a50f
-- Replaces: the strict dispatch-window comparison in security.provider_description_fire_v1 (edited in place; the function is not replaced)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object is touched (G3).

do $g$
begin
  if to_regprocedure('security.provider_description_fire_v1()') is null then raise exception 'required security.provider_description_fire_v1() is missing'; end if;
end $g$;

create or replace function pg_temp.edit_one(p_sig text, p_before text, p_after text, p_old text, p_new text) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_one('security.provider_description_fire_v1()', 'fc835699c88759e4a0b12c6d95e47965', '21662da5fc9c4e15facbaef47b63a50f',
$old$make_interval(mins => security.pipeline_num_v1('pdesc.every_minutes', 60)::int);$old$,
$new$make_interval(mins => security.pipeline_num_v1('pdesc.every_minutes', 60)::int) + interval '30 seconds'; -- fixed: fire jitter, so a fire exactly one window after the last dispatch is not blocked by the milliseconds that dispatch started after its minute$new$);
