-- CF-247 (Platform Admin decision, 28 Sep 2026): RMIT's weekly Layer 2 course refresh, disabled on 27 Aug under
-- CF-CHG-20260827-044 while RMIT canonical promotion was blocked, is switched back on. Today's rules apply to its
-- output: tuition candidates go through Layer 3 (Decision 160) and anything unsure goes to Layer 4; other fields
-- follow the Decision 152 admission lifecycle. First run due now; then weekly.
do $u$
declare v_n int;
begin
  update pipeline.refresh_policies
     set enabled=true, next_due_at=now(), change_control_ref='CF-CHG-20260915-247', updated_at=now()
   where id='fb417692-1c59-43ca-a5c4-924b5034b437' and source_profile_id='726918ee-10e9-41e3-9a2a-5dace20af754'
     and layer=2 and enabled=false;
  get diagnostics v_n=row_count;
  if v_n<>1 then raise exception 'RMIT weekly refresh policy not found in its disabled state; nothing changed'; end if;
end $u$;
