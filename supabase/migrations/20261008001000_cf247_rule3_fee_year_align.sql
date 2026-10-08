-- CF-247 Standing Review Rule 3, missing period (8 Oct 2026, Platform Admin): "Missing period : if the evidence is collected
-- in present day, fees get aligned to current year, no review needed."
-- A provider page annual international fee with no year, whose evidence was captured this calendar year, is given this
-- year. Its pending "No fee year on record" Layer 4 item is closed (superseded, reason recorded); no new item is raised.
-- Not aligned (left as they are, item stays pending): a course that already holds a different active fee for this year
-- (aligning would create two fees for one year), a fee entered or locked by hand, evidence captured in an earlier year.
-- Runs now and daily at 03:27 UTC (after Rule 1), so year-less fees read later are aligned too. Each run is logged in
-- pipeline.layer4_rule_runs. Nothing is removed.
create or replace function security.l4_rule_fee_year_align_v1()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_year int := extract(year from now())::int; v_fees int; v_items int; v_conf int; v_courses uuid[]; v_r jsonb;
begin
  create temporary table rule3_all on commit drop as
    select f.id, f.course_id, f.audience,
           exists (select 1 from catalogue.course_fees g where g.course_id = f.course_id and g.fee_type = 'provider_current_tuition' and g.audience = f.audience
                     and g.status = 'active' and g.fee_year = v_year and g.id <> f.id) conflict
      from catalogue.course_fees f join pipeline.evidence_artifacts ea on ea.id = f.evidence_id
     where f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.fee_year is null and f.amount > 0
       and extract(year from ea.captured_at)::int = v_year
       and not exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = f.course_id and m.field in ('tuition', 'fee', 'fees'));
  select count(*) filter (where conflict) into v_conf from rule3_all;
  create temporary table rule3_fees on commit drop as select id, course_id, audience from rule3_all where not conflict;

  update catalogue.course_fees f
     set fee_year = v_year, updated_at = now(),
         notes = concat_ws(' | ', nullif(f.notes, ''), 'Rule 3 (8 Oct 2026): no year on the page; evidence captured in ' || v_year || ', so aligned to ' || v_year || ' without review')
   where f.id in (select id from rule3_fees);
  get diagnostics v_fees = row_count;

  update pipeline.layer4_review_items i
     set status = 'superseded', decided_at = now(),
         escalation_reason = i.escalation_reason || ' Closed by Rule 3 (8 Oct 2026): evidence captured in ' || v_year || ', fee aligned to ' || v_year || '; no review needed.'
   where i.status = 'pending' and i.entity_type = 'course' and i.field_code = 'provider_current_tuition_validation'
     and i.escalation_reason like 'No fee year on record%'
     and i.entity_id in (select course_id from rule3_fees);
  get diagnostics v_items = row_count;

  select coalesce(array_agg(distinct course_id), '{}') into v_courses from rule3_fees;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;

  v_r := jsonb_build_object('year', v_year, 'fees_aligned', v_fees, 'items_closed', v_items, 'held_same_year_conflict', v_conf);
  insert into pipeline.layer4_rule_runs(rule, raised) values ('fee_year_align', v_r);
  return v_r;
end $f$;
revoke all on function security.l4_rule_fee_year_align_v1() from public, anon, authenticated;

select cron.schedule('l4-rule-fee-year-align', '27 3 * * *', 'select security.l4_rule_fee_year_align_v1()');
