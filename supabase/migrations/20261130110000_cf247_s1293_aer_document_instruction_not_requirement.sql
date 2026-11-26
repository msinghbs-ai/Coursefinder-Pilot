-- CF-247 s1293 (S2-AER; SS-Programme-Control 27 Nov 2026 09:57 AEDT, "Academic entry classification and Feedback 3 to 6 recovery", priority 1).
-- Found by S1-Build's morning check (27 Nov 09:55 AEDT) and traced to its stored evidence: 115246M (Certificate III in Individual Support, Job Training
--   Institute) holds an active prior_qualification row "Applicants should submit certified transcripts of all academic achievements, including secondary
--   school education" (quote "Certified transcripts of all academic achievements, including secondary school education"; Layer 4 item a7a8e264,
--   evidence 3b1a392d, content hash 9127385b..., captured 26 Nov 2026 20:25 UTC; read by enrich_ai, prompt course-entry-v1, gpt-4.1-mini). The words are an
--   application instruction (documents to send), they name no qualification an applicant must hold, and nothing in the evidence says otherwise.
-- D9 (Pilot #1709, held) would serve a prior_qualification or minimum_grade row for all students as course_general. Its safeguards exclude duration, pathway
--   and possible-route wording only, so this row would have been served as a requirement unless it is corrected first.
-- Fix (both live on deploy; worker v1.0.54 entryDocumentInstruction for new reads, this migration for admitted rows): an active prior_qualification or
--   minimum_grade row with no score and no grade whose words are a document-submission instruction (certified copies, transcripts or documents; submit,
--   upload, attach, send or lodge an application, form, document, transcript or copy) and that names no qualification level (Year 10 to 12, certificate III
--   or IV, diploma, bachelor, degree, AQF, honours, master, doctorate, equivalent) becomes kind general_note. Quote, description, audience and source stay;
--   provenance keeps the earlier kind; every id is logged. Manually locked courses are left unchanged. "Submit a copy of minimum Year 12 or equivalent"
--   (113935B, 119104D) names a level and is left as read.
-- Recorded: one row in pipeline.integration_issues (code defect, deployed).
-- G1: no job. G2: no setting. G3: no consumer object changed (checked); the consumer reads take the corrected rows. Locks unchanged. Nothing dropped
-- or deleted.
-- Replaces: the prior_qualification or minimum_grade kind of the application-instruction rows. Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the row updates

create temp table s1293_guard on commit drop as select (select count(*) from pipeline.manual_locks) as locks_before;
create temp table s1293_cron on commit drop as select jobid from cron.job;  -- the job ids: this change creates none

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $g$;

create temp table s1293_rows on commit drop as
select e.id, e.course_id, e.kind
  from catalogue.course_entry_requirements e
 where e.status = 'active' and e.kind in ('prior_qualification', 'minimum_grade')
   and e.min_entry_score is null and nullif(btrim(coalesce(e.min_grade, '')), '') is null
   and (coalesce(e.description, '') || ' ' || coalesce(e.quote, '')) ~* '(\mcertified (copy|copies|transcripts?|documents?)\M|\m(submit|upload|attach|send|lodge)\M[^.]{0,50}\m(application|form|documents?|transcripts?|copies|copy|certified)\M)'
   and (coalesce(e.description, '') || ' ' || coalesce(e.quote, '')) !~* '\m(year\s*(10|11|12)|certificate\s*(iii|iv|3|4)|diploma|bachelor|degree|aqf|honours|masters?|doctorate|equivalent)\M'
   and not exists (select 1 from pipeline.manual_locks l
                    where l.entity = 'course' and l.entity_id = e.course_id
                      and (l.field = 'all' or coalesce(security.toolset_setting('pipeline', 'aer.schedule_lock_fields'), '[]'::jsonb) ? l.field));

do $a$
declare v_n int; v_reason constant text := 'CF-247 s1293: a document-submission instruction is an application instruction, not a qualification or a grade (SS-Programme-Control 27 Nov 2026 09:57 AEDT)';
begin
  update catalogue.course_entry_requirements e
     set kind = 'general_note', updated_at = now(),
         provenance = coalesce(e.provenance, '{}'::jsonb) || jsonb_build_object('document_instruction', jsonb_build_object('kind', r.kind, 'by', 'CF-247 s1293', 'at', now()))
    from s1293_rows r
   where e.id = r.id;
  get diagnostics v_n = row_count;
  if v_n < 1 or v_n > 20 then raise exception 'guard: % rows matched (expected 1 to 20); nothing is changed', v_n; end if;  -- fixed: a sanity bound on this correction
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('aer', 'document_instruction_not_requirement', 'catalogue.course_entry_requirements', jsonb_build_object('reason', v_reason, 'rows', v_n,
          'courses', (select count(distinct course_id) from s1293_rows), 'to', 'general_note',
          'ids', (select jsonb_agg(id order by id) from s1293_rows), 'via', 'CF-247 s1293 migration'), null);
end $a$;

insert into pipeline.integration_issues(fingerprint, title, layer, subsystem, failure, expected, detection_source, validation_layer, root_cause_class, severity,
                                        workstream, status, course_ids, evidence, fix_migration, deployed_version)
select 'aer:kind:document-instruction-read-as-requirement', 'AER course entry: a document-submission instruction admitted as a prior qualification or minimum grade', 'AER', 'aer',
       'Active rows such as 115246M "Applicants should submit certified transcripts of all academic achievements" were kind prior_qualification; D9 course_general would have served them as a requirement.',
       'An instruction to send documents with an application is a general_note.',
       'S1-Build morning check 27 Nov 2026 09:55 AEDT, traced by S2-AER', 'V4', 'code_defect', 'P2',
       coalesce((select i.workstream from pipeline.integration_issues i where i.subsystem ilike '%aer%' group by 1 order by count(*) desc limit 1), 'A1'), 'deployed',
       (select array_agg(distinct course_id) from s1293_rows),
       jsonb_build_object('rows', (select count(*) from s1293_rows), 'cause', 'course-entry-v1 filed an application instruction as a qualification', 'fix', 'worker v1.0.54 entryDocumentInstruction; migration s1293'),
       '20261130110000', 'coverage-sweep-worker-v1.0.54'
 where not exists (select 1 from pipeline.integration_issues where fingerprint = 'aer:kind:document-instruction-read-as-requirement');

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1293_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1293_guard) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select 1 from catalogue.course_entry_requirements e join s1293_rows r on r.id = e.id where e.kind <> 'general_note' or e.status <> 'active') then
    raise exception 'post-check: a corrected row is not an active general_note';
  end if;
end $c$;
