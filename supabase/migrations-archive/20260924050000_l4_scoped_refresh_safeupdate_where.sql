-- Layer 4 approvals from the app failed with "UPDATE requires a WHERE clause": requests
-- through the API run with pg_safeupdate, which blocks UPDATE/DELETE without WHERE. The
-- scoped search refresh (called when a tuition decision records a fee) updated its working
-- table without one. Adding "where s.course_id is not null" keeps behaviour identical
-- (every working row has a course) and satisfies the guard. Guarded substitution.
do $mig$
declare d text;
  a text := E'''semantic_text'',s.enrichment_semantic_text\n  )::text,''sha256''),''hex'');';
  b text := E'''semantic_text'',s.enrichment_semantic_text\n  )::text,''sha256''),''hex'')\n  where s.course_id is not null;';
begin
  d := pg_get_functiondef('search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean)'::regprocedure);
  if strpos(d,b)>0 then return; end if;
  if (length(d)-length(replace(d,a,'')))/length(a) <> 1 then raise exception 'anchor not found exactly once'; end if;
  execute replace(d,a,b);
end $mig$;
