-- CF-247 (3 Oct 2026, 10:05 AEST). Rapid admission plan, step 3 (Platform Admin, 08:17: "I need solid full proof plan for
-- rapid data admission"): a course that failed a step is retried with the next method, nothing is dropped.
-- Found at 10:00: 11,653 course searches ended "none" with results stored (up to 5 pages each) because, when they ran
-- (1–2 Oct), the university had no URL recipe, so security.course_link_pick_v1 kept nothing. The 459 generic recipes
-- added at 20261003000600 now pick a candidate for 8,789 of them (AU 4,011, NZ 3,424, CA 1,354) whose course still has
-- no official page. No new search is needed (0 search credits): the stored results are picked again under the same
-- function and the first candidate is bound exactly as svc_course_link_search_record binds a fresh result. The page is
-- then read and judged by the identity rule like any other candidate; a page that does not prove itself is rejected.
-- A course whose page was bound by another method is left alone (course_link_bind_v1 only replaces a search binding
-- or a page that is not bound). Nothing is written to the catalogue here.
do $r$
declare r record; v_c text[]; v_n int := 0;
begin
  for r in
    select s.course_id, s.provider_id, s.stage, (select array_agg(x) from jsonb_array_elements_text(s.results) x) urls
      from pipeline.course_link_search s
     where s.state = 'none' and jsonb_typeof(s.results) = 'array' and jsonb_array_length(s.results) > 0
       and not exists (select 1 from catalogue.course_links l where l.course_id = s.course_id and l.link_type = 'official_course')
  loop
    v_c := security.course_link_pick_v1(r.provider_id, r.urls);
    if cardinality(v_c) > 0 then
      update pipeline.course_link_search
         set state = 'found', candidates = to_jsonb(v_c), cand_idx = 1, bound_url = v_c[1], done_at = now()
       where course_id = r.course_id and state = 'none';
      perform security.course_link_bind_v1(r.course_id, r.provider_id, v_c[1], case r.stage when 'cricos' then 'cricos_search' else 'title_search' end);
      v_n := v_n + 1;
    end if;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('requeue', 'repick', 'Course-page searches ended "none" before their university had a recipe: stored results picked again',
          jsonb_build_object('bound', v_n, 'search_credits', 0, 'direction', 'Platform Admin 3 Oct 2026 08:17 (rapid admission plan, step 3)'),
          '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
end $r$;
