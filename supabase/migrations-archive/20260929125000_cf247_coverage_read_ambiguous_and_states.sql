-- CF-247 coverage sweep v0.3.0 (pilot 29 Sep 2026):
--  * ambiguous course pages are read too (best candidate only) and accepted only with the CRICOS course code on the
--    page; an accepted page becomes 'bound' (basis cricos_code_on_page); up to 8 pages per provider per call;
--  * coverage states read the sweep: 'candidate' = value found on an identity-verified page, awaiting the admission
--    rule; 'not_on_page' = verified page read, value not published there; 'blocked' = site refused or robots.txt
--    disallows; 'page_found' = page bound, not read yet. All checksum-guarded.
do $patch$
declare v_def text;
begin
  if (select md5(prosrc) from pg_proc where oid='public.svc_coverage_read_next(int)'::regprocedure)<>'a215a236bb22de7b60e810b3d2e3dd09' then
    raise exception 'svc_coverage_read_next changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('public.svc_coverage_read_next(int)'::regprocedure);
  if position($o$where p.status='bound' and$o$ in v_def)=0 or position($o$where rk<=3 order by$o$ in v_def)=0 or position($o$'code',c.course_code)$o$ in v_def)=0 or position($o$returning p.course_id, p.provider_id, p.url)$o$ in v_def)=0 then
    raise exception 'read_next anchors not found'; end if;
  v_def:=replace(v_def,$o$where p.status='bound' and$o$,$n$where p.status in ('bound','ambiguous') and$n$);
  v_def:=replace(v_def,$o$where rk<=3 order by$o$,$n$where rk<=8 order by$n$);
  v_def:=replace(v_def,$o$returning p.course_id, p.provider_id, p.url)$o$,$n$returning p.course_id, p.provider_id, p.url, p.status)$n$);
  v_def:=replace(v_def,$o$'code',c.course_code)$o$,$n$'code',c.course_code,'status',u.status)$n$);
  execute v_def;

  if (select md5(prosrc) from pg_proc where oid='public.svc_coverage_read_record(uuid,text,int,text,text,text,text,jsonb)'::regprocedure)<>'4bc58e8277f68184caa71476389c305d' then
    raise exception 'svc_coverage_read_record changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('public.svc_coverage_read_record(uuid,text,int,text,text,text,text,jsonb)'::regprocedure);
  if position($o$status=case when p_read_status='identity_mismatch' then 'mismatch' else status end$o$ in v_def)=0 then raise exception 'read_record anchor not found'; end if;
  v_def:=replace(v_def,$o$status=case when p_read_status='identity_mismatch' then 'mismatch' else status end$o$,
    $n$status=case when p_read_status='identity_mismatch' then 'mismatch' when status='ambiguous' and p_identity_basis='cricos_code' then 'bound' else status end,
         basis=case when status='ambiguous' and p_identity_basis='cricos_code' then 'cricos_code_on_page' else basis end$n$);
  execute v_def;

  if (select md5(prosrc) from pg_proc where oid='security.course_coverage_build_v1()'::regprocedure)<>'ec08905df31d60ab505b1ead43bd85de' then
    raise exception 'course_coverage_build_v1 changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('security.course_coverage_build_v1()'::regprocedure);
  if position($o$  create temp table _val on commit drop as$o$ in v_def)=0 or position($o$      when r.read_ok then 'not_on_page'
      when r.blocked then 'blocked'
      when f.course_id is not null or v.url then 'page_found'$o$ in v_def)=0 then raise exception 'build anchors not found'; end if;
  v_def:=replace(v_def,$o$  create temp table _val on commit drop as$o$,$n$  create temp table _sw on commit drop as
    select course_id, status, read_status, identity_basis,
           (read_status='read' and identity_basis is not null) verified,
           coalesce((candidates->'fee'->>'value') is not null,false) c_tuition,
           coalesce(candidates->'english' ? 'ielts_overall' or candidates->'english' ? 'pte_overall' or candidates->'english' ? 'toefl_overall',false) c_english,
           coalesce(jsonb_array_length(candidates->'intakes')>0,false) c_intakes
      from pipeline.coverage_course_pages;
  create temp table _val on commit drop as$n$);
  v_def:=replace(v_def,$o$      when r.read_ok then 'not_on_page'
      when r.blocked then 'blocked'
      when f.course_id is not null or v.url then 'page_found'$o$,$n$      when sw.verified and (a.attribute='official_url' or (a.attribute='provider_tuition' and sw.c_tuition) or (a.attribute='english' and sw.c_english) or (a.attribute='intakes' and sw.c_intakes)) then 'candidate'
      when r.read_ok or sw.verified then 'not_on_page'
      when r.blocked or sw.read_status in ('blocked','robots_disallowed') then 'blocked'
      when f.course_id is not null or v.url or sw.status='bound' then 'page_found'$n$);
  v_def:=replace(v_def,$o$left join _read r using (course_id) left join _found f using (course_id)$o$,$n$left join _read r using (course_id) left join _found f using (course_id) left join _sw sw using (course_id)$n$);
  execute v_def;
end $patch$;
select security.course_coverage_build_v1();
