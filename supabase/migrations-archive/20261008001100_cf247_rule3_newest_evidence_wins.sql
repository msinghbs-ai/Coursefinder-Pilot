-- CF-247 Rule 3, same-year conflicts (8 Oct 2026, Platform Admin, multiple choice "Newest evidence wins").
-- When a year-less page fee captured this year meets a different active page fee already filed for this year on the same
-- course, the fee whose evidence was captured last becomes this year's fee and the other is marked superseded (kept, not
-- removed). The pending "No fee year on record" item is closed with the outcome. Hand-locked courses are still skipped.
-- Replaces security.l4_rule_fee_year_align_v1 (migration 1000) behind an md5 guard; the daily schedule is unchanged.
do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'security.l4_rule_fee_year_align_v1()'::regprocedure) is distinct from '5809297309d14a1a7ce609b6a9d55138' then
    raise exception 'l4_rule_fee_year_align_v1 is not the migration 1000 definition; refusing to replace it';
  end if;
end $g$;
create or replace function security.l4_rule_fee_year_align_v1()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_year int := extract(year from now())::int; v_fees int; v_items int; v_conf int; v_new int; v_old int; v_courses uuid[]; v_r jsonb;
begin
  create temporary table rule3_all on commit drop as
    select f.id, f.course_id, f.audience, ea.captured_at,
           (select g.id from catalogue.course_fees g where g.course_id = f.course_id and g.fee_type = 'provider_current_tuition' and g.audience = f.audience
               and g.status = 'active' and g.fee_year = v_year and g.id <> f.id
             order by g.updated_at desc nulls last limit 1) other_id
      from catalogue.course_fees f join pipeline.evidence_artifacts ea on ea.id = f.evidence_id
     where f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.fee_year is null and f.amount > 0
       and extract(year from ea.captured_at)::int = v_year
       and not exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = f.course_id and m.field in ('tuition', 'fee', 'fees'));
  select count(*) filter (where other_id is not null) into v_conf from rule3_all;

  -- same-year conflicts: newest evidence wins (a this-year fee with no evidence counts as older)
  create temporary table rule3_conf on commit drop as
    select a.id, a.course_id, a.other_id,
           (a.captured_at > coalesce((select eg.captured_at from catalogue.course_fees g join pipeline.evidence_artifacts eg on eg.id = g.evidence_id where g.id = a.other_id), '-infinity'::timestamptz)) yearless_newer
      from rule3_all a where a.other_id is not null;
  update catalogue.course_fees g
     set status = 'superseded', updated_at = now(),
         notes = concat_ws(' | ', nullif(g.notes, ''), 'Rule 3 (8 Oct 2026): superseded by a newer course page reading for ' || v_year || ' (newest evidence wins)')
   where g.id in (select other_id from rule3_conf where yearless_newer);
  get diagnostics v_new = row_count;
  update catalogue.course_fees f
     set status = 'superseded', updated_at = now(),
         notes = concat_ws(' | ', nullif(f.notes, ''), 'Rule 3 (8 Oct 2026): no year on the page; the ' || v_year || ' fee on record has newer evidence, so it stays (newest evidence wins)')
   where f.id in (select id from rule3_conf where not yearless_newer);
  get diagnostics v_old = row_count;

  create temporary table rule3_fees on commit drop as
    select id, course_id, audience from rule3_all where other_id is null
    union all select c.id, c.course_id, null from rule3_conf c where c.yearless_newer;
  create temporary table rule3_closed on commit drop as
    select course_id from rule3_all;

  update catalogue.course_fees f
     set fee_year = v_year, updated_at = now(),
         notes = concat_ws(' | ', nullif(f.notes, ''), 'Rule 3 (8 Oct 2026): no year on the page; evidence captured in ' || v_year || ', so aligned to ' || v_year || ' without review')
   where f.id in (select id from rule3_fees);
  get diagnostics v_fees = row_count;

  update pipeline.layer4_review_items i
     set status = 'superseded', decided_at = now(),
         escalation_reason = i.escalation_reason || ' Closed by Rule 3 (8 Oct 2026): evidence captured in ' || v_year || ', fee aligned to ' || v_year || ' (where another ' || v_year || ' fee was on record, the newest evidence wins); no review needed.'
   where i.status = 'pending' and i.entity_type = 'course' and i.field_code = 'provider_current_tuition_validation'
     and i.escalation_reason like 'No fee year on record%'
     and i.entity_id in (select course_id from rule3_closed);
  get diagnostics v_items = row_count;

  select coalesce(array_agg(distinct course_id), '{}') into v_courses from rule3_closed;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;

  v_r := jsonb_build_object('year', v_year, 'fees_aligned', v_fees, 'items_closed', v_items, 'same_year_conflicts', v_conf, 'conflict_yearless_newer_won', v_new, 'conflict_dated_fee_kept', v_old);
  insert into pipeline.layer4_rule_runs(rule, raised) values ('fee_year_align', v_r);
  return v_r;
end $f$;
revoke all on function security.l4_rule_fee_year_align_v1() from public, anon, authenticated;
