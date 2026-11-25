-- CF-247 S3 AER / Admin #1054, 25 Nov 2026.
-- Replaces: nothing. Extends existing source/reader pipeline only.
-- Retires: nothing. Preserves existing readers, locks and queues.
-- Existing stored course page extraction, NO new runner, cron, queue, model or
-- admission control. Default aer-det-v1.4 unattended sweep remains untouched.
-- Extra v1.5 rules are opt-in ONLY by manual workflow provider batch (<=15).
-- S2-AER continues owning qualification/identity and admission. S1-Build only
-- Integration Controller authorised to rehearse and release this shared change.
--
-- Evidence 1: North Island College Nursing BSN, course
-- fb977de2-3818-5b86-bc94-41c01da6a509, stored evidence
-- 51a36319-8c9e-4257-8c47-12ce9c14e233; phrase printed in existing
-- aer_det_academic_pages.uncovered "academic requirements: Grade 12 or equivalent".
-- This course has zero active course-entry rows. The v1.5 reader captures the
-- qualitative prior qualification without inventing a percentage or treating
-- domestic/unspecified requirements as international eligibility.
-- Evidence 2: Toi Ohomai L5 Business Management, evidence
-- da4cbcb3-147d-4430-8eee-e5e6184472d2, printed total 48 credits in NCEA
-- Level 2; ALREADY CANONICAL ACTIVE. Used only as duplicate-protection fixture.
-- Unchanged source/quote/edition/L4/locks and consumer API gates decide.
--
-- Rebased on live proposer MD5 from s119x; unchanged existing admission and
-- v1.24 preprocessing code is preserved by the exact-body guard.
-- Shared recorder and proposer accept both v1.4 global and v1.5 scoped stored
-- readings. New reading keys are accepted by recorder ONLY when the extractor
-- is v1.5. Only v1.5 is eligible from the bounded manual workflow; sweeping
-- v1.4 across the remaining platform continues as before. No 12,604-page replay.
set local lock_timeout='5s';
set local statement_timeout='120s';

do $s3$
declare
  v_before jsonb := security.consumer_api_check_v1();
  v_locks int := (select count(*) from pipeline.manual_locks);
  v_f text; v_old text; v_new text;
