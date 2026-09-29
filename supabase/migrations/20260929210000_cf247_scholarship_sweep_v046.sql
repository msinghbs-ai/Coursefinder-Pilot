-- CF-247 scholarship discovery, step-2 value hand-check (14 admitted pages against the live pages, 29 Sep 2026): all 14
-- are single, named, international scholarship pages; values wrong on 3 - Curtin English Scholarship ("up to A$7,496")
-- and Macquarie Vice-Chancellor's International Scholarship - ANZBAI ("up to AUD$20,000") taken as fixed amounts, and
-- Swinburne IAWA Scholarship ("$5,000 USD") taken as AUD; levels missed on pages whose "eligible countries" list was read
-- as the eligibility section (Bond, UQ, UniSQ, La Trobe). Extractor scholarship-sweep-v0.4.6 fixes these classes; values
-- and course links the sweep applied to discovered and admitted pages read by earlier v0.4 extractors are reverted
-- (logged) and those pages are read again.
do $rv$
declare v_ids uuid[]; v_courses uuid[];
begin
  select coalesce(array_agg(sp.scholarship_id),'{}') into v_ids from pipeline.scholarship_pages sp
   where sp.url_source in ('discovered','admitted') and sp.read_status='read'
     and coalesce(sp.facts->>'extractor','') in ('scholarship-sweep-v0.4.0','scholarship-sweep-v0.4.1','scholarship-sweep-v0.4.2','scholarship-sweep-v0.4.3','scholarship-sweep-v0.4.4','scholarship-sweep-v0.4.5');
  with ch as (select distinct on (scholarship_id) scholarship_id, before_value from pipeline.scholarship_sweep_changes
               where field='award_value' and scholarship_id=any(v_ids) and before_value is not null order by scholarship_id, id)
  update scholarship.scholarships s set award_value_type=coalesce(ch.before_value->>'type','text_only'), award_percentage=null, award_amount=null,
         award_currency_code=null, award_applies_to_fee_type=null, award_value_text=ch.before_value->>'text', updated_at=now()
    from ch where s.id=ch.scholarship_id
     and exists (select 1 from pipeline.scholarship_sweep_changes x where x.scholarship_id=s.id and x.field='award_value'
                  and x.id > coalesce((select max(r.id) from pipeline.scholarship_sweep_changes r where r.scholarship_id=s.id and r.field='revert'),0));
  insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
  select distinct scholarship_id,'revert','{"reason":"step-2 hand-check; re-read with scholarship-sweep-v0.4.6"}'::jsonb,null::jsonb
    from pipeline.scholarship_sweep_changes where scholarship_id=any(v_ids) and field in ('award_value','course_links');
  select coalesce(array_agg(distinct course_id),'{}') into v_courses from scholarship.course_mappings where scholarship_id=any(v_ids) and mapping_basis='sweep_level_field_scope';
  delete from scholarship.course_mappings where scholarship_id=any(v_ids) and mapping_basis='sweep_level_field_scope';
  delete from scholarship.scopes sc using pipeline.sources src where sc.source_id=src.id and src.source_type='provider_course_page_sweep' and sc.scope_type='study_level' and sc.scholarship_id=any(v_ids);
  if cardinality(v_courses)>0 then perform search.refresh_course_enrichment_scoped_v1(v_courses,true); end if;
  update pipeline.scholarship_pages set next_read_at=now(), applied_at=null, apply_result=null, attempts=0, leased_until=null where scholarship_id=any(v_ids);
end $rv$;
