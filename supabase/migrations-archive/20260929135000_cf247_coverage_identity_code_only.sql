-- CF-247 coverage precision check (29 Sep 2026), official course page against pages already admitted:
--   identity by CRICOS course code on the page 13/13 correct; by exact course title only 3/8 (RMIT "inherent
--   requirements" pages carry the exact course title). So:
--  * a page counts as verified (coverage state 'candidate') only when it prints the course's CRICOS code; exact-title
--    pages stay unconfirmed ('page_found');
--  * binding ignores pages in non-course sections (requirements, fees, applying, scholarships, careers, pathways,
--    news, events ...); courses bound to such pages are released and re-bound. All checksum-guarded.
do $patch$
declare v_def text; v_old text;
begin
  if (select md5(prosrc) from pg_proc where oid='security.coverage_bind_v2(uuid)'::regprocedure)<>'54069038d8d48cc2dbfe6718c464b0a4' then
    raise exception 'coverage_bind_v2 changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('security.coverage_bind_v2(uuid)'::regprocedure);
  v_old:='      from pipeline.coverage_provider_urls where provider_id=p_provider_id;';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'bind anchor not found exactly once'; end if;
  v_def:=replace(v_def,v_old,'      from pipeline.coverage_provider_urls where provider_id=p_provider_id'
    ||E'\n       and url !~* ''/(inherent-requirements|entry-requirements|admission-requirements|english-requirements|fees?|tuition-fees?|scholarships?|apply|how-to-apply|applying|careers?|pathways?|credit|recognition-of-prior-learning|timetables?|news|events?|stories|blog|alumni|research|contact|faqs?)(/|$)'';');
  execute v_def;

  if (select md5(prosrc) from pg_proc where oid='security.course_coverage_build_v1()'::regprocedure)<>'4b04002f0265fe007c877b6eaa277984' then
    raise exception 'course_coverage_build_v1 changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('security.course_coverage_build_v1()'::regprocedure);
  v_old:='(read_status=''read'' and identity_basis is not null) verified';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'build anchor not found exactly once'; end if;
  execute replace(v_def,v_old,'(read_status=''read'' and identity_basis=''cricos_code'') verified');
end $patch$;

update pipeline.coverage_course_pages set status='ambiguous', leased_until=null
 where status='bound' and url ~* '/(inherent-requirements|entry-requirements|admission-requirements|english-requirements|fees?|tuition-fees?|scholarships?|apply|how-to-apply|applying|careers?|pathways?|credit|recognition-of-prior-learning|timetables?|news|events?|stories|blog|alumni|research|contact|faqs?)(/|$)';
update pipeline.coverage_provider_discovery set bound_at=null where mapped_at is not null;
select security.course_coverage_build_v1();
