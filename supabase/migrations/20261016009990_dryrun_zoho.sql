-- CF-247 (23 Oct 2026). Read with AI on the University of Auckland diplomas (13:13): the Diploma in Dance Studies took its delivery from the
-- Master of Dance Studies page. The AI reader for every attribute (Enrich fields, source ai_stored) read whatever page was last tried for
-- a course, also a page the platform had already found to be another course's (status mismatch: 3,364 values on 2,369 courses in AU, CA
-- and NZ since 14 Oct). It now reads only the page bound to the course (or an ambiguous page with an identity proof), as the adapter
-- path already does; a course whose only page is another course's says so ("no correct course page"). The values already taken from
-- such pages are listed for the Platform Admin; nothing is changed here.
-- Replaces: nothing (security.enrich_fields_slice_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', 'dc7176b941a17f0df7991c676ecd8ce1', array[
  array[$o$          select e.storage_path, e.id into v_path, v_ev from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id where g.course_id = it.course_id;$o$,
        $n$          -- 23 Oct 2026: only the course's own page: bound, or ambiguous with an identity proof; never a page found to be another course's
          select e.storage_path, e.id into v_path, v_ev from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id
           where g.course_id = it.course_id and g.status in ('bound', 'ambiguous') and (g.status = 'bound' or g.identity_basis is not null);
          if v_path is null then
            update pipeline.field_enrich_items set reason = 'no correct course page: the page found is for another course'
             where id = it.id and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = it.course_id and g.status = 'mismatch');
          end if;$n$]]);


do $d$
declare v_def text := pg_get_functiondef('security.enrich_fields_slice_v1(uuid,integer)'::regprocedure);
begin
  if v_def not like '%g.status in (''bound'', ''ambiguous'') and (g.status = ''bound'' or g.identity_basis is not null)%' then raise exception 'edit missing'; end if;
  if v_def like '%join pipeline.evidence_artifacts e on e.id = g.evidence_id where g.course_id = it.course_id;%' then raise exception 'old line still present'; end if;
  raise exception 'DRYRUN OK new md5 %', md5(v_def);
end $d$;
