-- CF-247 intake fairness: focus priority within each round (Platform Admin direction 5 Nov 2026 15:50 §3 "Retain approved focus priority.
-- Allocate a bounded opportunity across eligible providers"; decision 16:36 §2 "Fair processing across eligible universities").
-- Why (production, 17:26, first scheduled run of v2.15.482): within a round the plan took the university served longest ago first and only
--   then the focus rank. Universities never served by the intake-dates job (for example William Angliss, VIT, ICHM, Albright, outside the
--   focus list) therefore came before the focus universities served at 10:26 (UNSW, Sydney, Melbourne, Newcastle and the rest of the top 10):
--   200 rows over 12 providers, none of the top 10. Fairness held (at most 25 each); focus priority did not.
-- What: within each round, focus universities come first, longest waiting first among them, then focus rank; universities outside the focus
--   list follow in the same order. Rounds, the share (intake_dates.provider_share), the batch, fingerprints, revisits, holds and locks are
--   unchanged. A focus university with no eligible rows takes nothing and blocks nobody, as before.
-- Consumer API: unchanged (G3).
-- Replaces: md5-guarded edit of security.intake_dates_plan_v3 (67e93081)
-- Retires: nothing
-- Nothing is dropped or deleted.

create or replace function pg_temp.edit(p_sig text, p_md5 text, p_marker text, p_old text[], p_new text[], p_times int[]) returns text language plpgsql as $e$
declare v text := pg_get_functiondef(p_sig::regprocedure); i int; n int;
begin
  if position(p_marker in v) > 0 then return p_sig || ': already applied'; end if;
  if md5(v) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %, expected %)', p_sig, md5(v), p_md5; end if;
  for i in 1 .. array_length(p_old, 1) loop
    n := (length(v) - length(replace(v, p_old[i], ''))) / length(p_old[i]);
    if n <> p_times[i] then raise exception '%: edit % must apply exactly % time(s), found %', p_sig, i, p_times[i], n; end if;
    v := replace(v, p_old[i], p_new[i]);
  end loop;
  execute v;
  return p_sig || ': edited';
end $e$;

select pg_temp.edit('security.intake_dates_plan_v3(uuid[],integer)', '67e930818ee190f9124af45093be2ff0', 'focus universities first within a round',
  array[$o$v_share), sets.served nulls first, f.rank nulls last, c.provider_id, i.course_id, i.id$o$],
  array[$n$v_share),
              (f.rank is null), sets.served nulls first, f.rank nulls last, c.provider_id, i.course_id, i.id  -- focus universities first within a round (direction 5 Nov 2026 15:50 §3), longest waiting first among them$n$],
  array[1]);
