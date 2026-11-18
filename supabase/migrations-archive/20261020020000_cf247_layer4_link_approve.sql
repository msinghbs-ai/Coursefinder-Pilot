-- CF-247 (20 Oct 2026). Platform Admin 07:02 (capture of Layer 4 › Review queue): "there is no Approve button".
-- Found: the review desk offered Approve for an official course link only when the proposed page was stored as url; all 24 waiting
-- items store it as course_url (security.l4_rule_unofficial_source_v1, coverage_admission_apply_v1), so Approve was hidden on every one.
-- Applying the decision already reads either name (security.layer4_course_link_apply_impl, 17 Oct 2026).
-- Replaces: security.layer4_review_desk_v1_impl(text,integer) (one line, md5-guarded)
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

select pg_temp.edit_once('security.layer4_review_desk_v1_impl(text,integer)', 'f9e79a59a14b94155a66c0adc463824c', array[
  array['(jsonb_typeof(b.proposed_value)=''object'' and b.proposed_value ? ''url'')',
        '(jsonb_typeof(b.proposed_value)=''object'' and (b.proposed_value ? ''url'' or b.proposed_value ? ''course_url''))']
]);
