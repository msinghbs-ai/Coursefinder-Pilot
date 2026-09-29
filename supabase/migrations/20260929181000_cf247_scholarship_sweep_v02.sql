-- CF-247 scholarship sweep v0.2.0 after the first-batch hand-check (29 Sep 2026): 8 of 10 correct; the ANU
-- International Achievement Award has regional tiers (20/25/50%) but was given 50%, and the Nicholas Auden scholarship
-- is Faculty of Law only but was linked to all Monash undergraduate and postgraduate courses.
--  * extractor: any other percentage in the text makes a single value unsafe (tiered); a faculty/school named in the
--    text restricts the field; an unmatched faculty stops course linking (field_unmapped);
--  * apply: no course links when field_unmapped; earlier sweep links not in the new set are removed as well;
--  * the first batch's value and course-link changes are reverted (logged) and the pages re-read with v0.2.0.
do $patch$
declare v text;
begin
  v:=pg_get_functiondef('security.scholarship_sweep_apply_v1(uuid)'::regprocedure);
  if position($o$  if cardinality(v_codes)>0 or cardinality(v_fields)>0 then$o$ in v)=0
     or position($o$mapping_basis='explicit_provider_scope' and not (course_id=any(v_new));$o$ in v)=0 then raise exception 'apply anchors not found'; end if;
  v:=replace(v,$o$  if cardinality(v_codes)>0 or cardinality(v_fields)>0 then$o$,
               $n$  if coalesce((f->>'field_unmapped')::boolean,false) and cardinality(v_fields)=0 then
    v_changes:=v_changes||'course_links_need_review'::text;
  elsif cardinality(v_codes)>0 or cardinality(v_fields)>0 then$n$);
  v:=replace(v,$o$mapping_basis='explicit_provider_scope' and not (course_id=any(v_new));$o$,
               $n$mapping_basis in ('explicit_provider_scope','sweep_level_field_scope') and not (course_id=any(v_new));$n$);
  execute v;
end $patch$;

-- revert the first batch (values and links), keeping the log
with ch as (select distinct on (scholarship_id) scholarship_id, before_value from pipeline.scholarship_sweep_changes where field='award_value' order by scholarship_id, id)
update scholarship.scholarships s set award_value_type=ch.before_value->>'type', award_percentage=null, award_amount=null,
       award_currency_code=null, award_value_text=ch.before_value->>'text', updated_at=now()
  from ch where s.id=ch.scholarship_id;
insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
select distinct scholarship_id,'revert','{"reason":"first-batch hand-check; re-read with scholarship-sweep-v0.2.0"}'::jsonb,null::jsonb from pipeline.scholarship_sweep_changes where field in ('award_value','course_links');
do $rv$
declare v_courses uuid[];
begin
  select coalesce(array_agg(distinct course_id),'{}') into v_courses from scholarship.course_mappings where mapping_basis='sweep_level_field_scope';
  delete from scholarship.course_mappings where mapping_basis='sweep_level_field_scope';
  delete from scholarship.scopes sc using pipeline.sources s where sc.source_id=s.id and s.source_type='provider_course_page_sweep' and sc.scope_type='study_level';
  if cardinality(v_courses)>0 then perform search.refresh_course_enrichment_scoped_v1(v_courses,true); end if;
end $rv$;
update pipeline.scholarship_pages set next_read_at=now(), applied_at=null, apply_result=null where read_at is not null;
select security.scholarship_publication_review_v1();
