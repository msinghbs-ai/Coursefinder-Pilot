-- CF-247 scholarship discovery, step-1 hand-check (14 matched pages against the live pages, 29 Sep 2026): names all
-- right; values wrong on 4 - Macquarie "ASEAN $10,000 Early Acceptance" and "Nigeria $5,000 Regional" given 100% (from
-- "must not hold a scholarship that covers full tuition fees"), Geelong Grammar "Sport Scholarship" given 100% ("up to
-- 100%"), UNSW "Scientia Scholarship" given $5,000 (a co-op bonus; the stated value is $10,000); and one matched page
-- was a UWA research-project page, not a scholarship page. Extractor scholarship-sweep-v0.4.3 fixes these classes; values
-- and course links the sweep applied to discovered and admitted pages read by v0.4.0-v0.4.2 are reverted (logged) and
-- those pages are read again.
do $rv$
declare v_ids uuid[]; v_courses uuid[];
begin
  select coalesce(array_agg(sp.scholarship_id),'{}') into v_ids from pipeline.scholarship_pages sp
   where sp.url_source in ('discovered','admitted') and sp.read_status='read'
     and coalesce(sp.facts->>'extractor','') in ('scholarship-sweep-v0.4.0','scholarship-sweep-v0.4.1','scholarship-sweep-v0.4.2');
  with ch as (select distinct on (scholarship_id) scholarship_id, before_value from pipeline.scholarship_sweep_changes
               where field='award_value' and scholarship_id=any(v_ids) and before_value is not null order by scholarship_id, id)
  update scholarship.scholarships s set award_value_type=coalesce(ch.before_value->>'type','text_only'), award_percentage=null, award_amount=null,
         award_currency_code=null, award_applies_to_fee_type=null, award_value_text=ch.before_value->>'text', updated_at=now()
    from ch where s.id=ch.scholarship_id
     and exists (select 1 from pipeline.scholarship_sweep_changes x where x.scholarship_id=s.id and x.field='award_value'
                  and x.id > coalesce((select max(r.id) from pipeline.scholarship_sweep_changes r where r.scholarship_id=s.id and r.field='revert'),0));
  insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
  select distinct scholarship_id,'revert','{"reason":"step-1 hand-check; re-read with scholarship-sweep-v0.4.3"}'::jsonb,null::jsonb
    from pipeline.scholarship_sweep_changes where scholarship_id=any(v_ids) and field in ('award_value','course_links');
  select coalesce(array_agg(distinct course_id),'{}') into v_courses from scholarship.course_mappings where scholarship_id=any(v_ids) and mapping_basis='sweep_level_field_scope';
  delete from scholarship.course_mappings where scholarship_id=any(v_ids) and mapping_basis='sweep_level_field_scope';
  delete from scholarship.scopes sc using pipeline.sources src where sc.source_id=src.id and src.source_type='provider_course_page_sweep' and sc.scope_type='study_level' and sc.scholarship_id=any(v_ids);
  if cardinality(v_courses)>0 then perform search.refresh_course_enrichment_scoped_v1(v_courses,true); end if;
  update pipeline.scholarship_pages set next_read_at=now(), applied_at=null, apply_result=null, attempts=0, leased_until=null where scholarship_id=any(v_ids);
end $rv$;
