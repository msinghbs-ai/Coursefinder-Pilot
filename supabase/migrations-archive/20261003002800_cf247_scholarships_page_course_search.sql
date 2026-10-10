-- CF-247 (3 Oct 2026, 23:15 AEST). Platform Admin, comment on the scholarships mockup (21:36): "Search — on course as
-- well". The Scholarships list read takes a course search (p_args->>'course': course title or CRICOS / course code):
-- only scholarships linked to a matching course by a decided course link are listed. The list also carries the clean
-- value label (Decision 248) and the number of linked courses. Replaced under an md5 guard.
do $g$ declare v_oid oid; v_def text; begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'admin_scholarships_page';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from 'ac15da340a80f56f04299ef8d44e509b' then raise exception 'admin_scholarships_page changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  if (length(v_def) - length(replace(v_def, $x$        and (nullif(p_args->>'audience','') is null or s.audience::text=p_args->>'audience')$x$, ''))) / length($x$        and (nullif(p_args->>'audience','') is null or s.audience::text=p_args->>'audience')$x$) <> 1 then raise exception 'audience predicate not found exactly once'; end if;
  v_def := replace(v_def, $x$        and (nullif(p_args->>'audience','') is null or s.audience::text=p_args->>'audience')$x$,
    $x$        and (nullif(p_args->>'audience','') is null or s.audience::text=p_args->>'audience')
        and (nullif(trim(coalesce(p_args->>'course','')),'') is null or exists (
              select 1 from scholarship.course_mappings cm join catalogue.courses c on c.id=cm.course_id
               where cm.scholarship_id=s.id and cm.mapping_state='mapped'
                 and (c.canonical_title ilike '%'||trim(p_args->>'course')||'%' or coalesce(c.display_title,'') ilike '%'||trim(p_args->>'course')||'%' or coalesce(c.course_code,'') ilike trim(p_args->>'course')||'%')))$x$);
  if (length(v_def) - length(replace(v_def, $x$s.audience,s.nationalities,s.award_value_text,$x$, ''))) / length($x$s.audience,s.nationalities,s.award_value_text,$x$) <> 1 then raise exception 'column list not found exactly once'; end if;
  execute replace(v_def, $x$s.audience,s.nationalities,s.award_value_text,$x$, $x$s.audience,s.nationalities,scholarship.value_label(s.id) value_label,s.award_value_text,$x$);
end $g$;
