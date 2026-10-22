-- CF-247 (22 Oct 2026). Found on the first live run of job country-scope-gate (scope ca-intl-college-plus-v2): 15 active Canadian courses
-- with a level outside the scope (certificate I to IV, short course, non-AQF award) were not hidden, because the wait for a credential
-- read was applied to every course, and a course that already has a level is never read for one. The wait now applies only to courses
-- with no level.
-- Replaces: security.country_scope_gate_v1 (md5-guarded edit)
-- Retires: nothing
do $edit$
declare v_def text := pg_get_functiondef('security.country_scope_gate_v1(boolean,text)'::regprocedure);
        v_old text := $o$     and not exists (select 1 from pipeline.coverage_course_pages pg where pg.course_id = c.id and pg.read_status = 'read' and pg.evidence_id is not null$o$;
begin
  if position('c.study_level_id is not null or not exists' in v_def) > 0 then return; end if;
  if md5(v_def) <> '6f1b9d783af6e31dd7cf145b0fe06336' then raise exception 'live security.country_scope_gate_v1 differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'credential wait must occur once'; end if;
  v_def := replace(v_def, v_old, $n$     and (c.study_level_id is not null or not exists (select 1 from pipeline.coverage_course_pages pg where pg.course_id = c.id and pg.read_status = 'read' and pg.evidence_id is not null$n$);
  v_def := replace(v_def, $o$and r.evidence_id = pg.evidence_id and r.outcome <> 'leased'));$o$, $n$and r.evidence_id = pg.evidence_id and r.outcome <> 'leased')));$n$);
  execute v_def;
end $edit$;
do $dry$ begin raise exception 'DRYRUN OK %', security.country_scope_gate_v1(false, 'CA'); end $dry$;
