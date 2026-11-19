-- PERF-2: admission refreshes only the courses it admitted.
-- Proven equivalent before switching: for 350 courses (all Layer 3 admissions plus a
-- random 300), the scoped calculation matched the full calculation's content hash for
-- every course (0 mismatches, 0 missing); full dry run 31.5 s vs scoped 0.9 s.
-- Guarded: each substitution must match exactly once; re-running is a no-op.
do $mig$
declare d text;
  a1 text := 'v_ex_amount numeric; v_ex_cur text;';
  b1 text := 'v_ex_amount numeric; v_ex_cur text; v_course_ids uuid[] := ''{}'';';
  a2 text := E'    v_admitted := v_admitted + 1;\n';
  b2 text := E'    v_admitted := v_admitted + 1;\n    v_course_ids := v_course_ids || r.course_id;\n';
  a3 text := 'if v_admitted > 0 then v_refresh := search.refresh_course_enrichment_v1(true); end if;';
  b3 text := 'if v_admitted > 0 then v_refresh := search.refresh_course_enrichment_scoped_v1(v_course_ids, true); end if;';
begin
  d := pg_get_functiondef('security.layer3_tuition_admit_validated_v1(integer)'::regprocedure);
  if strpos(d, b3) > 0 then return; end if;
  if (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 then raise exception 'anchor 1 not found exactly once'; end if;
  if (length(d)-length(replace(d,a2,'')))/length(a2) <> 1 then raise exception 'anchor 2 not found exactly once'; end if;
  if (length(d)-length(replace(d,a3,'')))/length(a3) <> 1 then raise exception 'anchor 3 not found exactly once'; end if;
  execute replace(replace(replace(d,a1,b1),a2,b2),a3,b3);
end $mig$;
