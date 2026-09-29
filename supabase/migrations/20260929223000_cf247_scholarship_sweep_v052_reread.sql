-- CF-247 scholarship sweep v0.5.2 (hand-check of the re-read holds): Melbourne "Ormond College Scholarships" states
-- "Eligible study level Undergraduate, Honours, Graduate coursework, Graduate research" in its key details, but the
-- eligibility section mentions only undergraduate and graduate research. A page's own study-level field now decides the
-- levels when present. Unpublished pages read by v0.5.0/v0.5.1 are read again; published records are not re-read.
update pipeline.scholarship_pages sp set next_read_at=now(), attempts=0, leased_until=null
  from scholarship.scholarships s
 where s.id=sp.scholarship_id and s.lifecycle_status='active' and s.publication_status<>'published' and sp.read_status='read'
   and coalesce(sp.facts->>'extractor','') in ('scholarship-sweep-v0.5.0','scholarship-sweep-v0.5.1');
