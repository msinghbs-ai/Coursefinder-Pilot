-- CF-247 AER programme batch (Platform Admin decision 29 Oct 2026 09:57, items 2 and 3: "approved as one bounded programme batch";
-- "course-level AER widening — approved for the existing provider scope"). Runs after v2.15.364 (migrations 20261029020000 and
-- 20261029030000) is live, through the same mechanisms as the workspace buttons; no SQL approval, nothing admitted.
-- 1. The ten named sources, one governed attempt each, through security.aer_reread_v1 (Catalogue › Entry requirements › Read again):
--    Western Sydney (PDF), UWA, Federation, Victoria University, Manukau, Wollongong: read again with the current reader (worker v0.51.0,
--    slices six at a time, 8,000 characters); Wintec, Otago Polytechnic, Lincoln, NMIT: fetched again as HTML (their markdown copies stay
--    as evidence). Earlier partial reads are superseded, never approved (Federation and Western Sydney stay unapproved until a complete
--    replacement read passes its source-anchored checks in Layer 4). A source the mechanism refuses is recorded with its reason and not retried.
-- 2. The first bounded course-level batch through security.course_entry_batch_v1 (entry.course_batch_size courses, next by priority: Monash),
--    within the AI limits and above the OpenRouter credit floor; every course read goes to Layer 4.
-- Actor: the Platform Admin (as for the decided BH126 read, 20261028001000). Count-guarded: exactly ten sources, at most one batch.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

do $$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- the Platform Admin (decision 29 Oct 2026 09:57)
        v_reason constant text := 'AER programme batch (Platform Admin decision 29 Oct 2026 09:57 item 2): one governed attempt with the current reader';
        v_ids uuid[]; r record; v_res jsonb; v_out jsonb := '[]'::jsonb; v_batch jsonb;
begin
  select array_agg(s.id) into v_ids from pipeline.entry_matrix_sources s
   where s.url in ('https://www.westernsydney.edu.au/content/dam/digital/pdf/international/INTL0910_Entry_Qualifications_v07.pdf',
                   'https://www.uwa.edu.au/study/how-to-apply/pathways-and-eligibility/international-and-overseas-qualifications',
                   'https://www.federation.edu.au/siteassets/files/apply/how-to-apply/international-students/academic-entry-requirements-by-country-guide2.pdf',
                   'https://www.vu.edu.au/sites/default/files/documents/2026-09/academic-entry-requirements-listed-by-country.pdf',
                   'https://www.manukau.ac.nz/study/international-students/how-to-apply/entry-requirements-academic/',
                   'https://www.uow.edu.au/study/international/representatives/international-entry-requirements/',
                   'https://www.wintec.ac.nz/international/international-academic-entry-requirements',
                   'https://www.op.ac.nz/international/apply-and-enrol/entry-requirements',
                   'https://www.lincoln.ac.nz/study/apply-and-enrol/international-undergraduate-entry-criteria/',
                   'https://www.nmit.ac.nz/international/entry-requirements');
  if coalesce(array_length(v_ids, 1), 0) <> 10 then raise exception 'expected exactly the ten named sources, found %', coalesce(array_length(v_ids, 1), 0); end if;
  for r in select s.id, s.url from pipeline.entry_matrix_sources s where s.id = any (v_ids) order by s.url loop
    begin
      v_res := security.aer_reread_v1(r.id, v_reason, v_pa);
    exception when others then
      v_res := jsonb_build_object('refused', sqlerrm);  -- recorded, not retried
    end;
    v_out := v_out || jsonb_build_array(jsonb_build_object('source', r.id, 'url', r.url, 'result', v_res));
  end loop;
  begin
    v_batch := security.course_entry_batch_v1(null, null, 'AER course-level programme, first batch (Platform Admin decision 29 Oct 2026 09:57 item 3): next by priority', v_pa, false);
  exception when others then
    v_batch := jsonb_build_object('refused', sqlerrm);
  end;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'programme_batch', 'migration 20261029040000', jsonb_build_object('rereads', v_out, 'course_batch', v_batch, 'reason', v_reason), v_pa);
end $$;
