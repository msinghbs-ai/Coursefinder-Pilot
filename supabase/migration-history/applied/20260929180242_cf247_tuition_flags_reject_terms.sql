-- CF-247 flagged tuition: apply the tuition reject terms (loan caps, student contribution, Commonwealth supported,
-- deposits, application fees) before the per-year rule. The first run admitted three "VET Student Loan cap" amounts as
-- tuition; they are reverted (fee inactive, flag removed, Layer 4 item reopened).
do $patch$
declare v text; a text:=$o$       and coalesce((i.validator_result->>'candidate_bound')::boolean,false)$o$;
begin
  v:=pg_get_functiondef('security.layer3_tuition_admit_assumed_annual_v1(int)'::regprocedure);
  if (length(v)-length(replace(v,a,'')))/length(a)<>1 then raise exception 'anchor not found exactly once'; end if;
  execute replace(v,a,a||$n$
       and coalesce(i.evidence_quotes::text,'') !~* '(loan|\mcap\M|student contribution|commonwealth supported|\mcsp\M|deposit|application fee|enrolment fee|amenities)'$n$);
end $patch$;
with bad as (
  select f.id fid, f.record_id, f.detail->>'interpretation_id' iid from pipeline.data_flags f
   where f.status='open' and coalesce(f.detail->>'quotes','') ~* '(loan|\mcap\M|student contribution|commonwealth supported|\mcsp\M|deposit|application fee|enrolment fee|amenities)'),
fees as (update catalogue.course_fees fe set status='inactive', updated_at=now(), notes=coalesce(notes,'')||' | reverted: the amount is a loan cap or other charge, not tuition' from bad where fe.id=bad.record_id returning fe.id),
flags as (update pipeline.data_flags f set status='removed', resolved_at=now(), resolution=jsonb_build_object('action','auto_revert','reason','loan cap or other charge, not tuition') from bad where f.id=bad.fid returning f.id),
l4 as (update pipeline.layer4_review_items l set status='pending', decided_at=null,
         escalation_reason='The amount on the page is a loan cap or another charge, not the tuition fee. Please find the annual tuition fee or mark it as not available.'
         from bad where l.layer3_interpretation_id::text=bad.iid and l.field_code='provider_current_tuition_validation' and l.status='superseded' returning l.id)
update pipeline.layer3_work_items w set status='layer4_required', updated_at=now(), last_error='held: loan cap or other charge, not tuition'
  from bad where w.interpretation_id::text=bad.iid and w.status='admitted';
select search.refresh_course_enrichment_scoped_v1(array(select distinct entity_id from pipeline.data_flags where resolution->>'reason'='loan cap or other charge, not tuition'),true);
