do $patch$
declare d text; n int;
  new_w constant text := 'from cf_search_enrichment_stage s where d.course_id=s.course_id and (d.enrichment_content_hash is distinct from s.enrichment_content_hash or d.projection_version is distinct from ''course-v3'' or d.updated_at = now());';
begin
  select pg_get_functiondef('search.refresh_course_enrichment_core_v1(boolean)'::regprocedure) into d;
  if md5(d) <> '9e339a25d36b7768e9c3e7c2c1589c6a' then raise exception 'refresh_course_enrichment_core_v1 changed since review (md5 %)', md5(d); end if;
  select count(*) into n from regexp_matches(d, 'from\s+cf_search_enrichment_stage\s+s\s+where\s+d\.course_id\s*=\s*s\.course_id\s*;', 'gi');
  if n<>1 then raise exception 'document update condition found % times', n; end if;
  d := regexp_replace(d, 'from\s+cf_search_enrichment_stage\s+s\s+where\s+d\.course_id\s*=\s*s\.course_id\s*;', new_w, 'i');
  execute d;
end $patch$;
