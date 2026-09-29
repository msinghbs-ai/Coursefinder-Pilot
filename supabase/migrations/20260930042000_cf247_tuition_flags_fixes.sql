-- CF-247 flagged tuition, fixes from the live check:
--  * skip a course that already has a current provider tuition fee (the one-current-fee trigger kept the existing one
--    and superseded ours, leaving a flag on an inactive fee); close such flags as removed with the reason;
--  * the operators' list shows the course title (catalogue.courses.display_title / canonical_title).
do $patch$
declare v text; a text:=$o$       and coalesce((i.validator_result->>'candidate_bound')::boolean,false)$o$;
begin
  v:=pg_get_functiondef('security.layer3_tuition_admit_assumed_annual_v1(int)'::regprocedure);
  if (length(v)-length(replace(v,a,'')))/length(a)<>1 then raise exception 'admit anchor not found exactly once'; end if;
  execute replace(v,a,a||$n$
       and not exists (select 1 from catalogue.course_fees x where x.course_id=w.entity_id and x.fee_type='provider_current_tuition' and x.status='active' and x.audience='international')$n$);
  v:=pg_get_functiondef('security.admin_data_flags_read_v1(jsonb)'::regprocedure);
  a:=$o$coalesce(to_jsonb(c)->>'title',to_jsonb(c)->>'name',to_jsonb(c)->>'course_name')$o$;
  if (length(v)-length(replace(v,a,'')))/length(a)<>1 then raise exception 'read anchor not found exactly once'; end if;
  execute replace(v,a,$n$coalesce(c.display_title,c.canonical_title)$n$);
end $patch$;
update pipeline.data_flags f set status='removed', resolved_at=now(),
       resolution=jsonb_build_object('action','auto_close','reason','the course already had a current tuition fee, which was kept')
  from catalogue.course_fees fe where fe.id=f.record_id and f.status='open' and fe.status<>'active';
