-- CF-247 StudySearch usability remediation SS-016 (Platform Admin direction 1 Nov 2026 13:52, priority 1: "fee review cards show the exact
-- proposed fee, currency, year and basis"; admin record §37; batch L4B-20261101-1253 checkpoint 3).
-- Why: a Course link fee-check item (field provider_current_tuition_validation) showed no fee, and its choices were the link choices.
--   "Enter another address" sends a web address, which security.layer4_tuition_apply_impl takes as a plain Approve: the item's own proposed
--   fee was admitted. 46 decisions on 30 Oct (L4B-20261030-0816, audit #25776-25821) meant "read the page again" and admitted a flagged fee
--   each; the 24 Oct guard (hotfix D1) covers only provider_current_tuition. The outcome of an admitted fee was reported against the course
--   link, so it read "saved, but the destination does not show it yet".
-- What:
--   * public.admin_layer4_inbox decide (md5-guarded): an address on a fee-check item is refused with a plain message; nothing is saved.
--   * security.layer4_decision_outcome_v1 (md5-guarded): a fee-check decision is read back from catalogue.course_fees (the row written for
--     that review item): admitted with the amount, currency, year and basis, or pending_check.
--   * The card (src/Layer4Inbox.jsx) shows the proposed fee and labels the choices Admit this fee / Do not admit this fee.
-- The 46 fees admitted on 30 Oct are not changed here: they go to the Platform Admin in the decision pack (refs, evidence, rollback).
-- After: admin_layer4_inbox 417f181d, layer4_decision_outcome_v1 c40ee758.
-- Rollback: re-apply admin_layer4_inbox c6b83e21 and layer4_decision_outcome_v1 eae00e61 (the definitions before this change).
-- Replaces: public.admin_layer4_inbox, security.layer4_decision_outcome_v1 (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API untouched (G3). No setting: the refusal is a rule, not a value (G2).

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

-- 1. an address on a fee-check item is refused
select pg_temp.edit_once('public.admin_layer4_inbox(text,jsonb)', 'c6b83e211ba5172d16a5b3b7e7399ef5', '417f181d12155f79f68c1e70c27a1892', array[
 array[$o$  -- 24 Oct 2026 (hotfix D1): a course-link row that holds a fee$o$,
       $n$  -- SS-016 fee check (1 Nov 2026): an address on a fee-check item was taken as a plain Approve and admitted the proposed fee (46 decisions
  -- on 30 Oct). A fee check is admitted or not; a different course page is set on the course record.
  if v_kind = 'course_link' and v_det->>'field_code' = 'provider_current_tuition_validation' and v_choice = 'enter' then
    raise exception 'this is a fee check: admit the proposed fee or do not admit it. A different course page is set on the course record';
  end if;

  -- 24 Oct 2026 (hotfix D1): a course-link row that holds a fee$n$]],
 array[1]);

-- 2. a fee-check decision is read back from the course's fees
select pg_temp.edit_once('security.layer4_decision_outcome_v1(text,text,jsonb)', 'eae00e61a7785c46f1f570991577ede0', 'c40ee758b2d5888deeb5a101fd036cb6', array[
 array[$o$    elsif p_kind = 'course_link' then
      v_url :=$o$,
       $n$    elsif p_kind = 'course_link' and exists (select 1 from pipeline.layer4_review_items r where r.id = (p_result->>'review_item_id')::uuid
                                                and r.field_code = 'provider_current_tuition_validation') then
      -- SS-016 fee check (1 Nov 2026): the fee written for this review item by security.layer4_tuition_apply_impl
      select jsonb_build_object('amount', f.amount, 'currency', f.currency_code, 'fee_year', f.fee_year, 'basis', f.basis, 'course_fee_id', f.id)
        into v_rows from catalogue.course_fees f
       where f.notes like 'CF-247 Layer 4 human decision; review item ' || (p_result->>'review_item_id') || ';%' and f.status = 'active'
       order by f.updated_at desc limit 1;
      return jsonb_build_object('class', case when v_rows is not null then 'admitted' else 'pending_check' end, 'verified', v_rows is not null,
                                'status', v_status, 'decision_id', p_result->>'decision_id', 'fee', v_rows, 'destination', 'course_fees');
    elsif p_kind = 'course_link' then
      v_url :=$n$]],
 array[1]);
