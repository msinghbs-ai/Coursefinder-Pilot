-- CF-247 scholarship sweep v0.3.0 after the second hand-check (6 of 8 right): levels are read from the eligibility
-- section when the page has one (the Indonesian Women Impact Scholarship is research-only; the Faculty of IT merit
-- scholarship is undergraduate-only). When a re-read states no level or field, earlier sweep links are removed rather
-- than kept. All pages are re-read with v0.3.0 before the first sweep publication batch.
do $patch$
declare v text;
begin
  v:=pg_get_functiondef('security.scholarship_sweep_apply_v1(uuid)'::regprocedure);
  if position($o$  update pipeline.scholarship_pages set applied_at=now()$o$ in v)=0 then raise exception 'apply anchor not found'; end if;
  v:=replace(v,$o$  update pipeline.scholarship_pages set applied_at=now()$o$,
               $n$  -- no level or field stated on this read: earlier sweep links cannot be justified any more
  if cardinality(v_codes)=0 and cardinality(v_fields)=0 and exists (select 1 from scholarship.course_mappings m where m.scholarship_id=s.id and m.mapping_basis='sweep_level_field_scope') then
    select coalesce(array_agg(course_id),'{}') into v_old from scholarship.course_mappings where scholarship_id=s.id and mapping_basis='sweep_level_field_scope';
    delete from scholarship.course_mappings where scholarship_id=s.id and mapping_basis='sweep_level_field_scope';
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (s.id,'course_links_removed',jsonb_build_object('courses',cardinality(v_old)),null,pg.evidence_id);
    v_changes:=v_changes||'course_links_removed'::text;
    perform search.refresh_course_enrichment_scoped_v1(v_old,true);
  end if;
  update pipeline.scholarship_pages set applied_at=now()$n$);
  execute v;
end $patch$;
update pipeline.scholarship_pages set next_read_at=now() where read_status='read';
