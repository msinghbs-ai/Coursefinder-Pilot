-- CF-247 s1280 (S1-Build; SS-Programme-Control 26 Nov 2026 22:27 AEDT, "First autonomous AER cycle: admission and consumer integrity").
-- Found (26 Nov 22:30 to 23:00 AEDT, read-only, the official pages read directly at $0):
--   121558M Certificate III in Carpentry (Melbourne College of Business and Technology), 121594G Certificate III in Carpentry (Canberra College),
--   121475C Certificate IV in Kitchen Management and 121476B Diploma of Hospitality Management (Redford Institute) each hold
--   "Australian Year 12 or (an) equivalent" as audience domestic, so Website v2 and v3 show it as a domestic requirement. The pages print it under
--   "Entry Requirements International Students" (MCBT) or for all "Applicants" (Redford). Cause: the course entry prompt (course-entry-v1) calls a
--   sentence domestic when it names an Australian school-leaver route, and the model read "Australian Year 12 or equivalent" as one. Identity,
--   source page and quotes are right; only the audience is wrong. The same defect holds 701 active rows on 671 courses (686 read by gpt-4.1-mini).
-- Fix (both live on deploy; worker v1.0.52 for new reads, this migration for admitted rows):
--   a row whose audience is domestic, whose quote accepts an equivalent qualification ("or equivalent", "or an equivalent", "or any equivalent")
--   and names no domestic-only route or group (VCE, ATAR, VTAC, STAT, QCE, HSC, SACE, WACE, UAC, QTAC, SATAC, TISC, selection rank, school leaver,
--   domestic, local, citizen, permanent resident) becomes audience all. Nothing else in the row changes; provenance keeps the earlier audience.
--   Manually locked courses (aer.schedule_lock_fields or 'all') are left unchanged. Each row's id and earlier audience go in one audit event.
-- Not changed: 121558M's "Diploma or Advanced Diploma from the BSB Training Package ... operational or leadership role" row. The official
--   carpentry page prints it under "Academic Requirements" (not extracted from another course page), while its international section says there
--   are no prerequisites: a source content conflict recorded as an integration issue for Layer 4 review, not withdrawn here. Redford's pages also
--   carry an international "Admission requirements" block naming BSB50420 (another course); recorded with it.
-- Recorded: two rows in pipeline.integration_issues (the defect, deployed; the source conflict, triaged for Layer 4).
-- G1: no job. G2: no setting. G3: no consumer object changed (checked); the consumer reads take the corrected rows. Locks unchanged. Nothing dropped
-- or deleted.
-- Replaces: the domestic audience of the equivalent-route rows. Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the row updates

create temp table s1280_guard on commit drop as
select (select count(*) from pipeline.manual_locks) as locks_before;
create temp table s1280_cron on commit drop as select jobid from cron.job;  -- the job ids: this change creates none (another lane may switch a job meanwhile)

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $g$;

create temp table s1280_rows on commit drop as
select e.id, e.course_id, e.audience
  from catalogue.course_entry_requirements e
 where e.status = 'active' and e.audience = 'domestic'
   and e.quote ~* '\mor (an |any )?equivalent'
   and e.quote !~* '\m(VCE|ATAR|VTAC|STAT|QCE|HSC|SACE|WACE|UAC|QTAC|SATAC|TISC|selection rank|school.leaver|domestic|local|citizen|permanent resident)\M'
   and not exists (select 1 from pipeline.manual_locks l
                    where l.entity = 'course' and l.entity_id = e.course_id
                      and (l.field = 'all' or coalesce(security.toolset_setting('pipeline', 'aer.schedule_lock_fields'), '[]'::jsonb) ? l.field));

do $a$
declare v_n int; v_reason constant text := 'CF-247 s1280: "Australian Year 12 or equivalent" accepts an equivalent qualification, so it applies to all applicants (SS-Programme-Control 26 Nov 2026 22:27 AEDT)';
begin
  update catalogue.course_entry_requirements e
     set audience = 'all', updated_at = now(),
         provenance = coalesce(e.provenance, '{}'::jsonb) || jsonb_build_object('audience_corrected', jsonb_build_object('from', 'domestic', 'by', 'CF-247 s1280', 'at', now()))
   where e.id in (select id from s1280_rows);
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('aer', 'audience_correct', 'catalogue.course_entry_requirements', jsonb_build_object('reason', v_reason, 'rows', v_n,
          'courses', (select count(distinct course_id) from s1280_rows), 'from', 'domestic', 'to', 'all',
          'ids', (select jsonb_agg(id order by id) from s1280_rows), 'via', 'CF-247 s1280 migration'), null);
