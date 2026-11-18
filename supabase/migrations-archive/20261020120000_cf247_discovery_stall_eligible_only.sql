-- CF-247 (20 Oct 2026). Platform health raised Critical "Coverage provider discovery has stopped: 85 waiting, nothing processed for 778
-- minutes". Found: discovery had not stopped. public.svc_coverage_discovery_next takes only providers in focus (security.enrich_focus_v1:
-- top-50 Australian focus, outside Australia, re-find waves; never one held as Course pages not found) that are not hidden; the health
-- check counted every pending or due row without those rules. The 85 were 42 held for a person (all in the Layer 4 Inbox) and 43 small
-- Australian providers outside the focus list. Platform Admin, 20 Oct 2026, choice "Also search the 43 small": the check counts only what
-- the job may take, and the 34 of them with 5 or more courses were put in re-find wave refind-2 (Build adapter, logged in
-- admin_control_events); the 9 with 1-4 courses stay CRICOS-only (19 Oct rule).
-- Replaces: security.platform_health_check_v1(boolean) (the coverage_queues:discover count uses the job's own eligibility; nothing else changes)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('security.platform_health_check_v1(boolean)', '47a4adf1e4aecddee0a1bb34301804ad', array[
  array[$o$d.next_due_at<=now())) and d.attempts<3$q$$o$,
        $n$d.next_due_at<=now())) and d.attempts<3 and security.enrich_focus_v1(d.provider_id) and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id=d.provider_id)$q$$n$]
]);
