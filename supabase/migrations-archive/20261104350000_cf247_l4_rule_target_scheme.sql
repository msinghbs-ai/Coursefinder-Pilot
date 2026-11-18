-- CF-247 IQ-00189 (Integration Controller 4 Nov 2026, rule runs 20-21): 11 Simon Fraser items of the rule sfu_no_term fail with "decision refused:
-- the link must be a full https:// web address" and stay waiting (safe).
-- Why: those items hold and propose http:// addresses (for example http://www.sfu.ca/students/calendar/2026/fall/programs/...); the rule uses
--   the proposed page, the executor approved the item's own proposed value, and the course-link apply (security.layer4_course_link_apply_impl,
--   not edited) accepts only a full https:// address. The validator did not look at the address the decision would write.
-- What:
--   1 The validator (md5-guarded edit) returns, for a rule that uses the proposed page, the address the decision writes: the proposed page as a
--     full https:// address (an http:// or scheme-less address is given https://; nothing else changes). An address that is still not a full web
--     address after that fails the item with a clear reason, before any decision.
--   2 The executor (md5-guarded edit) writes that address: when it differs from the item's proposed value, the item is decided through the same
--     decision path as an edited approval (edit_and_approve, the https:// address as the final value), so the item's history shows both. The
--     stored-copy, level, identity and every other check are unchanged and read the same addresses as before.
-- Replaces: nothing (the validator's target and the executor's decision call; same names, md5-guarded edits)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on. No spend. No rule is executed here. Consumer API untouched (G3).
-- md5 (pg_get_functiondef) before (live, read 4 Nov 2026 01:48 AEDT) -> after:
--   security.layer4_course_link_rule_validate_v1(text,uuid)            3a5d088e4aaf3ad1e1a5460524a2e70a -> 0cf77b67b8d90c98ef3b160306b67faa
--   security.layer4_course_link_rule_execute_v1(text,integer,boolean)  85c991e7b626e07f9777f7a65249fd81 -> cafae1b603ee3d42513ef87f34cb1639

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1 the validator returns the address the decision writes, and fails an item whose address cannot be written
select pg_temp.edit_once('security.layer4_course_link_rule_validate_v1(text,uuid)', '3a5d088e4aaf3ad1e1a5460524a2e70a', '0cf77b67b8d90c98ef3b160306b67faa',
  array[
    array[$e$ || ' days' end], null) reasons$e$,
          $e$ || ' days' end,
             -- fixed: the course-link apply's own address rule (security.layer4_course_link_apply_impl), checked before any decision
             case when lv.choice = 'use' and regexp_replace(coalesce(lv.target_url, ''), '^(https?://)?', 'https://', 'i') !~* '^https://[a-z0-9.-]+\.[a-z]{2,}(/[^\s]*)?$'
                  then 'the proposed page is not a full web address (' || coalesce(lv.target_url, 'none') || ')' end], null) reasons$e$],
    array[$e$v.held_url, v.prop_url, v.target_url, coalesce(cardinality(v.reasons), 0) = 0$e$,
          $e$v.held_url, v.prop_url, case when v.choice = 'use' then regexp_replace(v.target_url, '^(https?://)?', 'https://', 'i') else v.target_url end, coalesce(cardinality(v.reasons), 0) = 0$e$]
  ], array[1, 1]);

-- 2 the executor writes that address (an edited approval when it differs from the item's proposed value)
select pg_temp.edit_once('security.layer4_course_link_rule_execute_v1(text,integer,boolean)', '85c991e7b626e07f9777f7a65249fd81', 'cafae1b603ee3d42513ef87f34cb1639',
  array[
    array[$e$select x.item_id, x.pass, x.reasons, x.course_id, x.target_url into w$e$, $e$select x.item_id, x.pass, x.reasons, x.course_id, x.target_url, x.proposed_url into w$e$],
    array[$e$outcome, action) values (v_run, v.item_id, w.course_id, 'would_decide', case r.choice when 'keep' then 'reject' else 'approve' end);$e$,
          $e$outcome, action) values (v_run, v.item_id, w.course_id, 'would_decide',
               case when r.choice = 'keep' then 'reject' when w.target_url is distinct from w.proposed_url then 'edit_and_approve' else 'approve' end);$e$],
    array[$e$v_res := security.layer4_review_decide_impl(v.item_id, case r.choice when 'keep' then 'reject' else 'approve' end, v_reason, null);$e$,
          $e$-- the address the validator returned is the one written: an edited approval when it differs from the proposed value (http:// given https://)
        v_res := security.layer4_review_decide_impl(v.item_id,
                   case when r.choice = 'keep' then 'reject' when w.target_url is distinct from w.proposed_url then 'edit_and_approve' else 'approve' end, v_reason,
                   case when r.choice <> 'keep' and w.target_url is distinct from w.proposed_url then jsonb_build_object('course_url', w.target_url) end);$e$]
  ], array[1, 1, 1]);