end $a$;

-- the defect and the source conflict, in the existing integration issue register
insert into pipeline.integration_issues(fingerprint, title, layer, subsystem, failure, expected, detection_source, validation_layer, root_cause_class, severity,
                                        workstream, status, course_ids, evidence, fix_migration, deployed_version)
select 'aer:audience:equivalent-route-domestic', 'AER course entry: "Australian Year 12 or equivalent" admitted as domestic', 'AER', 'aer',
       '701 active course entry rows on 671 courses said domestic for a route that accepts an equivalent qualification; Website v2 and v3 showed them as domestic requirements (reported for 121558M, 121594G, 121475C, 121476B after scheduled run 593, 26 Nov 2026 22:13 AEDT).',
       'A route that accepts an equivalent qualification and names no domestic-only route or group applies to all applicants.',
       'S1-Build investigation (SS-Programme-Control 22:27 AEDT)', 'V4', 'code_defect', 'P1',
       coalesce((select i.workstream from pipeline.integration_issues i where i.subsystem ilike '%aer%' group by 1 order by count(*) desc limit 1), 'A1'), 'deployed',
       (select array_agg(distinct course_id) from s1280_rows),
       jsonb_build_object('rows', (select count(*) from s1280_rows), 'cause', 'course-entry-v1 audience rule: Australian school-leaver route', 'fix', 'worker v1.0.52 entryAudience; migration s1280'),
       '20261130031500', 'coverage-sweep-worker-v1.0.52'
 where not exists (select 1 from pipeline.integration_issues where fingerprint = 'aer:audience:equivalent-route-domestic');
insert into pipeline.integration_issues(fingerprint, title, layer, subsystem, failure, expected, detection_source, validation_layer, root_cause_class, severity,
                                        workstream, status, course_ids, evidence)
select 'aer:source-conflict:mcbt-redford-template-blocks', 'AER source conflict: provider pages carry another course''s entry wording', 'AER', 'aer',
       'The official 121558M Certificate III in Carpentry page prints "Diploma or Advanced Diploma from the BSB Training Package ... operational or leadership role" under Academic Requirements while its international section says there are no prerequisites; Redford pages (121475C, 121476B) carry an international Admission requirements block naming BSB50420. The rows quote the course''s own page (not cross-course extraction by the reader).',
       'Layer 4 review against the provider: keep, correct or close the conflicting row with the provider''s confirmed requirement; valid rows stay.',
       'S1-Build investigation (SS-Programme-Control 22:27 AEDT)', 'manual', 'unclassified', 'P2',
       coalesce((select i.workstream from pipeline.integration_issues i where i.subsystem ilike '%aer%' group by 1 order by count(*) desc limit 1), 'A1'), 'triaged',
       (select array_agg(c.id) from catalogue.courses c where c.course_code in ('121558M', '121475C', '121476B')),  -- fixed: the courses the conflict was found on
       jsonb_build_object('pages', jsonb_build_array('https://mcbt.vic.edu.au/our-courses/certificate-iii-in-carpentry', 'https://www.redfordinstitute.edu.au/sit50422-diploma-of-hospitality-management/'), 'read', '26 Nov 2026 22:40 AEDT, direct, $0')
 where not exists (select 1 from pipeline.integration_issues where fingerprint = 'aer:source-conflict:mcbt-redford-template-blocks');

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1280_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1280_guard) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select 1 from catalogue.course_entry_requirements e join s1280_rows r on r.id = e.id where e.audience <> 'all' or e.status <> 'active') then
    raise exception 'post-check: a corrected row is not active with audience all';
  end if;
  if exists (select 1 from catalogue.course_entry_requirements e join catalogue.courses c on c.id = e.course_id
              where c.course_code in ('121558M', '121594G', '121475C', '121476B') and e.status = 'active' and e.audience = 'domestic') then  -- fixed: the four reported courses
    raise exception 'post-check: a reported course still holds a domestic equivalent-route row';
  end if;
end $c$;
