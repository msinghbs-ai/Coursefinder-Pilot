-- CF-247 (19 Oct 2026). Platform Admin 17:05: "Proceed with task 4,5 and 6" (6: check the 20 Adelaide University courses that kept their
-- old page after the re-find on the new website).
-- Found: Adelaide University's course-page search accepts only https://adelaideuni.edu.au/study/degrees/<name>/. The search had found the
-- right new pages for 12 of the 20, but in shapes the recipe refused: online degrees (/study/degrees/online/<name>/), the international
-- page of a degree (/study/degrees/<name>/int/) and English courses (/study/english-language-centre/<name>/). The other 8 found only
-- unit pages (not offered under that name on the new site, or not found); they keep their old page.
-- 1 The recipe also accepts those three shapes (the degree page first, as before).
-- 2 The kept-old re-finds whose stored search results now give a candidate are opened again from those results (no new search, no credit):
--   the first candidate is bound and read; it replaces the old page only once the reader accepts it is this course's (as before), and if
--   none passes the old page is put back again.
-- Replaces: the Adelaide University course-page recipe patterns (one pattern; now four)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $p$
declare v_prov uuid; v_pat jsonb; r record; v_c text[]; v_n int := 0;
begin
  select pv.id into v_prov from catalogue.providers pv where pv.canonical_name = 'Adelaide University';
  select rc.patterns into v_pat from pipeline.course_link_recipes rc where rc.provider_id = v_prov and rc.active;
  if v_pat is distinct from '[{"re": "^https?://(www\\.)?adelaideuni\\.edu\\.au/study/degrees/([a-z0-9-]+)/?$", "rep": "https://adelaideuni.edu.au/study/degrees/\\2/"}]'::jsonb then
    raise exception 'Adelaide University recipe differs from the one this change extends: %', v_pat;
  end if;
  update pipeline.course_link_recipes set patterns = v_pat || '[
      {"re": "^https?://(www\\.)?adelaideuni\\.edu\\.au/study/degrees/online/([a-z0-9-]+)/?$", "rep": "https://adelaideuni.edu.au/study/degrees/online/\\2/"},
      {"re": "^https?://(www\\.)?adelaideuni\\.edu\\.au/study/degrees/([a-z0-9-]+)/int/?$", "rep": "https://adelaideuni.edu.au/study/degrees/\\2/int/"},
      {"re": "^https?://(www\\.)?adelaideuni\\.edu\\.au/study/english-language-centre/([a-z0-9-]+)/?$", "rep": "https://adelaideuni.edu.au/study/english-language-centre/\\2/"}]'::jsonb,
         notes = 'Adelaide University: degree page; online degree; international degree page; English course (19 Oct 2026)', updated_at = now()
   where provider_id = v_prov and active;

  for r in select f.course_id, s.results from pipeline.page_refind f join pipeline.course_link_search s on s.course_id = f.course_id
            where f.provider_id = v_prov and f.state = 'kept_old' and jsonb_typeof(s.results) = 'array' loop
    v_c := security.course_link_pick_v1(v_prov, array(select jsonb_array_elements_text(r.results)));
    continue when cardinality(v_c) = 0;
    update pipeline.page_refind set state = 'open', decided_at = null, result_url = null where course_id = r.course_id;
    update pipeline.course_link_search set state = 'found', candidates = to_jsonb(v_c), cand_idx = 1, bound_url = v_c[1], done_at = now()
     where course_id = r.course_id;
    perform security.course_link_bind_v1(r.course_id, v_prov, v_c[1], 'title_search');
    v_n := v_n + 1;
  end loop;
  if v_n <> 12 then raise exception 'expected 12 re-finds opened again from stored results, got %', v_n; end if;  -- fixed: the reviewed set
end $p$;

do $post$
begin
  if (select count(*) from pipeline.page_refind f join pipeline.coverage_course_pages g on g.course_id = f.course_id
       where f.state = 'open' and g.url like 'https://adelaideuni.edu.au/%' and g.status = 'bound') < 12 then raise exception 'post-check: new pages not bound'; end if;
  if (select count(*) from pipeline.page_refind where state = 'kept_old') <> 8 then raise exception 'post-check: kept-old count'; end if;
end $post$;
