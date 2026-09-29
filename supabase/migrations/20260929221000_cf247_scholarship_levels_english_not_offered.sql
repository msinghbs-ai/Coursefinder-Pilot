-- CF-247 scholarship sweep v0.5.0 (lead follow-up on the 40 publication holds, 29 Sep 2026).
--  1. Levels: "research and undergraduate" came from site menus and enquiry forms (RMIT "Undergraduate courses ...
--     Research degrees", Avondale/CQU "Postgraduate Courses Higher Degrees by Research", Avondale "I am interested in:
--     ... Research Degrees"), read when a page had no eligibility section. The worker now reads levels from the page
--     content only (from the page's own <h1>, menus, forms and link-only lists removed).
--  2. English language course scholarships (General English, IELTS preparation, ELICOS, EAP, Academic English, English
--     programs): the sweep links them only to the provider's own English language courses (non-AQF award courses whose
--     title names that kind of course), and removes (logged) any other link; with no such course, nothing is linked.
--     Publishability also reports an English course scholarship linked to anything else.
--  3. Not currently offered ("held in tenure until", "not currently offered", "no longer offered/available", "closed
--     permanently", "discontinued"): reported by publishability ('not currently offered (provider page)') rather than
--     withdrawing the record - it is reversible when the page changes (a tenure ends, a scholarship is reoffered), it
--     covers every record with a read provider page (not only admitted ones), and the batch and the nightly review
--     already act on publishability. An annual round that has closed for this year is not affected.
--  4. Every unpublished active record with a read provider page is read again with v0.5.0 (sweep study-level scopes
--     removed first, logged; course links are recomputed by the sweep apply). Published records are not re-read here.
do $patch$
declare v text; o text; n text;
begin
  -- 2. apply: English language course scholarships
  if (select md5(prosrc) from pg_proc where oid='security.scholarship_sweep_apply_v1(uuid)'::regprocedure)<>'f4d05c4d2d45622ade7f7de72a51e13d' then
    raise exception 'scholarship_sweep_apply_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('security.scholarship_sweep_apply_v1(uuid)'::regprocedure);
  o:=$o$  v_codes:=security.scholarship_level_codes(f->'levels');$o$;
  n:=$n$  -- v0.5.0: an English language course scholarship links only to the provider's English language courses
  if f ? 'english_course' then
    select coalesce(array_agg(c.id),'{}') into v_new
      from catalogue.courses c join ref.study_levels sl on sl.id=c.study_level_id
     where c.provider_id=s.provider_id and c.lifecycle_status='active' and sl.code='non_aqf_award' and coalesce(c.course_code,'')<>''
       and c.canonical_title ~* case f->'english_course'->>'course'
             when 'general english' then '\mgeneral english\M'
             when 'ielts preparation' then '\mielts\M'
             when 'academic english' then '(academic english|english for academic purposes|\meap\M)'
             else '(general english|academic english|english for academic purposes|\meap\M|\mielts\M|\melicos\M|english language)' end;
    select coalesce(array_agg(course_id),'{}') into v_old from scholarship.course_mappings
     where scholarship_id=s.id and mapping_basis in ('explicit_provider_scope','sweep_level_field_scope') and not (course_id=any(v_new));
    if cardinality(v_old)>0 then
      delete from scholarship.course_mappings where scholarship_id=s.id and course_id=any(v_old) and mapping_basis in ('explicit_provider_scope','sweep_level_field_scope');
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
      values (s.id,'course_links_removed',jsonb_build_object('courses',cardinality(v_old),'course_ids',to_jsonb(v_old)),jsonb_build_object('reason','English language course scholarship: not linked to other courses','english_course',f->'english_course'),pg.evidence_id);
      v_changes:=v_changes||'course_links_removed'::text;
    end if;
    delete from scholarship.scopes sc using pipeline.sources src where sc.source_id=src.id and src.source_type='provider_course_page_sweep' and sc.scope_type='study_level' and sc.scholarship_id=s.id;
    if cardinality(v_new)>0 then
      insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,evidence_id,mapped_by,mapped_at,updated_at)
      select s.id, x, 'mapped', 'sweep_level_field_scope', pg.evidence_id, null, now(), now() from unnest(v_new) x
      on conflict (scholarship_id,course_id) do update set mapping_basis='sweep_level_field_scope', mapping_state='mapped', evidence_id=excluded.evidence_id, updated_at=now();
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
      values (s.id,'course_links',null,jsonb_build_object('courses',cardinality(v_new),'english_course',f->'english_course'),pg.evidence_id);
      v_changes:=v_changes||'course_links'::text;
    end if;
    if cardinality(v_old)+cardinality(v_new)>0 then perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_old||v_new)),true); end if;
    update pipeline.scholarship_pages set applied_at=now(), apply_result=jsonb_build_object('changes',to_jsonb(v_changes),'english_course',f->'english_course') where scholarship_id=s.id;
    return jsonb_build_object('applied',true,'changes',to_jsonb(v_changes));
  end if;

  v_codes:=security.scholarship_level_codes(f->'levels');$n$;
  if (length(v)-length(replace(v,o,'')))/length(o)<>1 then raise exception 'apply anchor not found exactly once'; end if;
  execute replace(v,o,n);

  -- 2, 3. publishability
  if (select md5(prosrc) from pg_proc where oid='security.scholarship_publishability_v1()'::regprocedure)<>'46a535efa6f2ea9722fa42391af7d286' then
    raise exception 'scholarship_publishability_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('security.scholarship_publishability_v1()'::regprocedure);
  o:=$o$ then 'held after hand-check' end,$o$;
  n:=$n$ then 'held after hand-check' end,
        case when sp.facts is not null and coalesce((sp.facts->>'not_offered')::boolean,false) then 'not currently offered (provider page)' end,
        case when sp.facts ? 'english_course' and exists (select 1 from scholarship.course_mappings cm join catalogue.courses c on c.id=cm.course_id
                   left join ref.study_levels sl on sl.id=c.study_level_id where cm.scholarship_id=s.id and cm.mapping_state='mapped' and coalesce(sl.code,'')<>'non_aqf_award')
             then 'English language course linked to other courses' end,$n$;
  if (length(v)-length(replace(v,o,'')))/length(o)<>1 then raise exception 'publishability anchor not found exactly once'; end if;
  execute replace(v,o,n);
