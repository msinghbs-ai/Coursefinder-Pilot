-- CF-247 RM1I / RM1H page facts: two patterns follow the rendered pages (S2-Build; Platform Admin 18 Nov 2026 17:55).
--
-- What was read live (18 Nov 2026 18:40 AEDT, third load through workflow destination-run-now, run ba40a51e; Firecrawl 2 credits): four Home
-- Affairs facts found with verbatim quotes (Student visa charge AUD2,500, Temporary Graduate visa charge AUD5,750, work up to 48 hours a
-- fortnight, Overseas Student Health Cover) and 1,577 JSA OSCA occupation rows loaded from Table 1. Two facts were not found:
--   * the 12-month living cost: the rendered Student visa page (87,589 characters) says the amount is under "Gather Documents" in
--     Step by Step. The amounts sit in a table, and the reader puts a stop between table cells, so a pattern that stops at a full stop never
--     reached the amount. The pattern now reads from the row label (primary applicant, student or guardian) to the amount across cells.
--   * the Post-Higher Education Work stream stay: the Temporary Graduate visa overview page names the streams but not their stay periods,
--     which are on each stream's own page. The fact now reads the stream page (rendered) for the stay after a bachelor degree; the overview
--     fact is retired (an update; nothing is deleted).
-- A miss still writes nothing and shows the page text around the anchor. Nothing is dropped or deleted. G3 untouched.
-- Replaces: the visa_funds pattern; the post_study_work fact on the overview page.
-- Retires: nothing (the retired fact row stays for its history).

update destination.page_facts
   set pattern = '(?:primary applicant|student or guardian|student/guardian|student primary applicant)[^0-9]{0,120}?AUD\s?\$?\s?([0-9]{2},[0-9]{3})',
       anchor = 'primary applicant|student or guardian|student/guardian',
       note = coalesce(note || '; ', '') || '18 Nov 2026 (20261118224000): reads from the row label to the amount across table cells',
       updated_at = now()
 where status = 'active' and rule_category = 'visa_funds' and page_url = 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500';

update destination.page_facts
   set status = 'retired', updated_at = now(),
       note = coalesce(note || '; ', '') || '18 Nov 2026 (20261118224000): the overview page names the stream but not its stay; read from the stream page'
 where status = 'active' and rule_category = 'post_study_work' and page_url = 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/temporary-graduate-485';

insert into destination.page_facts(country_code, edition_label, page_url, kind, rule_category, title, applicant_scope, pattern, unit, min_value, max_value, anchor, read_mode, note)
select 'AU', 'Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages',
       'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/temporary-graduate-485/post-higher-education-work',
       'number', 'post_study_work', 'Temporary Graduate visa (subclass 485) Post-Higher Education Work stream stay after a bachelor degree', 'graduate with a bachelor degree',
       'bachelor[^0-9]{0,160}?([1-6])\s+years?', 'years', 1, 6, 'bachelor|stay', 'rendered', 'Seeded 18 Nov 2026 (20261118224000)'
 where not exists (select 1 from destination.page_facts f where f.status = 'active' and f.page_url = 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/temporary-graduate-485/post-higher-education-work'
                     and f.title = 'Temporary Graduate visa (subclass 485) Post-Higher Education Work stream stay after a bachelor degree');

do $$
begin
  if (select count(*) from destination.page_facts where status = 'active' and rule_category = 'post_study_work') <> 1 then raise exception 'post-check: one active post-study work fact'; end if;
  if not exists (select 1 from destination.page_facts where status = 'active' and rule_category = 'visa_funds' and pattern like '(?:primary applicant%') then raise exception 'post-check: visa funds pattern'; end if;
  if exists (select 1 from destination.page_facts where status = 'active' and page_url like 'https://immi.homeaffairs.gov.au/%' and read_mode <> 'rendered') then raise exception 'post-check: Home Affairs pages read rendered'; end if;
end $$;
