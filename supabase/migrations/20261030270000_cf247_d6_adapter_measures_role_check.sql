-- CF-247 decision D6 (Platform Admin 30 Oct 2026 08:45; admin decision paper §11.3): correct the ineffective security-definer role check
-- in public.admin_adapter_measures. APPROVED. "Enforce the originally intended server-side role/permission boundary; do not invent a broader
-- or narrower role policy. Keep migration/service execution paths working where legitimately required."
-- Design: the lane D6 design note, adopted as admin decision paper §11.3. Follows A5 (20261030080000), which corrected the same idiom in public.admin_entry_matrix_reread.
--
-- The check written on 5 Oct 2026 (archive 20261005001390, line 10) was
--   if current_user <> 'postgres' and (auth.uid() is null or coalesce(v_rank, 0) < 5) then raise ...
-- Inside this security definer function current_user is always the owner (postgres), so the test never fired and any signed-in user (and
-- service_role) could read the measures over the API (proven live 30 Oct 2026 by a rolled-back dry run as a rank 3 curator).
-- Now a request carrying JWT claims (any API caller) must be a signed-in user of rank 5 or above, as written on 5 Oct 2026 (the threshold
-- and the message 'Platform Admin or Operator required' are kept exactly); a direct owner session without claims (a migration, the SQL editor,
-- the wave measures taken from a database session) runs it as before. Nothing else in the function changes: the query body is byte-identical.
-- No cron job, database function, frontend code or edge function calls it (verified live 30 Oct 2026). Grants restated unchanged.
--
-- Replaces: public.admin_adapter_measures (same name and signature, md5-guarded edit of its role check only)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new job, table, setting, status or event action. Consumer API not touched (G3, Decision 266).

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

-- the live definition must be the one this change was written against (checked before anything changes); one edit, applied exactly once
select pg_temp.edit_n('public.admin_adapter_measures(uuid[])', 'b1417eafad2aa7a9ed11e3af65e848e8', array[
  array[$o$  if current_user <> 'postgres' and (auth.uid() is null or coalesce(v_rank, 0) < 5) then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;$o$,
        $n$  -- D6 (30 Oct 2026): a request through the API (JWT claims present) must be a signed-in user of rank 5 or above (Platform Admin or Operator, as written on 5 Oct 2026); a direct database session (the owner, a migration) has no claims. (current_user is always the owner inside a security definer function, so it cannot tell them apart)
  if (auth.uid() is not null or coalesce(auth.role(), '') <> '') and (auth.uid() is null or coalesce(v_rank, 0) < 5) then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;$n$]
], array[1]);

revoke all on function public.admin_adapter_measures(uuid[]) from public, anon;
grant execute on function public.admin_adapter_measures(uuid[]) to authenticated;
comment on function public.admin_adapter_measures(uuid[]) is 'CF-247 Decision 254: adapter measures per university (pages read; intakes, fees, IELTS and extra fields read by the adapter compared with held values). Read only. D6 (30 Oct 2026): API callers must be signed in with rank 5 or above (Platform Admin or Operator); a direct owner session without JWT claims is allowed.';

-- post-check: the new definition, the corrected check, no current_user test left, grants unchanged, the owner path still answers
do $$
declare v_def text := pg_get_functiondef('public.admin_adapter_measures(uuid[])'::regprocedure);
begin
  if md5(v_def) <> '8ad49afc3fdc03a94dda380404fa7a60' then raise exception 'D6 post-check: admin_adapter_measures md5 is % (expected 8ad49afc3fdc03a94dda380404fa7a60)', md5(v_def); end if;
  if position($c$if (auth.uid() is not null or coalesce(auth.role(), '') <> '') and (auth.uid() is null or coalesce(v_rank, 0) < 5) then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;$c$ in v_def) = 0 then
    raise exception 'D6 post-check: the corrected role check is missing'; end if;
  if v_def ~ 'current_user\s*<>' then raise exception 'D6 post-check: a current_user test is still in the function'; end if;
  if not has_function_privilege('authenticated', 'public.admin_adapter_measures(uuid[])', 'execute')
     or has_function_privilege('anon', 'public.admin_adapter_measures(uuid[])', 'execute') then
    raise exception 'D6 post-check: grants on admin_adapter_measures changed'; end if;
  if public.admin_adapter_measures(array[]::uuid[]) <> '[]'::jsonb then raise exception 'D6 post-check: the owner session no longer runs the measures'; end if;
end $$;
