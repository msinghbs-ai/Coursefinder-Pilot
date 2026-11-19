-- CF-247 scholarship discovery: most university sites refuse the worker's direct reads (HTTP 403). Candidate pages
-- the site refused are read again now that the worker falls back to Firecrawl for them (inside the 3,000-credit cap,
-- keeping 800 credits for step 1).
update pipeline.scholarship_page_candidates set next_read_at=now(), attempts=0, leased_until=null
 where read_status in ('blocked','fetch_failed','too_thin') and admit_status is null and matched_scholarship_id is null;