end $patch$;

-- 4. read again every unpublished active record with a read provider page (state before kept for the change count)
create table if not exists pipeline.scholarship_reread_snapshots (
  run_label text not null, scholarship_id uuid not null, levels jsonb, not_offered boolean, english_course jsonb, linked_courses int,
  publishable boolean, missing text[], captured_at timestamptz not null default now(), primary key (run_label, scholarship_id));
alter table pipeline.scholarship_reread_snapshots enable row level security;
revoke all on pipeline.scholarship_reread_snapshots from public, anon, authenticated;
insert into pipeline.scholarship_reread_snapshots(run_label,scholarship_id,levels,not_offered,english_course,linked_courses,publishable,missing)
select 'v0.5.0-before', s.id, sp.facts->'levels', coalesce((sp.facts->>'not_offered')::boolean,false), sp.facts->'english_course',
       (select count(*) from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped'), p.publishable, p.missing
  from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id=sp.scholarship_id
  join security.scholarship_publishability_v1() p on p.scholarship_id=s.id
 where s.lifecycle_status='active' and sp.read_status='read'
on conflict do nothing;
do $rv$
declare v_ids uuid[];
begin
  select coalesce(array_agg(sp.scholarship_id),'{}') into v_ids from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id=sp.scholarship_id
   where s.lifecycle_status='active' and s.publication_status<>'published' and sp.read_status='read';
  insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
  select sc.scholarship_id,'revert',jsonb_build_object('study_level_scopes',count(*)),'{"reason":"level hand-check; re-read with scholarship-sweep-v0.5.0"}'::jsonb
    from scholarship.scopes sc join pipeline.sources src on src.id=sc.source_id and src.source_type='provider_course_page_sweep'
   where sc.scope_type='study_level' and sc.scholarship_id=any(v_ids) group by sc.scholarship_id;
  delete from scholarship.scopes sc using pipeline.sources src where sc.source_id=src.id and src.source_type='provider_course_page_sweep' and sc.scope_type='study_level' and sc.scholarship_id=any(v_ids);
  update pipeline.scholarship_pages set next_read_at=now(), attempts=0, leased_until=null where scholarship_id=any(v_ids);
end $rv$;
