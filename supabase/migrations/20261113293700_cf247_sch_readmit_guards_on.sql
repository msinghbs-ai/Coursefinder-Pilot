-- CF-247 F-SCH safe re-admission (Platform Admin S2-Scholarship directive 13 Nov 2026 §3; Operating Model v1.19 S2-Scholarship 3).
-- Review of the deployed path (20261113260000) against the eight conditions before the gate is used:
--   1 withdrawal actor/reason: machine (20261113062000, F-SCH.01 post-activation check), reason eligibility_proof_not_specific   - checked
--   2 own single-award official page with sufficient eligibility evidence                                                          - checked
--     (security.scholarship_page_names_award_v1), BUT the page's currency was not checked: the positive test case, Sydney Bowel
--     Cancer Translational Research Scholarship, has one round only (opened 28 Mar 2019, closed 14 May 2019; the page was last changed
--     in 2020; read again 13 Nov 2026). Its eligibility sentence is right, but there is no evidence the award is offered now, and the
--     normal publication check would have published it (security.scholarship_publishability_for_v1 returned publishable: true).
--   3 provider and scholarship identity (same candidate, same record, provider site)                                               - checked
--   4 no protected human rejection, manual lock or contradictory decision: not checked by the path                                 - added
--   5 same scholarship ID reused; 6 unpublished on restore; 8 publication checks and withdrawal remain                             - checked
--   7 course links rebuilt only by the same scope rule that made them (security.scholarship_sweep_apply_v1)                        - checked
-- This change adds the two missing guards, in one place used by both the reader and the restore function:
--   security.scholarship_readmit_blocker_v1(scholarship) returns the reason a withdrawn record must not be restored, or null:
--     human_decision   a manual lock on the record, a Layer 4 block decision, or a person's scholarship review that rejected it
--     round_closed     the last recorded application round closed more than sch_elig.readmit_round_stale_days ago (default 365) and no
--                      application window closes today or later and applications are not recorded as rolling (unknown dates do not block)
--   The reader records readmit_human_decision / readmit_round_closed; security.scholarship_readmit_v1 refuses with the same reason.
-- With the guards in place the gate is used: sch_elig.readmit_on 0 -> 1, and the held re-admission read is re-evaluated. Expected and
-- verified in a rolled-back run against live: Sydney Bowel Cancer readmit_round_closed (not restored); Charles Perkins
-- readmit_page_not_specific and UTS Gullotta linked_page_not_scholarship (unchanged). No record is restored by this change.
-- Replaces: security.scholarship_eligibility_apply_v1(integer), security.scholarship_readmit_v1(bigint, jsonb) (same names and signatures;
--   md5-guarded edits). Retires: nothing.

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
values ('pipeline', 'sch_elig.readmit_round_stale_days', 'Scholarship re-admission: a closed round older than this is not restored',
        'A withdrawn scholarship is not admitted again when its last recorded application round closed more than this many days ago, no window closes today or later and applications are not rolling. Unknown dates do not block.',
        'number', '365'::jsonb, 30, 1825, 'days', 1424, 'F-SCH 13 Nov 2026: Sydney Bowel Cancer (one 2019 round) must not be restored', 'Scholarship eligibility reader', 'security.scholarship_readmit_blocker_v1')
on conflict (toolset_key, key) do nothing;

create or replace function security.scholarship_readmit_blocker_v1(p_scholarship uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from pipeline.manual_locks l where l.entity_id = p_scholarship)
      or exists (select 1 from pipeline.layer4_block_decisions b where b.entity_id = p_scholarship)
      or exists (select 1 from pipeline.scholarship_ai_reviews a where a.scholarship_id = p_scholarship and a.decided_by is not null
                  and coalesce(a.decision->>'decision', a.status) in ('refuse', 'refused', 'reject', 'rejected'))
      then 'human_decision'
    when s.application_close_date is not null
         and s.application_close_date < current_date - security.pipeline_num_v1('sch_elig.readmit_round_stale_days', 365)::int
         and not exists (select 1 from scholarship.application_windows w where w.scholarship_id = p_scholarship and w.closes_at >= current_date)
         and coalesce((select ad.application_rolling from scholarship.award_details ad where ad.scholarship_id = p_scholarship), false) is not true
      then 'round_closed'
    end
  from scholarship.scholarships s where s.id = p_scholarship
$$;
comment on function security.scholarship_readmit_blocker_v1(uuid) is
  'F-SCH re-admission guard: human_decision (manual lock, Layer 4 block, a person''s rejecting review) or round_closed (last round closed beyond sch_elig.readmit_round_stale_days, nothing open, not rolling); null when restoration may proceed.';
revoke all on function security.scholarship_readmit_blocker_v1(uuid) from public, anon, authenticated;

-- the reader: the guard is checked after the own-page check
select pg_temp.edit_n('security.scholarship_eligibility_apply_v1(integer)', 'c757df391e638712d52c7da316778ce0', array[
  array[$o$             else 'readmit' end$o$,
        $n$             when security.scholarship_readmit_blocker_v1(r.admitted_scholarship_id) is not null then 'readmit_' || security.scholarship_readmit_blocker_v1(r.admitted_scholarship_id)
             else 'readmit' end$n$]
], array[1]);

-- the restore: refuses with the same reason (defence in depth)
select pg_temp.edit_n('security.scholarship_readmit_v1(bigint,jsonb)', '2a50a647bf7c36ddfd2baee059f46dae', array[
  array[$o$  update scholarship.scholarships set lifecycle_status = 'active', updated_at = now() where id = s.id;$o$,
        $n$  if security.scholarship_readmit_blocker_v1(s.id) is not null then
    return jsonb_build_object('readmitted', false, 'reason', security.scholarship_readmit_blocker_v1(s.id));
  end if;
  update scholarship.scholarships set lifecycle_status = 'active', updated_at = now() where id = s.id;$n$]
], array[1]);

-- the gate is used, and the held read is evaluated again by the live rule at the next reader run
update pipeline.platform_toolset_settings set value = to_jsonb(1), updated_at = now(), updated_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b',
       reason = 'F-SCH 13 Nov 2026 (S2-Scholarship directive §3): the eight conditions checked; human-decision and closed-round guards added'
 where toolset_key = 'pipeline' and key = 'sch_elig.readmit_on' and value is distinct from to_jsonb(1);
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('scholarships', 'setting_changed', 'sch_elig.readmit_on 0 -> 1 (re-admission gate used after the eight-condition review)',
        jsonb_build_object('key', 'sch_elig.readmit_on', 'from', 0, 'to', 1, 'guards_added', jsonb_build_array('human_decision', 'round_closed'),
                           'positive_case_result', 'Sydney Bowel Cancer: readmit_round_closed (single 2019 round), not restored',
                           'negative_cases', jsonb_build_array('Charles Perkins: readmit_page_not_specific', 'UTS Gullotta: linked_page_not_scholarship'),
                           'directive', 'S2-Scholarship 13 Nov 2026 §3', 'migration', '20261113293700'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
update pipeline.scholarship_eligibility_reads set applied = null, updated_at = now() where applied->>'action' = 'readmit_held';

do $post$ begin
  if security.scholarship_readmit_blocker_v1('2c5beda6-4e59-5a9d-a0be-6d754f0bf9ed') is distinct from 'round_closed' then
    raise exception 'post-check: Sydney Bowel Cancer (one 2019 round) must be blocked as round_closed';
  end if;
end $post$;