begin
  if (v_before->>'functions')::int <> 75 or (v_before->>'relations')::int <> 48
     or jsonb_array_length(coalesce(v_before->'drift','[]'::jsonb)) <> 0 then
    raise exception 'S3 AER G3 frozen surface drift: %',v_before;
  end if;
  if (select count(*) from cron.job where active)>140 then
    raise exception 'S3 AER active cron ceiling exceeded';
  end if;
  -- Read and assert the existing unattended sweep; DO NOT EDIT ITS BODY.
  if md5(pg_get_functiondef('security.aer_det_sweep_v1()'::regprocedure))
      <> '6ff2467906e17f76baa8032f392c99e3' then
    raise exception 'S3 AER shared default sweep changed; coordinate with S1-Build';
  end if;
  v_f := pg_get_functiondef('security.aer_det_propose_v1()'::regprocedure);
  if md5(v_f) <> '330e281bf013eb6094b6e8932ef73af9' then
    raise exception 'S3 AER proposer body changed; coordinate shared integrator rebase';
  end if;

  -- Extend only the existing deterministic recording function, not a new
  -- writer. Without this step it silently drops the new v1.5 academic keys.
  -- Both historical v1.4 accept-list expressions are left identical for
  -- ordinary unattended reads. New keys work only for the opt-in version.
  v_f := pg_get_functiondef('security.aer_det_record_v2(jsonb)'::regprocedure);
  if md5(v_f) <> '6d854e35cea21e8227664a4793b20a2a' then
    raise exception 'S3 AER recorder body changed; obtain integrator rebase';
  end if;
  v_old := $o$count(*) from jsonb_array_elements(coalesce(p->'readings', '[]'::jsonb)) x where x->>'key' in ('atar','year12','ncea_l3','university_entrance','ib','alevel','india_board','ca_secondary','bachelor_gpa')$o$;
  v_new := $n$count(*) from jsonb_array_elements(coalesce(p->'readings', '[]'::jsonb)) x where
              (x->>'key' in ('atar','year12','ncea_l3','university_entrance','ib','alevel','india_board','ca_secondary','bachelor_gpa')
                or (p->>'extractor'='aer-det-v1.5' and x->>'key' in ('ncea_l2','ca_secondary_completion')))$n$;
  if (length(v_f)-length(replace(v_f,v_old,'')))/length(v_old) <> 1 then
    raise exception 'S3 AER recorder page-count anchor changed';
  end if;
  v_f := replace(v_f,v_old,v_new);
  v_old := $o$continue when r->>'key' not in ('atar','year12','ncea_l3','university_entrance','ib','alevel','india_board','ca_secondary','bachelor_gpa');$o$;
  v_new := $n$continue when not (r->>'key' in ('atar','year12','ncea_l3','university_entrance','ib','alevel','india_board','ca_secondary','bachelor_gpa')
                  or (p->>'extractor'='aer-det-v1.5' and r->>'key' in ('ncea_l2','ca_secondary_completion')));$n$;
  if (length(v_f)-length(replace(v_f,v_old,'')))/length(v_old) <> 1 then
    raise exception 'S3 AER recorder reading key anchor changed';
  end if;
  execute replace(v_f,v_old,v_new);

  -- Reset the edit buffer to the EXISTING proposer definition: the preceding
  -- change was for the recorder, which must never be edited as a proposer.
  v_f := pg_get_functiondef('security.aer_det_propose_v1()'::regprocedure);
  if md5(v_f) <> '330e281bf013eb6094b6e8932ef73af9' then
    raise exception 'S3 AER proposer changed before release; request S1-Build rebase';
  end if;

  -- Keep v1.4 default; switch only the current source-backed record's
  -- extractor inside the existing proposal loop. No second proposer.
  v_old := $o$  v_ext constant text := 'aer-det-v1.4';$o$;
  v_new := $n$  v_ext text := 'aer-det-v1.4';$n$;
  if (length(v_f)-length(replace(v_f,v_old,'')))/length(v_old) <> 1 then
    raise exception 'S3 AER proposer extractor declaration not unique';
  end if;
  v_f := replace(v_f,v_old,v_new);

  v_old := $o$select a.course_id, a.evidence_id, a.uncovered, c.provider_id
              from pipeline.aer_det_academic_pages a join catalogue.courses c on c.id = a.course_id and c.lifecycle_status = 'active'
             where a.extractor = v_ext and a.readings > 0 and a.outcome is null order by a.read_at loop$o$;
  v_new := $n$select a.course_id, a.evidence_id, a.uncovered, c.provider_id, a.extractor as reading_extractor
              from pipeline.aer_det_academic_pages a join catalogue.courses c on c.id = a.course_id and c.lifecycle_status = 'active'
             where a.extractor in ('aer-det-v1.4','aer-det-v1.5') and a.readings > 0 and a.outcome is null order by a.read_at loop$n$;
  if (length(v_f)-length(replace(v_f,v_old,'')))/length(v_old) <> 1 then
    raise exception 'S3 AER proposer stored reading iterator changed';
  end if;
  v_f := replace(v_f,v_old,v_new);
  v_old := 'exit when v_done >= v_room;';
  v_new := $n$exit when v_done >= v_room;
    v_ext := pg.reading_extractor;$n$;
  if (length(v_f)-length(replace(v_f,v_old,'')))/length(v_old) <> 1 then
    raise exception 'S3 AER proposer per-reading scope anchor changed';
  end if;
  v_f := replace(v_f,v_old,v_new);

  -- Exact NCEA Level 2 total-credit number, never NCEA level "2" nor the
  -- subject-specific 12 credits included in the same sentence.
  v_old := $o$elsif rd.test_key = 'ncea_l3' then v_kind := 'prior_qualification'; v_score := (rd.value->>'credits')::numeric; v_basis := 'credits'; v_desc := 'NCEA Level 3 with ' || (rd.value->>'credits') || ' credits';$o$;
  v_new := $n$elsif rd.test_key = 'ncea_l2' then v_kind := 'prior_qualification'; v_score := (rd.value->>'credits')::numeric; v_basis := 'credits'; v_desc := 'NCEA Level 2 with ' || (rd.value->>'credits') || ' credits';
        elsif rd.test_key = 'ncea_l3' then v_kind := 'prior_qualification'; v_score := (rd.value->>'credits')::numeric; v_basis := 'credits'; v_desc := 'NCEA Level 3 with ' || (rd.value->>'credits') || ' credits';$n$;
  if (length(v_f)-length(replace(v_f,v_old,'')))/length(v_old) <> 1 then
    raise exception 'S3 AER proposer NCEA mapping changed';
  end if;
  v_f := replace(v_f,v_old,v_new);

  -- Explicit academic Grade 12 completion without a number: qualitative only,
  -- and ONLY for CA provider pages; other countries' routes remain unchanged.
  v_old := $o$elsif rd.test_key = 'ca_secondary' then v_score := (rd.value->>'average_percent')::numeric; v_basis := case when lower(v_q) like '%per cent%' then 'per cent' else '%' end; v_desc := 'Secondary school average of ' || (rd.value->>'average_percent') || ' per cent';$o$;
  v_new := $n$elsif rd.test_key = 'ca_secondary_completion' then v_kind := 'prior_qualification'; v_grade := 'Grade 12 or equivalent'; v_desc := 'Grade 12 or equivalent';
        elsif rd.test_key = 'ca_secondary' then v_score := (rd.value->>'average_percent')::numeric; v_basis := case when lower(v_q) like '%per cent%' then 'per cent' else '%' end; v_desc := 'Secondary school average of ' || (rd.value->>'average_percent') || ' per cent';$n$;
  if (length(v_f)-length(replace(v_f,v_old,'')))/length(v_old) <> 1 then
    raise exception 'S3 AER proposer Canadian mapping changed';
  end if;
  v_f := replace(v_f,v_old,v_new);
  v_old := $o$if rd.test_key = 'atar' then$o$;
  v_new := $n$if rd.test_key = 'ca_secondary_completion' and v_cc is distinct from 'CA' then continue; end if;
        if rd.test_key = 'atar' then$n$;
  if (length(v_f)-length(replace(v_f,v_old,'')))/length(v_old) <> 1 then
    raise exception 'S3 AER CA-only mapping scope changed';
  end if;
  v_f := replace(v_f,v_old,v_new);
  v_old := 'v_conf := case rd.strength';
  v_new := $n$if rd.test_key = 'ca_secondary_completion' and v_aud = 'all' then v_aud := 'domestic'; end if;
        v_conf := case rd.strength$n$;
  if (length(v_f)-length(replace(v_f,v_old,'')))/length(v_old) <> 1 then
    raise exception 'S3 AER conservative audience anchor changed';
  end if;
  v_f := replace(v_f,v_old,v_new);

  execute v_f;
  if (select count(*) from pipeline.manual_locks) <> v_locks then
    raise exception 'S3 AER manual locks changed inside migration';
  end if;
  if (security.consumer_api_check_v1()->>'functions')::int <> 75
     or (security.consumer_api_check_v1()->>'relations')::int <> 48
     or jsonb_array_length(coalesce(security.consumer_api_check_v1()->'drift','[]'::jsonb)) <> 0 then
    raise exception 'S3 AER G3 post-check failed';
  end if;
end $s3$;
