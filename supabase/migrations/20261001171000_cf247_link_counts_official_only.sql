-- CF-247: course links now hold several kinds of link (Decision 200: official course page, handbook, international page,
-- how to apply, admission centre, regulator listing). Everywhere the platform asks "does this course have a link?" it
-- means the provider's official course page: the public search projection (has_link), the data quality views, the
-- admin Courses list and the Layer 2 factual snapshot. Without this change the 6,475 NZQA regulator listings added on
-- 1 Oct 2026 would count as course pages. Each function below is edited in place from its live definition, only if its
-- live body is the one checked on 1 Oct 2026 (md5 guard), and every reference to catalogue.course_links in it must take
-- the official-page condition exactly once.

do $official$
declare
  r record; s text; d text; v text; refs int; added int;
  fns text[][] := array[
    array['search','refresh_course_documents_v2','be471e0af75dc59c275ef7ec1e772b1b'],
    array['security','data_quality_course_base','c4dd11edf3ff69ab0e5886f346d5f562'],
    array['security','data_quality_overview_impl','0aca0be7db878cb7e419ad6af567ed41'],
    array['security','data_quality_exceptions_impl','94b35e262b0c8889f257129273c7c85d'],
    array['security','admin_course_page_fast_base','fb744daf34666e8bbe297c1b1e244435'],
    array['security','admin_course_page_unfiltered_fast','87e33f273631aff2158b9f675e3e8910'],
    array['public','ui_courses_decision_page','43545b749982af6d82487a87932bf6b9'],
    array['pipeline','layer2_course_factual_snapshot','fcdb007166d657ede260322c1e43d252']];
  i int;
begin
  for i in 1 .. array_length(fns, 1) loop
    select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = fns[i][1] and p.proname = fns[i][2];
    v := md5(s);
    if v is distinct from fns[i][3] then raise exception '%.% changed (md5 %); not replacing', fns[i][1], fns[i][2], v; end if;
    refs := (length(s) - length(replace(s, 'catalogue.course_links', ''))) / length('catalogue.course_links');
    -- "catalogue.course_links <alias> where ..." -> "... where <alias>.link_type = 'official_course' and ..."
    d := regexp_replace(d, 'catalogue\.course_links (l|cl)(\s+)where ', 'catalogue.course_links \1\2where \1.link_type = ''official_course'' and ', 'g');
    -- "catalogue.course_links l join <scope> on <...>=l.course_id group by" -> "... where l.link_type = 'official_course' group by"
    d := regexp_replace(d, '(catalogue\.course_links l join (?:scope s on s\.id|course_scope c on c\.id)=l\.course_id) group by',
                        '\1 where l.link_type = ''official_course'' group by', 'g');
    added := (length(d) - length(replace(d, 'link_type = ''official_course''', ''))) / length('link_type = ''official_course''')
           - (length(s) - length(replace(s, 'link_type = ''official_course''', ''))) / length('link_type = ''official_course''');
    if added <> refs then raise exception '%.%: % references to course_links but % official-page conditions added', fns[i][1], fns[i][2], refs, added; end if;
    execute d;
  end loop;
end $official$;
