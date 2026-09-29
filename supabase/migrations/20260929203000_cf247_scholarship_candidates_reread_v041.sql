-- CF-247 scholarship discovery hand-check of the first candidate reads (29 Sep 2026): RMIT scholarship detail pages
-- were rejected as listings (their menus list every scholarship) and supporting pages such as "Scholarship Specific
-- Terms and Conditions" carry "Scholarship" in their titles. Extractor scholarship-sweep-v0.4.1 counts listing links
-- from the page content only and excludes supporting pages; every candidate rejected by v0.4.0 is read again.
update pipeline.scholarship_page_candidates
   set admit_status=null, admit_reasons=null, next_read_at=now(), attempts=0, leased_until=null
 where admit_status='rejected' and coalesce(facts->>'extractor','')='scholarship-sweep-v0.4.0';
