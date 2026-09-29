-- CF-247 scholarship sweep v0.5.1: two corrections found while checking the population with v0.5.0 - "no longer
-- available" as a condition ("any change ... will result in the scholarship being no longer available", Griffith) is not
-- "not currently offered", and "students with an undergraduate degree qualification" is earlier study, not a level
-- (Monash University Indonesia). Unpublished pages read by v0.5.0 are read again. Published records are not re-read.
update pipeline.scholarship_pages sp set next_read_at=now(), attempts=0, leased_until=null
  from scholarship.scholarships s
 where s.id=sp.scholarship_id and s.lifecycle_status='active' and s.publication_status<>'published' and sp.read_status='read'
   and coalesce(sp.facts->>'extractor','')='scholarship-sweep-v0.5.0';
