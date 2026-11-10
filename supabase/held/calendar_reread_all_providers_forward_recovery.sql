-- HELD (not a migration): forward recovery for the calendar re-read scope change (security.calendar_reread_relevant_v2; public.svc_calendar_reread_next_v2 reads it).
-- Run only if the Platform Admin decides to go back to the 5 Nov 2026 pilot scope for the calendar re-read. It puts back, byte for byte, the body of
-- public.svc_calendar_reread_next_v2(integer,text) (body md5 755ef3b77c797c89fa2caa215e33d4ee), guarded by the md5 of what is live now: it changes nothing if the live body is neither
-- that text nor the one the migration wrote (6bede79de2f656b4bc9de6ea783696b6). security.calendar_reread_relevant_v2 stays, unused (nothing is dropped). Readings already made,
-- proposals and decisions are not touched; the picker's existing "set aside" step puts non-pilot calendars aside again on its next run. Running it twice changes nothing.

create or replace function pg_temp.restore(p_sig text, p_now text, p_earlier text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig::regprocedure), chr(13), ''); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  if md5(v_src) = p_earlier then raise notice '%: nothing to restore', p_sig; return p_sig || ': nothing to restore'; end if;
  if md5(v_src) <> p_now then raise exception 'live % differs from both texts this recovery knows (body md5 %)', p_sig, md5(v_src); end if;
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_earlier then raise exception '% after the restore has body md5 %, expected %', p_sig, md5(v_src), p_earlier; end if;
  raise notice '%: restored', p_sig;
  return p_sig || ': restored';
end $f$;

select pg_temp.restore('public.svc_calendar_reread_next_v2(integer,text)', '6bede79de2f656b4bc9de6ea783696b6', '755ef3b77c797c89fa2caa215e33d4ee',
  array[$n$from security.calendar_reread_relevant_v2() x;$n$], array[$o$from security.calendar_reread_relevant_v1() x;$o$]);
