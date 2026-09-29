-- CF-247 tuition period rule, tightened after the first sample check: the rule applies only when the page states NO
-- period. A quote that says "total", "whole/entire/full course", or per semester/trimester/term/unit/subject/credit
-- states a different period, so it stays in Layer 4 (first run admitted such fees, e.g. "The total indicative fee for
-- 2026 commencement is AU$25,250"; those are reverted: fee inactive, flag closed as removed, Layer 4 item reopened).
do $patch$
declare v text; a text:=$o$       and coalesce((i.validator_result->>'candidate_bound')::boolean,false)$o$;
begin
  if (select md5(prosrc) from pg_proc where oid='security.layer3_tuition_admit_assumed_annual_v1(int)'::regprocedure) is null then raise exception 'function missing'; end if;
  v:=pg_get_functiondef('security.layer3_tuition_admit_assumed_annual_v1(int)'::regprocedure);
  if (length(v)-length(replace(v,a,'')))/length(a)<>1 then raise exception 'anchor not found exactly once'; end if;
  execute replace(v,a,a||$n$
       and coalesce(i.evidence_quotes::text,'') !~* '(\mtotal\M|\m(whole|entire|full)\s+(course|program|programme|degree)\M|\mper\s+(semester|trimester|term|unit|subject|credit|study\s+period|session|course)\M|\mcourse\s+fee\M)'$n$);
end $patch$;

with bad as (
  select f.id fid, f.record_id, f.detail->>'interpretation_id' iid
    from pipeline.data_flags f
   where f.flag_code='tuition_period_assumed_annual' and f.status='open'
     and coalesce(f.detail->>'quotes','') ~* '(\mtotal\M|\m(whole|entire|full)\s+(course|program|programme|degree)\M|\mper\s+(semester|trimester|term|unit|subject|credit|study\s+period|session|course)\M|\mcourse\s+fee\M)'),
fees as (update catalogue.course_fees fe set status='inactive', updated_at=now(), notes=coalesce(notes,'')||' | reverted: the page states a different period (e.g. total), not per year' from bad where fe.id=bad.record_id returning fe.course_id),
flags as (update pipeline.data_flags f set status='removed', resolved_at=now(), resolution=jsonb_build_object('action','auto_revert','reason','the page states a different period (e.g. total)') from bad where f.id=bad.fid returning f.id),
l4 as (update pipeline.layer4_review_items l set status='pending', decided_at=null,
         escalation_reason='The page gives this fee for a different period (for example the total for the whole course), not per year. Please confirm the annual fee.'
         from bad where l.layer3_interpretation_id::text=bad.iid and l.field_code='provider_current_tuition_validation' and l.status='superseded' returning l.id)
update pipeline.layer3_work_items w set status='layer4_required', updated_at=now(), last_error='held: the page states a different period (e.g. total)'
  from bad where w.interpretation_id::text=bad.iid and w.status='admitted';
select search.refresh_course_enrichment_scoped_v1(array(select distinct entity_id from pipeline.data_flags where resolution->>'action'='auto_revert'),true);
