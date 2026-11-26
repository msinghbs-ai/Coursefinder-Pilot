-- CF-247 s1284 (S1-Build; SS-Programme-Control 26 Nov 2026 22:27 AEDT, "First autonomous AER cycle: admission and consumer integrity").
-- Found in the consumer read-back after s1280 (26 Nov 23:35 AEDT): Website v2 serves 121476B Diploma of Hospitality Management with entry
--   min_score 18, from "Applicants must be 18 years of age or over at the time of application." The course entry reader filed a minimum age as
--   kind minimum_grade with min_entry_score 18. The same holds 1,402 active rows on 1,365 courses (76 from today's cycles); none is manually locked.
-- Fix (both live on deploy; worker v1.0.53 entryAgeNotScore for new reads, this migration for admitted rows): an active minimum_grade row whose
--   score is 14 to 30, whose quote names an age (years of age, years old, years or older, aged, age of, minimum age, age) and no score word (ATAR,
--   rank, GPA, WAM, score, grade, percent, %) becomes kind general_note with no score and no score basis. Quote, description, audience and source
--   stay; provenance keeps the earlier kind, score and basis; every id is logged. Manually locked courses are left unchanged.
-- Recorded: one row in pipeline.integration_issues (code defect, deployed).
-- G1: no job. G2: no setting. G3: no consumer object changed (checked); the consumer reads take the corrected rows. Locks unchanged. Nothing dropped
-- or deleted.
-- Replaces: the minimum_grade kind and score of the age rows. Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the row updates

create temp table s1284_guard on commit drop as select (select count(*) from pipeline.manual_locks) as locks_before;
create temp table s1284_cron on commit drop as select jobid from cron.job;  -- the job ids: this change creates none

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $g$;

create temp table s1284_rows on commit drop as
select e.id, e.course_id, e.kind, e.min_entry_score, e.min_entry_score_basis
  from catalogue.course_entry_requirements e
 where e.status = 'active' and e.kind = 'minimum_grade'
   and e.min_entry_score between 14 and 30  -- fixed: the ages a page prints
   and e.quote ~* '\m(years of age|years old|years or older|aged|age of|minimum age|age)\M'
   and e.quote !~* '\m(ATAR|rank|GPA|WAM|score|grade|percent)\M' and e.quote not like '%\%%'
   and not exists (select 1 from pipeline.manual_locks l
                    where l.entity = 'course' and l.entity_id = e.course_id
                      and (l.field = 'all' or coalesce(security.toolset_setting('pipeline', 'aer.schedule_lock_fields'), '[]'::jsonb) ? l.field));

do $a$
declare v_n int; v_reason constant text := 'CF-247 s1284: a minimum age is an entry condition, not a minimum entry score (SS-Programme-Control 26 Nov 2026 22:27 AEDT)';
begin
  update catalogue.course_entry_requirements e
     set kind = 'general_note', min_entry_score = null, min_entry_score_basis = null, updated_at = now(),
         provenance = coalesce(e.provenance, '{}'::jsonb) || jsonb_build_object('age_not_score', jsonb_build_object('kind', r.kind, 'min_entry_score', r.min_entry_score,
                        'min_entry_score_basis', r.min_entry_score_basis, 'by', 'CF-247 s1284', 'at', now()))
    from s1284_rows r
   where e.id = r.id;
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('aer', 'age_not_score', 'catalogue.course_entry_requirements', jsonb_build_object('reason', v_reason, 'rows', v_n,
          'courses', (select count(distinct course_id) from s1284_rows), 'from', 'minimum_grade', 'to', 'general_note',
          'ids', (select jsonb_agg(id order by id) from s1284_rows), 'via', 'CF-247 s1284 migration'), null);
end $a$;

insert into pipeline.integration_issues(fingerprint, title, layer, subsystem, failure, expected, detection_source, validation_layer, root_cause_class, severity,
                                        workstream, status, course_ids, evidence, fix_migration, deployed_version)
select 'aer:kind:age-read-as-entry-score', 'AER course entry: a minimum age admitted as a minimum entry score', 'AER', 'aer',
       '1,402 active rows on 1,365 courses held a minimum age (for example "Applicants must be 18 years of age") as kind minimum_grade with min_entry_score 18; Website v2 served min_score 18 (found on 121476B after scheduled run 593, 26 Nov 2026).',
       'A minimum age is an entry condition (general_note) with no entry score.',
       'S1-Build consumer read-back (SS-Programme-Control 22:27 AEDT)', 'V4', 'code_defect', 'P1',
       coalesce((select i.workstream from pipeline.integration_issues i where i.subsystem ilike '%aer%' group by 1 order by count(*) desc limit 1), 'A1'), 'deployed',
       (select array_agg(distinct course_id) from s1284_rows),
       jsonb_build_object('rows', (select count(*) from s1284_rows), 'cause', 'course-entry-v1 minimum_grade read for a printed age', 'fix', 'worker v1.0.53 entryAgeNotScore; migration s1284'),
       '20261130051500', 'coverage-sweep-worker-v1.0.53'
 where not exists (select 1 from pipeline.integration_issues where fingerprint = 'aer:kind:age-read-as-entry-score');

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1284_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1284_guard) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select 1 from catalogue.course_entry_requirements e join s1284_rows r on r.id = e.id where e.kind <> 'general_note' or e.min_entry_score is not null or e.status <> 'active') then
    raise exception 'post-check: a corrected row is not an active general_note without a score';
  end if;
end $c$;
